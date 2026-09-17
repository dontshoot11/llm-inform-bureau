# Running a reader against live files needs modules built by hand

When: checking what a reader makes of the real `~/.claude/projects` or `~/.codex/sessions` —
the live runs every phase of this app ends with.
Do: build the libraries yourself rather than reaching for what `swift build` left behind.
`swiftc -emit-module -emit-library -static -module-name SessionHealthCore` over
`Sources/SessionHealthCore/*.swift` **minus `ThresholdConfigLoader.swift`**, the same for
`AgentFiles` with `-I` pointing at the first, then link the probe against both. Take the
thresholds from `ThresholdConfig.builtIn` — a test keeps it equal to the shipped file — and
give the sources explicit paths. Run the recipe as a `sh` script, never pasted into the shell
an agent runs commands through: that one is zsh, which does not split an unquoted `$core` into
words, and `swiftc` is handed one "file name" made of every path and a newline between each.
Why: the package builds executables, so `.build/debug` holds no `libAgentFiles.a` to link
against, and `ThresholdConfigLoader` reaches for `Bundle.module`, which only exists inside a
SwiftPM build. Compiling the sources into one module instead fails on their own
`import SessionHealthCore`.

Date: 2026-09-17 · Source: task session-waiting-indicator, phase 5 (three failed attempts at
linking a probe before the live Codex runs); task refresh-cost, phase 2 (the same recipe run
through zsh: `error opening input file … (File name too long)`)
