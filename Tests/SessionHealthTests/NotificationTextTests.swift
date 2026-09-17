import Foundation
import SessionHealthCore
import Phrasing

/// What a notification says. Three things make it worth a test: the CLI command at the end,
/// which is not the same for both services, the promise the widget must never make — that it
/// has measured the quality of the answers — and that both of these hold on either side of
/// every phrase, since a notification that lost its command in Russian would reach a reader in
/// exactly the state this suite exists to prevent.
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
        limitAlert(.claude, .short, resetsAt: reset), limitAlert(.codex, .weekly, resetsAt: reset)
    ]

    suite.test("every notification names its service and says something, in both languages") {
        for alert in everyAlert {
            let said = text(alert)
            suite.expect(
                said.title.holds { $0.contains(alert.service.shortLabel) },
                "title without a service: \(said.title.shown)"
            )
            suite.expect(said.body.holds { !$0.isEmpty }, "empty body for \(said.title.shown)")
        }
    }

    // The notification is what the user sees instead of the CLI, so it has to end by saying
    // which command shows the rest — and the two services do not share one. The command is the
    // same in either language, and it has to be at the end of both.
    suite.test("a context notification ends with the command of its own service") {
        let claude = text(windowFill(.claude))
        let codex = text(windowFill(.codex))
        suite.expect(claude.body.holds { $0.hasSuffix("/context") }, "Claude window: \(claude.body.shown)")
        suite.expect(codex.body.holds { $0.hasSuffix("/status") }, "Codex window: \(codex.body.shown)")
    }

    suite.test("a limit notification ends with /usage for both services") {
        let claude = text(limitAlert(.claude, .short, resetsAt: reset))
        let codex = text(limitAlert(.codex, .weekly, resetsAt: reset))
        suite.expect(claude.body.holds { $0.hasSuffix("/usage") }, "Claude limits: \(claude.body.shown)")
        suite.expect(codex.body.holds { $0.hasSuffix("/usage") }, "Codex limits: \(codex.body.shown)")
    }

    // The mark is what makes it a notification; the measurement is what makes it worth
    // reading. Crossing 50% and crossing 75% must not read as the same sentence.
    suite.test("a window notification names the mark in the title and the measurement in the body") {
        let said = text(windowFill(.claude))
        let mark = "\(Int(config.windowFill.elevated.rounded()))%"
        let measured = "\(Int((config.windowFill.elevated + 2).rounded()))%"
        suite.expect(said.title.holds { $0.contains(mark) }, "title: \(said.title.shown)")
        suite.expect(said.body.holds { $0.contains(measured) }, "body: \(said.body.shown)")
        suite.expect(said.body.holds { $0.contains("124K") }, "body without the tokens held: \(said.body.shown)")

        let higher = text(
            BudgetAlert(
                kind: .windowFill(percent: config.windowFill.high),
                service: .claude,
                percent: config.windowFill.high + 2,
                tokens: 160_000
            )
        )
        suite.expect(higher.title != said.title, "both marks read as the same notification: \(said.title.shown)")
        suite.expect(higher.body != said.body, "both marks read as the same body: \(said.body.shown)")
    }

    suite.test("a limit notification names the window, the mark and when it resets") {
        let short = text(limitAlert(.claude, .short, resetsAt: reset))
        suite.expect(
            short.title.carries(Wording.limitName(.short)),
            "title without the window: \(short.title.shown)"
        )
        suite.expect(
            short.title.holds { $0.contains("\(Int(config.limitUsage.high.rounded()))%") },
            "title without the mark: \(short.title.shown)"
        )
        suite.expect(
            short.body.holds { $0.contains("\(Int((config.limitUsage.high + 1).rounded()))%") },
            "body without the measurement: \(short.body.shown)"
        )
        suite.expect(
            short.body.carries(TimeDisplay.until(reset, now: now)),
            "body without when it resets: \(short.body.shown)"
        )

        let weekly = text(limitAlert(.codex, .weekly, resetsAt: reset))
        suite.expect(
            weekly.title.carries(Wording.limitName(.weekly)),
            "title: \(weekly.title.shown)"
        )
    }

    suite.test("a limit with no reset time says so instead of inventing one") {
        let said = text(limitAlert(.codex, .short))
        suite.expect(
            said.body.carries(Phrase("not reported", "не сообщено")),
            "body: \(said.body.shown)"
        )
    }

    // The panel's one explaining line, when a window has nothing left. The last mark it
    // crossed is beside the point by then, and saying "past 75%" about a spent window is the
    // kind of true-but-useless the interface is supposed to avoid.
    suite.test("a spent window is described as spent, not as the last mark it passed") {
        let said = Wording.spent(.claude, window: .short, resetsAt: reset, now: now)
        suite.expect(said.carries(Phrase("spent", "исчерпан")), "the fact is missing: \(said.shown)")
        suite.expect(
            said.carries(TimeDisplay.until(reset, now: now)),
            "when it comes back: \(said.shown)"
        )
        suite.expect(
            said.holds { !$0.contains("%") },
            "a percentage on a spent window reads as advice: \(said.shown)"
        )
    }

    suite.test("a spent window with no reset time says so rather than inventing one") {
        let said = Wording.spent(.codex, window: .weekly, resetsAt: nil, now: now)
        suite.expect(said.carries(Phrase("not reported", "не сообщено")), "said: \(said.shown)")
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
                text(limitAlert(service, .short, resetsAt: reset)).body
                    .holds { $0.hasSuffix(Wording.limitsCommand(service)) },
                "the limits notification and the panel hint disagree for \(service.shortLabel)"
            )
            suite.expect(
                text(windowFill(service)).body
                    .holds { $0.hasSuffix(Wording.contextCommand(service)) },
                "the context notification and the panel hint disagree for \(service.shortLabel)"
            )
        }

        suite.expect(
            Wording.moreDetails("/usage").holds { $0.hasPrefix("/usage") },
            "the hint must lead with the command: \(Wording.moreDetails("/usage").shown)"
        )
    }

    // The road a notification takes when the notification centre will not take it from this
    // app directly: `osascript`, which is a grammar, and a body that carries a slash command,
    // a line break and — in either language — whatever the person typed into their terminal.
    suite.test("the script a notification goes out over survives what the body carries") {
        let said = NotificationScript.display(
            title: "Claude ждёт вас в llm-inform-bureau",
            body: "Который \"подход\"?\n/context"
        )
        suite.expect(said.hasPrefix("display notification "), "the verb is missing: \(said)")
        suite.expect(
            said.contains("with title \"Claude ждёт вас в llm-inform-bureau\""),
            "the title did not arrive whole: \(said)"
        )
        // Two quotes of its own and no more: the ones the script is built out of. A quotation
        // mark in the body that was not escaped would end the string early and leave the rest
        // of the question as AppleScript to run.
        suite.expect(
            said.contains("\\\"подход\\\""), "a quotation mark left the string open: \(said)"
        )
        suite.expect(
            !said.contains("\n"), "a real line break ends the line the script is on: \(said)"
        )
        suite.expect(said.contains("\\n/context"), "the command did not arrive: \(said)")
    }

    suite.test("a backslash in the body is escaped before the quotes are counted") {
        let said = NotificationScript.display(title: "t", body: "a\\")
        suite.expectEqual(
            said, "display notification \"a\\\\\" with title \"t\"",
            "a trailing backslash must not escape the quote that closes the string"
        )
    }

    // AGENTS.md draws this line: "answer quality may degrade past this point" is a fact about
    // a mark, "quality: 62%" is a measurement nothing in the data supports. Asked of both
    // sides, with each language's own words for it (`QualityClaims`).
    suite.test("nothing claims to have measured quality, in either language") {
        for alert in everyAlert {
            let said = text(alert)
            for side in [said.title.english + " " + said.body.english, said.title.russian + " " + said.body.russian] {
                let claims = QualityClaims.found(in: side)
                suite.expect(claims.isEmpty, "a claim about the answers themselves — \(claims) — in: \(side)")
            }
        }
    }
}
