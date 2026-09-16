import Foundation

/// How close one number is to the point where it starts to matter.
///
/// Three steps rather than two, and one scale for every light in the widget: a colour means
/// the same thing whether it sits under the limits or under the context, so nobody has to
/// remember which light counts differently.
///
/// Ordered, so the worst of several readings is `max()`.
public enum BudgetLevel: Int, Comparable, Sendable {
    case normal = 0
    /// Worth knowing, not worth interrupting for — this level never sends a notification.
    case notice = 1
    case elevated = 2
    case high = 3

    public static func < (lhs: BudgetLevel, rhs: BudgetLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A threshold found crossed — the unit the notification rule works with.
///
/// An alert is a fact and its numbers, never a sentence: the wording lives in the layer that
/// delivers notifications, so the rules stay testable without reading English.
public struct BudgetAlert: Equatable, Sendable {
    /// What was crossed. This is also the identity the alert memory remembers, which is why
    /// the crossed mark is part of it: 50% and 75% of the same window are two different
    /// events and each deserves its own notification.
    public enum Kind: Equatable, Hashable, Sendable {
        /// Share of the context window in use crossed a configured mark.
        case windowFill(percent: Double)

        /// A subscription limit window crossed a configured mark.
        case limitUsage(window: LimitWindow.Kind, percent: Double)
    }

    public let kind: Kind
    public let service: AgentService

    /// The measured percentage behind the alert — window fill, or the spent share of a limit.
    public let percent: Double?

    /// The measured token count behind the alert — context held, or the growth of one turn.
    public let tokens: Int?

    /// When the limit window resets. Limit alerts only.
    public let resetsAt: Date?

    public init(
        kind: Kind,
        service: AgentService,
        percent: Double? = nil,
        tokens: Int? = nil,
        resetsAt: Date? = nil
    ) {
        self.kind = kind
        self.service = service
        self.percent = percent
        self.tokens = tokens
        self.resetsAt = resetsAt
    }
}
