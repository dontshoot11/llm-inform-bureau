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
    /// This app's own command, from a copy that is not this one: the shell wrapper an earlier
    /// release installed, or the same binary somewhere else on disk — a build directory, a
    /// previous location, an older bundle. What it names is a leftover of an install that has
    /// moved on, and the command the person had before this app is saved underneath it.
    /// Replacing it is the app taking over its own job.
    ///
    /// It is not `somebodyElse`, and the difference is the whole reason the case exists. Every
    /// copy of this app saves the displaced command in the same file, so saving one copy's
    /// command as "what was here before" would have the app calling itself, reading that same
    /// file, and calling itself again — without end.
    case oursElsewhere
    /// Somebody else's command, quoted as it is written in the file. Connecting saves it and
    /// keeps calling it.
    case somebodyElse(String)
    /// `settings.json` is there and does not parse. Nothing is written to a file this app
    /// cannot read: the alternative is replacing somebody's configuration with a guess.
    case unreadable(String)

    public var isOurs: Bool { self == .ours }

    /// Whether the app has something to offer *in place of a reading* — which is what decides
    /// whether the panel shows a button where the limits would be.
    ///
    /// Another copy of this app is not one of these, and that is the distinction: while that
    /// copy is there it is feeding the panel real numbers, and a button standing where they
    /// should be would be hiding a working reading behind an offer. What it gets instead is
    /// `needsTakingOver` — an offer underneath the numbers rather than instead of them.
    public var isConnectable: Bool {
        switch self {
        case .free, .somebodyElse: true
        case .ours, .oursElsewhere, .unreadable: false
        }
    }

    /// Whether what is in the slot is this app's own work done the old way, so the offer is to
    /// take it over rather than to connect something that is missing.
    public var needsTakingOver: Bool { self == .oursElsewhere }
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

    /// `true` when what is being replaced is this app's own command from another copy — the
    /// shell wrapper an earlier release installed, or the same binary elsewhere on disk. The
    /// preview has to say so: on this branch nothing of the person's is being displaced — it
    /// was displaced once already, and what is saved underneath stays exactly where it is.
    public let replacesEarlierCopy: Bool

    public init(
        kind: Kind,
        settingsPath: String,
        command: String?,
        keptUnderneath: String? = nil,
        replacesEarlierCopy: Bool = false
    ) {
        self.kind = kind
        self.settingsPath = settingsPath
        self.command = command
        self.keptUnderneath = keptUnderneath
        self.replacesEarlierCopy = replacesEarlierCopy
    }
}
