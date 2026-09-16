import Foundation
import AgentFiles
import Phrasing
import SessionHealthCore

/// The app run as Claude Code's status line command.
///
/// This is the one place in the project where another program's process is on the line: Claude
/// Code runs the command after every answer, takes its stdout as the bottom row of the
/// terminal, and — if somebody else's command was in the slot first — expects that command's
/// output to come back untouched. Every failure here is silent and lands on somebody who was
/// not doing anything with this app at the time, which is why it is all tested and not
/// eyeballed.
func runStatusLineModeTests(_ suite: TestSuite) {
    // The real one, not a fixed moment: clearing away old payloads compares `now` against the
    // modification dates the file system puts on the files, and those are always today.
    let now = Date()

    /// A support directory of its own for each case, and the mode pointed at it.
    func mode(_ root: URL, _ name: String) -> (StatusLineMode, URL) {
        let support = makeDirectory(root, name, suite)
        return (StatusLineMode(support: support), support)
    }

    func jsonFiles(_ mode: StatusLineMode) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: mode.directory.path)) ?? []).sorted()
    }

    withTemporaryDirectory(suite, named: "status-line-mode") { root in
        suite.test("the payload lands where the panel reads it") {
            let (mode, _) = mode(root, "lands")
            _ = mode.run(input: statusLinePayload(session: "s1", fiveHour: 46, sevenDay: 28), now: now)

            let store = ClaudeStatusStore(directory: mode.directory)
            guard case .value(let limits) = store.latestLimits() else {
                suite.expect(false, "the store must read back what the command just wrote")
                return
            }
            suite.expectClose(limits.window(.short)?.usedPercent, 46, "five-hour window")
            suite.expectClose(limits.window(.weekly)?.usedPercent, 28, "seven-day window")
            suite.expectEqual(store.payloads().first?.contextWindowTokens, 1_000_000, "window size")
        }

        suite.test("a session has one file, rewritten, and no half-written one beside it") {
            let (mode, _) = mode(root, "one-file")
            _ = mode.run(input: statusLinePayload(session: "s1", contextTokens: 10_000), now: now)
            _ = mode.run(input: statusLinePayload(session: "s1", contextTokens: 90_000), now: now)

            suite.expectEqual(jsonFiles(mode), ["s1.json"], "what is in the directory")
            suite.expectEqual(
                ClaudeStatusStore(directory: mode.directory).payloads().first?.contextTokens,
                90_000,
                "the tokens of the last run"
            )
        }

        suite.test("payloads of sessions that ended are cleared away, today's are not") {
            let (mode, _) = mode(root, "pruned")
            _ = mode.run(input: statusLinePayload(session: "old"), now: now)
            try? FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-3 * 24 * 60 * 60)],
                ofItemAtPath: mode.directory.appendingPathComponent("old.json").path
            )
            _ = mode.run(input: statusLinePayload(session: "current"), now: now)

            suite.expectEqual(jsonFiles(mode), ["current.json"], "what is left in the directory")
        }

        // The rule of the project: the slot is one, it was theirs first, and taking it must
        // take nothing away. A wrong branch here is invisible to this app and obvious to them.
        suite.test("the command that was in the slot gets the same payload, and its output comes back unchanged") {
            let (mode, support) = mode(root, "passed-through")
            writePrevious("cat", to: support, suite)

            let input = statusLinePayload(session: "s1", fiveHour: 12, sevenDay: 3)
            guard case .passedThrough(let output) = mode.run(input: input, now: now) else {
                suite.expect(false, "a command in the slot must be the one that answers")
                return
            }
            suite.expectEqual(output, input, "the payload the previous command saw")
        }

        suite.test("the previous command's output is not tidied up on its way out") {
            let (mode, support) = mode(root, "verbatim")
            writePrevious("printf 'mine  \\n\\n'", to: support, suite)

            guard case .passedThrough(let output) = mode.run(input: statusLinePayload(session: "s1"), now: now) else {
                suite.expect(false, "expected the previous command's output")
                return
            }
            suite.expectEqual(String(decoding: output, as: UTF8.self), "mine  \n\n", "output byte for byte")
        }

        suite.test("a previous command that fails still has its say") {
            let (mode, support) = mode(root, "failing-previous")
            writePrevious("printf 'still mine'; exit 7", to: support, suite)

            guard case .passedThrough(let output) = mode.run(input: statusLinePayload(session: "s1"), now: now) else {
                suite.expect(false, "expected the previous command's output")
                return
            }
            suite.expectEqual(String(decoding: output, as: UTF8.self), "still mine", "output")
        }

        suite.test("an empty previous command is no previous command") {
            let (mode, support) = mode(root, "empty-previous")
            writePrevious("\n  \n", to: support, suite)

            guard case .nothingToPassTo = mode.run(input: statusLinePayload(session: "s1"), now: now) else {
                suite.expect(false, "a blank file must not be run as a command")
                return
            }
        }

        // The loop this guard exists for, and the one this project fell into on 2026-09-16:
        // a second copy of the app saved as "the command that was here before". Calling it
        // would have that copy read this same file and call the app again, without end.
        suite.test("a saved command that is this app itself is not called") {
            let support = makeDirectory(root, "self-referencing", suite)
            let mode = StatusLineMode(support: support, executableName: "LLMInformBureau")
            writePrevious(
                "'/Users/nobody/build/LLMInformBureau.app/Contents/MacOS/LLMInformBureau' --status-line || true",
                to: support,
                suite
            )

            guard case .nothingToPassTo = mode.run(input: statusLinePayload(session: "s1"), now: now) else {
                suite.expect(false, "the app must not hand the payload to itself")
                return
            }
        }

        // And the guard is narrow: somebody else's status line tool is still somebody else's,
        // whatever its flags are called.
        suite.test("somebody else's command with a flag of the same name is still called") {
            let support = makeDirectory(root, "not-ours", suite)
            let mode = StatusLineMode(support: support, executableName: "LLMInformBureau")
            writePrevious("printf 'theirs' # --status-line", to: support, suite)

            guard case .passedThrough(let output) = mode.run(input: statusLinePayload(session: "s1"), now: now) else {
                suite.expect(false, "expected the previous command's output")
                return
            }
            suite.expectEqual(String(decoding: output, as: UTF8.self), "theirs", "output")
        }

        suite.test("with nothing in the slot before, the numbers to print come back") {
            let (mode, _) = mode(root, "own-line")
            let outcome = mode.run(
                input: statusLinePayload(session: "s1", fiveHour: 46, sevenDay: 28, contextTokens: 93_872),
                now: now
            )
            guard case .nothingToPassTo(let reading) = outcome else {
                suite.expect(false, "expected a reading to print")
                return
            }
            suite.expectEqual(reading.model, "Opus 5 (1M context)", "model")
            suite.expectEqual(reading.contextTokens, 93_872, "tokens held")
            suite.expectEqual(reading.contextWindowTokens, 1_000_000, "window size")
            suite.expectClose(reading.limits?.window(.short)?.usedPercent, 46, "five-hour window")
        }

        // Claude Code takes the exit code and the stdout of this command on every turn. There
        // is no payload bad enough to be worth a broken status line, so the bad ones write
        // nothing and answer anyway.
        suite.test("an empty payload writes nothing and still answers") {
            let (mode, _) = mode(root, "empty-payload")
            guard case .nothingToPassTo(let reading) = mode.run(input: Data(), now: now) else {
                suite.expect(false, "expected an answer")
                return
            }
            suite.expect(reading.model == nil, "nothing was said about the model")
            suite.expect(reading.limits == nil, "nothing was said about the limits")
            suite.expectEqual(jsonFiles(mode), [], "nothing written")
        }

        suite.test("a payload that is not JSON is not written as one") {
            let (mode, _) = mode(root, "broken-payload")
            _ = mode.run(input: Data("{ this is not json".utf8), now: now)
            suite.expectEqual(jsonFiles(mode), [], "nothing written")
        }

        suite.test("a broken payload still reaches the command that was in the slot") {
            let (mode, support) = mode(root, "broken-passed-through")
            writePrevious("cat", to: support, suite)

            let input = Data("{ this is not json".utf8)
            guard case .passedThrough(let output) = mode.run(input: input, now: now) else {
                suite.expect(false, "the previous command decides what to make of it, not this one")
                return
            }
            suite.expectEqual(output, input, "what the previous command saw")
        }

        // The session id becomes a file name, and it comes from outside. Losing which session
        // a payload belongs to costs a row in the panel; writing where the id says to could
        // cost a file that has nothing to do with this app.
        suite.test("a session id that is not a plain name is filed under one that is") {
            let (mode, support) = mode(root, "escaping-id")
            _ = mode.run(input: statusLinePayload(session: "../../escaped"), now: now)

            suite.expectEqual(jsonFiles(mode), ["unknown-session.json"], "what is in the directory")
            suite.expect(
                !FileManager.default.fileExists(atPath: support.appendingPathComponent("../escaped.json").path),
                "nothing written outside the payload directory"
            )
        }
    }
}

/// The line the command prints when it holds the slot alone.
func runStatusLineTextTests(_ suite: TestSuite) {
    func limits(fiveHour: Double?, sevenDay: Double?) -> LimitsSnapshot {
        LimitsSnapshot(
            service: .claude,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            windows: [
                fiveHour.map { LimitWindow(kind: .short, usedPercent: $0, resetsAt: nil) },
                sevenDay.map { LimitWindow(kind: .weekly, usedPercent: $0, resetsAt: nil) }
            ].compactMap { $0 }
        )
    }

    suite.test("everything the payload carried, in one row") {
        suite.expectEqual(
            StatusLineText.line(
                model: "Opus 5 (1M context)",
                contextTokens: 93_872,
                contextWindowTokens: 1_000_000,
                limits: limits(fiveHour: 46, sevenDay: 28.000000000000004)
            ),
            "Opus 5 (1M context) · 94K/1.0M (9%) · 5h 46% · 7d 28%",
            "the line"
        )
    }

    suite.test("an unnamed model is still a row") {
        suite.expectEqual(
            StatusLineText.line(model: nil, contextTokens: nil, contextWindowTokens: nil, limits: nil),
            "Claude",
            "the line"
        )
    }

    // The window size arrives in this payload and nowhere else. Without it there is no share
    // to take, and the app's rule everywhere is that it shows the tokens and not a percentage
    // of something it does not know.
    suite.test("without the window size the tokens are shown and no percentage is invented") {
        suite.expectEqual(
            StatusLineText.line(model: "Opus", contextTokens: 93_872, contextWindowTokens: nil, limits: nil),
            "Opus · 94K",
            "the line"
        )
    }

    suite.test("a window the subscription did not report is left out, not shown as zero") {
        suite.expectEqual(
            StatusLineText.line(
                model: "Opus",
                contextTokens: nil,
                contextWindowTokens: nil,
                limits: limits(fiveHour: nil, sevenDay: 62)
            ),
            "Opus · 7d 62%",
            "the line"
        )
    }
}

/// The built binary, run the way Claude Code runs it.
///
/// Everything above tests the library; this tests the product — that `--status-line` reaches
/// the mode at all, that the interface does not start behind it, and that the process ends.
/// `swift run SessionHealthTests` does not build the app target, so a missing binary is said
/// out loud rather than passing quietly.
func runStatusLineBinaryTests(_ suite: TestSuite) {
    guard let binary = builtBinary() else {
        print("  skip the built binary — .build/{debug,release}/LLMInformBureau is not built (swift build)")
        return
    }

    /// Runs the binary with its own support directory and the payload on stdin. Watched rather
    /// than waited on: if the menu bar app ever starts in this mode, the process never returns,
    /// and a test that hangs says nothing to anyone.
    func run(payload: Data, support: URL) -> (status: Int32, output: String, ended: Bool) {
        let printed = support.appendingPathComponent("stdout")
        let handedIn = support.appendingPathComponent("stdin")
        FileManager.default.createFile(atPath: printed.path, contents: nil)
        try? payload.write(to: handedIn)

        let process = Process()
        process.executableURL = binary
        process.arguments = [StatusLineMode.argument]
        var environment = ProcessInfo.processInfo.environment
        environment[SupportDirectory.environmentOverrideKey] = support.path
        process.environment = environment
        process.standardInput = try? FileHandle(forReadingFrom: handedIn)
        process.standardOutput = try? FileHandle(forWritingTo: printed)

        guard (try? process.run()) != nil else {
            suite.expect(false, "could not run \(binary.path)")
            return (-1, "", false)
        }
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        guard !process.isRunning else {
            process.terminate()
            return (-1, "", false)
        }
        let output = (try? String(contentsOf: printed, encoding: .utf8)) ?? ""
        return (process.terminationStatus, output, true)
    }

    withTemporaryDirectory(suite, named: "status-line-binary") { root in
        suite.test("the binary reads the payload, ends, and prints a line of its own") {
            let support = makeDirectory(root, "own-line", suite)
            let result = run(
                payload: statusLinePayload(session: "s1", fiveHour: 46, sevenDay: 28, contextTokens: 93_872),
                support: support
            )
            suite.expect(result.ended, "the process must end — the interface has no business starting here")
            suite.expectEqual(result.status, 0, "exit code")
            suite.expectEqual(
                result.output,
                "Opus 5 (1M context) · 94K/1.0M (9%) · 5h 46% · 7d 28%\n",
                "what the status line shows"
            )
            suite.expect(
                FileManager.default.fileExists(
                    atPath: support.appendingPathComponent("claude-status/s1.json").path
                ),
                "the payload must be saved where the panel reads it"
            )
        }

        suite.test("the binary hands the payload to the command that was in the slot") {
            let support = makeDirectory(root, "passed-through", suite)
            writePrevious("cat", to: support, suite)
            let payload = statusLinePayload(session: "s1")

            let result = run(payload: payload, support: support)
            suite.expectEqual(result.status, 0, "exit code")
            suite.expectEqual(result.output, String(decoding: payload, as: UTF8.self), "what came back")
        }

        suite.test("an empty payload does not break the status line") {
            let support = makeDirectory(root, "empty", suite)
            let result = run(payload: Data(), support: support)
            suite.expect(result.ended, "the process must end")
            suite.expectEqual(result.status, 0, "exit code")
            suite.expectEqual(result.output, "Claude\n", "what the status line shows")
        }
    }
}

/// The trimmed statusLine payload, with the fields this mode reads and the nesting Claude Code
/// puts them in.
private func statusLinePayload(
    session: String,
    fiveHour: Double? = nil,
    sevenDay: Double? = nil,
    contextTokens: Int = 93_872,
    windowSize: Int = 1_000_000
) -> Data {
    var parts: [String] = [
        "\"session_id\": \"\(session)\"",
        "\"cwd\": \"/Users/nobody/petProjects/llm-inform-bureau\"",
        "\"model\": {\"id\": \"claude-opus-5[1m]\", \"display_name\": \"Opus 5 (1M context)\"}",
        "\"context_window\": {\"total_input_tokens\": \(contextTokens), \"context_window_size\": \(windowSize)}"
    ]
    if let fiveHour, let sevenDay {
        parts.append("""
            "rate_limits": {\
            "five_hour": {"used_percentage": \(fiveHour), "resets_at": 1789584600}, \
            "seven_day": {"used_percentage": \(sevenDay), "resets_at": 1789984800}}
            """)
    }
    return Data("{\(parts.joined(separator: ", "))}".utf8)
}

/// Puts a command in the slot ahead of this app, the way the app itself will when it takes one.
private func writePrevious(_ command: String, to support: URL, _ suite: TestSuite) {
    do {
        try command.write(
            to: support.appendingPathComponent("previous-statusline"),
            atomically: true,
            encoding: .utf8
        )
    } catch {
        suite.expect(false, "could not write previous-statusline: \(error)")
    }
}

/// The app binary as SwiftPM last built it, newest first — the tests run from the same
/// `.build` and have no other way to find the product they are not built with.
private func builtBinary() -> URL? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/SessionHealthTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // the repository
        .appendingPathComponent(".build", isDirectory: true)

    return ["debug", "release"]
        .map { root.appendingPathComponent("\($0)/LLMInformBureau") }
        .filter { FileManager.default.isExecutableFile(atPath: $0.path) }
        .max { left, right in modified(left) < modified(right) }
}

private func modified(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
}
