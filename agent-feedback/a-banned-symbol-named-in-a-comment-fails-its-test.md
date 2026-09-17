# A banned symbol named in a comment fails the test that bans it

When: you are writing a doc comment or a code comment that wants to name the very API a
structural test forbids — the network APIs `OfflineTests` greps for, the prompting form of the
accessibility check `CheckupTests` greps for, and whatever is added to that family next.
Do: describe it instead of spelling it. "Its sibling, the one that takes a prompt option" rather
than the identifier. These tests read every `.swift` file under `Sources/` as text, and text is
all they read: a call and a mention in a comment look the same to them.
Why: the failure reads as a real violation and sends you looking for a call that is not there.
The tests are worth more than the convenience of naming a symbol — they are the only reason
"it works with the network off" and "opening the window asks the machine nothing" can be
claimed at all.

Date: 2026-09-17 · Source: task settings-and-checkup, phase 3 — a comment saying which call
raises the dialog failed the test holding that call to one file
