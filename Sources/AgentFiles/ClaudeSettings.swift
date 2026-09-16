import Foundation
import SessionHealthCore

/// `~/.claude/settings.json` — the one file this app writes that is not its own.
///
/// It is the user's: two hundred lines of permissions, plugins and environment on the machine
/// this was written on, all of it hand-edited and none of it ours. One key in it decides
/// whether this app can see Claude's limits at all, and the only acceptable way to set that
/// key is to leave every byte around it exactly as it was.
///
/// Which is why nothing here re-serialises the file. `JSONSerialization` writing it back out
/// loses the order of the keys, escapes every slash in every path and puts a space before each
/// colon — measured on the real file, three changes across a file where one was asked for. So
/// reading is `JSONSerialization`'s job and writing is a scan: find where the value of the key
/// sits, replace those bytes, leave the rest alone.
///
/// A file that does not parse is never written to. Replacing somebody's configuration with a
/// guess about what they meant is worse than saying so and stopping.
///
/// Usage:
/// ```swift
/// let settings = ClaudeSettings()
/// if case .command(let existing) = settings.read() { … }
/// try settings.setStatusLineCommand("'…/LLMInformBureau' --status-line || true", tag: "connect")
/// ```
public struct ClaudeSettings: Sendable {
    /// Points this at another file. For the tests and for a run against a throwaway home —
    /// `$HOME` cannot do it, because `homeDirectoryForCurrentUser` asks the system for the
    /// account's home and ignores the variable.
    public static let environmentOverrideKey = "LLM_INFORM_BUREAU_CLAUDE_SETTINGS"

    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[Self.environmentOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json", isDirectory: false)
    }

    public let url: URL

    public init(url: URL = ClaudeSettings.defaultURL()) {
        self.url = url
    }

    /// What the file says about the status line slot.
    public enum Reading: Equatable, Sendable {
        /// No file yet, or one with nothing in it. A first install, not a problem.
        case missing
        /// The file is there and is not JSON any more. Nothing will be written to it.
        case unreadable(String)
        /// The file parses. The command is `nil` when no status line is configured.
        case command(String?)
    }

    public func read() -> Reading {
        guard let data = try? Data(contentsOf: url), !Self.isBlank(data) else { return .missing }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .unreadable(url.path)
        }
        let slot = object["statusLine"] as? [String: Any]
        return .command(slot?["command"] as? String)
    }

    public enum Failure: Error, Equatable {
        /// The file is there and does not parse, so it was left alone.
        case unreadable(String)
        /// The edit could not be carried out. The file is untouched either way: it is written
        /// once, at the end, and only after the result has been parsed back.
        case notWritten(String)
    }

    /// Puts `command` in the slot, keeping everything else in the file as it was — including
    /// anything else inside `statusLine`, such as `padding`, which is the user's setting and
    /// not this app's to drop.
    public func setStatusLineCommand(_ command: String, tag: String) throws {
        try edit(tag: tag) { bytes in
            JSONText.settingStatusLine(to: command, in: bytes)
        }
    }

    /// Takes the key out entirely. What disconnecting does when there was no status line
    /// before this app took the slot — leaving an empty command behind would be a status line
    /// that prints nothing, which is not what the machine looked like.
    public func removeStatusLine(tag: String) throws {
        try edit(tag: tag) { bytes in
            JSONText.removingStatusLine(in: bytes)
        }
    }

    // MARK: Writing

    /// The one path that writes. Everything it does is in this order for a reason: a file that
    /// does not parse is refused before anything is built, the edit is parsed back before it
    /// is allowed anywhere near the disk, a copy is kept, and the write itself is atomic.
    private func edit(tag: String, _ change: ([UInt8]) -> [UInt8]?) throws {
        let existing = try? Data(contentsOf: url)

        guard let existing, !Self.isBlank(existing) else {
            // No file yet. Only something that adds a key has anything to do here: there is
            // nothing to take out of a file that does not exist.
            guard let created = change(Array("{}".utf8)) else { return }
            try write(Data(created), tag: tag)
            return
        }

        guard (try? JSONSerialization.jsonObject(with: existing)) is [String: Any] else {
            throw Failure.unreadable(url.path)
        }
        guard let edited = change([UInt8](existing)) else { return }

        let updated = Data(edited)
        // The scan above is the only thing standing between this app and somebody's
        // configuration, so its result is parsed before it is written. A bug here then costs
        // a refusal rather than a file.
        guard (try? JSONSerialization.jsonObject(with: updated)) is [String: Any] else {
            throw Failure.notWritten("the edit did not come out as JSON, so nothing was written")
        }
        try write(updated, tag: tag)
    }

    private func write(_ data: Data, tag: String) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            backup(tag: tag)
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.notWritten("\(url.path): \(error.localizedDescription)")
        }
    }

    /// A copy beside the file before every write, the way the installer this replaces did it.
    ///
    /// The operation is in the name along with the timestamp: connecting and disconnecting in
    /// the same second would otherwise land on one name, and the copy that gets overwritten is
    /// the one holding the command the user had before — the only state actually worth keeping.
    ///
    /// Failing to copy is not worth failing the write over: the file is still written
    /// atomically, and a missing backup costs a person nothing they did not already agree to.
    private func backup(tag: String) {
        let stamp = Self.stampFormatter.string(from: Date())
        try? FileManager.default.copyItem(
            at: url,
            to: url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).backup-\(stamp)-\(tag)")
        )
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func isBlank(_ data: Data) -> Bool {
        data.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
    }
}
