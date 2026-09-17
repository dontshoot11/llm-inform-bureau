import Foundation

/// The one line of AppleScript a notification goes out over when the notification centre will
/// not take it from this app directly.
///
/// Here rather than beside the notifier for the reason `TerminalRaise.script` is here: a script
/// is a string with a grammar, the grammar is where the mistakes are, and a string built in the
/// app target is a string no test can reach. What it produces is checked in the suite —
/// including the escaping, which is the whole of what stands between a quotation mark in
/// somebody's question and a script that will not parse.
///
/// It takes the two words already said. Which language they are in was decided where they were
/// drawn; this knows only that they are text going into a script.
public enum NotificationScript {
    /// `display notification` without `sound name` is silent, which is what makes this a usable
    /// fallback rather than a worse one.
    public static func display(title: String, body: String) -> String {
        "display notification \(quoted(body)) with title \(quoted(title))"
    }

    /// An AppleScript string literal.
    ///
    /// The body carries a slash command and a line break, so this is not decoration. Cyrillic
    /// needs nothing added to it: the argument leaves the process as UTF-8 and an AppleScript
    /// string takes it as it is — what the escaping is for is the quote, the backslash and the
    /// newline, in either language.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
