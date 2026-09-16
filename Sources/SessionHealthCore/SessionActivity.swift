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

    /// How long a wait may go silent before it stops being one an answer is expected out of.
    public let waitSilence: DurationThreshold

    public init(window: DurationThreshold, waitSilence: DurationThreshold) {
        self.window = window
        self.waitSilence = waitSilence
    }

    public init(config: ThresholdConfig) {
        self.init(window: config.sessionActivity, waitSilence: config.abandonedWait)
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

    /// What a session whose agent owed an answer at this moment is waiting for now — the fuse
    /// under the blinking light, and what the light does once it blows.
    ///
    /// Nothing on disk says a session died. A terminal closed mid-turn, a killed process and
    /// an agent hard at work look identical: an entry that owes an answer and no entry after
    /// it. What separates them is how long that has been true, and only that. Measured over
    /// 73,344 waits that did end: half were answered in 2.4 seconds, 99% within 48, and 25 of
    /// them — 0.03% — took longer than the configured ten minutes. So the blink outlives one
    /// wait in three thousand that was real, and stops blinking about the ones that were not:
    /// 34 transcripts on this machine owe an answer that will never come.
    ///
    /// The moment is the last entry of the conversation, not the file's date: measured, a
    /// transcript's modification date runs ahead of the last thing said in it by a median of
    /// 96 seconds and, in 87 files of 385, by more than ten minutes — housekeeping and
    /// rewrites keep touching a file long after the conversation in it stopped.
    ///
    /// Past the fuse the wait is not dropped, it is `.stalled`: an answer is still owed, and
    /// saying so with a sign of its own is the honest reading — the app cannot tell an agent
    /// thinking hard from a session that died, and a light that went plain steady would claim
    /// it could. What ends a stall is an answer arriving, or the row itself going.
    ///
    /// This decides the light alone. Whether the session is listed at all is `isActive` above,
    /// and it keeps its own half hour: a session that has gone quiet is still a session being
    /// worked on, it is just not one anybody is waiting on.
    public func replyWait(since: Date?, now: Date = Date()) -> ReplyWait {
        guard let since else { return .none }
        let silence = now.timeIntervalSince(since)
        // An entry written in the future — a clock that moved, a copied file — is not stale.
        guard silence > 0 else { return .waiting }
        return silence <= waitSilence.seconds ? .waiting : .stalled
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
