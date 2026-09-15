import Foundation

/// Token counts as the panel says them.
///
/// Rounded to thousands, because the difference between 121 300 and 121 800 tokens is not a
/// difference anyone acts on, and the full number costs the line its readability.
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
