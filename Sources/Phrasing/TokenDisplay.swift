import Foundation

/// Token counts as the panel says them.
///
/// Rounded to thousands, because the difference between 121 300 and 121 800 tokens is not a
/// difference anyone acts on, and the full number costs the line its readability.
///
/// The one file in this target whose output has no sides, and deliberately: `121K`, `+4K` and
/// `62%` are digits with a suffix, and the suffixes are read the same by both of this app's
/// readers. Giving them a Russian side would mean inventing `121К` in Cyrillic — a character
/// that looks like the one it replaces, does not paste back into anything, and would be the
/// only place in the app where a number is spelled differently depending on who is looking.
/// The nouns that stand next to these numbers are phrases; the numbers themselves are not.
public enum TokenDisplay {
    public static func short(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            return millions >= 10 ? "\(Int(millions.rounded()))M" : String(format: "%.1fM", millions)
        }
        if tokens >= 1_000 { return "\(Int((Double(tokens) / 1000).rounded()))K" }
        return "\(tokens)"
    }

    /// Growth over a turn, always signed: the point is the change, not the total.
    public static func growth(_ tokens: Int) -> String {
        "+\(short(tokens))"
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
