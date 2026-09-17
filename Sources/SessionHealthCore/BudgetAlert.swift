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

/// Something found worth interrupting the person for — the unit the notification rule works
/// with.
///
/// Mostly a threshold found crossed, and one case that is not a threshold at all: an agent
/// that has been standing still waiting on the person for longer than the configured delay.
/// It rides here rather than beside here because everything that makes a crossed mark bearable
/// is what it needs too — one event announced once, nothing announced about the backlog found
/// at launch, nothing announced on behalf of a subagent — and a second road to the same
/// notification centre would have to grow all three again.
///
/// An alert is a fact and its numbers, never a sentence: the wording lives in the layer that
/// delivers notifications, so the rules stay testable without reading English.
public struct BudgetAlert: Equatable, Sendable {
    /// What happened. This is also the identity the alert memory remembers, which is why
    /// the crossed mark is part of it: 50% and 75% of the same window are two different
    /// events and each deserves its own notification.
    public enum Kind: Equatable, Hashable, Sendable {
        /// Share of the context window in use crossed a configured mark.
        case windowFill(percent: Double)

        /// A subscription limit window crossed a configured mark.
        case limitUsage(window: LimitWindow.Kind, percent: Double)

        /// The agent has been waiting on the person for longer than
        /// `sessions.attention_notice_after_minutes`.
        ///
        /// Carries nothing, unlike the two above, and that is deliberate: what distinguishes
        /// one wait from the next is the moment it began, and the moment is the alert's
        /// *scope* (`AlertScope.asking`) rather than its identity. Putting it in the identity
        /// would work as well until the day something rephrases a question mid-wait, and then
        /// every rewording would arrive as a second notification.
        case attention
    }

    /// What the agent is waiting on the person for. Set on `.attention` alerts and on nothing
    /// else — the numbers below are the other kinds' equivalent.
    public struct Request: Equatable, Sendable {
        /// When the agent stopped and started waiting. What scopes the alert: one wait is
        /// announced once however long it lasts, and the next wait in the same session is a
        /// new scope and is announced again.
        public let since: Date

        /// The project whose session is waiting, as the panel names it — so that the person
        /// reading the notification can find the row it is about.
        public let project: String?

        /// What was asked, in the agent's own words, or `nil` when the transcript does not
        /// carry it. A notification that cannot say what about still says who is waiting.
        public let about: String?

        public init(since: Date, project: String?, about: String?) {
            self.since = since
            self.project = project
            self.about = about
        }
    }

    public let kind: Kind
    public let service: AgentService

    /// The measured percentage behind the alert — window fill, or the spent share of a limit.
    public let percent: Double?

    /// The measured token count behind the alert — context held, or the growth of one turn.
    public let tokens: Int?

    /// When the limit window resets. Limit alerts only.
    public let resetsAt: Date?

    /// What the agent is waiting on the person for. Attention alerts only.
    public let request: Request?

    public init(
        kind: Kind,
        service: AgentService,
        percent: Double? = nil,
        tokens: Int? = nil,
        resetsAt: Date? = nil,
        request: Request? = nil
    ) {
        self.kind = kind
        self.service = service
        self.percent = percent
        self.tokens = tokens
        self.resetsAt = resetsAt
        self.request = request
    }
}
