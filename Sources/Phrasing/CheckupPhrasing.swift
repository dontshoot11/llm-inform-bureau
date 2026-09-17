import Foundation
import SessionHealthCore

/// One line of the checkup: what it is, what this machine says about it, why the app wants it,
/// and where the answer is kept.
public struct CheckupRow: Equatable, Sendable {
    public let point: CheckupState.Point
    /// What this is, named after what it gives rather than after the file or the API behind it.
    public let title: String
    public let standing: CheckupState.Standing
    /// Why the app wants this and what it means that the machine answers as it does — one
    /// piece of text, because a reader who is told the state without the cost has been told
    /// nothing they can act on.
    public let detail: String
    /// The pane of System Settings where this answer is kept, for the rows that have one. The
    /// app opens it; the person answers in it.
    public let settings: SystemSettingsPane?

    public init(
        point: CheckupState.Point,
        title: String,
        standing: CheckupState.Standing,
        detail: String,
        settings: SystemSettingsPane? = nil
    ) {
        self.point = point
        self.title = title
        self.standing = standing
        self.detail = detail
        self.settings = settings
    }
}

/// What the settings window says about everything the app depends on.
///
/// The list exists because the app is only as good as what this Mac has given it, and every one
/// of those things fails quietly: a click raises the wrong window, a notification never comes,
/// "Claude" stands with an em dash. None of that looks like a missing permission — it looks
/// like a broken widget. So each line says the same three things in the same order: what it is,
/// what the machine says, and what it costs while the answer is no.
///
/// The three sources keep their own wording (`Briefing.items`): they were the half of this list
/// that already existed, and a source is explained by where it is read from rather than by what
/// it is allowed to do.
public enum CheckupPhrasing {
    /// The name over the list. Not "where the numbers come from" any more — that is three of
    /// its eight lines, and the rest are about what the app was allowed to do.
    public static let title = "What it uses on this Mac"

    public static let intro = """
        Everything is read from files this Mac already has. The app makes no network calls and \
        holds no credentials. It keeps its own files in Application Support, and the one thing \
        it writes anywhere else is a single key in ~/.claude/settings.json — only if you \
        connect the limits, and never without showing the change first.
        """

    /// Said at the end, because the alternative — a zero — is what every other widget shows
    /// for something it does not know.
    public static let closing = """
        Until a source has reported, the panel says what it does not know rather than showing \
        it as zero.
        """

    /// The whole list, in the order `CheckupState.Point` declares: what it reads, then what it
    /// was allowed to do, then what it is.
    public static func rows(for state: CheckupState) -> [CheckupRow] {
        let sources = Briefing.items(for: state.sources)
        return CheckupState.Point.allCases.map { point in
            let standing = state.standing(of: point)
            if let source = point.source, let item = sources.first(where: { $0.source == source }) {
                return CheckupRow(point: point, title: item.title, standing: standing, detail: item.detail)
            }
            switch point {
            case .claudeLimits, .claudeSessions, .codex:
                // Unreachable while every source has an item, and not worth a crash if a
                // source is ever added to one enum and not the other.
                return CheckupRow(point: point, title: point.rawValue, standing: standing, detail: "")
            case .statusLineSlot:
                return CheckupRow(
                    point: point,
                    title: "Claude Code's status line slot",
                    standing: standing,
                    detail: slotDetail(state.slot)
                )
            case .accessibility:
                return CheckupRow(
                    point: point,
                    title: "Allowed in Accessibility",
                    standing: standing,
                    detail: accessibilityDetail(state),
                    // Only while the answer is no. A button offering to open the pane where a
                    // permission already given is kept is a control with nothing to do, and
                    // this list is long enough without them.
                    settings: standing == .given ? nil : .accessibility
                )
            case .notifications:
                return CheckupRow(
                    point: point,
                    title: "Notifications",
                    standing: standing,
                    detail: notificationDetail(state.notifications),
                    // Nothing to open before the first notification: which name to look for
                    // there is exactly what has not been settled yet.
                    settings: state.notifications == nil ? nil : .notifications
                )
            case .openAtLogin:
                return CheckupRow(
                    point: point,
                    title: openAtLogin,
                    standing: standing,
                    detail: """
                        The widget says nothing while it is not running, and nothing else \
                        starts it. What gets registered is the copy below, so it belongs where \
                        you mean to keep it before this is ticked.
                        """
                )
            case .runningCopy:
                return CheckupRow(
                    point: point,
                    title: "The copy that is running",
                    standing: standing,
                    detail: copyDetail(state.copy)
                )
            }
        }
    }

    /// The label on the one control in this list that is a control rather than a reading. Said
    /// here so the checkbox and the line naming it cannot come to disagree.
    public static let openAtLogin = "Open at login"

    /// Said where a login item cannot be offered at all, with the reason the system gave.
    public static func openAtLoginUnavailable(_ why: String) -> String {
        "\(openAtLogin): \(why)"
    }

    /// What the app needs the slot for, and what is in it. The same sentence about where the
    /// limits come from on every branch: it is the reason the row exists, and a reader whose
    /// slot is held by somebody else needs it as much as one whose slot is empty.
    private static func slotDetail(_ slot: StatusLineSlotState) -> String {
        let why = """
            Claude hands its subscription limits and the size of its context window to its \
            status line command and to nothing else.
            """
        switch slot {
        case .ours:
            return """
                \(why) This app is in the slot, which is how they arrive at all — and whatever \
                command you had before is still called underneath, with the same payload.
                """
        case .oursElsewhere:
            return """
                \(why) The slot holds this app's own command from another copy of it — a \
                script an earlier version installed, or the same app in another place. The \
                limits do arrive; the panel offers to let the copy you are running do the job \
                itself.
                """
        case .free:
            return """
                \(why) Nothing is in the slot, so there are no limits to show. Press \
                \(Briefing.connectAction).
                """
        case .somebodyElse(let command):
            return """
                \(why) Your own command is in the slot: \(command). The app joins it rather \
                than replacing it — press \(Briefing.connectAction), and what is there goes on \
                being called with the same payload.
                """
        case .unreadable(let path):
            return "\(why) \(SlotPhrasing.unreadable(path))"
        }
    }

    private static func accessibilityDetail(_ state: CheckupState) -> String {
        let why = """
            A click on a session brings up the window it is running in, and telling one of a \
            terminal's four windows from another means looking through them.
            """
        if state.isAccessibilityTrusted {
            return "\(why) Given, so a click lands on the window titled after the session's project."
        }
        let missing = """
            \(why) Not given, so what comes up is whichever window you used last. The answer \
            is kept under Privacy & Security → Accessibility.
            """
        return state.copy.isAdHoc ? "\(missing) \(Wording.tickFromAnEarlierBuild)" : missing
    }

    /// What a notification is for, and whose name it will arrive under.
    ///
    /// No tick before the first one has been sent, and that is not a gap in the reading: the
    /// channel is chosen at the first notification, because asking for permission before there
    /// is anything to say is how an app gets refused.
    private static func notificationDetail(_ channel: NotificationChannel?) -> String {
        let why = """
            A crossed mark is said once, quietly, while you are looking at something else.
            """
        switch channel {
        case nil:
            return """
                \(why) Which channel that goes out over is settled at the first notification: \
                signed the way this copy is, the notification centre can refuse the app \
                outright, and it then sends them through osascript instead.
                """
        case .ownName:
            return "\(why) Sent through the notification centre, under this app's own name."
        case .scriptEditor:
            return """
                \(why) The notification centre refused this copy, so they are sent through \
                osascript and the system credits them to Script Editor — that is the name to \
                look for in Notification settings if none of them arrive.
                """
        }
    }

    /// Which bundle is in the menu bar, said in the two facts that tell two copies of the same
    /// name apart: where it is and when it was built.
    private static func copyDetail(_ copy: RunningCopy) -> String {
        var lines = [copy.path]
        lines.append(copy.builtAt.map { "Built \(TimeDisplay.moment($0))." } ?? "Built: the date could not be read.")
        if copy.isAdHoc {
            lines.append("""
                Signed ad-hoc: to the system every build of it is a different app, so a \
                permission given to the copy before this one stays ticked in System Settings \
                and grants nothing.
                """)
        }
        return lines.joined(separator: "\n")
    }
}
