# A rebuilt ad-hoc copy is a new app to TCC, and the old tick grants it nothing

When: checking anything that depends on a permission given by hand — Accessibility, Automation
— after a rebuild, or when the user says the permission is given and the app behaves as if it
were not.
Do: do not send anybody to untick and tick the row in System Settings; the entry remembers the
binary it was given for, and re-ticking it re-grants the copy that is gone. Wipe the entry —
`tccutil reset Accessibility com.artjemnikitin.llm-inform-bureau` — and have the user add the
copy that is actually running by its path (`+` in the pane, ⌘⇧G, the bundle path from
`ps`). Say which copy that is before asking for anything.
Why: with an ad-hoc signature the app has no identity beyond the hash of its binary, so every
build is a different app, and the pane shows one name for all of them. The app's own checkup
says this in a sentence (`Wording.tickFromAnEarlierBuild`), and the sentence is not enough when
the stale entry points somewhere else entirely.

Date: 2026-09-17 · Source: task settings-and-checkup, phase 4 (the live check of a permission
turning into a tick)
