import Foundation
import SessionHealthCore

/// One statusLine payload, as the status line last saw it for a session.
///
/// The statusLine contract is the only local source of Claude's subscription limits, and the
/// only one that knows the size of the context window — a transcript carries neither.
public struct ClaudeStatusPayload: Equatable, Sendable {
    public let sessionID: String
    public let project: String?

    /// Tokens held in the context window, or `nil` before the first answer of a session.
    public let contextTokens: Int?

    /// Size of the context window, or `nil` when the payload did not carry it.
    public let contextWindowTokens: Int?

    /// The subscription limits, or `nil`: the field is Pro and Max only, and arrives with the
    /// first answer of a session.
    public let limits: LimitsSnapshot?

    /// When the status line last ran for this session, which is the age of everything above.
    public let writtenAt: Date

    public init(
        sessionID: String,
        project: String?,
        contextTokens: Int?,
        contextWindowTokens: Int?,
        limits: LimitsSnapshot?,
        writtenAt: Date
    ) {
        self.sessionID = sessionID
        self.project = project
        self.contextTokens = contextTokens
        self.contextWindowTokens = contextWindowTokens
        self.limits = limits
        self.writtenAt = writtenAt
    }
}

/// Everything one walk of the payload directory has to say.
///
/// The app asks the status line two questions — what the subscription limits are, and how big
/// each session's context window is — and they are answered by the same files. They used to be
/// asked one after the other, which meant walking the directory twice and parsing every payload
/// in it twice on every pass. One walk answers both.
public struct ClaudeStatusReading: Sendable {
    /// The payloads that could be read, newest first.
    public let payloads: [ClaudeStatusPayload]

    /// Whether the walk found a file at all. What separates a status line that has not
    /// reported yet from one whose report this app cannot read.
    let foundFiles: Bool

    /// Whether a file the walk did find would not parse. A file that could not be opened at
    /// all is not that: one is a verdict on the format, the other is a moment.
    let sawUnreadableFile: Bool

    /// The freshest limits any session has reported.
    ///
    /// Age matters more than which session: every session of the same account reports the same
    /// subscription windows, so the most recently written payload is simply the most current.
    public var limits: LimitsReading {
        guard foundFiles else { return .noData(ClaudeStatusStore.nothingReported) }
        for payload in payloads {
            if let limits = payload.limits { return .value(limits) }
        }
        if sawUnreadableFile { return .unavailable(ClaudeStatusStore.unreadablePayload) }
        return .noData("""
            Claude reported no limits: the rate_limits field is for Pro and Max subscriptions \
            and arrives with the first answer of a session.
            """)
    }

    /// The sessions the status line has seen that are still being worked on.
    ///
    /// Only sessions whose context the payload actually carried: a payload written before the
    /// first answer has no numbers in it, and a session with no numbers is nothing to show.
    public func sessions(activity: SessionActivity, now: Date = Date()) -> SessionsReading {
        guard foundFiles else { return .noData(ClaudeStatusStore.nothingReported) }

        let snapshots = payloads.compactMap { payload -> SessionSnapshot? in
            guard let tokens = payload.contextTokens else { return nil }
            return SessionSnapshot(
                sessionID: payload.sessionID,
                service: .claude,
                contextTokens: tokens,
                contextWindowTokens: payload.contextWindowTokens,
                project: payload.project,
                lastActivityAt: payload.writtenAt
            )
        }
        if snapshots.isEmpty, sawUnreadableFile {
            return .unavailable(ClaudeStatusStore.unreadablePayload)
        }
        return .value(activity.active(snapshots, now: now))
    }
}

/// Reads what the status line command leaves on disk.
///
/// Claude Code runs a status line command on every new assistant message and hands it a JSON
/// payload carrying `rate_limits` and `context_window`. There is no file in `~/.claude` with
/// the same numbers, so this is the only way to have them locally — and the reason the app
/// takes that slot at all. `StatusLineSlot` is what takes it, by the button in the panel and
/// with whatever command was there kept underneath.
///
/// Usage:
/// ```swift
/// let store = ClaudeStatusStore()
/// switch store.read().limits {
/// case .value(let snapshot): show(snapshot)
/// case .noData(let why), .unavailable(let why): show(why)
/// }
/// ```
public struct ClaudeStatusStore: Sendable {
    /// Where the status line command writes. Inside this app's own Application Support
    /// directory: the payloads are this app's, and `~/.claude` holds nothing of ours but the
    /// one line in `settings.json` that points at the command.
    public static var defaultDirectory: URL {
        SupportDirectory.url().appendingPathComponent("claude-status", isDirectory: true)
    }

    /// Said when nothing has been reported yet.
    ///
    /// It no longer names a fix, because there may not be one to name: whether the slot is
    /// connected at all is `StatusLineSlot`'s answer and the panel's to act on — it puts a
    /// button here instead of this sentence. What is left for this to say is the other case,
    /// where the slot is the app's and the reporting has simply not started.
    static let nothingReported = """
        No Claude data yet — its limits and the size of its context window come from its \
        status line, which reports with the first answer of a session. The limits themselves \
        are Pro and Max only.
        """

    /// The status line is this app itself, so an unreadable payload is this app failing to read
    /// back what it wrote — the shape Claude Code puts on stdin is the part that can change.
    static let unreadablePayload = """
        The status line wrote something this app cannot read — the payload format may have \
        changed.
        """

    public let directory: URL

    /// How many session payloads to read. More than a person has sessions open at once.
    public let filesToScan: Int

    /// What each payload said last time it was read. The status line rewrites a session's
    /// payload on every answer, so between answers every pass used to parse the same JSON
    /// again — see `FileMemory` for what a hit is allowed to mean and what bounds the memory.
    ///
    /// A file that would not parse is remembered as such. Otherwise the one payload this app
    /// cannot read would be the one file it opens on every pass, for the same disappointment.
    private let readings = FileMemory<ClaudeStatusPayload?>()

    /// Kept for the life of the app rather than made per pass: what the memory above is worth
    /// depends on outliving a pass. `directory` is the tests' way in, and the measuring rig's.
    public init(directory: URL = ClaudeStatusStore.defaultDirectory, filesToScan: Int = 20) {
        self.directory = directory
        self.filesToScan = filesToScan
    }

    /// One walk of the directory, and everything that walk can answer.
    public func read() -> ClaudeStatusReading {
        // The end of a pass is what bounds the memory: whatever was not asked about is not in
        // the walk any more.
        defer { readings.forgetUnasked() }

        let files = newestFiles()
        let reads = files.map { read($0) }
        return ClaudeStatusReading(
            payloads: reads.compactMap { $0.payload },
            foundFiles: !files.isEmpty,
            sawUnreadableFile: reads.contains { $0.wouldNotParse }
        )
    }

    /// The freshest limits any session has reported.
    public func latestLimits() -> LimitsReading { read().limits }

    /// The sessions the status line has seen that are still being worked on.
    public func sessions(activity: SessionActivity, now: Date = Date()) -> SessionsReading {
        read().sessions(activity: activity, now: now)
    }

    /// Every payload on disk, newest first — how a transcript session learns the size of its
    /// context window, which the transcript itself never says.
    public func payloads() -> [ClaudeStatusPayload] { read().payloads }

    // MARK: Files

    private func newestFiles() -> [SessionFiles.Found] {
        SessionFiles.newest(in: directory, limit: filesToScan) { $0.pathExtension == "json" }
    }

    /// How one payload file turned out. Three outcomes rather than two: a file this app cannot
    /// make sense of is the status line writing something new, and worth saying out loud; a
    /// file that would not open is neither that nor anything to remember.
    private enum PayloadRead {
        case parsed(ClaudeStatusPayload)
        case wouldNotParse
        case wouldNotOpen

        var payload: ClaudeStatusPayload? {
            if case .parsed(let payload) = self { payload } else { nil }
        }

        var wouldNotParse: Bool {
            if case .wouldNotParse = self { true } else { false }
        }
    }

    private func read(_ file: SessionFiles.Found) -> PayloadRead {
        if let remembered = readings.value(of: file.url, unchangedSince: file.stamp) {
            return remembered.map { .parsed($0) } ?? .wouldNotParse
        }
        // A file that would not open said nothing, and nothing is not an answer to keep — see
        // `FileMemory`, "What it never remembers". A file that opened and made no sense is a
        // different matter, and that one is remembered on purpose.
        guard let data = try? Data(contentsOf: file.url) else { return .wouldNotOpen }
        let payload = parse(file, from: data)
        readings.remember(payload, of: file.url, as: file.stamp)
        return payload.map { .parsed($0) } ?? .wouldNotParse
    }

    /// What the bytes of the file say, with nothing remembered.
    private func parse(_ file: SessionFiles.Found, from data: Data) -> ClaudeStatusPayload? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        // The file is named after the session, so a payload whose own field went missing is
        // still attributable.
        let sessionID = (root["session_id"] as? String) ?? file.url.deletingPathExtension().lastPathComponent
        let context = root["context_window"] as? [String: Any]
        let workspace = root["workspace"] as? [String: Any]
        let workingDirectory = (workspace?["project_dir"] as? String) ?? (root["cwd"] as? String)

        return ClaudeStatusPayload(
            sessionID: sessionID,
            project: SessionFiles.projectName(fromWorkingDirectory: workingDirectory),
            contextTokens: (context?["total_input_tokens"] as? NSNumber)?.intValue,
            contextWindowTokens: (context?["context_window_size"] as? NSNumber)?.intValue,
            limits: Self.limits(root["rate_limits"], observedAt: file.modified),
            writtenAt: file.modified
        )
    }

    // MARK: The limits inside one payload

    /// Claude names its two windows where Codex numbers them; both mean the same thing, and
    /// `LimitWindow.Kind` is where the two vocabularies meet.
    static func limits(_ value: Any?, observedAt: Date) -> LimitsSnapshot? {
        guard let entry = value as? [String: Any] else { return nil }
        let windows = [
            window(entry["five_hour"], kind: .short),
            window(entry["seven_day"], kind: .weekly)
        ].compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        return LimitsSnapshot(service: .claude, observedAt: observedAt, windows: windows)
    }

    private static func window(_ value: Any?, kind: LimitWindow.Kind) -> LimitWindow? {
        guard
            let entry = value as? [String: Any],
            let used = entry["used_percentage"] as? NSNumber
        else { return nil }
        return LimitWindow(
            kind: kind,
            usedPercent: used.doubleValue,
            resetsAt: (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        )
    }
}
