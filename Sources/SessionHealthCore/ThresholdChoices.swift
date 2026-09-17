import Foundation

/// One mark of the config, named so a choice can be about it.
///
/// The six things the app compares its readings to. The raw value is the path of that entry in
/// `thresholds.json` — the same path the loader names when it reports a problem with the file,
/// and the key a choice is stored under, so a file written by this app can be read beside the
/// one it ships without a translation table.
public enum ThresholdMark: String, CaseIterable, Sendable {
    case windowFill = "context.window_fill_percent"
    case limitUsage = "limits.percent"
    case limitWindowNearlyReset = "limits.quiet_when_window_remaining_percent"
    case sessionActivity = "sessions.active_within_minutes"
    case abandonedWait = "sessions.abandoned_wait_after_minutes"
    case attentionNotice = "sessions.attention_notice_after_minutes"

    /// The marks that are a scale of three rather than one number.
    public static let scales: [ThresholdMark] = [.windowFill, .limitUsage]
}

/// The marks a person moved themselves, and what they become when the app's own marks are read.
///
/// What is kept is the choice and nothing else: which mark was moved and where to. Not a copy
/// of the config with one number changed — the config ships inside the app and changes from
/// release to release, so a copy would quietly turn every later improvement into the version
/// this person happened to edit once, and a change of format would throw their choice away
/// along with it. A choice against a named mark survives both: the new file arrives, and the
/// one mark they moved is still theirs.
///
/// A moved mark loses the rationale that shipped with it. That rationale describes a number
/// somebody placed against something; this is a different number, and repeating the sentence
/// under it would be the app inventing a justification for a mark nobody measured — the one
/// thing `AGENTS.md` asks these numbers never to do. `isChosen` is what the window says
/// instead.
public struct ThresholdChoices: Equatable, Sendable {
    /// The scales that were moved, by the mark they belong to.
    public var scales: [ThresholdMark: MarkScale]

    public init(scales: [ThresholdMark: MarkScale] = [:]) {
        self.scales = scales
    }

    /// `true` when nothing has been chosen — the ordinary state, and the one the app ships in.
    public var isEmpty: Bool { scales.isEmpty }

    public func scale(of mark: ThresholdMark) -> MarkScale? { scales[mark] }

    /// These choices with one more made.
    public func choosing(_ mark: ThresholdMark, _ scale: MarkScale) -> ThresholdChoices {
        var chosen = self
        chosen.scales[mark] = scale
        return chosen
    }

    /// These choices with one taken back — the mark goes back to whatever the app ships.
    public func forgetting(_ mark: ThresholdMark) -> ThresholdChoices {
        var chosen = self
        chosen.scales[mark] = nil
        return chosen
    }

    /// The config as it stands after the choices: every mark the app ships with, except the
    /// ones somebody moved.
    public func applied(to config: ThresholdConfig) -> ThresholdConfig {
        ThresholdConfig(
            version: config.version,
            windowFill: Self.marks(config.windowFill, chosen: scales[.windowFill]),
            limitUsage: Self.marks(config.limitUsage, chosen: scales[.limitUsage]),
            limitWindowNearlyReset: config.limitWindowNearlyReset,
            sessionActivity: config.sessionActivity,
            abandonedWait: config.abandonedWait,
            attentionNotice: config.attentionNotice
        )
    }

    private static func marks(_ shipped: PercentMarks, chosen: MarkScale?) -> PercentMarks {
        guard let chosen else { return shipped }
        return PercentMarks(
            notice: chosen.notice,
            elevated: chosen.elevated,
            high: chosen.high,
            rationale: chosenRationale,
            provenance: nil,
            isChosen: true
        )
    }

    /// Stands where the shipped rationale stood, and says the same kind of thing it does: where
    /// this number came from. It came from the person reading it.
    public static let chosenRationale = """
        Moved in this app's own settings. The rationale that shipped with this mark was \
        written about a different number and is not repeated here.
        """
}

/// Where the choices are kept, and how they survive an update of the app.
///
/// A file in the app's own directory, beside the note that the first run has been explained —
/// the same decision as everything else this app remembers: one file, in a place a person can
/// look at and delete, rather than a preference nobody can find. It is in Application Support
/// rather than inside the app, which is what makes a choice outlive the copy of the app that
/// was dragged over the old one.
///
/// Nothing here throws. A file that cannot be read means nothing was chosen, and the app runs
/// on the marks it ships with — the same fallback as everywhere else in this module, and the
/// right one: a person whose choice was lost gets the app's own numbers back, not a widget
/// that refuses to start.
public enum ThresholdChoicesStore {
    /// Version of *this* file's format, not the config's. The two move independently: the
    /// config file's shape is the app's business, and a choice names one mark and one value.
    public static let currentVersion = 1

    public static let fileName = "chosen-thresholds.json"

    public static func url(in directory: URL = SupportDirectory.url()) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// What was chosen, or nothing at all: no file, a broken one, a format this release does
    /// not read, or a scale that is not a scale. Every one of those ends the same way, because
    /// there is nothing a person could do about any of them that they would not rather do by
    /// moving the mark again.
    public static func read(at url: URL = url()) -> ThresholdChoices {
        guard
            let data = try? Data(contentsOf: url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            root["version"] as? Int == currentVersion
        else { return ThresholdChoices() }

        let stored = root["scales"] as? [String: Any] ?? [:]
        var scales: [ThresholdMark: MarkScale] = [:]
        for mark in ThresholdMark.scales {
            guard
                let entry = stored[mark.rawValue] as? [String: Any],
                let notice = (entry["notice"] as? NSNumber)?.doubleValue,
                let elevated = (entry["elevated"] as? NSNumber)?.doubleValue,
                let high = (entry["high"] as? NSNumber)?.doubleValue,
                // The rule the config file is held to, held here too: a record out of order is
                // not applied backwards, it gives way to the marks the app ships with.
                let scale = MarkScale(notice: notice, elevated: elevated, high: high)
            else { continue }
            scales[mark] = scale
        }
        return ThresholdChoices(scales: scales)
    }

    /// Writes the choices, or removes the file when there are none left — so "put it back the
    /// way it was" leaves nothing behind to be read by a later release.
    ///
    /// `false` when the write failed, which costs the person the choice they just made and
    /// nothing else; the app goes on running on the marks it had.
    @discardableResult
    public static func write(_ choices: ThresholdChoices, to url: URL = url()) -> Bool {
        guard !choices.isEmpty else {
            if !FileManager.default.fileExists(atPath: url.path) { return true }
            return (try? FileManager.default.removeItem(at: url)) != nil
        }

        var scales: [String: Any] = [:]
        for (mark, scale) in choices.scales {
            scales[mark.rawValue] = ["notice": scale.notice, "elevated": scale.elevated, "high": scale.high]
        }
        let root: [String: Any] = ["version": currentVersion, "scales": scales]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
        else { return false }

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
