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
| `BudgetRulesTests` | The four marks, each boundary from both sides, both services |
| `AlertMemoryTests` | One mark, one notification — and what makes a scope end |
| `AlertDispatchTests` | What a whole reading has left to say: scopes, `/clear`, a rolled-over limit window, and the backlog found at launch |
| `NotificationTextTests` | What a notification says: the CLI command of its own service at the end, and no claim to have measured quality |
| `LargeTranscriptTests` | A 400 MB transcript read from its end alone, within a time limit that fails if it is not |
| `SourceWatcherTests` | That a file change is reported at all, including a source directory that appears later |
| `SessionActivityTests` | Which sessions count as being worked on right now, and both sides of the edge |
| `ClaudeStatusTests` | Reading the statusLine wrapper's payloads, and the join between the two Claude sources |
| `ClaudeTranscriptTests` | Reading a session out of a transcript: tokens held, turn growth, sidechains, `/clear` |
| `CodexRolloutTests` | Reading limits and sessions out of rollout fixtures, including the shapes that mean "no data" and "source changed" |
| `SetupTests` | Which sources read as connected, what the first run says about the ones that do not, and showing that explanation once |
| `StatuslineInstallerTests` | What `Scripts/install-statusline.sh` does to the user's `settings.json`: the slot filled and emptied, a command that was already there surviving both, and every branch that must not write |
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

## The rule these cases follow

**No threshold is written as a literal.** Every expected boundary is read out of the loaded
config, because a test that repeats the numbers keeps passing after someone edits the file —
and catching exactly that is why the thresholds live in a file. There is no exception now:
all four marks are config entries.

**Fixtures are trimmed copies of real lines.** The rollout fixtures in `CodexRolloutTests`
reproduce shapes found in `~/.codex/sessions` — including the limit pool whose windows are
both null — rather than shapes that would be convenient to parse. The same holds for the
transcript fixtures (sidechain lines, `tool_result` user lines) and for the statusLine
payloads, which follow the documented contract field for field.

The transcript fixtures are in `ClaudeFixtures.swift`, shared by the session cases and the
subagent ones. Deliberately one copy: a subagent's file holds the same lines as a session's,
and two sets of builders would let the two halves of one reader be tested against two
different ideas of what a transcript looks like.

**A case that waits for something waits for the real thing.** The watcher cases block on a
semaphore with a generous timeout instead of sleeping for a fixed while: a loaded machine does
not fail them, and an event that never arrives still does.

**A shell script is tested by running it.** `StatuslineInstallerTests` starts the real
`Scripts/install-statusline.sh` against a throwaway `HOME` rather than re-implementing its
branching in Swift. It is the only file this project writes that belongs to somebody else, and
the failure worth catching is not a crash but a silent removal — the wrapper's `--uninstall`
used to take the user's own statusLine command away on a second run. A second test runner just
for shell was not worth having: this suite already is the one runner, and `Process` starts a
script as well as anything else would.

**A fixture's modification date is part of it.** What the widget shows depends on when a file
was last written, so the fixtures set it explicitly instead of relying on the order they were
created in.
