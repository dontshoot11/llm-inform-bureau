import Foundation

/// Transcript lines as Claude Code writes them, trimmed to the fields this app reads.
///
/// Shared by the session tests and the subagent tests on purpose: a subagent's file holds the
/// same lines as a session's, differing only in `isSidechain` and in where it lies on disk. Two
/// copies of these builders would let the two halves of the reader be tested against two
/// different ideas of what a transcript looks like.
let workingDirectory = "/Users/nobody/petProjects/llm-inform-bureau"

/// One assistant entry. `blocks` names the kinds of content block it carries, because one
/// response is written as several of these — `thinking`, then `text`, then `tool_use` — and all
/// of them carry the same `stop_reason`, which is the thing the waiting rule reads.
func assistant(
    input: Int,
    cacheCreation: Int,
    cacheRead: Int,
    sidechain: Bool = false,
    cwd: String = workingDirectory,
    model: String = "claude-opus-5",
    stopReason: String = "tool_use",
    blocks: [String] = ["text"]
) -> String {
    let content = blocks.map { "{\"type\":\"\($0)\"}" }.joined(separator: ",")
    return """
    {"type":"assistant","isSidechain":\(sidechain),"cwd":"\(cwd)",\
    "timestamp":"2026-09-15T16:03:08.915Z",\
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

func userPrompt(_ text: String, sidechain: Bool = false) -> String {
    """
    {"type":"user","isSidechain":\(sidechain),"cwd":"\(workingDirectory)",\
    "timestamp":"2026-09-15T16:02:00.000Z","message":{"role":"user","content":"\(text)"}}
    """
}

/// A tool result: a user line that continues the turn rather than starting one.
func toolResult(sidechain: Bool = false) -> String {
    """
    {"type":"user","isSidechain":\(sidechain),"cwd":"\(workingDirectory)",\
    "timestamp":"2026-09-15T16:02:30.000Z","message":{"role":"user",\
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
