import Foundation
import SessionHealthCore

/// One statusLine payload, as the wrapper last saw it for a session.
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

    /// When the wrapper last ran for this session, which is the age of everything above.
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
/// switch store.latestLimits() {
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

    public init(directory: URL = ClaudeStatusStore.defaultDirectory, filesToScan: Int = 20) {
        self.directory = directory
        self.filesToScan = filesToScan
    }

    /// The freshest limits any session has reported.
    ///
    /// Age matters more than which session: every session of the same account reports the same
    /// subscription windows, so the most recently written payload is simply the most current.
    public func latestLimits() -> LimitsReading {
        let files = newestFiles()
        guard !files.isEmpty else { return .noData(Self.nothingReported) }

        var unreadable = false
        for file in files {
            guard let payload = payload(at: file) else {
                unreadable = true
                continue
            }
            if let limits = payload.limits { return .value(limits) }
        }
        if unreadable {
            return .unavailable(Self.unreadablePayload)
        }
        return .noData("""
            Claude reported no limits: the rate_limits field is for Pro and Max subscriptions \
            and arrives with the first answer of a session.
            """)
    }

    /// The sessions the wrapper has seen that are still being worked on.
    ///
    /// Only sessions whose context the payload actually carried: a payload written before the
    /// first answer has no numbers in it, and a session with no numbers is nothing to show.
    public func sessions(activity: SessionActivity, now: Date = Date()) -> SessionsReading {
        let files = newestFiles()
        guard !files.isEmpty else { return .noData(Self.nothingReported) }

        var snapshots: [SessionSnapshot] = []
        var unreadable = false
        for file in files {
            guard let payload = payload(at: file) else {
                unreadable = true
                continue
            }
            guard let tokens = payload.contextTokens else { continue }
            snapshots.append(
                SessionSnapshot(
                    sessionID: payload.sessionID,
                    service: .claude,
                    contextTokens: tokens,
                    contextWindowTokens: payload.contextWindowTokens,
                    project: payload.project,
                    lastActivityAt: payload.writtenAt
                )
            )
        }
        if snapshots.isEmpty, unreadable {
            return .unavailable(Self.unreadablePayload)
        }
        return .value(activity.active(snapshots, now: now))
    }

    /// Every payload on disk, newest first — how a transcript session learns the size of its
    /// context window, which the transcript itself never says.
    public func payloads() -> [ClaudeStatusPayload] {
        newestFiles().compactMap { payload(at: $0) }
    }

    // MARK: Files

    private func newestFiles() -> [SessionFiles.Found] {
        SessionFiles.newest(in: directory, limit: filesToScan) { $0.pathExtension == "json" }
    }

    private func payload(at file: SessionFiles.Found) -> ClaudeStatusPayload? {
        guard
            let data = try? Data(contentsOf: file.url),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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
