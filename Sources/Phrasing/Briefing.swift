import Foundation
import SessionHealthCore

/// One source, as the first-run explanation presents it.
public struct BriefingItem: Equatable, Sendable {
    public let source: SetupState.Source
    /// What this source gives, not what file it is.
    public let title: String
    /// Where it comes from, and — when it is not connected — what to run.
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
    public let title: String
    /// The lights this mark turns on, when it is a scale. Empty for a mark that is one number.
    public let scale: [ScaleStep]
    /// What this mark is set to, in words. Empty when `scale` carries it instead.
    public let value: String
    private let unmeasuredNote: String
    public let provenance: ThresholdProvenance?

    public init(
        title: String,
        scale: [ScaleStep] = [],
        value: String = "",
        unmeasuredNote: String,
        provenance: ThresholdProvenance?
    ) {
        self.title = title
        self.scale = scale
        self.value = value
        self.unmeasuredNote = unmeasuredNote
        self.provenance = provenance
    }

    /// The line under the number. A measured mark names its date; an unmeasured one says it is
    /// a guess, because a number with an invented source lies silently and nothing catches it.
    public var note: String {
        guard let provenance else { return unmeasuredNote }
        return "Published \(provenance.measuredAt)"
    }

    public var source: URL? { provenance?.source }
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
/// from and names the one command that has to be run — and says it again in the panel for as
/// long as something is still missing.
///
/// The claim about the network is in the first sentence on purpose: an app that reads the
/// transcripts of two coding agents should say what it does with them before it is asked.
public enum Briefing {
    public static let title = "Where the numbers come from"

    public static let intro = """
        Everything is read from files this Mac already has. The app makes no network calls, \
        holds no credentials, and writes nothing outside its own folder in Application Support.
        """

    /// Said at the end, because the alternative — a zero — is what every other widget shows
    /// for something it does not know.
    public static let closing = """
        Until a source has reported, the panel says what it does not know rather than showing \
        it as zero.
        """

    /// The one command a person has to run, named in one place so the window, the panel and
    /// the README cannot drift apart.
    public static let statusLineCommand = "Scripts/install-statusline.sh"

    public static let marksTitle = "The marks it watches"

    /// Said under the marks, because it is the one thing the dots beside them cannot show.
    public static let marksNote = """
        Yellow only colours a light. Orange and red also send a notification — each one once \
        per session.
        """

    /// The same scale in one line, for the tooltip on a light in the panel.
    public static func scaleHelp(_ config: ThresholdConfig) -> String {
        "Yellow past \(TokenDisplay.percent(config.windowFill.notice)) of the window, orange past "
            + "\(TokenDisplay.percent(config.windowFill.elevated)), red past "
            + "\(TokenDisplay.percent(config.windowFill.high)) — how full it is. Orange and red notify."
    }

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
                title: "Context window filled",
                scale: steps(config.windowFill),
                unmeasuredNote: """
                    How much of the window a session is holding. The fuller it gets, the more \
                    of it is history that has stopped earning its place — and the more of that \
                    there is, the more it weighs on what the model concludes.
                    """,
                provenance: config.windowFill.provenance
            ),
            MarkNote(
                title: "Subscription limit spent",
                scale: steps(config.limitUsage),
                unmeasuredNote: """
                    The same scale, so a colour means one thing everywhere in the widget. Not \
                    measured: nobody publishes where a quota starts being worth planning around.
                    """,
                provenance: config.limitUsage.provenance
            ),
            MarkNote(
                title: "One expensive request",
                value: "\(TokenDisplay.percent(config.expensiveTurn.windowSharePercent)) of the window"
                    + " or \(TokenDisplay.short(config.expensiveTurn.tokens)) tokens",
                unmeasuredNote: "Not measured — a starting default, to be corrected by experience. Either ceiling is enough.",
                provenance: config.expensiveTurn.provenance
            ),
            MarkNote(
                title: "A limit window about to reset",
                value: "under \(TokenDisplay.percent(config.limitWindowNearlyReset.remainingSharePercent)) of it left to run",
                unmeasuredNote: "Not measured. Below this the limit marks stay quiet: the window comes back before it can get in the way.",
                provenance: config.limitWindowNearlyReset.provenance
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
            "Connected. The statusLine wrapper is reporting for every Claude session."
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
            ~/.claude carries them. Run \(statusLineCommand) to connect the wrapper: it shows \
            what it will change before changing it, and keeps any status line you already have.
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
