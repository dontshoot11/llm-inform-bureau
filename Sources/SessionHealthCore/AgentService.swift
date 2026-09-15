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

    /// Label for the menu bar, where the budget is pixels.
    public var shortLabel: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}
