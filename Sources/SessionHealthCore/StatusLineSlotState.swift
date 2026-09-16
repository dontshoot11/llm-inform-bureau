import Foundation

/// What is in Claude Code's one status line slot.
///
/// The slot is the only way the subscription limits and the size of the context window can be
/// seen on this machine, and it holds exactly one command. So the question is never "is it
/// on", it is "whose is it" — and the rule of this project is that somebody else's command
/// survives being joined.
///
/// Facts only: reading `settings.json` is `AgentFiles`', the English is `Phrasing`'s.
public enum StatusLineSlotState: Equatable, Sendable {
    /// No status line is configured at all. Taking the slot takes nothing away.
    case free
    /// This app's command is in it, which is the only way limits ever arrive.
    case ours
    /// Somebody else's command, quoted as it is written in the file. Connecting saves it and
    /// keeps calling it.
    case somebodyElse(String)
    /// `settings.json` is there and does not parse. Nothing is written to a file this app
    /// cannot read: the alternative is replacing somebody's configuration with a guess.
    case unreadable(String)

    public var isOurs: Bool { self == .ours }

    /// Whether the app has something to offer here — which is what decides whether the panel
    /// shows a button in place of the limits.
    public var isConnectable: Bool {
        switch self {
        case .free, .somebodyElse: true
        case .ours, .unreadable: false
        }
    }
}

/// What pressing the button would do to `settings.json`, before anything is written.
///
/// A change is shown and then applied, never applied and then reported. The file belongs to
/// the user, holds far more than this one key, and this app is the only thing in the project
/// that writes to it — so the one honest order is: say what will change, and change it only
/// if asked again.
public struct StatusLineChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case connect
        case disconnect
    }

    public let kind: Kind

    /// The file being edited, as a path a person can go and look at.
    public let settingsPath: String

    /// What `statusLine.command` will hold afterwards. `nil` means the key is removed, which
    /// is what disconnecting does when there was nothing in the slot before this app.
    public let command: String?

    /// The command that stays underneath ours and goes on being called with the same payload.
    /// Connecting only, and `nil` when the slot was free.
    public let keptUnderneath: String?

    public init(
        kind: Kind,
        settingsPath: String,
        command: String?,
        keptUnderneath: String? = nil
    ) {
        self.kind = kind
        self.settingsPath = settingsPath
        self.command = command
        self.keptUnderneath = keptUnderneath
    }
}
