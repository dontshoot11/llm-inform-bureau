import Foundation
import AgentFiles

/// The watcher is the whole reason a finished turn shows up at once instead of within an
/// interval, so what is tested is the timing: every case waits for a real callback and fails
/// on a timeout rather than on a wrong value.
func runSourceWatcherTests(_ suite: TestSuite) {
    /// Waits for the watcher to fire, giving it far longer than it should ever need — a
    /// generous limit keeps the suite from failing on a loaded machine, and a real regression
    /// (no event at all) still fails.
    func waitForChange(_ signal: DispatchSemaphore, seconds: Double = 5) -> Bool {
        signal.wait(timeout: .now() + seconds) == .success
    }

    withTemporaryDirectory(suite, named: "watcher") { root in
        suite.test("a file appearing in a watched tree is reported") {
            let directory = makeDirectory(root, "appearing", suite)
            let nested = makeDirectory(directory, "project-a", suite)
            let signal = DispatchSemaphore(value: 0)
            let watcher = SourceWatcher(paths: [directory]) { signal.signal() }
            watcher.start()
            defer { watcher.stop() }

            // FSEvents reports what happened after the stream started, so nothing may be
            // written until it is running.
            Thread.sleep(forTimeInterval: 0.3)
            try? "{}\n".write(to: nested.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

            suite.expect(waitForChange(signal), "a new session file must be reported without a restart")
        }

        suite.test("an append to a file already there is reported") {
            let directory = makeDirectory(root, "appending", suite)
            let file = directory.appendingPathComponent("rollout.jsonl")
            try? "{}\n".write(to: file, atomically: true, encoding: .utf8)

            let signal = DispatchSemaphore(value: 0)
            let watcher = SourceWatcher(paths: [directory]) { signal.signal() }
            watcher.start()
            defer { watcher.stop() }
            Thread.sleep(forTimeInterval: 0.3)

            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("{\"appended\":true}\n".utf8))
                try? handle.close()
            }

            suite.expect(waitForChange(signal), "a turn appended to an open session must be reported")
        }

        suite.test("a directory that does not exist yet is watched through its parent") {
            let parent = makeDirectory(root, "parent", suite)
            let missing = parent.appendingPathComponent("sessions", isDirectory: true)
            let signal = DispatchSemaphore(value: 0)
            let watcher = SourceWatcher(paths: [missing]) { signal.signal() }
            watcher.start()
            defer { watcher.stop() }
            Thread.sleep(forTimeInterval: 0.3)

            // A machine that has not run Codex yet has no sessions directory. It must not be
            // necessary to restart the app once it does.
            try? FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
            try? "{}\n".write(to: missing.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)

            suite.expect(waitForChange(signal), "a source directory created later must be picked up")
        }

        suite.test("a path with no existing ancestor is skipped rather than watched blindly") {
            let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/deeper/still")
            let watcher = SourceWatcher(paths: [missing]) { }
            watcher.start()
            defer { watcher.stop() }

            // The alternative — climbing until something exists — ends at the home directory
            // or at the root, and watching either of those recursively is not a fallback.
            suite.expectEqual(watcher.watchedPaths.count, 0, "watched paths")
        }

        suite.test("a stopped watcher reports nothing") {
            let directory = makeDirectory(root, "stopped", suite)
            let signal = DispatchSemaphore(value: 0)
            let watcher = SourceWatcher(paths: [directory]) { signal.signal() }
            watcher.start()
            Thread.sleep(forTimeInterval: 0.3)
            // Whatever setting the fixture up produced is not what this case is about; what
            // matters is that nothing arrives after the watcher is stopped.
            while signal.wait(timeout: .now()) == .success {}
            watcher.stop()

            try? "{}\n".write(to: directory.appendingPathComponent("after-stop.jsonl"), atomically: true, encoding: .utf8)
            suite.expect(!waitForChange(signal, seconds: 1), "a stopped watcher must not deliver events")
        }
    }
}
