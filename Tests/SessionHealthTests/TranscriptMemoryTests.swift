import Foundation
import AgentFiles
import Phrasing
import SessionHealthCore

/// What the reader remembers between passes, and what makes it forget.
///
/// A turn is dozens of file system events, and every one of them used to re-read every active
/// transcript from the beginning. These cases are about the other half of that: a file that has
/// nothing new to say is not opened, and a file that does have something new is read whichever
/// way it changed.
///
/// How "not opened" is checked rather than assumed — the permissions trick and the control that
/// keeps it honest — is with `withoutPermissions`.
func runTranscriptMemoryTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The tokens held by the one session in a directory, or nil when there is no row.
    func tokens(_ store: ClaudeTranscriptStore) -> Int? {
        store.activeSessions(activity: activity, now: now).value?.first?.contextTokens
    }

    withTemporaryDirectory(suite, named: "transcript-memory") { root in
        suite.test("a transcript that has not changed is not opened again") {
            let directory = makeProjectDirectory(root, "unchanged", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 100_000)],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            suite.expectEqual(tokens(store), 100_802, "the first pass reads the file")

            withoutPermissions(transcript(in: directory, named: "abc.jsonl"), suite) {
                suite.expectEqual(tokens(store), 100_802, "the second pass answers without opening it")
                suite.expectEqual(
                    tokens(ClaudeTranscriptStore(projectsDirectory: directory)), nil,
                    "control: a reader with no memory of it gets nothing out of that file"
                )
            }
        }

        suite.test("a transcript that grew is read again") {
            let directory = makeProjectDirectory(root, "grew", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 100_000)],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            suite.expectEqual(tokens(store), 100_802, "the first pass")

            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 100_000),
                    userPrompt("and again"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 150_000)
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )
            suite.expectEqual(tokens(store), 150_802, "the new last answer, not the remembered one")
        }

        // The size is the same on purpose: a turn that ends where the last one did — the same
        // count of digits in the same fields — has to be noticed by the date alone.
        suite.test("a transcript whose date moved is read again, even at the same size") {
            let directory = makeProjectDirectory(root, "date-moved", suite)
            let first = [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 100_000)]
            let second = [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 200_000)]
            writeTranscript(first, to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite)
            let url = transcript(in: directory, named: "abc.jsonl")
            let lengthBefore = facts(of: url).size
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            suite.expectEqual(tokens(store), 100_802, "the first pass")

            writeTranscript(second, to: directory, named: "abc.jsonl", modified: now, suite)
            suite.expectEqual(
                facts(of: url).size, lengthBefore,
                "the case only means what it says while the two states are the same length"
            )
            suite.expectEqual(tokens(store), 200_802, "the date moving is enough to read it again")
        }

        // Nothing observed on this machine shortens a transcript — `/clear` starts a new file —
        // but the rule must not rest on that: the memory is keyed by what the file looks like,
        // and a file that got smaller does not look the same.
        suite.test("a transcript that got shorter is read again") {
            let directory = makeProjectDirectory(root, "shorter", suite)
            writeTranscript(
                [
                    userPrompt("start"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 100_000),
                    userPrompt("and again"),
                    assistant(input: 2, cacheCreation: 800, cacheRead: 150_000)
                ],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            suite.expectEqual(tokens(store), 150_802, "the first pass")

            writeTranscript(
                [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 90_000)],
                to: directory, named: "abc.jsonl", modified: now, suite
            )
            suite.expectEqual(tokens(store), 90_802, "what the shorter file says, not what the longer one said")
        }

        // The head of a transcript is a quarter of a megabyte and a JSON parse per line, for a
        // `cwd` that cannot change: the project is the *first* one in the file. So it is
        // remembered by the file's identity alone — and a file that grew is proof of that, since
        // a re-read of the head would answer with the directory written into it since.
        suite.test("the directory a session started in is remembered, not read again") {
            let directory = makeProjectDirectory(root, "home", suite)
            writeTranscript(
                [
                    assistant(input: 2, cacheCreation: 0, cacheRead: 100_000, cwd: workingDirectory),
                    userPrompt("start")
                ],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            let first = store.activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(first?.project, "llm-inform-bureau", "the project of the first pass")

            // Rewritten in place, so the file keeps its identifier: the same file, saying
            // something else about where it started.
            writeTranscript(
                [
                    assistant(input: 2, cacheCreation: 0, cacheRead: 100_000, cwd: "/Users/nobody/somewhere/else"),
                    userPrompt("start"),
                    assistant(input: 2, cacheCreation: 0, cacheRead: 120_000, cwd: "/Users/nobody/somewhere/else")
                ],
                to: directory, named: "abc.jsonl", modified: now, suite
            )
            let second = store.activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(second?.contextTokens, 120_002, "the tail is read again")
            suite.expectEqual(second?.project, "llm-inform-bureau", "the head is not")
        }

        // Not rewritten in place but replaced: the name is the same and the file behind it is
        // another one. Same size and same date on purpose — the identifier is then the only
        // thing left to notice it by, and without it the new file would be answered for out of
        // the old one's reading, tail and head alike.
        suite.test("a transcript replaced by another file under the same name is read again") {
            let directory = makeProjectDirectory(root, "replaced", suite)
            let written = now.addingTimeInterval(-60)
            writeTranscript(
                [
                    assistant(input: 2, cacheCreation: 0, cacheRead: 100_000, cwd: "/Users/nobody/projects/one"),
                    userPrompt("start")
                ],
                to: directory, named: "abc.jsonl", modified: written, suite
            )
            let url = transcript(in: directory, named: "abc.jsonl")
            let before = facts(of: url)
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            let first = store.activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(first?.contextTokens, 100_002, "the first pass")
            suite.expectEqual(first?.project, "one", "and where that session started")

            removeFile(url, suite)
            writeTranscript(
                [
                    assistant(input: 2, cacheCreation: 0, cacheRead: 200_000, cwd: "/Users/nobody/projects/two"),
                    userPrompt("start")
                ],
                to: directory, named: "abc.jsonl", modified: written, suite
            )
            let after = facts(of: url)
            suite.expectEqual(after.size, before.size, "the case only means what it says at the same size")
            suite.expectEqual(after.modified, before.modified, "and at the same date")
            suite.expect(
                after.identity != nil && after.identity != before.identity,
                "and only while the volume gives the new file an identifier of its own"
            )

            let second = store.activeSessions(activity: activity, now: now).value?.first
            suite.expectEqual(second?.contextTokens, 200_002, "what the new file says, not what the old one said")
            suite.expectEqual(second?.project, "two", "and where the new file's session started")
        }

        // What bounds the memory is the walk, and nothing else: a file the walk stopped finding
        // is dropped at the end of that pass. Checked by taking the file out of the tree and
        // putting it back untouched — a move leaves size, date and identifier exactly as they
        // were, so a record that had survived would answer for it, and coming back empty-handed
        // is the only thing not having one can look like.
        suite.test("a transcript the walk stopped seeing is forgotten, not kept for ever") {
            let directory = makeProjectDirectory(root, "forgotten", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 2, cacheCreation: 800, cacheRead: 100_000)],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-60), suite
            )
            let url = transcript(in: directory, named: "abc.jsonl")
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            suite.expectEqual(tokens(store), 100_802, "the first pass reads the file")

            let before = facts(of: url)
            let elsewhere = makeDirectory(root, "forgotten-elsewhere", suite)
                .appendingPathComponent("abc.jsonl")
            moveFile(url, to: elsewhere, suite)
            suite.expectEqual(tokens(store), nil, "a pass with nothing in the tree")
            moveFile(elsewhere, to: url, suite)
            suite.expectEqual(facts(of: url), before, "the file came back exactly as it left")

            withoutPermissions(url, suite) {
                suite.expectEqual(tokens(store), nil, "and nothing remembered answers for it")
            }
            suite.expectEqual(tokens(store), 100_802, "control: with its permissions back it reads again")
        }

        // Somebody else is writing the file the pass is reading — the ordinary case, not an edge
        // of one. Nothing here waits for a particular interleaving: hundreds of passes run
        // against a transcript being appended to, and what has to hold whatever the timing does
        // is asserted. Every answer is a number that was actually written; none is smaller than
        // an earlier pass had; none is a failure to read a file that is there. Then the writing
        // stops and the next pass says what the file finally says — a reading filed under a
        // stamp newer than the bytes it came from would be stuck at what it saw instead.
        suite.test("a transcript written while the pass reads it is never stale and never broken") {
            let directory = makeProjectDirectory(root, "mid-write", suite)
            let turns = 200
            writeTranscript(
                [userPrompt("start", at: Date())],
                to: directory, named: "abc.jsonl", modified: Date(), suite
            )
            let store = ClaudeTranscriptStore(projectsDirectory: directory)

            // The clock is the real one here, not the fixture's: the writer stamps the file as
            // it goes, and the activity rule reads those stamps against now.
            func held() -> SessionsReading {
                store.activeSessions(activity: activity, now: Date())
            }

            let writer = TranscriptWriter(appendingTo: transcript(in: directory, named: "abc.jsonl"), turns: turns)
            writer.start()

            var passes = 0
            var sightings = 0
            var highest = 0
            var unreadable: Phrase?
            var nobodyWrote: Int?
            var wentBackwards: Int?
            while !writer.isFinished {
                passes += 1
                switch held() {
                case .unavailable(let why): unreadable = why
                case .noData: continue
                case .value(let sessions):
                    guard let tokens = sessions.first?.contextTokens else { continue }
                    sightings += 1
                    if (tokens - TranscriptWriter.firstTokens) % TranscriptWriter.step != 0
                        || tokens > TranscriptWriter.tokens(afterTurn: turns) {
                        nobodyWrote = tokens
                    }
                    if tokens < highest { wentBackwards = tokens }
                    highest = max(highest, tokens)
                }
            }

            suite.expect(writer.trouble == nil, writer.trouble ?? "")
            suite.expect(passes > 5, "the case says nothing without passes to spare: \(passes)")
            suite.expect(sightings > 0, "not one pass saw the session while the file was being written")
            suite.expectEqual(unreadable, nil, "a pass called the transcript unreadable")
            suite.expectEqual(nobodyWrote, nil, "a pass answered with a number nobody wrote")
            suite.expectEqual(wentBackwards, nil, "a pass answered with less than an earlier one had")
            suite.expectEqual(
                held().value?.first?.contextTokens, TranscriptWriter.tokens(afterTurn: turns),
                "with the writing over, what the file finally says"
            )
        }
    }
}

// MARK: Somebody else writing the file

/// A transcript being appended to while the reader is inside it.
///
/// Each turn lands its answer half a line at a time on purpose: what a reader catches a writer
/// at is a line that is not finished, and the half of it already on disk is JSON only by
/// accident. Every turn reports ten tokens more than the one before, so the number a pass comes
/// back with says which state of the file that pass saw.
final class TranscriptWriter: @unchecked Sendable {
    /// What the first turn's answer reports, and what each turn after it adds.
    static let firstTokens = 100_012
    static let step = 10

    static func tokens(afterTurn turn: Int) -> Int { firstTokens + (turn - 1) * step }

    private let url: URL
    private let turns: Int
    private let lock = NSLock()
    private var done = false
    private var problem: String?

    init(appendingTo url: URL, turns: Int) {
        self.url = url
        self.turns = turns
    }

    /// Whether the last turn has landed. Once it has, the file stands still, and what the next
    /// pass says is what the file finally says.
    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    /// What went wrong in the writing, if anything did — asked once the writing is over, so
    /// that a case does not pass because its file was never written.
    var trouble: String? {
        lock.lock()
        defer { lock.unlock() }
        return problem
    }

    func start() {
        DispatchQueue.global().async {
            self.append()
            self.lock.lock()
            self.done = true
            self.lock.unlock()
        }
    }

    private func append() {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            lock.lock()
            problem = "could not open \(url.lastPathComponent) to write"
            lock.unlock()
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        for turn in 1...turns {
            let moment = Date()
            let answer = assistant(
                input: 2, cacheCreation: 0, cacheRead: Self.tokens(afterTurn: turn) - 2, at: moment
            ) + "\n"
            let half = answer.index(answer.startIndex, offsetBy: answer.count / 2)
            handle.write(Data(String(answer[..<half]).utf8))
            usleep(300)
            handle.write(Data(String(answer[half...]).utf8))
            handle.write(Data((userPrompt("turn \(turn)", at: moment) + "\n").utf8))
            handle.write(Data((filler(padding: 2_000) + "\n").utf8))
        }
    }
}

// MARK: Getting at one transcript

/// Where `writeTranscript` put a file: inside the project directory it makes under the root.
private func transcript(in root: URL, named name: String) -> URL {
    root.appendingPathComponent(defaultProjectDirectoryName, isDirectory: true)
        .appendingPathComponent(name)
}
