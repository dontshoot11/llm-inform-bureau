import Foundation
import SessionHealthCore

/// What the widget calls things, in both of the languages it speaks.
///
/// Every sentence here says what was crossed and how full something is — never how good the
/// answers are. There is no signal for that in anything this app can read, and a sentence that
/// implies one would be the widget's only lie. The rule holds on both sides: a Russian phrase
/// that graded a session would be the same lie said where fewer reviewers would catch it.
///
/// Where a mark comes from is part of what it says, and every mark is now the project's own.
/// The wording says so rather than letting a number pass for a vendor's line; what it can
/// attribute is the published compaction point the red mark sits below, and it says a session
/// *may* be rewritten past it rather than promising it will be.
///
/// What is not a phrase here is what is not this app's to say: the names of the two services,
/// the slash commands of their CLIs, and the name an agent gave itself. Translating any of
/// those would be inventing a word the reader cannot type back into a terminal.
public enum Wording {
    public static func service(_ service: AgentService) -> String { service.shortLabel }

    /// The same service as the menu bar has room to name it. See `AgentService.barLabel`.
    public static func serviceInBar(_ service: AgentService) -> String { service.barLabel }

    /// Said for an agent whose CLI is not on this machine at all. Not a fault and not a gap:
    /// there is nothing to install for this app's sake, and nothing to wait for.
    public static let notInstalled = Phrase(
        "Not installed on this Mac — nothing to connect.",
        "Не установлено на этом Маке — подключать нечего."
    )

    /// Said in a folded row whose service has reported nothing yet — the slot is connected and
    /// the first answer of a session has not come back.
    ///
    /// Two words rather than none. The rule of this panel is that a reading nobody made shows a
    /// sentence and never a zero; folded away there is no room for the sentence, and what was
    /// there instead was an empty right-hand side, which reads as an app that did not do what
    /// the button promised. The sentence itself is one fold away.
    public static let noReadingYet = Phrase("no data yet", "данных пока нет")

    /// A window with nothing left, where there is room for a word and not for a sentence.
    /// What it costs is said in full when the limits are opened out; folded away, the cross
    /// beside it is already saying most of it.
    public static let spentLabel = Phrase("spent", "исчерпано")

    // MARK: The panel, as it is laid out

    /// The name over the first half of the panel. Capitals are the panel's own — it sets both
    /// of these in small caps, and the word itself is written the way a sentence would have it.
    public static let limitsSection = Phrase("Subscription limits", "Лимиты подписки")

    /// The name over the second half. The dash is doing the work of "and what they hold": the
    /// caption has the width of the panel and no more.
    public static let contextSection = Phrase("Active sessions — context", "Активные сессии — контекст")

    /// Said where the second half would be, with nothing running anywhere.
    public static let noActiveSessions = Phrase("No active sessions.", "Активных сессий нет.")

    /// Said in place of a reading before the first pass has come back. It is not an absence —
    /// nothing has been asked yet — so it says what is happening rather than what is missing.
    public static let firstPass = Phrase("Reading…", "Читаем…")

    /// How much of a window is gone, as a row of either half says it.
    public static func used(_ percent: Double) -> Phrase {
        let share = TokenDisplay.percent(percent)
        return Phrase("\(share) used", "\(share) израсходовано")
    }

    /// When a window comes back, under the number saying how much of it is gone.
    public static func resets(at date: Date, now: Date = Date()) -> Phrase {
        let when = TimeDisplay.until(date, now: now)
        return Phrase("resets \(when.english)", "сбросится \(when.russian)")
    }

    /// Said instead, for a window whose reset time nobody reported. The reading is still a
    /// reading; what is missing is the half of it that says when it stops mattering.
    public static let resetTimeNotReported = Phrase(
        "reset time not reported",
        "время сброса не сообщено"
    )

    /// How old a limits reading is, under the windows it describes.
    public static func reported(at observedAt: Date, now: Date = Date()) -> Phrase {
        let age = TimeDisplay.age(of: observedAt, now: now)
        return Phrase("Reported \(age.english)", "Сообщено \(age.russian)")
    }

    /// The one row a session entry has: what is being spent.
    public static let contextWindowRow = Phrase("Context window", "Окно контекста")

    /// How full a context window is, when the size of it was reported.
    public static func windowFill(percent: Double, of windowTokens: Int) -> Phrase {
        let share = TokenDisplay.percent(percent)
        let size = TokenDisplay.short(windowTokens)
        return Phrase("\(share) of \(size)", "\(share) из \(size)")
    }

    /// Said in place of that share when nobody reported the size of the window. Never a
    /// percentage of something unknown.
    public static let windowSizeUnknown = Phrase("size unknown", "размер неизвестен")

    /// What a session is holding, in the line under its reading.
    public static func tokensHeld(_ tokens: Int) -> Phrase {
        let held = TokenDisplay.short(tokens)
        return Phrase("\(held) tokens held", "в контексте \(held) токенов")
    }

    /// What the last request added to it.
    ///
    /// "Request" rather than the domain's own word: a turn is what the rules measure between
    /// two user prompts, and a person reading the panel calls that the last thing they asked
    /// for.
    public static func lastRequest(_ growth: Int) -> Phrase {
        let added = TokenDisplay.growth(growth)
        return Phrase("\(added) last request", "\(added) за последний запрос")
    }

    // MARK: What is under the pointer

    /// Said over the light of a limits entry, in front of the scale the light is read on.
    public static let limitsEntryHelp = Phrase(
        "This service's subscription limits — the first of its two dots in the menu bar.",
        "Лимиты подписки этого сервиса — первая из двух его точек в строке меню."
    )

    /// The same, over one session's light.
    public static let sessionContextHelp = Phrase(
        "The context this session holds — the second of its service's two dots in the menu bar.",
        "Контекст, который держит эта сессия, — вторая из двух точек её сервиса в строке меню."
    )

    /// And over the light of a service whose sessions could not be read at all.
    public static let serviceContextHelp = Phrase(
        "The context this service's sessions hold — the second of its two dots in the menu bar.",
        "Контекст, который держат сессии этого сервиса, — вторая из двух его точек в строке меню."
    )

    /// Said over the smaller light of a subagent's row: what it is, whose window it runs on,
    /// and why its own mark never announces itself.
    public static let subagentHelp = Phrase(
        "A subagent started by this session. It runs on the session's context window unless it "
            + "was given a model of its own, and its mark never notifies: it ends by itself, "
            + "usually within minutes.",
        "Подагент, запущенный этой сессией. Он идёт на окне контекста сессии, если ему не "
            + "выдали собственную модель, и его отметка не уведомляет: он заканчивается сам, "
            + "обычно за минуты."
    )

    /// What the gear opens, said where the pointer is on it.
    public static let settingsHelp = Phrase(
        "Settings: where the numbers come from, what is connected, and whether to open at login",
        "Настройки: откуда берутся числа, что подключено и запускаться ли при входе"
    )

    // MARK: Folding the limits away, and the way out of the app

    /// The control under the limits, in the words of what it does next.
    public static let showLess = Phrase("Show less", "Свернуть")

    public static let showBothWindows = Phrase(
        "Show both windows and when they reset",
        "Показать оба окна и когда они сбрасываются"
    )

    /// The question the power icon asks, and the two answers to it. Quitting is two taps
    /// rather than one because the panel is opened to read something, and the icon sits where
    /// a thumb lands.
    public static let terminateHelp = Phrase("Terminate the widget", "Завершить виджет")

    public static let terminateQuestion = Phrase("Terminate?", "Завершить?")

    public static let yes = Phrase("Yes", "Да")

    public static let no = Phrase("No", "Нет")

    /// The one item of the menu the app builds for itself, so that ⌘Q exists. The name of the
    /// app is its own and goes through untranslated.
    public static func quit(_ application: String) -> Phrase {
        Phrase("Quit \(application)", "Завершить \(application)")
    }

    /// The shortest name a limit window has, for a row that has room for a number and little
    /// else. The opened-out rows say "5-hour window" and "Weekly window"; folded away, next to
    /// its own percentage, the only question left is which of the two windows this is.
    public static func limitWindowShort(_ kind: LimitWindow.Kind) -> Phrase {
        kind == .short ? Phrase("5h", "5 ч") : Phrase("7d", "7 дн")
    }

    /// A limit window inside a sentence about it: "Claude weekly limit 62% used".
    public static func limitName(_ kind: LimitWindow.Kind) -> Phrase {
        kind == .short
            ? Phrase("5-hour limit", "лимит за 5 часов")
            : Phrase("weekly limit", "недельный лимит")
    }

    /// A limit window as a row of the panel names it, and as a sentence about it names it.
    ///
    /// One phrase for both, which is why the Russian side is lower case where the English one
    /// is not: Russian capitalises a heading far less readily, and the same words have to stand
    /// in the middle of "Claude: недельное окно перешло 62%" without reading as a new sentence.
    public static func limitWindow(_ kind: LimitWindow.Kind, minutes: Int?) -> Phrase {
        if let minutes {
            let length = TimeDisplay.windowLength(minutes)
            return Phrase("\(length.english) window", "окно \(length.russian)")
        }
        return kind == .short
            ? Phrase("5-hour window", "окно 5 часов")
            : Phrase("Weekly window", "недельное окно")
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
    ) -> Phrase {
        let comesBack: Phrase
        if let resetsAt {
            let when = TimeDisplay.until(resetsAt, now: now)
            comesBack = Phrase("back \(when.english)", "вернётся \(when.russian)")
        } else {
            comesBack = resetTimeNotReported
        }
        let name = limitName(window)
        return Phrase(
            "\(self.service(service)) \(name.english) is spent — \(comesBack.english)",
            "\(self.service(service)): \(name.russian) исчерпан — \(comesBack.russian)"
        )
    }

    /// Which reading lit the worst light, in one line.
    public static func reason(
        for kind: BudgetAlert.Kind,
        service: AgentService,
        config: ThresholdConfig
    ) -> Phrase {
        let name = self.service(service)
        switch kind {
        case .windowFill(let percent):
            let mark = TokenDisplay.percent(percent)
            return Phrase(
                "\(name) context window past \(mark)",
                "\(name): окно контекста перешло \(mark)"
            )
        case .limitUsage(let window, let percent):
            let mark = TokenDisplay.percent(percent)
            let named = limitWindow(window, minutes: nil)
            return Phrase(
                "\(name) \(named.english) past \(mark)",
                "\(name): \(named.russian) перешло \(mark)"
            )
        // A request lights nothing — form carries the state and colour carries the budget — so
        // nothing asks this of a request today. It answers all the same, and truthfully: the
        // alternative is a stand-in sentence waiting for the first reading that does ask.
        case .attention:
            return Phrase("\(name) is waiting on you", "\(name) ждёт вашего ответа")
        }
    }

    /// What a subagent's row is called: the kind of agent it is, or the plain word for one
    /// when its metadata file is missing. Never an empty row — the tokens it holds are worth
    /// showing whether or not anything said what the agent was.
    ///
    /// A name an agent gave itself has one side written twice, because it is the same name in
    /// both windows: it came out of somebody's configuration file, and translating it would
    /// leave a reader looking for a row that is not called that anywhere else.
    public static func subagentName(_ type: String?) -> Phrase {
        guard let type else { return Phrase("Subagent", "Субагент") }
        return Phrase.name(type)
    }

    /// What a subagent's row says under its name: the task it was given, when one was
    /// recorded. `nil` rather than a stand-in sentence — the row's other half is the numbers.
    ///
    /// Not a phrase: these are the words somebody wrote to their agent, and the app has no
    /// business rewriting them into another language.
    public static func subagentTask(_ task: String?) -> String? {
        guard let task, !task.isEmpty else { return nil }
        return task
    }

    /// The command that shows the subscription limits in full. The same in both CLIs, and the
    /// same in both languages: it is typed, not read.
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
    ///
    /// The command leads on both sides — it is what the reader's eye is looking for, and what
    /// follows it is the reason to read the rest of the line.
    public static func moreDetails(_ command: String) -> Phrase {
        Phrase("\(command) for more details", "\(command) — подробности")
    }

    /// What a click on a session's row does, said where the pointer already is.
    ///
    /// It promises the window and not the tab, because the tab is what two terminals out of
    /// several can give (`TerminalRaise`) and the panel has no business guessing which one a
    /// person is in. Getting the tab when the terminal can name it is better than what was
    /// promised, which is the only direction this app is allowed to surprise anybody in.
    public static let raiseSession = Phrase(
        "Click to bring up the window this session is running in.",
        "Щелчок поднимет окно, в котором идёт эта сессия."
    )

    /// What the panel's dead ends promise when the pointer is on them.
    ///
    /// Three sentences and not one, because a dead end is only worth pressing if a person can
    /// tell what they are about to get: a reading that never arrived, a row that cannot be
    /// clicked through, and a click that got partway. Each says what is wrong before it says
    /// where it leads — the window is the answer, not the news.
    public static let whyNoNumbers = Phrase(
        "No numbers here. Click to see what they are waiting on.",
        "Чисел здесь нет. Щёлкните, чтобы увидеть, чего они ждут."
    )

    public static let whyNoRaise = Phrase(
        "This session cannot be brought up. Click to see what a click on a session needs.",
        "Эту сессию не поднять. Щёлкните, чтобы увидеть, что для этого нужно."
    )

    public static let whereThisIsExplained = Phrase(
        "Click for the line that explains this in full.",
        "Щёлкните, чтобы открыть строку, где это объяснено целиком."
    )

    /// Said after a click got the application but not the tab or window inside it.
    ///
    /// Careful about what it claims, because the app cannot tell a refused permission from a
    /// terminal that turned out not to answer: it says what happened, names the permission as
    /// the likely reason, and stops there. The application was brought up either way — that
    /// goes first, so that a person who mostly got what they wanted is not reading an apology.
    ///
    /// **The sentence about a tick already given** (`signedAdHoc`) is for the one case where
    /// the pane lies to a person's face. Signed ad-hoc, this app has no name the system can
    /// keep an answer against beyond the hash of its binary, and a new version has a new hash:
    /// the tick from the version before is still in the pane, under this same name, granting
    /// access to a copy that is gone. Nothing in the pane says so, and nothing the app can do
    /// clears it — the one thing left is to say which tick it is. Measured 2026-09-17: a tick
    /// given an hour earlier, the system asking again on every click
    /// (`Scripts/Scripts.md`, "Why a development Mac wants a certificate of its own").
    ///
    /// Said only by a copy signed that way, because a copy signed with a certificate keeps its
    /// permissions across versions, and the sentence would then be sending somebody to undo a
    /// tick that works.
    public static func permissionOffer(
        _ permission: TerminalRaise.Permission,
        signedAdHoc: Bool = false
    ) -> Phrase {
        switch permission {
        case .automation:
            return Phrase(
                "Its application was brought up, but its tab could not be asked for. If you "
                    + "refused the permission to control other apps, that answer is kept in "
                    + "System Settings.",
                "Приложение поднялось, но спросить его о вкладке не вышло. Если вы отказали в "
                    + "праве управлять другими программами, этот ответ хранится в настройках "
                    + "системы."
            )
        case .accessibility:
            let said = Phrase(
                "Its application was brought up, but its windows could not be looked through, "
                    + "so the one in front is whichever you used last. Picking the right window "
                    + "needs this app allowed in Accessibility.",
                "Приложение поднялось, но заглянуть в его окна не вышло, поэтому впереди то, "
                    + "которым вы пользовались последним. Чтобы выбрать нужное окно, программе "
                    + "нужен доступ в разделе «Универсальный доступ»."
            )
            guard signedAdHoc else { return said }
            return Phrase.joined([said, tickFromAnEarlierBuild])
        }
    }

    /// What a tick in a privacy pane is worth to a copy signed ad-hoc, said wherever such a
    /// copy has to explain a permission that looks given and is not.
    ///
    /// One sentence in one place because two things say it: the panel, after a click that got
    /// no further than the application, and the checkup, where a row reads "not given" under a
    /// name the person can see ticked in System Settings. Measured 2026-09-17 — a tick given an
    /// hour earlier, the system asking again on every click (`Scripts/Scripts.md`, "Why a
    /// development Mac wants a certificate of its own").
    public static let tickFromAnEarlierBuild = Phrase(
        "If it is ticked there already, that tick was given to the version before this one — "
            + "untick it and tick it again.",
        "Если галочка там уже стоит, её дали прошлой версии — снимите и поставьте заново."
    )

    /// The button under the sentence above.
    public static func permissionSettings(_ permission: TerminalRaise.Permission) -> Phrase {
        openSettings(permission.pane)
    }

    /// The button that opens a pane of System Settings, named after the pane it opens. One
    /// place, so the panel and the checkup cannot come to call the same pane two things.
    ///
    /// The Russian side names each pane as macOS itself names it in a Russian system, because
    /// the button is a promise about what the reader will be looking at a second later.
    public static func openSettings(_ pane: SystemSettingsPane) -> Phrase {
        switch pane {
        case .automation:
            return Phrase("Open Automation settings", "Открыть раздел «Автоматизация»")
        case .accessibility:
            return Phrase("Open Accessibility settings", "Открыть раздел «Универсальный доступ»")
        case .notifications:
            return Phrase("Open Notification settings", "Открыть раздел «Уведомления»")
        }
    }
}
