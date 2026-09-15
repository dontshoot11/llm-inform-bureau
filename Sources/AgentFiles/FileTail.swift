import Foundation

/// Reads the end of a file without loading the whole thing.
///
/// Rollouts and transcripts run to hundreds of megabytes, and everything this app wants is
/// written at the end of them. Reading a tail keeps a refresh proportional to what changed
/// rather than to the length of the session.
enum FileTail {
    /// The last complete lines within `maxBytes` of the end of the file.
    ///
    /// Both incomplete lines are dropped: the first, because the window almost certainly
    /// starts in the middle of one, and the last, because a file that is being appended to
    /// right now ends in half a line rather than in a broken one.
    static func lines(of url: URL, maxBytes: Int) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else { return nil }
        let offset = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd()
        else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        if let last = lines.last, last.isEmpty {
            lines.removeLast()          // the file ended with a newline: nothing was cut
        } else if !lines.isEmpty {
            lines.removeLast()          // a line still being written
        }
        return lines
    }

    /// The first complete lines within `maxBytes` of the start of the file.
    ///
    /// The head is where a session says what it is — Codex writes its working directory in the
    /// first line — and that line carries the whole system prompt with it, so "the first line"
    /// still means tens of kilobytes.
    static func headLines(of url: URL, maxBytes: Int) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        // The last one is cut off unless the read happened to end on a newline.
        if let last = lines.last, last.isEmpty || UInt64(data.count) < size(of: url) {
            lines.removeLast()
        }
        return lines
    }

    static func size(of url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values?.fileSize ?? 0)
    }
}
