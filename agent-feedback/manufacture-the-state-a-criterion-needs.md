# A criterion about an empty panel is checked by making the panel empty, not by waiting

When: a phase ends in "click the thing that has no numbers / no click behind it", and this Mac
is in the healthy state where everything reports.
Do: make the state, check it, put it back. A session with no live process — `claude -p "say ok"`
in a throwaway directory with the environment stripped
(`clean-the-environment-before-spawning-a-cli.md`): a non-interactive run writes a transcript
and no record in `~/.claude/sessions`, so the row appears in the panel at once with nothing
behind it. Limits with no numbers — move
`~/Library/Application Support/LLMInformBureau/claude-status` aside; the payloads never age out
on their own, so nothing else makes those numbers go away. Put it back and restart the app
(`pkill -x` then `open`), because the watcher was left holding a directory that vanished. A
missing Accessibility permission costs nothing to arrange: every `Scripts/build-app.sh` breaks
it by itself (`a-rebuilt-ad-hoc-copy-needs-the-grant-reset.md`). Print what the panel is showing
before asking the user to look — a throwaway probe over `UsageReader`
(`probe-a-reader-with-hand-built-modules.md`) tells you whether the state is actually up.
Why: the user is asked to look once, and a question sent while the machine is still healthy
gets "there is nothing to click" back, which reads as the feature not working.

Date: 2026-09-17 · Source: task settings-and-checkup, phase 5 (three dead ends, none of them
present on a Mac where everything reports)
