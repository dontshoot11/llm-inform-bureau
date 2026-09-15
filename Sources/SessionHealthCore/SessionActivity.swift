import Foundation

/// Which sessions count as the ones being worked on right now.
///
/// The widget has room for a handful of lines, and a machine that has run these CLIs for a
/// while holds hundreds of session files. Almost all of them were last written to hours or
/// days ago and the few being worked on were written to minutes ago, so the cut is not a
/// delicate number: anything in that gap separates the same sessions. The configured default
/// is not measured, and `Thresholds.md` says so — it is the number to change if sessions that
/// are running drop off the list, or finished ones linger on it.
///
/// Usage:
/// ```swift
/// let activity = SessionActivity(config: load.config)
/// let visible = activity.active(sessions, now: Date())
/// ```
public struct SessionActivity: Sendable {
    public let window: DurationThreshold

    public init(window: DurationThreshold) {
        self.window = window
    }

    public init(config: ThresholdConfig) {
        self.init(window: config.sessionActivity)
    }

    /// Whether a session last written to at this moment is still being worked on.
    ///
    /// Inclusive at the mark, unlike the budget thresholds: those ask "has this gone past a
    /// line", this one asks "is this still within reach", and exactly at the edge it is.
    public func isActive(lastActivityAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(lastActivityAt)
        // A file written in the future — a clock that moved, a copied file — is not stale.
        guard age > 0 else { return true }
        return age <= window.seconds
    }

    /// The readings still worth showing, freshest first — sessions and the subagents running
    /// inside them.
    ///
    /// Ordering is part of the rule: the menu shows the session being worked on right now at
    /// the top. So is the second rule here — a subagent does not outlive its session. It is
    /// shown nested under it, and a nested row whose parent has gone quiet is a row with
    /// nothing above it to say whose work it was.
    public func active(_ sessions: [SessionSnapshot], now: Date = Date()) -> [SessionSnapshot] {
        let live = sessions
            .filter { isActive(lastActivityAt: $0.lastActivityAt, now: now) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        let sessionIDs = Set(live.filter { !$0.isSubagent }.map(\.sessionID))
        return live.filter { snapshot in
            guard let origin = snapshot.subagent else { return true }
            return sessionIDs.contains(origin.parentSessionID)
        }
    }
}
