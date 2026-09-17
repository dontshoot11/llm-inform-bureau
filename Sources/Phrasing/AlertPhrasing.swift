import Foundation
import SessionHealthCore

/// One notification, as the user reads it.
///
/// Two phrases rather than two strings, because a notification is built in one place and
/// resolved in another: the rules assemble it as the reading comes in, and the app picks a side
/// of it at the moment it goes to the screen. A notification sitting in the queue while the
/// person changes the language of the app is then said in the language they are now reading.
public struct NotificationText: Equatable, Sendable {
    public let title: Phrase
    public let body: Phrase

    public init(title: Phrase, body: Phrase) {
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
/// it chooses — in both languages, since a promise the English side does not make is not one
/// the Russian side may make instead.
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
            let crossed = TokenDisplay.percent(mark)
            let held = alert.tokens.map { tokens -> Phrase in
                let short = TokenDisplay.short(tokens)
                return Phrase(", \(short) tokens held", ", в нём \(short) токенов")
            }
            return NotificationText(
                title: Phrase(
                    "\(service) context window past \(crossed)",
                    "\(service): окно контекста перешло \(crossed)"
                ),
                body: detail(
                    [
                        Phrase(
                            "\(percent(alert.percent)) full\(held?.english ?? "").",
                            "заполнено на \(percent(alert.percent))\(held?.russian ?? "")."
                        ),
                        mostOfItGone ? mostlyHistory : roomToFinishUp
                    ],
                    command: command
                )
            )

        case .limitUsage(let window, let mark):
            let crossed = TokenDisplay.percent(mark)
            let named = Wording.limitName(window)
            let resets: Phrase
            if let resetsAt = alert.resetsAt {
                let when = TimeDisplay.until(resetsAt, now: now)
                resets = Phrase("Resets \(when.english).", "Сбросится \(when.russian).")
            } else {
                resets = Phrase("Reset time not reported.", "Время сброса не сообщено.")
            }
            return NotificationText(
                title: Phrase(
                    "\(service) \(named.english) past \(crossed)",
                    "\(service): \(named.russian) перешёл \(crossed)"
                ),
                body: detail(
                    [
                        Phrase(
                            "\(percent(alert.percent)) used.",
                            "израсходовано \(percent(alert.percent))."
                        ),
                        resets,
                        workStops
                    ],
                    command: command
                )
            )

        // Not a mark and not a number: the agent has stopped and the next move is the
        // person's. The title says that in as many words — "waiting on you", not "the session
        // stopped" — because the difference between the two is the whole reason this arrives
        // at all.
        case .attention:
            let title: Phrase
            if let project = alert.request?.project {
                title = Phrase(
                    "\(service) is waiting on you in \(project)",
                    "\(service) ждёт вашего ответа в \(project)"
                )
            } else {
                title = Phrase(
                    "\(service) is waiting on you",
                    "\(service) ждёт вашего ответа"
                )
            }
            return NotificationText(title: title, body: detail([Self.asked(alert.request)], command: command))
        }
    }

    /// What a window this full is holding, when most of what is in it has stopped earning its
    /// place. Said past the red mark, where the sentence below it would be understating things.
    private static let mostlyHistory = Phrase(
        "Most of what is in there is history by now, and the more of it there is, the more it "
            + "weighs on what the model concludes. A fresh session keeps what still matters.",
        "Большая часть того, что там лежит, — уже история, и чем её больше, тем сильнее она "
            + "давит на выводы модели. Новая сессия оставит при себе то, что ещё важно."
    )

    /// The same thing said earlier, when there is still room and the point is that this is a
    /// good moment rather than a late one.
    private static let roomToFinishUp = Phrase(
        "The fuller the window, the more of it is history that has stopped earning its place. "
            + "A comfortable point to finish up and start fresh.",
        "Чем полнее окно, тем больше в нём истории, которая уже не оправдывает своё место. "
            + "Удобная точка, чтобы закончить начатое и начать заново."
    )

    /// Why a spent subscription window is worth a notification rather than a line in a panel.
    private static let workStops = Phrase(
        "Work stops until it does, so what is left is worth spending deliberately.",
        "До сброса работа встанет, так что остаток стоит тратить осознанно."
    )

    /// The body of every notification: a sentence or two, then the command, last and alone, so
    /// that a glance at the end of the notification answers "and how do I see the rest".
    ///
    /// No command is the legitimate answer for a request to the person, and then the body is
    /// the sentences alone — see the type's own comment for why.
    private static func detail(_ sentences: [Phrase?], command: String?) -> Phrase {
        let said = Phrase.joined(sentences.compactMap { $0 })
        guard let command else { return said }
        return said.mapped { $0 + "\n" + command }
    }

    /// What the session is being held up by, in one sentence.
    ///
    /// A question says itself: its own words are better than any sentence about them, and they
    /// are used whenever the transcript carried them. A permission prompt has no words
    /// anywhere on disk, so it is named for what it is — the person has a yes or a no to give,
    /// and telling them that is the difference between a notification worth opening and one
    /// that only says a session stopped.
    ///
    /// A request the record did not name gets the sentence every request got before this app
    /// could tell them apart: true of both, and it claims nothing it was not told.
    ///
    /// A question that was carried is repeated as it was written, on both sides: those are the
    /// agent's words to the person, and an app that translated them would be answering for it.
    private static func asked(_ request: BudgetAlert.Request?) -> Phrase {
        guard let request else { return stopped }
        switch request.asked {
        case .question:
            return Self.oneLine(request.about).map(Phrase.name) ?? putAQuestion
        case .permission:
            return askingForATool
        case .unnamed:
            return Self.oneLine(request.about).map(Phrase.name) ?? stopped
        }
    }

    private static let stopped = Phrase(
        "The agent has stopped and is waiting for an answer.",
        "Агент остановился и ждёт ответа."
    )

    private static let putAQuestion = Phrase(
        "The agent has put a question to you and is waiting on the answer.",
        "Агент задал вам вопрос и ждёт ответа."
    )

    private static let askingForATool = Phrase(
        "The agent is asking to use a tool and waits on a yes or a no.",
        "Агент просит разрешения на инструмент и ждёт согласия или отказа."
    )

    /// A question as a notification can carry it: one line, and short enough to be read at a
    /// glance rather than opened.
    ///
    /// A question is written to be read in a terminal, so it arrives with line breaks in it and
    /// sometimes with a paragraph around it. Both are flattened here rather than at the source:
    /// the panel and any later reader get the question whole, and only the line that has to fit
    /// in a banner is cut. Cut on a word, with an ellipsis, so that what is shown never reads
    /// as the whole of what was asked.
    private static func oneLine(_ text: String?, limit: Int = 120) -> String? {
        guard let text else { return nil }
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
