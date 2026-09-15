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

// MARK: Fixtures

private func limitsLine(primary: Double, secondary: Double, at timestamp: String) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count",\
    "info":{"last_token_usage":{"total_tokens":193454},"model_context_window":258400},\
    "rate_limits":{"limit_id":"codex","limit_name":null,\
    "primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":1789249351},\
    "secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":1789836151},\
    "plan_type":"plus"}}}
    """
}

/// The shape Codex writes for a limit pool it has nothing to say about — seen on disk.
private func emptyPoolLine() -> String {
    """
    {"timestamp":"2026-09-12T17:33:00.000Z","type":"event_msg","payload":{"type":"token_count",\
    "rate_limits":{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null,\
    "plan_type":"plus"}}}
    """
}

/// The moment a fixture line was written, parsed the same way a reader of the file would.
private func instant(_ iso8601: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: iso8601) ?? .distantPast
}

private func chatter(padding: Int = 0) -> String {
    let text = String(repeating: "x", count: padding)
    return "{\"timestamp\":\"2026-09-12T17:00:00.000Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"text\":\"\(text)\"}}"
}

/// Rollouts live nested by date, so the fixtures are nested the same way.
private func makeRolloutDirectory(_ root: URL, _ name: String, _ suite: TestSuite) -> URL {
    let directory = makeDirectory(root, name, suite).appendingPathComponent("2026/09", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        suite.expect(false, "could not create \(directory.path): \(error)")
    }
    return root.appendingPathComponent(name, isDirectory: true)
}

/// Writes a rollout with an explicit modification date, because "the newest file" is the rule
/// under test and two files written in the same millisecond would not exercise it.
private func write(
    lines: [String],
    to directory: URL,
    named name: String,
    modified: TimeInterval,
    _ suite: TestSuite
) {
    // The limits cases only care which file is newer, so they pass an offset rather than a date.
    write(lines: lines, to: directory, named: name, modified: Date(timeIntervalSince1970: 1_789_000_000 + modified), suite)
}

private func write(
    lines: [String],
    to directory: URL,
    named name: String,
    modified: Date,
    _ suite: TestSuite
) {
    let url = directory.appendingPathComponent("2026/09", isDirectory: true).appendingPathComponent(name)
    do {
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    } catch {
        suite.expect(false, "could not write \(url.path): \(error)")
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
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 20_622, window: 258_400)],
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

        suite.test("growth is measured over the last turn") {
            let directory = makeRolloutDirectory(root, "growth", suite)
            write(
                lines: [
                    sessionMeta(),
                    taskStarted(), tokenCount(held: 40_000, window: 258_400),
                    taskStarted(), tokenCount(held: 55_000, window: 258_400),
                    tokenCount(held: 70_000, window: 258_400)
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
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 200_000, window: 1_000_000)],
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
                lines: [sessionMeta(), taskStarted(), tokenCount(held: 9000, window: 258_400)],
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
                lines: [sessionMeta(padding: 40_000), taskStarted(), tokenCount(held: 1000, window: 258_400)],
                to: directory, named: "rollout-2026-09-15T17-59-45-aaa.jsonl",
                modified: now, suite
            )
            let session = CodexRolloutStore(sessionsDirectory: directory)
                .activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(session?.project, "llm-inform-bureau", "project")
        }
    }
}

// MARK: Session fixtures

private func sessionMeta(padding: Int = 0) -> String {
    """
    {"timestamp":"2026-09-15T15:59:45.739Z","type":"session_meta","payload":{\
    "session_id":"01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2",\
    "cwd":"/Users/nobody/petProjects/llm-inform-bureau",\
    "base_instructions":{"text":"\(String(repeating: "x", count: padding))"}}}
    """
}

private func taskStarted() -> String {
    "{\"timestamp\":\"2026-09-15T15:59:46.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}"
}

private func tokenCount(held: Int, window: Int) -> String {
    """
    {"timestamp":"2026-09-15T15:59:50.276Z","type":"event_msg","payload":{"type":"token_count",\
    "info":{"last_token_usage":{"total_tokens":\(held)},"model_context_window":\(window)}}}
    """
}
