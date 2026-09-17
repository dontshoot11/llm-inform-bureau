# Check what is running before explaining what was seen

When: somebody reports how the app behaved — a light blinking wrong, a panel showing something
stale — or you are about to check a visual criterion yourself.
Do: compare when the process started with when the binary was built, before reading any code.
`ps -eo lstart,comm | grep LLMInformBureau` against
`stat -f '%Sm' .build/app/LLMInformBureau.app/Contents/MacOS/LLMInformBureau`. Process older
than the binary → what was seen belongs to earlier code, and explaining it from the current
source is explaining the wrong thing. Rebuild, restart, look again, then investigate. Restart
means `pkill -x LLMInformBureau` and only then `open`: `open` on a bundle whose copy is already
running just brings that copy forward, so the fresh build never starts and the comparison above
keeps failing for a reason that looks like a mystery.
A complaint about a macOS permission needs the copy's identity too, not only its age:
`codesign -d --requirements -` prints the cdhash the grant is bound to, and the Accessibility
pane shows two copies of the same name as one row — Scripts/Scripts.md has the measurement.
Why: `Scripts/build-app.sh` replaces the bundle while the running copy keeps its own code, and
nothing in the menu bar says which of the two you are looking at.

Date: 2026-09-17 · Source: user's reports (task session-waiting-indicator, phases 2 and 3 —
the same trap twice: a screenshot of lights not blinking came from a process two builds old);
task session-needs-attention, phase 1 (`open` after a rebuild left the older process
running); a permission that "is there" and keeps being asked for, because the copy it was
given to is not the copy running
