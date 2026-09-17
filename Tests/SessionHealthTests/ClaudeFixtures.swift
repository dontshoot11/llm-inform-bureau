import Foundation

/// What Claude Code writes: the lines of a transcript and the payload of the status line,
/// both trimmed to the fields this app reads.
///
/// Shared by the session tests and the subagent tests on purpose: a subagent's file holds the
/// same lines as a session's, differing only in `isSidechain` and in where it lies on disk. Two
/// copies of these builders would let the two halves of the reader be tested against two
/// different ideas of what a transcript looks like.
let workingDirectory = "/Users/nobody/petProjects/llm-inform-bureau"

/// The moments a turn's lines carry, unless a test says otherwise: a question a minute ago, the
/// tool result half a minute later, the answer after that — a turn that happened just before
/// the clock the reader tests read it at.
///
/// Recent on purpose. How long an entry has gone unanswered is a fact the reader now uses: a
/// wait silent for longer than the configured fuse is one nobody is waiting on any more. A
/// fixture turn dated last year would be read as abandoned, and every case about the state
/// would pass for the wrong reason. Cases about the fuse itself pass their own moments.
let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)
let fixtureAskedAt = fixtureNow.addingTimeInterval(-60)
let fixtureToolResultAt = fixtureNow.addingTimeInterval(-30)
let fixtureAnsweredAt = fixtureNow.addingTimeInterval(-10)

/// A moment as Claude Code writes it: ISO 8601, to the millisecond.
func stamp(_ moment: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: moment)
}

/// One assistant entry. `blocks` names the kinds of content block it carries, because one
/// response is written as several of these — `thinking`, then `text`, then `tool_use` — and all
/// of them carry the same `stop_reason`, which is the thing the waiting rule reads.
///
/// `asking` fills a `tool_use` block in: the call to `AskUserQuestion` and the question inside
/// it, which is where a notification's wording comes from. Without it the block is left
/// nameless, which is the case the reader has to survive alongside it — a tool that is merely
/// running is written exactly like that.
func assistant(
    input: Int,
    cacheCreation: Int,
    cacheRead: Int,
    sidechain: Bool = false,
    cwd: String = workingDirectory,
    model: String = "claude-opus-5",
    stopReason: String = "tool_use",
    blocks: [String] = ["text"],
    asking: String? = nil,
    at: Date = fixtureAnsweredAt
) -> String {
    let content = blocks.map { kind -> String in
        guard kind == "tool_use", let asking else { return "{\"type\":\"\(kind)\"}" }
        return "{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"AskUserQuestion\","
            + "\"input\":{\"questions\":[{\"header\":\"Approach\",\"question\":\"\(asking)\","
            + "\"options\":[{\"label\":\"One\"},{\"label\":\"Two\"}]}]}}"
    }.joined(separator: ",")
    return """
    {"type":"assistant","isSidechain":\(sidechain),"cwd":"\(cwd)",\
    "timestamp":"\(stamp(at))",\
    "message":{"role":"assistant","model":"\(model)","stop_reason":"\(stopReason)",\
    "content":[\(content)],\
    "usage":{"input_tokens":\(input),\
    "cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead),\
    "output_tokens":400}}}
    """
}

/// The housekeeping Claude Code writes after an answer lands. None of it carries a timestamp or
/// a message, and all of it comes *after* the last thing said — which is why "the last line of
/// the file" is not what the waiting rule asks.
func serviceTail() -> [String] {
    [
        #"{"type":"system","subtype":"post_turn","sessionId":"abc"}"#,
        #"{"type":"last-prompt","prompt":"do the thing"}"#,
        #"{"type":"mode","mode":"default"}"#,
        #"{"type":"atis-latch","value":false}"#,
        #"{"type":"file-history-snapshot","messageId":"msg_1","snapshot":{}}"#
    ]
}

func userPrompt(_ text: String, sidechain: Bool = false, at: Date = fixtureAskedAt) -> String {
    """
    {"type":"user","isSidechain":\(sidechain),"cwd":"\(workingDirectory)",\
    "timestamp":"\(stamp(at))","message":{"role":"user","content":"\(text)"}}
    """
}

/// The line Claude Code writes when the person stops the agent mid-turn: an ordinary user
/// entry whose text is the marker, carrying the id of the message it cut off. Trimmed from a
/// real one — the content is a block list and not a bare string, which is the shape the rule
/// has to see through.
func interrupted(forToolUse: Bool = false, sidechain: Bool = false, at: Date = fixtureToolResultAt) -> String {
    let marker = forToolUse ? "[Request interrupted by user for tool use]" : "[Request interrupted by user]"
    return """
    {"type":"user","isSidechain":\(sidechain),"cwd":"\(workingDirectory)",\
    "timestamp":"\(stamp(at))","interruptedMessageId":"msg_1",\
    "message":{"role":"user","content":[{"type":"text","text":"\(marker)"}]}}
    """
}

/// A tool result: a user line that continues the turn rather than starting one.
func toolResult(sidechain: Bool = false, at: Date = fixtureToolResultAt) -> String {
    """
    {"type":"user","isSidechain":\(sidechain),"cwd":"\(workingDirectory)",\
    "timestamp":"\(stamp(at))","message":{"role":"user",\
    "content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}}
    """
}

/// The line Claude Code appends when a session ends: its cost, and nothing about a message.
func costState() -> String {
    """
    {"type":"cost-state","sessionId":"abc","totalCostUSD":49.68,"totalAPIDuration":3614014,\
    "totalDuration":6051383,"startTime":1789493693456}
    """
}

/// A line of something else: an attachment, carrying no message and no usage. Named apart
/// from Codex's filler, which is a different shape in a different file.
func filler(padding: Int) -> String {
    "{\"type\":\"attachment\",\"filler\":\"\(String(repeating: "x", count: padding))\"}"
}

// MARK: Where the files go

/// The directory a project's transcripts live in, named the way Claude Code names it: the
/// working directory with every separator turned into a dash.
let defaultProjectDirectoryName = "-Users-nobody-petProjects-llm-inform-bureau"

private func projectDirectory(_ root: URL, _ project: String = defaultProjectDirectoryName) -> URL {
    root.appendingPathComponent(project, isDirectory: true)
}

func makeProjectDirectory(_ root: URL, _ name: String, _ suite: TestSuite) -> URL {
    let directory = projectDirectory(makeDirectory(root, name, suite))
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        suite.expect(false, "could not create \(directory.path): \(error)")
    }
    return root.appendingPathComponent(name, isDirectory: true)
}

func writeTranscript(
    _ lines: [String],
    to root: URL,
    named name: String,
    modified: Date,
    project: String = defaultProjectDirectoryName,
    _ suite: TestSuite
) {
    write(lines, to: projectDirectory(root, project).appendingPathComponent(name), modified: modified, suite)
}

/// A subagent's transcript, where Claude Code puts it: in a `subagents` directory named after
/// the session that started it, beside that session's own file.
func writeSubagentTranscript(
    _ lines: [String],
    to root: URL,
    session: String,
    named name: String,
    modified: Date,
    _ suite: TestSuite
) {
    let directory = subagentsDirectory(root, session: session, suite)
    write(lines, to: directory.appendingPathComponent(name), modified: modified, suite)
}

/// The metadata file beside a subagent's transcript: what kind of agent it is and what it was
/// asked to do. Written as raw JSON because its absence and its oddities are what the tests are
/// about.
func writeSubagentMeta(
    _ json: String,
    to root: URL,
    session: String,
    named name: String,
    _ suite: TestSuite
) {
    let directory = subagentsDirectory(root, session: session, suite)
    write([json], to: directory.appendingPathComponent(name), modified: nil, suite)
}

private func subagentsDirectory(_ root: URL, session: String, _ suite: TestSuite) -> URL {
    let directory = projectDirectory(root)
        .appendingPathComponent(session, isDirectory: true)
        .appendingPathComponent("subagents", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        suite.expect(false, "could not create \(directory.path): \(error)")
    }
    return directory
}

private func write(_ lines: [String], to url: URL, modified: Date?, _ suite: TestSuite) {
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    } catch {
        suite.expect(false, "could not write \(url.lastPathComponent): \(error)")
    }
}

// MARK: What a running Claude Code process leaves behind

/// One record of `~/.claude/sessions`, trimmed to the fields this app reads and keeping enough
/// of the rest to be the file the CLI actually writes.
///
/// `status` is passed as a string rather than as a case of something, because the point of
/// most of these cases is a value this app has no case for: the three it has seen are `busy`,
/// `waiting` and `idle`, and the format is the CLI's own undocumented business.
func sessionRecord(
    pid: Int,
    session: String,
    status: String,
    statusUpdatedAt: Date
) -> String {
    let millis = Int(statusUpdatedAt.timeIntervalSince1970 * 1000)
    return """
    {"pid":\(pid),"sessionId":"\(session)","cwd":"\(workingDirectory)",    "startedAt":\(millis - 600_000),"version":"2.1.274","kind":"interactive","entrypoint":"cli",    "name":"llm-inform-bureau-e7","nameSource":"derived","status":"\(status)",    "updatedAt":\(millis),"statusUpdatedAt":\(millis)}
    """
}

func writeSessionRecord(
    _ contents: String,
    to directory: URL,
    named name: String,
    modified: Date,
    _ suite: TestSuite
) {
    let url = directory.appendingPathComponent(name)
    do {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    } catch {
        suite.expect(false, "could not write \(name): \(error)")
    }
}

// MARK: What the status line leaves behind

/// A statusLine payload, trimmed to the fields this app reads.
func payload(
    session: String,
    fiveHour: Double?,
    sevenDay: Double?,
    contextTokens: Int? = 15_500,
    windowSize: Int? = 200_000
) -> String {
    var parts: [String] = [
        "\"session_id\": \"\(session)\"",
        "\"cwd\": \"/Users/nobody/petProjects/llm-inform-bureau\"",
        "\"model\": {\"id\": \"claude-opus-5\", \"display_name\": \"Opus\"}"
    ]
    var context: [String] = []
    if let contextTokens { context.append("\"total_input_tokens\": \(contextTokens)") }
    if let windowSize { context.append("\"context_window_size\": \(windowSize)") }
    parts.append("\"context_window\": {\(context.joined(separator: ", "))}")
    if let fiveHour, let sevenDay {
        parts.append("""
            "rate_limits": {\
            "five_hour": {"used_percentage": \(fiveHour), "resets_at": 1738425600}, \
            "seven_day": {"used_percentage": \(sevenDay), "resets_at": 1738857600}}
            """)
    }
    return "{\(parts.joined(separator: ", "))}"
}

func writeStatus(
    _ contents: String,
    to directory: URL,
    named name: String,
    modified: Date,
    _ suite: TestSuite
) {
    let url = directory.appendingPathComponent(name)
    do {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    } catch {
        suite.expect(false, "could not write \(name): \(error)")
    }
}
