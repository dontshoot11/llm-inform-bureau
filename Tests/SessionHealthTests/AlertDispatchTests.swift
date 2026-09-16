import Foundation
import SessionHealthCore

/// What the app does with everything the rules report on every file change: which of it is
/// news, and which of it has already been said.
func runAlertDispatchTests(_ suite: TestSuite, config: ThresholdConfig) {
    let rules = BudgetRules(config: config)
    let window = 100_000
    let fill = config.windowFill
    let limit = config.limitUsage

    func filled(_ percent: Double) -> Int {
        Int((Double(window) * percent / 100).rounded()) + 1
    }

    func session(_ id: String, at percent: Double, service: AgentService = .codex) -> ContextAssessment {
        rules.assess(
            SessionSnapshot(
                sessionID: id,
                service: service,
                contextTokens: filled(percent),
                contextWindowTokens: window
            )
        )
    }

    /// A fixed clock: a limit window is silent once it is about to reset, so a case that read
    /// the real one would start passing or failing on its own.
    let now = Date(timeIntervalSince1970: 1_789_249_000)

    func limits(_ percent: Double, resetsAt: Date, service: AgentService = .claude) -> LimitsAssessment {
        rules.assess(
            LimitsSnapshot(
                service: service,
                observedAt: now,
                windows: [LimitWindow(kind: .short, usedPercent: percent, resetsAt: resetsAt)]
            ),
            now: now
        )
    }

    /// Three hours into a five-hour window: far enough from resetting to be worth a word.
    let reset = now.addingTimeInterval(3 * 3600)

    // The app is started at login and finds whatever the day has already spent. Announcing a
    // backlog on every launch would train the user to ignore the notification that matters —
    // the one that arrives the moment a mark is crossed with the app watching.
    suite.test("the first pass records what is already crossed without announcing it") {
        var dispatch = AlertDispatch()
        let first = dispatch.pending(limits: [limits(limit.high + 5, resetsAt: reset)], sessions: [session("a", at: fill.high + 5)])
        suite.expectEqual(first.count, 0, "alerts on the first pass")
    }

    suite.test("a mark crossed while the app is watching is announced once") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated - 5)])

        let crossing = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated + 1)])
        suite.expect(crossing.map(\.kind) == [.windowFill(percent: fill.elevated)], "got \(crossing.map(\.kind))")

        let again = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated + 2)])
        suite.expectEqual(again.count, 0, "the same mark on the next file change")
    }

    suite.test("the second mark is announced after the first one") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated - 5)])
        _ = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated + 1)])

        let high = dispatch.pending(limits: [], sessions: [session("a", at: fill.high + 1)])
        suite.expect(high.map(\.kind) == [.windowFill(percent: fill.high)], "got \(high.map(\.kind))")
    }

    // `/clear` starts a new transcript with a new identifier, so the session scope ends by
    // itself and nothing has to notice the command.
    suite.test("after /clear the same mark may be announced again") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [session("before", at: fill.elevated - 5)])
        _ = dispatch.pending(limits: [], sessions: [session("before", at: fill.elevated + 1)])

        // The cleared session is empty at first, and the old file is still listed for a while.
        _ = dispatch.pending(limits: [], sessions: [session("before", at: fill.elevated + 1), session("after", at: 1)])
        let cleared = dispatch.pending(limits: [], sessions: [session("after", at: fill.elevated + 1)])
        suite.expect(cleared.map(\.kind) == [.windowFill(percent: fill.elevated)], "got \(cleared.map(\.kind))")
    }

    // Found on a live run: without this, jumping from under 50% to over 75% between two file
    // changes produced two notifications a second apart that differed in one word.
    suite.test("both marks crossed at once are announced as the higher one alone") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated - 5)])

        let jumped = dispatch.pending(limits: [], sessions: [session("a", at: fill.high + 5)])
        suite.expect(jumped.map(\.kind) == [.windowFill(percent: fill.high)], "got \(jumped.map(\.kind))")

        // The mark that was not shown is still remembered: it is history, not news waiting.
        suite.expectEqual(dispatch.remembers(.windowFill(percent: fill.elevated), session: "a"), true, "the lower mark")
        suite.expectEqual(dispatch.pending(limits: [], sessions: [session("a", at: fill.high + 6)]).count, 0, "nothing left to say")
    }

    suite.test("a limit window that rolled over is announced again") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [limits(limit.elevated - 5, resetsAt: reset)], sessions: [])
        let crossing = dispatch.pending(limits: [limits(limit.elevated + 1, resetsAt: reset)], sessions: [])
        suite.expectEqual(crossing.count, 1, "the mark as it is crossed")
        suite.expectEqual(dispatch.pending(limits: [limits(limit.elevated + 2, resetsAt: reset)], sessions: []).count, 0, "same window")

        let next = reset.addingTimeInterval(5 * 60 * 60)
        let rolled = dispatch.pending(limits: [limits(limit.elevated + 1, resetsAt: next)], sessions: [])
        suite.expectEqual(rolled.count, 1, "after the window rolled over")
    }

    suite.test("both services are announced, each with its own service on the alert") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [session("c", at: 1, service: .claude), session("x", at: 1, service: .codex)])

        let crossed = dispatch.pending(
            limits: [],
            sessions: [session("c", at: fill.elevated + 1, service: .claude), session("x", at: fill.elevated + 1, service: .codex)]
        )
        suite.expectEqual(crossed.count, 2, "one per service")
        suite.expect(Set(crossed.map(\.service)) == [.claude, .codex], "got \(crossed.map(\.service))")
    }

    // Whatever one turn added, it is a reading in the panel and never a notification: in
    // agent work a large read is most turns, and a mark lit on most of them says nothing.
    suite.test("a turn's growth alone never reaches the notifications") {
        func turn(growth: Int, held: Int) -> ContextAssessment {
            rules.assess(
                SessionSnapshot(
                    sessionID: "a",
                    service: .codex,
                    contextTokens: held,
                    contextWindowTokens: window,
                    turnGrowthTokens: growth
                )
            )
        }

        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [turn(growth: 10, held: 1_000)])
        let huge = Int(Double(window) * 0.3)
        suite.expectEqual(
            dispatch.pending(limits: [], sessions: [turn(growth: huge, held: 20_000)]).count,
            0,
            "a turn worth a third of the window, and still nothing to say"
        )
    }

    suite.test("a session that ended is forgotten rather than remembered forever") {
        var dispatch = AlertDispatch()
        _ = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated - 5)])
        _ = dispatch.pending(limits: [], sessions: [session("a", at: fill.elevated + 1)])
        suite.expectEqual(dispatch.remembers(.windowFill(percent: fill.elevated), session: "a"), true, "while it is listed")

        _ = dispatch.pending(limits: [], sessions: [session("b", at: 1)])
        suite.expectEqual(dispatch.remembers(.windowFill(percent: fill.elevated), session: "a"), false, "once it fell off the list")
    }
}
