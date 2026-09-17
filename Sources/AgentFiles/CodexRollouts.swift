import Foundation
import SessionHealthCore

/// Everything one walk of the rollout tree has to say.
///
/// Both questions the app asks of Codex — the subscription limits and the sessions being
/// worked on — are answered by the same files, and used to be asked one after the other: two
/// walks of the tree per pass, and the newest rollout read twice.
public struct CodexRolloutReading: Sendable {
    public let limits: LimitsReading
    public let sessions: SessionsReading
}

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

    /// What the end of each rollout last said about the limits — see `FileMemory` for what a
    /// hit is allowed to mean and what bounds the memory. A rollout is appended to all through
    /// a turn, so between turns this is the same half-megabyte tail scanned for the same
    /// answer.
    private let limitsReadings = FileMemory<LimitsInFile>()

    /// What the end of each rollout last said about its session.
    private let sessionReadings = FileMemory<SourceReading<Reading>>()

    /// What the head of each rollout says the session is, remembered by file identity alone:
    /// `session_meta` is the first line written and appending cannot move it. Worth its own
    /// memory because that line carries the whole system prompt — half a megabyte read and
    /// parsed, on every pass, for an answer that never changes.
    private let metas = FileMemory<RolloutMeta>()

    /// Kept for the life of the app rather than made per pass: what the memories above are
    /// worth depends on outliving a pass. `sessionsDirectory` is the tests' way in, and the
    /// measuring rig's.
    public init(sessionsDirectory: URL = CodexRolloutStore.defaultSessionsDirectory, filesToScan: Int = 5) {
        self.sessionsDirectory = sessionsDirectory
        self.filesToScan = filesToScan
    }

    /// One walk of the tree, and everything that walk can answer.
    ///
    /// The walk is the sessions half's: it wants every rollout that might still be running,
    /// where the limits half only needs the newest few, and the newest few are the beginning of
    /// the same list.
    public func read(activity: SessionActivity, now: Date = Date()) -> CodexRolloutReading {
        let rollouts = newestRollouts(limit: rolloutsToWalk)
        return CodexRolloutReading(
            limits: limits(in: Array(rollouts.prefix(filesToScan))),
            sessions: sessions(in: rollouts, activity: activity, now: now)
        )
    }

    public func latestLimits() -> LimitsReading {
        limits(in: newestRollouts(limit: filesToScan))
    }

    /// How many rollouts one walk looks at.
    private var rolloutsToWalk: Int { max(filesToScan, 20) }

    // MARK: The limits, across the newest files

    private func limits(in rollouts: [SessionFiles.Found]) -> LimitsReading {
        // Every exit from here ends this half of a pass, and the end of a pass is what bounds
        // the memory: whatever was not asked about is not in the walk any more.
        defer { limitsReadings.forgetUnasked() }

        guard !rollouts.isEmpty else {
            return .noData("No Codex sessions yet — one appears the first time Codex answers.")
        }

        // A file is only reached once the ones newer than it had nothing to say, which is why
        // the unreadable ones are counted as they are passed rather than looked for afterwards.
        var sawUnreadableLine = false
        for rollout in rollouts {
            let reading = limits(of: rollout)
            if let snapshot = reading.snapshot { return .value(snapshot) }
            sawUnreadableLine = sawUnreadableLine || reading.sawUnreadableLine
        }
        // Asked only once nothing could be read at all: a broken line in a file that still
        // answered is not a broken source.
        if sawUnreadableLine {
            return .unavailable("Codex rollouts no longer look the way this app reads them.")
        }
        return .noData("Codex has not reported any limits yet — they arrive with its next answer.")
    }

    // MARK: One file

    /// What one rollout says about the limits.
    fileprivate struct LimitsInFile: Equatable, Sendable {
        /// The last usable limits reading in the file, or `nil` when it carries none.
        let snapshot: LimitsSnapshot?

        /// Whether a line claiming to carry limits is not JSON at all — the shape a changed
        /// format takes on disk. A line that parses and describes another limit pool is not
        /// that, which is why the two are told apart here.
        let sawUnreadableLine: Bool
    }

    private func limits(of rollout: SessionFiles.Found) -> LimitsInFile {
        if let remembered = limitsReadings.value(of: rollout.url, unchangedSince: rollout.stamp) {
            return remembered
        }
        // A file that would not open said nothing about the limits, and nothing is not an
        // answer to keep — see `FileMemory`, "What it never remembers".
        guard let reading = parseLimits(rollout) else {
            return LimitsInFile(snapshot: nil, sawUnreadableLine: false)
        }
        limitsReadings.remember(reading, of: rollout.url, as: rollout.stamp)
        return reading
    }

    /// The last usable limits reading in one rollout, read from its end. `nil` when the file
    /// would not open at all, which is not something the file said.
    private func parseLimits(_ rollout: SessionFiles.Found) -> LimitsInFile? {
        var sawUnreadableLine = false
        var opened = false
        for (index, tail) in Self.tailSizes.enumerated() {
            // Widening past the size of the file would only re-read the same lines.
            if index > 0, rollout.stamp.size <= Self.tailSizes[index - 1] { break }
            guard let lines = FileTail.lines(of: rollout.url, maxBytes: tail) else { break }
            opened = true
            for line in lines.reversed() where line.contains("\"rate_limits\"") {
                if let snapshot = Self.snapshot(fromLine: line, fileModified: rollout.modified) {
                    return LimitsInFile(snapshot: snapshot, sawUnreadableLine: sawUnreadableLine)
                }
                if index == 0, (try? JSONSerialization.jsonObject(with: Data(line.utf8))) == nil {
                    sawUnreadableLine = true
                }
            }
        }
        guard opened else { return nil }
        return LimitsInFile(snapshot: nil, sawUnreadableLine: sawUnreadableLine)
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

    /// What one rollout said about its session, before it is anybody's snapshot.
    ///
    /// Nothing in here is measured against a clock: how long a session has been waiting moves
    /// while the file stands still, so what is remembered is what the file said — a moment —
    /// and the rule is applied to it afresh on every pass.
    fileprivate struct Reading: Equatable, Sendable {
        let contextTokens: Int
        let contextWindowTokens: Int?
        let turnGrowthTokens: Int?
        /// The model the last turn opened on.
        let model: String?
        /// When the turn that still owes an answer was last written to, or `nil` when nothing
        /// is owed.
        let awaitingSince: Date?
    }

    /// What the head of a rollout says the session is.
    fileprivate struct RolloutMeta: Equatable, Sendable {
        let sessionID: String?
        let workingDirectory: String?
    }

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
        sessions(in: newestRollouts(limit: rolloutsToWalk), activity: activity, now: now)
    }

    private func sessions(
        in rollouts: [SessionFiles.Found],
        activity: SessionActivity,
        now: Date
    ) -> SessionsReading {
        // Every exit from here ends this half of a pass; see `limits(in:)` for what that does.
        defer {
            sessionReadings.forgetUnasked()
            metas.forgetUnasked()
        }

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
            switch read(rollout) {
            case .value(let reading):
                snapshots.append(snapshot(of: rollout, reading: reading, activity: activity, now: now))
            case .noData: continue
            case .unavailable: unreadable = true
            }
        }
        if snapshots.isEmpty, unreadable {
            return .unavailable("Codex rollouts no longer look the way this app reads them.")
        }
        return .value(activity.active(snapshots, now: now))
    }

    /// What the panel shows for one rollout: what the file said, told what time it is.
    private func snapshot(
        of rollout: SessionFiles.Found,
        reading: Reading,
        activity: SessionActivity,
        now: Date
    ) -> SessionSnapshot {
        let meta = meta(of: rollout)
        return SessionSnapshot(
            sessionID: meta?.sessionID ?? rollout.url.deletingPathExtension().lastPathComponent,
            service: .codex,
            contextTokens: reading.contextTokens,
            contextWindowTokens: reading.contextWindowTokens,
            turnGrowthTokens: reading.turnGrowthTokens,
            model: reading.model,
            project: SessionFiles.projectName(fromWorkingDirectory: meta?.workingDirectory),
            lastActivityAt: rollout.modified,
            replyWait: activity.replyWait(since: reading.awaitingSince, now: now)
        )
    }

    private func read(_ rollout: SessionFiles.Found) -> SourceReading<Reading> {
        if let remembered = sessionReadings.value(of: rollout.url, unchangedSince: rollout.stamp) {
            return remembered
        }
        // A file that would not open said nothing, and nothing is not an answer to keep — see
        // `FileMemory`, "What it never remembers".
        guard let reading = parse(rollout) else { return .noData("could not be opened just now") }
        sessionReadings.remember(reading, of: rollout.url, as: rollout.stamp)
        return reading
    }

    /// What the file itself says, with nothing remembered. `nil` when the file would not open
    /// at all, which is not something the file said.
    private func parse(_ rollout: SessionFiles.Found) -> SourceReading<Reading>? {
        guard let lines = FileTail.lines(of: rollout.url, maxBytes: Self.tailSizes[0]) else {
            return nil
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
            Reading(
                contextTokens: held,
                contextWindowTokens: last.element.contextWindow,
                turnGrowthTokens: growth,
                // The last turn's, not the session's: Codex lets the model be changed mid
                // session, and every turn says which one it opened on.
                model: events.last { $0.isTurnContext }?.model,
                awaitingSince: Self.awaitingSince(events, writtenBy: rollout.modified)
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
    ///
    /// **Only the agent is ever waited on here.** Claude has a third answer — the person is
    /// the one being waited on, and the bar draws it as a pause sign — and Codex has no way to
    /// give it: nothing it writes down says a request is standing open. Measured on Codex
    /// 0.154.0 with a live approval prompt held open (see the task's research.md): while the
    /// person is being asked, the app-server tells its client over the socket
    /// (`waitingOnApproval`) and the rollout says nothing — its last lines are the tool call
    /// and a token count, which is exactly what an allowed command that is still running
    /// writes. No line marks the moment of an answer, there is no per-process record beside
    /// the rollout as there is for Claude, and the state databases hold an inventory rather
    /// than a live status. The tool call does carry the model's own
    /// `sandbox_permissions: "require_escalated"`, and reading that as a request was turned
    /// down twice over: it cannot be told from a command the person already allowed, and where
    /// the reviewer is `auto_review` no person is asked at all. So a Codex session that is
    /// standing on a request blinks, like every other turn in flight.
    private static func awaitingSince(_ events: [RolloutLine], writtenBy modified: Date) -> Date? {
        guard let boundary = events.last(where: { $0.isTurnStart || $0.isTurnEnd }), boundary.isTurnStart
        else { return nil }
        // The last line, and the file's own date under it — never an earlier line that still
        // has a timestamp. Asking further back would answer with a moment older than the
        // silence really is and stall a session that is working; the file's date cannot,
        // because measured over every rollout here it and the last line agree to the second.
        return events.last?.writtenAt ?? modified
    }

    /// What the head of the rollout says the session is, read once per file rather than once
    /// per pass — see `metas`.
    private func meta(of rollout: SessionFiles.Found) -> RolloutMeta? {
        if let remembered = metas.value(of: rollout.url, stillTheSameFileAs: rollout.stamp) {
            return remembered
        }
        guard let meta = Self.sessionMeta(in: rollout.url) else { return nil }
        // Only an answer is remembered. A rollout whose head has no `session_meta` in it yet
        // would otherwise be remembered as having none for as long as it lives.
        metas.remember(meta, of: rollout.url, as: rollout.stamp)
        return meta
    }

    private static func sessionMeta(in url: URL) -> RolloutMeta? {
        guard let lines = FileTail.headLines(of: url, maxBytes: Self.headSize) else { return nil }
        for line in lines where line.contains("session_meta") {
            guard
                let root = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                let payload = root["payload"] as? [String: Any]
            else { continue }
            return RolloutMeta(
                sessionID: payload["session_id"] as? String,
                workingDirectory: payload["cwd"] as? String
            )
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

    /// The line that opens a turn with the settings it runs on. It is a line of its own rather
    /// than an `event_msg`, so it has no `type` inside the payload — the one on the envelope is
    /// what names it.
    var isTurnContext: Bool { json?["type"] as? String == "turn_context" }

    /// The model this turn opened on. Read from `turn_context` alone: the same name appears in
    /// a `world_state` line and three times inside the session's own metadata, and one place to
    /// read it from is what keeps this reader from disagreeing with itself.
    var model: String? { isTurnContext ? payload?["model"] as? String : nil }

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
