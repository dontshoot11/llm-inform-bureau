import Foundation

/// How a file looked at the moment it was read, and the whole of what makes a second read of
/// it unnecessary.
///
/// Three fields rather than two. Size and modification date are what move when a CLI appends
/// a line, and on APFS the date carries nanoseconds — measured on this machine,
/// `mtime=1787242588.223001172` — so two different states of one file sharing both is not a
/// case this has to survive. The identifier is for the other case: a file deleted and written
/// again under the same name keeps neither its inode nor its identifier (measured:
/// `inode=210788128 → 210788129`, `0x205f900c… → 0x215f900c…`), and without it a tidied
/// directory could hand back the previous file's reading.
struct FileStamp: Hashable, Sendable {
    /// The volume's own identifier for the file, when it gives one — `fileResourceIdentifier`,
    /// which on Darwin is the volume id and the inode. `nil` on a volume that gives none,
    /// which leaves the size and the date to answer alone.
    let identity: Data?

    let size: Int
    let modified: Date
}

/// What one file said, for as long as the file still looks the way it did when it said it.
///
/// **Why this exists.** Both CLIs append to a transcript as a turn goes on, so a turn is
/// dozens of file system events, and every one of them used to re-read *every* active file
/// from the beginning — megabyte tails and quarter-megabyte heads, over and again, for a file
/// that had not been touched since the last pass. Measured before this: one pass cost around
/// 1.2–1.4 s of CPU on a set of six sessions, and a working agent held the app at a third of
/// a core. The activity rule already decides which files are worth opening; this decides which
/// of those have anything new to say.
///
/// **What it never does.** It does not stand in for a reading that failed. A remembered answer
/// belongs to a file whose size, date and identity all still match, which is the same file
/// with the same bytes — so a hit says what a re-read would have said, and `.unavailable`
/// stays `.unavailable`. Freshness is not what is being traded here; re-reading the unchanged
/// is.
///
/// **What bounds it.** Entries are made only for files a walk found, and a walk is bounded
/// (`filesToScan`, plus the subagents of each active session). `forgetUnasked()` at the end of
/// a pass drops everything this pass did not ask about, so a session that ended, or that has
/// dropped off the newest few, leaves no record behind. There is no size to tune and no expiry
/// to get wrong.
///
/// Usage:
/// ```swift
/// let readings = FileMemory<Reading>()
/// if let known = readings.value(of: file.url, unchangedSince: file.stamp) { return known }
/// let reading = parse(file)
/// readings.remember(reading, of: file.url, as: file.stamp)
/// // …at the end of the pass, once:
/// readings.forgetUnasked()
/// ```
final class FileMemory<Value: Sendable>: @unchecked Sendable {
    private struct Entry {
        let stamp: FileStamp
        let value: Value
    }

    /// A lock rather than an actor: the readers around this are `nonisolated` and synchronous
    /// all the way down, and two passes never overlap anyway — `UsageModel.refresh` holds a
    /// flag that makes the second wait. The lock is what makes that a property of the type
    /// instead of a promise about its callers.
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// Which files were asked about since the last `forgetUnasked()`. Asking is what keeps a
    /// record alive, so nothing has to know when a session ended.
    private var asked: Set<String> = []

    /// What this file said, if it has not changed since it said it.
    func value(of file: URL, unchangedSince stamp: FileStamp) -> Value? {
        value(of: file) { $0 == stamp }
    }

    /// What this file said, if it is still the same file — whatever has been appended to it
    /// since.
    ///
    /// For the parts of a reading that a later line cannot change: the directory a session
    /// started in is read from the *first* `cwd` in the transcript, and appending never moves
    /// it. A file with no identifier is never claimed to be the same file, because nothing on
    /// such a volume could tell.
    func value(of file: URL, stillTheSameFileAs stamp: FileStamp) -> Value? {
        value(of: file) { remembered in
            remembered.identity != nil && remembered.identity == stamp.identity
        }
    }

    func remember(_ value: Value, of file: URL, as stamp: FileStamp) {
        lock.lock()
        defer { lock.unlock() }
        entries[file.path] = Entry(stamp: stamp, value: value)
        asked.insert(file.path)
    }

    /// Forgets every file that was not asked about since this was last called. One call at the
    /// end of a pass; see "What bounds it" above.
    func forgetUnasked() {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { asked.contains($0.key) }
        asked.removeAll()
    }

    private func value(of file: URL, if isStillGood: (FileStamp) -> Bool) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        asked.insert(file.path)
        guard let entry = entries[file.path] else { return nil }
        guard isStillGood(entry.stamp) else {
            entries.removeValue(forKey: file.path)
            return nil
        }
        return entry.value
    }
}
