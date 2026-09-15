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

    /// Said for an agent whose CLI is not on this machine at all. Not a fault and not a gap:
    /// there is nothing to install for this app's sake, and nothing to wait for.
    public static let notInstalled = "Not installed on this Mac — nothing to connect."

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
        case .expensiveTurn:
            "\(self.service(service)) grew sharply in one request"
        case .limitUsage(let window, let percent):
            "\(self.service(service)) \(limitWindow(window, minutes: nil)) past \(TokenDisplay.percent(percent))"
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
    public static func command(for kind: BudgetAlert.Kind, service: AgentService) -> String {
        switch kind {
        case .limitUsage:
            limitsCommand(service)
        case .windowFill, .expensiveTurn:
            contextCommand(service)
        }
    }

    /// The hint under a reading in the panel: the command, and what it is for.
    public static func moreDetails(_ command: String) -> String { "\(command) for more details" }
}
