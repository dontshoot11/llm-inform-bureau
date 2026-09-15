# LLMInformBureau

The menu bar app: four lights in the bar, a panel behind them, and one window it opens once.

## Build and run

```sh
Scripts/install.sh --apply  # build, install, connect the wrapper, start it
Scripts/build-app.sh --run  # rebuild the bundle and restart it, while working on it
```

See `Scripts/Scripts.md` for what each script does. The app is quit from its own panel; there
is no Dock icon to quit it from.

## What it shows

The bar carries two lights per service and no numbers, stacked one above the other: the upper
light is that service's subscription limits, the lower one the context its running sessions
hold. Stacked because it costs a third of the width, and because it puts the two in the order
the panel's sections are in, so the bar reads the same way round as what opens behind it. A limit window with nothing left in it is a red **cross** rather than a fourth colour: red
already means "the end is close", and no shade of it reads as "the end arrived", while a
different shape says so at a glance. A light with nothing behind it is not drawn at all, and
its place is kept — a ring was tried
first and reads as a dot that failed rather than as an absence, and position is what names a
light. What it must never be is green: the single dot this replaced fell back to green for an
unreported reading, which is the one lie the panel forbids everywhere else. In the panel the
ring stays, because a sentence explaining the absence stands next to it.

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
apart. The bar has no sections, so it puts the pair side by side under the service name.

The bar answers "is anything worth looking at" and the panel answers "how much exactly". A
percentage in the bar was the previous arrangement, and it said nothing about the half of the
picture that was fine. The lights are drawn as an image rather than styled, because the menu
bar renders a label as a template image and would tint the colour away — and the colour is the
whole point of glancing at it; the service names stay `Text` so the system colours them for the
menu bar they are in.

The panel carries, in order, its two halves named after the two dots in the bar:

1. **Subscription limits** — each service under one light of its own: every window with its
   percentage, its reset time, the plan, and how old the reading is.
2. **Active sessions — context** — the running sessions of both services, laid out by the same
   two builders as the half above it: service and project on the lit line, "Context window"
   against how much of it is gone, and tokens held plus what the last request added underneath.
   A limit window and a session read the same way on purpose — both are something being spent.
   A session's subagents are indented under it, each with its own light, its kind, its task and
   the tokens it holds: an agent fills a window of its own, so it is a consumer in its own
   right rather than a part of the session's number. Its light is drawn in full here and
   nowhere else — agent marks never colour the bar and never notify, because an agent ends by
   itself within minutes and a red dot nothing explains is a riddle.
   A service with nothing running keeps its place here too, under a hollow light and the
   sentence for why — an empty space beside the other service's sessions would read as a
   service that is fine.
3. **Why the bar is that colour** — the one reading that set it, named.
4. **"Default thresholds applied"**, with what was wrong, when the config file could not be
   used as written.
5. **Two icons**: the way back to the first-run explanation, and the way out. Terminating asks
   once — the panel is opened to read something, and the icon sits where a thumb lands.

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
  the panel, never `0%`. A Claude session without the wrapper says "window size unknown" and
  shows its tokens.
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

## The first run, and the one window

Two of the three sources connect themselves the first time their CLI answers, and one — the
statusLine wrapper — has to be installed by hand. A first launch with no explanation is
therefore a menu bar item showing an em dash next to "Claude" and no way to find out why. So
the app opens one window, once, listing every source with whether it has reported and what to
run for the one that has not. `SetupInspector` finds the facts, `Briefing` in `Phrasing` says
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
the app is installed to `/Applications` before the box is ticked — which is the order
`Scripts/install.sh` does it in.

## Files

| File | Holds |
| --- | --- |
| `LLMInformBureauApp.swift` | The `MenuBarExtra` scene |
| `UsageModel.swift` | What is on screen, and what keeps it current: file events, the heartbeat, and the alerts that come out of a refresh |
| `MenuContent.swift` | The panel, and the one light a section shows |
| `Notifier.swift` | Putting a notification on screen, silently, over whichever channel works |
| `WelcomeWindow.swift` | The first-run explanation, and the only window this app has |
| `LoginItem.swift` | Starting with the Mac, and the checkbox both views share |

The English it speaks is its own target: see `Sources/Phrasing/Phrasing.md`.
