import Foundation
import AgentFiles
import SessionHealthCore

/// Reading the Codex limits off disk, including every way the files can fail to say anything.
///
/// The fixtures are trimmed copies of real rollout lines: the shapes here — a `token_count`
/// event carrying `rate_limits`, a pool with both windows null — were all found in
/// `~/.codex/sessions`.
func runCodexRolloutTests(_ suite: TestSuite) {
    withTemporaryDirectory(suite, named: "codex-rollouts") { root in
        suite.test("the newest rollout answers, with both windows, the reset and the plan") {
            let directory = makeRolloutDirectory(root, "newest-answers", suite)
            write(
                lines: [chatter(), limitsLine(primary: 52, secondary: 8, at: "2026-09-12T17:32:38.307Z")],
                to: directory, named: "rollout-2026-09-12T18-42-21-aaa.jsonl", modified: 200, suite
            )
            write(
                lines: [limitsLine(primary: 10, secondary: 1, at: "2026-09-11T10:00:00.000Z")],
                to: directory, named: "rollout-2026-09-11T15-43-23-bbb.jsonl", modified: 100, suite
            )

            guard case .value(let snapshot) = CodexRolloutStore(sessionsDirectory: directory).latestLimits() else {
                suite.expect(false, "expected limits from the newest rollout")
                return
            }
            suite.expectEqual(snapshot.service, .codex, "service")
            suite.expectClose(snapshot.window(.short)?.usedPercent, 52, "short window")
            suite.expectClose(snapshot.window(.weekly)?.usedPercent, 8, "weekly window")
            suite.expectEqual(snapshot.window(.short)?.windowMinutes, 300, "short window length")
            suite.expectEqual(snapshot.window(.weekly)?.windowMinutes, 10080, "weekly window length")
            suite.expectEqual(snapshot.window(.short)?.resetsAt, Date(timeIntervalSince1970: 1_789_249_351), "reset")
            suite.expectEqual(snapshot.planType, "plus", "plan")
            suite.expectClose(
                snapshot.observedAt.timeIntervalSince1970,
                instant("2026-09-12T17:32:38.307Z").timeIntervalSince1970,
                "observed at — the age comes from the line, not from the file",
                tolerance: 0.01
            )
            suite.expectClose(snapshot.worstUsedPercent, 52, "worst window")
        }

        suite.test("a trailing entry for another limit pool does not blank the reading") {
            let directory = makeRolloutDirectory(root, "other-pool", suite)
            write(
                lines: [limitsLine(primary: 52, secondary: 8, at: "2026-09-12T17:32:38.307Z"), emptyPoolLine()],
                to: directory, named: "rollout-2026-09-12T18-42-21-aaa.jsonl", modified: 200, suite
            )

            guard case .value(let snapshot) = CodexRolloutStore(sessionsDirectory: directory).latestLimits() else {
                suite.expect(false, "expected the last usable entry, not the empty pool")
                return
            }
            suite.expectClose(snapshot.window(.short)?.usedPercent, 52, "short window")
        }

        suite.test("a session that has not called the API yet sends the reader to the next file") {
            let directory = makeRolloutDirectory(root, "fresh-session", suite)
            write(
                lines: [chatter(), chatter()],
                to: directory, named: "rollout-2026-09-12T19-00-00-ccc.jsonl", modified: 300, suite
            )
            write(
                lines: [limitsLine(primary: 33, secondary: 4, at: "2026-09-12T17:32:38.307Z")],
                to: directory, named: "rollout-2026-09-12T18-42-21-aaa.jsonl", modified: 200, suite
            )

            guard case .value(let snapshot) = CodexRolloutStore(sessionsDirectory: directory).latestLimits() else {
                suite.expect(false, "expected the limits from the older rollout")
                return
            }
            suite.expectClose(snapshot.window(.short)?.usedPercent, 33, "short window")
        }

        suite.test("the reading is found without reading the whole file") {
            let directory = makeRolloutDirectory(root, "large-file", suite)
            var lines = [limitsLine(primary: 61, secondary: 9, at: "2026-09-12T17:32:38.307Z")]
            lines.append(contentsOf: (0..<700).map { _ in chatter(padding: 1000) })
            write(lines: lines, to: directory, named: "rollout-2026-09-12T18-42-21-aaa.jsonl", modified: 200, suite)

            guard case .value(let snapshot) = CodexRolloutStore(sessionsDirectory: directory).latestLimits() else {
                suite.expect(false, "expected the limits from behind the trailing traffic")
                return
            }
            suite.expectClose(snapshot.window(.short)?.usedPercent, 61, "short window")
        }

        suite.test("rollouts without any limits are no data, not zero percent") {
            let directory = makeRolloutDirectory(root, "no-limits", suite)
            write(lines: [chatter()], to: directory, named: "rollout-2026-09-12T18-42-21-aaa.jsonl", modified: 200, suite)

            if case .noData = CodexRolloutStore(sessionsDirectory: directory).latestLimits() { return }
            suite.expect(false, "expected no data")
        }

        suite.test("no Codex on this machine is no data either") {
            let directory = root.appendingPathComponent("never-created", isDirectory: true)
            if case .noData = CodexRolloutStore(sessionsDirectory: directory).latestLimits() { return }
            suite.expect(false, "expected no data")
        }

        suite.test("limits the app can no longer parse are reported as an unavailable source") {
            let directory = makeRolloutDirectory(root, "changed-format", suite)
            write(
                lines: ["{\"type\":\"event_msg\",\"payload\":{\"rate_limits\": <<broken>>}}"],
                to: directory, named: "rollout-2026-09-12T18-42-21-aaa.jsonl", modified: 200, suite
            )

            if case .unavailable = CodexRolloutStore(sessionsDirectory: directory).latestLimits() { return }
            suite.expect(false, "expected an unavailable source")
        }
    }
}


/// Reading the context budget of a Codex session out of the same rollouts.
///
/// Codex is the easier half: the `token_count` event carries the tokens held *and* the size of
/// the window, so nothing has to be inferred. The session's working directory is in the
/// `session_meta` line at the head of the file, which is why this reader reads both ends.
func runCodexSessionTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    withTemporaryDirectory(suite, named: "codex-sessions") { root in
        suite.test("a rollout gives the tokens held, the real window size and the project") {
            let directory = makeRolloutDirectory(root, "reads", suite)
            write(
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 20_622, window: 258_400), taskComplete()],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now.addingTimeInterval(-60), suite
            )

            let reading = CodexRolloutStore(sessionsDirectory: directory).activeSessions(activity: activity, now: now)
            guard case .value(let sessions) = reading, let session = sessions.first else {
                suite.expect(false, "expected one session, got \(reading)")
                return
            }
            suite.expectEqual(session.service, .codex, "service")
            suite.expectEqual(session.sessionID, "01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2", "session id")
            suite.expectEqual(session.contextTokens, 20_622, "tokens held")
            suite.expectEqual(session.contextWindowTokens, 258_400, "window size, straight from the file")
            suite.expectEqual(session.project, "llm-inform-bureau", "project")
            suite.expectClose(session.windowFillPercent, 7.98, "window fill", tolerance: 0.01)
        }

        // Codex writes the model on the line that opens a turn, so a session that switched
        // models mid-flight reports the one it is on now.
        suite.test("the model comes from the turn that opened last") {
            let directory = makeRolloutDirectory(root, "model", suite)
            write(
                lines: [
                    sessionMeta(),
                    turnContext(model: "gpt-5.6-thinking"), taskStarted(),
                    tokenCount(held: 20_000, window: 258_400), taskComplete(),
                    turnContext(model: "gpt-5.6-sol"), taskStarted(),
                    tokenCount(held: 30_000, window: 258_400), taskComplete()
                ],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )

            let session = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.model, "gpt-5.6-sol", "model")
        }

        suite.test("a rollout whose turn context is out of reach leaves the model unsaid") {
            let directory = makeRolloutDirectory(root, "no-model", suite)
            write(
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 20_000, window: 258_400), taskComplete()],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )

            let session = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.contextTokens, 20_000, "the reading is still read")
            suite.expect(session?.model == nil, "nothing is invented for a model nobody named")
        }

        suite.test("growth is measured over the last turn") {
            let directory = makeRolloutDirectory(root, "growth", suite)
            write(
                lines: [
                    sessionMeta(),
                    taskStarted(), tokenCount(held: 40_000, window: 258_400), taskComplete(),
                    taskStarted(), tokenCount(held: 55_000, window: 258_400),
                    tokenCount(held: 70_000, window: 258_400), taskComplete()
                ],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )

            let session = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.contextTokens, 70_000, "tokens held")
            suite.expectEqual(session?.turnGrowthTokens, 30_000, "growth over the turn")
        }

        suite.test("the Anthropic mark is never applied to a Codex session") {
            let directory = makeRolloutDirectory(root, "no-claude-mark", suite)
            write(
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 200_000, window: 1_000_000), taskComplete()],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )

            guard let session = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            else {
                suite.expect(false, "expected a session")
                return
            }
            // A lot of tokens held, and only 20% of the window: length on its own colours
            // nothing any more, because every mark is a share of the window.
            suite.expect(session.contextTokens > 150_000, "a long session by absolute length")
            suite.expectEqual(BudgetRules(config: config).assess(session).level, .normal, "level")
        }

        suite.test("a session from yesterday is not active") {
            let directory = makeRolloutDirectory(root, "stale", suite)
            write(
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 9000, window: 258_400), taskComplete()],
                to: directory, named: "rollout-2026-09-14T10-00-00-aaa.jsonl",
                modified: now.addingTimeInterval(-86_400), suite
            )
            let sessions = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value
            suite.expectEqual(sessions?.count, 0, "nothing running")
        }

        suite.test("a session that has not called the API yet has no context to report") {
            let directory = makeRolloutDirectory(root, "fresh", suite)
            write(
                lines: [sessionMeta(), taskStarted()],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )
            let sessions = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value
            suite.expectEqual(sessions?.count, 0, "nothing answered yet")
        }

        suite.test("no Codex rollouts at all is no data, and reads as waiting rather than as a fault") {
            let absent = root.appendingPathComponent("never-used", isDirectory: true)
            guard case .noData(let explanation) = CodexRolloutStore(sessionsDirectory: absent)
                .activeSessions(activity: activity, now: now)
            else {
                suite.expect(false, "expected no data")
                return
            }
            suite.expect(explanation.lowercased().contains("yet"), "the sentence waits: \(explanation)")
            suite.expect(!explanation.contains("/"), "a filesystem path in a sentence for a person: \(explanation)")
        }

        suite.test("lines this app can no longer parse are an unavailable source") {
            let directory = makeRolloutDirectory(root, "changed-format", suite)
            write(
                lines: [sessionMeta(), "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\", broken"],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )
            guard case .unavailable = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now)
            else {
                suite.expect(false, "expected the source to be reported as unavailable")
                return
            }
        }

        suite.test("the working directory is found in a head line as long as a real one") {
            // The real `session_meta` carries the whole system prompt and runs to about 18 KB.
            let directory = makeRolloutDirectory(root, "long-meta", suite)
            write(
                lines: [sessionMeta(padding: 40_000), taskStarted(), tokenCount(held: 1000, window: 258_400), taskComplete()],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )
            let session = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.project, "llm-inform-bureau", "project")
        }
    }
}

/// What a Codex session is waiting for — the same blinking light, read a different way.
///
/// Claude has to be inferred: nothing in a transcript says a turn is running, so the state
/// comes off whose entry was last and whether it promised another. Codex says it outright —
/// `task_started` opens a turn, `task_complete` closes it, `turn_aborted` closes the one the
/// person cut short — so these cases are about reading those boundaries in the right order and
/// about the two things the announcement does not cover: a turn nobody ever closed, and a turn
/// that opened further back than the reader looks.
func runCodexWaitingStateTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = fixtureNow

    /// The one rollout in a directory of its own, read back.
    func session(_ root: URL, _ name: String, _ lines: [String]) -> SessionSnapshot? {
        let directory = makeRolloutDirectory(root, name, suite)
        write(lines: lines, to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl", modified: now, suite)
        let reading = CodexRolloutStore(sessionsDirectory: directory).activeSessions(activity: activity, now: now)
        guard let found = reading.value?.first else {
            suite.expect(false, "expected a session, got \(reading)")
            return nil
        }
        return found
    }

    func expectWaiting(_ root: URL, _ name: String, _ lines: [String], _ wait: ReplyWait, _ label: String) {
        guard let snapshot = session(root, name, lines) else { return }
        suite.expectEqual(snapshot.replyWait, wait, label)
    }

    withTemporaryDirectory(suite, named: "codex-waiting") { root in
        suite.test("a turn that opened and has not closed is a session waiting") {
            expectWaiting(
                root, "open-turn",
                [sessionMeta(), taskStarted(), tokenCount(held: 20_622, window: 258_400)],
                .waiting, "the turn is still running"
            )
        }

        suite.test("a turn that completed is not waiting") {
            expectWaiting(
                root, "completed",
                [sessionMeta(), taskStarted(), tokenCount(held: 20_622, window: 258_400), taskComplete()],
                .none, "the answer landed"
            )
        }

        // The Codex half of "interrupting is an end of the wait announced in the file": the
        // person pressed Esc, the turn is over, and nobody waits for the fuse to say so.
        suite.test("a turn the person cut short is not waiting") {
            expectWaiting(
                root, "aborted",
                [sessionMeta(), taskStarted(), tokenCount(held: 20_622, window: 258_400), turnAborted()],
                .none, "an aborted turn owes nothing"
            )
        }

        suite.test("the next question after an answer is a wait again") {
            expectWaiting(
                root, "second-turn",
                [
                    sessionMeta(),
                    taskStarted(at: now.addingTimeInterval(-300)),
                    tokenCount(held: 20_000, window: 258_400, at: now.addingTimeInterval(-290)),
                    taskComplete(at: now.addingTimeInterval(-289)),
                    taskStarted(),
                    tokenCount(held: 30_000, window: 258_400)
                ],
                .waiting, "the last boundary is an opening one, not the completion before it"
            )
        }

        // Codex writes all the way through a turn — reasoning, tool calls, their output, a
        // token count per response — so the silence is the silence since the last of those.
        // A turn that opened an hour ago and wrote something ten seconds ago is a turn with a
        // long tool call in it, not an abandoned one.
        suite.test("the silence is counted from the last line, not from the opening of the turn") {
            expectWaiting(
                root, "long-turn",
                [
                    sessionMeta(),
                    taskStarted(at: now.addingTimeInterval(-config.abandonedWait.seconds * 3)),
                    tokenCount(held: 30_000, window: 258_400)
                ],
                .waiting, "still writing, so still working"
            )
        }

        // And from the last line of any kind, not from the last one this reader took numbers
        // out of. Two thirds of the rollouts here that end mid-turn end on something other
        // than a `token_count`, and the gap between the two runs to six minutes — a reader
        // clocking the silence from the token count would stall a session still writing.
        suite.test("the silence is counted from the last line of any kind, not the last token count") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds - 60)
            expectWaiting(
                root, "last-line-not-last-count",
                [
                    sessionMeta(),
                    taskStarted(at: longAgo.addingTimeInterval(-30)),
                    tokenCount(held: 30_000, window: 258_400, at: longAgo),
                    itemCompleted(at: now.addingTimeInterval(-10))
                ],
                .waiting, "the tool is still writing, whatever the last token count said"
            )
        }

        suite.test("a last line with no readable moment falls back to the file, not to an older line") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds - 60)
            expectWaiting(
                root, "timeless-tail",
                [
                    sessionMeta(),
                    taskStarted(at: longAgo.addingTimeInterval(-30)),
                    tokenCount(held: 30_000, window: 258_400, at: longAgo),
                    unreadableMoment()
                ],
                .waiting, "the file was written just now, whatever the line before it says"
            )
        }

        // The fuse. Six rollouts of the 133 on this machine end on an opening with nothing
        // after it: terminals closed mid-turn, processes killed. Nothing on disk tells those
        // from an agent thinking hard, so the app says the one thing it knows.
        suite.test("a turn silent for longer than the fuse is a stall") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds - 60)
            expectWaiting(
                root, "abandoned",
                [
                    sessionMeta(),
                    taskStarted(at: longAgo.addingTimeInterval(-30)),
                    tokenCount(held: 30_000, window: 258_400, at: longAgo)
                ],
                .stalled, "no line for this long is a stall, not an answer that landed"
            )
        }

        suite.test("a turn silent for less than the fuse is still a wait") {
            let recently = now.addingTimeInterval(-config.abandonedWait.seconds + 60)
            expectWaiting(
                root, "inside-fuse",
                [
                    sessionMeta(),
                    taskStarted(at: recently.addingTimeInterval(-30)),
                    tokenCount(held: 30_000, window: 258_400, at: recently)
                ],
                .waiting, "a long tool call is still somebody waiting"
            )
        }

        // The sign is for a wait and only for a wait: a session whose turn ended owes nothing,
        // however long it sits there. The half-hour activity window is what takes that row
        // away, not this rule.
        suite.test("a Codex session that owes nothing never stalls, however long it is quiet") {
            let longAgo = now.addingTimeInterval(-config.abandonedWait.seconds * 3)
            expectWaiting(
                root, "quiet",
                [
                    sessionMeta(),
                    taskStarted(at: longAgo.addingTimeInterval(-30)),
                    tokenCount(held: 30_000, window: 258_400, at: longAgo),
                    taskComplete(at: longAgo)
                ],
                .none, "quiet is not waiting"
            )
        }

        suite.test("asking again after cutting a turn short waits once more") {
            expectWaiting(
                root, "after-abort",
                [
                    sessionMeta(),
                    taskStarted(at: now.addingTimeInterval(-300)),
                    tokenCount(held: 20_000, window: 258_400, at: now.addingTimeInterval(-290)),
                    turnAborted(at: now.addingTimeInterval(-289)),
                    taskStarted(),
                    tokenCount(held: 30_000, window: 258_400)
                ],
                .waiting, "an abort ends a wait, it does not end them"
            )
        }

        // The one thing the announcement does not survive: a turn whose opening is further
        // back than the half megabyte this reader looks at. That takes a tool output running
        // to megabytes, and on a guess the light stays steady rather than blinking.
        suite.test("a turn whose boundary is out of reach is not claimed as a wait") {
            expectWaiting(
                root, "out-of-reach",
                [
                    sessionMeta(),
                    taskStarted(),
                    chatter(padding: 600_000),
                    tokenCount(held: 30_000, window: 258_400)
                ],
                .none, "nothing read says a turn is open"
            )
        }
    }
}
