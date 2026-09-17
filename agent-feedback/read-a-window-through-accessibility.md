# Text in a window is read through System Events, not photographed

When: a criterion is about the *words* in a window of the running app — which language it is
in, what a line says, whether a control appeared — and `screencapture` is denied here.
Do: read the window's own tree.
`osascript -e 'tell application "System Events" to tell process "LLMInformBureau" to get
entire contents of window 1'` lists every element with its text; `get value of static texts 1
thru N of scroll area 1 of group 1 of window 1` reads them, `get name of window 1` reads the
AppKit title, and `click` on an element works the control for real. Needs no permission
dialog once the shell running it is allowed in Accessibility, and nothing about it is a
dev-only path: it is the shipped bundle being read.
What SwiftUI hands over: a `Text` is a static text with its value; a segmented `Picker` is a
radio group whose buttons have no title but whose `value` is 0/1, so selection is read by
index; a `.buttonStyle(.link)` button is a bare `UI element` with description `link` — its
presence or absence is the evidence that a conditional control is there.
What it does not hand over: the words inside a `Button` whose label is a whole layout. The
panel's session row and its folding sections come back as a leaf `AXButton` with no title and
no children, and only `help` can be read off them. So a criterion about the words in such a
row is confirmed by the `help` beside it plus the identical code path proved elsewhere in the
same window — and, for the words themselves and for whether anything is cut off, by the user's
eyes (`AskUserQuestion` while the state is up).
Why: it is stronger evidence than a photograph and it is available — the shape rules still
hold for a badge on the menu bar, which has no text to read
(`no-screenshots-look-at-the-shape-instead.md`).

Date: 2026-09-18 · Source: task app-release, phase 1 (interface language on the running
build); phase 3 (a session row and a folding section read as leaf buttons)
