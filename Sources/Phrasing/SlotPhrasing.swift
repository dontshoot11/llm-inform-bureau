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

    /// The button for a slot held by another copy of this app — a Mac set up by the release
    /// that had an installer, or a bundle that has since moved. It stands under the limits
    /// rather than in place of them, because while that copy is there the limits are there —
    /// what is being offered is this copy doing the job itself.
    public static let takeOver = "Update the status line"

    public static let takeOverHelp = """
        Claude's limits are reaching this panel through another copy of this app — a script an \
        earlier version installed, or the same app in another place. This copy does it itself \
        now: the same numbers, nothing else on this Mac in between, and whatever command you \
        had before stays exactly where it is.
        """

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
        if change.replacesEarlierCopy { return takeOverNotes(change) }
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

    /// Taking over from another copy of this app — the shell wrapper an earlier release
    /// installed, or the same binary elsewhere on disk. Said apart from the other branches
    /// because on this one nothing of the person's is being displaced: it was displaced once,
    /// by this same app, and what was saved then is left alone now.
    private static func takeOverNotes(_ change: StatusLineChange) -> [String] {
        var notes = [
            """
            The slot holds this app's own command from another copy of it — a script an \
            earlier version installed, or the same app in another place. This puts the copy \
            you are looking at there instead: the same payload, read the same way.
            """
        ]
        if let existing = change.keptUnderneath {
            notes.append(
                """
                The status line command you had before that app is kept, exactly where it \
                already is. It goes on being called with the same payload and its output \
                printed unchanged:
                """
            )
            notes.append(existing)
        } else {
            notes.append(
                """
                Nothing of yours is saved underneath it, so nothing is being put back: the \
                app will print a short line of its own, as the script does now.
                """
            )
        }
        notes.append("The script itself is deleted once the slot is the app's.")
        notes.append(keptCopy)
        return notes
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
