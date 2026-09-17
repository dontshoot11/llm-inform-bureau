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
/// The one thing that happens here and nowhere else is the join between the three Claude
/// sources, none of which is complete on its own. The transcript is always there and knows the
/// tokens held; the status line is there once the slot is connected and knows the size of the
/// window; the session record is there while an interactive process is running and is the only
/// one that knows the agent has stopped and is waiting on the person. So a Claude session is
/// read from its transcript and then told what the other two know about it, when they know it.
///
/// Usage:
/// ```swift
/// let reading = UsageReader().read(config: load.config)
/// ```
public struct UsageReader: Sendable {
    public let claudeTranscripts: ClaudeTranscriptStore
    public let claudeStatus: ClaudeStatusStore
    public let claudeSessionRecords: ClaudeSessionRecordStore
    public let codexRollouts: CodexRolloutStore

    public init(
        claudeTranscripts: ClaudeTranscriptStore = ClaudeTranscriptStore(),
        claudeStatus: ClaudeStatusStore = ClaudeStatusStore(),
        claudeSessionRecords: ClaudeSessionRecordStore = ClaudeSessionRecordStore(),
        codexRollouts: CodexRolloutStore = CodexRolloutStore()
    ) {
        self.claudeTranscripts = claudeTranscripts
        self.claudeStatus = claudeStatus
        self.claudeSessionRecords = claudeSessionRecords
        self.codexRollouts = codexRollouts
    }

    /// One pass: one walk of each of the four trees, and nothing opened that has not changed.
    ///
    /// Each source answers everything it is asked in a single call, because each of them is
    /// asked about twice — Claude for its limits and its window sizes, Codex for its limits and
    /// its sessions — and asking separately meant walking the same tree twice and parsing the
    /// same files twice, on every one of the dozens of events a single turn produces.
    public func read(config: ThresholdConfig, now: Date = Date()) -> UsageReading {
        let activity = SessionActivity(config: config)
        let transcripts = claudeTranscripts.activeSessions(activity: activity, now: now)
        let status = claudeStatus.read()
        let records = claudeSessionRecords.read()
        let codex = codexRollouts.read(activity: activity, now: now)

        var installed: Set<AgentService> = []
        if exists(claudeTranscripts.projectsDirectory) { installed.insert(.claude) }
        if exists(codexRollouts.sessionsDirectory) { installed.insert(.codex) }

        return UsageReading(
            claudeLimits: status.limits,
            codexLimits: codex.limits,
            claudeSessions: Self.withRecords(
                Self.withWindowSizes(transcripts, from: status.payloads),
                from: records,
                activity: activity,
                now: now
            ),
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

    /// Adds to each session what only the record of its running process knows: that the agent
    /// has stopped and is waiting on the person, and which process to find its window by.
    ///
    /// The first overrides whatever the transcript concluded, and has to: a question is written
    /// there as a tool call with no result yet, which the waiting rule reads — correctly, for
    /// everything it can see — as an agent still at work. The record is the only source that
    /// knows better, so where it speaks it decides.
    ///
    /// Three things bound what a record is allowed to do, and all three are about records that
    /// outlive the process that wrote them:
    ///
    /// - **Only a session already on the list.** A record matching no row draws nothing. The
    ///   panel lists what has been written to recently, and a record cannot add a row of its
    ///   own — a session nobody is working on is not made interesting by a file left behind.
    /// - **Only the newest record of a session.** A session resumed in a new process has a
    ///   record under each pid, and the older one is frozen at whatever it last said. The
    ///   freshest one is the only one telling the truth about now.
    /// - **Only while it is fresh.** A record whose status has not moved inside the activity
    ///   window is not read at all, which is what keeps a killed process from leaving a pause
    ///   sign standing. Nothing rewrites a record while the person is away, so this is the
    ///   same half hour after which the row itself would go — the sign never outlives the row.
    ///
    /// The process is bound by one rule of its own, and it is not the freshness of the record
    /// but the process itself: the pid is carried across only if the process behind it is
    /// still the one the record was written about (`SessionProcess.isTheOne`). A record left
    /// behind by a killed session names a pid the system is free to hand out again, and a row
    /// offering to take a person to a stranger's window is worse than a row offering nothing.
    /// That check is the reason a live process is asked about on every pass rather than read
    /// once — and it is why the pid does not ride on the freshness rule above: a row with an
    /// old record and a live process still leads to the right window.
    ///
    /// Subagents are left out of both: they have no record of their own, a request is
    /// something a session makes of the person, never an agent running inside one, and an
    /// agent has no window — it lives inside its session's.
    public static func withRecords(
        _ sessions: SessionsReading,
        from records: [ClaudeSessionRecord],
        activity: SessionActivity,
        now: Date = Date(),
        isTheOne: (Int32, Date) -> Bool = SessionProcess.isTheOne
    ) -> SessionsReading {
        guard case .value(let snapshots) = sessions else { return sessions }
        var newest: [String: ClaudeSessionRecord] = [:]
        for record in records {
            guard let known = newest[record.sessionID] else {
                newest[record.sessionID] = record
                continue
            }
            if record.statusUpdatedAt > known.statusUpdatedAt { newest[record.sessionID] = record }
        }
        return .value(
            snapshots.map { snapshot in
                guard !snapshot.isSubagent, let record = newest[snapshot.sessionID] else {
                    return snapshot
                }
                let asking = record.isAsking
                    && activity.isActive(lastActivityAt: record.statusUpdatedAt, now: now)
                let process = isTheOne(record.pid, record.startedAt) ? record.pid : nil
                guard asking || process != nil else { return snapshot }
                return snapshot.withRecord(
                    asking: asking ? record.statusUpdatedAt : nil,
                    for: record.asking ?? .unnamed,
                    process: process
                )
            }
        )
    }
}
