# SessionHealthTests

The test suite for `SessionHealthCore` and `AgentFiles`. Run it with:

```sh
swift run SessionHealthTests
```

Exit code 0 when everything passes, 1 otherwise, with a line per case.

## Why this is not a SwiftPM test target

`swift test` cannot run in this project's toolchain. Both Swift test frameworks live inside
Xcode: with Command Line Tools alone, `import XCTest` and `import Testing` both fail with
*no such module*, which is where this package is built (see the research notes for the
toolchain decision). Adding a test framework as a package dependency was ruled out too — the
app ships with no external dependencies.

So the suite is an executable target with a ~70-line harness in `TestSuite.swift`: named
cases, recorded failures, a summary, an exit code. That is the whole feature list, and it is
enough for rules that are pure functions over value types.

If the project ever gains an Xcode dependency for other reasons, this is worth revisiting —
the cases are plain functions and would port to swift-testing mechanically.

## What is covered

| Suite | Covers |
| --- | --- |
| `ThresholdConfigTests` | The shipped config itself, and every way a file on disk can be broken without taking the app down |
| `ThresholdChoiceTests` | Moving a mark: the arithmetic of the bar (a point on it, the stop against a neighbour, the ends), what a choice is kept as, and that a later release still reaches every mark nobody moved |
| `BudgetRulesTests` | The four marks, each boundary from both sides, both services |
| `AlertMemoryTests` | One mark, one notification — and what makes a scope end |
| `AlertDispatchTests` | What a whole reading has left to say: scopes, `/clear`, a rolled-over limit window, and the backlog found at launch |
| `NotificationTextTests` | What a notification says: the CLI command of its own service at the end, and no claim to have measured quality |
| `LargeTranscriptTests` | A 400 MB transcript read from its end alone, within a time limit that fails if it is not |
| `SourceWatcherTests` | That a file change is reported at all, including a source directory that appears later |
| `SessionActivityTests` | Which sessions count as being worked on right now, and both sides of the edge |
| `ClaudeStatusTests` | Reading the payloads the status line command leaves, and the join between the two Claude sources |
| `ClaudeTranscriptTests` | Reading a session out of a transcript: tokens held, turn growth, sidechains, `/clear` |
| `TranscriptMemoryTests` | What the reader remembers between passes: a file whose stamp has not moved is not opened again — checked by taking its permissions away rather than by counting — and one that grew, got shorter, had its date moved or was replaced by another file under the same name is read afresh. Plus what the memory must not become: a file the walk stopped seeing is forgotten, a file that would not open is not filed as one with nothing to say, and a file somebody else is writing is read neither stale nor torn |
| `SourceMemoryTests` | The same questions for the other sources and for a whole pass: a payload and a rollout that have not moved are not read again, one walk of a tree answers everything asked of it, and an event that changed no file at all opens none |
| `WaitingStateTests` | Whether a session is waiting on its agent: the four moments of a turn, the housekeeping written after an answer, and a response arriving as several entries |
| `AskingStateTests` | The other direction — an agent waiting on the person: what the record of a running process is allowed to override in the transcript's verdict, what a record left behind by a dead or resumed process may not claim, that the fuse never turns a request into a stall, and what a record costs to read twice |
| `AttentionNoticeTests` | Telling the person out loud that an agent is waiting on them: nothing said under the delay, one notification per wait however long it stands, the next wait announced again, a turn that ended announced never, and what the text owes — the project it names and the question cut to one line |
| `SessionRaiseTests` | The road from a row to the window a session runs in: what a live process says about itself and what a pid nothing is using does not, that a pid travels only while the process behind it is the one the record named, that the chain above a process is walked to the top rather than to the first step that will not answer, and how far a click can get in each terminal — the tab, the window titled after the project, or the application — and what the panel says when it got no further than the application, which depends on how this copy is signed |
| `CodexRolloutTests` | Reading limits and sessions out of rollout fixtures, including the shapes that mean "no data" and "source changed", and the request a rollout does not carry |
| `SetupTests` | Which sources read as connected, what the first run says about the ones that do not, and showing that explanation once |
| `StatusLineSlotTests` | `~/.claude/settings.json` edited from Swift: the key set and removed, every other byte of a hand-used file where it was, a command already in the slot saved and put back, the two branches that refuse to write, and taking over from the shell wrapper an earlier release installed |
| `OfflineTests` | That no source file reaches for a network API — the reason the app works with the network off |

## Writing a case

```swift
suite.test("what the rule should do") {
    suite.expectEqual(assessment.level, .degrading, "level")
    suite.expect(assessment.level(of: .windowFill) == nil, "window fill must not be reported")
}
```

- `expect(_:_:)` for a condition, `expectEqual(_:_:_:)` for a comparison,
  `expectClose(_:_:_:)` for percentages. All of them record and continue, so one run reports
  every failure in the case rather than the first.
- Compare optionals with `expect(x == y, …)`; the equality helper is for non-optionals.

A case that works on files has the rest of the harness for it: `withTemporaryDirectory` for a
directory that lives as long as the case, `withoutPermissions` for checking that a file was not
opened rather than assuming it, `facts(of:)` for the three things the reader's memory is keyed
by, and `removeFile` / `moveFile` for the difference between a file rewritten, a file replaced
and a file the walk has stopped finding.

## The rule these cases follow

**No threshold is written as a literal.** Every expected boundary is read out of the loaded
config, because a test that repeats the numbers keeps passing after someone edits the file —
and catching exactly that is why the thresholds live in a file. There is no exception now:
all four marks are config entries.

**Fixtures are trimmed copies of real lines.** The rollout fixtures reproduce shapes found in
`~/.codex/sessions` — including the limit pool whose windows are both null — rather than shapes
that would be convenient to parse. The same holds for the transcript fixtures (sidechain lines,
`tool_result` user lines) and for the statusLine payloads, which follow the documented contract
field for field.

They live in two files: `ClaudeFixtures.swift` for what Claude Code writes — transcript lines
and status line payloads — and `CodexFixtures.swift` for what Codex writes. Deliberately one
copy of each: a subagent's file holds the same lines as a session's, the limits and the session
of a rollout are read out of the same file, and a second set of builders would let the halves of
one reader be tested against two different ideas of what its files look like.

**A case that waits for something waits for the real thing.** The watcher cases block on a
semaphore with a generous timeout instead of sleeping for a fixed while: a loaded machine does
not fail them, and an event that never arrives still does.

**A case about a race asserts what has to hold whatever the timing does.** The transcripts are
written by somebody else while the app reads them, so one case has a thread appending to a file
while passes run against it — and it waits for no particular interleaving. What it asserts is
what must be true of every pass: the number is one that was actually written, it is never less
than an earlier pass gave, the file is never called unreadable, and the pass after the writing
stops says what the file finally says. A case that needed a race to happen would pass on a quiet
machine for the wrong reason; this one only needs passes to happen, and it says so.

**The machine an older release left behind is a fixture, not a memory.** The cases for taking
over from the shell wrapper build that machine on disk — the wrapper's file in the app's own
directory, its path in the slot, the displaced command saved underneath — because the failure
they guard is silent: read as somebody else's command, the wrapper's path would be written over
the person's own saved command and then called by a wrapper that reads the file naming itself.
Nothing on screen would say so.

**The file that belongs to somebody else is checked byte for byte.** `settings.json` is the one
file this project writes that is not its own, and the failure worth catching there is not a
crash but a silent change: a key reordered, a slash escaped, a setting dropped, a command
removed that nobody can get back. So `StatusLineSlotTests` compares the whole file against the
text it should be, rather than parsing it and checking the one key — parsing is exactly what
would not notice the other four.

**A fixture's modification date is part of it.** What the widget shows depends on when a file
was last written, so the fixtures set it explicitly instead of relying on the order they were
created in.
