import Foundation
import AgentFiles
import SessionHealthCore

/// A transcript of a long session runs to hundreds of megabytes, and the widget re-reads it
/// every time the file changes — which is once per assistant message. Reading the whole thing
/// would turn a working session into a machine that spends its disk on the widget watching it.
///
/// The fixture is a sparse file: the size is real, the bytes in the middle cost nothing to
/// create, and the reader has no way to tell the difference.
func runLargeTranscriptTests(_ suite: TestSuite, config: ThresholdConfig) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let activity = SessionActivity(config: config)
    let workingDirectory = "/Users/nobody/petProjects/llm-inform-bureau"
    let gigantic = 400 * 1024 * 1024

    func size(of url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    withTemporaryDirectory(suite, named: "large-transcript") { root in
        let projects = makeDirectory(root, "projects", suite)
        let directory = makeDirectory(projects, "-Users-nobody-petProjects-llm-inform-bureau", suite)
        let file = directory.appendingPathComponent("huge.jsonl")

        func assistant(cacheRead: Int, cacheCreation: Int) -> String {
            """
            {"type":"assistant","isSidechain":false,"cwd":"\(workingDirectory)",\
            "timestamp":"2026-09-15T16:03:08.915Z",\
            "message":{"role":"assistant","model":"claude-opus-5","usage":{"input_tokens":1,\
            "cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead),\
            "output_tokens":400}}}
            """
        }

        // The last turn of a session that has been running all day: an answer, the prompt that
        // started the current turn, and the answer to it.
        let tail = [
            // The window into the file starts in the middle of a line, and the reader drops
            // that line. On a real transcript it is one line of many; here it has to be put
            // there deliberately, or the fixture would lose a line the test depends on.
            "{\"type\":\"attachment\",\"filler\":\"cut in half by the window\"}",
            assistant(cacheRead: 120_000, cacheCreation: 0),
            """
            {"type":"user","isSidechain":false,"cwd":"\(workingDirectory)",\
            "timestamp":"2026-09-15T16:02:00.000Z","message":{"role":"user","content":"go on"}}
            """,
            assistant(cacheRead: 151_000, cacheCreation: 1_000)
        ]

        FileManager.default.createFile(atPath: file.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: file) else {
            suite.test("a sparse transcript can be created") { suite.expect(false, "could not open \(file.path)") }
            return
        }
        try? handle.truncate(atOffset: UInt64(gigantic))
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((tail.joined(separator: "\n") + "\n").utf8))
        try? handle.close()
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)

        suite.test("the fixture really is hundreds of megabytes") {
            suite.expect(size(of: file) >= UInt64(gigantic), "size: \(size(of: file))")
        }

        suite.test("a session is read out of a 400 MB transcript from its end alone") {
            let started = Date()
            let reading = ClaudeTranscriptStore(projectsDirectory: projects).activeSessions(activity: activity, now: now)
            let elapsed = Date().timeIntervalSince(started)

            guard let session = reading.value?.first else {
                suite.expect(false, "expected a session, got \(reading)")
                return
            }
            suite.expectEqual(session.contextTokens, 152_001, "tokens held")
            suite.expectEqual(session.turnGrowthTokens, 32_000, "growth over the turn that began inside the window")

            // Reading 400 MB off this disk takes seconds; reading the last megabyte of it does
            // not. The limit is loose on purpose — it fails on reading the file, not on load.
            suite.expect(elapsed < 2, "a refresh took \(String(format: "%.2f", elapsed))s — the tail is not being read alone")
        }
    }
}
