import Foundation
import SessionHealthCore

/// The rules that decide what the widget says and what it notifies about.
///
/// Every expected boundary is read out of the loaded config rather than written here as a
/// literal: a test that repeats the numbers would keep passing after someone edits the file,
/// which is exactly the failure these cases exist to catch.
func runBudgetRulesTests(_ suite: TestSuite, config: ThresholdConfig) {
    let rules = BudgetRules(config: config)
    let fill = config.windowFill
    let limitMarks = config.limitUsage

    /// Small enough that a percentage of it is a round number of tokens, and small enough that
    /// no share of it trips the expensive-turn ceiling by accident.
    let window = 100_000

    func session(
        _ service: AgentService,
        tokens: Int,
        window: Int?,
        growth: Int? = nil,
        id: String = "session-1"
    ) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: id,
            service: service,
            contextTokens: tokens,
            contextWindowTokens: window,
            turnGrowthTokens: growth
        )
    }

    func tokens(_ percent: Double, of window: Int) -> Int {
        Int((Double(window) * percent / 100).rounded())
    }

    // MARK: Window fill — both services, one mark at a time

    for service in AgentService.allCases {
        suite.test("\(service.rawValue): window fill exactly at the notice mark has not crossed it") {
            let assessment = rules.assess(session(service, tokens: tokens(fill.notice, of: window), window: window))
            suite.expectEqual(assessment.level, .normal, "level")
            suite.expectEqual(assessment.alerts.count, 0, "alerts")
            suite.expectClose(assessment.windowFillPercent, fill.notice, "window fill")
        }

        // The whole reason the notice mark exists: a share almost every session passes is worth
        // a colour and not worth an interruption.
        suite.test("\(service.rawValue): past the notice mark the light changes colour and nothing is said") {
            let filled = tokens(fill.notice, of: window) + 1
            let assessment = rules.assess(session(service, tokens: filled, window: window))
            suite.expectEqual(assessment.level, .notice, "level")
            suite.expectEqual(assessment.alerts.count, 0, "alerts")
            suite.expect(
                assessment.levelSource == .windowFill(percent: fill.notice),
                "the panel must name the mark that set the colour, got \(String(describing: assessment.levelSource))"
            )
        }

        suite.test("\(service.rawValue): window fill exactly at the elevated mark has not crossed it") {
            let assessment = rules.assess(session(service, tokens: tokens(fill.elevated, of: window), window: window))
            suite.expectEqual(assessment.level, .notice, "level")
            suite.expectEqual(assessment.alerts.count, 0, "alerts")
        }

        suite.test("\(service.rawValue): past the elevated mark alerts once, with the percentage") {
            let filled = tokens(fill.elevated, of: window) + 1
            let assessment = rules.assess(session(service, tokens: filled, window: window))
            suite.expectEqual(assessment.level, .elevated, "level")
            suite.expectEqual(assessment.alerts.count, 1, "alerts")
            suite.expect(
                assessment.alerts.first?.kind == .windowFill(percent: fill.elevated),
                "the alert must name the mark that was crossed, got \(String(describing: assessment.alerts.first?.kind))"
            )
            suite.expectClose(assessment.alerts.first?.percent, Double(filled) / Double(window) * 100, "reported fill")
            suite.expectEqual(assessment.alerts.first?.service, service, "service")
        }

        suite.test("\(service.rawValue): window fill exactly at the high mark has not crossed it") {
            let assessment = rules.assess(session(service, tokens: tokens(fill.high, of: window), window: window))
            suite.expectEqual(assessment.level, .elevated, "level")
            suite.expect(
                assessment.alerts.map(\.kind) == [.windowFill(percent: fill.elevated)],
                "only the elevated mark is crossed here, got \(assessment.alerts.map(\.kind))"
            )
        }

        suite.test("\(service.rawValue): past the high mark alerts about that mark too") {
            let filled = tokens(fill.high, of: window) + 1
            let assessment = rules.assess(session(service, tokens: filled, window: window))
            suite.expectEqual(assessment.level, .high, "level")
            suite.expect(
                assessment.alerts.map(\.kind) == [
                    .windowFill(percent: fill.elevated),
                    .windowFill(percent: fill.high)
                ],
                "both speaking marks are behind us, lower one first, got \(assessment.alerts.map(\.kind))"
            )
        }

        // One scale, both lights: the same share must not mean one colour under the context
        // and another under the limits.
        suite.test("\(service.rawValue): the context and the limits colour the same share alike") {
            let share = fill.elevated + 1
            let context = rules.assess(session(service, tokens: tokens(share, of: window), window: window))
            let limit = rules.assess(
                LimitsSnapshot(
                    service: service,
                    observedAt: Date(timeIntervalSince1970: 1_789_000_000),
                    windows: [LimitWindow(kind: .short, usedPercent: share, resetsAt: nil)]
                )
            )
            suite.expectEqual(context.level, limit.level, "the same share on two lights")
        }
    }

    // MARK: An expensive turn

    let turn = config.expensiveTurn

    suite.test("a turn exactly at the configured share of the window is not expensive yet") {
        let growth = tokens(turn.windowSharePercent, of: window)
        let assessment = rules.assess(session(.codex, tokens: growth, window: window, growth: growth))
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
    }

    suite.test("a turn above that share alerts with how much it added") {
        let growth = tokens(turn.windowSharePercent, of: window) + 1
        let held = tokens(fill.elevated, of: window)
        let assessment = rules.assess(session(.codex, tokens: held, window: window, growth: growth))
        suite.expect(
            assessment.alerts.map(\.kind) == [.expensiveTurn(atContextTokens: held)],
            "got \(assessment.alerts.map(\.kind))"
        )
        suite.expectEqual(assessment.alerts.first?.tokens, growth, "reported growth")
        suite.expectClose(assessment.alerts.first?.percent, Double(growth) / Double(window) * 100, "growth as a share")
    }

    suite.test("an expensive turn does not change the level — it is news about one turn") {
        let growth = tokens(turn.windowSharePercent, of: window) + 1
        let assessment = rules.assess(session(.codex, tokens: growth, window: window, growth: growth))
        suite.expectEqual(assessment.level, .normal, "level")
    }

    suite.test("without a window size an expensive turn is measured in absolute tokens") {
        let atMark = rules.assess(session(.codex, tokens: 40_000, window: nil, growth: turn.tokens))
        suite.expectEqual(atMark.alerts.count, 0, "alerts at the mark")

        let above = rules.assess(session(.codex, tokens: 40_000, window: nil, growth: turn.tokens + 1))
        suite.expect(
            above.alerts.map(\.kind) == [.expensiveTurn(atContextTokens: 40_000)],
            "got \(above.alerts.map(\.kind))"
        )
        suite.expect(above.alerts.first?.percent == nil, "no share of a window nobody knows the size of")
    }

    // The case the share-only rule got wrong: on a 1M window a tenth of it is 100K, so the
    // share alone went quiet on exactly the longest sessions. Either ceiling is enough now.
    suite.test("on a very large window the absolute ceiling catches what the share misses") {
        let huge = 1_000_000
        let growth = turn.tokens + 1
        suite.expect(
            Double(growth) / Double(huge) * 100 < turn.windowSharePercent,
            "this case is only meaningful while \(growth) tokens is under \(turn.windowSharePercent)% of \(huge)"
        )
        let assessment = rules.assess(session(.claude, tokens: 300_000, window: huge, growth: growth))
        suite.expect(
            assessment.alerts.map(\.kind) == [.expensiveTurn(atContextTokens: 300_000)],
            "got \(assessment.alerts.map(\.kind))"
        )
        suite.expectEqual(assessment.alerts.first?.tokens, growth, "reported growth")
    }

    suite.test("on a small window the share still catches what the absolute ceiling misses") {
        let growth = tokens(turn.windowSharePercent, of: window) + 1
        suite.expect(growth < turn.tokens, "this case is only meaningful while \(growth) is under \(turn.tokens)")
        let assessment = rules.assess(session(.codex, tokens: 50_000, window: window, growth: growth))
        suite.expect(
            assessment.alerts.map(\.kind) == [.expensiveTurn(atContextTokens: 50_000)],
            "got \(assessment.alerts.map(\.kind))"
        )
    }

    suite.test("a first reading has no turn growth to judge and says nothing about it") {
        let assessment = rules.assess(session(.codex, tokens: 90_000, window: window, growth: nil))
        suite.expect(
            !assessment.alerts.contains { if case .expensiveTurn = $0.kind { true } else { false } },
            "got \(assessment.alerts.map(\.kind))"
        )
    }

    // MARK: An unknown window size is a fact, not an error

    suite.test("an unknown window size shows tokens, no percentage and no window alerts") {
        let assessment = rules.assess(session(.codex, tokens: 900_000, window: nil))
        suite.expect(assessment.windowFillPercent == nil, "no percentage without a window size")
        suite.expectEqual(assessment.contextTokens, 900_000, "tokens are still reported")
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
        suite.expectEqual(assessment.level, .normal, "level")
    }

    suite.test("a window size of zero is treated as unknown rather than as a division") {
        let assessment = rules.assess(session(.codex, tokens: 10_000, window: 0))
        suite.expect(assessment.windowFillPercent == nil, "no percentage")
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
    }

    // MARK: Subscription limits

    func limits(_ short: Double, _ weekly: Double, resetsAt: Date? = nil) -> LimitsSnapshot {
        LimitsSnapshot(
            service: .codex,
            observedAt: Date(timeIntervalSince1970: 1_789_000_000),
            windows: [
                LimitWindow(kind: .short, usedPercent: short, resetsAt: resetsAt, windowMinutes: 300),
                LimitWindow(kind: .weekly, usedPercent: weekly, resetsAt: resetsAt, windowMinutes: 10080)
            ]
        )
    }

    /// A fixed clock, because "how much of this window is left" is the rule under test and a
    /// case that reads the real one would pass or fail depending on when it ran.
    let now = Date(timeIntervalSince1970: 1_789_000_000)

    // Spent is not the same as worrying, and the bar shows it differently: past the upper mark
    // is still a dot, nothing left is a cross. The line between them is arithmetic, not a mark.
    suite.test("a window with nothing left reads as exhausted, and says which window") {
        let short = rules.assess(limits(100, 0))
        suite.expect(short.isExhausted, "100% used has nothing left")
        suite.expect(short.spentWindow?.kind == .short, "the 5-hour window is the spent one")

        let weekly = rules.assess(limits(0, 100))
        suite.expect(weekly.isExhausted, "either window counts")
        suite.expect(weekly.spentWindow?.kind == .weekly, "the weekly window is the spent one")
    }

    // Which one is named matters: a 5-hour window coming back within the hour changes nothing
    // while the week's is still empty, so that is the one the sentence is about.
    suite.test("both windows spent names the weekly one") {
        suite.expect(rules.assess(limits(100, 100)).spentWindow?.kind == .weekly, "weekly wins")
    }

    suite.test("a spent window carries its reset time, because that is what is worth saying") {
        let reset = Date(timeIntervalSince1970: 1_789_249_351)
        suite.expect(
            rules.assess(limits(100, 0, resetsAt: reset)).spentWindow?.resetsAt == reset,
            "the sentence about a spent window is about when it comes back"
        )
    }

    suite.test("a window past the upper mark but not spent is not exhausted") {
        suite.expect(rules.assess(limits(limitMarks.high + 1, 0)).spentWindow == nil, "no window is spent")
        suite.expect(
            !rules.assess(limits(limitMarks.high + 1, 0)).isExhausted,
            "\(limitMarks.high + 1)% used still has something left"
        )
        suite.expect(!rules.assess(limits(99, 0)).isExhausted, "99% used still has something left")
    }

    suite.test("limits nobody reported are not exhausted either") {
        let nothing = LimitsSnapshot(
            service: .claude,
            observedAt: Date(timeIntervalSince1970: 1_789_000_000),
            windows: []
        )
        suite.expect(!rules.assess(nothing).isExhausted, "no reading must not read as spent")
    }

    suite.test("a limit window exactly at the notice mark has not crossed it") {
        let assessment = rules.assess(limits(limitMarks.notice, 0), now: now)
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
        suite.expectEqual(assessment.level, .normal, "level")
    }

    suite.test("past the notice mark a limit light changes colour and nothing is said") {
        let assessment = rules.assess(limits(limitMarks.notice + 1, 0), now: now)
        suite.expectEqual(assessment.level, .notice, "level")
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
    }

    suite.test("a limit window exactly at the elevated mark has not crossed it") {
        let assessment = rules.assess(limits(limitMarks.elevated, 0), now: now)
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
        suite.expectEqual(assessment.level, .notice, "level")
    }

    suite.test("a limit window above the elevated mark alerts, naming the window and the reset") {
        let reset = now.addingTimeInterval(4 * 3600)
        let assessment = rules.assess(limits(limitMarks.elevated + 1, 0, resetsAt: reset), now: now)
        suite.expectEqual(assessment.level, .elevated, "level")
        suite.expect(
            assessment.alerts.map(\.kind) == [.limitUsage(window: .short, percent: limitMarks.elevated)],
            "got \(assessment.alerts.map(\.kind))"
        )
        suite.expectEqual(assessment.alerts.first?.resetsAt, reset, "reset time")
        suite.expectEqual(assessment.alerts.first?.service, .codex, "service")
    }

    suite.test("a limit window above the high mark alerts about that mark too") {
        let assessment = rules.assess(limits(limitMarks.high + 1, 0), now: now)
        suite.expectEqual(assessment.level, .high, "level")
        suite.expect(
            assessment.alerts.map(\.kind) == [
                .limitUsage(window: .short, percent: limitMarks.elevated),
                .limitUsage(window: .short, percent: limitMarks.high)
            ],
            "got \(assessment.alerts.map(\.kind))"
        )
    }

    suite.test("the two limit windows are judged separately and the worst one is the headline") {
        let assessment = rules.assess(limits(limitMarks.elevated + 1, limitMarks.high + 2), now: now)
        suite.expectEqual(assessment.level, .high, "level")
        suite.expect(
            assessment.alerts.map(\.kind) == [
                .limitUsage(window: .short, percent: limitMarks.elevated),
                .limitUsage(window: .weekly, percent: limitMarks.elevated),
                .limitUsage(window: .weekly, percent: limitMarks.high)
            ],
            "got \(assessment.alerts.map(\.kind))"
        )
        suite.expectClose(assessment.worstUsedPercent, limitMarks.high + 2, "worst window")
    }

    // MARK: A window about to reset is not worth stopping someone for

    suite.test("a limit window with almost none of its length left says nothing") {
        let quiet = config.limitWindowNearlyReset.remainingSharePercent
        let remaining = 300.0 * (quiet / 100) * 0.5  // minutes, half of what it takes to speak
        let assessment = rules.assess(
            limits(limitMarks.high + 1, 0, resetsAt: now.addingTimeInterval(remaining * 60)),
            now: now
        )
        suite.expectEqual(assessment.alerts.count, 0, "alerts: \(assessment.alerts.map(\.kind))")
    }

    // The colour is a fact about what is spent and stays true; only the interruption is dropped.
    suite.test("a window that stays quiet still shows the colour it has earned") {
        let remaining = 300.0 * (config.limitWindowNearlyReset.remainingSharePercent / 100) * 0.5
        let assessment = rules.assess(
            limits(limitMarks.high + 1, 0, resetsAt: now.addingTimeInterval(remaining * 60)),
            now: now
        )
        suite.expectEqual(assessment.level, .high, "level")
    }

    // Five hours and a week are not comparable in absolute time, which is the whole reason the
    // threshold is a share of the window: the same hour is nothing to one and everything to
    // the other.
    suite.test("the same hour left means one thing to a five-hour window and another to a week") {
        let hour = now.addingTimeInterval(3600)

        // A fifth of a five-hour window is still a fifth of it: worth saying.
        let short = rules.assess(limits(limitMarks.high + 1, 0, resetsAt: hour), now: now)
        suite.expect(
            short.alerts.map(\.kind) == [
                .limitUsage(window: .short, percent: limitMarks.elevated),
                .limitUsage(window: .short, percent: limitMarks.high)
            ],
            "an hour is a fifth of a five-hour window, got \(short.alerts.map(\.kind))"
        )

        // The same hour is the last fraction of a week, and the week comes back on its own.
        let weekly = rules.assess(limits(0, limitMarks.high + 1, resetsAt: hour), now: now)
        suite.expectEqual(weekly.alerts.count, 0, "the week is nearly back: \(weekly.alerts.map(\.kind))")
    }

    // Stale data describes a window that has already rolled over: the percentage refers to a
    // window that no longer exists, so it is not something to interrupt anyone about.
    suite.test("a window whose reset time has already passed is not announced") {
        let assessment = rules.assess(
            limits(limitMarks.high + 1, 0, resetsAt: now.addingTimeInterval(-3600)),
            now: now
        )
        suite.expectEqual(assessment.alerts.count, 0, "alerts: \(assessment.alerts.map(\.kind))")
    }

    // An unknown reset time is not evidence that the reset is near, and guessing would silence
    // exactly the windows the widget knows least about.
    suite.test("a window that never said when it resets is never silenced") {
        let assessment = rules.assess(limits(limitMarks.high + 1, 0, resetsAt: nil), now: now)
        suite.expectEqual(assessment.alerts.count, 2, "alerts: \(assessment.alerts.map(\.kind))")
    }

    suite.test("limits nobody has reported are absent, not zero") {
        let empty = LimitsSnapshot(service: .codex, observedAt: Date(), windows: [])
        let assessment = rules.assess(empty)
        suite.expect(assessment.worstUsedPercent == nil, "no percentage to show")
        suite.expectEqual(assessment.alerts.count, 0, "alerts")
        suite.expectEqual(assessment.level, .normal, "level")
    }
}
