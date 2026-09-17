import Foundation
import AgentFiles
import SessionHealthCore

/// When the agent is waiting on the person rather than the other way round — the state the
/// pause sign rests on.
///
/// Read from a source of its own, and that is the whole point of these cases. A question to the
/// person is written into the transcript as a tool call with no result yet, which is exactly
/// what a tool that is still running looks like: the transcript cannot tell them apart and the
/// record of the running process can. So every case here is about the join of the two — what
/// the record is allowed to override, and what it must not be allowed to claim.
func runAskingStateTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = fixtureNow

    /// A turn in which the agent has called a tool and no result has come back — on disk, the
    /// only shape a question to the person takes. Without a record it reads as an agent at
    /// work, which is what these cases put the record against.
    let askedTurn = [
        userPrompt("do the thing"),
        assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["tool_use"])
    ]

    /// The same turn finished: the agent answered and nobody owes anybody anything.
    let finishedTurn = askedTurn + [
        toolResult(),
        assistant(input: 1, cacheCreation: 0, cacheRead: 60_000, stopReason: "end_turn", blocks: ["text"])
    ]

    /// One pass of the joined reader over a transcript and a set of records, each in a
    /// directory of its own — the same two sources the app reads, named by path rather than by
    /// standing in for a home directory.
    func pass(
        _ root: URL,
        _ name: String,
        transcript: [String],
        records: [String],
        transcriptModified: Date = fixtureNow,
        now: Date = fixtureNow
    ) -> SessionSnapshot? {
        let projects = makeProjectDirectory(root, name, suite)
        writeTranscript(transcript, to: projects, named: "abc.jsonl", modified: transcriptModified, suite)
        let directory = makeDirectory(root, "\(name)-records", suite)
        for (index, record) in records.enumerated() {
            writeSessionRecord(record, to: directory, named: "\(index).json", modified: now, suite)
        }
        let reading = UsageReader(
            claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: projects),
            claudeStatus: ClaudeStatusStore(directory: root.appendingPathComponent("no-status")),
            claudeSessionRecords: ClaudeSessionRecordStore(directory: directory),
            codexRollouts: CodexRolloutStore(sessionsDirectory: root.appendingPathComponent("no-codex"))
        ).read(config: config, now: now)
        guard let found = reading.claudeSessions.value?.first(where: { !$0.isSubagent }) else {
            suite.expect(false, "expected a session, got \(reading.claudeSessions)")
            return nil
        }
        return found
    }

    withTemporaryDirectory(suite, named: "claude-asking") { root in
        // MARK: What the record says

        suite.test("a record that says waiting is the agent asking, from the moment it asked") {
            let askedAt = now.addingTimeInterval(-90)
            guard let snapshot = pass(
                root, "asked",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: askedAt)]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .asking(since: askedAt), "asking, dated by the record")
            suite.expect(!snapshot.replyWait.isOwed, "and the agent owes nothing: the next move is the person's")
        }

        // The same transcript, unchanged, read twice: once with the record saying the agent is
        // asking and once with it saying the agent is working. Nothing in the file itself
        // separates the two, which is why this source exists at all.
        suite.test("the same transcript without the record is an agent at work") {
            guard let snapshot = pass(
                root, "no-record",
                transcript: askedTurn,
                records: []
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "the behaviour of the release before this one")
        }

        // The other half of the request, and the other file it comes from: the record says the
        // person is being waited on, and only the transcript says what about.
        suite.test("what was asked is read from the transcript, beside the record's verdict") {
            let askedTurn = [
                userPrompt("do the thing"),
                assistant(
                    input: 1, cacheCreation: 0, cacheRead: 40_000,
                    stopReason: "tool_use", blocks: ["thinking", "tool_use"],
                    asking: "Which approach should I take?"
                )
            ]
            guard let snapshot = pass(
                root, "asked-about",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.request, "Which approach should I take?", "the question")
            suite.expectEqual(snapshot.replyWait, .asking(since: now), "and the state it belongs to")
        }

        // The rule is the name of one tool, which is the vendor's to change. What a renamed
        // tool costs is the wording of a notification and nothing else.
        suite.test("a tool call that is not a question to the person leaves nothing to say") {
            guard let snapshot = pass(
                root, "asked-nothing",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.request, nil, "a running tool is not a question")
            suite.expectEqual(snapshot.replyWait, .asking(since: now), "and the record is still believed")
        }

        // Answered, and the question with it: what is carried is the request in flight, not the
        // last one the session ever had.
        suite.test("an answered question is no longer what the session is asking") {
            let answered = [
                userPrompt("do the thing"),
                assistant(
                    input: 1, cacheCreation: 0, cacheRead: 40_000,
                    stopReason: "tool_use", blocks: ["tool_use"],
                    asking: "Which approach should I take?"
                ),
                toolResult(),
                assistant(input: 1, cacheCreation: 0, cacheRead: 60_000, stopReason: "end_turn", blocks: ["text"])
            ]
            guard let snapshot = pass(
                root, "answered-question",
                transcript: answered,
                records: [sessionRecord(pid: 501, session: "abc", status: "idle", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.request, nil, "the question the person already answered")
        }

        suite.test("a record that says busy leaves the transcript's verdict alone") {
            guard let snapshot = pass(
                root, "busy",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "busy", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "a tool is running, nobody is being asked")
        }

        // The distinction the whole feature turns on: a turn that ended asks nothing, and the
        // bar already says so by blinking and then stopping.
        suite.test("a record that says idle is the end of a turn, not a request") {
            guard let snapshot = pass(
                root, "idle",
                transcript: finishedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "idle", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .none, "nothing is owed either way")
        }

        suite.test("a status this app has never seen is not a request") {
            guard let snapshot = pass(
                root, "unknown-status",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "compacting", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "an unknown state falls back, it does not invent a sign")
        }

        // The person answered: the CLI rewrites the record in the same breath, and the sign has
        // to go in the very pass that reads it — this is the file system event that wakes the
        // app up.
        suite.test("the answer takes the sign away in the same pass") {
            let projects = makeProjectDirectory(root, "answered", suite)
            writeTranscript(askedTurn, to: projects, named: "abc.jsonl", modified: now, suite)
            let directory = makeDirectory(root, "answered-records", suite)
            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now.addingTimeInterval(-60)),
                to: directory, named: "501.json", modified: now.addingTimeInterval(-60), suite
            )
            let reader = UsageReader(
                claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: projects),
                claudeStatus: ClaudeStatusStore(directory: root.appendingPathComponent("no-status")),
                claudeSessionRecords: ClaudeSessionRecordStore(directory: directory),
                codexRollouts: CodexRolloutStore(sessionsDirectory: root.appendingPathComponent("no-codex"))
            )
            suite.expect(
                reader.read(config: config, now: now).claudeSessions.value?.first?.replyWait.isAsking == true,
                "asking while the record says so"
            )

            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "busy", statusUpdatedAt: now),
                to: directory, named: "501.json", modified: now, suite
            )
            suite.expectEqual(
                reader.read(config: config, now: now).claudeSessions.value?.first?.replyWait, .waiting,
                "and back to the transcript's verdict the moment the record moves"
            )
        }

        // MARK: What a record left behind may not do

        suite.test("a record for another session draws nothing here") {
            guard let snapshot = pass(
                root, "other-session",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "somebody-else", status: "waiting", statusUpdatedAt: now)]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "no state borrowed from another session's record")
        }

        // A process that was killed leaves its last state on disk. Nothing rewrites a record
        // while the person is away, so a stale one is exactly what a dead process looks like,
        // and the sign it would draw has no end.
        suite.test("a record of a process that is gone stops drawing the sign") {
            let stale = now.addingTimeInterval(-config.sessionActivity.seconds - 60)
            guard let snapshot = pass(
                root, "dead-process",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: stale)]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "a record older than the activity window is not read")
        }

        // `claude --resume` runs the same session in a new process, and the old process's
        // record stays behind frozen at whatever it last said.
        suite.test("a session resumed in a new process is told by the newest of its records") {
            guard let snapshot = pass(
                root, "resumed",
                transcript: askedTurn,
                records: [
                    sessionRecord(
                        pid: 501, session: "abc", status: "waiting",
                        statusUpdatedAt: now.addingTimeInterval(-600)
                    ),
                    sessionRecord(pid: 777, session: "abc", status: "busy", statusUpdatedAt: now)
                ]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "the frozen record does not outvote the live one")
        }

        suite.test("the newest record is read whichever order the walk found them in") {
            guard let snapshot = pass(
                root, "resumed-other-way",
                transcript: askedTurn,
                records: [
                    sessionRecord(pid: 777, session: "abc", status: "busy", statusUpdatedAt: now.addingTimeInterval(-600)),
                    sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now)
                ]
            ) else { return }
            suite.expect(snapshot.replyWait.isAsking, "the live record is the one that says waiting")
        }

        suite.test("a record that is not JSON at all leaves the session as the transcript read it") {
            guard let snapshot = pass(
                root, "broken-record",
                transcript: askedTurn,
                records: ["not json, and never was"]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "an unreadable record decides nothing")
        }

        suite.test("a record with no moment in it decides nothing") {
            guard let snapshot = pass(
                root, "undated-record",
                transcript: askedTurn,
                records: [#"{"pid":501,"sessionId":"abc","status":"waiting"}"#]
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .waiting, "a request that cannot be dated cannot be aged out")
        }

        // MARK: The fuse, the blink and the subagents, as they were

        // The fuse is about an answer that is not coming. A request is not owed an answer by
        // anybody but the person, and a person who has not come back for an hour has not
        // stalled — they are out of the room.
        suite.test("a request older than the fuse is still a request, not a stall") {
            let askedAt = now.addingTimeInterval(-config.abandonedWait.seconds - 600)
            guard let snapshot = pass(
                root, "long-request",
                transcript: askedTurn,
                records: [sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: askedAt)],
                // The transcript is untouched while the person is away; only the row's own
                // activity window decides how long it is shown, and that is unchanged.
                transcriptModified: now.addingTimeInterval(-60)
            ) else { return }
            suite.expectEqual(snapshot.replyWait, .asking(since: askedAt), "the pause sign stays a pause sign")
        }

        // The other three states are what the light did before this, and they are meant to be
        // exactly what they were: the request stands beside them as a third thing, not over
        // them.
        suite.test("the blink and the figure eight are untouched by any of this") {
            let long = now.addingTimeInterval(-config.abandonedWait.seconds - 60)
            guard let working = pass(root, "still-working", transcript: askedTurn, records: []) else { return }
            suite.expectEqual(working.replyWait, .waiting, "an agent at work still blinks")

            guard let stalled = pass(
                root, "still-stalled",
                transcript: [
                    userPrompt("do the thing", at: long),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: long
                    )
                ],
                records: [],
                transcriptModified: now.addingTimeInterval(-60)
            ) else { return }
            suite.expectEqual(stalled.replyWait, .stalled, "a long silence is still a figure eight")

            guard let done = pass(root, "still-done", transcript: finishedTurn, records: []) else { return }
            suite.expectEqual(done.replyWait, .none, "and a finished turn is still a plain dot")
        }

        // A subagent has no process and no record of its own. The only way one could be marked
        // is a record naming it, which would mean the panel drew a request nobody made.
        suite.test("a subagent is never the one asking, whatever a record says") {
            let projects = makeProjectDirectory(root, "subagent", suite)
            writeTranscript(askedTurn, to: projects, named: "abc.jsonl", modified: now, suite)
            writeSubagentTranscript(
                [
                    userPrompt("look into it", sidechain: true),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 20_000,
                        sidechain: true, stopReason: "tool_use", blocks: ["tool_use"]
                    )
                ],
                to: projects, session: "abc", named: "agent-1.jsonl", modified: now, suite
            )
            let directory = makeDirectory(root, "subagent-records", suite)
            writeSessionRecord(
                sessionRecord(pid: 501, session: "agent-1", status: "waiting", statusUpdatedAt: now),
                to: directory, named: "501.json", modified: now, suite
            )
            let sessions = UsageReader(
                claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: projects),
                claudeStatus: ClaudeStatusStore(directory: root.appendingPathComponent("no-status")),
                claudeSessionRecords: ClaudeSessionRecordStore(directory: directory),
                codexRollouts: CodexRolloutStore(sessionsDirectory: root.appendingPathComponent("no-codex"))
            ).read(config: config, now: now).claudeSessions.value ?? []

            guard let agent = sessions.first(where: { $0.isSubagent }) else {
                suite.expect(false, "expected the subagent to be listed")
                return
            }
            suite.expectEqual(agent.replyWait, .waiting, "an agent works; it asks nothing of anybody")
        }

        // MARK: What the sign is drawn in

        // Shape carries the state and colour goes on carrying the budget, which only works if
        // the numbers behind a session being asked about are judged exactly as they were.
        suite.test("a session that is asking is still judged by its numbers, ceiling included") {
            let rules = BudgetRules(config: config)
            func assess(_ wait: ReplyWait, tokens: Int) -> BudgetLevel {
                rules.assess(
                    SessionSnapshot(
                        sessionID: "asking",
                        service: .claude,
                        contextTokens: tokens,
                        contextWindowTokens: 200_000,
                        replyWait: wait
                    )
                ).level
            }
            let full = 199_000
            let asking = ReplyWait.asking(since: now)
            suite.expectEqual(assess(asking, tokens: full), assess(.none, tokens: full), "at the ceiling")
            suite.expectEqual(assess(asking, tokens: full), .high, "and the ceiling is red")
            suite.expectEqual(assess(asking, tokens: 1_000), assess(.none, tokens: 1_000), "well under it")
        }
    }

    // MARK: What a pass costs

    withTemporaryDirectory(suite, named: "record-memory") { root in
        // The records are small, but they are read on every one of the dozens of events a turn
        // makes, and the point of the memory is that "small" never gets multiplied by that.
        suite.test("a record that has not changed is not read again") {
            let directory = makeDirectory(root, "unchanged", suite)
            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now),
                to: directory, named: "501.json", modified: now, suite
            )
            let store = ClaudeSessionRecordStore(directory: directory)
            suite.expect(store.read().first?.isAsking == true, "the first pass reads the record")

            withoutPermissions(everyFile(under: directory), suite) {
                suite.expect(
                    store.read().first?.isAsking == true,
                    "the second pass answers without opening it"
                )
                suite.expect(
                    ClaudeSessionRecordStore(directory: directory).read().isEmpty,
                    "control: a reader with no memory of it gets nothing out of that file"
                )
            }
        }

        suite.test("a record the CLI wrote again is read again") {
            let directory = makeDirectory(root, "rewritten", suite)
            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "busy", statusUpdatedAt: now.addingTimeInterval(-60)),
                to: directory, named: "501.json", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeSessionRecordStore(directory: directory)
            suite.expect(store.read().first?.isAsking == false, "busy on the first pass")

            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now),
                to: directory, named: "501.json", modified: now, suite
            )
            suite.expect(store.read().first?.isAsking == true, "and asking as soon as it says so")
        }

        // The directory holds a key file per session beside the records, and it is none of this
        // app's business: opening one would be a read of something nobody asked for.
        suite.test("only the records are read, not everything in the directory") {
            let directory = makeDirectory(root, "keys-too", suite)
            writeSessionRecord(
                sessionRecord(pid: 501, session: "abc", status: "waiting", statusUpdatedAt: now),
                to: directory, named: "501.json", modified: now, suite
            )
            let key = directory.appendingPathComponent("501.abcdef.key")
            try? Data("not for us".utf8).write(to: key)

            withoutPermissions([key], suite) {
                let records = ClaudeSessionRecordStore(directory: directory).read()
                suite.expectEqual(records.count, 1, "the record, and nothing else in the directory")
                suite.expectEqual(records.first?.sessionID, "abc", "and it is the one that was asked for")
            }
        }

        // A machine whose Claude Code does not write these, or one where nothing is running:
        // the same answer, and neither is a fault.
        suite.test("no directory at all is an empty list and not a failure") {
            let nowhere = root.appendingPathComponent("never-written", isDirectory: true)
            suite.expect(
                ClaudeSessionRecordStore(directory: nowhere).read().isEmpty,
                "nothing to say, said quietly"
            )
        }
    }
}
