import Foundation

/// What the rules make of one session's context.
public struct ContextAssessment: Equatable, Sendable {
    public let sessionID: String
    public let service: AgentService
    public let contextTokens: Int

    /// Share of the window in use, or `nil` when the window size is unknown — in which case
    /// the interface shows tokens and no percentage, and no error.
    public let windowFillPercent: Double?

    /// The worst of the readings — the colour this session contributes to the menu bar.
    public let level: BudgetLevel

    /// Which crossed mark set that level, so the menu can say why the bar is the colour it
    /// is instead of leaving the user to guess. `nil` while the level is normal.
    public let levelSource: BudgetAlert.Kind?

    /// Every mark currently found crossed, lower ones first. Deduplication into "one mark,
    /// one notification" is `AlertMemory`'s job, not this one's.
    public let alerts: [BudgetAlert]

    /// Whether this reading is a subagent's. Its mark is drawn in full in the panel and does
    /// nothing else: it never notifies and never colours the service's light. The reason is
    /// the same for both — an agent lives for minutes and ends on its own, so a mark it
    /// crosses is worth looking at and never worth being interrupted by.
    public let isSubagent: Bool
}

/// What the rules make of one service's subscription limits.
public struct LimitsAssessment: Equatable, Sendable {
    public let service: AgentService
    public let level: BudgetLevel

    /// Which crossed mark set that level. `nil` while the level is normal.
    public let levelSource: BudgetAlert.Kind?

    public let alerts: [BudgetAlert]

    /// The most spent window — the number the menu bar has room for.
    public let worstUsedPercent: Double?

    /// The window that has nothing left in it, if one has.
    ///
    /// Not a threshold and deliberately not in the config, unlike every mark the rules compare
    /// against. Those are opinions about where to worry and they go stale; this is arithmetic —
    /// a window reporting all of itself as used has none of itself left. There is nothing here
    /// for a later measurement to correct.
    ///
    /// The whole window and not just its name, because what the interface has to say about a
    /// spent one is when it comes back.
    public let spentWindow: LimitWindow?

    public var isExhausted: Bool { spentWindow != nil }
}

/// The thresholds applied to what was read from disk.
///
/// Pure functions over value types: no files, no clock, no interface. Every number they
/// compare against comes from `ThresholdConfig`, which is why editing the config file changes
/// behaviour and editing this file does not.
///
/// Usage:
/// ```swift
/// let rules = BudgetRules(config: ThresholdConfigLoader.load().config)
/// let assessment = rules.assess(snapshot)
/// ```
public struct BudgetRules: Sendable {
    public let config: ThresholdConfig

    public init(config: ThresholdConfig) {
        self.config = config
    }

    /// The context level one service shows in the menu bar, or `nil` when it has nothing to
    /// show there.
    ///
    /// Two readings are left out, for two different reasons. A session whose window size
    /// nobody reported has no share to place on a scale made of shares — counting it as normal
    /// would paint a green light for a session the app cannot judge at all. And a subagent is
    /// left out because its mark is deliberately silent: a light it turned red would be a
    /// red dot in the menu bar that no notification ever explains.
    public static func serviceContextLevel(of assessments: [ContextAssessment]) -> BudgetLevel? {
        assessments
            .filter { !$0.isSubagent && $0.windowFillPercent != nil }
            .map(\.level)
            .max()
    }

    public func assess(_ snapshot: SessionSnapshot) -> ContextAssessment {
        var alerts: [BudgetAlert] = []
        var level = BudgetLevel.normal
        var levelSource: BudgetAlert.Kind?
        let fill = snapshot.windowFillPercent

        /// Records what raised the level, so only the reading that actually set it is named.
        func raise(to candidate: BudgetLevel, by kind: @autoclosure () -> BudgetAlert.Kind) {
            guard candidate > level else { return }
            level = candidate
            levelSource = kind()
        }

        if let fill {
            let reached = config.windowFill.level(for: fill)
            raise(to: reached, by: .windowFill(percent: config.windowFill.mark(for: reached) ?? fill))
            for mark in config.windowFill.crossed(by: fill) {
                alerts.append(
                    BudgetAlert(
                        kind: .windowFill(percent: mark),
                        service: snapshot.service,
                        percent: fill,
                        tokens: snapshot.contextTokens
                    )
                )
            }
        }

        // An expensive turn says something about the last turn, not about the state of the
        // session, so it never changes the colour — it is only worth a word.
        if let growth = snapshot.turnGrowthTokens,
           config.expensiveTurn.isCrossed(byGrowth: growth, inWindow: snapshot.contextWindowTokens) {
            alerts.append(
                BudgetAlert(
                    kind: .expensiveTurn(atContextTokens: snapshot.contextTokens),
                    service: snapshot.service,
                    percent: snapshot.contextWindowTokens.map { Double(growth) / Double($0) * 100 },
                    tokens: growth
                )
            )
        }

        return ContextAssessment(
            sessionID: snapshot.sessionID,
            service: snapshot.service,
            contextTokens: snapshot.contextTokens,
            windowFillPercent: fill,
            level: level,
            levelSource: levelSource,
            alerts: alerts,
            isSubagent: snapshot.isSubagent
        )
    }

    /// `now` decides which windows are too close to resetting to be worth a word, so it is a
    /// parameter rather than a call to the clock: the rules stay pure and the case is testable.
    public func assess(_ limits: LimitsSnapshot, now: Date = Date()) -> LimitsAssessment {
        var alerts: [BudgetAlert] = []
        var level = BudgetLevel.normal
        var levelSource: BudgetAlert.Kind?
        var spent: LimitWindow?

        for window in limits.windows {
            // Spent is read off the window rather than off a mark: "all of it used" is not an
            // opinion. The weekly one wins when both are gone — a 5-hour window coming back in
            // an hour changes nothing while the week's is still empty.
            if window.usedPercent >= 100, spent?.kind != .weekly {
                spent = window
            }
            let candidate = config.limitUsage.level(for: window.usedPercent)
            if candidate > level {
                level = candidate
                levelSource = .limitUsage(
                    window: window.kind,
                    percent: config.limitUsage.mark(for: candidate) ?? window.usedPercent
                )
            }
            // The colour still tells the truth about what is spent; only the interruption is
            // dropped. A window that comes back before it can get in the way is not worth
            // stopping someone for, and a window that never said when it resets is never
            // silenced on a guess.
            guard !config.limitWindowNearlyReset.silences(window, now: now) else { continue }

            for mark in config.limitUsage.crossed(by: window.usedPercent) {
                alerts.append(
                    BudgetAlert(
                        kind: .limitUsage(window: window.kind, percent: mark),
                        service: limits.service,
                        percent: window.usedPercent,
                        resetsAt: window.resetsAt
                    )
                )
            }
        }

        return LimitsAssessment(
            service: limits.service,
            level: level,
            levelSource: levelSource,
            alerts: alerts,
            worstUsedPercent: limits.worstUsedPercent,
            spentWindow: spent
        )
    }
}
