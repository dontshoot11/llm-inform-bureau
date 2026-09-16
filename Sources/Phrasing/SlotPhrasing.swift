import Foundation
import SessionHealthCore

/// What the panel puts in front of somebody before it edits their `settings.json`.
///
/// One screen of text, and the order of it is the point: the file being changed, the line
/// going into it, and then what that does to what they already had. A person who does not read
/// past the first line has still seen which file this is about.
public struct SlotPreview: Equatable, Sendable {
    public let title: String
    /// The file, as a path to go and look at.
    public let path: String
    /// The line that will be in the slot afterwards, set in the font it is written in. `nil`
    /// when the key is being removed and nothing takes its place.
    public let command: String?
    /// What this does to what was there, and what it costs. Sentences, in the order they
    /// matter.
    public let notes: [String]

    public init(title: String, path: String, command: String?, notes: [String]) {
        self.title = title
        self.path = path
        self.command = command
        self.notes = notes
    }
}

/// The English for taking Claude Code's status line slot and giving it back.
public enum SlotPhrasing {
    /// The button that stands where the limits would be. Named for what it produces rather
    /// than for what it does to a config file: the person is looking at an empty reading.
    public static let connect = "Connect limits"

    public static let connectHelp = """
        Claude hands its subscription limits and the size of its context window to its status \
        line command and to nothing else. This puts the app in that slot — and keeps calling \
        whatever was there before.
        """

    public static let disconnectHelp = "Disconnect: put back the status line that was there before"

    /// Said on the two buttons of the preview. "Write it" rather than "OK": the whole reason
    /// the preview exists is that the next click edits a file.
    public static let apply = "Write it"
    public static let cancel = "Cancel"

    public static func preview(_ change: StatusLineChange) -> SlotPreview {
        switch change.kind {
        case .connect:
            return SlotPreview(
                title: "This will set statusLine.command in",
                path: change.settingsPath,
                command: change.command,
                notes: connectNotes(change)
            )
        case .disconnect:
            return SlotPreview(
                title: change.command == nil
                    ? "This will remove statusLine from"
                    : "This will set statusLine.command back in",
                path: change.settingsPath,
                command: change.command,
                notes: [keptCopy]
            )
        }
    }

    private static func connectNotes(_ change: StatusLineChange) -> [String] {
        guard let existing = change.keptUnderneath else {
            return [
                """
                No status line is configured now, so nothing of yours is being replaced. The \
                app will print a short line of its own: model, context, limits.
                """,
                """
                One thing this changes for you: with any status line configured, Claude Code \
                stops showing most footer hints, including "esc to interrupt".
                """,
                keptCopy
            ]
        }
        return [
            """
            Your status line command is kept. It will be called with the same payload and its \
            output printed unchanged:
            """,
            existing,
            keptCopy
        ]
    }

    /// Said on every branch that writes, because it is the answer to the question the preview
    /// raises.
    private static let keptCopy = "A copy of the file is kept beside it first."

    /// Said when the file cannot be read, in place of the button. Nothing is written to a file
    /// this app does not understand, and the person is the only one who can say what is in it.
    public static func unreadable(_ path: String) -> String {
        """
        \(path) is not readable as JSON, so nothing will be written to it. Fixing it is the \
        one step this app will not take on somebody's behalf.
        """
    }

    /// Said when a write did not happen. It names the file, because the next thing anybody
    /// does is go and look at it.
    public static func failed(_ reason: String) -> String {
        "Nothing was written — \(reason)"
    }
}
