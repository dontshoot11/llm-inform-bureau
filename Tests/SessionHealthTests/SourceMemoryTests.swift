import Foundation
import AgentFiles
import SessionHealthCore

/// What the other sources remember between passes, and what a whole pass costs when nothing
/// has changed.
///
/// The transcripts are the expensive source and have their cases of their own
/// (`TranscriptMemoryTests`), and the records of the running processes have theirs
/// (`AskingStateTests`). These are about the payloads the status line leaves and the rollouts
/// Codex writes — and about the pass as a whole: a turn is dozens of
/// file system events, almost all of them about a file that has already been read, and the one
/// thing such an event must not cost is a single file being opened.
///
/// How "not opened" is checked rather than assumed, and what keeps the check honest, is with
/// `withoutPermissions`.
func runSourceMemoryTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = fixtureNow

    // MARK: The payloads the status line leaves

    withTemporaryDirectory(suite, named: "status-memory") { root in
        suite.test("a payload that has not changed is not read again") {
            let directory = makeDirectory(root, "unchanged", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 23.5, sevenDay: 41.2),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeStatusStore(directory: directory)
            suite.expectClose(
                store.read().limits.value?.window(.short)?.usedPercent, 23.5,
                "the first pass reads the payload"
            )

            withoutPermissions(everyFile(under: directory), suite) {
                let second = store.read()
                suite.expectClose(
                    second.limits.value?.window(.short)?.usedPercent, 23.5,
                    "the second pass answers without opening it"
                )
                suite.expectEqual(
                    second.payloads.first?.contextWindowTokens, 200_000,
                    "and still knows the size of the window"
                )
                suite.expect(
                    ClaudeStatusStore(directory: directory).read().limits.value == nil,
                    "control: a reader with no memory of it gets nothing out of that file"
                )
            }
        }

        // The status line rewrites a session's payload in place on every answer, so this is the
        // ordinary case rather than an edge of one: the file is the same file, and everything
        // in it is new.
        suite.test("a payload the status line wrote again is read again") {
            let directory = makeDirectory(root, "rewritten", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 23.5, sevenDay: 41.2, contextTokens: 15_500),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeStatusStore(directory: directory)
            suite.expectClose(store.read().limits.value?.window(.short)?.usedPercent, 23.5, "the first pass")

            writeStatus(
                payload(session: "s1", fiveHour: 44, sevenDay: 41.2, contextTokens: 61_000),
                to: directory, named: "s1.json", modified: now, suite
            )
            let second = store.read()
            suite.expectClose(
                second.limits.value?.window(.short)?.usedPercent, 44,
                "what the new payload says, not what the old one said"
            )
            suite.expectEqual(second.payloads.first?.contextTokens, 61_000, "and its new context")
        }

        // The app asks the status line two questions, and they used to be two walks of the
        // directory and two JSON parses of every payload in it, per pass.
        suite.test("one walk answers both the limits and the window sizes") {
            let directory = makeDirectory(root, "one-walk", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 23.5, sevenDay: 41.2, windowSize: 1_000_000),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-60), suite
            )
            writeStatus(
                payload(session: "s2", fiveHour: nil, sevenDay: nil, windowSize: 200_000),
                to: directory, named: "s2.json", modified: now.addingTimeInterval(-120), suite
            )

            let reading = ClaudeStatusStore(directory: directory).read()
            suite.expectClose(
                reading.limits.value?.window(.short)?.usedPercent, 23.5,
                "the limits, out of the newest payload that carries them"
            )
            suite.expectEqual(reading.payloads.count, 2, "and every payload's window size, from the same walk")
        }

        // A file that would not open is not a file that would not parse. The first is a moment;
        // the second is this app failing to read back what it wrote, and the panel says so in
        // those words. Calling the first the second would be wrong twice over — wrong now, and
        // wrong for as long as the file stands still, because what a pass decides about a file
        // is what the next pass is told.
        suite.test("a payload that could not be opened is not remembered as unreadable") {
            let directory = makeDirectory(root, "unopenable", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 23.5, sevenDay: 41.2),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeStatusStore(directory: directory)

            withoutPermissions(directory.appendingPathComponent("s1.json"), suite) {
                let reading = store.read()
                suite.expect(reading.limits.value == nil, "nothing to report while the file will not open")
                suite.expect(
                    reading.limits.explanation?.english.contains("format") != true,
                    "and no verdict on a format this pass never saw"
                )
            }
            suite.expectClose(
                store.read().limits.value?.window(.short)?.usedPercent, 23.5,
                "and the pass after it reads the file, rather than repeating what it failed to hear"
            )
        }
    }

    // MARK: The rollouts Codex writes

    let rollout = [
        sessionMeta(),
        limitsLine(primary: 52, secondary: 8, at: "2026-09-12T17:32:38.307Z"),
        taskStarted(),
        tokenCount(held: 20_622, window: 258_400)
    ]

    withTemporaryDirectory(suite, named: "codex-memory") { root in
        suite.test("a rollout that has not changed is not read again") {
            let directory = makeRolloutDirectory(root, "unchanged", suite)
            write(
                lines: rollout, to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now.addingTimeInterval(-60), suite
            )
            let store = CodexRolloutStore(sessionsDirectory: directory)
            let first = store.read(activity: activity, now: now)
            suite.expectClose(first.limits.value?.window(.short)?.usedPercent, 52, "the limits of the first pass")
            suite.expectEqual(first.sessions.value?.first?.contextTokens, 20_622, "the session of the first pass")

            withoutPermissions(everyFile(under: directory), suite) {
                let second = store.read(activity: activity, now: now)
                suite.expectClose(
                    second.limits.value?.window(.short)?.usedPercent, 52,
                    "the limits again, without opening the file"
                )
                suite.expectEqual(
                    second.sessions.value?.first?.contextTokens, 20_622,
                    "the session again, without opening the file"
                )

                let control = CodexRolloutStore(sessionsDirectory: directory).read(activity: activity, now: now)
                suite.expect(control.limits.value == nil, "control: with no memory there are no limits to be had")
                suite.expect(
                    control.sessions.value?.isEmpty == true,
                    "control: with no memory there is no session to be had"
                )
            }
        }

        suite.test("a rollout that grew is read again") {
            let directory = makeRolloutDirectory(root, "grew", suite)
            let name = "rollout-2026-09-15T17-59-45-aaa.jsonl"
            write(lines: rollout, to: directory, named: name, modified: now.addingTimeInterval(-60), suite)
            let store = CodexRolloutStore(sessionsDirectory: directory)
            suite.expectEqual(
                store.read(activity: activity, now: now).sessions.value?.first?.contextTokens, 20_622,
                "the first pass"
            )

            write(
                lines: rollout + [
                    limitsLine(primary: 71, secondary: 9, at: "2026-09-12T18:00:00.000Z"),
                    tokenCount(held: 41_000, window: 258_400)
                ],
                to: directory, named: name, modified: now, suite
            )
            let second = store.read(activity: activity, now: now)
            suite.expectEqual(
                second.sessions.value?.first?.contextTokens, 41_000,
                "what the longer file says, not what the shorter one said"
            )
            suite.expectClose(second.limits.value?.window(.short)?.usedPercent, 71, "and its newer limits")
        }

        // The head of a rollout is the `session_meta` line, and that line carries the whole
        // system prompt: half a megabyte read and parsed for a session id and a working
        // directory that cannot change. So it is remembered by the file's identity alone — and
        // a file that grew is the proof, since a re-read of the head would answer with what has
        // been written into it since.
        suite.test("what the head of a rollout says is remembered, not read again") {
            let directory = makeRolloutDirectory(root, "head", suite)
            let name = "rollout-2026-09-15T17-59-45-aaa.jsonl"
            write(lines: rollout, to: directory, named: name, modified: now.addingTimeInterval(-60), suite)
            let store = CodexRolloutStore(sessionsDirectory: directory)
            let first = store.read(activity: activity, now: now).sessions.value?.first
            suite.expectEqual(first?.project, "llm-inform-bureau", "the project of the first pass")
            suite.expectEqual(first?.sessionID, "01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2", "and its session id")

            // Rewritten in place, so the file keeps its identifier: the same file, saying
            // something else about whose session it is.
            write(
                lines: [
                    sessionMeta(session: "nobody-else", cwd: "/Users/nobody/somewhere/else"),
                    limitsLine(primary: 52, secondary: 8, at: "2026-09-12T17:32:38.307Z"),
                    taskStarted(),
                    tokenCount(held: 33_000, window: 258_400)
                ],
                to: directory, named: name, modified: now, suite
            )
            let second = store.read(activity: activity, now: now).sessions.value?.first
            suite.expectEqual(second?.contextTokens, 33_000, "the tail is read again")
            suite.expectEqual(second?.project, "llm-inform-bureau", "the head is not")
            suite.expectEqual(second?.sessionID, "01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2", "nor the session id in it")
        }

        // Codex ends a session by writing the last line of its rollout, and nothing observed
        // here shortens one afterwards. The rule must not rest on that: what is remembered is
        // keyed by what the file looks like, and a file that got smaller does not look the same.
        suite.test("a rollout that got shorter is read again") {
            let directory = makeRolloutDirectory(root, "shorter", suite)
            let name = "rollout-2026-09-15T17-59-45-aaa.jsonl"
            write(
                lines: rollout + [
                    limitsLine(primary: 71, secondary: 9, at: "2026-09-12T18:00:00.000Z"),
                    tokenCount(held: 41_000, window: 258_400)
                ],
                to: directory, named: name, modified: now.addingTimeInterval(-60), suite
            )
            let store = CodexRolloutStore(sessionsDirectory: directory)
            let first = store.read(activity: activity, now: now)
            suite.expectEqual(first.sessions.value?.first?.contextTokens, 41_000, "the first pass")
            suite.expectClose(first.limits.value?.window(.short)?.usedPercent, 71, "and its limits")

            write(lines: rollout, to: directory, named: name, modified: now, suite)
            let second = store.read(activity: activity, now: now)
            suite.expectEqual(
                second.sessions.value?.first?.contextTokens, 20_622,
                "what the shorter file says, not what the longer one said"
            )
            suite.expectClose(second.limits.value?.window(.short)?.usedPercent, 52, "and the limits in it")
        }

        // Not rewritten in place but replaced: the name is the same and the file behind it is
        // another one. Same size and same date on purpose — the identifier is then the only
        // thing left to notice it by, and the head is remembered by the identifier alone, so
        // without it this session would keep answering under the name of the one before it.
        suite.test("a rollout replaced by another file under the same name is read again") {
            let directory = makeRolloutDirectory(root, "replaced", suite)
            let name = "rollout-2026-09-15T17-59-45-aaa.jsonl"
            let written = now.addingTimeInterval(-60)
            write(
                lines: [
                    sessionMeta(session: "01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2", cwd: "/Users/nobody/projects/one"),
                    limitsLine(primary: 52, secondary: 8, at: "2026-09-12T17:32:38.307Z"),
                    taskStarted(),
                    tokenCount(held: 20_622, window: 258_400)
                ],
                to: directory, named: name, modified: written, suite
            )
            let url = rolloutFile(in: directory, named: name)
            let before = facts(of: url)
            let store = CodexRolloutStore(sessionsDirectory: directory)
            let first = store.read(activity: activity, now: now).sessions.value?.first
            suite.expectEqual(first?.sessionID, "01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2", "the session of the first pass")
            suite.expectEqual(first?.project, "one", "and where it started")

            removeFile(url, suite)
            write(
                lines: [
                    sessionMeta(session: "02b1b6dc-c4af-8aa2-ae5a-f7cdd9b9e3e3", cwd: "/Users/nobody/projects/two"),
                    limitsLine(primary: 71, secondary: 9, at: "2026-09-12T17:32:38.307Z"),
                    taskStarted(),
                    tokenCount(held: 41_000, window: 258_400)
                ],
                to: directory, named: name, modified: written, suite
            )
            let after = facts(of: url)
            suite.expectEqual(after.size, before.size, "the case only means what it says at the same size")
            suite.expectEqual(after.modified, before.modified, "and at the same date")
            suite.expect(
                after.identity != nil && after.identity != before.identity,
                "and only while the volume gives the new file an identifier of its own"
            )

            let second = store.read(activity: activity, now: now)
            suite.expectEqual(
                second.sessions.value?.first?.sessionID, "02b1b6dc-c4af-8aa2-ae5a-f7cdd9b9e3e3",
                "whose session the new file is, not whose the old one was"
            )
            suite.expectEqual(second.sessions.value?.first?.project, "two", "and where that one started")
            suite.expectEqual(second.sessions.value?.first?.contextTokens, 41_000, "and what it holds")
            suite.expectClose(second.limits.value?.window(.short)?.usedPercent, 71, "and the limits in it")
        }

        // The same rule as for the payloads above and the transcripts next door: a file that
        // would not open said nothing, and nothing is not an answer to keep.
        suite.test("a rollout that could not be opened is not remembered as having nothing to say") {
            let directory = makeRolloutDirectory(root, "unopenable", suite)
            write(
                lines: rollout, to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now.addingTimeInterval(-60), suite
            )
            let store = CodexRolloutStore(sessionsDirectory: directory)

            withoutPermissions(everyFile(under: directory), suite) {
                let reading = store.read(activity: activity, now: now)
                suite.expect(reading.limits.value == nil, "nothing to report while the file will not open")
                suite.expect(reading.sessions.value?.isEmpty == true, "and no session either")
            }
            let after = store.read(activity: activity, now: now)
            suite.expectClose(
                after.limits.value?.window(.short)?.usedPercent, 52,
                "and the pass after it reads the file"
            )
            suite.expectEqual(after.sessions.value?.first?.contextTokens, 20_622, "the session too")
        }
    }

    // MARK: A whole pass

    // The case the task exists for. Dozens of events arrive over one turn of one agent, and
    // every one of them used to re-read every active file of all three sources — every
    // transcript, every payload, every rollout — whichever single file had actually moved.
    withTemporaryDirectory(suite, named: "pass-memory") { root in
        suite.test("an event that changed no file at all opens none of them") {
            let projects = makeProjectDirectory(root, "projects", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 100_000)],
                to: projects, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )
            let payloads = makeDirectory(root, "status", suite)
            writeStatus(
                payload(session: "abc", fiveHour: 23.5, sevenDay: 41.2, windowSize: 1_000_000),
                to: payloads, named: "abc.json", modified: now.addingTimeInterval(-60), suite
            )
            let records = makeDirectory(root, "sessions", suite)
            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now.addingTimeInterval(-60)),
                to: records, named: "501.json", modified: now.addingTimeInterval(-60), suite
            )
            let rollouts = makeRolloutDirectory(root, "codex", suite)
            write(
                lines: rollout, to: rollouts, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now.addingTimeInterval(-60), suite
            )

            let reader = UsageReader(
                claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: projects),
                claudeStatus: ClaudeStatusStore(directory: payloads),
                claudeSessionRecords: ClaudeSessionRecordStore(directory: records),
                codexRollouts: CodexRolloutStore(sessionsDirectory: rollouts)
            )
            let first = reader.read(config: config, now: now)
            suite.expectEqual(first.claudeSessions.value?.count, 1, "the first pass reads a Claude session")
            suite.expect(
                first.claudeSessions.value?.first?.replyWait.isAsking == true,
                "and the record that says it is asking"
            )
            suite.expectEqual(first.codexSessions.value?.count, 1, "and a Codex one")
            suite.expect(first.claudeLimits.value != nil, "and Claude's limits")
            suite.expect(first.codexLimits.value != nil, "and Codex's")

            withoutPermissions(everyFile(under: root), suite) {
                suite.expect(
                    reader.read(config: config, now: now) == first,
                    "all four readings are what they were, and not one file was opened to say so"
                )
                let control = UsageReader(
                    claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: projects),
                    claudeStatus: ClaudeStatusStore(directory: payloads),
                    claudeSessionRecords: ClaudeSessionRecordStore(directory: records),
                    codexRollouts: CodexRolloutStore(sessionsDirectory: rollouts)
                ).read(config: config, now: now)
                suite.expect(control != first, "control: a reader with no memory of these files cannot answer")
            }
        }
    }
}

// MARK: Getting at one rollout

/// Where `write(lines:to:named:)` puts a rollout: nested by date, the way Codex nests them.
private func rolloutFile(in root: URL, named name: String) -> URL {
    root.appendingPathComponent("2026/09", isDirectory: true).appendingPathComponent(name)
}
