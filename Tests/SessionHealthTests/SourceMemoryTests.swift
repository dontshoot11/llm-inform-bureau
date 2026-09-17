import Foundation
import AgentFiles
import SessionHealthCore

/// What the other two sources remember between passes, and what a whole pass costs when
/// nothing has changed.
///
/// The transcripts are the expensive source and have their cases of their own
/// (`TranscriptMemoryTests`). These are about the other two — the payloads the status line
/// leaves and the rollouts Codex writes — and about the pass as a whole: a turn is dozens of
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
            let rollouts = makeRolloutDirectory(root, "codex", suite)
            write(
                lines: rollout, to: rollouts, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now.addingTimeInterval(-60), suite
            )

            let reader = UsageReader(
                claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: projects),
                claudeStatus: ClaudeStatusStore(directory: payloads),
                codexRollouts: CodexRolloutStore(sessionsDirectory: rollouts)
            )
            let first = reader.read(config: config, now: now)
            suite.expectEqual(first.claudeSessions.value?.count, 1, "the first pass reads a Claude session")
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
                    codexRollouts: CodexRolloutStore(sessionsDirectory: rollouts)
                ).read(config: config, now: now)
                suite.expect(control != first, "control: a reader with no memory of these files cannot answer")
            }
        }
    }
}
