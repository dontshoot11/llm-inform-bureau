import Foundation

/// The one way this app reads a written moment.
///
/// Both agents stamp their lines in ISO 8601, and both files are asked what time the last
/// thing in them happened — Codex for when a limits reading was taken, Claude for how long a
/// turn has owed an answer. One reader's idea of a timestamp is not worth having twice.
///
/// Fractional seconds first, whole seconds after. Every timestamp written by either CLI on
/// this machine carries them, and that is exactly why the second attempt is here: a parser
/// that insisted would quietly read a line as timeless the day the format loosened, and a
/// moment that cannot be read falls back to the file's own date, which says something else.
///
/// The formatter is made per call rather than kept. `ISO8601DateFormatter` is not `Sendable`,
/// and the reads happen off the main actor; a shared one would be a mutable global reached
/// from all of them. It is made once per file per pass, not once per line.
enum Timestamps {
    static func date(fromISO8601 text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
