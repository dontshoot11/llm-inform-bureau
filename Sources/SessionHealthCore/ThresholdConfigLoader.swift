import Foundation

/// Which copy of the threshold config the values came from.
public enum ThresholdConfigSource: Equatable, Sendable {
    /// A file outside the app bundle — editing it changes behaviour without a rebuild.
    case external(URL)
    /// The copy shipped inside the bundle, used when nothing is installed outside it.
    case bundled
    /// The values compiled into the app, used when even the bundled copy failed to load.
    case builtIn
}

/// A loaded config, where it came from, and everything the file got wrong.
public struct ThresholdConfigLoad: Equatable, Sendable {
    public let config: ThresholdConfig
    public let source: ThresholdConfigSource

    /// One line per problem found in the file, in the words the dropdown can show. Empty
    /// when the config was used exactly as written.
    public let problems: [String]

    /// `true` when at least one value had to fall back. The interface says so rather than
    /// quietly behaving differently from the file the user is looking at.
    public var usesFallbackValues: Bool { !problems.isEmpty }

    public init(config: ThresholdConfig, source: ThresholdConfigSource, problems: [String]) {
        self.config = config
        self.source = source
        self.problems = problems
    }
}

/// Reads the threshold config from disk.
///
/// The config lives outside the app bundle so that changing a threshold is a file edit rather
/// than a build. Nothing here throws: a broken file must not take the menu bar down with it,
/// so every failure degrades to the next copy down and is reported in `problems`.
///
/// Usage:
/// ```swift
/// let load = ThresholdConfigLoader.load()
/// let rules = BudgetRules(config: load.config)
/// if load.usesFallbackValues { /* the dropdown says "default values applied" */ }
/// ```
public enum ThresholdConfigLoader {
    /// Overrides the external path. For the tests and for running against a working copy.
    public static let environmentOverrideKey = "LLM_INFORM_BUREAU_THRESHOLDS"

    /// Path of the editable config: the environment override if set, otherwise the per-user
    /// copy in Application Support.
    public static func externalConfigURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment[environmentOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return SupportDirectory.url(home: home)
            .appendingPathComponent("thresholds.json", isDirectory: false)
    }

    /// The installed config when there is one, the bundled copy otherwise, the compiled-in
    /// values as the last resort.
    public static func load(at externalURL: URL? = nil) -> ThresholdConfigLoad {
        let bundled = loadBundled()
        let url = externalURL ?? externalConfigURL()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return bundled
        }
        guard let data = try? Data(contentsOf: url) else {
            return ThresholdConfigLoad(
                config: bundled.config,
                source: bundled.source,
                problems: bundled.problems + ["\(url.path) could not be read — the bundled thresholds are in use"]
            )
        }

        let parsed = ThresholdConfigParser.parse(data, fallback: bundled.config)
        return ThresholdConfigLoad(
            config: parsed.config,
            source: .external(url),
            problems: bundled.problems + parsed.problems
        )
    }

    /// The copy inside the bundle, falling back to the compiled-in values.
    public static func loadBundled() -> ThresholdConfigLoad {
        guard
            let url = Bundle.module.url(forResource: "thresholds", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return ThresholdConfigLoad(
                config: .builtIn,
                source: .builtIn,
                problems: ["the bundled thresholds.json is missing — built-in values are in use"]
            )
        }
        let parsed = ThresholdConfigParser.parse(data, fallback: .builtIn)
        return ThresholdConfigLoad(
            config: parsed.config,
            source: parsed.problems.isEmpty ? .bundled : .builtIn,
            problems: parsed.problems.map { "bundled thresholds.json: \($0)" }
        )
    }
}

/// Turns the config file into values, replacing anything unusable with the fallback and
/// saying what it replaced.
///
/// Written against `JSONSerialization` rather than `Decodable` on purpose: `Decodable` gives
/// one error and no values, and this app needs the opposite — every value it can use, plus a
/// list of what it could not. A half-broken file keeps the app running on the rest of it.
enum ThresholdConfigParser {
    static func parse(
        _ data: Data,
        fallback: ThresholdConfig
    ) -> (config: ThresholdConfig, problems: [String]) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (fallback, ["the file is not a JSON object — default values are in use"])
        }
        guard let version = root["version"] as? Int else {
            return (fallback, ["\"version\" is missing — default values are in use"])
        }
        guard version == ThresholdConfig.currentVersion else {
            return (
                fallback,
                ["version \(version) is not the format this app reads (\(ThresholdConfig.currentVersion)) — default values are in use"]
            )
        }

        var problems: [String] = []
        let context = object(root["context"], at: "context", problems: &problems)
        let limits = object(root["limits"], at: "limits", problems: &problems)
        let sessions = object(root["sessions"], at: "sessions", problems: &problems)

        let config = ThresholdConfig(
            version: version,
            windowFill: percentMarks(
                context?["window_fill_percent"],
                at: "context.window_fill_percent",
                fallback: fallback.windowFill,
                problems: &problems
            ),
            expensiveTurn: turnGrowth(
                context?["expensive_turn"],
                at: "context.expensive_turn",
                fallback: fallback.expensiveTurn,
                problems: &problems
            ),
            limitUsage: percentMarks(
                limits?["percent"],
                at: "limits.percent",
                fallback: fallback.limitUsage,
                problems: &problems
            ),
            limitWindowNearlyReset: windowReset(
                limits?["quiet_when_window_remaining_percent"],
                at: "limits.quiet_when_window_remaining_percent",
                fallback: fallback.limitWindowNearlyReset,
                problems: &problems
            ),
            sessionActivity: duration(
                sessions?["active_within_minutes"],
                at: "sessions.active_within_minutes",
                fallback: fallback.sessionActivity,
                problems: &problems
            ),
            abandonedWait: duration(
                sessions?["abandoned_wait_after_minutes"],
                at: "sessions.abandoned_wait_after_minutes",
                fallback: fallback.abandonedWait,
                problems: &problems
            )
        )
        return (config, problems)
    }

    // MARK: Entries

    private static func percentMarks(
        _ value: Any?,
        at path: String,
        fallback: PercentMarks,
        problems: inout [String]
    ) -> PercentMarks {
        let defaults = "the defaults \(fallback.notice)% / \(fallback.elevated)% / \(fallback.high)%"
        guard let entry = object(value, at: path, problems: &problems) else { return fallback }
        guard
            let notice = number(entry["notice"], at: "\(path).notice", problems: &problems),
            let elevated = number(entry["elevated"], at: "\(path).elevated", problems: &problems),
            let high = number(entry["high"], at: "\(path).high", problems: &problems)
        else {
            problems.append("\(path): \(defaults) are in use")
            return fallback
        }
        guard notice > 0, elevated > notice, high > elevated, high <= 100 else {
            problems.append(
                "\(path): \(notice)% / \(elevated)% / \(high)% is not an ordered scale inside 0-100 — \(defaults) are in use"
            )
            return fallback
        }
        return PercentMarks(
            notice: notice,
            elevated: elevated,
            high: high,
            rationale: rationale(entry, at: path, problems: &problems),
            provenance: provenance(entry["measurement"], at: path, problems: &problems)
        )
    }

    private static func windowReset(
        _ value: Any?,
        at path: String,
        fallback: WindowResetThreshold,
        problems: inout [String]
    ) -> WindowResetThreshold {
        guard let entry = object(value, at: path, problems: &problems) else { return fallback }
        guard
            let share = number(entry["remaining_percent"], at: "\(path).remaining_percent", problems: &problems),
            share > 0, share < 100
        else {
            problems.append(
                "\(path): \"remaining_percent\" must be a share inside 0-100 — the default \(fallback.remainingSharePercent)% is in use"
            )
            return fallback
        }
        return WindowResetThreshold(
            remainingSharePercent: share,
            rationale: rationale(entry, at: path, problems: &problems),
            provenance: provenance(entry["measurement"], at: path, problems: &problems)
        )
    }

    private static func turnGrowth(
        _ value: Any?,
        at path: String,
        fallback: TurnGrowthThreshold,
        problems: inout [String]
    ) -> TurnGrowthThreshold {
        guard let entry = object(value, at: path, problems: &problems) else { return fallback }
        guard
            let share = number(entry["window_share_percent"], at: "\(path).window_share_percent", problems: &problems),
            let tokens = number(entry["tokens"], at: "\(path).tokens", problems: &problems),
            share > 0, share <= 100, tokens > 0
        else {
            problems.append(
                "\(path): the defaults \(fallback.windowSharePercent)% / \(fallback.tokens) tokens are in use"
            )
            return fallback
        }
        return TurnGrowthThreshold(
            windowSharePercent: share,
            tokens: Int(tokens),
            rationale: rationale(entry, at: path, problems: &problems),
            provenance: provenance(entry["measurement"], at: path, problems: &problems)
        )
    }

    private static func duration(
        _ value: Any?,
        at path: String,
        fallback: DurationThreshold,
        problems: inout [String]
    ) -> DurationThreshold {
        guard let entry = object(value, at: path, problems: &problems) else { return fallback }
        guard let minutes = number(entry["minutes"], at: "\(path).minutes", problems: &problems), minutes > 0 else {
            problems.append("\(path): \"minutes\" must be a positive number — the default \(fallback.minutes) is in use")
            return fallback
        }
        return DurationThreshold(
            minutes: Int(minutes),
            rationale: rationale(entry, at: path, problems: &problems),
            provenance: provenance(entry["measurement"], at: path, problems: &problems)
        )
    }

    // MARK: Fields

    private static func object(
        _ value: Any?,
        at path: String,
        problems: inout [String]
    ) -> [String: Any]? {
        guard let dictionary = value as? [String: Any] else {
            problems.append("\"\(path)\" is missing or is not an object — defaults are in use")
            return nil
        }
        return dictionary
    }

    private static func number(_ value: Any?, at path: String, problems: inout [String]) -> Double? {
        guard let number = value as? NSNumber else {
            problems.append("\"\(path)\" is missing or is not a number")
            return nil
        }
        return number.doubleValue
    }

    /// A missing rationale changes no behaviour, so it costs a line in the report and nothing
    /// else — the numbers from the file are still used.
    private static func rationale(
        _ entry: [String: Any],
        at path: String,
        problems: inout [String]
    ) -> String {
        guard let text = entry["rationale"] as? String, !text.isEmpty else {
            problems.append("\(path): no \"rationale\" — the next person to edit this number will be guessing")
            return "(no rationale in the config)"
        }
        return text
    }

    /// Absent provenance is legal and means "nobody measured this". Present but broken is not,
    /// and is reported: an unreadable source is indistinguishable from an invented one.
    private static func provenance(
        _ value: Any?,
        at path: String,
        problems: inout [String]
    ) -> ThresholdProvenance? {
        guard let value, !(value is NSNull) else { return nil }
        guard
            let entry = value as? [String: Any],
            let measuredAt = entry["measured_at"] as? String,
            let source = entry["source"] as? String,
            let url = URL(string: source)
        else {
            problems.append("\(path): \"measurement\" is present but unreadable — the number counts as unmeasured")
            return nil
        }
        return ThresholdProvenance(measuredAt: measuredAt, source: url)
    }
}
