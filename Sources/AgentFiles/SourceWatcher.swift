import CoreServices
import Foundation

/// Watches the directory trees the readers read, and says when something in them changed.
///
/// This is what makes a finished turn show up at once. Both CLIs append to a file as the turn
/// ends — the transcript, the rollout, the file the status line writes — so the end of
/// a turn is a file system event, and the widget does not have to poll for it. Polling was the
/// previous arrangement and it had the two faults polling always has: a notification that
/// arrives late enough to be about the past, and a machine re-reading files that nobody
/// touched.
///
/// `FSEvents` rather than one watcher per file: the trees are nested by project and by date,
/// the interesting file is a new one as often as it is an existing one, and a session that
/// starts while the app runs has to be picked up without a restart.
///
/// The callback says only *that* something changed, never what. Deciding what to re-read is
/// the readers' job, and they already decide it from modification dates — passing paths here
/// would be a second, worse copy of that rule.
///
/// Usage:
/// ```swift
/// let watcher = SourceWatcher(paths: SourceWatcher.defaultPaths) { … }
/// watcher.start()
/// ```
public final class SourceWatcher: @unchecked Sendable {
    /// The three trees the readers read: Claude's transcripts, Codex's rollouts, and what the
    /// status line leaves for this app.
    public static var defaultPaths: [URL] {
        [
            ClaudeTranscriptStore.defaultProjectsDirectory,
            CodexRolloutStore.defaultSessionsDirectory,
            ClaudeStatusStore.defaultDirectory
        ]
    }

    /// How long FSEvents may batch events before delivering them. Short enough that nobody
    /// experiences it as a delay, long enough that the dozens of writes one turn makes arrive
    /// as one callback rather than as thirty.
    public static let coalescingLatency: TimeInterval = 0.2

    /// The paths actually being watched, which is not always the paths asked for: a directory
    /// that does not exist yet is watched through its parent. Empty until `start()`.
    public private(set) var watchedPaths: [URL] = []

    private let requestedPaths: [URL]
    private let latency: TimeInterval
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.artjemnikitin.llm-inform-bureau.watcher")
    private var stream: FSEventStreamRef?

    public init(
        paths: [URL],
        latency: TimeInterval = SourceWatcher.coalescingLatency,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.requestedPaths = paths
        self.latency = latency
        self.handler = Handler(onChange: onChange)
    }

    deinit {
        stop()
    }

    /// Starts watching. Watching nothing is a valid outcome — a machine with neither CLI
    /// installed — and the app's own periodic refresh covers it.
    public func start() {
        guard stream == nil else { return }
        watchedPaths = requestedPaths.compactMap(Self.watchable)
        guard !watchedPaths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // `NoDefer` is what keeps the first event of a quiet period immediate: the latency then
        // only batches what follows it, which is the traffic of a turn already reported.
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().onChange()
            },
            &context,
            watchedPaths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            watchedPaths = []
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        watchedPaths = []
    }

    /// The path to watch for a source: itself, or its parent when it does not exist yet.
    ///
    /// A machine that has not run Codex has no `~/.codex/sessions`, and FSEvents resolves a
    /// path when the stream is created — watching the parent is what makes the directory
    /// appearing later an event rather than a reason to restart the app. One level only: above
    /// that lies the home directory, and watching a home directory recursively is not a
    /// fallback, it is a different program.
    static func watchable(_ url: URL) -> URL? {
        // Resolved, because FSEvents reports and matches real paths: a watch registered
        // through a symlink — which is what a temporary directory is on macOS — never fires.
        let resolved = url.resolvingSymlinksInPath()
        if exists(resolved) { return resolved }
        let parent = resolved.deletingLastPathComponent()
        return exists(parent) ? parent : nil
    }

    private static func exists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Holds the callback at a stable address, so the C context pointer has something to point
    /// at that is neither the watcher itself nor a copy of a closure.
    private final class Handler {
        let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }
    }
}
