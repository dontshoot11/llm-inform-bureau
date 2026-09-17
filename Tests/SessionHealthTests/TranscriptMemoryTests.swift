import Foundation
import AgentFiles
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
            let lengthBefore = size(of: url, suite)
            let store = ClaudeTranscriptStore(projectsDirectory: directory)
            suite.expectEqual(tokens(store), 100_802, "the first pass")

            writeTranscript(second, to: directory, named: "abc.jsonl", modified: now, suite)
            suite.expectEqual(
                size(of: url, suite), lengthBefore,
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
    }
}

// MARK: Getting at one transcript

/// Where `writeTranscript` put a file: inside the project directory it makes under the root.
private func transcript(in root: URL, named name: String) -> URL {
    root.appendingPathComponent(defaultProjectDirectoryName, isDirectory: true)
        .appendingPathComponent(name)
}

private func size(of url: URL, _ suite: TestSuite) -> Int {
    let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.fileSizeKey])
    guard let size = values?.fileSize else {
        suite.expect(false, "could not size \(url.lastPathComponent)")
        return -1
    }
    return size
}
