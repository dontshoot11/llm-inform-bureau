import Foundation
import SessionHealthCore

/// One notification, as the user reads it.
public struct NotificationText: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// The wording of a notification.
///
/// A notification interrupts, so it earns the interruption by answering the only two questions
/// the user has at that moment — what was crossed, and what to type to see the rest. The
/// command is the last thing in the body for exactly that reason, and it is not the same
/// command for both services.
///
/// What the wording never does is grade the session. The marks are Anthropic's compaction
/// point, two shares of a window, and two shares of a subscription; none of them is a
/// measurement of how good the answers have become, and the notification says so in the words
/// it chooses.
///
/// Usage:
/// ```swift
/// let said = AlertPhrasing.text(for: alert, config: config)
/// ```
public enum AlertPhrasing {
    public static func text(for alert: BudgetAlert, config: ThresholdConfig, now: Date = Date()) -> NotificationText {
        let service = Wording.service(alert.service)
        let command = Wording.command(for: alert.kind, service: alert.service)

        switch alert.kind {
        // The title carries the mark and the body the measurement, because the mark is what
        // makes this a notification and the measurement is what makes it worth reading.
        case .windowFill(let mark):
            // The sentence says what the number means and stops there. It does not promise
            // what the model will do next: how full a window is, is something this app can
            // read, and how well anything is being answered is not.
            let mostOfItGone = mark >= config.windowFill.high
            return NotificationText(
                title: "\(service) context window past \(TokenDisplay.percent(mark))",
                body: detail(
                    [
                        "\(percent(alert.percent)) full"
                            + (alert.tokens.map { ", \(TokenDisplay.short($0)) tokens held" } ?? "")
                            + ".",
                        mostOfItGone
                            ? "Most of what is in there is history by now, and the more of it there is, the more it weighs on what the model concludes. A fresh session keeps what still matters."
                            : "The fuller the window, the more of it is history that has stopped earning its place. A comfortable point to finish up and start fresh."
                    ],
                    command: command
                )
            )

        case .expensiveTurn(let atContextTokens):
            return NotificationText(
                title: "\(service) grew \(TokenDisplay.growth(alert.tokens ?? 0)) in one request",
                body: detail(
                    [
                        "Context is now \(TokenDisplay.short(atContextTokens)) tokens"
                            + (alert.percent.map { ", and that request was \(percent($0)) of the window" } ?? "")
                            + ".",
                        "One request costing this much is usually a large file or a wide search."
                    ],
                    command: command
                )
            )

        case .limitUsage(let window, let mark):
            return NotificationText(
                title: "\(service) \(Wording.limitName(window)) past \(TokenDisplay.percent(mark))",
                body: detail(
                    [
                        "\(percent(alert.percent)) used.",
                        alert.resetsAt.map { "Resets \(TimeDisplay.until($0, now: now))." }
                            ?? "Reset time not reported.",
                        "Work stops until it does, so what is left is worth spending deliberately."
                    ],
                    command: command
                )
            )
        }
    }

    /// The body of every notification: a sentence or two, then the command, last and alone, so
    /// that a glance at the end of the notification answers "and how do I see the rest".
    private static func detail(_ sentences: [String?], command: String) -> String {
        (sentences.compactMap { $0 }.joined(separator: " ") + "\n" + command)
    }

    private static func percent(_ value: Double?) -> String {
        value.map { TokenDisplay.percent($0) } ?? "—"
    }
}
