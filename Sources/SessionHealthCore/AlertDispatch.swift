import Foundation

/// What the app has left to say, given everything the rules report on every file change.
///
/// The rules are stateless: they answer "what is crossed right now", and they answer it again
/// for the same session a second later when the file changes again. This is the piece that
/// turns that into notifications — it decides what is news, which is two decisions:
///
/// - **Scope.** A mark is news once per the thing that has to end before it can be news again:
///   a session for a context mark, a limit window for a limit mark, one wait for a request to
///   the person. `/clear` starts a new session file with a new identifier, a limit window ends
///   at its reset time, and a wait ends when it is answered — so every scope ends by itself and
///   nothing here has to watch for any of those events.
/// - **The first pass.** The app is started at login and finds whatever the day has already
///   spent. Announcing that backlog would teach the user to dismiss the notification that
///   matters — the one that arrives the moment a mark is crossed with the app watching — so
///   the first pass is recorded silently. The panel shows the state either way.
///
/// A session that falls off the active list is forgotten, so the memory stays the size of what
/// is running. Coming back to it after it went idle may repeat a mark; that is the cost of not
/// remembering every session the machine has ever had, and it says something true.
///
/// Usage:
/// ```swift
/// var dispatch = AlertDispatch()
/// let toNotify = dispatch.pending(limits: limitAssessments, sessions: contextAssessments)
/// ```
public struct AlertDispatch: Sendable {
    private var memory = AlertMemory()
    private var recorded = false

    public init() {}

    /// The alerts that have not been announced yet, in the order they should be shown: limits
    /// first, then sessions, lower marks before higher ones.
    public mutating func pending(
        limits: [LimitsAssessment],
        sessions: [ContextAssessment]
    ) -> [BudgetAlert] {
        var grouped: [(scope: String, alerts: [BudgetAlert])] = []
        for assessment in limits {
            for alert in assessment.alerts {
                append(alert, to: &grouped, scope: Self.scope(ofLimit: alert))
            }
        }
        // A subagent's marks are read in the panel and announced nowhere. The rule lives here
        // rather than in the caller so that it holds for every caller: an agent runs for
        // minutes and ends by itself, and interrupting someone over a window that is about to
        // close is noise they cannot act on.
        let ofSessions = sessions.filter { !$0.isSubagent }
        for assessment in ofSessions {
            for alert in assessment.alerts {
                append(alert, to: &grouped, scope: Self.scope(of: alert, in: assessment.sessionID))
            }
        }

        // Scopes come from what is on screen, not from what was delivered: a session with
        // nothing crossed still has to keep its memory, or the first mark it crosses would
        // look like a scope nobody had seen before.
        var live = Set(ofSessions.map { AlertScope.session($0.sessionID) })
        live.formUnion(grouped.map(\.scope))
        memory.retain(scopes: live)

        var fresh: [BudgetAlert] = []
        for group in grouped {
            let undelivered = memory.undelivered(group.alerts, scope: group.scope)
            if recorded { fresh.append(contentsOf: Self.collapsingLowerMarks(undelivered)) }
        }
        recorded = true
        return fresh
    }

    /// Whether this mark has already been announced for this session. For tests and for the
    /// panel; the decision itself is `pending`.
    public func remembers(_ kind: BudgetAlert.Kind, session: String) -> Bool {
        memory.hasDelivered(kind, scope: AlertScope.session(session))
    }

    private func append(
        _ alert: BudgetAlert,
        to grouped: inout [(scope: String, alerts: [BudgetAlert])],
        scope: String
    ) {
        if let index = grouped.firstIndex(where: { $0.scope == scope }) {
            grouped[index].alerts.append(alert)
        } else {
            grouped.append((scope, [alert]))
        }
    }

    /// Two marks of the same measurement crossed between one read and the next are one event.
    ///
    /// A session that goes from 48% to 80% of its window has passed both marks, and saying so
    /// twice in the same second is two notifications that differ in one word. Only the higher
    /// one is shown; the lower one is remembered as delivered all the same, so it never
    /// arrives later as news.
    private static func collapsingLowerMarks(_ alerts: [BudgetAlert]) -> [BudgetAlert] {
        var highest: [String: Double] = [:]
        for alert in alerts {
            guard let (measurement, mark) = Self.measurement(of: alert) else { continue }
            highest[measurement] = max(highest[measurement] ?? mark, mark)
        }
        return alerts.filter { alert in
            guard let (measurement, mark) = Self.measurement(of: alert) else { return true }
            return highest[measurement] == mark
        }
    }

    /// What an alert measures, and the mark it crossed — `nil` for a kind that has only one
    /// mark and so can never collapse with anything.
    private static func measurement(of alert: BudgetAlert) -> (String, Double)? {
        switch alert.kind {
        case .windowFill(let mark):
            ("window:\(alert.service.rawValue)", mark)
        case .limitUsage(let window, let mark):
            ("limit:\(alert.service.rawValue):\(window.rawValue)", mark)
        case .attention:
            nil
        }
    }

    /// The scope one session's alert is remembered in: the session, or — for a request to the
    /// person — the wait it belongs to. A wait ends by itself, which is what lets the next
    /// request in the same session be announced without anything watching for the answer.
    private static func scope(of alert: BudgetAlert, in sessionID: String) -> String {
        guard case .attention = alert.kind, let request = alert.request else {
            return AlertScope.session(sessionID)
        }
        return AlertScope.asking(session: sessionID, since: request.since)
    }

    private static func scope(ofLimit alert: BudgetAlert) -> String {
        guard case .limitUsage(let window, _) = alert.kind else {
            return AlertScope.session("unscoped")
        }
        return AlertScope.limitWindow(service: alert.service, kind: window, resetsAt: alert.resetsAt)
    }
}
