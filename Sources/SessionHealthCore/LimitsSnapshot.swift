import Foundation

/// One subscription limit window and how much of it is spent.
public struct LimitWindow: Equatable, Sendable {
    /// Both services meter two windows: a short rolling one and a weekly one. The names
    /// differ (Codex calls them primary and secondary, Claude five-hour and seven-day),
    /// the meaning does not.
    public enum Kind: String, Equatable, Hashable, Sendable {
        case short
        case weekly
    }

    public let kind: Kind

    /// Share of the window already spent, 0...100.
    public let usedPercent: Double

    /// When the window rolls over, or `nil` when the source did not say.
    public let resetsAt: Date?

    /// Length of the window in minutes, when the source reports it. Codex does, Claude
    /// names its windows instead.
    public let windowMinutes: Int?

    /// Length of the window in minutes, falling back to what the window is called when the
    /// source did not report one: both services meter a five-hour window and a weekly one,
    /// and Claude names its windows instead of measuring them.
    public var nominalMinutes: Int {
        windowMinutes ?? (kind == .short ? 5 * 60 : 7 * 24 * 60)
    }

    public init(kind: Kind, usedPercent: Double, resetsAt: Date?, windowMinutes: Int? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }
}

/// The subscription limits of one service, as of the last time the service reported them.
///
/// The numbers are a snapshot taken at the service's last API call, not a live reading:
/// `observedAt` is how the interface shows their age instead of pretending they are current.
public struct LimitsSnapshot: Equatable, Sendable {
    public let service: AgentService

    /// When the service reported these numbers.
    public let observedAt: Date

    public let windows: [LimitWindow]

    /// Subscription plan the service named, e.g. `plus`. `nil` when it did not say.
    public let planType: String?

    public init(service: AgentService, observedAt: Date, windows: [LimitWindow], planType: String? = nil) {
        self.service = service
        self.observedAt = observedAt
        self.windows = windows
        self.planType = planType
    }

    public func window(_ kind: LimitWindow.Kind) -> LimitWindow? {
        windows.first { $0.kind == kind }
    }

    /// The most spent window — the one number the menu bar has room for.
    public var worstUsedPercent: Double? {
        windows.map(\.usedPercent).max()
    }
}
