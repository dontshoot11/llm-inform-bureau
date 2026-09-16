import Foundation

/// Where a number in the threshold config came from.
///
/// Numbers like these go stale faster than the code around them, so a measured one carries
/// its date and its source. Its absence is not an oversight: it marks a number nobody has
/// measured, and the interface is allowed to say so.
public struct ThresholdProvenance: Equatable, Sendable {
    /// Date the number was published, `YYYY-MM-DD`.
    public let measuredAt: String
    public let source: URL

    public init(measuredAt: String, source: URL) {
        self.measuredAt = measuredAt
        self.source = source
    }
}

/// Three percentage marks on one scale: worth knowing, worth saying, worth acting on.
///
/// The lowest mark colours a light and nothing more. It is deliberately quiet: a share that
/// almost every session passes would, as a notification, only teach the user to ignore the
/// app. Which marks speak is a property of the scale and not of the caller, which is why
/// `crossed(by:)` returns the notifying marks alone.
public struct PercentMarks: Equatable, Sendable {
    /// Colours the light. Never notifies.
    public let notice: Double
    public let elevated: Double
    public let high: Double
    public let rationale: String
    public let provenance: ThresholdProvenance?

    public var isMeasured: Bool { provenance != nil }

    public init(
        notice: Double,
        elevated: Double,
        high: Double,
        rationale: String,
        provenance: ThresholdProvenance?
    ) {
        self.notice = notice
        self.elevated = elevated
        self.high = high
        self.rationale = rationale
        self.provenance = provenance
    }

    /// Where a measured percentage falls. Every mark is exclusive: a session sitting exactly
    /// on 40% has not crossed it yet.
    public func level(for percent: Double) -> BudgetLevel {
        if percent > high { return .high }
        if percent > elevated { return .elevated }
        if percent > notice { return .notice }
        return .normal
    }

    /// The mark that puts a reading at this level — what the panel names when it says why a
    /// light is the colour it is. Not the same question as which marks notify: the notice mark
    /// colours a light it will never speak about, and naming the measurement instead would
    /// pass a reading off as a mark.
    public func mark(for level: BudgetLevel) -> Double? {
        switch level {
        case .normal: nil
        case .notice: notice
        case .elevated: elevated
        case .high: high
        }
    }

    /// The marks this percentage has passed that are worth a notification, lower one first —
    /// crossing 60% and crossing 90% are two different things to be told about. The notice
    /// mark is not among them by design.
    public func crossed(by percent: Double) -> [Double] {
        [elevated, high].filter { percent > $0 }
    }
}

/// How big a single turn has to be to count as expensive.
public struct TurnGrowthThreshold: Equatable, Sendable {
    /// Growth as a share of the context window.
    public let windowSharePercent: Double
    /// Growth in absolute tokens.
    public let tokens: Int
    public let rationale: String
    public let provenance: ThresholdProvenance?

    public var isMeasured: Bool { provenance != nil }

    public init(
        windowSharePercent: Double,
        tokens: Int,
        rationale: String,
        provenance: ThresholdProvenance?
    ) {
        self.windowSharePercent = windowSharePercent
        self.tokens = tokens
        self.rationale = rationale
        self.provenance = provenance
    }

    /// `true` when this much growth over one turn is worth a word.
    ///
    /// Either ceiling is enough, and the absolute one is not a stand-in for an unknown window:
    /// on a 1M window a tenth of it is 100K, so a share-only rule would go quiet on exactly
    /// the longest sessions, where a jump of that size matters most.
    public func isCrossed(byGrowth growth: Int, inWindow window: Int?) -> Bool {
        if growth > tokens { return true }
        guard let window, window > 0 else { return false }
        return Double(growth) / Double(window) * 100 > windowSharePercent
    }
}

/// How little of a limit window may be left before its marks stop speaking.
public struct WindowResetThreshold: Equatable, Sendable {
    /// Share of the window's own length still to run, below which its marks stay quiet.
    public let remainingSharePercent: Double
    public let rationale: String
    public let provenance: ThresholdProvenance?

    public var isMeasured: Bool { provenance != nil }

    public init(remainingSharePercent: Double, rationale: String, provenance: ThresholdProvenance?) {
        self.remainingSharePercent = remainingSharePercent
        self.rationale = rationale
        self.provenance = provenance
    }

    /// `true` when the window comes back so soon that saying anything about it is noise.
    ///
    /// A window that never said when it resets is never silenced: an unknown reset time is
    /// not evidence that it is near.
    public func silences(_ window: LimitWindow, now: Date) -> Bool {
        guard let resetsAt = window.resetsAt else { return false }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return true }
        let length = TimeInterval(window.nominalMinutes) * 60
        guard length > 0 else { return false }
        return remaining / length * 100 < remainingSharePercent
    }
}

/// How recently a session must have been written to for the widget to call it active.
public struct DurationThreshold: Equatable, Sendable {
    public let minutes: Int
    public let rationale: String
    public let provenance: ThresholdProvenance?

    public var isMeasured: Bool { provenance != nil }

    public var seconds: TimeInterval { TimeInterval(minutes) * 60 }

    public init(minutes: Int, rationale: String, provenance: ThresholdProvenance?) {
        self.minutes = minutes
        self.rationale = rationale
        self.provenance = provenance
    }
}

/// The thresholds the rules work against, read from a file rather than baked into the logic.
///
/// Format, current values and how to change them: `Thresholds.md` next to this file.
public struct ThresholdConfig: Equatable, Sendable {
    /// Format version, so a changed schema is detected rather than mis-read.
    public static let currentVersion = 5

    public let version: Int

    /// Share of the context window in use. Both services.
    public let windowFill: PercentMarks

    /// Growth over a single turn.
    public let expensiveTurn: TurnGrowthThreshold

    /// Share of a subscription limit window spent. Both services, same scale as the context.
    public let limitUsage: PercentMarks

    /// When a limit window is close enough to resetting that its marks stay quiet.
    public let limitWindowNearlyReset: WindowResetThreshold

    /// How recently a session must have been written to to count as being worked on.
    /// Not a budget mark — it decides what the widget shows rather than what it warns about.
    public let sessionActivity: DurationThreshold

    /// How long a session may owe an answer in silence before nobody is taken to be waiting
    /// on it. The fuse under the blinking light — `SessionActivity.isStillWaiting`.
    public let abandonedWait: DurationThreshold

    public init(
        version: Int,
        windowFill: PercentMarks,
        expensiveTurn: TurnGrowthThreshold,
        limitUsage: PercentMarks,
        limitWindowNearlyReset: WindowResetThreshold,
        sessionActivity: DurationThreshold,
        abandonedWait: DurationThreshold
    ) {
        self.version = version
        self.windowFill = windowFill
        self.expensiveTurn = expensiveTurn
        self.limitUsage = limitUsage
        self.limitWindowNearlyReset = limitWindowNearlyReset
        self.sessionActivity = sessionActivity
        self.abandonedWait = abandonedWait
    }

    /// The floor under the floor: the values compiled into the app, used when even the
    /// bundled copy of the config cannot be read. They are the same numbers as
    /// `Resources/thresholds.json`, and a test fails if the two ever drift apart.
    public static let builtIn = ThresholdConfig(
        version: currentVersion,
        windowFill: PercentMarks(
            notice: 40,
            elevated: 60,
            high: 90,
            rationale: """
                Three marks on one scale, and the scale is the claim: the fuller the window, \
                the more of it is old and no longer load-bearing, and the higher the risk that \
                the model is working around its own history. None of the three measures that \
                risk — no such measurement exists for the current generation, and the vendors' \
                own position is that quality holds across the window. 40% and 60% are ours; \
                the yellow one was 30% until 2026-09-15 and was raised because a mark that \
                nearly every session and nearly every limit window reaches says nothing by \
                the time it is lit. So is 90%, but it is placed against a published fact: Claude Code compacts at \
                about 967K on a native 1M window and at the 200K boundary on a 200K one \
                (code.claude.com/docs/en/model-config, checked 2026-09-15), so 90% is the last \
                point at which a warning still arrives before the CLI rewrites the session \
                itself. Codex configures its own compaction point and does not publish it.
                """,
            provenance: nil
        ),
        expensiveTurn: TurnGrowthThreshold(
            windowSharePercent: 10,
            tokens: 20_000,
            rationale: """
                Not measured. Two ceilings, either of which is enough: a turn worth a tenth of \
                the window, or 20K tokens outright. The absolute one is not a fallback for an \
                unknown window — on a 1M window a tenth of it is 100K, so a share-only rule \
                would go quiet on exactly the longest sessions.
                """,
            provenance: nil
        ),
        limitUsage: PercentMarks(
            notice: 40,
            elevated: 60,
            high: 90,
            rationale: """
                The same three marks as the context scale, deliberately: a colour means one \
                thing everywhere in the widget rather than one thing per light. Not measured — \
                nobody publishes where a subscription window starts being worth planning \
                around, and the 60 / 80 this replaces were ours as well. The yellow mark \
                moved from 30% to 40% on 2026-09-15, with the context scale and for the same \
                reason: a third of a window gone is not yet news about either of them.
                """,
            provenance: nil
        ),
        limitWindowNearlyReset: WindowResetThreshold(
            remainingSharePercent: 5,
            rationale: """
                Not measured. A limit window's marks stay quiet once less than this share of \
                its own length is left to run: 60% of a weekly window with five days to go and \
                60% of a five-hour one with twenty minutes to go are different situations, and \
                interrupting someone over a window about to come back on its own is noise. A \
                share of the window rather than a number of minutes, because five hours and a \
                week are not comparable in absolute time.
                """,
            provenance: nil
        ),
        sessionActivity: DurationThreshold(
            minutes: 30,
            rationale: """
                Not measured — a sensible default. Thirty minutes is where a session being \
                worked on stops looking like one that is finished; it was chosen for that \
                rather than derived, and any number in the same neighbourhood lists the same \
                sessions. Correct it if running sessions drop off the list, or finished ones \
                linger on it.
                """,
            provenance: nil
        ),
        abandonedWait: DurationThreshold(
            minutes: 10,
            rationale: """
                Not measured — a sensible default, and the app is handed to people whose \
                sessions are not the ones it was written on. Nothing on disk says a session \
                died: a closed terminal, a killed process and an agent hard at work all look \
                like an entry that owes an answer and nothing after it. So a wait that has \
                gone this long without a word is presumed abandoned and its light stops \
                blinking, while the session itself stays listed for its own half hour. The \
                number only has to be longer than the longest silence inside a turn that is \
                really running — a working turn writes an entry every few seconds — and \
                short enough that nobody watches a dead session blink. Raise it if a long \
                tool call stops the light while you are still waiting; lower it if a closed \
                terminal keeps blinking too long afterwards.
                """,
            provenance: nil
        )
    )
}
