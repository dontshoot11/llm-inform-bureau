import Foundation
import SessionHealthCore

/// Claude Code's one status line slot, as something the app can take and give back.
///
/// Everything the old shell installer did, moved into the app: read what is in the slot, save
/// whatever was there, write this binary in its place, and put the old command back on the way
/// out. It is the other half of `StatusLineMode` — that one is the command being run, this one
/// is what puts it in the slot.
///
/// It also knows the slot it is replacing. A Mac set up by the release that shipped an
/// installer has that installer's shell wrapper in the slot, and telling it apart from
/// somebody else's command is what makes taking over from it safe rather than a loop —
/// see `isShellWrapper`.
///
/// Two rules shape all of it. The slot is one and it was somebody's first, so a command found
/// in it is saved and goes on being called with the same payload. And a change to
/// `settings.json` is shown before it is made, never after — `change(for:)` is what the panel
/// puts in front of the person, and nothing here writes until `apply` is called with it.
///
/// Usage:
/// ```swift
/// let slot = StatusLineSlot()
/// let change = slot.change(for: .connect)   // what would happen
/// try slot.apply(change)                    // only once they have said yes
/// ```
public struct StatusLineSlot: Sendable {
    /// The binary that will be written into the slot — this one, wherever it is installed.
    public let executable: URL

    /// This app's own directory, where the displaced command is kept.
    public let support: URL

    public let settings: ClaudeSettings

    public init(
        executable: URL = StatusLineSlot.runningExecutable(),
        support: URL = SupportDirectory.url(),
        settings: ClaudeSettings = ClaudeSettings()
    ) {
        self.executable = executable
        self.support = support
        self.settings = settings
    }

    /// The command as it goes into the file.
    ///
    /// Shell-quoted because Claude Code runs the slot through a shell and this path contains
    /// "Application Support". The `|| true` is for the day the app is dragged to the trash
    /// without being disconnected first: a command that is no longer there exits non-zero, and
    /// what the person sees then is an error at the bottom of every turn instead of an empty
    /// status line. It costs nothing while the binary is there.
    public var command: String {
        "'\(executable.path.replacingOccurrences(of: "'", with: "'\\''"))' \(StatusLineMode.argument) || true"
    }

    /// Where the command that was in the slot before this app is kept — the same file
    /// `StatusLineMode` reads when it decides whom to pass the payload on to.
    public var previousCommandFile: URL {
        support.appendingPathComponent("previous-statusline", isDirectory: false)
    }

    /// The shell wrapper an earlier release of this app copied here and put in the slot.
    ///
    /// It did exactly what `StatusLineMode` does now, down to the file it saved the displaced
    /// command in — which is why taking over from it is a change of one line in
    /// `settings.json` and nothing else.
    public var shellWrapperFile: URL {
        support.appendingPathComponent("statusline-wrapper.sh", isDirectory: false)
    }

    /// Whose the slot is right now.
    public func state() -> StatusLineSlotState {
        switch settings.read() {
        case .missing:
            return .free
        case .unreadable(let path):
            return .unreadable(path)
        case .command(let command):
            guard let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .free
            }
            if isOurs(command) { return .ours }
            if isShellWrapper(command) { return .shellWrapper }
            return .somebodyElse(command)
        }
    }

    /// Whether a command in the slot is this app's.
    ///
    /// By the path rather than by the whole line: the same bundle can be written with or
    /// without quotes and with or without the tail, and all of those are still this binary
    /// answering. What it must not match is a command that merely mentions the app somewhere.
    private func isOurs(_ command: String) -> Bool {
        command.contains(executable.path) && command.contains(StatusLineMode.argument)
    }

    /// Whether a command in the slot is the wrapper an earlier release installed — written
    /// bare or in single quotes, both of which that installer produced.
    ///
    /// This has to be told apart from somebody else's command, and the cost of not telling
    /// them apart is the whole reason the case exists: connecting would save the wrapper as
    /// "the command that was here before", over the top of the person's own command saved in
    /// that same file — and then call it, so the wrapper would read the file naming itself and
    /// go round for ever.
    private func isShellWrapper(_ command: String) -> Bool {
        command.contains(shellWrapperFile.path)
    }

    /// What the saved command is, if there is one.
    public func savedCommand() -> String? {
        guard let text = try? String(contentsOf: previousCommandFile, encoding: .utf8) else { return nil }
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    /// What either button would change, before anything is written. `nil` when there is
    /// nothing to do — the slot is already the way the button would leave it, or the file
    /// cannot be read at all.
    public func change(for kind: StatusLineChange.Kind) -> StatusLineChange? {
        let state = state()
        switch kind {
        case .connect:
            switch state {
            case .ours, .unreadable:
                return nil
            case .free:
                return StatusLineChange(kind: .connect, settingsPath: settings.url.path, command: command)
            case .shellWrapper:
                // What is kept is what the wrapper was already keeping. The person's own
                // command, if they had one, is in that file and stays there untouched — this
                // change is one line of `settings.json` and a leftover script deleted.
                return StatusLineChange(
                    kind: .connect,
                    settingsPath: settings.url.path,
                    command: command,
                    keptUnderneath: savedCommand(),
                    replacesShellWrapper: true
                )
            case .somebodyElse(let existing):
                return StatusLineChange(
                    kind: .connect,
                    settingsPath: settings.url.path,
                    command: command,
                    keptUnderneath: existing
                )
            }
        case .disconnect:
            // Only ever our own command comes out. The guard is the whole point of the branch:
            // without it, a slot holding somebody else's command and an empty saved file would
            // read as "put nothing back" and take their status line away.
            guard state.isOurs else { return nil }
            return StatusLineChange(
                kind: .disconnect,
                settingsPath: settings.url.path,
                command: savedCommand()
            )
        }
    }

    /// Carries out a change that was shown first.
    ///
    /// The state is read again here rather than trusted from the change: the panel may have
    /// been open for an hour, and what it is about to write should be decided against the file
    /// as it is now.
    public func apply(_ change: StatusLineChange) throws {
        switch change.kind {
        case .connect:
            try connect()
        case .disconnect:
            try disconnect()
        }
    }

    private func connect() throws {
        var takingOverFromWrapper = false
        switch state() {
        case .ours:
            return
        case .unreadable(let path):
            throw ClaudeSettings.Failure.unreadable(path)
        case .somebodyElse(let existing):
            try save(existing)
        case .shellWrapper:
            // Nothing is saved and nothing is dropped. The wrapper read the same file this
            // binary reads, so whatever it was passing the payload on to goes on being passed
            // the payload — the only thing that changes is who does the passing.
            takingOverFromWrapper = true
        case .free:
            // A saved command with nothing in the slot is a leftover: the command it names is
            // not what this machine is configured with any more, and keeping it would have the
            // status line calling something the person took out themselves.
            try? FileManager.default.removeItem(at: previousCommandFile)
        }
        try settings.setStatusLineCommand(command, tag: "connect")
        if takingOverFromWrapper {
            // Only after the slot is ours, and only this one file: it is the app's own copy,
            // nothing names it any more, and deleting it before the write would have left a
            // slot pointing at a script that is gone.
            try? FileManager.default.removeItem(at: shellWrapperFile)
        }
    }

    private func disconnect() throws {
        guard state().isOurs else { return }
        if let saved = savedCommand() {
            try settings.setStatusLineCommand(saved, tag: "disconnect")
        } else {
            try settings.removeStatusLine(tag: "disconnect")
        }
        try? FileManager.default.removeItem(at: previousCommandFile)
    }

    /// Keeps the command that was in the slot, for `StatusLineMode` to go on calling.
    private func save(_ command: String) throws {
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try Data(command.utf8).write(to: previousCommandFile, options: .atomic)
        } catch {
            // Nothing is written to `settings.json` after this throws, so the slot is left as
            // it was. Taking it while the command it displaced could not be saved is the one
            // failure here that would cost somebody something.
            throw ClaudeSettings.Failure.notWritten(
                "\(previousCommandFile.path): \(error.localizedDescription)"
            )
        }
    }

    /// This binary, wherever it was installed.
    ///
    /// `Bundle.main.executableURL` inside an app bundle, which is what is running when the
    /// panel is open; the argument the process was started with otherwise, which is what the
    /// tests and a run from `.build` have.
    public static func runningExecutable() -> URL {
        if let executable = Bundle.main.executableURL {
            return executable.resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: CommandLine.arguments.first ?? "LLMInformBureau")
            .resolvingSymlinksInPath()
    }
}
