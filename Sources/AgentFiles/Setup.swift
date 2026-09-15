import Foundation
import SessionHealthCore

/// Which sources have left something to read, and whether the first run has been explained.
///
/// Both answers are about the state of the machine rather than about any reading: they are
/// what the app needs before it has a single number to show, and the only two questions it
/// asks of the disk without caring what is inside the files.
public enum SetupInspector {
    /// Looks for one file of each kind. What is in it does not matter here — a source that has
    /// written nothing at all is the difference between "not connected" and "nothing yet", and
    /// that is the whole question the first run answers.
    public static func inspect(
        statusDirectory: URL = ClaudeStatusStore.defaultDirectory,
        transcriptsDirectory: URL = ClaudeTranscriptStore.defaultProjectsDirectory,
        rolloutsDirectory: URL = CodexRolloutStore.defaultSessionsDirectory
    ) -> SetupState {
        var connected: Set<SetupState.Source> = []
        if hasAFile(in: statusDirectory, { $0.pathExtension == "json" }) {
            connected.insert(.claudeLimits)
        }
        if hasAFile(in: transcriptsDirectory, { $0.pathExtension == "jsonl" }) {
            connected.insert(.claudeSessions)
        }
        if hasAFile(in: rolloutsDirectory, {
            $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl"
        }) {
            connected.insert(.codex)
        }
        return SetupState(connected: connected)
    }

    private static func hasAFile(in directory: URL, _ isWanted: (URL) -> Bool) -> Bool {
        !SessionFiles.newest(in: directory, limit: 1, matching: isWanted).isEmpty
    }
}

/// The note that says the first-run explanation has already been shown.
///
/// A file rather than a preference: everything else this app keeps lives in the same
/// directory as a file a person can look at and delete, and deleting this one is how the
/// explanation is seen again.
public struct WelcomeRecord: Sendable {
    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        SupportDirectory.url(home: home).appendingPathComponent("welcome-shown", isDirectory: false)
    }

    public let url: URL

    public init(url: URL = WelcomeRecord.defaultURL()) {
        self.url = url
    }

    public var hasBeenShown: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Records that it was shown. A failure here costs the user a second explanation on the
    /// next launch and nothing more, so it is not worth failing a launch over.
    public func markShown(at moment: Date = Date()) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stamp = ISO8601DateFormatter().string(from: moment)
        try? Data("\(stamp)\n".utf8).write(to: url, options: .atomic)
    }
}
