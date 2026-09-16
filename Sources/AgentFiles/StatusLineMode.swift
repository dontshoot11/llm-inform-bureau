import Foundation
import SessionHealthCore

/// The app run as Claude Code's status line command.
///
/// Claude Code runs that command after every answer and hands it a JSON payload on stdin. The
/// payload is the only place on this machine where `rate_limits` and the size of the context
/// window exist — no file under `~/.claude` carries either — so the app takes the slot, saves
/// what it is handed where `ClaudeStatusStore` reads it, and hands the same payload on to
/// whatever command was in the slot before, printing that command's output unchanged.
///
/// This is the contract the shell wrapper an earlier release installed had, moved into the app
/// itself: one thing to install instead of two, and measured at a fifth of that script's
/// startup, which matters for something that runs after every answer.
///
/// Nothing here throws and nothing here fails. Whatever the payload turns out to be, Claude
/// Code has to get a status line back and an exit code of zero — a status line command that
/// errors takes the bottom of the terminal with it.
///
/// Usage:
/// ```swift
/// switch StatusLineMode().run(input: FileHandle.standardInput.readDataToEndOfFile()) {
/// case .passedThrough(let output):     FileHandle.standardOutput.write(output)
/// case .nothingToPassTo(let reading):  print(StatusLineText.line(of: reading))
/// }
/// ```
public struct StatusLineMode: Sendable {
    /// What turns the app into the command instead of the menu bar. An argument rather than a
    /// guess at whether stdin is a terminal: the slot is configured once, by this app, and a
    /// mode the app can be asked for is a mode that can be run by hand and tested.
    public static let argument = "--status-line"

    /// What the payload said, for the line the command prints when the slot was empty before.
    ///
    /// Not `ClaudeStatusPayload`: that one is what the panel reads back off disk later, where
    /// what matters is which session it belongs to and how old it is. This is what this one
    /// run was handed, and the only thing it is for is one line of text.
    public struct Reading: Equatable, Sendable {
        public let model: String?
        public let contextTokens: Int?
        public let contextWindowTokens: Int?
        public let limits: LimitsSnapshot?

        public init(
            model: String?,
            contextTokens: Int?,
            contextWindowTokens: Int?,
            limits: LimitsSnapshot?
        ) {
            self.model = model
            self.contextTokens = contextTokens
            self.contextWindowTokens = contextWindowTokens
            self.limits = limits
        }
    }

    /// What the caller has to print. Which of the two it is depends on the slot alone, never
    /// on whether the payload was any good.
    public enum Outcome: Equatable, Sendable {
        /// The command that held the slot before ran and printed this. Print it unchanged:
        /// adding anything to it would be this app editing somebody else's status line.
        case passedThrough(Data)
        /// Nothing held the slot before, so the line is ours to write. Silence is not an
        /// option — Claude Code hides its own hints the moment a status line is configured,
        /// and an empty one would leave the bottom of the terminal blank.
        case nothingToPassTo(Reading)
    }

    /// Where the payloads go — the directory `ClaudeStatusStore` reads.
    public let directory: URL

    /// Holds the command that was in the slot before this one, exactly as it was written
    /// there. Written by the app when it takes the slot.
    public let previousCommandFile: URL

    /// How long a payload is kept. Sessions end without saying so, and their payloads would
    /// otherwise sit in the directory forever, ageing the panel's idea of what is running.
    public let keepPayloadsFor: TimeInterval

    public init(
        support: URL = SupportDirectory.url(),
        keepPayloadsFor: TimeInterval = 24 * 60 * 60
    ) {
        directory = support.appendingPathComponent("claude-status", isDirectory: true)
        previousCommandFile = support.appendingPathComponent("previous-statusline", isDirectory: false)
        self.keepPayloadsFor = keepPayloadsFor
    }

    /// Saves the payload, then answers what the status line should say.
    public func run(input: Data, now: Date = Date()) -> Outcome {
        let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]

        // A payload that does not parse is not written at all, rather than written broken.
        // `ClaudeStatusStore` reads a file it cannot parse as "the format changed" and says so
        // in the panel — a truthful complaint about the wrong thing.
        if let payload {
            save(input, forSession: Self.sessionID(in: payload))
            removePayloadsOlderThan(now.addingTimeInterval(-keepPayloadsFor))
        }

        if let command = previousCommand() {
            return .passedThrough(outputOf(command, input: input))
        }
        return .nothingToPassTo(Self.reading(from: payload, observedAt: now))
    }

    // MARK: Saving what was handed in

    /// One file per session, replaced whole on every run.
    ///
    /// Written through a temporary file in the same directory: the app reads this directory
    /// whenever it likes, and half a payload would read as a source that changed format.
    private func save(_ input: Data, forSession session: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(session).\(ProcessInfo.processInfo.processIdentifier).tmp")
        guard (try? input.write(to: temporary)) != nil else { return }
        let destination = directory.appendingPathComponent("\(session).json")
        if (try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)) == nil {
            // `replaceItemAt` needs something to replace; the first payload of a session has
            // nothing there yet.
            if (try? FileManager.default.moveItem(at: temporary, to: destination)) == nil {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
    }

    private func removePayloadsOlderThan(_ cutoff: Date) {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? manager.removeItem(at: file) }
        }
    }

    /// The session a payload belongs to, as a file name.
    ///
    /// Checked rather than trusted: the id becomes a path, and this app is not the one who
    /// decides what goes into it. Anything that is not a plain name is filed under one name
    /// for all of them — losing which session it was costs a row in the panel, while writing
    /// where we were told to could cost a file somewhere else entirely.
    static func sessionID(in payload: [String: Any]) -> String {
        guard let id = payload["session_id"] as? String, !id.isEmpty else { return unknownSession }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.unicodeScalars.allSatisfy(allowed.contains) ? id : unknownSession
    }

    static let unknownSession = "unknown-session"

    // MARK: Passing the payload on

    /// The command that held the slot, or `nil` when the slot was this app's to begin with.
    private func previousCommand() -> String? {
        guard
            let text = try? String(contentsOf: previousCommandFile, encoding: .utf8)
        else { return nil }
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    /// Runs the previous command through a shell with the same payload on stdin and collects
    /// what it printed.
    ///
    /// Through a shell because that is how Claude Code would have run it: the slot holds a
    /// command line, quoting and all, not a path. Its stdin is a file rather than a pipe so
    /// that a command which never reads it cannot leave this one blocked on a write nobody is
    /// listening to. Its stderr is left alone — a complaint from somebody else's command
    /// belongs to the person who configured it.
    private func outputOf(_ command: String, input: Data) -> Data {
        let handedOn = FileManager.default.temporaryDirectory
            .appendingPathComponent("llm-inform-bureau-statusline-\(UUID().uuidString)")
        guard (try? input.write(to: handedOn)) != nil else { return Data() }
        defer { try? FileManager.default.removeItem(at: handedOn) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = try? FileHandle(forReadingFrom: handedOn)
        let output = Pipe()
        process.standardOutput = output

        guard (try? process.run()) != nil else { return Data() }
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return printed
    }

    // MARK: The line of our own

    static func reading(from payload: [String: Any]?, observedAt: Date) -> Reading {
        let context = payload?["context_window"] as? [String: Any]
        return Reading(
            model: (payload?["model"] as? [String: Any])?["display_name"] as? String,
            contextTokens: (context?["total_input_tokens"] as? NSNumber)?.intValue,
            contextWindowTokens: (context?["context_window_size"] as? NSNumber)?.intValue,
            limits: ClaudeStatusStore.limits(payload?["rate_limits"], observedAt: observedAt)
        )
    }
}
