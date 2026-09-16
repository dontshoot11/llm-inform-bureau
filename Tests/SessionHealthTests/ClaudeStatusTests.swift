import Foundation
import AgentFiles
import SessionHealthCore

/// Reading what the status line leaves on disk.
///
/// The fixtures are trimmed copies of the documented statusLine payload — the same field
/// names and nesting Claude Code puts on the status line's stdin, including the parts that are
/// documented as sometimes absent (`rate_limits` before the first answer, `context_window`
/// values that are null early in a session).
func runClaudeStatusTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    withTemporaryDirectory(suite, named: "claude-status") { root in
        suite.test("a payload gives both limit windows, their resets and the age of the reading") {
            let directory = makeDirectory(root, "limits", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 23.5, sevenDay: 41.2),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-120), suite
            )

            guard case .value(let snapshot) = ClaudeStatusStore(directory: directory).latestLimits() else {
                suite.expect(false, "expected limits from the status line payload")
                return
            }
            suite.expectEqual(snapshot.service, .claude, "service")
            suite.expectClose(snapshot.window(.short)?.usedPercent, 23.5, "five-hour window")
            suite.expectClose(snapshot.window(.weekly)?.usedPercent, 41.2, "seven-day window")
            suite.expectEqual(snapshot.window(.short)?.resetsAt, Date(timeIntervalSince1970: 1_738_425_600), "reset")
            suite.expect(snapshot.window(.short)?.windowMinutes == nil, "Claude names its windows, it does not time them")
            suite.expectClose(
                snapshot.observedAt.timeIntervalSince1970,
                now.addingTimeInterval(-120).timeIntervalSince1970,
                "the age of the reading is when the status line last ran",
                tolerance: 1.5
            )
        }

        suite.test("the newest payload wins when several sessions have written one") {
            let directory = makeDirectory(root, "newest", suite)
            writeStatus(
                payload(session: "old", fiveHour: 5, sevenDay: 5),
                to: directory, named: "old.json", modified: now.addingTimeInterval(-3600), suite
            )
            writeStatus(
                payload(session: "new", fiveHour: 61, sevenDay: 12),
                to: directory, named: "new.json", modified: now.addingTimeInterval(-30), suite
            )

            guard case .value(let snapshot) = ClaudeStatusStore(directory: directory).latestLimits() else {
                suite.expect(false, "expected the newest payload")
                return
            }
            suite.expectClose(snapshot.window(.short)?.usedPercent, 61, "five-hour window")
        }

        // The sentence says nothing has reported yet and nothing more. Whether the slot is
        // connected at all is `StatusLineSlot`'s answer, and the panel puts a button here
        // instead of this sentence when it is not — so naming a fix from down here would be
        // this app telling somebody to do something it has no idea is needed.
        suite.test("no payload directory means nothing has reported, not zero percent") {
            let absent = root.appendingPathComponent("never-installed", isDirectory: true)
            guard case .noData(let explanation) = ClaudeStatusStore(directory: absent).latestLimits() else {
                suite.expect(false, "expected no data")
                return
            }
            suite.expect(
                explanation.lowercased().contains("status line"),
                "the sentence has to name where the numbers come from: \(explanation)"
            )
            suite.expect(
                !explanation.contains("Scripts/"),
                "and must not send anybody to a script: \(explanation)"
            )
        }

        suite.test("a payload without rate_limits is no data — the field is Pro and Max only") {
            let directory = makeDirectory(root, "no-limits", suite)
            writeStatus(
                payload(session: "s1", fiveHour: nil, sevenDay: nil),
                to: directory, named: "s1.json", modified: now, suite
            )
            guard case .noData(let explanation) = ClaudeStatusStore(directory: directory).latestLimits() else {
                suite.expect(false, "expected no data rather than 0%")
                return
            }
            suite.expect(!explanation.isEmpty, "the panel needs a sentence to show")
        }

        suite.test("a payload this app can no longer parse is an unavailable source") {
            let directory = makeDirectory(root, "broken", suite)
            writeStatus("{ this is no longer JSON", to: directory, named: "s1.json", modified: now, suite)
            guard case .unavailable = ClaudeStatusStore(directory: directory).latestLimits() else {
                suite.expect(false, "expected the source to be reported as unavailable")
                return
            }
        }

        suite.test("the payload carries the real window size, which a transcript never does") {
            let directory = makeDirectory(root, "context", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 10, sevenDay: 10, contextTokens: 88_000, windowSize: 1_000_000),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-60), suite
            )
            let sessions = ClaudeStatusStore(directory: directory).sessions(activity: activity, now: now)
            guard case .value(let found) = sessions, let session = found.first else {
                suite.expect(false, "expected one session from the payload")
                return
            }
            suite.expectEqual(session.sessionID, "s1", "session id")
            suite.expectEqual(session.service, .claude, "service")
            suite.expectEqual(session.contextTokens, 88_000, "context tokens")
            suite.expectEqual(session.contextWindowTokens, 1_000_000, "window size")
            suite.expectEqual(session.project, "llm-inform-bureau", "project, from the working directory")
            suite.expectClose(session.windowFillPercent, 8.8, "window fill")
        }

        suite.test("context values that are null early in a session are unknown, not zero") {
            let directory = makeDirectory(root, "null-context", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 10, sevenDay: 10, contextTokens: nil, windowSize: nil),
                to: directory, named: "s1.json", modified: now, suite
            )
            let sessions = ClaudeStatusStore(directory: directory).sessions(activity: activity, now: now)
            guard case .value(let found) = sessions else {
                suite.expect(false, "expected a reading")
                return
            }
            suite.expectEqual(found.count, 0, "a payload with no context numbers contributes no session")
        }

        suite.test("a payload left behind by a session that ended is not an active session") {
            let directory = makeDirectory(root, "stale", suite)
            writeStatus(
                payload(session: "s1", fiveHour: 10, sevenDay: 10, contextTokens: 5000, windowSize: 200_000),
                to: directory, named: "s1.json", modified: now.addingTimeInterval(-86_400), suite
            )
            let sessions = ClaudeStatusStore(directory: directory).sessions(activity: activity, now: now)
            suite.expectEqual(sessions.value?.count, 0, "yesterday's payload")

            // The limits it carries are still the freshest ones there are, and still shown —
            // with their age, which is the whole point of showing it.
            suite.expect(ClaudeStatusStore(directory: directory).latestLimits().value != nil, "limits survive")
        }
    }
}

// MARK: Fixtures

/// A statusLine payload, trimmed to the fields this app reads.
private func payload(
    session: String,
    fiveHour: Double?,
    sevenDay: Double?,
    contextTokens: Int? = 15_500,
    windowSize: Int? = 200_000
) -> String {
    var parts: [String] = [
        "\"session_id\": \"\(session)\"",
        "\"cwd\": \"/Users/nobody/petProjects/llm-inform-bureau\"",
        "\"model\": {\"id\": \"claude-opus-5\", \"display_name\": \"Opus\"}"
    ]
    var context: [String] = []
    if let contextTokens { context.append("\"total_input_tokens\": \(contextTokens)") }
    if let windowSize { context.append("\"context_window_size\": \(windowSize)") }
    parts.append("\"context_window\": {\(context.joined(separator: ", "))}")
    if let fiveHour, let sevenDay {
        parts.append("""
            "rate_limits": {\
            "five_hour": {"used_percentage": \(fiveHour), "resets_at": 1738425600}, \
            "seven_day": {"used_percentage": \(sevenDay), "resets_at": 1738857600}}
            """)
    }
    return "{\(parts.joined(separator: ", "))}"
}

private func writeStatus(
    _ contents: String,
    to directory: URL,
    named name: String,
    modified: Date,
    _ suite: TestSuite
) {
    let url = directory.appendingPathComponent(name)
    do {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    } catch {
        suite.expect(false, "could not write \(name): \(error)")
    }
}

/// The join between the two Claude sources.
///
/// A transcript always knows the tokens held and never the size of the window; the status
/// line knows the size and is only there once the slot is connected. Neither is complete on
/// its own, and what the widget shows for a Claude session depends on which of them answered.
func runClaudeSourceJoinTests(_ suite: TestSuite, config: ThresholdConfig) {
    let transcriptSession = SessionSnapshot(
        sessionID: "s1",
        service: .claude,
        contextTokens: 160_000,
        contextWindowTokens: nil,
        project: "llm-inform-bureau"
    )

    // Without the status line there is no window size, and every mark is a share of the window —
    // so there is nothing to place. The session is still listed with its tokens; what it must
    // not do is come out looking judged.
    suite.test("without the status line a Claude session is tokens alone, nothing to place on the scale") {
        let joined = UsageReader.withWindowSizes(.value([transcriptSession]), from: [])
        guard let session = joined.value?.first else {
            suite.expect(false, "expected the session through unchanged")
            return
        }
        suite.expect(session.contextWindowTokens == nil, "the window size stays unknown")
        suite.expect(session.windowFillPercent == nil, "no percentage is shown")
        suite.expect(session.contextTokens > 0, "the tokens are still reported")

        let assessment = BudgetRules(config: config).assess(session)
        suite.expectEqual(assessment.level, .normal, "no mark can be applied")
        suite.expect(assessment.levelSource == nil, "and nothing claims to have set a level")
    }

    suite.test("with the status line the same session is measured against its real window") {
        let payload = ClaudeStatusPayload(
            sessionID: "s1",
            project: "llm-inform-bureau",
            contextTokens: 160_000,
            contextWindowTokens: 1_000_000,
            limits: nil,
            writtenAt: Date()
        )
        let joined = UsageReader.withWindowSizes(.value([transcriptSession]), from: [payload])
        guard let session = joined.value?.first else {
            suite.expect(false, "expected the session")
            return
        }
        suite.expectEqual(session.contextWindowTokens, 1_000_000, "window size from the status line")
        suite.expectClose(session.windowFillPercent, 16, "window fill")
        suite.expectEqual(session.contextTokens, 160_000, "the tokens still come from the transcript")
    }

    suite.test("a payload for another session leaves this one alone") {
        let payload = ClaudeStatusPayload(
            sessionID: "somebody-else",
            project: "other",
            contextTokens: 10,
            contextWindowTokens: 200_000,
            limits: nil,
            writtenAt: Date()
        )
        let joined = UsageReader.withWindowSizes(.value([transcriptSession]), from: [payload])
        suite.expect(joined.value?.first?.contextWindowTokens == nil, "no window size borrowed from another session")
    }
}
