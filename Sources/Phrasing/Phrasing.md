# Phrasing

Every English string the widget says about a number, and the rules about what it may claim.

## Why this is its own target

It started inside the app target. A notification, unlike a line in a panel, has to be right
about something a test can check — that it ends with `/context` for a Claude session and
`/status` for a Codex one, that a mark is attributed to whoever drew it, that nothing
anywhere reads as a measurement of how good the answers are. A SwiftPM
executable target cannot be imported, so none of that was reachable from the suite while the
wording lived in the app.

The rules stay where they were: `SessionHealthCore` returns facts and numbers, this target
turns one into a sentence, and the app shows it. A rule never reads English.

## The line the wording must not cross

`AGENTS.md` draws it and the tests enforce it. "Answer quality may degrade past this point" is
a fact about a mark somebody drew. "Quality: 62%" would be a measurement, and there is no
signal for it in anything this app can read — not in the transcripts, not in the rollouts, not
in the statusLine payload. The widget reports that a line has been crossed. It never grades
the session, and the words "health" and "degraded" do not appear in anything it says.

## What a notification looks like

```
Claude context window past 90%
92% full, 920K tokens held. Most of what is in there is history by now, and the more of it
there is, the more it weighs on what the model concludes. A fresh session keeps what still
matters.
/context
```

Two habits that sentence shows. **It says what the number is**, not what will happen because
of it: how full a window is can be read off a file, and how good the next answer will be
cannot. **It offers the one thing the reader can do about it** — the sentence ends where the
reader's options begin, and the command below it is how they look.

The panel says the same thing under the same reading — "/usage for more details" — from the
same two functions, so the two places cannot answer differently.

Last line, alone, is the command — because at the moment of the interruption the user has two
questions, and the second one is "and how do I see the rest". The two services do not share
one: context is `/context` in Claude Code and `/status` in Codex, limits are `/usage` in both.

## Files

| File | Holds |
| --- | --- |
| `AlertPhrasing.swift` | A crossed mark as a notification: title, body, command |
| `Wording.swift` | What a mark is called, what a subagent's row is called, which command shows more of it, and what a service is called — `service` where there is room to say it, `serviceInBar` where the budget is pixels |
| `Briefing.swift` | What the first run says: where every number comes from, and what is not connected |
| `TokenDisplay.swift` | Token counts and percentages, rounded the way the widget says them |
| `TimeDisplay.swift` | Ages, reset times and window lengths |

Tests: `Tests/SessionHealthTests/NotificationTextTests.swift` and `SetupTests.swift`.
