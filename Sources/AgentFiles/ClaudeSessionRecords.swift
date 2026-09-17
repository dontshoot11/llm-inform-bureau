import Foundation
import SessionHealthCore

/// What one record in `~/.claude/sessions` says: which session a running Claude Code process
/// is on, and whether that process has stopped and is waiting on the person.
///
/// Only the three fields this app reads. The file holds a dozen more — the pid, the socket it
/// listens on, the name the CLI gave itself — and none of them answers a question the widget
/// asks.
public struct ClaudeSessionRecord: Equatable, Sendable {
    /// The session this process is running. What ties the record to a row in the panel: the
    /// record is named after the pid, and the pid means nothing to anything else here.
    public let sessionID: String

    /// Whether the CLI is waiting on the person rather than working.
    ///
    /// The one distinction a transcript cannot make. A question to the person is written there
    /// as a tool call with no result yet, which is precisely what a tool that is still running
    /// looks like; the record separates them outright — measured on a live session, a question
    /// puts it in `waiting` and the end of a turn in `idle`.
    public let isAsking: Bool

    /// When the status above was last written, which for a request is the moment it was made:
    /// nothing rewrites the record while the person is away.
    public let statusUpdatedAt: Date

    public init(sessionID: String, isAsking: Bool, statusUpdatedAt: Date) {
        self.sessionID = sessionID
        self.isAsking = isAsking
        self.statusUpdatedAt = statusUpdatedAt
    }
}

/// Reads what the running Claude Code processes say about themselves.
///
/// **Why this source exists at all.** Every other reading in this app comes from a transcript
/// or a rollout, and neither of them distinguishes "the agent asked you something and is
/// standing still" from "the agent is running a tool". Claude Code 2.1.27x keeps one small
/// JSON per interactive process in `~/.claude/sessions`, named after its pid, and that file
/// does: `busy` while a turn is worked on, `waiting` while the person is being waited on,
/// `idle` once the turn is over and nothing is asked. So this answers *who* is being waited
/// on; the transcript goes on answering everything else, including what the question was.
///
/// **What it does not promise.** The format is the CLI's own internal business and nothing
/// documents it. There is no record for a non-interactive run (`claude -p`), none for a
/// version old enough not to write them, and there may be none for the next version either.
/// A session with no record is read exactly as it was before this source existed: the
/// transcript's verdict, the blinking light, no pause sign. Missing is the normal case, not a
/// fault, and nothing in the interface mentions the file.
///
/// **A record outlives nothing for long.** It is written by a live process, and a killed one
/// leaves its last state behind — a stuck `waiting` would otherwise draw a pause sign forever.
/// Two rules bound that, and both live in the join (`UsageReader.withAsking`): a record is
/// read only for a session the panel is already showing on its own activity, and a record
/// whose status has not moved inside the activity window is not read at all.
///
/// Usage:
/// ```swift
/// let records = ClaudeSessionRecordStore().read()
/// ```
public struct ClaudeSessionRecordStore: Sendable {
    /// Where Claude Code keeps them. Not this app's directory, unlike the status line
    /// payloads: these are the CLI's own files and this app only reads them.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    public let directory: URL

    /// How many records to read. Well past the number of Claude Code windows a person has
    /// open at once, and the join discards the rest anyway.
    public let filesToScan: Int

    /// What each record said last time it was read. The CLI rewrites a record on every status
    /// change and on nothing else, so between changes every pass would parse the same JSON
    /// again — see `FileMemory` for what a hit is allowed to mean and what bounds the memory.
    ///
    /// A file that would not parse is remembered as such, for the reason the status line
    /// payloads are: otherwise the one record this app cannot read is the one file it opens on
    /// every pass, for the same disappointment.
    private let readings = FileMemory<ClaudeSessionRecord?>()

    /// Kept for the life of the app rather than made per pass: what the memory above is worth
    /// depends on outliving a pass. `directory` is the tests' way in, and the measuring rig's.
    public init(
        directory: URL = ClaudeSessionRecordStore.defaultDirectory,
        filesToScan: Int = 20
    ) {
        self.directory = directory
        self.filesToScan = filesToScan
    }

    /// One walk of the directory: every record it could read, newest first.
    ///
    /// An empty list is the ordinary answer on a machine whose Claude Code does not write
    /// these, and it is indistinguishable here from one where nothing is running. Both mean
    /// the same thing downstream — nobody is being waited on that this app can prove.
    public func read() -> [ClaudeSessionRecord] {
        // The end of a pass is what bounds the memory: whatever was not asked about is not in
        // the walk any more.
        defer { readings.forgetUnasked() }

        // `.json` and not everything: the directory also holds a key file per session, which
        // is none of this app's business.
        let files = SessionFiles.newest(in: directory, limit: filesToScan) {
            $0.pathExtension == "json"
        }
        return files.compactMap { read($0) }
    }

    private func read(_ file: SessionFiles.Found) -> ClaudeSessionRecord? {
        if let remembered = readings.value(of: file.url, unchangedSince: file.stamp) {
            return remembered
        }
        // A file that would not open said nothing, and nothing is not an answer to keep — see
        // `FileMemory`, "What it never remembers". A file that opened and made no sense is a
        // different matter, and that one is remembered on purpose.
        guard let data = try? Data(contentsOf: file.url) else { return nil }
        let record = Self.parse(data)
        readings.remember(record, of: file.url, as: file.stamp)
        return record
    }

    /// What the bytes of one record say, with nothing remembered.
    ///
    /// `nil` for anything this app cannot use: no session named, or no moment to date the
    /// status by. Neither is worth guessing at — a record with no `sessionId` matches no row,
    /// and a status with no moment could not be told from one left behind by a dead process.
    static func parse(_ data: Data) -> ClaudeSessionRecord? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let sessionID = root["sessionId"] as? String,
            let updated = root["statusUpdatedAt"] as? NSNumber
        else { return nil }
        return ClaudeSessionRecord(
            sessionID: sessionID,
            // Only `waiting` raises the sign. Anything else — `busy`, `idle`, a status this
            // app has never seen — is read as "not asking", so a CLI that renames its states
            // falls back to the behaviour of the release before this one rather than lighting
            // a sign nobody can explain.
            isAsking: (root["status"] as? String) == "waiting",
            // Milliseconds since the epoch, as the CLI writes every moment in this file.
            statusUpdatedAt: Date(timeIntervalSince1970: updated.doubleValue / 1000)
        )
    }
}
