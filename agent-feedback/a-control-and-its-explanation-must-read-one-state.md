# A control and the line explaining it must read the same state

When: writing a row of the settings window where anything depends on the reader's own choice —
a button that appears once a mark is moved, a line saying whose the number now is.
Do: take both from this window's `@State` (`chosen`, `scales`, `minutes`), not from the config
the window was built with, and list the marks from `marks.shipped` so the words under them
cannot be somebody's old choice either. `WelcomeView` is built once per run of the app: the
config in hand is what the disk said when the window opened, and a mark moved a minute ago
lives only in the state.
Why: a control and its explanation reading different sources disagree silently, and only for
the person who has just changed something — the button appears, the line under it does not, and
nothing in this test suite looks at a view.

Date: 2026-09-17 · Source: task settings-and-checkup, fix after verification (commit 4d41d7b),
found from a screenshot the user sent
