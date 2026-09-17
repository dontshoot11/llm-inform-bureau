import Foundation
import SessionHealthCore

/// Everything the widget shows, read once.
///
/// Each half is its own reading, so one source going quiet says so in its own words instead of
/// blanking the other: a machine with no Codex still shows Claude, and a Claude whose status
/// line slot is not connected still shows its sessions from the transcripts.
public struct UsageReading: Equatable, Sendable {
    public let claudeLimits: LimitsReading
    public let codexLimits: LimitsReading
    public let claudeSessions: SessionsReading
    public let codexSessions: SessionsReading

    /// The services whose CLI has left a directory on this machine.
    ///
    /// Not everyone runs both, and "this agent is not here" is a different fact from "this
    /// agent has nothing to report yet": one is answered by installing nothing, the other by
    /// waiting for the next answer. They looked identical while both were only an absence of
    /// files, which made an agent somebody does not use look like a fault.
    public let installed: Set<AgentService>

    public func isInstalled(_ service: AgentService) -> Bool { installed.contains(service) }

    public func limits(of service: AgentService) -> LimitsReading {
        switch service {
        case .claude: claudeLimits
        case .codex: codexLimits
        }
    }

    public func sessions(of service: AgentService) -> SessionsReading {
        switch service {
        case .claude: claudeSessions
        case .codex: codexSessions
        }
    }
}

/// Reads both services and hands back one picture of them.
///
/// The one thing that happens here and nowhere else is the join between the two Claude
/// sources. A transcript is always there and knows the tokens held; the status line is there
/// only once the slot is connected and knows the size of the window. Neither is complete, so a
/// Claude session is read from the transcript and then told how big its window is, when
/// something knows.
///
/// Usage:
/// ```swift
/// let reading = UsageReader().read(config: load.config)
/// ```
public struct UsageReader: Sendable {
    public let claudeTranscripts: ClaudeTranscriptStore
    public let claudeStatus: ClaudeStatusStore
    public let codexRollouts: CodexRolloutStore

    public init(
        claudeTranscripts: ClaudeTranscriptStore = ClaudeTranscriptStore(),
        claudeStatus: ClaudeStatusStore = ClaudeStatusStore(),
        codexRollouts: CodexRolloutStore = CodexRolloutStore()
    ) {
        self.claudeTranscripts = claudeTranscripts
        self.claudeStatus = claudeStatus
        self.codexRollouts = codexRollouts
    }

    /// One pass: one walk of each of the three trees, and nothing opened that has not changed.
    ///
    /// Each source answers everything it is asked in a single call, because each of them is
    /// asked about twice — Claude for its limits and its window sizes, Codex for its limits and
    /// its sessions — and asking separately meant walking the same tree twice and parsing the
    /// same files twice, on every one of the dozens of events a single turn produces.
    public func read(config: ThresholdConfig, now: Date = Date()) -> UsageReading {
        let activity = SessionActivity(config: config)
        let transcripts = claudeTranscripts.activeSessions(activity: activity, now: now)
        let status = claudeStatus.read()
        let codex = codexRollouts.read(activity: activity, now: now)

        var installed: Set<AgentService> = []
        if exists(claudeTranscripts.projectsDirectory) { installed.insert(.claude) }
        if exists(codexRollouts.sessionsDirectory) { installed.insert(.codex) }

        return UsageReading(
            claudeLimits: status.limits,
            codexLimits: codex.limits,
            claudeSessions: Self.withWindowSizes(transcripts, from: status.payloads),
            codexSessions: codex.sessions,
            installed: installed
        )
    }

    /// The directory a CLI makes for itself the first time it runs. Its absence is the one
    /// reliable sign the agent is not on this machine — an empty one means it is, and has been
    /// tidied or has simply not been used.
    private func exists(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.path)
    }

    /// Fills in what a transcript cannot say.
    ///
    /// Only the window size is taken from the status line. The tokens held come from the
    /// transcript either way, so a session whose payload is a few seconds behind still
    /// reads correctly — and a session with no payload at all loses nothing but the percentage.
    ///
    /// A subagent has no payload of its own and never will: nothing it writes names the size
    /// of its window. It takes the number from the session that started it, which is where it
    /// is running unless it was given a model of its own — `SubagentOrigin` is where that is
    /// decided, and this only carries the number across.
    public static func withWindowSizes(
        _ sessions: SessionsReading,
        from payloads: [ClaudeStatusPayload]
    ) -> SessionsReading {
        guard case .value(let snapshots) = sessions else { return sessions }
        let windows = Dictionary(
            payloads.compactMap { payload in payload.contextWindowTokens.map { (payload.sessionID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let told = snapshots.map { snapshot in
            guard snapshot.contextWindowTokens == nil, let window = windows[snapshot.sessionID] else {
                return snapshot
            }
            return snapshot.withWindow(window)
        }

        let sessionWindows = Dictionary(
            told.compactMap { snapshot in
                snapshot.isSubagent ? nil : snapshot.contextWindowTokens.map { (snapshot.sessionID, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return .value(
            told.map { snapshot in
                guard let origin = snapshot.subagent,
                      origin.inheritsParentWindow,
                      snapshot.contextWindowTokens == nil,
                      let window = sessionWindows[origin.parentSessionID]
                else { return snapshot }
                return snapshot.withWindow(window)
            }
        )
    }
}
