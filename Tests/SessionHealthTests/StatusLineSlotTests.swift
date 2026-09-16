import Foundation
import AgentFiles
import SessionHealthCore

/// Taking Claude Code's status line slot, and giving it back.
///
/// The file being edited here is `~/.claude/settings.json`, and on a machine that has been used
/// it is two hundred lines of permissions, plugins and environment that have nothing to do with
/// this app. Every case below is about the same thing from a different angle: the one key this
/// app sets is set, and not one byte of what surrounds it moves. A wrong branch here does not
/// crash anything — it quietly changes somebody's configuration, which is the failure a test has
/// to catch instead of a person.
func runStatusLineSlotTests(_ suite: TestSuite) {
    /// A hand-used `settings.json`: several keys, a nested object, an array, paths with
    /// slashes in them. Written out as text rather than built from a dictionary, because what
    /// is being checked is that this exact text survives.
    let plainSettings = """
        {
          "model": "opus",
          "env": {
            "PATH": "/usr/local/bin:/usr/bin"
          },
          "permissions": {
            "allow": ["Bash(ls:*)"]
          },
          "tui": "fullscreen"
        }
        """

    /// The same file with somebody else's status line already in it, and a setting of their own
    /// beside the command.
    let takenSettings = """
        {
          "model": "opus",
          "statusLine": {
            "type": "command",
            "command": "/Users/nobody/bin/mine.sh",
            "padding": 0
          },
          "tui": "fullscreen"
        }
        """

    let binary = "/Applications/LLMInformBureau.app/Contents/MacOS/LLMInformBureau"
    let ours = "'\(binary)' --status-line || true"

    /// A slot of its own for each case: a settings file with the given text, an empty support
    /// directory, and this app pretending to be installed.
    func slot(_ root: URL, _ name: String, settings text: String?) -> StatusLineSlot {
        let home = makeDirectory(root, name, suite)
        let support = makeDirectory(home, "support", suite)
        let claude = makeDirectory(home, ".claude", suite)
        let file = claude.appendingPathComponent("settings.json")
        if let text {
            do {
                try text.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                suite.expect(false, "could not write the fixture: \(error)")
            }
        }
        return StatusLineSlot(
            executable: URL(fileURLWithPath: binary),
            support: support,
            settings: ClaudeSettings(url: file)
        )
    }

    func text(of slot: StatusLineSlot) -> String {
        (try? String(contentsOf: slot.settings.url, encoding: .utf8)) ?? ""
    }

    func connect(_ slot: StatusLineSlot) {
        guard let change = slot.change(for: .connect) else {
            suite.expect(false, "there was nothing to connect")
            return
        }
        do {
            try slot.apply(change)
        } catch {
            suite.expect(false, "connecting threw: \(error)")
        }
    }

    func disconnect(_ slot: StatusLineSlot) {
        guard let change = slot.change(for: .disconnect) else {
            suite.expect(false, "there was nothing to disconnect")
            return
        }
        do {
            try slot.apply(change)
        } catch {
            suite.expect(false, "disconnecting threw: \(error)")
        }
    }

    withTemporaryDirectory(suite, named: "status-line-slot") { root in

        // MARK: The file around the key

        // The whole reason this edits text instead of re-serialising: the key lands where a
        // key would, and the two hundred lines nobody asked about are still byte for byte
        // what they were. Slashes unescaped, no space before a colon, keys in their order.
        suite.test("the command goes in and the rest of the file does not move") {
            let slot = slot(root, "untouched", settings: plainSettings)
            connect(slot)

            suite.expectEqual(
                text(of: slot),
                """
                {
                  "statusLine": {
                    "type": "command",
                    "command": "\(ours)"
                  },
                  "model": "opus",
                  "env": {
                    "PATH": "/usr/local/bin:/usr/bin"
                  },
                  "permissions": {
                    "allow": ["Bash(ls:*)"]
                  },
                  "tui": "fullscreen"
                }
                """,
                "the file after connecting"
            )
        }

        // Somebody else's settings inside `statusLine` are theirs. Replacing the object whole
        // would drop `padding` without anything ever saying so.
        suite.test("only the command changes inside a statusLine somebody already had") {
            let slot = slot(root, "padding", settings: takenSettings)
            connect(slot)

            suite.expectEqual(
                text(of: slot),
                """
                {
                  "model": "opus",
                  "statusLine": {
                    "type": "command",
                    "command": "\(ours)",
                    "padding": 0
                  },
                  "tui": "fullscreen"
                }
                """,
                "the file after taking a slot that was in use"
            )
        }

        // Connecting and disconnecting is a round trip, to the byte. Anything less means the
        // app left a trace in a file that is not its own.
        suite.test("disconnecting puts the file back exactly as it was") {
            let slot = slot(root, "round-trip", settings: takenSettings)
            connect(slot)
            disconnect(slot)

            suite.expectEqual(text(of: slot), takenSettings, "the file after connect and disconnect")
        }

        suite.test("disconnecting with nothing to put back removes the key and its comma") {
            let slot = slot(root, "round-trip-empty", settings: plainSettings)
            connect(slot)
            disconnect(slot)

            suite.expectEqual(text(of: slot), plainSettings, "the file after connect and disconnect")
        }

        // The last key is the case a naive removal leaves a trailing comma on — which is not
        // JSON, and would take Claude Code's settings down with it.
        suite.test("the key comes out cleanly when it is the last one in the file") {
            let settings = """
                {
                  "model": "opus",
                  "statusLine": {"type": "command", "command": "\(ours)"}
                }
                """
            let slot = slot(root, "last-key", settings: settings)
            disconnect(slot)

            suite.expectEqual(
                text(of: slot),
                """
                {
                  "model": "opus"
                }
                """,
                "the file after the last key was taken out"
            )
        }

        suite.test("the key comes out cleanly when it is the only one in the file") {
            let slot = slot(root, "only-key", settings: """
                {
                  "statusLine": {"type": "command", "command": "\(ours)"}
                }
                """)
            disconnect(slot)

            suite.expect(
                (try? JSONSerialization.jsonObject(with: Data(text(of: slot).utf8))) is [String: Any],
                "what is left must still be JSON: \(text(of: slot))"
            )
            suite.expect(!text(of: slot).contains("statusLine"), "the key is gone: \(text(of: slot))")
        }

        suite.test("a Mac with no settings.json yet gets one") {
            let slot = slot(root, "no-file", settings: nil)
            suite.expectEqual(slot.state(), .free, "the slot before")
            connect(slot)

            suite.expectEqual(slot.state(), .ours, "the slot after")
            suite.expect(
                (try? JSONSerialization.jsonObject(with: Data(text(of: slot).utf8))) is [String: Any],
                "the created file must be JSON: \(text(of: slot))"
            )
        }

        // The one refusal in here. A file this app cannot read is a file whose contents it
        // would have to guess at, and guessing costs somebody their configuration.
        suite.test("a settings.json that does not parse is read as unreadable and never written to") {
            let broken = "{ \"model\": \"opus\", oops }"
            let slot = slot(root, "broken", settings: broken)

            suite.expectEqual(slot.state(), .unreadable(slot.settings.url.path), "the slot")
            suite.expect(slot.change(for: .connect) == nil, "there is nothing to offer")
            do {
                try slot.settings.setStatusLineCommand(ours, tag: "connect")
                suite.expect(false, "writing to it must throw")
            } catch {
                suite.expectEqual(
                    error as? ClaudeSettings.Failure,
                    .unreadable(slot.settings.url.path),
                    "what it threw"
                )
            }
            suite.expectEqual(text(of: slot), broken, "the file")
        }

        suite.test("a copy of the file is kept before every write") {
            let slot = slot(root, "backups", settings: plainSettings)
            connect(slot)
            disconnect(slot)

            let directory = slot.settings.url.deletingLastPathComponent()
            let copies = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasPrefix("settings.json.backup-") }
            suite.expect(
                copies.contains { $0.hasSuffix("-connect") },
                "a copy from connecting: \(copies)"
            )
            suite.expect(
                copies.contains { $0.hasSuffix("-disconnect") },
                "a copy from disconnecting: \(copies)"
            )
        }

        // MARK: Whose the slot is

        suite.test("an empty slot, our command and somebody else's read as three different things") {
            suite.expectEqual(slot(root, "state-free", settings: plainSettings).state(), .free, "empty")

            let mine = slot(root, "state-theirs", settings: takenSettings)
            suite.expectEqual(mine.state(), .somebodyElse("/Users/nobody/bin/mine.sh"), "theirs")

            let taken = slot(root, "state-ours", settings: plainSettings)
            connect(taken)
            suite.expectEqual(taken.state(), .ours, "ours")
            suite.expect(taken.change(for: .connect) == nil, "nothing left to offer once it is ours")
        }

        // What the panel shows before it writes anything. The command being displaced is in it
        // because that is the question somebody actually has.
        suite.test("the change says what will be written and what is being kept") {
            let slot = slot(root, "change", settings: takenSettings)
            guard let change = slot.change(for: .connect) else {
                suite.expect(false, "there must be something to offer")
                return
            }
            suite.expectEqual(change.kind, .connect, "kind")
            suite.expectEqual(change.settingsPath, slot.settings.url.path, "the file named")
            suite.expectEqual(change.command, ours, "the command going in")
            suite.expectEqual(change.keptUnderneath, "/Users/nobody/bin/mine.sh", "the command kept")
        }

        // MARK: What happens to the command that was there

        // The rule of the project: the slot is one, it was theirs first, and taking it must
        // take nothing away. `StatusLineMode` reads this file to know whom to pass the payload
        // on to, so this is the whole of what keeps their status line working.
        suite.test("somebody else's command is saved where the status line mode looks for it") {
            let slot = slot(root, "saved", settings: takenSettings)
            connect(slot)

            suite.expectEqual(slot.savedCommand(), "/Users/nobody/bin/mine.sh", "what was saved")
        }

        suite.test("taking an empty slot saves nothing") {
            let slot = slot(root, "saved-nothing", settings: plainSettings)
            connect(slot)

            suite.expect(slot.savedCommand() == nil, "nothing to save: \(slot.savedCommand() ?? "—")")
        }

        // A leftover from an earlier install would have the status line calling a command the
        // person has since taken out of their own settings.
        suite.test("a saved command left over from before is dropped when the slot is empty") {
            let slot = slot(root, "stale", settings: plainSettings)
            do {
                try "/Users/nobody/bin/gone.sh".write(
                    to: slot.previousCommandFile,
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                suite.expect(false, "could not write the leftover: \(error)")
            }
            connect(slot)

            suite.expect(slot.savedCommand() == nil, "the leftover is gone: \(slot.savedCommand() ?? "—")")
        }

        suite.test("disconnecting puts the saved command back and forgets it") {
            let slot = slot(root, "restore", settings: takenSettings)
            connect(slot)
            disconnect(slot)

            suite.expectEqual(slot.state(), .somebodyElse("/Users/nobody/bin/mine.sh"), "the slot after")
            suite.expect(slot.savedCommand() == nil, "the saved copy is gone")
        }

        // Without this guard, a slot holding somebody else's command and an empty saved file
        // would read as "put nothing back" and take their status line away.
        suite.test("disconnecting does nothing at all to a slot that is not ours") {
            let slot = slot(root, "not-ours", settings: takenSettings)

            suite.expect(slot.change(for: .disconnect) == nil, "there is nothing to offer")
            suite.expectEqual(text(of: slot), takenSettings, "the file")
        }

        // MARK: A Mac set up by the release that had an installer

        // That release copied a shell wrapper into this app's own directory, put its path in
        // the slot, and saved whatever was there into the very file this app reads. Every case
        // below is about telling that apart from somebody else's command — because read as
        // somebody else's, its path would be written over the person's own saved command, and
        // then called by a wrapper that reads the file naming itself.

        /// A slot of its own with the shell wrapper in it, the wrapper's file on disk, and the
        /// command it displaced saved underneath — a machine as that release left it.
        func wrapperSlot(_ name: String, quoted: Bool, saved: String?) -> StatusLineSlot {
            let slot = slot(root, name, settings: plainSettings)
            let path = slot.shellWrapperFile.path
            let command = quoted ? "'\(path)'" : path
            do {
                try """
                    {
                      "model": "opus",
                      "statusLine": {
                        "type": "command",
                        "command": "\(command)",
                        "padding": 0
                      },
                      "tui": "fullscreen"
                    }
                    """.write(to: slot.settings.url, atomically: true, encoding: .utf8)
                try Data("#!/bin/sh\n".utf8).write(to: slot.shellWrapperFile)
                if let saved {
                    try Data(saved.utf8).write(to: slot.previousCommandFile)
                }
            } catch {
                suite.expect(false, "could not set the fixture up: \(error)")
            }
            return slot
        }

        suite.test("the wrapper an earlier release installed is not read as somebody else's command") {
            for quoted in [true, false] {
                let slot = wrapperSlot("state-wrapper-\(quoted)", quoted: quoted, saved: nil)
                suite.expectEqual(slot.state(), .oursElsewhere, "written \(quoted ? "quoted" : "bare")")
            }
        }

        // The limits are arriving through it, so the panel puts the offer under the numbers
        // rather than in place of them — which is the difference between these two answers.
        suite.test("a slot holding the wrapper is offered a take-over, not a connection") {
            let state = wrapperSlot("offer-wrapper", quoted: true, saved: nil).state()
            suite.expectEqual(state.isConnectable, false, "isConnectable")
            suite.expectEqual(state.needsTakingOver, true, "needsTakingOver")
            suite.expectEqual(state.isOurs, false, "isOurs")
        }

        suite.test("the change says the wrapper is what is being replaced, and names what stays") {
            let slot = wrapperSlot("change-wrapper", quoted: true, saved: "/Users/nobody/bin/mine.sh")
            guard let change = slot.change(for: .connect) else {
                suite.expect(false, "there must be something to offer")
                return
            }
            suite.expectEqual(change.replacesEarlierCopy, true, "replacesEarlierCopy")
            suite.expectEqual(change.command, ours, "the command going in")
            suite.expectEqual(change.keptUnderneath, "/Users/nobody/bin/mine.sh", "what stays underneath")
        }

        // The case this whole branch exists for. Read as somebody else's command, the wrapper's
        // own path would be saved over "my-own.sh" — and the person's status line would be gone
        // for good, with nothing on screen to say so.
        suite.test("taking over from the wrapper leaves the command saved underneath it untouched") {
            let slot = wrapperSlot("take-over", quoted: true, saved: "/Users/nobody/bin/mine.sh")
            connect(slot)

            suite.expectEqual(slot.state(), .ours, "the slot after")
            suite.expectEqual(slot.savedCommand(), "/Users/nobody/bin/mine.sh", "what is saved")
            suite.expect(
                !FileManager.default.fileExists(atPath: slot.shellWrapperFile.path),
                "the orphaned script must be gone"
            )
        }

        // And the way back out still works: the command put back is the person's, not the
        // wrapper's path.
        suite.test("disconnecting after a take-over puts the original command back") {
            let slot = wrapperSlot("take-over-back", quoted: false, saved: "/Users/nobody/bin/mine.sh")
            connect(slot)
            disconnect(slot)

            suite.expectEqual(slot.state(), .somebodyElse("/Users/nobody/bin/mine.sh"), "the slot after")
        }

        // Nothing was saved because there was nothing to save: the wrapper was printing its own
        // line, and so will this. What must not happen is a stale file being invented here.
        suite.test("taking over a wrapper with nothing underneath saves nothing") {
            let slot = wrapperSlot("take-over-empty", quoted: true, saved: nil)
            guard let change = slot.change(for: .connect) else {
                suite.expect(false, "there must be something to offer")
                return
            }
            suite.expect(change.keptUnderneath == nil, "nothing to keep: \(change.keptUnderneath ?? "—")")
            connect(slot)

            suite.expectEqual(slot.state(), .ours, "the slot after")
            suite.expect(slot.savedCommand() == nil, "still nothing saved: \(slot.savedCommand() ?? "—")")
        }

        // MARK: The same app, installed in a second place

        // The case that cost two thousand processes in seventy seconds on 2026-09-16: a build
        // directory and an installed bundle, both this app, and the installed one asked to
        // connect. Read as somebody else's, the other copy's command is saved in the file
        // *every* copy reads — so the app calls itself, reads the same file, and calls itself
        // again.

        /// The same binary somewhere else on disk, written the way this app writes it.
        let elsewhere = "'/Users/nobody/build/LLMInformBureau.app/Contents/MacOS/LLMInformBureau' --status-line || true"

        func elsewhereSlot(_ name: String, saved: String?) -> StatusLineSlot {
            let slot = slot(root, name, settings: nil)
            do {
                try """
                    {
                      "statusLine": { "type": "command", "command": "\(elsewhere)" }
                    }
                    """.write(to: slot.settings.url, atomically: true, encoding: .utf8)
                if let saved {
                    try Data(saved.utf8).write(to: slot.previousCommandFile)
                }
            } catch {
                suite.expect(false, "could not set the fixture up: \(error)")
            }
            return slot
        }

        suite.test("this app installed in a second place is not read as somebody else's command") {
            suite.expectEqual(elsewhereSlot("state-elsewhere", saved: nil).state(), .oursElsewhere, "the slot")
        }

        suite.test("taking over from another copy does not save that copy as the command underneath") {
            let slot = elsewhereSlot("take-over-elsewhere", saved: "/Users/nobody/bin/mine.sh")
            connect(slot)

            suite.expectEqual(slot.state(), .ours, "the slot after")
            suite.expectEqual(slot.savedCommand(), "/Users/nobody/bin/mine.sh", "what is saved")
        }

        // Even written by hand, or left by a build that did not know better: a saved command
        // that is this app cannot come back into the slot.
        suite.test("a saved command that is this app itself reads as nothing saved") {
            let slot = slot(root, "poisoned-saved", settings: nil)
            do {
                try Data(elsewhere.utf8).write(to: slot.previousCommandFile)
            } catch {
                suite.expect(false, "could not write the fixture: \(error)")
            }
            suite.expect(slot.savedCommand() == nil, "nothing saved: \(slot.savedCommand() ?? "—")")

            connect(slot)
            disconnect(slot)
            suite.expectEqual(slot.state(), .free, "the slot after disconnecting")
        }

        // A command that merely mentions the app's directory is still somebody else's.
        suite.test("a command of their own that names this app's folder is not the wrapper") {
            let slot = slot(root, "not-the-wrapper", settings: plainSettings)
            let command = "\(slot.support.path)/mine.sh"
            do {
                try """
                    {
                      "statusLine": { "type": "command", "command": "\(command)" }
                    }
                    """.write(to: slot.settings.url, atomically: true, encoding: .utf8)
            } catch {
                suite.expect(false, "could not write the fixture: \(error)")
            }
            suite.expectEqual(slot.state(), .somebodyElse(command), "the slot")
        }
    }
}
