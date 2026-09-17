import Foundation

/// Which copy of the app is running, as the checkup names it.
///
/// A fact about the app rather than about anything it reads, and the one fact nothing else on
/// the machine will give a person: several copies of a bundle with the same name can sit on one
/// disk — a build directory, `/Applications`, a download — and the system's own privacy panes
/// list them all as one name with no way to tell which is which. The panel shows numbers and
/// says nothing about where it is running from, so when a permission looks given and behaves as
/// if it were not, there is nothing to check against. This is that something.
public struct RunningCopy: Equatable, Sendable {
    /// The bundle, as a path a person can go and look at.
    public let path: String

    /// When it was built. The date of the executable inside the bundle rather than a version
    /// string: `CFBundleShortVersionString` does not move from build to build, and what is
    /// being told apart here is two builds of the same version. `nil` when the file cannot be
    /// asked — a missing date is worth showing as missing, not as a guess.
    public let builtAt: Date?

    /// Whether this copy carries an ad-hoc signature, which is what decides whether a
    /// permission survives the app being replaced.
    public let isAdHoc: Bool

    public init(path: String, builtAt: Date?, isAdHoc: Bool) {
        self.path = path
        self.builtAt = builtAt
        self.isAdHoc = isAdHoc
    }
}

/// How a notification reached the screen.
///
/// Two channels because the first one is not always available: signed ad-hoc, the app is
/// refused by the notification centre outright and falls back to `osascript`, which the system
/// credits to Script Editor. Which one it will be is not knowable in advance — it is settled at
/// the first notification — so the checkup says the channel it got rather than a tick.
public enum NotificationChannel: Equatable, Sendable {
    /// The notification centre, under the app's own name and icon.
    case ownName
    /// `osascript`, which the system attributes to Script Editor.
    case scriptEditor
}

/// A pane of System Settings the app can open for somebody.
///
/// The app never answers a permission question on anybody's behalf; what it can do is put the
/// pane where the answer is kept in front of them, because a step described in prose is a step
/// half the people never take. Here rather than at the border so the URL that opens each one is
/// covered by a test: a pane identifier that stops working fails silently — the URL opens the
/// front page of Settings and the person is left looking for a list nobody named.
public enum SystemSettingsPane: String, CaseIterable, Sendable {
    /// Privacy & Security → Accessibility: looking through another app's windows.
    case accessibility
    /// Privacy & Security → Automation: controlling another app, which is what asking a
    /// terminal about its tabs is.
    case automation
    /// Notifications, where the banners of whoever sends them are switched on and off.
    case notifications

    /// The URL that opens it. Optional rather than force-unwrapped: a typo here is not worth a
    /// crash in a widget that runs all day.
    public var url: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        }
    }
}

/// Everything the app depends on and did not bring with it, in one list.
///
/// The app runs on what this machine has given it — a status line slot, a permission, a source
/// that has written something — and until now a person found out which of those was missing
/// only when something failed to happen: a click raised the wrong window, a notification never
/// came, "Claude" stood with an em dash. The sources were the half of this that already
/// existed (`SetupState`); this grows around them rather than beside them, so there is one list
/// and not two.
///
/// Facts only: reading the machine is the app's, the English is `Phrasing`'s. Every one of
/// these is read without asking the system for anything — opening a window that raised a
/// permission dialog would be the app demanding an answer for its own convenience.
public struct CheckupState: Equatable, Sendable {
    /// One thing the app depends on, in the order the list shows them: what it reads, then
    /// what it was allowed to do, then what it is.
    public enum Point: String, CaseIterable, Sendable {
        case claudeLimits
        case claudeSessions
        case codex
        case statusLineSlot
        case accessibility
        case automation
        case sessionRecords
        case notifications
        case openAtLogin
        case runningCopy

        /// The source this point is about, for the three that are sources.
        public var source: SetupState.Source? { SetupState.Source(rawValue: rawValue) }
    }

    /// What the machine says about one point.
    public enum Standing: Equatable, Sendable {
        /// There, and the app is using it.
        case given
        /// Not there. Every one of these has a line saying what it costs and, where there is
        /// one, a button.
        case missing
        /// macOS will not say until the app tries. A tick invented for one of these is worse
        /// than its absence: it would be the app's guess wearing the system's authority.
        case settledOnUse
        /// Nothing to tick — the row states a fact or carries its own control.
        case stated
    }

    /// Which sources have written something this app can read.
    public let sources: SetupState

    /// Whose Claude Code's one status line slot is.
    public let slot: StatusLineSlotState

    /// Whether the app is allowed to look through other applications' windows.
    public let isAccessibilityTrusted: Bool

    /// Whether Claude Code is leaving records of its running sessions where this app can read
    /// them — which is what a click on a session row runs on.
    public let hasSessionRecords: Bool

    /// Which channel the notifications went out over, or `nil` while none has been sent.
    public let notifications: NotificationChannel?

    public let copy: RunningCopy

    public init(
        sources: SetupState,
        slot: StatusLineSlotState,
        isAccessibilityTrusted: Bool,
        hasSessionRecords: Bool,
        notifications: NotificationChannel?,
        copy: RunningCopy
    ) {
        self.sources = sources
        self.slot = slot
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.hasSessionRecords = hasSessionRecords
        self.notifications = notifications
        self.copy = copy
    }

    public func standing(of point: Point) -> Standing {
        switch point {
        case .claudeLimits, .claudeSessions, .codex:
            // The three sources answer for themselves; a point with no source behind it cannot
            // be in this branch, and reading as missing is the honest answer if it ever is.
            guard let source = point.source else { return .missing }
            return sources.isConnected(source) ? .given : .missing
        case .statusLineSlot:
            // Another copy of this app in the slot counts as held: the limits are arriving,
            // which is what this row is about. Which copy is doing it is the panel's offer to
            // take over, not a gap in the checkup.
            return slot.isOurs || slot.needsTakingOver ? .given : .missing
        case .accessibility:
            return isAccessibilityTrusted ? .given : .missing
        case .automation:
            // Never a tick and never a gap, whatever has happened in this run. macOS has no
            // question that answers "may this app control Terminal" — the only way to find out
            // is to try, and the trying is somebody's click. A row that went on to read
            // "missing" after one failed attempt would be reporting a script that found no tab
            // as a permission refused, and a row that read "given" after a successful one
            // would be saying it of every terminal on the machine because one of them
            // answered.
            return .settledOnUse
        case .sessionRecords:
            // Stated and never missing, whether records are being read this minute or not.
            // Nothing on this machine is waiting on the person here: the records are written
            // by a running Claude Code and by nothing else, there is no pane to open and no
            // button to press, and a dashed circle would make the ordinary state of a Mac with
            // no session open — or a CLI too old to write them — look like a fault. What the
            // row is for is the sentence, which says what a click needs and what is there now.
            return .stated
        case .notifications:
            return notifications == nil ? .settledOnUse : .given
        case .openAtLogin, .runningCopy:
            return .stated
        }
    }

    /// Whether anything in the list is waiting on the person — which is what decides whether
    /// the window opens with this list unfolded. Nothing missing means nothing to do about it,
    /// and a list of ticks is not what somebody opened a settings window for.
    public var hasSomethingMissing: Bool {
        Point.allCases.contains { standing(of: $0) == .missing }
    }
}

/// A place in the panel that cannot do its job, and the line of the checkup that says why.
///
/// The panel is a page of readings, and when a reading is missing or a click leads nowhere it
/// has room for a sentence and no room for the paragraph behind it. That paragraph is already
/// written — it is a row of the checkup — so the panel's dead ends become roads into the window
/// rather than places where the app goes quiet.
///
/// A rule and not an `if` in a view, for the reason the rest of this file is here: which row
/// answers which dead end is a decision that can be got wrong silently, and a road that leads
/// to the wrong line is worse than no road — it tells a person to go and fix something that was
/// never the problem.
public enum CheckupRoad: Equatable, Sendable {
    /// A service's subscription limits, where the numbers should be and are not.
    case limits(AgentService)
    /// A session row that cannot bring up the window it is running in.
    case sessionClick
    /// A click that got the application and no further, and said which permission it wanted.
    case permission(TerminalRaise.Permission)

    /// The row of the checkup this leads to.
    ///
    /// - Parameter slot: whose Claude Code's status line slot is — the one thing a dead end
    ///   cannot tell about itself. Missing Claude limits are two different stories: nothing
    ///   holds the slot, so no number was ever going to arrive, or the slot is held and the
    ///   source has simply not reported yet. They are fixed in different places, so they are
    ///   two different rows.
    public func point(slot: StatusLineSlotState) -> CheckupState.Point {
        switch self {
        case .limits(.claude):
            // The same question the slot's own row answers with a tick, asked in one place:
            // a second reading of what "held" means is a second chance to disagree.
            return slot.isOurs || slot.needsTakingOver ? .claudeLimits : .statusLineSlot
        case .limits(.codex):
            return .codex
        case .sessionClick:
            return .sessionRecords
        case .permission(.accessibility):
            return .accessibility
        case .permission(.automation):
            return .automation
        }
    }
}
