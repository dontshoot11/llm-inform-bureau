import Foundation
import SessionHealthCore

/// Reads the Codex subscription limits out of `~/.codex/sessions`.
///
/// Codex writes its rollout as it goes, and every API response appends a `token_count` event
/// carrying the current `rate_limits`. So the freshest reading is the last such event in the
/// most recently written rollout — no network call, no login, nothing to keep in sync.
///
/// Usage:
/// ```swift
/// switch CodexRolloutStore().latestLimits() {
/// case .value(let snapshot): show(snapshot)           // snapshot.observedAt is its age
/// case .noData(let why), .unavailable(let why): show(why)
/// }
/// ```
public struct CodexRolloutStore: Sendable {
    /// Where Codex keeps its rollouts, nested by date.
    public static var defaultSessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// The pool `/usage` reports. Codex meters other pools in the same field — a reserve
    /// pool, a premium one that is usually all nulls — and those are not the subscription.
    static let subscriptionLimitID = "codex"

    /// How much of the end of a rollout to read before widening the window. The first size
    /// covers a normal session's trailing traffic; the second is the concession to a session
    /// that ended with a very long tool output.
    static let tailSizes = [512 * 1024, 8 * 1024 * 1024]

    public let sessionsDirectory: URL

    /// How many of the newest rollouts to look into before giving up. The newest file
    /// normally answers on the first try; the rest cover a session that was started and
    /// abandoned before its first API response.
    public let filesToScan: Int

    public init(sessionsDirectory: URL = CodexRolloutStore.defaultSessionsDirectory, filesToScan: Int = 5) {
        self.sessionsDirectory = sessionsDirectory
        self.filesToScan = filesToScan
    }

    public func latestLimits() -> LimitsReading {
        let rollouts = newestRollouts(limit: filesToScan)
        guard !rollouts.isEmpty else {
            return .noData("No Codex sessions yet — one appears the first time Codex answers.")
        }

        for rollout in rollouts {
            if let snapshot = limits(in: rollout.url, modified: rollout.modified) {
                return .value(snapshot)
            }
        }
        // Asked only once nothing could be read at all: a broken line in a file that still
        // answered is not a broken source.
        if rollouts.contains(where: { hasUnreadableLine($0.url) }) {
            return .unavailable("Codex rollouts no longer look the way this app reads them.")
        }
        return .noData("Codex has not reported any limits yet — they arrive with its next answer.")
    }

    // MARK: One file

    /// The last usable limits reading in one rollout, read from its end.
    private func limits(in url: URL, modified: Date) -> LimitsSnapshot? {
        let size = FileTail.size(of: url)
        for (index, tail) in Self.tailSizes.enumerated() {
            // Widening past the size of the file would only re-read the same lines.
            if index > 0, size <= UInt64(Self.tailSizes[index - 1]) { break }
            guard let lines = FileTail.lines(of: url, maxBytes: tail) else { return nil }
            for line in lines.reversed() where line.contains("\"rate_limits\"") {
                if let snapshot = Self.snapshot(fromLine: line, fileModified: modified) { return snapshot }
            }
        }
        return nil
    }

    /// Whether the file ends in lines that mention limits and are not JSON at all — the shape
    /// a changed format takes on disk.
    private func hasUnreadableLine(_ url: URL) -> Bool {
        guard let lines = FileTail.lines(of: url, maxBytes: Self.tailSizes[0]) else { return false }
        return lines.contains { line in
            line.contains("\"rate_limits\"")
                && (try? JSONSerialization.jsonObject(with: Data(line.utf8))) == nil
        }
    }

    // MARK: One line

    static func snapshot(fromLine line: String, fileModified: Date) -> LimitsSnapshot? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
            let payload = root["payload"] as? [String: Any],
            let limits = payload["rate_limits"] as? [String: Any]
        else { return nil }

        // A rollout carries several limit pools; only the subscription one is what /usage shows.
        if let id = limits["limit_id"] as? String, id != subscriptionLimitID { return nil }

        let windows = [
            window(limits["primary"], kind: .short),
            window(limits["secondary"], kind: .weekly)
        ].compactMap { $0 }
        guard !windows.isEmpty else { return nil }

        let timestamp = (root["timestamp"] as? String).flatMap(Timestamps.date(fromISO8601:)) ?? fileModified
        return LimitsSnapshot(
            service: .codex,
            observedAt: timestamp,
            windows: windows,
            planType: limits["plan_type"] as? String
        )
    }

    private static func window(_ value: Any?, kind: LimitWindow.Kind) -> LimitWindow? {
        guard
            let entry = value as? [String: Any],
            let used = entry["used_percent"] as? NSNumber
        else { return nil }
        return LimitWindow(
            kind: kind,
            usedPercent: used.doubleValue,
            resetsAt: (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
            windowMinutes: (entry["window_minutes"] as? NSNumber)?.intValue
        )
    }

}

// MARK: Session context

extension CodexRolloutStore {
    /// How much of the head of a rollout to read to find its `session_meta` line. That line
    /// carries the whole system prompt, so it runs to tens of kilobytes on its own.
    static let headSize = 512 * 1024

    /// The Codex sessions being worked on right now, with their context budget.
    ///
    /// Codex is the easier half of the two: the `token_count` event carries both the tokens
    /// held and `model_context_window`, so the window fill is a fact rather than something
    /// inferred from the model name. What it does not carry is the working directory — that is
    /// in the `session_meta` line at the head of the file, which is why this reads both ends.
    ///
    /// Usage:
    /// ```swift
    /// switch CodexRolloutStore().activeSessions(activity: SessionActivity(config: config)) {
    /// case .value(let sessions): show(sessions)       // an empty list means nothing is running
    /// case .noData(let why), .unavailable(let why): show(why)
    /// }
    /// ```
    public func activeSessions(activity: SessionActivity, now: Date = Date()) -> SessionsReading {
        let rollouts = newestRollouts(limit: max(filesToScan, 20))
        guard !rollouts.isEmpty else {
            return .noData("No Codex sessions yet — one appears the first time Codex answers.")
        }

        // The activity rule is a property of the modification date, so it decides what gets
        // opened at all: a refresh costs what is running, not what the machine has stored.
        let active = rollouts.filter { activity.isActive(lastActivityAt: $0.modified, now: now) }
        guard !active.isEmpty else { return .value([]) }

        var snapshots: [SessionSnapshot] = []
        var unreadable = false
        for rollout in active {
            switch session(in: rollout, activity: activity, now: now) {
            case .value(let snapshot): snapshots.append(snapshot)
            case .noData: continue
            case .unavailable: unreadable = true
            }
        }
        if snapshots.isEmpty, unreadable {
            return .unavailable("Codex rollouts no longer look the way this app reads them.")
        }
        return .value(activity.active(snapshots, now: now))
    }

    private func session(
        in rollout: SessionFiles.Found,
        activity: SessionActivity,
        now: Date
    ) -> SourceReading<SessionSnapshot> {
        guard let lines = FileTail.lines(of: rollout.url, maxBytes: Self.tailSizes[0]) else {
            return .noData("unreadable file")
        }
        let events = lines.map { RolloutLine(raw: $0) }
        let counts = events.enumerated().filter { $0.element.isTokenCount }

        guard let last = counts.last, let held = last.element.tokensHeld else {
            let unreadable = events.contains { $0.looksLikeAnEntry && $0.json == nil }
            return unreadable ? .unavailable("unparseable lines") : .noData("nothing answered yet")
        }

        // A turn starts with `task_started`; the reading before it is where this turn began.
        let growth = counts.last { $0.offset < (events.lastIndex { $0.isTurnStart } ?? 0) }?
            .element.tokensHeld
            .map { max(0, held - $0) }

        return .value(
            SessionSnapshot(
                sessionID: meta(of: rollout.url)?.sessionID ?? rollout.url.deletingPathExtension().lastPathComponent,
                service: .codex,
                contextTokens: held,
                contextWindowTokens: last.element.contextWindow,
                turnGrowthTokens: growth,
                project: SessionFiles.projectName(fromWorkingDirectory: meta(of: rollout.url)?.workingDirectory),
                lastActivityAt: rollout.modified,
                replyWait: activity.replyWait(
                    since: Self.awaitingSince(events, writtenBy: rollout.modified),
                    now: now
                )
            )
        )
    }

    /// When the turn that still owes an answer was last written to, or `nil` when nothing is
    /// owed.
    ///
    /// Codex is the easy half of this question. A Claude transcript never says a turn is
    /// running, so the state is inferred from whose entry was last and whether it promised
    /// another; a rollout announces it. `task_started` opens a turn, `task_complete` closes
    /// it, and `turn_aborted` closes the one the person cut short — measured over 133 rollouts
    /// here, 870 turns opened, 825 completed, 39 were interrupted, and every abort carried
    /// `reason: "interrupted"`. So the wait is read rather than derived: the last boundary in
    /// the file is either an opening one or a closing one.
    ///
    /// The 6 remaining files end on an opening with nothing after it — terminals closed
    /// mid-turn, the same abandoned waits a Claude transcript leaves, and the same fuse
    /// catches them.
    ///
    /// The moment is the last line of the file rather than the opening of the turn, because
    /// Codex writes all the way through one: reasoning, tool calls, their output, a token
    /// count per response. So the silence the fuse measures is the silence since the last of
    /// those, exactly as it is for Claude — and it means the same thing at the same number.
    /// Measured over 32,804 gaps between consecutive lines inside a turn: half were under a
    /// second, 99% under 27, and 5 of them — 0.015% — ran past the ten-minute fuse.
    ///
    /// A turn whose boundary is further back than the tail this reads is not claimed as a
    /// wait. Half a megabyte of rollout is many turns' worth, and a light that blinks on a
    /// guess is worse than one that stays steady. It does happen: one rollout on this machine
    /// holds 102 lines longer than the window and one of 31.6 MB, and while a line like that
    /// is the last one written this reader has no complete line to read at all — the row goes
    /// quiet rather than wrong, which is the older behaviour of the reading and not of the
    /// wait.
    private static func awaitingSince(_ events: [RolloutLine], writtenBy modified: Date) -> Date? {
        guard let boundary = events.last(where: { $0.isTurnStart || $0.isTurnEnd }), boundary.isTurnStart
        else { return nil }
        // The last line, and the file's own date under it — never an earlier line that still
        // has a timestamp. Asking further back would answer with a moment older than the
        // silence really is and stall a session that is working; the file's date cannot,
        // because measured over every rollout here it and the last line agree to the second.
        return events.last?.writtenAt ?? modified
    }

    /// What the head of the rollout says the session is.
    private func meta(of url: URL) -> (sessionID: String?, workingDirectory: String?)? {
        guard let lines = FileTail.headLines(of: url, maxBytes: Self.headSize) else { return nil }
        for line in lines where line.contains("session_meta") {
            guard
                let root = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                let payload = root["payload"] as? [String: Any]
            else { continue }
            return (payload["session_id"] as? String, payload["cwd"] as? String)
        }
        return nil
    }

    func newestRollouts(limit: Int) -> [SessionFiles.Found] {
        SessionFiles.newest(in: sessionsDirectory, limit: limit) {
            $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl"
        }
    }
}

/// One line of a rollout, and the few questions this app asks of it.
private struct RolloutLine {
    let json: [String: Any]?
    let looksLikeAnEntry: Bool

    init(raw: String) {
        looksLikeAnEntry = raw.contains("\"token_count\"")
        json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    }

    /// When Codex wrote this line. Parsed on demand rather than for every line of the tail:
    /// only the last one of a file is ever asked.
    var writtenAt: Date? { (json?["timestamp"] as? String).flatMap(Timestamps.date(fromISO8601:)) }

    private var payload: [String: Any]? { json?["payload"] as? [String: Any] }

    var isTokenCount: Bool { payload?["type"] as? String == "token_count" }

    /// Codex starts every turn with this event, which is what makes a turn a thing this app
    /// can measure growth over.
    var isTurnStart: Bool { payload?["type"] as? String == "task_started" }

    /// And ends every turn with one of these: the answer landed, or the person cut the turn
    /// short. Either way nobody is waiting on the agent any more.
    var isTurnEnd: Bool {
        let type = payload?["type"] as? String
        return type == "task_complete" || type == "turn_aborted"
    }

    private var info: [String: Any]? { payload?["info"] as? [String: Any] }

    /// Tokens held in the context after the last request — not the session total, which the
    /// same event reports separately and which only ever grows.
    var tokensHeld: Int? {
        ((info?["last_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber)?.intValue
    }

    var contextWindow: Int? { (info?["model_context_window"] as? NSNumber)?.intValue }
}
