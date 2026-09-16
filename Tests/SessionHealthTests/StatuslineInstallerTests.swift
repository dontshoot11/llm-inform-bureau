import Foundation

/// What `Scripts/install-statusline.sh` does to `~/.claude/settings.json` — the only file this
/// project writes that belongs to somebody else.
///
/// These cases run the real script against a throwaway `HOME`, because the thing worth checking
/// is not a Swift function but the script's branching: there is exactly one statusLine slot, the
/// user's own command lives in it, and the rule of the project is that it survives. A wrong
/// branch here does not crash anything — it quietly removes a setting nobody can get back, which
/// is precisely the kind of failure a test has to catch instead of a person.
func runStatuslineInstallerTests(_ suite: TestSuite) {
    let script = repositoryRoot
        .appendingPathComponent("Scripts/install-statusline.sh")

    guard FileManager.default.fileExists(atPath: script.path) else {
        suite.test("install-statusline.sh is where this test expects it") {
            suite.expect(false, "not found at \(script.path)")
        }
        return
    }

    /// A `HOME` with the given statusLine command already configured, plus a neighbouring key
    /// and a nested one: the point of parsing the file instead of editing it with a regex is
    /// that everything else in it survives, and only a fixture with something else in it can
    /// show that.
    func makeHome(_ root: URL, _ name: String, command: String?) -> URL {
        let home = makeDirectory(root, name, suite)
        let claude = makeDirectory(home, ".claude", suite)
        var settings: [String: Any] = ["model": "opus"]
        if let command {
            settings["statusLine"] = ["type": "command", "command": command, "padding": 1]
        }
        let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        FileManager.default.createFile(
            atPath: claude.appendingPathComponent("settings.json").path,
            contents: data
        )
        return home
    }

    func settingsOf(_ home: URL) -> [String: Any] {
        let url = home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    func statusLineOf(_ home: URL) -> [String: Any]? {
        settingsOf(home)["statusLine"] as? [String: Any]
    }

    func commandIn(_ home: URL) -> String? {
        statusLineOf(home)?["command"] as? String
    }

    /// Runs the script with the given argument against `home`. Returns its exit code; output is
    /// captured so a passing run stays quiet.
    @discardableResult
    func run(_ argument: String?, in home: URL) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + (argument.map { [$0] } ?? [])
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        process.environment = environment
        // One pipe for both streams: the output is captured only to keep a passing run quiet,
        // and with two pipes this would have to drain them concurrently — reading one to the end
        // while the other fills its buffer is how a child blocks forever.
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            suite.expect(false, "could not run the script: \(error)")
            return -1
        }
        _ = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func wrapperPath(_ home: URL) -> String {
        home.appendingPathComponent(
            "Library/Application Support/LLMInformBureau/statusline-wrapper.sh"
        ).path
    }

    withTemporaryDirectory(suite, named: "statusline-installer") { root in
        suite.test("a preview changes nothing") {
            let home = makeHome(root, "preview", command: "my-own.sh")
            suite.expectEqual(run(nil, in: home), 0, "exit code")
            suite.expectEqual(commandIn(home), "my-own.sh", "command after a preview")
        }

        suite.test("connecting keeps the command that was there and calls it") {
            let home = makeHome(root, "keeps", command: "my-own.sh")
            suite.expectEqual(run("--apply", in: home), 0, "exit code")
            suite.expectEqual(commandIn(home), "'\(wrapperPath(home))'", "command after --apply")

            let previous = home.appendingPathComponent(
                "Library/Application Support/LLMInformBureau/previous-statusline"
            )
            let saved = try? String(contentsOf: previous, encoding: .utf8)
            suite.expectEqual(saved, "my-own.sh", "the saved predecessor")
        }

        suite.test("keys the user had beside statusLine are left alone") {
            let home = makeHome(root, "neighbours", command: "my-own.sh")
            run("--apply", in: home)
            suite.expectEqual(settingsOf(home)["model"] as? String, "opus", "a neighbouring key")
            suite.expectEqual(statusLineOf(home)?["padding"] as? Int, 1, "a key inside statusLine")
        }

        suite.test("connecting twice does not save the wrapper as its own predecessor") {
            let home = makeHome(root, "twice", command: "my-own.sh")
            run("--apply", in: home)
            suite.expectEqual(run("--apply", in: home), 0, "exit code of the second --apply")

            let previous = home.appendingPathComponent(
                "Library/Application Support/LLMInformBureau/previous-statusline"
            )
            let saved = try? String(contentsOf: previous, encoding: .utf8)
            suite.expectEqual(saved, "my-own.sh", "the saved predecessor after a second --apply")
            suite.expectEqual(commandIn(home), "'\(wrapperPath(home))'", "command")
        }

        suite.test("removing puts the command that was there back") {
            let home = makeHome(root, "restore", command: "my-own.sh")
            run("--apply", in: home)
            suite.expectEqual(run("--uninstall", in: home), 0, "exit code")
            suite.expectEqual(commandIn(home), "my-own.sh", "command after --uninstall")
            suite.expectEqual(statusLineOf(home)?["padding"] as? Int, 1, "padding after --uninstall")
        }

        // The two cases this file exists for. Both were live: --uninstall restored whatever was
        // saved without asking whether the wrapper was in the slot at all, and an empty saved
        // value means "delete the key" — so the second run, and a run on a Mac that never had
        // the wrapper, took the user's own command away.
        suite.test("removing twice leaves the restored command alone") {
            let home = makeHome(root, "twice-uninstall", command: "my-own.sh")
            run("--apply", in: home)
            run("--uninstall", in: home)
            suite.expectEqual(run("--uninstall", in: home), 0, "exit code of the second --uninstall")
            suite.expectEqual(commandIn(home), "my-own.sh", "command after a second --uninstall")
        }

        suite.test("removing what was never connected touches nothing") {
            let home = makeHome(root, "never-connected", command: "my-own.sh")
            suite.expectEqual(run("--uninstall", in: home), 0, "exit code")
            suite.expectEqual(commandIn(home), "my-own.sh", "the user's own command")
            suite.expectEqual(statusLineOf(home)?["padding"] as? Int, 1, "padding")
        }

        suite.test("an empty slot is filled and emptied again") {
            let home = makeHome(root, "empty-slot", command: nil)
            run("--apply", in: home)
            suite.expectEqual(commandIn(home), "'\(wrapperPath(home))'", "command after --apply")

            suite.expectEqual(run("--uninstall", in: home), 0, "exit code")
            suite.expect(statusLineOf(home) == nil, "the key must be gone, as there was none before")
            suite.expectEqual(settingsOf(home)["model"] as? String, "opus", "a neighbouring key")
        }

        suite.test("settings.json that is not valid JSON does not stop the install") {
            let home = makeDirectory(root, "broken-json", suite)
            let claude = makeDirectory(home, ".claude", suite)
            let settings = claude.appendingPathComponent("settings.json")
            try? "{ this is not json".write(to: settings, atomically: true, encoding: .utf8)

            suite.expectEqual(run("--apply", in: home), 0, "exit code")
            suite.expectEqual(commandIn(home), "'\(wrapperPath(home))'", "command")
        }

        suite.test("a HOME with no settings.json at all gets one") {
            let home = makeDirectory(root, "no-settings", suite)
            suite.expectEqual(run("--apply", in: home), 0, "exit code")
            suite.expectEqual(commandIn(home), "'\(wrapperPath(home))'", "command")
        }

        suite.test("every write keeps a backup of the file it changed") {
            let home = makeHome(root, "backups", command: "my-own.sh")
            run("--apply", in: home)
            run("--uninstall", in: home)

            let claude = home.appendingPathComponent(".claude")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: claude.path)) ?? []
            let backups = names.filter { $0.hasPrefix("settings.json.backup-") }
            // One per write: --apply and --uninstall both edit the user's file. Run back to
            // back they land on the same second, so the operation is part of the name — without
            // it the second copy overwrites the first, and the first is the one holding the
            // user's original command.
            suite.expect(backups.count >= 2, "backups kept: \(backups.count) — \(names)")
            suite.expect(
                backups.contains { $0.hasSuffix("-apply") },
                "a backup from before --apply: \(backups)"
            )
            suite.expect(
                backups.contains { $0.hasSuffix("-uninstall") },
                "a backup from before --uninstall: \(backups)"
            )
        }

        suite.test("an unknown argument is refused without touching anything") {
            let home = makeHome(root, "bad-argument", command: "my-own.sh")
            suite.expect(run("--wat", in: home) != 0, "an unknown argument must not exit 0")
            suite.expectEqual(commandIn(home), "my-own.sh", "command")
        }
    }
}

/// The repository this test file was compiled from. `#filePath` is the one thing that still
/// points at the checkout when the test binary runs from `.build`, and the script under test
/// lives beside the sources rather than inside the built product.
private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Tests/SessionHealthTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // the repository
