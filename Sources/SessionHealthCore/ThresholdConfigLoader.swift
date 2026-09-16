import Foundation

/// Which copy of the threshold config the values came from.
public enum ThresholdConfigSource: Equatable, Sendable {
    /// A file named from outside — the environment override, which is how the tests and a run
    /// against a working copy point the app at marks of their own. Never something a person
    /// installed: the app ships its marks and reads no others.
    case external(URL)
    /// The copy shipped inside the app, which is what every ordinary run uses.
    case bundled
    /// The values compiled into the app, used when even the shipped copy failed to load.
    case builtIn
}

/// A loaded config, where it came from, and everything the file got wrong.
public struct ThresholdConfigLoad: Equatable, Sendable {
    public let config: ThresholdConfig
    public let source: ThresholdConfigSource

    /// One line per problem found in the file. Empty when the config was used exactly as
    /// written — which is every ordinary run, because the only config an ordinary run reads is
    /// the one this app ships and a test keeps correct.
    ///
    /// Nothing in the interface shows these: the marks are the app's own business, and a person
    /// who never chose a number has nothing to do about one. What reads them is whoever is
    /// editing the file — the author, with the suite in front of them.
    public let problems: [String]

    /// `true` when at least one value had to fall back.
    public var usesFallbackValues: Bool { !problems.isEmpty }

    public init(config: ThresholdConfig, source: ThresholdConfigSource, problems: [String]) {
        self.config = config
        self.source = source
        self.problems = problems
    }
}

/// Reads the threshold config the app ships with.
///
/// The marks are data rather than code so that changing one is an edit to a file and a commit,
/// not a number hunted down in a rule — but the file is the app's, not the reader's. There is
/// no copy in Application Support, nothing is created on a first launch, and a copy left behind
/// by an older release is not read: nobody was going to hand-edit JSON to move a percentage,
/// and the way to choose these numbers will be the app's own settings.
///
/// Nothing here throws: a broken file must not take the menu bar down with it, so every failure
/// degrades to the next copy down and is listed in `problems` for whoever is editing it.
///
/// Usage:
/// ```swift
/// let load = ThresholdConfigLoader.load()
/// let rules = BudgetRules(config: load.config)
/// ```
public enum ThresholdConfigLoader {
    /// Reads marks from somewhere else entirely. For the tests and for running against a
    /// working copy — it is the only way anything but the shipped file is ever read.
    public static let environmentOverrideKey = "LLM_INFORM_BUREAU_THRESHOLDS"

    /// The file named by the override, when one is set. `nil` is the ordinary answer, and it
    /// means the app runs on its own marks.
    public static func overrideConfigURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let override = environment[environmentOverrideKey], !override.isEmpty else { return nil }
        return URL(fileURLWithPath: override)
    }

    /// The shipped copy, or the file an override names; the compiled-in values as the last
    /// resort.
    public static func load(at externalURL: URL? = nil) -> ThresholdConfigLoad {
        let bundled = loadBundled()
        guard let url = externalURL ?? overrideConfigURL() else { return bundled }

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
            let url = bundledConfigURL(),
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

    /// The copy of the config that ships inside the app.
    ///
    /// Found the way an app finds its own resources, with `Bundle.module` only as the fallback,
    /// and that order is the whole point. SwiftPM's `Bundle.module` looks in exactly two
    /// places — beside the `.app`, and at the absolute path of the build directory — and calls
    /// `fatalError` when it finds neither. `build-app.sh` puts the resource bundle where a Mac
    /// app keeps its resources, `Contents/Resources`, which is neither of those, so on the
    /// machine that built the app the build path carries it and on anybody else's the app dies
    /// on launch. Measured 2026-09-16: the build directory hidden, a copy of the bundle run,
    /// `could not load resource bundle`.
    ///
    /// Moving the bundle to the root of the `.app`, where the accessor does look, is not the
    /// way out: `codesign --verify --strict` refuses a Mac app with unsealed contents there,
    /// and the notification centre ignores a bundle whose signature does not hold.
    ///
    /// Nothing here knows SwiftPM's naming: the resources are searched for the file, so a
    /// renamed package or target costs nothing. The fallback is for the test binary, where the
    /// accessor's build path is the right answer.
    public static func bundledConfigURL() -> URL? {
        if let resources = Bundle.main.resourceURL {
            let nested = (try? FileManager.default.contentsOfDirectory(
                at: resources,
                includingPropertiesForKeys: nil
            )) ?? []
            for candidate in nested where candidate.pathExtension == "bundle" {
                if let url = Bundle(url: candidate)?.url(forResource: "thresholds", withExtension: "json") {
                    return url
                }
            }
        }
        return Bundle.module.url(forResource: "thresholds", withExtension: "json")
    }
}

/// Turns the config file into values, replacing anything unusable with the fallback and
/// saying what it replaced.
///
/// Written against `JSONSerialization` rather than `Decodable` on purpose: `Decodable` gives
/// one error and no values, and this app needs the opposite — every value it can use, plus a
/// list of what it could not. A half-broken file keeps the app running on the rest of it.
enum ThresholdConfigParser {
    /// Values to use, and what was wrong with the file.
    struct Result {
        let config: ThresholdConfig
        let problems: [String]
    }

    static func parse(_ data: Data, fallback: ThresholdConfig) -> Result {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Result(config: fallback, problems: ["the file is not a JSON object — default values are in use"])
        }
        guard let version = root["version"] as? Int else {
            return Result(config: fallback, problems: ["\"version\" is missing — default values are in use"])
        }
        // A format this release does not read falls back **without a word.** Every other problem
        // in this file belongs to somebody who is editing it right now, and silence there would
        // be the app running on numbers other than the ones they are looking at. A changed
        // schema is not that: the app installs this file itself on a first launch, so after a
        // release that moves the format every single Mac would carry the complaint — including
        // every person who has never opened the file and has no reason to care which marks
        // these are. The marks that ship are the ones almost everybody runs on anyway.
        guard version == ThresholdConfig.currentVersion else {
            return Result(config: fallback, problems: [])
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
        return Result(config: config, problems: problems)
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
