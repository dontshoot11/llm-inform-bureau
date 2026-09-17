import Foundation

/// The scopes an alert can be remembered in.
///
/// A scope is "the thing that has to end before this may be said again". For context alerts
/// that is the session: `/clear` starts a new session file with a new identifier, so the
/// memory resets by itself and the same mark may fire again in the new session. For limit
/// alerts it is the window: once it rolls over, its usage is a new story. For a request to the
/// person it is the wait itself.
public enum AlertScope {
    public static func session(_ sessionID: String) -> String {
        "session:\(sessionID)"
    }

    /// One wait of one session, named by the moment it began.
    ///
    /// The moment is what makes this a scope rather than a mark on the session: the person
    /// answers, the agent asks again, and the new wait has a moment of its own and is
    /// announced again — with nothing counting anything and nothing having to notice the
    /// answer. It ends the way a wait ends: once the request is over the scope stops being
    /// reported, and what was delivered under it is forgotten with it.
    public static func asking(session: String, since: Date) -> String {
        "asking:\(session):\(Int(since.timeIntervalSince1970))"
    }

    public static func limitWindow(
        service: AgentService,
        kind: LimitWindow.Kind,
        resetsAt: Date?
    ) -> String {
        let reset = resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown-reset"
        return "limit:\(service.rawValue):\(kind.rawValue):\(reset)"
    }
}

/// Remembers which alerts have already been delivered, so a mark that stays crossed does not
/// notify on every refresh.
///
/// The rules run on every file change and report everything currently crossed; this is what
/// turns that stream into "one mark, one notification".
///
/// Usage:
/// ```swift
/// var memory = AlertMemory()
/// let assessment = rules.assess(snapshot)
/// let toDeliver = memory.undelivered(assessment.alerts, scope: AlertScope.session(snapshot.sessionID))
/// ```
public struct AlertMemory: Equatable, Sendable {
    private var delivered: [String: Set<BudgetAlert.Kind>] = [:]

    public init() {}

    /// The alerts of this scope that have not been delivered before, recording them as
    /// delivered. Order is preserved, so a session that jumps past two marks at once reports
    /// the lower one first.
    public mutating func undelivered(_ alerts: [BudgetAlert], scope: String) -> [BudgetAlert] {
        var known = delivered[scope] ?? []
        var fresh: [BudgetAlert] = []
        for alert in alerts where known.insert(alert.kind).inserted {
            fresh.append(alert)
        }
        delivered[scope] = known
        return fresh
    }

    public func hasDelivered(_ kind: BudgetAlert.Kind, scope: String) -> Bool {
        delivered[scope]?.contains(kind) ?? false
    }

    /// Forgets everything outside these scopes — sessions that ended, limit windows that
    /// rolled over. Keeps the memory from growing for the lifetime of the app.
    public mutating func retain(scopes: Set<String>) {
        delivered = delivered.filter { scopes.contains($0.key) }
    }
}
