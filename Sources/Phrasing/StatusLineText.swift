import Foundation
import SessionHealthCore

/// The one line the app prints when it holds Claude Code's status line slot and nothing was
/// in that slot before it.
///
/// It exists because silence is not neutral here. Configuring a status line makes Claude Code
/// drop its own hints from the bottom of the terminal, so a command that printed nothing would
/// take away a row the person had and give nothing back. What goes in it is what this app
/// watches anyway: which model is answering, how full the window is, and how much of each
/// subscription window is spent.
///
/// The words are shorter than anywhere else in the app — `5h` where the panel says `5-hour
/// limit` — because this shares one terminal row with the prompt. The numbers are not: they go
/// through `TokenDisplay` like every other number the app says, so the line and the panel
/// round the same way and cannot drift apart.
///
/// The one thing the app says that has no second language, and for a reason that is not
/// oversight. There is no prose in it: a model's name, two token counts, two percentages and
/// the two labels `5h` and `7d`. It is also the one thing the app says that nobody is looking
/// at the app for — it is printed into somebody's terminal, beside a prompt, by a command
/// Claude Code runs; the reader of that row is reading their own shell, and a row that changed
/// shape with a setting in a menu bar app would be the app redecorating a place it was let
/// into. Should a sentence ever be wanted here, it becomes a `Phrase` like every other.
public enum StatusLineText {
    /// Said instead of a model name when the payload did not carry one. Never an empty line:
    /// the status line is a row that exists whether or not there is anything to put in it.
    public static let unnamedModel = "Claude"

    public static func line(
        model: String?,
        contextTokens: Int?,
        contextWindowTokens: Int?,
        limits: LimitsSnapshot?
    ) -> String {
        var parts = [model.flatMap { $0.isEmpty ? nil : $0 } ?? unnamedModel]

        if let held = contextTokens {
            if let window = contextWindowTokens, window > 0 {
                parts.append(
                    "\(TokenDisplay.short(held))/\(TokenDisplay.short(window))"
                        + " (\(TokenDisplay.percent(Double(held) / Double(window) * 100)))"
                )
            } else {
                // The window size comes from this payload and nowhere else, so when it is
                // missing there is no share to take — the same rule the panel follows: the
                // tokens held are a fact, a percentage of an unknown window is not.
                parts.append(TokenDisplay.short(held))
            }
        }

        for window in [LimitWindow.Kind.short, .weekly] {
            guard let spent = limits?.window(window)?.usedPercent else { continue }
            parts.append("\(shortLabel(window)) \(TokenDisplay.percent(spent))")
        }

        return parts.joined(separator: " · ")
    }

    /// A limit window in as few characters as it can be named. `Wording.limitName` is the same
    /// window said in a sentence; this is the same window said in a row that is also holding a
    /// model name and a token count.
    private static func shortLabel(_ kind: LimitWindow.Kind) -> String {
        kind == .short ? "5h" : "7d"
    }
}
