import Foundation
import SessionHealthCore

/// Reads the context budget of Claude sessions out of `~/.claude/projects`.
///
/// Claude Code appends every message to a per-session `.jsonl` as it goes, and each assistant
/// line carries the `usage` of the response that produced it. The tokens held in the context
/// are the input side of that: `input_tokens + cache_creation_input_tokens +
/// cache_read_input_tokens`, the same sum the status line's `used_percentage` is calculated
/// from. This works with nothing installed, which is why it is the base reading and the
/// statusLine wrapper is the layer that adds what a transcript cannot know.
///
/// What a transcript does not carry is the size of the context window. That stays `nil` here
/// rather than being guessed from the model name: the interface shows absolute tokens and no
/// percentage.
///
/// Subagents are read the same way out of their own files, which lie in `subagents/` beside
/// the session that started them. A sidechain line is not the *session's* context — in an
/// agent's own file it is the whole of it.
///
/// Usage:
/// ```swift
/// let store = ClaudeTranscriptStore()
/// switch store.activeSessions(activity: SessionActivity(config: config)) {
/// case .value(let sessions): show(sessions)          // an empty list means nothing is running
/// case .noData(let why), .unavailable(let why): show(why)
/// }
/// ```
public struct ClaudeTranscriptStore: Sendable {
    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// How much of the end of a transcript to read before widening once.
    ///
    /// The tokens held are on the very last answer, so the first size always answers that. The
    /// second size is for the other number: a turn that ran for a long time puts the prompt
    /// that started it a long way back, and that is exactly the turn worth calling expensive.
    static let tailSizes = [1024 * 1024, 16 * 1024 * 1024]

    /// How much of the beginning of a transcript to read for the directory the session started
    /// in. Measured on this machine: the first `cwd` appears within the first five kilobytes
    /// of every transcript on disk, and the widest margin here still costs one page-sized read.
    static let headSize = 256 * 1024

    public let projectsDirectory: URL

    /// How many of the newest transcripts to look into. Well past the number of sessions a
    /// person has open at once, and the activity rule discards the rest anyway.
    public let filesToScan: Int

    /// How many subagents of one session to look into. Measured here: a session runs between
    /// one and six of them, and this is the panel's patience rather than a limit on the CLI.
    public let subagentsToScan: Int

    public init(
        projectsDirectory: URL = ClaudeTranscriptStore.defaultProjectsDirectory,
        filesToScan: Int = 20,
        subagentsToScan: Int = 20
    ) {
        self.projectsDirectory = projectsDirectory
        self.filesToScan = filesToScan
        self.subagentsToScan = subagentsToScan
    }

    public func activeSessions(activity: SessionActivity, now: Date = Date()) -> SessionsReading {
        // Subagent files are left out of the walk on purpose: they are newer than the session
        // they belong to, so counting them here would spend the budget of files to look at on
        // one busy session and drop other projects off the list. They are found through their
        // session instead, below.
        let files = SessionFiles.newest(in: projectsDirectory, limit: filesToScan) {
            $0.pathExtension == "jsonl" && !SessionFiles.isSubagentTranscript($0)
        }
        guard !files.isEmpty else {
            return .noData("No Claude sessions yet — one appears the first time Claude Code answers.")
        }

        // Only the files that are still being worked on are opened at all: the activity rule
        // is a property of the file's modification date, and applying it first is what keeps a
        // refresh proportional to what is running rather than to what the machine has stored.
        let active = files.filter { activity.isActive(lastActivityAt: $0.modified, now: now) }
        guard !active.isEmpty else { return .value([]) }

        var snapshots: [SessionSnapshot] = []
        var unreadable = false
        for file in active {
            switch read(file, as: .session) {
            case .value(let reading):
                let session = SessionSnapshot(
                    sessionID: file.url.deletingPathExtension().lastPathComponent,
                    service: .claude,
                    contextTokens: reading.contextTokens,
                    contextWindowTokens: nil,
                    turnGrowthTokens: reading.turnGrowthTokens,
                    model: reading.model,
                    project: SessionFiles.projectName(
                        fromWorkingDirectory: Self.home(of: file.url) ?? reading.workingDirectory
                    ),
                    lastActivityAt: file.modified,
                    replyWait: activity.replyWait(since: reading.awaitingSince, now: now)
                )
                snapshots.append(session)
                snapshots.append(
                    contentsOf: subagents(of: file, in: session, on: reading.model, activity: activity, now: now)
                )
            case .noData: continue
            case .unavailable: unreadable = true
            }
        }
        if snapshots.isEmpty, unreadable {
            return .unavailable("Claude transcripts no longer look the way this app reads them.")
        }
        return .value(activity.active(snapshots, now: now))
    }

    // MARK: The subagents of one session

    /// The subagents of a session that are still running, as rows of their own.
    ///
    /// A finished agent is dropped here rather than aged out: unlike a session, an agent is
    /// over the moment it answers for the last time, and a row for it would be a window that
    /// nothing holds any more. What the metadata cannot say — the size of the window — is
    /// filled in later, by the join that knows what the session's window is.
    private func subagents(
        of session: SessionFiles.Found,
        in snapshot: SessionSnapshot,
        on sessionModel: String?,
        activity: SessionActivity,
        now: Date
    ) -> [SessionSnapshot] {
        SessionFiles.subagentTranscripts(ofSession: session.url, limit: subagentsToScan)
            .filter { activity.isActive(lastActivityAt: $0.modified, now: now) }
            .compactMap { file in
                guard let reading = read(file, as: .subagent).value else { return nil }
                let meta = SubagentMeta(besides: file.url)
                return SessionSnapshot(
                    sessionID: file.url.deletingPathExtension().lastPathComponent,
                    service: .claude,
                    contextTokens: reading.contextTokens,
                    contextWindowTokens: nil,
                    // An agent is one request as far as the person who started it is
                    // concerned; the turns inside it are not things they asked for, so there
                    // is no "last request" to report and no expensive one to warn about.
                    turnGrowthTokens: nil,
                    project: snapshot.project,
                    lastActivityAt: file.modified,
                    replyWait: activity.replyWait(since: reading.awaitingSince, now: now),
                    subagent: SubagentOrigin(
                        parentSessionID: snapshot.sessionID,
                        type: meta?.type,
                        task: meta?.task,
                        inheritsParentWindow: Self.inheritsWindow(
                            meta: meta,
                            agentModel: reading.model,
                            sessionModel: sessionModel
                        )
                    )
                )
            }
    }

    /// Whether this agent may be measured against its session's window.
    ///
    /// The metadata names a model only when one was set for the agent — `inherit` being a fork
    /// saying in as many words that it did not. The model on the agent's own lines is the
    /// safety net underneath that: the metadata is an undocumented format, and a percentage of
    /// somebody else's window would be wrong without looking wrong.
    private static func inheritsWindow(
        meta: SubagentMeta?,
        agentModel: String?,
        sessionModel: String?
    ) -> Bool {
        if let model = meta?.model, model.lowercased() != "inherit" { return false }
        if let agentModel, let sessionModel, agentModel != sessionModel { return false }
        return true
    }

    // MARK: One transcript

    /// Which kind of context a file holds, which is the whole of the difference between reading
    /// a session and reading one of its subagents.
    private enum Role {
        case session
        case subagent

        /// Whose lines count as the context of this file. A subagent writes nothing else.
        var countsSidechain: Bool { self == .subagent }
    }

    /// What one transcript said, before it is anybody's snapshot.
    private struct Reading: Equatable, Sendable {
        let contextTokens: Int
        let turnGrowthTokens: Int?
        /// When the entry that still owes an answer was written, or `nil` when nothing is
        /// owed. A moment rather than a flag: how long a wait has been silent is what decides
        /// whether it is still a wait, and that threshold belongs to the rule and not here.
        let awaitingSince: Date?
        let workingDirectory: String?
        /// The model on the last answer. A session's is what its agents inherit from; an
        /// agent's is what tells the inheritance to stop.
        let model: String?
    }

    private func read(_ file: SessionFiles.Found, as role: Role) -> SourceReading<Reading> {
        var sawUnreadableLine = false
        var result: SourceReading<Reading> = .noData("nothing answered yet")

        for tail in Self.readableTailSizes(of: file.url) {
            guard let lines = FileTail.lines(of: file.url, maxBytes: tail) else { break }

            let entries = lines.map { TranscriptLine(raw: $0) }
            sawUnreadableLine = sawUnreadableLine || entries.contains { $0.looksLikeAnEntry && $0.json == nil }

            // Neither kind of file is worth a row once it is over — a session that has been
            // closed off, an agent that has answered for the last time.
            if Self.isOver(entries, role: role) { return .noData("this one is over") }

            guard let lastAnswer = entries.last(where: { $0.isAnswer(sidechain: role.countsSidechain) })
            else { continue }
            let held = lastAnswer.contextTokens ?? 0

            // The turn began at the last prompt; everything after it — tool results and the
            // answers between them — is the same turn. Growth is measured from the context as
            // it stood when that prompt arrived, and only for a session: see `subagents`.
            let growth = role == .session ? Self.growth(to: held, in: entries) : nil
            result = .value(
                Reading(
                    contextTokens: held,
                    turnGrowthTokens: growth,
                    awaitingSince: Self.awaitingSince(entries, role: role, writtenBy: file.modified),
                    workingDirectory: lastAnswer.workingDirectory,
                    model: lastAnswer.model
                )
            )
            // Everything but the growth is answered by the first pass; only a turn whose
            // beginning is further back than that is worth reading more of the file for.
            if growth != nil || role == .subagent { break }
        }
        if case .noData = result, sawUnreadableLine {
            return .unavailable("unparseable lines")
        }
        return result
    }

    /// The tail sizes worth reading for this file: the ones smaller than it, plus the first
    /// one that covers it whole. Widening past the file only re-reads the same lines.
    private static func readableTailSizes(of url: URL) -> [Int] {
        let size = FileTail.size(of: url)
        var sizes: [Int] = []
        for tail in tailSizes {
            sizes.append(tail)
            if size <= UInt64(tail) { break }
        }
        return sizes
    }

    /// The directory the session started in, read from the head of its transcript.
    ///
    /// Not the directory of its last answer: a session that runs a command deeper in the tree
    /// carries that path from then on, and naming it after that makes one project look like
    /// two in a list where each session gets one line. The first `cwd` written is the one the
    /// session belongs to — Claude Code names the transcript's own directory after it — and
    /// the first lines of the file are where it is.
    private static func home(of url: URL) -> String? {
        guard let lines = FileTail.headLines(of: url, maxBytes: headSize) else { return nil }
        for line in lines {
            guard let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let cwd = json["cwd"] as? String
            else { continue }
            return cwd
        }
        return nil
    }

    /// Whether this file has nothing left to report — and the two kinds end differently.
    ///
    /// **A session** is closed off after its last message. Claude Code writes the session's
    /// cost as one line when the session ends — on `/clear` and on quitting — so the marker is
    /// the one thing on disk that separates a session that stopped a minute ago from one that
    /// is between turns. Resuming appends messages after it, and then the session is running
    /// again; housekeeping lines carry no message and leave it closed. Codex has no
    /// equivalent: its rollouts end on `task_complete`, which is the end of a turn and not of
    /// the session.
    ///
    /// **A subagent** gets no such line. It ends the way a turn ends: its last answer says
    /// `end_turn`, and that answer is the last message in the file. An agent that was
    /// interrupted never writes one, which is why the activity rule still applies to it.
    private static func isOver(_ entries: [TranscriptLine], role: Role) -> Bool {
        guard let lastMessage = entries.lastIndex(where: { $0.isMessage }) else {
            return role == .session && entries.contains { $0.isEndOfSession }
        }
        switch role {
        case .session:
            guard let closed = entries.lastIndex(where: { $0.isEndOfSession }) else { return false }
            return closed > lastMessage
        case .subagent:
            return entries[lastMessage].isFinalAnswer
        }
    }

    /// Whether the agent still owes this file an answer.
    ///
    /// Nothing in a transcript announces a request in flight — measured: while a turn is worked
    /// on, neither the transcript nor the statusLine payload is written at all. So the question
    /// is asked of the last thing that *was* written: does it leave an answer owed.
    ///
    /// Two things make that readable. The first is which entries count: the tail of a
    /// transcript is housekeeping — `last-prompt`, `mode`, `atis-latch`, `file-history-*`,
    /// `attachment`, `system` — written after an answer lands, so "the last line of the file"
    /// is not the last thing said. Only the conversation's own entries are asked, and only the
    /// ones belonging to this file: a session's, or an agent's sidechain lines in its own file.
    ///
    /// The second is what an answer owes. A user entry owes one outright, and a `tool_result`
    /// is a user entry — which is what keeps the wait unbroken while tools run. An assistant
    /// entry owes one when it called a tool, and `stop_reason` is what says so: measured over
    /// 32,000 assistant entries here, one response is written as several entries — `thinking`,
    /// then `text`, then `tool_use` — and every one of them carries the same `stop_reason`. The
    /// content blocks alone would read that middle `text` entry as the end of the turn and
    /// break the wait in two; `stop_reason` reads it as the middle, which is what it is.
    /// Anything other than `tool_use` — `end_turn`, `stop_sequence`, `max_tokens`, or none at
    /// all — is the turn over: whatever happens next waits on the person, not on the agent.
    ///
    /// The answer is a moment and not a yes: an entry that owes an answer says the agent was
    /// working when it was written, not that it still is. A terminal closed mid-turn leaves a
    /// transcript owing an answer forever — 34 files on this machine — so how long ago that
    /// entry was written is the other half of the question, and `SessionActivity` holds the
    /// threshold that answers it.
    private static func awaitingSince(
        _ entries: [TranscriptLine],
        role: Role,
        writtenBy modified: Date
    ) -> Date? {
        guard let last = entries.last(where: { $0.isTurnEntry(sidechain: role.countsSidechain) }),
              last.owesAnAnswer
        else { return nil }
        // Every entry of a conversation carries a timestamp — the housekeeping around them is
        // what does not, and that is skipped above. The file's own date stands in for the one
        // entry in a format that stopped carrying one.
        return last.writtenAt ?? modified
    }

    /// Growth over the turn in progress, or `nil` when its beginning is not in what was read.
    private static func growth(to held: Int, in entries: [TranscriptLine]) -> Int? {
        guard let promptIndex = entries.lastIndex(where: { $0.isMainSessionPrompt }) else { return nil }
        guard let before = entries[..<promptIndex].last(where: { $0.isAnswer(sidechain: false) })?.contextTokens else {
            return nil
        }
        return max(0, held - before)
    }
}

/// What a subagent's metadata file says about it.
///
/// Written beside the transcript as `agent-<id>.meta.json`. Around one agent in forty has none
/// — the file is not a promise of the format, and a row without a name is better than no row.
struct SubagentMeta {
    let type: String?
    let task: String?

    /// The model the agent was given, named only when it was given one at all. `inherit` is a
    /// fork saying it kept the session's.
    let model: String?

    init?(besides transcript: URL) {
        let url = transcript.deletingPathExtension().appendingPathExtension("meta.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        type = json["agentType"] as? String
        task = json["description"] as? String
        model = json["model"] as? String
    }
}

/// One line of a transcript, and the few questions this app asks of it.
private struct TranscriptLine {
    let json: [String: Any]?

    /// Whether the line claims to be one of the entries this app reads. A line that says so
    /// and does not parse is the shape a changed format takes on disk; a line of something
    /// else entirely is just a line of something else.
    let looksLikeAnEntry: Bool

    init(raw: String) {
        looksLikeAnEntry = raw.contains("\"type\":\"assistant\"") || raw.contains("\"type\": \"assistant\"")
        json = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    }

    /// Subagent traffic shares a session's file without sharing its context window; in the
    /// agent's own file it is the only traffic there is. So the question is never "is this a
    /// sidechain line" but "whose context is this file", which is what the caller answers.
    private var isSidechain: Bool { json?["isSidechain"] as? Bool ?? false }

    func isAnswer(sidechain: Bool) -> Bool {
        json?["type"] as? String == "assistant" && isSidechain == sidechain
    }

    /// A line of the conversation itself, whoever wrote it — a subagent's line included: it
    /// means the session was still running when it was written.
    var isMessage: Bool {
        let type = json?["type"] as? String
        return type == "assistant" || type == "user"
    }

    /// A line of the conversation belonging to *this* file — the session's own, or the agent's
    /// sidechain lines in the agent's own file. Whose file it is, is the caller's to say; the
    /// housekeeping that surrounds them is nobody's.
    func isTurnEntry(sidechain: Bool) -> Bool { isMessage && isSidechain == sidechain }

    /// Whether this entry leaves an answer owed. See `ClaudeTranscriptStore.awaitingSince`
    /// for why a tool call counts and why `stop_reason` answers it rather than the blocks.
    var owesAnAnswer: Bool {
        switch json?["type"] as? String {
        case "user":
            return !isInterruption
        case "assistant":
            return (json?["message"] as? [String: Any])?["stop_reason"] as? String == "tool_use"
        default:
            return false
        }
    }

    /// The moment this entry was written, as it says itself. Housekeeping lines carry no
    /// timestamp; the entries of the conversation do.
    var writtenAt: Date? {
        guard let text = json?["timestamp"] as? String else { return nil }
        return Timestamps.date(fromISO8601: text)
    }

    /// Whether this is the line Claude Code writes when the person stops the agent mid-turn.
    ///
    /// It is an ordinary user entry, so the rule above would read it as a question waiting to
    /// be answered — and it is the opposite: the agent has been told to stop, and what happens
    /// next waits on the person. Measured here: of 73 such entries, 69 are followed by the
    /// person typing again rather than by an answer, a median of 16 seconds later. Both
    /// wordings are matched by their common beginning — the second names the tool the stop
    /// landed on. A rejected tool call is *not* one of these: the agent is handed the refusal
    /// and answers it, which is why only this marker is read.
    ///
    /// The words rather than the `interruptedMessageId` beside them, because that field is on
    /// 61 of those 73 and the words are on all of them: the older entries predate it.
    var isInterruption: Bool {
        guard json?["type"] as? String == "user" else { return false }
        return text.contains("[Request interrupted by user")
    }

    /// What the entry says in words, whichever shape its content takes: a bare string for a
    /// typed question, a list of blocks for everything else.
    private var text: String {
        let content = (json?["message"] as? [String: Any])?["content"]
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
    }

    /// An answer that ended its turn rather than asking for a tool. For a subagent, whose
    /// whole life is one turn, that is the end of it.
    var isFinalAnswer: Bool {
        json?["type"] as? String == "assistant"
            && (json?["message"] as? [String: Any])?["stop_reason"] as? String == "end_turn"
    }

    /// The line Claude Code appends when the session ends, carrying what it cost.
    var isEndOfSession: Bool { json?["type"] as? String == "cost-state" }

    /// A user line that starts a turn. A `tool_result` is also a user line and does not: it is
    /// the middle of the turn that is already running.
    var isMainSessionPrompt: Bool {
        guard json?["type"] as? String == "user", !isSidechain else { return false }
        let content = (json?["message"] as? [String: Any])?["content"]
        if content is String { return true }
        guard let blocks = content as? [Any] else { return false }
        return blocks.contains { ($0 as? [String: Any])?["type"] as? String != "tool_result" }
    }

    /// Tokens held in the context after this answer: the input side of `usage`, which is what
    /// the status line's own percentage is calculated from.
    var contextTokens: Int? {
        guard
            let usage = (json?["message"] as? [String: Any])?["usage"] as? [String: Any]
        else { return nil }
        let fields = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
        return fields.reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
    }

    /// The model that wrote this answer. Never the variant: a model with a larger window is
    /// written here exactly like the ordinary one, which is why window sizes are inherited
    /// rather than looked up.
    var model: String? { (json?["message"] as? [String: Any])?["model"] as? String }

    var workingDirectory: String? { json?["cwd"] as? String }
}
