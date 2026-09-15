import Foundation

/// The one directory this app writes to.
///
/// Three things live in it and nothing else does: the payloads the statusLine wrapper leaves,
/// the editable copy of the thresholds, and the note that the first-run explanation has been
/// shown. Neither `~/.claude` nor `~/.codex` is ever written to — the app reads another
/// program's files and keeps its own state out of them.
public enum SupportDirectory {
    /// `home` is a parameter so the tests can point the whole app at a temporary directory
    /// rather than at the machine's real one.
    public static func url(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/LLMInformBureau", isDirectory: true)
    }
}
