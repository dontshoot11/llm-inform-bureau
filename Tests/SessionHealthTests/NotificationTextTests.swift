import Foundation
import SessionHealthCore
import Phrasing

/// What a notification says. Two things make it worth a test: the CLI command at the end,
/// which is not the same for both services, and the promise the widget must never make —
/// that it has measured the quality of the answers.
func runNotificationTextTests(_ suite: TestSuite, config: ThresholdConfig) {
    let reset = Date(timeIntervalSince1970: 1_789_260_000)
    let now = Date(timeIntervalSince1970: 1_789_249_000)

    func text(_ alert: BudgetAlert) -> NotificationText {
        AlertPhrasing.text(for: alert, config: config, now: now)
    }

    func windowFill(_ service: AgentService) -> BudgetAlert {
        BudgetAlert(
            kind: .windowFill(percent: config.windowFill.elevated),
            service: service,
            percent: config.windowFill.elevated + 2,
            tokens: 124_000
        )
    }

    func expensiveTurn(_ service: AgentService) -> BudgetAlert {
        BudgetAlert(
            kind: .expensiveTurn(atContextTokens: 96_000),
            service: service,
            percent: 18,
            tokens: 34_000
        )
    }

    func limitAlert(_ service: AgentService, _ window: LimitWindow.Kind, resetsAt: Date? = nil) -> BudgetAlert {
        BudgetAlert(
            kind: .limitUsage(window: window, percent: config.limitUsage.high),
            service: service,
            percent: config.limitUsage.high + 1,
            resetsAt: resetsAt
        )
    }

    let everyAlert = [
        windowFill(.claude), windowFill(.codex),
        expensiveTurn(.claude), expensiveTurn(.codex),
        limitAlert(.claude, .short, resetsAt: reset), limitAlert(.codex, .weekly, resetsAt: reset)
    ]

    suite.test("every notification names its service and says something") {
        for alert in everyAlert {
            let said = text(alert)
            suite.expect(said.title.contains(alert.service.shortLabel), "title without a service: \(said.title)")
            suite.expect(!said.body.isEmpty, "empty body for \(said.title)")
        }
    }

    // The notification is what the user sees instead of the CLI, so it has to end by saying
    // which command shows the rest — and the two services do not share one.
    suite.test("a context notification ends with the command of its own service") {
        suite.expect(text(windowFill(.claude)).body.hasSuffix("/context"), "Claude window: \(text(windowFill(.claude)).body)")
        suite.expect(text(windowFill(.codex)).body.hasSuffix("/status"), "Codex window: \(text(windowFill(.codex)).body)")
        suite.expect(text(expensiveTurn(.claude)).body.hasSuffix("/context"), "Claude turn")
        suite.expect(text(expensiveTurn(.codex)).body.hasSuffix("/status"), "Codex turn")
    }

    suite.test("a limit notification ends with /usage for both services") {
        suite.expect(text(limitAlert(.claude, .short, resetsAt: reset)).body.hasSuffix("/usage"), "Claude limits")
        suite.expect(text(limitAlert(.codex, .weekly, resetsAt: reset)).body.hasSuffix("/usage"), "Codex limits")
    }

    // The mark is what makes it a notification; the measurement is what makes it worth
    // reading. Crossing 50% and crossing 75% must not read as the same sentence.
    suite.test("a window notification names the mark in the title and the measurement in the body") {
        let said = text(windowFill(.claude))
        suite.expect(said.title.contains("\(Int(config.windowFill.elevated.rounded()))%"), "title: \(said.title)")
        suite.expect(said.body.contains("\(Int((config.windowFill.elevated + 2).rounded()))%"), "body: \(said.body)")
        suite.expect(said.body.contains("124K"), "body without the tokens held: \(said.body)")

        let higher = text(
            BudgetAlert(
                kind: .windowFill(percent: config.windowFill.high),
                service: .claude,
                percent: config.windowFill.high + 2,
                tokens: 160_000
            )
        )
        suite.expect(higher.title != said.title, "both marks read as the same notification: \(said.title)")
    }

    suite.test("an expensive turn notification carries how much the turn added") {
        let said = text(expensiveTurn(.codex))
        suite.expect(said.title.contains("34K"), "title: \(said.title)")
        suite.expect(said.body.contains("96K"), "the context it ended at: \(said.body)")
    }

    suite.test("a limit notification names the window, the mark and when it resets") {
        let short = text(limitAlert(.claude, .short, resetsAt: reset))
        suite.expect(short.title.lowercased().contains("5-hour"), "title: \(short.title)")
        suite.expect(short.title.contains("\(Int(config.limitUsage.high.rounded()))%"), "title without the mark: \(short.title)")
        suite.expect(short.body.contains("\(Int((config.limitUsage.high + 1).rounded()))%"), "body without the measurement: \(short.body)")
        suite.expect(short.body.contains(TimeDisplay.until(reset, now: now)), "body: \(short.body)")

        let weekly = text(limitAlert(.codex, .weekly, resetsAt: reset))
        suite.expect(weekly.title.lowercased().contains("weekly"), "title: \(weekly.title)")
    }

    suite.test("a limit with no reset time says so instead of inventing one") {
        let said = text(limitAlert(.codex, .short))
        suite.expect(said.body.lowercased().contains("not reported"), "body: \(said.body)")
    }

    // The panel's one explaining line, when a window has nothing left. The last mark it
    // crossed is beside the point by then, and saying "past 75%" about a spent window is the
    // kind of true-but-useless the interface is supposed to avoid.
    suite.test("a spent window is described as spent, not as the last mark it passed") {
        let said = Wording.spent(.claude, window: .short, resetsAt: reset, now: now)
        suite.expect(said.lowercased().contains("spent"), "the fact is missing: \(said)")
        suite.expect(said.contains(TimeDisplay.until(reset, now: now)), "when it comes back: \(said)")
        suite.expect(!said.contains("%"), "a percentage on a spent window reads as advice: \(said)")
    }

    suite.test("a spent window with no reset time says so rather than inventing one") {
        let said = Wording.spent(.codex, window: .weekly, resetsAt: nil, now: now)
        suite.expect(said.lowercased().contains("not reported"), "said: \(said)")
    }

    // The panel names the same commands under the same readings. One source, so the two places
    // cannot drift apart — and the services do not share the context one.
    suite.test("the panel's hints are the commands its notifications end with") {
        suite.expectEqual(Wording.limitsCommand(.claude), "/usage", "Claude limits")
        suite.expectEqual(Wording.limitsCommand(.codex), "/usage", "Codex limits")
        suite.expectEqual(Wording.contextCommand(.claude), "/context", "Claude context")
        suite.expectEqual(Wording.contextCommand(.codex), "/status", "Codex context")

        for service in AgentService.allCases {
            suite.expect(
                text(limitAlert(service, .short, resetsAt: reset)).body.hasSuffix(Wording.limitsCommand(service)),
                "the limits notification and the panel hint disagree for \(service.shortLabel)"
            )
            suite.expect(
                text(windowFill(service)).body.hasSuffix(Wording.contextCommand(service)),
                "the context notification and the panel hint disagree for \(service.shortLabel)"
            )
        }

        suite.expect(
            Wording.moreDetails("/usage").hasPrefix("/usage"),
            "the hint must lead with the command: \(Wording.moreDetails("/usage"))"
        )
    }

    // AGENTS.md draws this line: "answer quality may degrade past this point" is a fact about
    // a mark, "quality: 62%" is a measurement nothing in the data supports.
    suite.test("nothing claims to have measured quality") {
        for alert in everyAlert {
            let said = (text(alert).title + " " + text(alert).body).lowercased()
            suite.expect(!said.contains("quality:"), "a measured-quality claim in: \(said)")
            suite.expect(!said.contains("health"), "a health score in: \(said)")
            suite.expect(!said.contains("degraded"), "a verdict on the session in: \(said)")
        }
    }
}
