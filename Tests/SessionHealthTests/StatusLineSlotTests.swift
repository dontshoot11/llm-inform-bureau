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
    }
}
