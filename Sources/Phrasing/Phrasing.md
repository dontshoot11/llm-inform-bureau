# Phrasing

Every string the widget says about a number, in both of the languages it speaks, and the rules
about what either of them may claim.

A string here is a `Phrase`: one value with an English side and a Russian one, so an
untranslated line does not compile rather than reaching a reader as English in the middle of a
Russian window. Which side is showing is the app's to decide (`InterfaceLanguage`) and is
decided where the text is drawn, which is why the language can change while a window is open.

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

## The one notification with no command

An agent waiting on the person is the other thing worth interrupting them for, and it reads
differently on purpose:

```
Claude is waiting on you in llm-inform-bureau
Which approach should I take — the reader, or the join?
```

**The title names the project**, because that is how the person finds the row: the panel lists
sessions by project, and a notification that named only the service would point at the whole
app. **The body is the question**, flattened to one line and cut on a word if it runs long — a
question is written for a terminal and arrives with line breaks in it. **And there is no
command**, for the same reason the others have one: what the reader can do about this is
answer, in a terminal that is already open, and a slash command at the end would send them to
look up a number instead.

## Files

| File | Holds |
| --- | --- |
| `Phrase.swift` | Something the app says, in both languages at once: one value with two sides, and no way to build one without writing both |
| `LanguageInUse.swift` | Which language the app opens in — the choice on disk, and failing that the Mac's own list |
| `AlertPhrasing.swift` | A crossed mark — or an agent waiting on the person — as a notification: title, body, command |
| `Wording.swift` | What a mark is called, what a subagent's row is called, which command shows more of it, what a folded row with no reading yet says, what a service is called — `service` where there is room to say it, `serviceInBar` where the budget is pixels — and what a clickable session row promises, what the panel's dead ends promise instead — a reading with no numbers, a session that cannot be brought up, a click that got partway — plus the line and button shown when the permission for something closer than the application is missing, the name of the button that opens any pane of System Settings, and the sentence an ad-hoc-signed copy adds about a tick that belongs to the version before this one — said in one place because both the panel and the checkup say it |
| `Briefing.swift` | What the settings window says about its marks: what each colour is like to be in, how a scale is worked, what each mark decides, said under every one of them whether the app placed it or the reader did — because that describes the mark and not the number standing on it — and, under that, where the number itself came from: a published date, an admission that nobody measured it, or, for a mark somebody moved, that they chose it, since the reasoning that shipped was about another number — plus each source of readings, as the checkup lists it |
| `CheckupPhrasing.swift` | The other half of that window: every thing the app uses on this Mac as one line — what it is, what the machine answered, what it costs while the answer is no, and the pane of System Settings where that answer is kept; for the two answers macOS gives only on use — controlling a terminal, and the channel a notification goes out over — what the app will ask for and when instead of a tick; and what a click on a session runs on before any permission comes into it, which is a record the CLI writes only while a session is running and Codex never writes at all; plus the labels on the two controls that stand in that list rather than beside it — starting with the Mac, and announcing a crossed mark at all — and what a reader who unticks the second one has to be told went with it, which is nothing |
| `TokenDisplay.swift` | Token counts and percentages, rounded the way the widget says them |
| `TimeDisplay.swift` | Ages, reset times and window lengths — and the one date that is not an age: when the running copy was built |
| `StatusLineText.swift` | The one row the app prints when it holds Claude Code's status line and nothing was there before it |
| `SlotPhrasing.swift` | The button that takes that slot, in the panel, and the one that gives it back, on the checkup line about the slot in the settings window — and what the change to `~/.claude/settings.json` is shown as before either of them is made |

Tests: `Tests/SessionHealthTests/NotificationTextTests.swift`, `SetupTests.swift`,
`CheckupTests.swift`, `NotificationChoiceTests.swift`, `LanguageChoiceTests.swift` and
`StatusLineModeTests.swift`.
