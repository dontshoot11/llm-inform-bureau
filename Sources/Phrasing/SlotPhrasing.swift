import Foundation
import SessionHealthCore

/// What the panel puts in front of somebody before it edits their `settings.json`.
///
/// One screen of text, and the order of it is the point: the file being changed, the line
/// going into it, and then what that does to what they already had. A person who does not read
/// past the first line has still seen which file this is about.
public struct SlotPreview: Equatable, Sendable {
    public let title: Phrase
    /// The file, as a path to go and look at. A path and not a phrase: it is the same file
    /// whatever the window is speaking, and it is there to be compared against a terminal.
    public let path: String
    /// The line that will be in the slot afterwards, set in the font it is written in. `nil`
    /// when the key is being removed and nothing takes its place. A command, so it has no
    /// second side either — it is going into a config file, not into a sentence.
    public let command: String?
    /// What this does to what was there, and what it costs. Sentences, in the order they
    /// matter.
    public let notes: [Phrase]

    public init(title: Phrase, path: String, command: String?, notes: [Phrase]) {
        self.title = title
        self.path = path
        self.command = command
        self.notes = notes
    }
}

/// Taking Claude Code's status line slot and giving it back, in both languages.
public enum SlotPhrasing {
    /// The button that stands where the limits would be. Named for what it produces rather
    /// than for what it does to a config file: the person is looking at an empty reading.
    public static let connect = Phrase("Connect limits", "Подключить лимиты")

    public static let connectHelp = Phrase(
        "Claude hands its subscription limits and the size of its context window to its status "
            + "line command and to nothing else. This puts the app in that slot — and keeps "
            + "calling whatever was there before.",
        "Claude отдаёт лимиты подписки и размер окна контекста команде своей строки состояния "
            + "и больше никому. Это ставит программу в тот слот — и продолжает вызывать то, что "
            + "стояло там раньше."
    )

    /// The button that gives the slot back, in the settings window beside the line that says
    /// what is in it. Named for what it does to the slot rather than for what it does to the
    /// panel: what goes away is the reading, and what comes back is whatever was there before.
    public static let disconnect = Phrase("Disconnect", "Отключить")

    public static let disconnectHelp = Phrase(
        "Disconnect: put back the status line that was there before",
        "Отключить: вернуть строку состояния, которая была раньше"
    )

    /// The button for a slot held by another copy of this app — a Mac set up by the release
    /// that had an installer, or a bundle that has since moved. It stands under the limits
    /// rather than in place of them, because while that copy is there the limits are there —
    /// what is being offered is this copy doing the job itself.
    public static let takeOver = Phrase("Update the status line", "Обновить строку состояния")

    public static let takeOverHelp = Phrase(
        "Claude's limits are reaching this panel through another copy of this app — a script an "
            + "earlier version installed, or the same app in another place. This copy does it "
            + "itself now: the same numbers, nothing else on this Mac in between, and whatever "
            + "command you had before stays exactly where it is.",
        "Лимиты Claude доходят до этой панели через другую копию программы — скрипт, "
            + "поставленный прошлой версией, или ту же программу в другом месте. Теперь это "
            + "делает сама эта копия: те же числа, ничего лишнего между ними на этом Маке, а "
            + "ваша прежняя команда остаётся ровно там, где стояла."
    )

    /// Said on the two buttons of the preview. "Write it" rather than "OK": the whole reason
    /// the preview exists is that the next click edits a file.
    public static let apply = Phrase("Write it", "Записать")
    public static let cancel = Phrase("Cancel", "Отмена")

    public static func preview(_ change: StatusLineChange) -> SlotPreview {
        switch change.kind {
        case .connect:
            return SlotPreview(
                title: Phrase("This will set statusLine.command in", "Будет задано statusLine.command в"),
                path: change.settingsPath,
                command: change.command,
                notes: connectNotes(change)
            )
        case .disconnect:
            return SlotPreview(
                title: change.command == nil
                    ? Phrase("This will remove statusLine from", "Будет убрано statusLine из")
                    : Phrase(
                        "This will set statusLine.command back in",
                        "Будет возвращено statusLine.command в"
                    ),
                path: change.settingsPath,
                command: change.command,
                notes: [keptCopy]
            )
        }
    }

    private static func connectNotes(_ change: StatusLineChange) -> [Phrase] {
        if change.replacesEarlierCopy { return takeOverNotes(change) }
        guard let existing = change.keptUnderneath else {
            return [
                Phrase(
                    "No status line is configured now, so nothing of yours is being replaced. "
                        + "The app will print a short line of its own: model, context, limits.",
                    "Сейчас строка состояния не настроена, так что ничего вашего не заменяется. "
                        + "Программа будет печатать свою короткую строку: модель, контекст, "
                        + "лимиты."
                ),
                Phrase(
                    "One thing this changes for you: with any status line configured, Claude "
                        + "Code stops showing most footer hints, including \"esc to interrupt\".",
                    "Одно это всё же меняет: с любой настроенной строкой состояния Claude Code "
                        + "перестаёт показывать большую часть подсказок внизу, включая «esc to "
                        + "interrupt»."
                ),
                keptCopy
            ]
        }
        return [
            Phrase(
                "Your status line command is kept. It will be called with the same payload and "
                    + "its output printed unchanged:",
                "Ваша команда строки состояния сохраняется. Её будут вызывать с теми же "
                    + "данными, а вывод печатать без изменений:"
            ),
            Phrase.name(existing),
            keptCopy
        ]
    }

    /// Taking over from another copy of this app — the shell wrapper an earlier release
    /// installed, or the same binary elsewhere on disk. Said apart from the other branches
    /// because on this one nothing of the person's is being displaced: it was displaced once,
    /// by this same app, and what was saved then is left alone now.
    private static func takeOverNotes(_ change: StatusLineChange) -> [Phrase] {
        var notes = [
            Phrase(
                "The slot holds this app's own command from another copy of it — a script an "
                    + "earlier version installed, or the same app in another place. This puts "
                    + "the copy you are looking at there instead: the same payload, read the "
                    + "same way.",
                "В слоте стоит команда самой этой программы из другой её копии — скрипт, "
                    + "поставленный прошлой версией, или та же программа в другом месте. Туда "
                    + "встанет копия, на которую вы смотрите: те же данные, прочитанные так же."
            )
        ]
        if let existing = change.keptUnderneath {
            notes.append(
                Phrase(
                    "The status line command you had before that app is kept, exactly where it "
                        + "already is. It goes on being called with the same payload and its "
                        + "output printed unchanged:",
                    "Команда строки состояния, которая была у вас до той программы, "
                        + "сохраняется ровно там же. Её так же будут вызывать с теми же "
                        + "данными, а вывод печатать без изменений:"
                )
            )
            notes.append(Phrase.name(existing))
        } else {
            notes.append(
                Phrase(
                    "Nothing of yours is saved underneath it, so nothing is being put back: the "
                        + "app will print a short line of its own, as the script does now.",
                    "Под ней ничего вашего не сохранено, так что возвращать нечего: программа "
                        + "будет печатать свою короткую строку, как сейчас делает скрипт."
                )
            )
        }
        notes.append(
            Phrase(
                "The script itself is deleted once the slot is the app's.",
                "Сам скрипт удаляется, как только слот переходит программе."
            )
        )
        notes.append(keptCopy)
        return notes
    }

    /// Said on every branch that writes, because it is the answer to the question the preview
    /// raises.
    private static let keptCopy = Phrase(
        "A copy of the file is kept beside it first.",
        "Сначала рядом с файлом кладётся его копия."
    )

    /// Said when the file cannot be read, in place of the button. Nothing is written to a file
    /// this app does not understand, and the person is the only one who can say what is in it.
    public static func unreadable(_ path: String) -> Phrase {
        Phrase(
            "\(path) is not readable as JSON, so nothing will be written to it. Fixing it is "
                + "the one step this app will not take on somebody's behalf.",
            "\(path) не читается как JSON, поэтому туда ничего не запишут. Починить его — тот "
                + "самый шаг, который программа за человека не делает."
        )
    }

    /// Said when a write did not happen. It names the file, because the next thing anybody
    /// does is go and look at it.
    ///
    /// The reason is a phrase and not a string, because two quite different ones arrive here:
    /// the app's own account of why it refused, which has both sides like everything else it
    /// says, and a system error, which comes in whatever language the system gives it and goes
    /// on both sides as it is (`Phrase.name`).
    public static func failed(_ reason: Phrase) -> Phrase {
        Phrase(
            "Nothing was written — \(reason.english)",
            "Ничего не записано — \(reason.russian)"
        )
    }
}
