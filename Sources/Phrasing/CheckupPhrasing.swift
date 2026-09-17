import Foundation
import SessionHealthCore

/// One line of the checkup: what it is, what this machine says about it, why the app wants it,
/// and where the answer is kept.
public struct CheckupRow: Equatable, Sendable {
    public let point: CheckupState.Point
    /// What this is, named after what it gives rather than after the file or the API behind it.
    public let title: Phrase
    public let standing: CheckupState.Standing
    /// Why the app wants this and what it means that the machine answers as it does — one
    /// piece of text, because a reader who is told the state without the cost has been told
    /// nothing they can act on.
    public let detail: Phrase
    /// The pane of System Settings where this answer is kept, for the rows that have one. The
    /// app opens it; the person answers in it.
    public let settings: SystemSettingsPane?

    public init(
        point: CheckupState.Point,
        title: Phrase,
        standing: CheckupState.Standing,
        detail: Phrase,
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
    /// its lines, and the rest are about what the app was allowed to do.
    public static let title = Phrase("What it uses on this Mac", "Что оно берёт у этого Мака")

    public static let intro = Phrase(
        "Everything is read from files this Mac already has. The app makes no network calls and "
            + "holds no credentials. It keeps its own files in Application Support, and the one "
            + "thing it writes anywhere else is a single key in ~/.claude/settings.json — only "
            + "if you connect the limits, and never without showing the change first.",
        "Всё читается из файлов, которые у этого Мака уже есть. Программа не ходит в сеть и не "
            + "хранит никаких доступов. Свои файлы она держит в Application Support, а "
            + "единственное, что она пишет где-то ещё, — один ключ в ~/.claude/settings.json, и "
            + "только если вы подключите лимиты, и никогда не показав правку заранее."
    )

    /// Said at the end, because the alternative — a zero — is what every other widget shows
    /// for something it does not know.
    public static let closing = Phrase(
        "Until a source has reported, the panel says what it does not know rather than showing "
            + "it as zero.",
        "Пока источник не отчитался, панель говорит, чего она не знает, вместо того чтобы "
            + "показать это нулём."
    )

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
                return CheckupRow(
                    point: point,
                    title: Phrase.name(point.rawValue),
                    standing: standing,
                    detail: Phrase("", "")
                )
            case .statusLineSlot:
                return CheckupRow(
                    point: point,
                    title: Phrase(
                        "Claude Code's status line slot",
                        "Слот строки состояния Claude Code"
                    ),
                    standing: standing,
                    detail: slotDetail(state.slot)
                )
            case .accessibility:
                return CheckupRow(
                    point: point,
                    title: Phrase(
                        "Allowed in Accessibility",
                        "Разрешено в «Универсальном доступе»"
                    ),
                    standing: standing,
                    detail: accessibilityDetail(state),
                    // Only while the answer is no. A button offering to open the pane where a
                    // permission already given is kept is a control with nothing to do, and
                    // this list is long enough without them.
                    settings: standing == .given ? nil : .accessibility
                )
            case .automation:
                return CheckupRow(
                    point: point,
                    title: Phrase(
                        "Allowed to control Terminal and iTerm2",
                        "Разрешено управлять Terminal и iTerm2"
                    ),
                    standing: standing,
                    detail: automationDetail,
                    // Offered whatever has happened, because the answer is not knowable from
                    // here: somebody who refused the dialog months ago has nothing else that
                    // would tell them where that answer is kept.
                    settings: .automation
                )
            case .sessionRecords:
                return CheckupRow(
                    point: point,
                    title: Phrase(
                        "Records of the sessions running now",
                        "Записи о сессиях, идущих прямо сейчас"
                    ),
                    standing: standing,
                    detail: sessionRecordsDetail(state.hasSessionRecords)
                )
            case .notifications:
                return CheckupRow(
                    point: point,
                    title: Phrase("Notifications", "Уведомления"),
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
                    detail: Phrase(
                        "The widget says nothing while it is not running, and nothing else "
                            + "starts it. What gets registered is the copy below, so it belongs "
                            + "where you mean to keep it before this is ticked.",
                        "Пока программа не запущена, она ничего не говорит, и запустить её "
                            + "некому. Регистрируется та копия, что названа ниже, — так что "
                            + "положите её туда, где собираетесь держать, прежде чем ставить "
                            + "эту галочку."
                    )
                )
            case .runningCopy:
                return CheckupRow(
                    point: point,
                    title: Phrase("The copy that is running", "Копия, которая работает"),
                    standing: standing,
                    detail: copyDetail(state.copy)
                )
            }
        }
    }

    /// The label on the login checkbox. Said here so the control and the line naming it cannot
    /// come to disagree.
    public static let openAtLogin = Phrase("Open at login", "Запускать при входе")

    /// The label on the other checkbox in this list: the only thing about notifications that is
    /// a decision rather than an answer.
    ///
    /// Named after what ticking it does, in the words the line above it already uses — a
    /// checkbox reading "Notifications" beside a row called Notifications says nothing about
    /// what it switches.
    public static let announceMarks = Phrase(
        "Announce a crossed mark",
        "Объявлять пересечённую отметку"
    )

    /// Said under that checkbox while it is off, and about the two things somebody unticking it
    /// has to be sure of: that nothing else went with it, and that the mark beside the row is
    /// still answering its own question.
    public static let silenced = Phrase(
        "Off: nothing is announced. The lights, the signs in the panel and everything they are "
            + "counted from go on exactly as they are — the difference is that nothing "
            + "interrupts you. The mark beside this line is about the channel, which is settled "
            + "by the first notification that does go out.",
        "Выключено: ничего не объявляется. Огни, знаки на панели и всё, из чего они считаются, "
            + "работают ровно как работали, — разница в том, что вас никто не отвлекает. "
            + "Отметка рядом с этой строкой — про канал, а он определяется первым уведомлением, "
            + "которое всё же уйдёт."
    )

    /// Said where a login item cannot be offered at all, with the reason.
    ///
    /// The reason is a phrase because two kinds arrive here: this app's own account of why
    /// there is nothing to register, and the system's own words, which come in whatever
    /// language it gives them and go on both sides as they are (`Phrase.name`).
    public static func openAtLoginUnavailable(_ why: Phrase) -> Phrase {
        Phrase(
            "\(openAtLogin.english): \(why.english)",
            "\(openAtLogin.russian): \(why.russian)"
        )
    }

    /// The reason there is nothing to register: the executable is being run on its own rather
    /// than out of the bundle the build script makes. That is a developer at a terminal, and
    /// the row says so rather than offering a checkbox that could not work.
    public static let openAtLoginNeedsBundle = Phrase(
        "Available once the app runs from the bundle built by Scripts/build-app.sh.",
        "Станет доступно, когда приложение запустится из бандла, собранного Scripts/build-app.sh."
    )

    /// Said under the checkbox while the system has the registration and has not let it
    /// through. Ticked here, off over there — and nothing launches until somebody says so in
    /// System Settings, so the pane is named rather than described.
    public static let openAtLoginWaitingForApproval = Phrase(
        "Waiting to be allowed in System Settings › General › Login Items.",
        "Ожидает разрешения в Системных настройках › Основные › Объекты входа."
    )

    /// What the app needs the slot for, and what is in it. The same sentence about where the
    /// limits come from on every branch: it is the reason the row exists, and a reader whose
    /// slot is held by somebody else needs it as much as one whose slot is empty.
    private static func slotDetail(_ slot: StatusLineSlotState) -> Phrase {
        let why = Phrase(
            "Claude hands its subscription limits and the size of its context window to its "
                + "status line command and to nothing else.",
            "Claude отдаёт лимиты подписки и размер окна контекста команде своей строки "
                + "состояния и больше никому."
        )
        switch slot {
        case .ours:
            return Phrase.joined([
                why,
                Phrase(
                    "This app is in the slot, which is how they arrive at all — and whatever "
                        + "command you had before is still called underneath, with the same "
                        + "payload.",
                    "В слоте стоит эта программа, потому они и доходят, — а команду, которая "
                        + "была у вас раньше, по-прежнему вызывают под ней, с теми же данными."
                )
            ])
        case .oursElsewhere:
            return Phrase.joined([
                why,
                Phrase(
                    "The slot holds this app's own command from another copy of it — a script "
                        + "an earlier version installed, or the same app in another place. The "
                        + "limits do arrive; the panel offers to let the copy you are running "
                        + "do the job itself.",
                    "В слоте стоит команда этой же программы из другой её копии — скрипт, "
                        + "поставленный прошлой версией, или та же программа в другом месте. "
                        + "Лимиты доходят; панель предлагает, чтобы этим занялась запущенная "
                        + "вами копия."
                )
            ])
        case .free:
            return Phrase.joined([
                why,
                Phrase(
                    "Nothing is in the slot, so there are no limits to show. Press "
                        + "\(Briefing.connectAction.english).",
                    "Слот пуст, поэтому лимитов и нет. Нажмите \(Briefing.connectAction.russian)."
                )
            ])
        case .somebodyElse(let command):
            return Phrase.joined([
                why,
                Phrase(
                    "Your own command is in the slot: \(command). The app joins it rather than "
                        + "replacing it — press \(Briefing.connectAction.english), and what is "
                        + "there goes on being called with the same payload.",
                    "В слоте стоит ваша команда: \(command). Программа встаёт рядом, а не "
                        + "вместо неё — нажмите \(Briefing.connectAction.russian), и то, что "
                        + "там стоит, продолжат вызывать с теми же данными."
                )
            ])
        case .unreadable(let path):
            return Phrase.joined([why, SlotPhrasing.unreadable(path)])
        }
    }

    /// What a click on a session row runs on, and why some of those rows do not click.
    ///
    /// The row a person arrives at from a session that led nowhere, so it answers that question
    /// first: a click needs a live record naming the process, and the two permissions above it
    /// decide only how close that click lands. Neither of them is why nothing happened at all.
    ///
    /// No button and no pane, because nothing on this Mac accepts an answer here. The records
    /// appear while an interactive Claude Code is running and at no other time, which is why
    /// the row states what is there rather than reporting a permission.
    private static func sessionRecordsDetail(_ present: Bool) -> Phrase {
        let why = Phrase(
            "A click on a session brings up the window it is running in, and getting there "
                + "needs the process behind it. Claude Code writes one small file per "
                + "interactive session in ~/.claude/sessions, and that file is the only thing "
                + "on this machine that names that process — a transcript never does. Codex "
                + "writes nothing of the kind, so its sessions are readings and never click.",
            "Щелчок по сессии поднимает окно, в котором она идёт, а для этого нужен стоящий за "
                + "ней процесс. Claude Code пишет по одному небольшому файлу на интерактивную "
                + "сессию в ~/.claude/sessions, и только этот файл на этой машине называет тот "
                + "процесс — в транскрипте его нет. Codex ничего подобного не пишет, поэтому "
                + "его сессии — это показания, и щелчок по ним ничего не делает."
        )
        guard present else {
            return Phrase.joined([
                why,
                Phrase(
                    "Nothing in ~/.claude/sessions at the moment: no interactive Claude Code is "
                        + "running, or the one in use is old enough not to write them. Nothing "
                        + "to connect — the file appears by itself, and a session shown without "
                        + "one is read exactly as it was before this app could read them at all.",
                    "Сейчас в ~/.claude/sessions пусто: интерактивный Claude Code не запущен "
                        + "или та версия, которой вы пользуетесь, ещё не пишет такие файлы. "
                        + "Подключать нечего — файл появляется сам, а сессию без него читают "
                        + "ровно так же, как читали до того, как программа научилась их видеть."
                )
            ])
        }
        return Phrase.joined([
            why,
            Phrase(
                "They are there and being read, so a Claude session running right now leads to "
                    + "its window.",
                "Они на месте и читаются, так что идущая прямо сейчас сессия Claude ведёт к "
                    + "своему окну."
            )
        ])
    }

    /// Why the app asks a terminal anything, and why this row has a question mark where every
    /// other permission has a tick.
    ///
    /// The honest shape of the only permission macOS will not answer for: there is no call that
    /// says whether controlling another app is allowed, and the one way to find out is to send
    /// an event and see. So the row says when that happens — a click on a session in one of
    /// those two terminals — rather than showing a tick the app would have had to invent.
    private static let automationDetail = Phrase(
        "A click on a session running in Terminal.app or iTerm2 brings up its tab, and finding "
            + "which tab holds it means asking the terminal — which macOS counts as controlling "
            + "another app. It will not say in advance whether that is allowed: the system asks "
            + "the first time it happens, with your click behind it, and nothing about it is "
            + "needed until then. Refused, a click still brings the terminal to the front, and "
            + "the answer is kept under Privacy & Security → Automation.",
        "Щелчок по сессии, идущей в Terminal.app или iTerm2, поднимает её вкладку, а чтобы "
            + "понять, в какой вкладке она живёт, нужно спросить терминал — macOS считает это "
            + "управлением другой программой. Заранее система не скажет, разрешено ли это: она "
            + "спросит в первый же раз, когда это случится, с вашим щелчком за спиной, а до "
            + "того ничего из этого не нужно. Если отказать, щелчок всё равно вынесет терминал "
            + "вперёд, а ответ хранится в «Конфиденциальность и безопасность» → «Автоматизация»."
    )

    private static func accessibilityDetail(_ state: CheckupState) -> Phrase {
        let why = Phrase(
            "A click on a session brings up the window it is running in, and telling one of a "
                + "terminal's four windows from another means looking through them.",
            "Щелчок по сессии поднимает окно, в котором она идёт, а чтобы отличить одно из "
                + "четырёх окон терминала от другого, нужно в них заглянуть."
        )
        if state.isAccessibilityTrusted {
            return Phrase.joined([
                why,
                Phrase(
                    "Given, so a click lands on the window titled after the session's project.",
                    "Доступ есть, поэтому щелчок попадает в окно, названное по проекту сессии."
                )
            ])
        }
        let missing = Phrase.joined([
            why,
            Phrase(
                "Not given, so what comes up is whichever window you used last. The answer is "
                    + "kept under Privacy & Security → Accessibility.",
                "Доступа нет, поэтому поднимется то окно, которым вы пользовались последним. "
                    + "Ответ хранится в «Конфиденциальность и безопасность» → «Универсальный "
                    + "доступ»."
            )
        ])
        guard state.copy.isAdHoc else { return missing }
        return Phrase.joined([missing, Wording.tickFromAnEarlierBuild])
    }

    /// What a notification is for, and whose name it will arrive under.
    ///
    /// No tick before the first one has been sent, and that is not a gap in the reading: the
    /// channel is chosen at the first notification, because asking for permission before there
    /// is anything to say is how an app gets refused.
    private static func notificationDetail(_ channel: NotificationChannel?) -> Phrase {
        let why = Phrase(
            "A crossed mark is said once, quietly, while you are looking at something else.",
            "Про пересечённую отметку говорят один раз и тихо, пока вы смотрите на другое."
        )
        switch channel {
        case nil:
            return Phrase.joined([
                why,
                Phrase(
                    "Which channel that goes out over is settled at the first notification: "
                        + "signed the way this copy is, the notification centre can refuse the "
                        + "app outright, and it then sends them through osascript instead.",
                    "Каким каналом это уйдёт, решается на первом уведомлении: с такой подписью, "
                        + "как у этой копии, центр уведомлений может отказать программе "
                        + "напрямую, и тогда она отправляет их через osascript."
                )
            ])
        case .ownName:
            return Phrase.joined([
                why,
                Phrase(
                    "Sent through the notification centre, under this app's own name.",
                    "Уходят через центр уведомлений, под собственным именем программы."
                )
            ])
        case .scriptEditor:
            return Phrase.joined([
                why,
                Phrase(
                    "The notification centre refused this copy, so they are sent through "
                        + "osascript and the system credits them to Script Editor — that is the "
                        + "name to look for in Notification settings if none of them arrive.",
                    "Центр уведомлений отказал этой копии, поэтому они уходят через osascript, "
                        + "и система записывает их на Script Editor — именно это имя искать в "
                        + "настройках уведомлений, если ни одно не доходит."
                )
            ])
        }
    }

    /// Which bundle is in the menu bar, said in the two facts that tell two copies of the same
    /// name apart: where it is and when it was built.
    private static func copyDetail(_ copy: RunningCopy) -> Phrase {
        let path = Phrase.name(copy.path)
        let built: Phrase
        if let builtAt = copy.builtAt {
            let when = TimeDisplay.moment(builtAt)
            built = Phrase("Built \(when.english).", "Собрано \(when.russian).")
        } else {
            built = Phrase(
                "Built: the date could not be read.",
                "Сборка: дату прочитать не удалось."
            )
        }
        var lines = [path, built]
        if copy.isAdHoc {
            lines.append(
                Phrase(
                    "Signed ad-hoc: to the system every build of it is a different app, so a "
                        + "permission given to the copy before this one stays ticked in System "
                        + "Settings and grants nothing.",
                    "Подписано на скорую руку: для системы каждая сборка — другая программа, "
                        + "поэтому доступ, выданный прошлой копии, так и стоит галочкой в "
                        + "настройках системы и ничего не даёт."
                )
            )
        }
        return Phrase.joined(lines, separator: "\n")
    }
}
