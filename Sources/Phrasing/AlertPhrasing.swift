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
/// A request to the person is the one notification with no command at the end, and that is the
/// same rule read the other way: what they have to do about it is answer, and the session
/// asking them is already open in a terminal somewhere. What that one owes instead is the
/// project — the panel lists sessions by project, so naming it is how the notification points
/// at a row rather than at the whole app.
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

        // Not a mark and not a number: the agent has stopped and the next move is the
        // person's. The title says that in as many words — "waiting on you", not "the session
        // stopped" — because the difference between the two is the whole reason this arrives
        // at all.
        case .attention:
            let asked = alert.request?.about.flatMap { Self.oneLine($0) }
            return NotificationText(
                title: alert.request?.project.map { "\(service) is waiting on you in \($0)" }
                    ?? "\(service) is waiting on you",
                body: detail(
                    [asked ?? "The agent has stopped and is waiting for an answer."],
                    command: command
                )
            )
        }
    }

    /// The body of every notification: a sentence or two, then the command, last and alone, so
    /// that a glance at the end of the notification answers "and how do I see the rest".
    ///
    /// No command is the legitimate answer for a request to the person, and then the body is
    /// the sentences alone — see the type's own comment for why.
    private static func detail(_ sentences: [String?], command: String?) -> String {
        let said = sentences.compactMap { $0 }.joined(separator: " ")
        guard let command else { return said }
        return said + "\n" + command
    }

    /// A question as a notification can carry it: one line, and short enough to be read at a
    /// glance rather than opened.
    ///
    /// A question is written to be read in a terminal, so it arrives with line breaks in it and
    /// sometimes with a paragraph around it. Both are flattened here rather than at the source:
    /// the panel and any later reader get the question whole, and only the line that has to fit
    /// in a banner is cut. Cut on a word, with an ellipsis, so that what is shown never reads
    /// as the whole of what was asked.
    private static func oneLine(_ text: String, limit: Int = 120) -> String? {
        let flattened = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flattened.isEmpty else { return nil }
        guard flattened.count > limit else { return flattened }
        let head = flattened.prefix(limit)
        let lastSpace = head.lastIndex(of: " ")
        let kept = lastSpace.map { head[head.startIndex..<$0] } ?? head
        return kept + "…"
    }

    private static func percent(_ value: Double?) -> String {
        value.map { TokenDisplay.percent($0) } ?? "—"
    }
}
