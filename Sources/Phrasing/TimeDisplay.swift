import Foundation

/// Durations as the panel says them: short, and never rounded into a lie.
///
/// A reading from eleven seconds ago is "just now"; one from yesterday says the day, because
/// the age of a limit reading is the difference between "this is current" and "this is what
/// Codex thought before lunch".
public enum TimeDisplay {
    public static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 60 * 60 * 12 { return "\(compact(seconds)) ago" }
        return "on " + moment(date)
    }

    public static func until(_ date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "any moment" }
        if seconds < 60 * 60 * 24 { return "in \(compact(seconds))" }
        return "on " + moment(date)
    }

    /// A moment named outright rather than measured against now.
    ///
    /// For the one date in the app that is not an age: when the running copy was built. "Two
    /// hours ago" is the wrong shape for it — the question it answers is which of the bundles
    /// on this disk is in the menu bar, and that is settled by a date and a time, not by a gap.
    public static func moment(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The length of a limit window, as the service reports it in minutes.
    public static func windowLength(_ minutes: Int) -> String {
        if minutes % (60 * 24) == 0 { return "\(minutes / (60 * 24))d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func compact(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(max(minutes, 1))m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
