# LLMInformBureau

The menu bar app: four lights in the bar, a panel behind them, and one window it opens once.

The same binary is also something else. Run with `--status-line`, it is the command Claude Code
calls after every answer — the only way the subscription limits and the size of the context
window can be seen on this machine at all. `Entry.swift` is the fork between the two, and it
comes before anything AppKit does: in that mode there is no bar, no panel and no event loop,
just a program that reads stdin, prints a row and exits. What it does there is `StatusLineMode`
in `AgentFiles`; the row it prints is `StatusLineText` in `Phrasing`.

**One menu bar item, always.** Before the app starts, `Entry.endOtherCopies()` asks any other
running copy of this bundle to quit, and the copy that started last is the one that stays. Two
copies are easy to end up with — a build beside an installed bundle, an app dragged somewhere
new, a login item starting one while another is up — and they are not a cosmetic problem: two
identical lights in the bar, every notification said twice, and the status line slot offered
from two panels that disagree about who holds it, with nothing on screen saying which copy is
which. The last one launched wins because launching an app is how a person asks for it. Only
the menu bar app does this; the status line command may run several at once and exits on its
own.

## Build and run

```sh
Scripts/build-app.sh --run  # rebuild the bundle and restart it, while working on it
Scripts/build-dmg.sh        # the image that is handed out
```

See `Scripts/Scripts.md` for what each script does. There is nothing else to run: the marks
travel inside the app, and the status line slot is taken from the panel. The app is quit from
its own panel; there is no Dock icon to quit it from.

## What it shows

The bar carries two lights per service and no numbers, stacked one above the other: the upper
light is that service's subscription limits, the lower one the context its running sessions
hold. The services are named `CLD` and `CDX` here and `Claude` and `Codex` everywhere else —
`AgentService.barLabel` against `shortLabel`. The bar is shared with every other app on the
Mac, and when it runs out of room macOS stops drawing status items, this one included;
measured at the bar's font, the abbreviations cost 83.2 pt drawn against 123.7 pt for the
names, so a third of the width goes back to staying visible. Nowhere with room to spare uses
them: in the panel or in a notification title "CLD" only reads as a typo. Stacked because it costs a third of the width, and because it puts the two in the order
the panel's sections are in, so the bar reads the same way round as what opens behind it. A limit window with nothing left in it is a red **cross** rather than a fourth colour: red
already means "the end is close", and no shade of it reads as "the end arrived", while a
different shape says so at a glance. A light with nothing behind it is not drawn at all, and
its place is kept — a ring was tried
first and reads as a dot that failed rather than as an absence, and position is what names a
light. What it must never be is green: the single dot this replaced fell back to green for an
unreported reading, which is the one lie the panel forbids everywhere else. In the panel the
ring stays, because a sentence explaining the absence stands next to it.

**A light blinks when its number moves.** Three times, 200ms dark and 200ms lit, on the
context light in the bar and on the row of the session that moved in the panel — both on the
same phase, so they go out together. It fires when a session's held tokens or its last-request
growth change, which is the same number the panel prints and the agent's own status line
prints. Of the two ends of a wait it now marks only the far one: the transcript is written
when a question is sent and again when the answer lands, but by the time the question is
written the session is already waiting, and a waiting light does not flash — see below.

**And it goes on blinking while a session waits on its agent.** The same light, the same beat,
for as long as the agent owes an answer: a question was asked, or a tool was called, and
nothing has come back. That is what the wait looks like from the corner of an eye — the state
lasts as long as the waiting does, rather than marking only its two ends.

Both signals share one light and one rhythm, and what tells them apart is how long they last:
three blinks and steady again is "the reading moved", blinking that does not stop is "it is
still working". A second rhythm was the alternative and was rejected — 200ms against 400ms is
not a difference an eye catches sideways, and two beats laid over one light are a ripple in
which neither is legible.

**So the two never run at once: while a light is waiting, its flash is suppressed.** They
would otherwise collide constantly rather than rarely — the numbers move several times inside
a single turn, measured here at anything from a tenth of a second to three quarters of a
minute apart, and every one of them would restart the beat. What that looks like is not two
signals but one broken one: series of three blinks with gaps between them, which reads as a
light dithering rather than as a process running. Suppressed is the right word and not
"dropped" — the flash means "the reading moved", the wait already means "something is
happening here", and during a wait the first says nothing the second has not. Outside a wait
it works exactly as it did, which includes the flash that fires the moment an answer lands and
the wait ends.

The beat itself is placed on a fixed grid rather than slept through a frame at a time. A sleep
lasts at least its length and the drawing after it takes its own; frame by frame that drifts,
and a blink that runs for minutes has to look at its end the way it looked at its start. The
wakeups ask for no tolerance for the same reason — a frame stretched to suit the scheduler is
the unevenness this is avoiding.

Waiting reaches the light the same way from both services, and is found in two different ways.
For Claude it is **derived, not observed**, and nothing this app can read would observe it:
measured, while a turn is being worked on neither the statusLine payload nor the transcript is
written at all, so what the app reads is what the last thing written leaves owed. Codex marks
both ends of a turn in its rollout and the state is simply read off them. Either way the light
is told a `ReplyWait` and nothing about where it came from — the rules, and what they cannot
cover, are in `AgentFiles.md`.

**A session waiting on the person is the other direction, and gets a sign of its own.** An
agent that has asked a question, or asked to be allowed to run something, is standing still and
looks in the bar exactly like one hard at work — the same blinking light, and the same light
for the opposite situation. So its light is drawn as a pause sign instead: two upright bars, the
shape everybody already reads as *stopped, and it is your move*. It appears the moment the
request does and goes in the pass that reads the answer; the bar then answers "who are we
waiting on" without the panel and without a notification. Which sessions those are comes from a
file Claude Code keeps per running process (`AgentFiles.md`), and a session it says nothing
about behaves exactly as it did before that file was read.

A light wearing a sign does not blink, and asking wins over a stall. Blinking is drawn by
leaving the light out for a frame, so a blinking sign would be a sign going missing and coming
back; and of the things the bar's one light per service could say, "this one wants you" is the
one a glance is for. The panel has a row per session and never has to choose.

**And a wait that drags on stops blinking and becomes a sign.** A closed terminal, a killed
process and an agent hard at work leave the same thing on disk, so what ends the blinking when
no answer is ever coming is time: past `sessions.abandoned_wait_after_minutes` of silence the
light is drawn as a figure eight instead — in the bar for the service, in the panel for the row.
It says the one thing the file supports, *no answer for a long time*, and refuses the two it
does not: neither "the session is dead", which nothing on disk shows, nor a plain steady dot,
which would claim the wait was over. It lasts until an answer arrives or until the row itself
goes by the activity window; there is no second fuse under it. Stopping the agent on purpose
needs no fuse at all: the interrupt is written down, and the light goes steady on the next pass.

**Shape carries the state, colour goes on carrying the budget.** Either sign is the light's own
colour — green because `.normal` is green, red when the context is against the ceiling, which
says both things at once and neither of them twice. Each keeps the dot's slot and its centre and
overhangs it into the padding, the eight sideways and the pause sign up and down: at six points
a figure eight squeezed into a dot's width is a smudge, and a light that moved its neighbour
would read as a different light. A sign is drawn only where a dot would have been drawn — in
the bar an unreported reading draws nothing, so a Claude session with the slot unconnected
stalls invisibly there, exactly as it blinks invisibly today, and the panel shows it in the
grey of its outline.

Only somebody being waited on gets a sign. A session nobody has typed into for an hour owes
nothing and asks nothing, so it keeps its plain dot however long it stays quiet and leaves by
the half-hour window like any other. Neither sign is drawn for a subagent either: an agent
finishes by itself and asks the person nothing.

Why blinking and not a glow: a halo fading in alpha over a point or two was drawn first and
was simply invisible in a menu bar — the eye gets nothing from a gradient that small. A light
being absent for 200ms is unmistakable, and it is the same kind of change as a light changing
colour, which already redraws reliably. The slot is kept empty rather than closed up, for the
same reason it is kept for a light with nothing behind it: position is what names a light.

The animation runs only while a blink does, and a wait is what keeps one going: the frames stop
the moment nothing is blinking and nothing is waiting. There is no timer the rest of the time —
the app still wakes only when a file changes, which is what makes this affordable at all. A
light wearing a sign costs nothing on top of that: it is a shape and not a beat, so a machine
full of abandoned sessions and unanswered questions animates exactly as much as an empty one
does, which is not at all.

**Three colours on one scale, under every light.** Yellow, orange and red mark the same three
shares of a window whether the window is a subscription limit or a session's context, so a
colour means one thing everywhere and nobody has to remember which light counts differently.
The first of the three only colours a dot: almost every session passes it, and a notification
there would teach the reader to ignore the two that matter. The marks themselves are in
`Thresholds.md`, and the first-run window shows them as the lights they turn on rather than
describing them in a sentence.

**A session whose window size nobody reported has no light.** Every mark is a share of a
window, so there is nothing to place: the session is still listed with its tokens, and its
light says "no reading" instead of the green it would otherwise fall back to. The rule is the
same one the bar applies to a source that has not reported at all.

**One light per section in the panel, both of them stacked in the bar.** The two sections are
named for the two dots — "Subscription limits" and "Active sessions — context" — and a heading
carries a light about its own contents — the limits heading about that service's limit windows,
each session row about itself — because in the panel there is room to keep the two subjects
apart. The bar has no sections, so it puts the pair together on one plate.

**And on the same side in both: the lights come first, the name after.** Every row of the panel
is a dot and then what it is about, and the bar sat the other way round until the two were seen
open together — the panel hangs directly under the plate it belongs to, and two arrangements of
the same four lights disagreeing about which side the colour is on cost a beat of looking every
time the eye moves between them. Width is unchanged: the same parts in the other order.

The bar answers "is anything worth looking at" and the panel answers "how much exactly". A
percentage in the bar was the previous arrangement, and it said nothing about the half of the
picture that was fine. The lights are drawn as an image rather than styled, because the menu
bar renders a label as a template image and would tint the colour away — and the colour is the
whole point of glancing at it; the service names stay `Text` so the system colours them for the
menu bar they are in.

The panel carries, in order, its two halves named after the two dots in the bar:

1. **Subscription limits**, folded away — each service on one line: its light, its name, and
   the five-hour window, named, with how much of it is gone. Opening it out gives both windows
   with their percentages, their reset times, the plan, and how old the reading is.
   The five-hour window and not the worst of the two, because it is the one that runs out
   during a working day and the one a glance is asking about — the weekly one is a question
   people ask deliberately, which is what opening the section out is for. Two exceptions, and
   both are one rule: a window with nothing left, and a weekly window that has crossed a mark
   the five-hour one has not. Each of those is the reason the dot is the colour it is, and a
   row showing the other window would leave the two disagreeing.
   The control that folds it stands under the readings, above the divider, saying what it
   opens. Not on the section's name: every other caption in this panel is a label, and a
   caption that was secretly a button was a control nobody found.
   Folded, because the two halves are not alike. A session's context moves several times a
   turn and is what the panel is opened for; a limit window creeps, and the question it
   answers — "have I got room today" — is asked once in a while. In full it is sixteen lines
   of a panel that also has to hold every running session, and with ten of those open there is
   nothing left to hold them in. The folded line keeps the number the light is made of, so the
   panel and the bar cannot say two different things about a service.
   It opens itself for the one thing in that half that is not a reading: a change to
   `settings.json` waiting for an answer, or a complaint that one did not happen. The offer to
   connect keeps its place even folded — until it is pressed there are no limits to fold, and
   once it is pressed the same place says "no data yet" rather than going blank: the moment
   after the button is the moment a person is watching it hardest.
2. **Active sessions — context** — the running sessions of both services, laid out by the same
   two builders as the half above it: service, the model it is answering on and the project on
   the lit line, "Context window" against how much of it is gone, and tokens held plus what the
   last request added underneath.
   The model is the identifier its own CLI uses — `claude-opus-5`, `gpt-5.6-sol` — set in the
   font the command hints are set in, because that is what it is: something you would type,
   not prose about the session. It sits against the service name rather than off to the right,
   since it says what this "Claude" currently *is*; the right edge belongs to the project and
   is the first thing a narrow panel truncates. A session whose source never named a model
   simply has no tag — no table of prettier names is kept here, and one would go stale the week
   a model ships.
   A limit window and a session read the same way on purpose — both are something being spent.
   A session's subagents are indented under it, each with its own light, its kind, its task and
   the tokens it holds: an agent fills a window of its own, so it is a consumer in its own
   right rather than a part of the session's number. Its light is drawn in full here and
   nowhere else — agent marks never colour the bar and never notify, because an agent ends by
   itself within minutes and a red dot nothing explains is a riddle.
   A service with nothing running is not listed. A row saying "No active sessions." under a
   heading that already says what the section is about spends a name, a dot and a line to
   repeat what the empty space says by itself; where the service stands in the widget is said
   above, by its limits entry, and in the bar, by its two dots. What does keep a row is a
   service whose files stopped parsing: that is a reading, and one nobody would otherwise
   ever see.
3. **Why the bar is that colour** — the one reading that set it, named.
4. **The icons**: disconnecting the status line slot, while it is the app's; the way back to
   the first-run explanation; and the way out. Terminating asks once — the panel is opened to
   read something, and the icon sits where a thumb lands.

Nothing in the panel is styled to be clicked — a caption looks like a caption, an icon like an
icon — so the few things that do something say so under the pointer, and only then: a plate
appears behind them and nothing else changes. That is `Hoverable`, and it is on the fold
control and on the three icons at the foot of the panel. A reading never gets one; lighting up
under a pointer would promise something it does not do.

Under every reading stands the command that shows the rest of it — `/usage` under a service's
limits, `/context` or `/status` under a session. It is the same command its notification ends
with, taken from the same place in `Phrasing`, because the panel and the notification answering
differently would be worse than either of them saying nothing.

Three rules the interface follows everywhere:

- **An agent nobody installed keeps its place.** It shows its name, two hollow lights and one
  line — "Not installed on this Mac — nothing to connect." Hiding it would save a little width
  and cost the only way to learn the widget covers that service; saying it in two places at
  once would read as two different problems, so the sessions half stays quiet about it.
- **Unknown is never zero.** No reading at all shows an em dash in the bar and a sentence in
  the panel, never `0%`. A Claude session with the status line slot unconnected says "window
  size unknown" and shows its tokens.
- **The age is always visible.** Limits are what the service reported at its last API call,
  not a live reading, and an hour-old number that looks current is worse than no number.
- **Nothing implies a measure of quality.** "Past the length Anthropic compacts at" is a fact
  about a line the vendor drew. "Quality: 62%" would be an invention, and there is no signal
  for it in anything this app can read.

## How it stays current

A source file changing is what triggers a refresh, and both CLIs append to a file as a turn
ends — so the panel is current a fraction of a second after the answer finishes, and a
notification about a mark crossed on that turn arrives while the turn is still what the user is
looking at. `SourceWatcher` in `AgentFiles` is the mechanism; events are let settle for 200 ms
first, because one turn writes to several files.

Underneath it a 30-second heartbeat refreshes anyway. It is not a second way of noticing
changes: it is for everything that changes with nothing being written — the age of every
reading, the time until a window resets, a session going quiet long enough to fall off the
list.

Reading happens off the main actor and the published values are replaced only once a reading is
complete, so the panel shows the previous numbers rather than a blank while the next ones are
read. Two readings never overlap: a file event arriving mid-read asks the read in progress to
go round once more instead of starting a second one. The thresholds are re-read on every pass,
so editing the config file changes behaviour without a restart, and so is the activity window
that decides which sessions the list holds.

The reader itself is kept for the life of the app rather than made per refresh, and that is
what makes the frequency above affordable. A turn is dozens of events about one file, and a
reader made afresh each time re-read every active session from the beginning for each of them;
one that outlives a pass remembers what a file said while the file still looks that way, so a
refresh costs what changed. The memory and its rules are `FileMemory`, in `AgentFiles` — the
directing of a copy of the app at a controlled set of files, for measuring, is the same
argument.

## Notifications

A mark crossed while the app is watching is said once, silently, and the last line of the
notification is the CLI command that shows the rest. What is worth saying is
`AlertDispatch`'s decision (in `SessionHealthCore`), the words are `Phrasing`'s, and `Notifier`
is only the delivery.

Two things about the delivery are worth knowing:

- **Silence is deliberate.** The widget interrupts while the user is working on something else.
  Neither channel ever asks for a sound.
- **There are two channels, and today the fallback is the one that works.** The notification
  centre refuses an ad-hoc signed app outright — `granted: false`, "Notifications are not allowed
  for this application", no dialog, no entry in the notification settings — measured from three
  launch paths with a correctly re-signed bundle. So notifications arrive through `osascript`,
  silently, attributed to Script Editor. Permission is still asked for first, so a build with a
  real signature starts using the centre without a code change. One consequence of borrowing
  Script Editor's identity: several notifications in a row collapse into one stack in the
  Notification Center, and only the newest shows on top of it.

The state found at launch is recorded rather than announced. The app starts at login and finds
whatever the day has already spent; a handful of notifications about the past every morning is
how a user learns to dismiss the one that matters.

## Connecting the limits, from the panel

Two of the three sources connect themselves the first time their CLI answers. The third —
Claude's subscription limits — exists only in what Claude Code hands its status line command,
so somebody has to put this app in that slot.

**The button for it stands where the limits would be.** The place a person looks for a figure
is the place that should say how to get one, so while the slot is not the app's, the Claude
limits entry holds a button and not a sentence about missing data. It goes as soon as the slot
is taken: what stands there afterwards is the reading itself, or — until the first answer of a
session arrives — the one sentence saying nothing has reported yet.

**Pressing it shows the change and writes nothing.** `UsageModel.propose` asks `StatusLineSlot`
what the edit to `~/.claude/settings.json` would be and publishes it; the panel shows the file,
the line going into it, and what happens to any status line command already there; and only
"Write it" applies it. Cancelling, or simply closing the panel, leaves the file alone. This is
the only thing in the panel that does something rather than reports something, and it is the
reason that whole entry steps aside while the question is on screen.

**Disconnecting is not there.** It is an icon in the panel's settings row, beside the `?` and
the power button, shown only while the slot is the app's. It acts on the app rather than on a
reading, and a control that takes a number away does not belong under that number.

## The first run, and the one window

A first launch with no explanation is a menu bar item showing an em dash next to "Claude" and
no way to find out why. So the app opens one window, once, listing every source with whether it
has reported and, for the one that has not, where the button is. `SetupInspector` finds the facts, `Briefing` in `Phrasing` says
them, and `WelcomeRecord` is the note in Application Support that keeps it to once. Deleting
that note brings the window back, and so does the button in the panel.

AppKit rather than a SwiftUI `Window` scene: with `LSUIElement` the app is not active when it
launches, so the window has to be ordered in front and the app activated by hand. The launch
itself is caught by an `NSApplicationDelegate`, because `MenuBarExtra` offers no callback until
its panel is opened — which is exactly the moment that is too late.

## Starting with the Mac

`SMAppService.mainApp`, the supported route since macOS 13, offered as a checkbox in the
first-run window — the one place it lives, reachable from the panel's `?` whenever it is wanted
again. A panel of readings is not where a checkbox belongs, and one copy of a control cannot
disagree with another. It is measured to work from an ad-hoc signed bundle, unlike
the notification centre.

The state is read back from the system every time the control appears rather than remembered:
Login Items can be switched off in System Settings without the app hearing about it, and a
remembered "on" would then be a lie. What is registered is the bundle **where it is now**, so
the app belongs in `/Applications` before the box is ticked — which is why the instructions have
the drag first and the first launch after it.

## Files

| File | Holds |
| --- | --- |
| `Entry.swift` | Where the process starts: the menu bar app, or Claude Code's status line command |
| `LLMInformBureauApp.swift` | The `MenuBarExtra` scene |
| `UsageModel.swift` | What is on screen, and what keeps it current: file events, the heartbeat, the one reader kept across passes, the alerts that come out of a refresh, and the change to `settings.json` waiting for a yes or a no |
| `MenuContent.swift` | The panel, the one light a section shows, and the button that takes Claude Code's status line slot |
| `Notifier.swift` | Putting a notification on screen, silently, over whichever channel works |
| `WelcomeWindow.swift` | The first-run explanation, and the only window this app has |
| `LoginItem.swift` | Starting with the Mac, and the checkbox both views share |

The English it speaks is its own target: see `Sources/Phrasing/Phrasing.md`.
