import Foundation

/// Finding the files a service has most recently written to.
///
/// All three sources are the same shape — a directory tree full of per-session files, of which
/// only the newest few matter — so the walk lives here instead of three times over.
enum SessionFiles {
    struct Found {
        let url: URL
        let modified: Date
    }

    /// The most recently written matching files under `directory`, newest first.
    ///
    /// Returns an empty list for a directory that does not exist: a machine without Codex, or
    /// a status line slot never connected, is a fact about the machine and not an error.
    static func newest(
        in directory: URL,
        limit: Int,
        matching isWanted: (URL) -> Bool
    ) -> [Found] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Found] = []
        for case let url as URL in walker {
            guard isWanted(url) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            found.append(Found(url: url, modified: values?.contentModificationDate ?? .distantPast))
        }
        return found.sorted { $0.modified > $1.modified }.prefix(limit).map { $0 }
    }

    /// What Claude Code calls the directory it keeps a session's subagents in.
    static let subagentsDirectoryName = "subagents"

    /// Whether this is a subagent's transcript rather than a session's.
    ///
    /// They are the same kind of file in the same tree, and the walk that looks for the newest
    /// sessions would otherwise spend its budget on them: agent files are written *after* the
    /// session they belong to, so one busy session used to push other projects' sessions out
    /// of the list entirely. Agents are found through their session instead — see
    /// `subagentTranscripts(ofSession:)`.
    static func isSubagentTranscript(_ url: URL) -> Bool {
        url.deletingLastPathComponent().lastPathComponent == subagentsDirectoryName
    }

    /// The subagent transcripts of one session: `<session>.jsonl` has them in
    /// `<session>/subagents/` beside it. An empty list for a session that started none — and
    /// for a Claude Code old enough not to write them at all, which is the same absence.
    static func subagentTranscripts(ofSession transcript: URL, limit: Int) -> [Found] {
        let directory = transcript
            .deletingPathExtension()
            .appendingPathComponent(subagentsDirectoryName, isDirectory: true)
        return newest(in: directory, limit: limit) { $0.pathExtension == "jsonl" }
    }

    /// The project name to show for a session, from the directory it works in.
    ///
    /// A name rather than a path: the menu gives a session one line, and the last component is
    /// what the person calls the project.
    static func projectName(fromWorkingDirectory path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
