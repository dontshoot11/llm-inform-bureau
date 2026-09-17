import Foundation

/// Rollout lines as Codex writes them, trimmed to the fields this app reads.
///
/// Shared by the limits cases, the session cases and the cases about what the reader remembers
/// between passes: all three read the same files, and three ideas of what a rollout looks like
/// would let the halves of the reader be tested against three different formats.

// MARK: The limits inside a rollout

func limitsLine(primary: Double, secondary: Double, at timestamp: String) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count",\
    "info":{"last_token_usage":{"total_tokens":193454},"model_context_window":258400},\
    "rate_limits":{"limit_id":"codex","limit_name":null,\
    "primary":{"used_percent":\(primary),"window_minutes":300,"resets_at":1789249351},\
    "secondary":{"used_percent":\(secondary),"window_minutes":10080,"resets_at":1789836151},\
    "plan_type":"plus"}}}
    """
}

/// The shape Codex writes for a limit pool it has nothing to say about — seen on disk.
func emptyPoolLine() -> String {
    """
    {"timestamp":"2026-09-12T17:33:00.000Z","type":"event_msg","payload":{"type":"token_count",\
    "rate_limits":{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null,\
    "plan_type":"plus"}}}
    """
}

/// The moment a fixture line was written, parsed the same way a reader of the file would.
func instant(_ iso8601: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: iso8601) ?? .distantPast
}

func chatter(padding: Int = 0, at moment: Date = fixtureAnsweredAt) -> String {
    let text = String(repeating: "x", count: padding)
    return "{\"timestamp\":\"\(stamp(moment))\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"text\":\"\(text)\"}}"
}

/// Rollouts live nested by date, so the fixtures are nested the same way.
func makeRolloutDirectory(_ root: URL, _ name: String, _ suite: TestSuite) -> URL {
    let directory = makeDirectory(root, name, suite).appendingPathComponent("2026/09", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        suite.expect(false, "could not create \(directory.path): \(error)")
    }
    return root.appendingPathComponent(name, isDirectory: true)
}

/// Writes a rollout with an explicit modification date, because "the newest file" is the rule
/// under test and two files written in the same millisecond would not exercise it.
func write(
    lines: [String],
    to directory: URL,
    named name: String,
    modified: TimeInterval,
    _ suite: TestSuite
) {
    // The limits cases only care which file is newer, so they pass an offset rather than a date.
    write(lines: lines, to: directory, named: name, modified: Date(timeIntervalSince1970: 1_789_000_000 + modified), suite)
}

func write(
    lines: [String],
    to directory: URL,
    named name: String,
    modified: Date,
    _ suite: TestSuite
) {
    let url = directory.appendingPathComponent("2026/09", isDirectory: true).appendingPathComponent(name)
    do {
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    } catch {
        suite.expect(false, "could not write \(url.path): \(error)")
    }
}
// MARK: What a session is made of

func sessionMeta(
    session: String = "01a0a5cb-b39e-7991-9d49-e6bcc8a8f2d2",
    cwd: String = workingDirectory,
    padding: Int = 0
) -> String {
    """
    {"timestamp":"2026-09-15T15:59:45.739Z","type":"session_meta","payload":{\
    "session_id":"\(session)",\
    "cwd":"\(cwd)",\
    "base_instructions":{"text":"\(String(repeating: "x", count: padding))"}}}
    """
}

/// The events that open and close a Codex turn. Unlike Claude, which leaves its boundaries to
/// be inferred from whose entry was last, Codex announces both ends — which is the whole of
/// why the waiting rule for it is read rather than derived.
///
/// The moments default to the same turn the Claude fixtures describe: asked a minute before
/// the clock the tests read at, answered ten seconds before it. A fixture turn dated last year
/// would read as abandoned and every case about the state would pass for the wrong reason.
/// The line that opens a turn with the settings it runs on — a line of its own, not an
/// `event_msg`, which is what makes the model readable from one place instead of four.
func turnContext(model: String, at moment: Date = fixtureAskedAt) -> String {
    "{\"timestamp\":\"\(stamp(moment))\",\"type\":\"turn_context\",\"payload\":{\"model\":\"\(model)\"}}"
}

func taskStarted(at moment: Date = fixtureAskedAt) -> String {
    "{\"timestamp\":\"\(stamp(moment))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}"
}

func taskComplete(at moment: Date = fixtureAnsweredAt) -> String {
    "{\"timestamp\":\"\(stamp(moment))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}"
}

/// How a turn the person cut short ends. Every one of the 39 aborts on this machine carried
/// this reason; the field is kept in the fixture because it is what the line looks like, not
/// because the reader asks about it.
func turnAborted(at moment: Date = fixtureAnsweredAt) -> String {
    """
    {"timestamp":"\(stamp(moment))","type":"event_msg","payload":{"type":"turn_aborted",\
    "turn_id":"019fa422-6a72-7a50-9550-42d1f7cbeb8a","reason":"interrupted"}}
    """
}

/// A line whose moment this app cannot read — the shape a loosened timestamp format takes on
/// disk. The reader falls back to the file's own date for it, which for a rollout is accurate
/// to the second; falling back to an earlier line instead would age the silence by whatever
/// that line's distance is.
func unreadableMoment() -> String {
    "{\"timestamp\":\"soon\",\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\"}}"
}

/// A line that is not a `token_count` — what a rollout cut short mid-turn actually ends on.
/// Of the rollouts here that end inside a turn, two thirds end on one of these, and the gap
/// between the last `token_count` and the last line runs to six minutes, which is most of the
/// fuse.
func itemCompleted(at moment: Date) -> String {
    "{\"timestamp\":\"\(stamp(moment))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\"}}"
}

/// The call Codex writes when the model asks for a command the sandbox will not allow — the
/// line that stands at the end of a rollout for as long as the person is being asked to allow
/// it. Copied down from a live approval prompt held open on Codex 0.154.0 and trimmed to the
/// fields this app reads.
///
/// `status: "completed"` is the delivery of the call, not the running of the command: the same
/// line stands there whether the person has been asked, has allowed it and the command is
/// running, or has never been asked at all. That is the measurement the case using this
/// fixture guards — see the task's research.md.
func escalatedToolCall(at moment: Date) -> String {
    """
    {"timestamp":"\(stamp(moment))","type":"response_item","payload":{"type":"custom_tool_call",\
    "status":"completed","call_id":"call_ODqyjWuc5CuDHfq0C0TZGgtC","name":"exec",\
    "input":"text(await tools.exec_command({cmd:\\"printf 'hi' > probe.txt\\",\
    sandbox_permissions:\\"require_escalated\\",\
    justification:\\"Allow creating probe.txt in the current directory?\\"}));"}}
    """
}

/// What follows that call: the usage of the response that carried it. A line of its own rather
/// than an `event_msg`, so it has no `type` inside the payload.
func tokenUsageRecord(at moment: Date) -> String {
    """
    {"timestamp":"\(stamp(moment))","type":"token_usage_record","payload":{\
    "usage":{"input_tokens":17101,"output_tokens":80,"total_tokens":17181}}}
    """
}

func tokenCount(held: Int, window: Int, at moment: Date = fixtureAnsweredAt) -> String {
    """
    {"timestamp":"\(stamp(moment))","type":"event_msg","payload":{"type":"token_count",\
    "info":{"last_token_usage":{"total_tokens":\(held)},"model_context_window":\(window)}}}
    """
}

