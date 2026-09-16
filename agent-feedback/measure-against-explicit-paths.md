# Measuring this app needs explicit paths, not a substituted HOME

When: measuring or reproducing the app's behaviour against a controlled set of files — idle
cost, a reader's verdict, anything where the sources must be something other than the real ones.
Do: give the paths explicitly — `ClaudeTranscriptStore(projectsDirectory:)`, `UsageModel(paths:)`,
`LLM_INFORM_BUREAU_THRESHOLDS` for the config. Never launch the app with `HOME` set elsewhere and
call the result controlled.
Why: `FileManager.homeDirectoryForCurrentUser` and `NSHomeDirectory()` ignore `$HOME` here
(verified 2026-09-16), so `SourceWatcher.defaultPaths` and the support directory still resolve to
the real home. The measurement looks isolated, reads the machine's live sessions, and every number
out of it is wrong in a way nothing about it looks wrong.

Date: 2026-09-16 · Source: task session-waiting-indicator, phase 3 (two idle-cost measurements
thrown away)
