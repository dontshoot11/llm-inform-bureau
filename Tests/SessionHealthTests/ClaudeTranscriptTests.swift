import Foundation
import AgentFiles
import SessionHealthCore

/// Reading the context budget of a Claude session out of its transcript.
///
/// The fixtures — trimmed copies of real lines from `~/.claude/projects` — are in
/// `ClaudeFixtures.swift`, shared with the subagent tests: the two read the same shape of file.
func runClaudeTranscriptTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    withTemporaryDirectory(suite, named: "claude-transcripts") { root in
        suite.test("the last answer gives the tokens held, the project and the session") {
            let directory = makeProjectDirectory(root, "reads", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 100_000)
                ],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )

            let reading = ClaudeTranscriptStore(projectsDirectory: directory).activeSessions(activity: activity, now: now)
            guard case .value(let sessions) = reading, let session = sessions.first else {
                suite.expect(false, "expected one session, got \(reading)")
                return
            }
            suite.expectEqual(session.sessionID, "abc", "session id")
            suite.expectEqual(session.service, .claude, "service")
            suite.expectEqual(session.contextTokens, 100_802, "tokens held: input + cache creation + cache read")
            suite.expectEqual(session.project, "llm-inform-bureau", "project, from the session's working directory")
        }

        // Which model a session runs on can be changed mid session, so it is a fact about the
        // last answer and not about the file. The identifier is shown as written: the transcript
        // is the only source every Claude session has, and it names nothing else.
        suite.test("the model comes from the last answer, not the first") {
            let directory = makeProjectDirectory(root, "model", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 10_000, model: "claude-sonnet-5"),
                    userPrompt("switched"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 40_000, model: "claude-opus-5")
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.model, "claude-opus-5", "model")
        }

        suite.test("a transcript that never named a model leaves it unsaid, not guessed") {
            let directory = makeProjectDirectory(root, "no-model", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    """
                    {"type":"assistant","isSidechain":false,"cwd":"\(workingDirectory)",\
                    "timestamp":"\(stamp(fixtureAnsweredAt))",\
                    "message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text"}],\
                    "usage":{"input_tokens":2,"cache_creation_input_tokens":0,\
                    "cache_read_input_tokens":10000,"output_tokens":10}}}
                    """
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.contextTokens, 10_002, "the reading is still read")
            suite.expect(session?.model == nil, "nothing is invented for a model nobody named")
        }

        suite.test("a transcript does not know the window size, and says nothing rather than guessing") {
            let directory = makeProjectDirectory(root, "no-window", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 0, cacheCreation: 0, cacheRead: 160_000)],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            guard let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            else {
                suite.expect(false, "expected a session")
                return
            }
            suite.expect(session.contextWindowTokens == nil, "the window size is unknown")
            suite.expect(session.windowFillPercent == nil, "and so there is no percentage to show")

            // Every mark is a share of the window, so an unknown window leaves nothing to
            // place on the scale. The tokens are still reported; no colour is claimed.
            let assessment = BudgetRules(config: config).assess(session)
            suite.expectEqual(assessment.level, .normal, "no mark can be applied without a window")
            suite.expect(assessment.levelSource == nil, "and nothing claims to have set a level")
        }

        suite.test("growth is measured over the last turn, not over the last line") {
            let directory = makeProjectDirectory(root, "growth", suite)
            writeTranscript(
                [
                    userPrompt("first"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000),
                    userPrompt("second"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 55_000),
                    toolResult(),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 70_000)
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            guard let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            else {
                suite.expect(false, "expected a session")
                return
            }
            suite.expectEqual(session.contextTokens, 70_001, "tokens held")
            // The turn started at the second prompt, when 40001 tokens were held; the
            // tool_result in the middle continued that turn rather than starting a new one.
            suite.expectEqual(session.turnGrowthTokens, 30_000, "growth over the turn")
        }

        suite.test("the first turn of a session has nothing to compare against") {
            let directory = makeProjectDirectory(root, "first-turn", suite)
            writeTranscript(
                [userPrompt("first"), assistant(input: 1, cacheCreation: 0, cacheRead: 40_000)],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expect(session?.turnGrowthTokens == nil, "growth is unknown, not zero")
        }

        suite.test("a subagent's lines are not the session's context") {
            let directory = makeProjectDirectory(root, "sidechain", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 50_000),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 900_000, sidechain: true)
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.contextTokens, 50_001, "the main session's own context")
        }

        suite.test("a session left over from yesterday is not active") {
            let directory = makeProjectDirectory(root, "stale", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 50_000)],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-86_400), suite
            )
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 10_000)],
                to: directory, named: "def.jsonl", modified: now.addingTimeInterval(-120), suite
            )

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value
            suite.expectEqual(sessions?.map(\.sessionID), ["def"], "only today's session")
        }

        suite.test("a session that has just been cleared reads as no session rather than as the old one") {
            // `/clear` starts a new transcript file; the old one stops being written to. The
            // new file holds the prompt and no answer yet, so there is no context to report.
            let directory = makeProjectDirectory(root, "cleared", suite)
            writeTranscript([userPrompt("fresh start")], to: directory, named: "new.jsonl", modified: now, suite)

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value
            suite.expectEqual(sessions?.count, 0, "nothing answered yet")
        }

        suite.test("the project is where the session started, not where it wandered off to") {
            // A session can change directory while it runs — a shell command deeper into the
            // tree is enough — and the last answer then carries that directory rather than the
            // project's. Naming the session after it makes one project look like two.
            let directory = makeProjectDirectory(root, "wandered", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000),
                    assistant(
                        input: 1, cacheCreation: 0, cacheRead: 60_000,
                        cwd: workingDirectory + "/TODO/context-usage-widget"
                    )
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.project, "llm-inform-bureau", "the project the session belongs to")
        }

        suite.test("the session `/clear` closed off is gone, not left beside the new one") {
            // `/clear` writes the cost of the finished session as the last line of its
            // transcript — which also touches the file, so the activity rule alone keeps the
            // session that has just ended on screen for another half hour, next to the fresh
            // one. The end marker is what tells them apart.
            let directory = makeProjectDirectory(root, "closed-off", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 500_000), costState()],
                to: directory, named: "old.jsonl", modified: now.addingTimeInterval(-30), suite
            )
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 60_000)],
                to: directory, named: "new.jsonl", modified: now, suite
            )

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value
            suite.expectEqual(sessions?.map(\.sessionID), ["new"], "only the session still running")
        }

        suite.test("a resumed session is running again, whatever its earlier end marker says") {
            let directory = makeProjectDirectory(root, "resumed", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 40_000),
                    costState(),
                    userPrompt("back again"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 55_000)
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.contextTokens, 55_001, "the reading after the session came back")
        }

        suite.test("bookkeeping written after the end marker does not revive the session") {
            // Closing a session can be followed by a line or two of housekeeping that carries
            // no message: what ends a transcript is the marker, not the last byte in the file.
            let directory = makeProjectDirectory(root, "housekeeping", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 70_000),
                    costState(),
                    filler(padding: 10)
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let sessions = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value
            suite.expectEqual(sessions?.count, 0, "the session is over")
        }

        // Whether the agent is on this machine at all is `UsageReading.installed`'s answer, not
        // this store's: here an empty tree and a missing one are the same "nothing yet", and
        // the sentence waits rather than blaming anything.
        suite.test("no transcripts at all is no data, and reads as waiting rather than as a fault") {
            let absent = root.appendingPathComponent("never-used", isDirectory: true)
            guard case .noData(let explanation) = ClaudeTranscriptStore(projectsDirectory: absent)
                .activeSessions(activity: activity, now: now)
            else {
                suite.expect(false, "expected no data")
                return
            }
            suite.expect(
                explanation.english.lowercased().contains("yet")
                    && explanation.russian.lowercased().contains("пока"),
                "the sentence waits: \(explanation.shown)"
            )
            suite.expect(
                explanation.holds { !$0.contains("/") },
                "a filesystem path in a sentence for a person: \(explanation.shown)"
            )
        }

        suite.test("lines this app can no longer parse are an unavailable source") {
            let directory = makeProjectDirectory(root, "changed-format", suite)
            writeTranscript(
                ["{\"type\":\"assistant\", this is no longer JSON"],
                to: directory, named: "abc.jsonl", modified: now, suite
            )
            guard case .unavailable = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now)
            else {
                suite.expect(false, "expected the source to be reported as unavailable")
                return
            }
        }

        suite.test("the reading is found without reading the whole file") {
            let directory = makeProjectDirectory(root, "large-file", suite)
            var lines = [userPrompt("start")]
            lines.append(contentsOf: (0..<3000).map { _ in filler(padding: 1000) })
            lines.append(assistant(input: 1, cacheCreation: 0, cacheRead: 77_000))
            writeTranscript(lines, to: directory, named: "abc.jsonl", modified: now, suite)

            let started = Date()
            let session = ClaudeTranscriptStore(projectsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.contextTokens, 77_001, "tokens held")
            suite.expect(Date().timeIntervalSince(started) < 2, "a tail read, not a full one")
        }
    }
}
