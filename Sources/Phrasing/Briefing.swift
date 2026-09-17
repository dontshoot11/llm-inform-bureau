import Foundation
import SessionHealthCore

/// One source, as the first-run explanation presents it.
public struct BriefingItem: Equatable, Sendable {
    public let source: SetupState.Source
    /// What this source gives, not what file it is.
    public let title: Phrase
    /// Where it comes from, and — when it is not connected — how to connect it.
    public let detail: Phrase
    public let isConnected: Bool

    public init(source: SetupState.Source, title: Phrase, detail: Phrase, isConnected: Bool) {
        self.source = source
        self.title = title
        self.detail = detail
        self.isConnected = isConnected
    }
}

/// One step of a scale: a percentage and the light it turns on.
///
/// The marks are shown as the lights they actually produce rather than described in a
/// paragraph. A sentence explaining that 60% is orange is a fact the reader has to hold and
/// match against a dot later; a dot with 60% beside it is the same fact, already matched.
public struct ScaleStep: Equatable, Sendable {
    public let percent: Double
    public let level: BudgetLevel

    public init(percent: Double, level: BudgetLevel) {
        self.percent = percent
        self.level = level
    }

    /// A number with a percent sign, which is the same label in both languages.
    public var label: String { TokenDisplay.percent(percent) }
}

/// One mark, as the first-run window presents it: what it is, what it is set to, and who says
/// so — a published source with its date, or an admission that nobody published one.
public struct MarkNote: Equatable, Sendable {
    /// Which mark this is — the identity the window moves, rather than the title it shows.
    public let mark: ThresholdMark
    public let title: Phrase
    /// The lights this mark turns on, when it is a scale. Empty for a mark that is one number,
    /// which the window shows as the number itself.
    public let scale: [ScaleStep]

    /// What this mark decides: which light it turns on, what stops or starts when it is
    /// crossed, and which way to move it when the app is getting it wrong.
    ///
    /// Said under every mark, whether the app placed it or the reader did. It describes the
    /// mark rather than the number standing on it, so moving that number does not make a word
    /// of it untrue — and a person who has just dragged a handle is the one who most needs to
    /// know what they have moved.
    public let what: Phrase

    private let unmeasuredOrigin: Phrase?
    public let provenance: ThresholdProvenance?
    /// `true` when the person moved this mark themselves.
    public let isChosen: Bool

    public init(
        mark: ThresholdMark,
        title: Phrase,
        scale: [ScaleStep] = [],
        what: Phrase,
        unmeasuredOrigin: Phrase? = nil,
        provenance: ThresholdProvenance?,
        isChosen: Bool = false
    ) {
        self.mark = mark
        self.title = title
        self.scale = scale
        self.what = what
        self.unmeasuredOrigin = unmeasuredOrigin
        self.provenance = provenance
        self.isChosen = isChosen
    }

    /// Where the number itself came from, or nothing when there is nothing honest to say.
    ///
    /// A measured mark names its date; an unmeasured one may admit it is a guess, because a
    /// number with an invented source lies silently and nothing catches it. A mark somebody
    /// moved says the only true thing left: they chose it. What stood there was written about
    /// the number the app ships, and repeating it under theirs would be the app inventing a
    /// justification for a mark nobody measured.
    public var origin: Phrase? {
        if isChosen { return Self.chosen }
        guard let provenance else { return unmeasuredOrigin }
        return Phrase("Published \(provenance.measuredAt)", "Опубликовано \(provenance.measuredAt)")
    }

    /// Said where the provenance of a shipped mark would be.
    public static let chosen = Phrase(
        "Chosen by you — the reasoning that shipped was about another number.",
        "Выбрано вами — обоснование, с которым пришла программа, было про другое число."
    )

    /// No source under a mark the person set: there is nothing published about a number
    /// somebody chose for themselves.
    public var source: URL? { isChosen ? nil : provenance?.source }
}

/// What one of the colours means, for the key above the marks.
///
/// The marks below it say where each colour begins; this says what being in it is like. A
/// reader who has just been handed a widget of coloured dots knows neither, and the numbers
/// are the half that cannot be guessed from the dot.
public struct LevelMeaning: Equatable, Sendable {
    public let level: BudgetLevel
    public let meaning: Phrase

    public init(level: BudgetLevel, meaning: Phrase) {
        self.level = level
        self.meaning = meaning
    }
}

/// One piece of published work behind the idea that context length matters.
///
/// Hardcoded rather than read from the config, and deliberately so: these set no number. The
/// config holds what the app *compares against*, and every entry there has to survive being
/// wrong; this is background, and its job is to let someone check the premise for themselves
/// instead of taking the widget's word for it.
public struct Reading: Equatable, Sendable {
    /// The title as it is published, which is a title in one language whatever the reader's is:
    /// somebody following this list is going to search for these words.
    public let title: Phrase
    public let year: String
    public let note: Phrase
    private let url: String

    public init(title: Phrase, year: String, note: Phrase, url: String) {
        self.title = title
        self.year = year
        self.note = note
        self.url = url
    }

    /// Optional rather than force-unwrapped: a typo in a reading list is not worth a crash in
    /// a widget that runs all day.
    public var source: URL? { URL(string: url) }
}

/// What the settings window says about its marks, and about where each reading comes from.
///
/// Two of the three sources connect themselves and one does not, and a person cannot tell which
/// is which from a panel of em dashes. So the window says where every number comes from and
/// names the one thing that has to be connected by hand — and the panel says it again, where
/// the button to do it stands, for as long as it is missing. Those three lines are the oldest
/// part of the checkup and keep their own wording here; the rest of that list — the slot, the
/// permissions, the copy that is running — is `CheckupPhrasing`'s.
public enum Briefing {
    /// The window's own name. It is a settings window now — the marks are moved in it — and
    /// the explanation of where the readings come from is one of the things folded up inside.
    public static let windowTitle = Phrase("Settings", "Настройки")

    /// The button that closes the window. Nothing is applied by it that was not applied
    /// already — every control in here writes when it is touched — so it says "done" rather
    /// than "save", which would promise a step that does not exist.
    public static let done = Phrase("Done", "Готово")

    /// The row that picks the language of the interface.
    ///
    /// A setting rather than a reading, and the first line of the window because it governs
    /// every word under it: a person who opened this window to change the language should not
    /// have to read a screenful of the wrong one to find the control.
    public static let languageTitle = Phrase("Language", "Язык")

    /// What each language is called, in itself.
    ///
    /// One string and not a phrase, deliberately: a language names itself the same way whatever
    /// the app is currently speaking, and "Russian"/"Русский" side by side in one picker would
    /// be the app answering in a language the reader may not have.
    public static func languageName(_ language: Language) -> String {
        switch language {
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// Said under the picker while nobody has touched it. It is the whole difference between
    /// not having chosen and having chosen English, and it is worth a line: the app is
    /// following something, and the reader is entitled to know what.
    public static let languageFollowsMac = Phrase(
        "Following the language of this Mac.",
        "Как язык этого Мака."
    )

    /// Said under the picker once somebody has picked. The counterpart of the line above, and
    /// read off the same state the picker is: a choice outranks the system from here on, which
    /// is the thing a reader cannot see and has to be told.
    public static let languageChosen = Phrase(
        "Chosen by you. Changing the language of this Mac will not change it back.",
        "Выбран вами. Смена языка этого Мака его уже не поменяет."
    )

    /// Puts the language back to following the Mac, and takes the choice off the disk. Shown
    /// only once there is a choice to undo, the same as the button under a mark somebody moved.
    public static let languageFollowMac = Phrase("Follow this Mac", "Следовать за Маком")

    /// How the one source that has to be connected is connected, named in one place so the
    /// window, the panel and the README cannot drift apart. The button itself is
    /// `SlotPhrasing.connect`, so the sentence and the thing it tells you to press cannot come
    /// to disagree.
    public static let connectAction = Phrase(
        "the \"\(SlotPhrasing.connect.english)\" button in the panel",
        "кнопку «\(SlotPhrasing.connect.russian)» на панели"
    )

    public static let marksTitle = Phrase("The marks it watches", "Отметки, за которыми оно следит")

    /// What each colour is like to be in, above the marks that say where it starts. Every
    /// colour the widget can draw is here, green included: a dot that never gets explained is
    /// the one a reader invents a meaning for.
    public static let levelKey: [LevelMeaning] = [
        LevelMeaning(level: .normal, meaning: Phrase("Comfort zone.", "Зона комфорта.")),
        LevelMeaning(
            level: .notice,
            meaning: Phrase(
                "Noticeable, nothing to do about it yet.",
                "Заметно, но делать пока нечего."
            )
        ),
        LevelMeaning(level: .elevated, meaning: Phrase("Worth your attention.", "Стоит внимания.")),
        LevelMeaning(
            level: .high,
            meaning: Phrase(
                "Step away from the keyboard. Go and touch some grass.",
                "Отойдите от клавиатуры. Сходите потрогайте траву."
            )
        )
    ]

    /// The same scale in one line, for the tooltip on a light in the panel.
    public static func scaleHelp(_ config: ThresholdConfig) -> Phrase {
        let notice = TokenDisplay.percent(config.windowFill.notice)
        let elevated = TokenDisplay.percent(config.windowFill.elevated)
        let high = TokenDisplay.percent(config.windowFill.high)
        return Phrase(
            "Yellow past \(notice) of the window, orange past \(elevated), red past \(high) — "
                + "how full it is. Orange and red notify.",
            "Жёлтый после \(notice) окна, оранжевый после \(elevated), красный после \(high) — "
                + "это его наполнение. Оранжевый и красный уведомляют."
        )
    }

    /// Puts a mark back where the app had it. Shown only on a mark that was moved: a button
    /// that undoes nothing is a control a reader learns to skip over.
    public static let resetMark = Phrase("Reset to default", "Вернуть как было")

    /// How the bar is worked, said once under it. Dragging is discoverable; the arrow keys are
    /// not, and they are the only way to land on an exact number.
    public static let markEditHint = Phrase(
        "Drag a mark to move it, or click one and use the arrow keys.",
        "Отметку можно перетащить, а можно щёлкнуть по ней и двигать стрелками."
    )

    /// The unit of the marks that are one number. Beside the field rather than in the title,
    /// because the number is what changes and the unit is what it is measured in.
    public static let minuteUnit = Phrase("min", "мин")

    /// What a field of minutes is called when it is read out rather than looked at: the number
    /// on its own says nothing about which mark it belongs to.
    public static func minuteFieldLabel(of markTitle: Phrase) -> Phrase {
        Phrase(
            "\(markTitle.english), in minutes",
            "\(markTitle.russian), в минутах"
        )
    }

    /// What a handle of a scale is called when it is read out rather than looked at — a mark
    /// is a colour, and a colour is exactly what a screen reader cannot pass on.
    public static func handleLabel(_ handle: MarkScale.Handle, of markTitle: Phrase) -> Phrase {
        let colour: Phrase
        switch handle {
        case .notice: colour = Phrase("the yellow mark", "жёлтая отметка")
        case .elevated: colour = Phrase("the orange mark", "оранжевая отметка")
        case .high: colour = Phrase("the red mark", "красная отметка")
        }
        return Phrase(
            "\(markTitle.english): \(colour.english)",
            "\(markTitle.russian): \(colour.russian)"
        )
    }

    /// The marks this window shows, scales first and then the marks that are one number. Not
    /// every mark the app watches: the quiet rule about a limit window that is about to reset
    /// does its work without anybody deciding anything about it, and a settings window is a
    /// list of things to act on.
    public static func marks(of config: ThresholdConfig) -> [MarkNote] {
        func steps(_ marks: PercentMarks) -> [ScaleStep] {
            [
                ScaleStep(percent: marks.notice, level: .notice),
                ScaleStep(percent: marks.elevated, level: .elevated),
                ScaleStep(percent: marks.high, level: .high)
            ]
        }

        return [
            MarkNote(
                mark: .windowFill,
                title: Phrase("Context window filled", "Наполнение окна контекста"),
                scale: steps(config.windowFill),
                what: Phrase(
                    "How much of the window a session is holding. The fuller it gets, the more "
                        + "of it is history that has stopped earning its place — and the more "
                        + "of that there is, the more it weighs on what the model concludes.",
                    "Какую часть окна держит сессия. Чем полнее оно становится, тем больше в "
                        + "нём истории, которая уже не оправдывает своё место, — и тем сильнее "
                        + "она давит на выводы модели."
                ),
                unmeasuredOrigin: Phrase(
                    "Not measured: what is published about long contexts says the effect is "
                        + "real, not where to put a mark.",
                    "Не измерено: опубликованное про длинный контекст говорит, что эффект "
                        + "реален, но не говорит, где ставить отметку."
                ),
                provenance: config.windowFill.provenance,
                isChosen: config.windowFill.isChosen
            ),
            MarkNote(
                mark: .limitUsage,
                title: Phrase("Subscription limit spent", "Израсходовано от лимита подписки"),
                scale: steps(config.limitUsage),
                what: Phrase(
                    "How much of a subscription's quota has gone. The app ships this scale and "
                        + "the one above it alike, so a colour means one thing everywhere in "
                        + "the widget; moved here, it becomes your own colour language for the "
                        + "two.",
                    "Сколько квоты подписки уже ушло. Программа привозит эту шкалу такой же, "
                        + "как та, что выше, чтобы цвет всюду значил одно и то же; сдвинув её "
                        + "здесь, вы заводите собственный язык цвета для них двоих."
                ),
                unmeasuredOrigin: Phrase(
                    "Not measured: nobody publishes where a quota starts being worth planning "
                        + "around.",
                    "Не измерено: никто не публикует, с какого места квоту стоит планировать."
                ),
                provenance: config.limitUsage.provenance,
                isChosen: config.limitUsage.isChosen
            ),
            MarkNote(
                mark: .abandonedWait,
                title: Phrase("Stop expecting an answer after", "Перестать ждать ответа через"),
                what: Phrase(
                    "How long a session may owe an answer in silence before one stops being "
                        + "expected out of it: past this, its light stops blinking and is drawn "
                        + "as a figure eight. Nothing on disk says a session died — a closed "
                        + "terminal and an agent hard at work look the same — so this is how "
                        + "long the app goes on promising an answer. Raise it if a long tool "
                        + "call stops the light while you are still waiting.",
                    "Сколько сессия может молча оставаться должна ответ, прежде чем его "
                        + "перестанут ждать: после этого её огонь перестаёт мигать и рисуется "
                        + "восьмёркой. На диске ничего не говорит, что сессия умерла — закрытый "
                        + "терминал и агент за работой выглядят одинаково, — так что это срок, "
                        + "в течение которого программа продолжает обещать ответ. Поднимите "
                        + "его, если долгий вызов инструмента гасит огонь, пока вы ещё ждёте."
                ),
                provenance: config.abandonedWait.provenance,
                isChosen: config.abandonedWait.isChosen
            ),
            MarkNote(
                mark: .attentionNotice,
                title: Phrase("Announce a request for you after", "Сообщать о просьбе к вам через"),
                what: Phrase(
                    "How long the agent may be waiting on you before a notification is sent. "
                        + "The pause sign in the panel appears the moment the request does; "
                        + "this delays the notification alone, so a question answered by "
                        + "somebody sitting at the terminal is never announced at all.",
                    "Сколько агент может ждать вас, прежде чем уйдёт уведомление. Знак паузы на "
                        + "панели появляется вместе с просьбой; отложено только уведомление, "
                        + "так что вопрос, на который ответили прямо в терминале, не объявляют "
                        + "вовсе."
                ),
                provenance: config.attentionNotice.provenance,
                isChosen: config.attentionNotice.isChosen
            ),
            MarkNote(
                mark: .sessionActivity,
                title: Phrase("Keep a session on the list for", "Держать сессию в списке"),
                what: Phrase(
                    "How recently a session must have been written to for the panel to list it "
                        + "at all. It warns about nothing and lights nothing: it decides what "
                        + "you are looking at. Raise it if sessions you are still working on "
                        + "drop off the list; lower it if finished ones linger.",
                    "Насколько недавно в сессию должны были писать, чтобы панель вообще её "
                        + "показывала. Эта отметка ни о чём не предупреждает и ничего не "
                        + "зажигает: она решает, на что вы смотрите. Поднимите её, если "
                        + "сессии, над которыми вы ещё работаете, уходят из списка; опустите, "
                        + "если законченные задерживаются."
                ),
                provenance: config.sessionActivity.provenance,
                isChosen: config.sessionActivity.isChosen
            )
        ]
    }

    public static let furtherReadingTitle = Phrase(
        "Why a full window is worth watching at all",
        "Зачем вообще следить за наполнением окна"
    )

    public static let furtherReadingNote = Phrase(
        "None of these set a mark. They are the published work the premise rests on, so it can "
            + "be checked rather than taken on trust.",
        "Ни одна из них не задаёт отметку. Это опубликованные работы, на которых держится сама "
            + "предпосылка, — чтобы её можно было проверить, а не принимать на веру."
    )

    public static let furtherReading: [Reading] = [
        Reading(
            title: Phrase.name("Chroma: Context Rot"),
            year: "2025",
            note: Phrase(
                "18 models, simple retrieval tasks: every one degrades as the input grows, and "
                    + "none of them falls off a cliff you could mark.",
                "18 моделей, простые задачи на поиск: с ростом входа хуже становится у каждой, "
                    + "и ни у одной нет обрыва, на котором можно поставить отметку."
            ),
            url: "https://www.trychroma.com/research/context-rot"
        ),
        Reading(
            title: Phrase.name("Context Is What You Need (MECW)"),
            year: "2026",
            note: Phrase(
                "Effective context is a property of the task, not the model — on hard problems "
                    + "it collapses to a few hundred tokens. Why no absolute mark is honest.",
                "Полезный контекст — свойство задачи, а не модели: на трудных задачах он "
                    + "схлопывается до пары сотен токенов. Отсюда и вывод, что честной "
                    + "абсолютной отметки нет."
            ),
            url: "https://arxiv.org/abs/2509.21361"
        ),
        Reading(
            title: Phrase.name("Classifier Context Rot"),
            year: "2026",
            note: Phrase(
                "Recall falls as the prefix grows — and worst when what matters sits in the "
                    + "middle of it.",
                "С ростом префикса полнота падает — и сильнее всего тогда, когда важное лежит "
                    + "у него в середине."
            ),
            url: "https://arxiv.org/html/2605.12366v1"
        ),
        Reading(
            title: Phrase.name("The Limits of Long-Context Reasoning in Automated Bug Fixing"),
            year: "2026",
            note: Phrase(
                "Successful agent runs stay under 20–30K tokens; longer contexts resolve less "
                    + "often.",
                "Удачные прогоны агента укладываются в 20–30K токенов; с более длинным "
                    + "контекстом задача решается реже."
            ),
            url: "https://arxiv.org/html/2602.16069v2"
        ),
        Reading(
            title: Phrase.name("TraceLab"),
            year: "2026",
            note: Phrase(
                "Prefix length at p99: 918K on Claude, 231K on Codex. Long sessions are not a "
                    + "corner case.",
                "Длина префикса на p99: 918K у Claude, 231K у Codex. Длинные сессии — не редкий "
                    + "случай."
            ),
            url: "https://arxiv.org/html/2606.30560v1"
        ),
        Reading(
            title: Phrase.name("Lost in the Middle"),
            year: "2024",
            note: Phrase(
                "The middle of a context is used markedly worse than either end — the mechanism "
                    + "behind the rest.",
                "Середина контекста используется заметно хуже обоих краёв — это механизм, "
                    + "стоящий за остальным."
            ),
            url: "https://arxiv.org/abs/2307.03172"
        )
    ]

    public static func items(for state: SetupState) -> [BriefingItem] {
        SetupState.Source.allCases.map { source in
            let connected = state.isConnected(source)
            return BriefingItem(
                source: source,
                title: title(of: source),
                detail: connected ? connectedDetail(of: source) : missingDetail(of: source),
                isConnected: connected
            )
        }
    }

    private static func title(of source: SetupState.Source) -> Phrase {
        switch source {
        case .claudeLimits:
            Phrase(
                "Claude limits and context window size",
                "Лимиты Claude и размер окна контекста"
            )
        case .claudeSessions:
            Phrase("Claude context budget", "Бюджет контекста Claude")
        case .codex:
            Phrase("Codex limits and context budget", "Лимиты и бюджет контекста Codex")
        }
    }

    private static func connectedDetail(of source: SetupState.Source) -> Phrase {
        switch source {
        case .claudeLimits:
            Phrase(
                "Connected. The app holds Claude Code's status line slot and reports for every "
                    + "session.",
                "Подключено. Программа держит слот строки состояния Claude Code и сообщает "
                    + "показания по каждой сессии."
            )
        case .claudeSessions:
            Phrase(
                "Read from ~/.claude/projects, which Claude Code writes as it answers.",
                "Читается из ~/.claude/projects, куда Claude Code пишет по ходу ответов."
            )
        case .codex:
            Phrase(
                "Read from ~/.codex/sessions, which Codex writes as it answers.",
                "Читается из ~/.codex/sessions, куда Codex пишет по ходу ответов."
            )
        }
    }

    private static func missingDetail(of source: SetupState.Source) -> Phrase {
        switch source {
        case .claudeLimits:
            return Phrase(
                "Claude hands these to its status line and to nothing else — no file under "
                    + "~/.claude carries them. Press \(connectAction.english) to connect: it "
                    + "shows what it will change in ~/.claude/settings.json before changing it, "
                    + "and keeps any status line you already have.",
                "Claude отдаёт их своей строке состояния и больше никуда — ни один файл в "
                    + "~/.claude их не несёт. Нажмите \(connectAction.russian), чтобы "
                    + "подключить: перед правкой ~/.claude/settings.json программа покажет, что "
                    + "именно поменяет, и сохранит вашу строку состояния, если она есть."
            )
        case .claudeSessions:
            return Phrase(
                "Nothing in ~/.claude/projects yet. It fills in by itself the first time Claude "
                    + "Code answers; nothing to connect.",
                "В ~/.claude/projects пока пусто. Оно заполнится само при первом ответе Claude "
                    + "Code; подключать нечего."
            )
        case .codex:
            return Phrase(
                "Nothing in ~/.codex/sessions yet. It fills in by itself the first time Codex "
                    + "answers; nothing to connect.",
                "В ~/.codex/sessions пока пусто. Оно заполнится само при первом ответе Codex; "
                    + "подключать нечего."
            )
        }
    }
}
