# Check what is running before explaining what was seen

When: somebody reports how the app behaved — a light blinking wrong, a panel showing something
stale — or you are about to check a visual criterion yourself.
Do: compare when the process started with when the binary was built, before reading any code.
`ps -eo lstart,comm | grep LLMInformBureau` against
`stat -f '%Sm' .build/app/LLMInformBureau.app/Contents/MacOS/LLMInformBureau`. Process older
than the binary → what was seen belongs to earlier code, and explaining it from the current
source is explaining the wrong thing. Rebuild, restart, look again, then investigate.
Why: `Scripts/build-app.sh` replaces the bundle while the running copy keeps its own code, and
nothing in the menu bar says which of the two you are looking at.

Date: 2026-09-16 · Source: user's report (task session-waiting-indicator, phase 2)
