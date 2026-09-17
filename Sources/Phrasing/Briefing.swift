import Foundation
import SessionHealthCore

/// One source, as the first-run explanation presents it.
public struct BriefingItem: Equatable, Sendable {
    public let source: SetupState.Source
    /// What this source gives, not what file it is.
    public let title: String
    /// Where it comes from, and — when it is not connected — how to connect it.
    public let detail: String
    public let isConnected: Bool

    public init(source: SetupState.Source, title: String, detail: String, isConnected: Bool) {
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

    public var label: String { TokenDisplay.percent(percent) }
}

/// One mark, as the first-run window presents it: what it is, what it is set to, and who says
/// so — a published source with its date, or an admission that nobody published one.
public struct MarkNote: Equatable, Sendable {
    /// Which mark this is — the identity the window moves, rather than the title it shows.
    public let mark: ThresholdMark
    public let title: String
    /// The lights this mark turns on, when it is a scale. Empty for a mark that is one number,
    /// which the window shows as the number itself.
    public let scale: [ScaleStep]
    private let unmeasuredNote: String
    public let provenance: ThresholdProvenance?
    /// `true` when the person moved this mark themselves.
    public let isChosen: Bool

    public init(
        mark: ThresholdMark,
        title: String,
        scale: [ScaleStep] = [],
        unmeasuredNote: String,
        provenance: ThresholdProvenance?,
        isChosen: Bool = false
    ) {
        self.mark = mark
        self.title = title
        self.scale = scale
        self.unmeasuredNote = unmeasuredNote
        self.provenance = provenance
        self.isChosen = isChosen
    }

    /// The line under the number, or nothing at all.
    ///
    /// A measured mark names its date; an unmeasured one says it is a guess, because a number
    /// with an invented source lies silently and nothing catches it. A mark somebody moved says
    /// neither: the reasoning that shipped was written about a different number, and what has
    /// replaced it is the button beside the mark, which only appears when the mark is not where
    /// the app put it. A line saying the same thing in words was one line too many.
    public var note: String {
        if isChosen { return "" }
        guard let provenance else { return unmeasuredNote }
        return "Published \(provenance.measuredAt)"
    }

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
    public let meaning: String

    public init(level: BudgetLevel, meaning: String) {
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
    public let title: String
    public let year: String
    public let note: String
    private let url: String

    public init(title: String, year: String, note: String, url: String) {
        self.title = title
        self.year = year
        self.note = note
        self.url = url
    }

    /// Optional rather than force-unwrapped: a typo in a reading list is not worth a crash in
    /// a widget that runs all day.
    public var source: URL? { URL(string: url) }
}

/// What the app says about itself the first time it runs.
///
/// Two of its three sources connect themselves and one does not, and a person cannot tell
/// which is which from a panel of em dashes. So the first launch says where every number comes
/// from and names the one thing that has to be connected by hand — and says it again in the
/// panel, where the button to do it stands, for as long as it is missing.
///
/// The claim about the network is in the first sentence on purpose: an app that reads the
/// transcripts of two coding agents should say what it does with them before it is asked.
public enum Briefing {
    /// The window's own name. It is a settings window now — the marks are moved in it — and
    /// the explanation of where the readings come from is one of the things folded up inside.
    public static let windowTitle = "Settings"

    public static let title = "Where the numbers come from"

    public static let intro = """
        Everything is read from files this Mac already has. The app makes no network calls and \
        holds no credentials. It keeps its own files in Application Support, and the one thing \
        it writes anywhere else is a single key in ~/.claude/settings.json — only if you \
        connect the limits, and never without showing the change first.
        """

    /// Said at the end, because the alternative — a zero — is what every other widget shows
    /// for something it does not know.
    public static let closing = """
        Until a source has reported, the panel says what it does not know rather than showing \
        it as zero.
        """

    /// How the one source that has to be connected is connected, named in one place so the
    /// window, the panel and the README cannot drift apart. The button itself is
    /// `SlotPhrasing.connect`, so the sentence and the thing it tells you to press cannot come
    /// to disagree.
    public static let connectAction = "the \"\(SlotPhrasing.connect)\" button in the panel"

    public static let marksTitle = "The marks it watches"

    /// What each colour is like to be in, above the marks that say where it starts. Every
    /// colour the widget can draw is here, green included: a dot that never gets explained is
    /// the one a reader invents a meaning for.
    public static let levelKey: [LevelMeaning] = [
        LevelMeaning(level: .normal, meaning: "Comfort zone."),
        LevelMeaning(level: .notice, meaning: "Noticeable, nothing to do about it yet."),
        LevelMeaning(level: .elevated, meaning: "Worth your attention."),
        LevelMeaning(level: .high, meaning: "Step away from the keyboard. Go and touch some grass.")
    ]

    /// The same scale in one line, for the tooltip on a light in the panel.
    public static func scaleHelp(_ config: ThresholdConfig) -> String {
        "Yellow past \(TokenDisplay.percent(config.windowFill.notice)) of the window, orange past "
            + "\(TokenDisplay.percent(config.windowFill.elevated)), red past "
            + "\(TokenDisplay.percent(config.windowFill.high)) — how full it is. Orange and red notify."
    }

    /// Puts a mark back where the app had it. Shown only on a mark that was moved: a button
    /// that undoes nothing is a control a reader learns to skip over.
    public static let resetMark = "Reset to default"

    /// How the bar is worked, said once under it. Dragging is discoverable; the arrow keys are
    /// not, and they are the only way to land on an exact number.
    public static let markEditHint = "Drag a mark to move it, or click one and use the arrow keys."

    /// The unit of the marks that are one number. Beside the field rather than in the title,
    /// because the number is what changes and the unit is what it is measured in.
    public static let minuteUnit = "min"

    /// What a field of minutes is called when it is read out rather than looked at: the number
    /// on its own says nothing about which mark it belongs to.
    public static func minuteFieldLabel(of markTitle: String) -> String {
        "\(markTitle), in minutes"
    }

    /// What a handle of a scale is called when it is read out rather than looked at — a mark
    /// is a colour, and a colour is exactly what a screen reader cannot pass on.
    public static func handleLabel(_ handle: MarkScale.Handle, of markTitle: String) -> String {
        switch handle {
        case .notice: "\(markTitle): the yellow mark"
        case .elevated: "\(markTitle): the orange mark"
        case .high: "\(markTitle): the red mark"
        }
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
                title: "Context window filled",
                scale: steps(config.windowFill),
                unmeasuredNote: """
                    How much of the window a session is holding. The fuller it gets, the more \
                    of it is history that has stopped earning its place — and the more of that \
                    there is, the more it weighs on what the model concludes.
                    """,
                provenance: config.windowFill.provenance,
                isChosen: config.windowFill.isChosen
            ),
            MarkNote(
                mark: .limitUsage,
                title: "Subscription limit spent",
                scale: steps(config.limitUsage),
                unmeasuredNote: """
                    The same scale, so a colour means one thing everywhere in the widget. Not \
                    measured: nobody publishes where a quota starts being worth planning around.
                    """,
                provenance: config.limitUsage.provenance,
                isChosen: config.limitUsage.isChosen
            ),
            MarkNote(
                mark: .abandonedWait,
                title: "Stop expecting an answer after",
                unmeasuredNote: """
                    How long a session may owe an answer in silence before one stops being \
                    expected out of it: past this, its light stops blinking and is drawn as a \
                    figure eight. Nothing on disk says a session died — a closed terminal and \
                    an agent hard at work look the same — so this is how long the app goes on \
                    promising an answer. Raise it if a long tool call stops the light while \
                    you are still waiting.
                    """,
                provenance: config.abandonedWait.provenance,
                isChosen: config.abandonedWait.isChosen
            ),
            MarkNote(
                mark: .attentionNotice,
                title: "Announce a request for you after",
                unmeasuredNote: """
                    How long the agent may be waiting on you before a notification is sent. \
                    The pause sign in the panel appears the moment the request does; this \
                    delays the notification alone, so a question answered by somebody sitting \
                    at the terminal is never announced at all.
                    """,
                provenance: config.attentionNotice.provenance,
                isChosen: config.attentionNotice.isChosen
            ),
            MarkNote(
                mark: .sessionActivity,
                title: "Keep a session on the list for",
                unmeasuredNote: """
                    How recently a session must have been written to for the panel to list it \
                    at all. It warns about nothing and lights nothing: it decides what you are \
                    looking at. Raise it if sessions you are still working on drop off the \
                    list; lower it if finished ones linger.
                    """,
                provenance: config.sessionActivity.provenance,
                isChosen: config.sessionActivity.isChosen
            )
        ]
    }

    public static let furtherReadingTitle = "Why a full window is worth watching at all"

    public static let furtherReadingNote = """
        None of these set a mark. They are the published work the premise rests on, so it can \
        be checked rather than taken on trust.
        """

    public static let furtherReading: [Reading] = [
        Reading(
            title: "Chroma: Context Rot",
            year: "2025",
            note: "18 models, simple retrieval tasks: every one degrades as the input grows, and none of them falls off a cliff you could mark.",
            url: "https://www.trychroma.com/research/context-rot"
        ),
        Reading(
            title: "Context Is What You Need (MECW)",
            year: "2026",
            note: "Effective context is a property of the task, not the model — on hard problems it collapses to a few hundred tokens. Why no absolute mark is honest.",
            url: "https://arxiv.org/abs/2509.21361"
        ),
        Reading(
            title: "Classifier Context Rot",
            year: "2026",
            note: "Recall falls as the prefix grows — and worst when what matters sits in the middle of it.",
            url: "https://arxiv.org/html/2605.12366v1"
        ),
        Reading(
            title: "The Limits of Long-Context Reasoning in Automated Bug Fixing",
            year: "2026",
            note: "Successful agent runs stay under 20–30K tokens; longer contexts resolve less often.",
            url: "https://arxiv.org/html/2602.16069v2"
        ),
        Reading(
            title: "TraceLab",
            year: "2026",
            note: "Prefix length at p99: 918K on Claude, 231K on Codex. Long sessions are not a corner case.",
            url: "https://arxiv.org/html/2606.30560v1"
        ),
        Reading(
            title: "Lost in the Middle",
            year: "2024",
            note: "The middle of a context is used markedly worse than either end — the mechanism behind the rest.",
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

    private static func title(of source: SetupState.Source) -> String {
        switch source {
        case .claudeLimits: "Claude limits and context window size"
        case .claudeSessions: "Claude context budget"
        case .codex: "Codex limits and context budget"
        }
    }

    private static func connectedDetail(of source: SetupState.Source) -> String {
        switch source {
        case .claudeLimits:
            "Connected. The app holds Claude Code's status line slot and reports for every session."
        case .claudeSessions:
            "Read from ~/.claude/projects, which Claude Code writes as it answers."
        case .codex:
            "Read from ~/.codex/sessions, which Codex writes as it answers."
        }
    }

    private static func missingDetail(of source: SetupState.Source) -> String {
        switch source {
        case .claudeLimits:
            """
            Claude hands these to its status line and to nothing else — no file under \
            ~/.claude carries them. Press \(connectAction) to connect: it shows what it will \
            change in ~/.claude/settings.json before changing it, and keeps any status line \
            you already have.
            """
        case .claudeSessions:
            """
            Nothing in ~/.claude/projects yet. It fills in by itself the first time Claude \
            Code answers; nothing to connect.
            """
        case .codex:
            """
            Nothing in ~/.codex/sessions yet. It fills in by itself the first time Codex \
            answers; nothing to connect.
            """
        }
    }
}
