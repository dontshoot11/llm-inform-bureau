import Foundation
import SessionHealthCore

/// One mark, one notification. The rules report everything currently crossed on every refresh,
/// so without this the widget would notify about the same 50% on every keystroke.
func runAlertMemoryTests(_ suite: TestSuite, config: ThresholdConfig) {
    let rules = BudgetRules(config: config)
    let window = 100_000
    let fill = config.windowFill

    func session(_ id: String, tokens: Int) -> SessionSnapshot {
        SessionSnapshot(sessionID: id, service: .codex, contextTokens: tokens, contextWindowTokens: window)
    }

    func filled(_ percent: Double) -> Int {
        Int((Double(window) * percent / 100).rounded()) + 1
    }

    suite.test("a mark that stays crossed is delivered once") {
        var memory = AlertMemory()
        let alerts = rules.assess(session("a", tokens: filled(fill.elevated))).alerts
        let scope = AlertScope.session("a")

        suite.expectEqual(memory.undelivered(alerts, scope: scope).count, 1, "first pass")
        suite.expectEqual(memory.undelivered(alerts, scope: scope).count, 0, "second pass")
        suite.expectEqual(memory.undelivered(alerts, scope: scope).count, 0, "third pass")
        suite.expectEqual(memory.hasDelivered(.windowFill(percent: fill.elevated), scope: scope), true, "remembered")
    }

    suite.test("the next mark is delivered even though the first one is already remembered") {
        var memory = AlertMemory()
        let scope = AlertScope.session("a")
        _ = memory.undelivered(rules.assess(session("a", tokens: filled(fill.elevated))).alerts, scope: scope)

        let later = memory.undelivered(rules.assess(session("a", tokens: filled(fill.high))).alerts, scope: scope)
        suite.expect(later.map(\.kind) == [.windowFill(percent: fill.high)], "got \(later.map(\.kind))")
    }

    suite.test("a session that jumps past both marks at once reports the lower one first") {
        var memory = AlertMemory()
        let alerts = rules.assess(session("a", tokens: filled(fill.high))).alerts
        let delivered = memory.undelivered(alerts, scope: AlertScope.session("a"))
        suite.expect(
            delivered.map(\.kind) == [.windowFill(percent: fill.elevated), .windowFill(percent: fill.high)],
            "got \(delivered.map(\.kind))"
        )
    }

    // `/clear` starts a new session file with a new identifier, so this is what makes the
    // counter reset itself when the user clears — nothing has to notice the command.
    suite.test("a new session starts with an empty memory") {
        var memory = AlertMemory()
        let alerts = rules.assess(session("a", tokens: filled(fill.elevated))).alerts
        _ = memory.undelivered(alerts, scope: AlertScope.session("a"))

        let afterClear = rules.assess(session("b", tokens: filled(fill.elevated))).alerts
        suite.expectEqual(memory.undelivered(afterClear, scope: AlertScope.session("b")).count, 1, "new session")
        suite.expectEqual(
            memory.hasDelivered(.windowFill(percent: fill.elevated), scope: AlertScope.session("a")),
            true,
            "the old session is still remembered"
        )
    }

    suite.test("a limit window that has rolled over may be reported again") {
        var memory = AlertMemory()
        let first = Date(timeIntervalSince1970: 1_789_249_351)
        let next = Date(timeIntervalSince1970: 1_789_267_351)
        let alert = BudgetAlert(
            kind: .limitUsage(window: .short, percent: config.limitUsage.elevated),
            service: .codex,
            percent: config.limitUsage.elevated + 1
        )

        let before = AlertScope.limitWindow(service: .codex, kind: .short, resetsAt: first)
        suite.expectEqual(memory.undelivered([alert], scope: before).count, 1, "first window")
        suite.expectEqual(memory.undelivered([alert], scope: before).count, 0, "same window again")

        let after = AlertScope.limitWindow(service: .codex, kind: .short, resetsAt: next)
        suite.expectEqual(memory.undelivered([alert], scope: after).count, 1, "after the reset")
    }

    suite.test("the same mark on the two limit windows is two separate notifications") {
        var memory = AlertMemory()
        let reset = Date(timeIntervalSince1970: 1_789_249_351)
        let percent = config.limitUsage.elevated
        let short = BudgetAlert(kind: .limitUsage(window: .short, percent: percent), service: .codex)
        let weekly = BudgetAlert(kind: .limitUsage(window: .weekly, percent: percent), service: .codex)
        let scope = AlertScope.limitWindow(service: .codex, kind: .short, resetsAt: reset)

        suite.expectEqual(memory.undelivered([short, weekly], scope: scope).count, 2, "both windows")
    }

    suite.test("scopes that are gone are forgotten") {
        var memory = AlertMemory()
        let alerts = rules.assess(session("a", tokens: filled(fill.elevated))).alerts
        _ = memory.undelivered(alerts, scope: AlertScope.session("a"))
        _ = memory.undelivered(alerts, scope: AlertScope.session("b"))

        memory.retain(scopes: [AlertScope.session("b")])
        suite.expectEqual(
            memory.hasDelivered(.windowFill(percent: fill.elevated), scope: AlertScope.session("a")),
            false,
            "the session that ended"
        )
        suite.expectEqual(
            memory.hasDelivered(.windowFill(percent: fill.elevated), scope: AlertScope.session("b")),
            true,
            "the session still running"
        )
    }
}
