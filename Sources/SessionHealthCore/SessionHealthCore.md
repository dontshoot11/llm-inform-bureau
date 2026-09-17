# SessionHealthCore

The rules that turn what was read off disk into what the widget says. No file watching, no
user interface, no knowledge of where session data lives — just: given these numbers, is
anything worth saying, and has it already been said?

## Why this is a module of its own

These rules are the part of the app that has to be right, and the only part that can be
checked without a running Mac session. Keeping them free of Claude Code and Codex file
formats means the awkward cases — a session in a window nobody knows the size of, a limit
window that has rolled over, a config file someone broke — are ordinary test cases rather
than fixtures.

## What it measures

Four marks, all of them in `Resources/thresholds.json`, none of them in the code. The file
ships inside the app and is nobody's to edit — but the marks are not the app's last word: both
scales and the three marks that are one number of minutes are moved in the settings window
behind the gear, and what is kept is the choice rather than a copy of the file
(`ThresholdChoices`, and "Marks the reader moved" below).

| Mark | Applies to | What it means | What the user can do |
| --- | --- | --- | --- |
| Window fill 40 / 60 / 90% | Both services | That share of the context window is gone | Wrap up or start a fresh session |
| Limit usage 40 / 60 / 90% | Both services | That share of a subscription window is spent | Plan the rest of the window |
| Turn growth | Both services | One turn cost an unusual amount of window | Know what it was |
| A limit window about to reset | Both services | Its marks stay quiet: it comes back on its own | Nothing — that is the point |

The two scales are deliberately the same numbers. A colour that means one thing under the
limits and another under the context is a colour nobody can read at a glance, which is the
only thing a menu bar is for.

Every mark is a share of a window, so a session whose window size nobody reported has nothing
to place: it is listed with its tokens and its light says "no reading" rather than green. The
one absolute mark this module used to carry — Anthropic's 150K compaction default — is gone;
`Thresholds.md` says why, and it is not because the number moved.

A fifth number in the same file is not a mark at all: `sessions.active_within_minutes` decides
what the widget *shows* rather than what it warns about. It lives there for the same reason —
it was measured, it will need correcting, and a number in the code cannot be corrected without
a rebuild. `SessionActivity` is the rule that applies it.

**Nothing here claims to measure answer quality.** The rules say "you are past a line the
vendor draws", never "your session has degraded" — there is no signal for the latter in any
data this app can read.

## Subagents are consumers of a window, and silent ones

A Claude session can start subagents, and each of them fills a context window of its own. They
are read as ordinary snapshots — same fields, same marks, same scale — carrying a
`SubagentOrigin` that says which session started them and what they were asked to do.

Two things they are not allowed to do, both for the same reason: an agent lives for minutes and
ends by itself, so a mark it crosses is worth looking at and never worth being interrupted by.

- **No notification, on any mark.** `AlertDispatch` drops their alerts. The rule is in the
  dispatcher rather than in its caller so that it holds for every caller.
- **No colour in the menu bar.** `BudgetRules.serviceContextLevel` is what a service's light is
  decided from, and it leaves agents out — a red dot that no notification ever explains is a
  riddle, not a warning.

The size of their window is inherited, never guessed: nothing an agent writes names it, and the
variant of a model with the larger window is written exactly like the ordinary one. An agent
given a model of its own therefore shows tokens and no percentage, like any session whose
window nobody reported. `SubagentOrigin.inheritsParentWindow` is that decision; `AgentFiles.md`
has what it is read from.

## Marks the reader moved

The marks that ship are placed for everybody, and the person reading them is allowed to
disagree. `MarkScale` is what a scale becomes when it can be moved: three marks that stay in
order, inside 0-100 and never on top of one another, with the arithmetic of the bar in the
window — where a point along it falls, where a mark may go, what an arrow key does — under
tests, because a mark that slips past its neighbour leaves three colours in no order and a
widget that means nothing. The config file is read by the same rule, so a scale from a file and
a scale from a person are held to one standard rather than two.

`MinuteMark` is the same idea for a mark that is one number rather than a range: whole minutes,
at least one and at most twelve hours. A field that accepted nought would silence a mark, and a
record of it read back on the next launch would be refused — one rule in one place, met by the
window and by the file alike.

`ThresholdChoices` is what is kept: which mark was moved and where to, in
`chosen-thresholds.json` beside the app's other files, and nothing else. Not a copy of the
config with one number changed — that would quietly freeze every later release at the version
somebody edited once. `applied(to:)` is where a choice meets the marks that shipped, and where a
moved mark loses its rationale and its provenance: the sentence under it was written about a
different number. `isChosen` is what is left — the flag the window turns into a "Reset to
default" button beside that mark and into no explanation at all under it.

## What this Mac has given the app

The app depends on things it did not bring with it: a status line slot, a permission, a source
that has written something. Every one of them fails quietly — a click raises the wrong window,
a notification never comes, "Claude" stands with an em dash — and none of that looks like a
missing permission. It looks like a broken widget. `CheckupState` is the list, and the rules in
it are about what may be claimed:

- A tick only for what is really there.
- A **question mark** for what macOS will not answer until the app tries. Automation and the
  notification centre are both like this, and a tick invented for either would be the app's
  guess wearing the system's authority.
- A **plain note** for a line that states a fact rather than reporting a permission: which copy
  is running, and the login checkbox, which is its own answer.
- Only a `missing` line unfolds the list. The two that state a fact never do — a window that
  opened a list of eight to show a path is asking for attention it has no use for.

Reading any of it is the app's job, not this module's, and the rule there is that **opening the
window must not raise a permission dialog**: a dialog is a question, and the moment to ask one
is when somebody's own click needs the answer.

## Marks are exclusive

A session sitting exactly on 50% has not crossed it. Every rule follows this, so a test can
name a boundary and check both sides of it.

When several marks are behind us, every one of them is reported, lower first: crossing 50%
and crossing 75% are two different things to be told about, and `AlertMemory` is what keeps
the first from being repeated once the second arrives.

## One mark, one notification

The rules run on every file change and report everything currently crossed — they hold no
state at all. `AlertMemory` turns that stream into notifications, remembering what has
already been delivered inside a *scope*:

- a **session**, identified by its session id. `/clear` starts a new session file with a new
  id, so the memory resets by itself and the same mark may fire again in the new session.
- a **limit window**, identified by the moment it resets. Once it rolls over, its usage is a
  new story and may be reported again.
- one **wait on the person**, identified by the moment the agent stopped and asked. The person
  answers, the agent asks again, and the new wait is a scope of its own — so it is announced
  again without anything here having to notice the answer.

There is no exception to that rule. There used to be one — a mark for a single turn that
grew the context a lot, an event rather than a line that stays crossed — and it was removed on
2026-09-16 for the reason a mark is ever removed: in agent work a large read is most turns, so
it spoke on nearly all of them. How much the last turn added is still in the panel, under the
session it belongs to. A reading nobody is interrupted by is worth more than a mark nobody
reads.

## The one alert that is not a mark

An agent that has asked the person something and is standing still is not a number crossing a
line, and it is announced through the same dispatcher all the same (`BudgetAlert.Kind`
`.attention`). What makes a crossed mark bearable is exactly what a request needs: said once,
never on behalf of a subagent, and never about the backlog the app found when it started. A
second road to the same notification centre would have to grow all three again.

Two things are its own. The delay (`sessions.attention_notice_after_minutes`) is not a scope
and not a memory: the alert is simply not made while the request is younger than the mark, so a
question answered at the keyboard never reaches a notification instead of being announced and
taken back. And what was asked rides beside the kind rather than inside it — the kind is the
identity the memory remembers, and a question rephrased mid-wait must not read as a second
request.

The pause sign in the bar does not wait for any of this. It is drawn from `ReplyWait.asking`
the moment the request appears; the delay belongs to the interruption alone.

The sign is also the whole of what the bar says about it: a question and a permission prompt
are one shape, because the bar answers "who is being waited on" and both answer "you". The
difference between them (`Asking`) is spent on the notification, which has a sentence and owes
the person the errand they are being pulled out of another window for — a question to read, or
a yes and a no to give. A request the record did not name keeps the wording both had before
they could be told apart.

## Which mark made the bar that colour

An assessment carries `levelSource` beside `level`: the mark that set the colour, not merely
the last one found. Several readings compete for one light — two limit windows, two running
sessions — and the panel has to name the one the colour came from. It is a
`BudgetAlert.Kind`, not a sentence: the English lives in the app, so these rules stay testable
without reading it.

## Which sessions are shown

A machine that has run these CLIs for a while holds hundreds of session files, and the widget
has room for a handful of lines. `SessionActivity` draws the line at the configured window
since the session file was last written to.

The cut is not a matter of taste. Counting how long ago each session file was last written
gave a few under two hours and several hundred over a day, with almost nothing in between, so
any cut inside that gap separates exactly the same sessions. Unlike the budget marks, this one
is inclusive: those ask whether something has gone past a line, this one asks whether a session
is still within reach, and exactly at the edge it is.

## Unknown is not zero

`windowFillPercent == nil` means the window size is unknown — a Claude transcript does not
carry it — and the interface shows absolute tokens and no percentage. `worstUsedPercent ==
nil` means the service has not reported any limits, and the interface says so instead of
showing 0%.

## Using it

```swift
let load = ThresholdConfigLoader.load()
let rules = BudgetRules(config: load.config)
var memory = AlertMemory()

let assessment = rules.assess(
    SessionSnapshot(
        sessionID: "01a0967f",
        service: .codex,
        contextTokens: 193_454,
        contextWindowTokens: 258_400,
        turnGrowthTokens: 31_000
    )
)

assessment.level              // .elevated — past 60% of the window, not yet past 90%
assessment.windowFillPercent  // 74.9, or nil when the window size is unknown
let toNotify = memory.undelivered(assessment.alerts, scope: AlertScope.session(assessment.sessionID))
```

An app watching both services at once does not scope alert by alert — `AlertDispatch` does that
over a whole reading, and it is what the menu bar app uses:

```swift
var dispatch = AlertDispatch()
let toNotify = dispatch.pending(limits: limitAssessments, sessions: contextAssessments)
```

Nothing in the loader throws: a broken config file degrades to the values below it and
`load.problems` carries what went wrong, in words the dropdown can show.

## Files

| File | Holds |
| --- | --- |
| `AgentService.swift` | The two services, and why they are not symmetric |
| `SessionActivity.swift` | Which sessions count as the ones being worked on right now |
| `SessionSnapshot.swift` | The input: a session's tokens, window, last turn and the model that answered it, who it is waiting on (nobody, its agent, its agent for a long time, or the person it has asked something), the live process it runs in — and, for a subagent, where it came from |
| `LimitsSnapshot.swift` | The input: one service's limit windows and when they were reported |
| `BudgetAlert.swift` | What a crossed mark is — and a request to the person, which is not one — plus the identity the memory remembers |
| `AlertMemory.swift` | One mark, one notification — scopes (a session, a limit window, one wait) and what ends them |
| `AlertDispatch.swift` | What is news: scoping every alert of a whole reading, and staying quiet about the backlog found at launch |
| `BudgetRules.swift` | The rules themselves, and the two assessments they return |
| `ThresholdConfig.swift` | The marks, and the built-in copy of them |
| `ThresholdConfigLoader.swift` | Reading the marks the app ships with, the choices over them, and the built-in values under both |
| `MarkScale.swift` | A scale somebody can move: where a mark sits on the bar, how far it may go, and what a drag or an arrow key comes to |
| `MinuteMark.swift` | The rule for a mark that is one number of minutes: how small and how large it may be, and what a typed number becomes |
| `ThresholdChoices.swift` | The marks the reader moved — what is kept of them, where, and what they become when the app's own marks are read |
| `SetupState.swift` | Which sources have written anything on this machine |
| `CheckupState.swift` | Everything the app runs on that this Mac had to give it — the sources, the slot, the permissions, which copy is running — what each of those answers means, and the panes of System Settings where the answers are kept |
| `StatusLineSlotState.swift` | Whose Claude Code's one status line slot is, and what taking it or giving it back would change |
| `TerminalRaise.swift` | How far a click on a session's row can get — the tab, the window titled after the project, or the application — the AppleScript that asks for a tab, and which permission each answer costs |
| `SupportDirectory.swift` | The directory this app keeps its own files in |
| `Resources/thresholds.json` | The marks themselves — see `Thresholds.md` |

Tests: `Tests/SessionHealthTests`, run with `swift run SessionHealthTests`.
