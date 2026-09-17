import Foundation

/// What nothing the app says may claim, in either language.
///
/// `AGENTS.md` draws the line: that a mark has been crossed is a fact about a mark somebody
/// placed, and a score for how good the answers have become is a measurement there is no signal
/// for anywhere this app can read. A rule that knew only English would let a Russian sentence
/// grade a session and pass — the second language is exactly where a claim like that would go
/// unnoticed, since fewer people read that side.
///
/// Matched as lower-cased substrings, and the Russian entries are stems rather than words: the
/// language inflects, and a word list would catch one ending in six.
enum QualityClaims {
    static let banned = [
        "quality:", "health", "degraded",
        "качеств", "здоровь", "деградир", "ухудшен"
    ]

    /// Which of them a piece of text says, if any.
    static func found(in text: String) -> [String] {
        let said = text.lowercased()
        return banned.filter { said.contains($0) }
    }
}
