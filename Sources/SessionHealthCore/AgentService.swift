import Foundation

/// A coding agent whose usage this app watches.
///
/// The two services are not symmetric in what they report — Codex names the length of a limit
/// window and Claude names the window instead, Claude hands its limits to a status line and
/// writes them nowhere — but they are judged by the same marks. Every mark is a share of a
/// window, and a share means the same thing on either side.
public enum AgentService: String, CaseIterable, Sendable {
    case claude
    case codex

    /// What this service is called wherever there is room to say it: the panel, and the title
    /// of a notification.
    public var shortLabel: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// What it is called in the menu bar, where the budget is pixels and nothing else.
    ///
    /// Three letters rather than the name because the bar is shared with every other app on
    /// the Mac, and when it runs out of room macOS stops drawing status items — this one
    /// included. Measured at the bar's own font: the pair of names costs 123.7 pt drawn, the
    /// pair of abbreviations 83.2 pt, so a third of the width goes back to staying visible.
    ///
    /// Deliberately not the same property as `shortLabel`. That one drifted from the bar into
    /// the panel and into notification titles, where the room exists and "CLD" would only read
    /// as a typo.
    public var barLabel: String {
        switch self {
        case .claude: "CLD"
        case .codex: "CDX"
        }
    }
}
