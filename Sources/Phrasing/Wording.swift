import Foundation
import SessionHealthCore

/// The English the widget speaks.
///
/// Every sentence here says what was crossed and how full something is — never how good the
/// answers are. There is no signal for that in anything this app can read, and a sentence that
/// implies one would be the widget's only lie.
///
/// Where a mark comes from is part of what it says, and every mark is now the project's own.
/// The wording says so rather than letting a number pass for a vendor's line; what it can
/// attribute is the published compaction point the red mark sits below, and it says a session
/// *may* be rewritten past it rather than promising it will be.
public enum Wording {
    public static func service(_ service: AgentService) -> String { service.shortLabel }

    /// The same service as the menu bar has room to name it. See `AgentService.barLabel`.
    public static func serviceInBar(_ service: AgentService) -> String { service.barLabel }

    /// Said for an agent whose CLI is not on this machine at all. Not a fault and not a gap:
    /// there is nothing to install for this app's sake, and nothing to wait for.
    public static let notInstalled = "Not installed on this Mac — nothing to connect."

    /// Said in a folded row whose service has reported nothing yet — the slot is connected and
    /// the first answer of a session has not come back.
    ///
    /// Two words rather than none. The rule of this panel is that a reading nobody made shows a
    /// sentence and never a zero; folded away there is no room for the sentence, and what was
    /// there instead was an empty right-hand side, which reads as an app that did not do what
    /// the button promised. The sentence itself is one fold away.
    public static let noReadingYet = "no data yet"

    /// A window with nothing left, where there is room for a word and not for a sentence.
    /// What it costs is said in full when the limits are opened out; folded away, the cross
    /// beside it is already saying most of it.
    public static let spentLabel = "spent"

    /// The shortest name a limit window has, for a row that has room for a number and little
    /// else. The opened-out rows say "5-hour window" and "Weekly window"; folded away, next to
    /// its own percentage, the only question left is which of the two windows this is.
    public static func limitWindowShort(_ kind: LimitWindow.Kind) -> String {
        kind == .short ? "5h" : "7d"
    }

    /// A limit window inside a sentence about it: "Claude weekly limit 62% used".
    public static func limitName(_ kind: LimitWindow.Kind) -> String {
        kind == .short ? "5-hour limit" : "weekly limit"
    }

    public static func limitWindow(_ kind: LimitWindow.Kind, minutes: Int?) -> String {
        if let minutes { return "\(TimeDisplay.windowLength(minutes)) window" }
        return kind == .short ? "5-hour window" : "Weekly window"
    }

    /// Said when a subscription window has nothing left.
    ///
    /// The last mark it crossed is beside the point by now: "past 75%" is advice about a
    /// window that still had something in it, and this one does not. What is worth a line here
    /// is that the work has stopped and when it starts again.
    public static func spent(
        _ service: AgentService,
        window: LimitWindow.Kind,
        resetsAt: Date?,
        now: Date = Date()
    ) -> String {
        let comesBack = resetsAt.map { "back \(TimeDisplay.until($0, now: now))" } ?? "reset time not reported"
        return "\(self.service(service)) \(limitName(window)) is spent — \(comesBack)"
    }

    /// Which reading lit the worst light, in one line.
    public static func reason(for kind: BudgetAlert.Kind, service: AgentService, config: ThresholdConfig) -> String {
        switch kind {
        case .windowFill(let percent):
            "\(self.service(service)) context window past \(TokenDisplay.percent(percent))"
        case .limitUsage(let window, let percent):
            "\(self.service(service)) \(limitWindow(window, minutes: nil)) past \(TokenDisplay.percent(percent))"
        // A request lights nothing — form carries the state and colour carries the budget — so
        // nothing asks this of a request today. It answers all the same, and truthfully: the
        // alternative is a stand-in sentence waiting for the first reading that does ask.
        case .attention:
            "\(self.service(service)) is waiting on you"
        }
    }

    /// What a subagent's row is called: the kind of agent it is, or the plain word for one
    /// when its metadata file is missing. Never an empty row — the tokens it holds are worth
    /// showing whether or not anything said what the agent was.
    public static func subagentName(_ type: String?) -> String { type ?? "Subagent" }

    /// What a subagent's row says under its name: the task it was given, when one was
    /// recorded. `nil` rather than a stand-in sentence — the row's other half is the numbers.
    public static func subagentTask(_ task: String?) -> String? {
        guard let task, !task.isEmpty else { return nil }
        return task
    }

    /// The command that shows the subscription limits in full. The same in both CLIs.
    public static func limitsCommand(_ service: AgentService) -> String { "/usage" }

    /// The command that shows what the context holds. The two services do not share one.
    public static func contextCommand(_ service: AgentService) -> String {
        service == .claude ? "/context" : "/status"
    }

    /// How a reading is followed up in the CLI. Said at the end of a notification and under the
    /// same reading in the panel — from here in both cases, so the two cannot drift apart.
    ///
    /// `nil` for a request to the person: there is no command that answers a question. The
    /// session is already on screen somewhere waiting for them, and a slash command at the end
    /// of that notification would send them to look at a number instead of answering.
    public static func command(for kind: BudgetAlert.Kind, service: AgentService) -> String? {
        switch kind {
        case .limitUsage:
            limitsCommand(service)
        case .windowFill:
            contextCommand(service)
        case .attention:
            nil
        }
    }

    /// The hint under a reading in the panel: the command, and what it is for.
    public static func moreDetails(_ command: String) -> String { "\(command) for more details" }

    /// What a click on a session's row does, said where the pointer already is.
    ///
    /// It promises the window and not the tab, because the tab is what two terminals out of
    /// several can give (`TerminalRaise`) and the panel has no business guessing which one a
    /// person is in. Getting the tab when the terminal can name it is better than what was
    /// promised, which is the only direction this app is allowed to surprise anybody in.
    public static let raiseSession = "Click to bring up the window this session is running in."

    /// Said after a click got the application but not the tab or window inside it.
    ///
    /// Careful about what it claims, because the app cannot tell a refused permission from a
    /// terminal that turned out not to answer: it says what happened, names the permission as
    /// the likely reason, and stops there. The application was brought up either way — that
    /// goes first, so that a person who mostly got what they wanted is not reading an apology.
    public static func permissionOffer(_ permission: TerminalRaise.Permission) -> String {
        switch permission {
        case .automation:
            "Its application was brought up, but its tab could not be asked for. If you refused "
                + "the permission to control other apps, that answer is kept in System Settings."
        case .accessibility:
            "Its application was brought up, but its windows could not be looked through, so the "
                + "one in front is whichever you used last. Picking the right window needs this "
                + "app allowed in Accessibility."
        }
    }

    /// The button under the sentence above.
    public static func permissionSettings(_ permission: TerminalRaise.Permission) -> String {
        switch permission {
        case .automation: "Open Automation settings"
        case .accessibility: "Open Accessibility settings"
        }
    }
}
