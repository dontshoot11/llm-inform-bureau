import Foundation
import AgentFiles
import SessionHealthCore

/// What a session is waiting for — the state the blinking light and the stalled sign rest on.
///
/// Nothing in a transcript says "a request is in flight": measured, while a turn is worked on
/// nothing is written at all. So the state is read off the last thing that *was* written, and
/// these cases are the four moments of a turn plus the three things that make the reading hard —
/// the housekeeping written after an answer lands, a response arriving as several entries of
/// which the middle one is plain text, and a wait that no answer is ever coming for.
func runWaitingStateTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The one session in a directory of its own, read back.
    func session(_ root: URL, _ name: String, _ lines: [String]) -> SessionSnapshot? {
        let directory = makeProjectDirectory(root, name, suite)
        writeTranscript(lines, to: directory, named: "abc.jsonl", modified: now, suite)
        let reading = ClaudeTranscriptStore(projectsDirectory: directory)
            .activeSessions(activity: activity, now: now)
        guard let found = reading.value?.first(where: { !$0.isSubagent }) else {
            suite.expect(false, "expected a session, got \(reading)")
            return nil
        }
        return found
    }

    func expectWaiting(_ root: URL, _ name: String, _ lines: [String], _ wait: ReplyWait, _ label: String) {
        guard let snapshot = session(root, name, lines) else { return }
        suite.expectEqual(snapshot.replyWait, wait, label)
    }

    withTemporaryDirectory(suite, named: "claude-waiting") { root in
        suite.test("a question asked after the last answer is a session waiting") {
            expectWaiting(
                root, "asked",
                [
                    userPrompt("the previous thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "end_turn", blocks: ["text"]),
                    userPrompt("do the thing")
                ],
                .waiting, "waiting from the moment the question is written"
            )
        }

        // The transcript of a session that has never answered carries no `usage`, and a row
        // with no tokens on it is the one thing this app refuses to invent — unknown is never
        // zero. So the first turn of a brand-new session (and of one just cleared, which
        // starts a file of its own) has no row to blink, and gets one the moment the first
        // answer lands. Every turn after that is covered.
        suite.test("a session that has never answered has no row to blink yet") {
            let directory = makeProjectDirectory(root, "never-answered", suite)
            writeTranscript([userPrompt("do the thing")], to: directory, named: "abc.jsonl", modified: now, suite)

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value ?? []
            suite.expect(sessions.isEmpty, "nothing to report until something has been answered")
        }

        suite.test("an answer that called a tool is still waiting") {
            expectWaiting(
                root, "tool-called",
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["tool_use"])
                ],
                .waiting, "waiting while the tool runs"
            )
        }

        suite.test("a tool result is the middle of the turn, not the end of it") {
            expectWaiting(
                root, "tool-result",
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["tool_use"]),
                    toolResult()
                ],
                .waiting, "waiting after the result comes back"
            )
        }

        // The naive reading of this one: the last entry is an assistant entry carrying nothing
        // but text, so the turn looks over. It is not — `stop_reason` says the same response
        // went on to call a tool, and reading the blocks instead would break the wait in two
        // every time the agent said something before reaching for a tool.
        suite.test("text in the middle of a response does not end the turn") {
            expectWaiting(
                root, "mid-turn-text",
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["thinking"]),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["text"])
                ],
                .waiting, "waiting: the response is not over"
            )
        }

        suite.test("an answer that ended its turn is not waiting") {
            expectWaiting(
                root, "answered",
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["tool_use"]),
                    toolResult(),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 60_000, stopReason: "end_turn", blocks: ["text"])
                ],
                .none, "the answer landed"
            )
        }

        suite.test("the housekeeping after an answer is not the last thing said") {
            expectWaiting(
                root, "service-tail",
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 60_000, stopReason: "end_turn", blocks: ["text"])
                ] + serviceTail(),
                .none, "the tail carries no message and decides nothing"
            )
        }

        // Every other stop reason is the turn being over: whatever happens next waits on the
        // person, not on the agent. Counted here: seven `stop_sequence` and one `max_tokens`
        // against 32,000 entries, and a session stuck blinking on one of them would blink for
        // as long as it stayed on the list.
        suite.test("a turn that stopped for any other reason is not waiting") {
            expectWaiting(
                root, "stop-sequence",
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 60_000, stopReason: "stop_sequence", blocks: ["text"])
                ],
                .none, "not waiting on a turn that stopped"
            )
        }

        // The fuse. A terminal closed mid-turn and a killed process leave exactly what a
        // working agent leaves — an entry owing an answer and nothing after it — so how long
        // ago it was written is the only thing that separates them. Past it the wait is not
        // dropped but stalled: an answer is still owed, and the app has no way of knowing
        // whether one is coming, so it says the one thing it does know.
        suite.test("a wait older than the fuse becomes a stall") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds - 60)
            expectWaiting(
                root, "abandoned",
                [
                    userPrompt("do the thing", at: longAgo.addingTimeInterval(-30)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: longAgo
                    )
                ],
                .stalled, "no answer for this long is a stall, not an answer that landed"
            )
        }

        suite.test("a wait inside the fuse is still a wait") {
            let recently = now.addingTimeInterval(-config.abandonedWait.seconds + 60)
            expectWaiting(
                root, "still-going",
                [
                    userPrompt("do the thing", at: recently.addingTimeInterval(-30)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: recently
                    )
                ],
                .waiting, "a long tool call is still somebody waiting"
            )
        }

        // The fuse takes the blink away and nothing else: the session is still one being
        // worked on, and a row that vanished would say it was over.
        suite.test("a stalled session keeps its row and its numbers") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds - 60)
            guard let snapshot = session(
                root, "abandoned-row",
                [
                    userPrompt("do the thing", at: longAgo.addingTimeInterval(-30)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: longAgo
                    )
                ]
            ) else { return }
            suite.expectEqual(snapshot.contextTokens, 40_001, "the row still carries what the session holds")
            suite.expectEqual(snapshot.replyWait, .stalled, "and says an answer is still owed")
        }

        // The sign is for a wait and only for a wait. A session nobody has typed into for an
        // hour owes nothing: its turn ended, and what happens next waits on the person. The
        // half-hour activity window is what eventually takes that row away, not this rule.
        suite.test("a session that owes nothing never stalls, however long it is quiet") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds * 3)
            expectWaiting(
                root, "quiet",
                [
                    userPrompt("do the thing", at: longAgo.addingTimeInterval(-30)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 60_000,
                        stopReason: "end_turn", blocks: ["text"], at: longAgo
                    )
                ],
                .none, "idle is idle at any age"
            )
        }

        // A turn the person stopped is over, and staying stopped for longer does not turn it
        // into something the agent owes an answer for. Read the marker only inside the fuse
        // and every interrupted session on the machine would end up wearing the sign.
        suite.test("a turn stopped long ago is over rather than stalled") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds * 3)
            expectWaiting(
                root, "interrupted-long-ago",
                [
                    userPrompt("do the thing", at: longAgo.addingTimeInterval(-60)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: longAgo.addingTimeInterval(-40)
                    ),
                    interrupted(at: longAgo)
                ],
                .none, "stopped on purpose, whatever the age"
            )
        }

        // Pressing Esc writes an ordinary user entry, which the rule above would read as a
        // question waiting to be answered. It is the opposite: the agent was told to stop, and
        // whatever happens next waits on the person.
        suite.test("a turn the person stopped is not a wait") {
            expectWaiting(
                root, "interrupted",
                [
                    userPrompt("do the thing", at: now.addingTimeInterval(-60)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: now.addingTimeInterval(-40)
                    ),
                    interrupted(at: now.addingTimeInterval(-20))
                ],
                .none, "stopped on purpose, not waiting"
            )
        }

        suite.test("a tool call the person stopped is not a wait either") {
            expectWaiting(
                root, "interrupted-tool",
                [
                    userPrompt("do the thing", at: now.addingTimeInterval(-60)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: now.addingTimeInterval(-40)
                    ),
                    interrupted(forToolUse: true, at: now.addingTimeInterval(-20))
                ],
                .none, "the second wording says the same thing"
            )
        }

        // What the person types after stopping the agent is a question like any other, and the
        // light goes back to blinking on it. Read the marker as "this session is done" and it
        // would stay dark for the rest of the session.
        suite.test("asking again after stopping the agent waits once more") {
            expectWaiting(
                root, "interrupted-then-asked",
                [
                    userPrompt("do the thing", at: now.addingTimeInterval(-60)),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 40_000,
                        stopReason: "tool_use", blocks: ["tool_use"], at: now.addingTimeInterval(-40)
                    ),
                    interrupted(at: now.addingTimeInterval(-20)),
                    userPrompt("do this instead", at: now.addingTimeInterval(-10))
                ],
                .waiting, "a new question is a new wait"
            )
        }

        suite.test("a subagent's lines do not decide whether its session is waiting") {
            let directory = makeProjectDirectory(root, "sidechain", suite)
            writeTranscript(
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 60_000, stopReason: "end_turn", blocks: ["text"]),
                    // The agent goes on writing into the session's file after the session's own
                    // turn is over. Its entries are sidechain, and they are not the session's.
                    userPrompt("go and look", sidechain: true),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 20_000,
                        sidechain: true, stopReason: "tool_use", blocks: ["tool_use"]
                    )
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            guard let snapshot = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first(where: { !$0.isSubagent })
            else {
                suite.expect(false, "expected a session")
                return
            }
            suite.expectEqual(
                snapshot.replyWait, .none,
                "the session answered; the sidechain is somebody else's turn"
            )
        }

        suite.test("of two sessions, only the one being worked on is waiting") {
            let directory = makeProjectDirectory(root, "two", suite)
            writeTranscript(
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["tool_use"])
                ],
                to: directory, named: "busy.jsonl", modified: now, suite
            )
            writeTranscript(
                [
                    userPrompt("do the other thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 50_000, stopReason: "end_turn", blocks: ["text"])
                ],
                to: directory, named: "idle.jsonl", modified: now, suite
            )

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value ?? []
            let waiting = sessions.filter { $0.replyWait == .waiting }.map(\.sessionID).sorted()
            suite.expectEqual(waiting, ["busy"], "only the session whose agent owes an answer")
        }

        suite.test("a subagent still working is a row that is waiting") {
            let directory = makeProjectDirectory(root, "agent", suite)
            writeTranscript(
                [
                    userPrompt("do the thing"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000, stopReason: "tool_use", blocks: ["tool_use"])
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )
            writeSubagentTranscript(
                [
                    userPrompt("go and look", sidechain: true),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 20_000,
                        sidechain: true, stopReason: "tool_use", blocks: ["tool_use"]
                    )
                ],
                to: directory, session: "abc", named: "agent-1.jsonl", modified: now, suite
            )

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value ?? []
            guard let agent = sessions.first(where: \.isSubagent) else {
                suite.expect(false, "expected a subagent row")
                return
            }
            suite.expectEqual(agent.replyWait, .waiting, "the agent has a tool running")
        }
    }

    // What the sign is drawn in. Shape carries the wait and colour goes on carrying the
    // budget, so a stall must not touch what the rules make of the session's numbers — a
    // session that stalled with its window against the ceiling wears a red sign, which says
    // both things at once. The drawing itself lives in the app target, which no test can
    // import; what is checked here is the reading it is handed.
    suite.test("a stalled session is still judged by its numbers, ceiling included") {
        let rules = BudgetRules(config: config)
        func assess(_ wait: ReplyWait, tokens: Int) -> BudgetLevel {
            rules.assess(
                SessionSnapshot(
                    sessionID: "stalled",
                    service: .claude,
                    contextTokens: tokens,
                    contextWindowTokens: 100_000,
                    replyWait: wait
                )
            ).level
        }
        let full = Int(config.windowFill.high / 100 * 100_000) + 1
        suite.expectEqual(assess(.stalled, tokens: full), assess(.none, tokens: full), "at the ceiling")
        suite.expectEqual(assess(.stalled, tokens: full), .high, "and the ceiling is red")
        suite.expectEqual(assess(.stalled, tokens: 1_000), assess(.none, tokens: 1_000), "well under it")
    }
}
