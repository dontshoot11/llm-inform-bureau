# LLM Inform Bureau

A macOS menu bar app for working in Claude Code and Codex at the same time. It keeps the two
things that quietly run out in sight, and says something the moment either crosses a mark:

- **Subscription limits** — Claude's 5-hour and weekly windows, Codex's primary and secondary
  ones: how much is spent, when it resets, and how old the reading is. Hitting a limit in the
  middle of a task costs the rest of the window.
- **Context budget** — what each running session holds: tokens, how much of the context window
  that is, and what the last request added. A full window is worth knowing about for two
  reasons: the more of it is old history, the more the model works around it, and past a point
  the CLI rewrites the session itself and the detail in the middle is what goes.
  [Claude Code](https://code.claude.com/docs/en/model-config) compacts at about 967K on a 1M
  window and at the 200K boundary on a 200K one.
- **Subagents of a Claude session** — each one fills a window of its own, so each gets its own
  line indented under the session that started it: what kind of agent it is, what it was asked
  to do, and how full its window is. Its mark is shown and never announced: an agent runs for
  minutes and ends by itself.

All of it already exists inside the CLIs — `/usage`, `/context`, `/status` — but reading it
means stopping to ask. This keeps it in the menu bar and notifies, silently, at the moment a
mark is crossed.

```
        ●         ●
 CLAUDE       CODEX
        ●
```

Two lights per service, stacked in the order the panel is in: the upper one is its
subscription limits, the lower one the context its running sessions hold. One scale under both
and under either service — **yellow past 40% of a window, orange past 60%, red past 90%** — so
a colour means the same thing wherever it appears. A red ✕ for a limit window with nothing left
in it, since no shade of red reads as "the end arrived", and nothing at all where there is
nothing to report, since "not reported" is not "all good". In the sketch above that is Codex:
limits to report, no session running, and the empty place still naming the light.

The scale measures how full something is, and nothing else. It is not a reading of how good
the answers are: nobody publishes a length at which that changes, the vendors say it does not,
and this app will not be the one to imply otherwise.

**A light blinks while a session is waiting on its agent** — a question asked, a tool running,
nothing back yet — and stops the moment the answer lands. The same light also blinks three
times when a session's numbers move, so what tells the two apart is how long they last: three
blinks and steady again is "the reading moved", blinking that does not stop is "it is still
working". A wait that goes silent for longer than ten minutes is drawn as a figure eight
instead: a closed terminal, a killed process and an agent hard at work leave the same thing on
disk, so the app says the one thing it knows — no answer for a long time — rather than claiming
the session died or pretending the wait is over. Shape carries the state and colour goes on
carrying the budget: a session that stalled with its window against the ceiling wears a red
figure eight.

Both services do this, found in two different ways: Codex brackets every turn in its rollout,
and Claude's boundaries are read off the last entry of the transcript — whose it was, and
whether it promised another. The blink runs while something is waiting and stops with it;
nothing is polled and no timer runs when nobody is waiting.

**And when the agent is waiting on you, its light is a pause sign.** A Claude session that has
asked a question is standing still, and until now it looked in the bar exactly like one hard at
work — the same blinking light for the opposite situation. Two upright bars say *stopped, and
it is your move*: they appear the moment the question does and go the moment you answer, so the
bar answers "who are we waiting on" without opening anything. The fuse above does not apply —
somebody who has not come back in an hour has not stalled, they are out of the room. This comes
from a record Claude Code keeps per running process, and a session it says nothing about — a
non-interactive run, an older CLI — goes on blinking as before.

No numbers in the bar on purpose. The bar answers *is anything worth looking at*; the panel
behind it answers *how much exactly* — each service's limit windows with their reset times and
the age of the reading, then every session running right now with its project, tokens, window
fill and what the last request added, its subagents indented beneath it, and one line naming
the reading that lit the worst light. Subagent marks stay in the panel: they never colour a
light in the bar, or a background agent would paint the bar red with no notification anywhere
to explain it.

## Notifications

Silent, once per mark per session, each ending with the command that shows the rest:

```
Claude context window past 90%
92% full, 920K tokens held. Our mark, placed below where the CLI compacts on its own: past
here it may rewrite the session, and what it drops first is the detail in the middle.
/context
```

Three marks, shipped inside the app — both scales and the marks that are one number can be
moved from the settings window behind the gear, and what you move stays yours across updates:

| Mark | Fires for | Default |
| --- | --- | --- |
| Context window filled | both services | 60%, then 90% |
| Subscription limit spent | both services | 60%, then 90% |
| A limit window about to reset | both services | under 5% of the window's length left — its marks stay quiet |

**Yellow never notifies.** Nearly every session and nearly every limit window passes 40%, so it
colours a light and says nothing; an alert there would only teach you to ignore the ones that
matter.

A mark is said once per session; `/clear` starts a new session, so it can be said again there.
Nothing is said twice about the same crossing.

**Or nothing at all.** The notifications line of the settings window carries a checkbox, and
unticking it stops the banners and nothing else — the lights, the signs in the bar and
everything they are counted from go on as they were. It survives a restart and an update, and
switching it back on does not deliver what you missed: the app goes on keeping count while it
is quiet, so a mark crossed during the silence is not news afterwards.

## Install

**Before you start:** macOS 13 or newer. That is the whole list. Nothing is compiled on your
Mac, so the Xcode Command Line Tools are not needed; there is nothing to sign in to, and the
app makes no network calls at any point — during installation or after it.

What you are given is one file, `LLMInformBureau-<version>.dmg`, holding the built app and an
`INSTALL.txt` saying everything this section says. From a release page it comes with a second
file beside it, `LLMInformBureau-<version>.pdf`, saying what the app is for and what each of its
lights means — that one is worth reading before installing anything. Building both yourself
instead is one command — see [Development](#development).

**No script of anybody else's runs on your Mac.** You drag the app in, the way you drag any
other app, and run one command. There is nothing else to set up: the marks the app watches
travel inside it, and Claude's limits are connected from its own panel, which shows you the
change before making it.

### Step 1 — Mount the image

Double-click the downloaded `.dmg`, or:

```sh
hdiutil attach ~/Downloads/LLMInformBureau-*.dmg
```

The volume is called `LLMInformBureau`, which is what makes the command below a constant
rather than something depending on where your browser puts downloads.

### Step 2 — Drag the app into Applications

The window that opened holds the app, a shortcut to your Applications folder and `INSTALL.txt`.
Drag the app onto the shortcut — both ends of the gesture are in the one window, so there is no
second one to find and arrange. Replacing an older copy is the same drag; quit the running one
from its panel first.

### Step 3 — One command

```sh
xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app
```

macOS marks everything that arrives over the network, and an ad-hoc signed app carrying that
mark is refused on launch. This clears it.

**It has to run after the drag, and it has to name the installed copy.** The mark travels with
a copy: clearing it on the disk image still leaves the copy in `/Applications` marked. Run it
first and there is nothing to clear — `xattr` answers `No such file` and stops.

### Step 4 — If you opened the app too early

macOS shows **"LLMInformBureau Not Opened — Apple could not verify…"**. Nothing is wrong with
the download. The bundle is signed ad-hoc rather than with a paid Apple developer account, and
anything so signed that arrived over the network is refused until the mark is cleared.

**Do not press the blue button.** It reads **Move to Trash**, it is the default one, and it
removes the app rather than the mark. Press **Done**, then run the command.

On macOS 26 that command is the only way through: the dialog leaves no "Open Anyway" entry in
System Settings → Privacy & Security — checked on a downloaded image. The routes usually named
for older systems — that same "Open Anyway" entry on macOS 15, Control-click in Finder →
**Open** on macOS 13 and 14 — are **not verified here**, there was no Mac on those versions to
try them on. The command works on all of them.

### Step 5 — The first run

Open it from Launchpad or `/Applications`, or with `open -a LLMInformBureau`.

It opens its settings window: the marks it watches — each scale is a bar you can move, and the
marks that are one number are fields beside their names — and, folded up underneath, everything
the app uses on this Mac and whether it has got it. Three sources, Claude Code's status line
slot — which is also where the slot is given back once the app holds it — the Accessibility
permission a click on a session needs, which name the notifications arrive under — with the
checkbox that decides whether they arrive at all — the **Open at
login** checkbox, and which copy of the app is the one running — its path and the date it was
built, because several bundles of the same name can sit on one disk and the system's own
privacy panes list them as one name. Every line says what it costs while the answer is no, and
the ones with an answer to give carry the button that opens the right pane of System Settings. That part opens by itself while something is still missing;
opening the window asks the system for nothing.

Afterwards the window is reached again from the gear in the panel. Nothing is installed as a
background service or a daemon: this is a normal application that happens to have no windows,
and unticking **Open at login** is all it takes to stop it starting.

### Step 6 — Check the menu bar

Two lights per service. What you should expect to see on a fresh install:

| What you see | What it means |
| --- | --- |
| Codex lights are lit | Codex needs nothing connected — it is read from its own rollouts |
| Claude's limits light is missing | The status line slot is not connected yet — see below |
| A service shows one line saying it is not installed | That agent is not on this Mac. Nothing to do |

Claude's limits appear only on a **Pro or Max** subscription, and only after the first answer
of a session — that field is not written on other plans at all. Open the panel for the numbers
behind the lights.

### Connecting Claude's limits

Claude's subscription limits and the size of its context window are handed to the statusLine
command and to nothing else — no file under `~/.claude` carries them. Reading them means
occupying that slot, and **there is exactly one slot.**

So the app asks for it. Open the panel: where Claude's limits would be there is a **Connect
limits** button instead of an empty reading — the place you look for the figure is the place
that tells you how to get one. Pressing it shows the exact line it would write into
`~/.claude/settings.json` and changes nothing until you say yes; a timestamped copy of that
file is kept beside it first.

The app then *is* the status line command, and it wraps what was there rather than replacing it.
Whatever command was configured before is saved, called with the same payload, and its output
printed unchanged:

```
Claude Code ──payload──▶ LLMInformBureau --status-line ──┬──▶ …/claude-status/<session>.json
                                                         └──▶ the command that was there before ──▶ the status line
```

The way back out is in the settings window behind the gear: on the line about Claude Code's
status line slot, a **Disconnect** button that puts your previous command back in the slot and
takes the app out of it. It shows the change before making it, the same way connecting does.

One consequence the preview says out loud: **with any statusLine configured, Claude Code stops
showing most footer hints**, `esc to interrupt` among them. That is Claude Code's behaviour and
the real cost of connecting.

Without it the app still shows Codex in full and Claude's context from the transcripts — and
says "no data" for Claude's limits rather than showing them as 0%.

**Slot held by another copy of this app?** Two ways that happens: an older version installed a
shell wrapper and put its path there, or a second copy of the app lives somewhere else on this
Mac and was connected from there. The panel offers to update it — under the numbers this time,
because they are arriving and nothing is broken. Taking the offer changes one line of
`settings.json`, deletes the leftover script if there is one, and leaves whatever command you
had underneath exactly where it is. What the app never does is treat its own command as
somebody else's: every copy keeps the displaced command in the same file, so saving one would
have the app calling itself out of that file for ever.

### Keeping it up to date

Download the new image and drag the app in over the old one, quitting the running copy from its
panel first. Then run the `xattr` command again: the mark is on the new copy too.

The connected slot stays connected — the command in it names the bundle, which is where the
new one went. A mark you moved yourself stays where you put it: what is kept is the choice, not
a copy of the app's own marks, so every mark you left alone arrives with the new version.

### Removing it

Open the settings from the gear in the panel. Untick **Open at login**, and — under *What it
uses on this Mac*, on the line about Claude Code's status line slot — press **Disconnect**. That
puts your previous command back where it was and takes the app's out, which matters because the
command in that slot names a binary inside the bundle you are about to delete. Then quit from
the panel and:

```sh
rm -rf /Applications/LLMInformBureau.app
rm -rf ~/Library/Application\ Support/LLMInformBureau
```

The second line removes the saved payloads and the command the app kept for you — everything
this app ever wrote for itself.

## Where the data comes from

Everything is read from files this Mac already has. The app makes no network calls, holds no
credentials, and writes nothing outside its own folder in Application Support. A test fails if
a network API ever appears in the sources.

| Service | Source | Gives | Needs installing |
| --- | --- | --- | --- |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` | limits, context, window size | no |
| Claude Code | `~/.claude/projects/**/*.jsonl` | context held, turn growth, project | no |
| Claude Code | `~/.claude/projects/**/<session>/subagents/agent-*.jsonl` | a subagent's context, its kind and its task | no |
| Claude Code | [statusLine contract](https://code.claude.com/docs/en/statusline), with the app in the slot | limits, context window size | **yes** |
| Claude Code | `~/.claude/sessions/<pid>.json` | whether a session has stopped and is waiting on you | no |

**Running only one of the two agents is normal.** The other keeps its place in the bar and the
panel, with hollow lights and one line saying it is not installed — nothing errors, and nothing
about the agent you do run is affected. An agent that is installed but has not answered yet
says that instead, because those are different facts.

**A subagent's window size is inherited, not guessed.** Nothing an agent writes says how big
its window is, and a model with a larger window is written down exactly like the ordinary one.
So an agent runs on its session's window unless it was given a model of its own — and when it
was, the line shows tokens with no percentage and a hollow mark, the same as any session whose
window nobody reported. About one agent in twelve here; a percentage of somebody else's window
would cost more than an absent one.

A file changing is what triggers a re-read — both CLIs append as a turn ends — so a
notification arrives while the turn is still what you are looking at, rather than within a
polling interval. Transcripts reach hundreds of megabytes; only the end of one is ever read.

## What it does not claim

**It does not measure the quality of the answers.** No such number follows from anything the
app can read — not the transcripts, not the rollouts, not the statusLine payload. "The window is
92% full" is a fact; "quality: 62%" would be an invention, and the interface never says it.

There is no mark for "this context has got too long" either: no published measurement supports
one for the models in use today, and the vendors' position is that there is no such length.
Every number the app compares against is the project's own, and **not one of them carries a
source** — an entry with no measurement is honest, an entry with an invented one lies silently.
They ship inside the app rather than sitting in a file you are expected to find and edit;
choosing them from the app's own settings is a task of its own. Which numbers, what they rest on
and what would make them wrong: [Thresholds.md](Sources/SessionHealthCore/Thresholds.md); how to
change one: [AGENTS.md](AGENTS.md).

### What was tried and dropped

An earlier version of this project tried to score the *health* of a session — to tell, from its
own history, that it had started going in circles. Three candidate signals were tested against
39 real sessions and none survived:

| Candidate signal | Result |
| --- | --- |
| Re-reading a file it had already read | Occurs in 1 session out of 39 — effectively never fires |
| Editing the same file over and over | Median 0 in both short and long sessions; only outliers |
| Share of failed tool calls | *Lower* in long sessions (0.023) than in short ones (0.050) |

The error-rate result inverts the expectation, so it was checked within sessions too: first half
0.019, second half 0.020, across 37 long sessions, with the second half worse in 18 of them.
That is a coin flip. A marker planted in the context and checked later was rejected for a
different reason — [NoLiMa](https://arxiv.org/abs/2502.05167v3) shows models stay strong at
literal string matching long after inference has degraded, so such a check fails optimistically,
which is worse than no check.

Context length remains worth watching because the underlying effect is real and measured —
[Context Rot](https://www.trychroma.com/research/context-rot) finds degradation at every
increment of input length across 18 frontier models, and
[RULER](https://www.alphaxiv.org/abs/2404.06654) finds usable context consistently far shorter
than advertised. That is why the app shows absolute tokens next to the percentage: a 300K
session is a long session whether the window is 200K or 1M.

## Notifications, honestly

macOS refuses the notification centre to an ad-hoc signed app: `requestAuthorization` returns
`granted: false` before any dialog appears, and the app never shows up in notification settings.
So notifications go out through `osascript` instead — silent all the same, but attributed to
Script Editor, and several in a row collapse into one stack. Permission is still requested
first, so a build with a real Developer ID signature starts using the centre with no code
change.

## Development

```sh
git clone https://github.com/dontshoot11/llm-inform-bureau.git
cd llm-inform-bureau

swift build                  # the library targets and the executable
swift run SessionHealthTests # the test suite: one line per case, exit code 0 or 1
Scripts/build-app.sh --run   # rebuild the bundle and restart it
Scripts/build-dmg.sh         # the whole disk image, version and all — one command
Scripts/build-handout.sh     # the PDF description that goes on the release page beside it
Scripts/release.sh -         # both of those, the tag and the release page — one command
```

`Scripts/build-dmg.sh` builds the app, checks it, and writes
`.build/LLMInformBureau-<version>.dmg`, the single file that is handed to anybody else. The
version in the file name is `CFBundleShortVersionString` from `Scripts/Info.plist`, so there is
no second place to remember. The recipient's instructions ride inside the image as
`INSTALL.txt`, written by that same script — there is no second copy of them to keep in step.

**The author installs from the image like everybody else**, with the drag and the one command
in [Install](#install). There is no developer-only installation path in this repository, which
is why the one path there is stays working.

### Releasing a version

```sh
Scripts/release.sh - <<'NOTES'
- The interface speaks Russian as well as English.
NOTES
```

That is the whole of a release: it builds the image, builds the PDF, tags `v<version>` and
publishes a GitHub release page with both files attached. The number comes from
`CFBundleShortVersionString` alone, so bumping that one line in `Scripts/Info.plist` is the whole
of "releasing 0.2.0". The argument is what changed, in Markdown — there is no changelog file here,
and the page is written at the moment of release; under it the script adds the first steps of
installing, with the version in them.

It refuses before it builds anything: no notes, no `gh`, `gh` not logged in, a dirty tree, a
version already released, a commit not pushed. The tag is made by GitHub in the same call that
creates the page, so an attempt that stops early leaves nothing to undo on either side. What each
refusal means, and why the order is that one:
[Scripts/Scripts.md](Scripts/Scripts.md#publishing-a-release).

### What to send with the link

Everything the recipient is given in writing rides inside the image — including the part that
says to mount it, which is no use to somebody who has not. The release page says those first
steps above the two files, so a link to it needs nothing added. A file handed over directly — in
a chat, without the page — still does, and this is the text for that message:

```
Download the image, then:

  1. Open ~/Downloads/LLMInformBureau-<version>.dmg
  2. Drag LLMInformBureau.app onto the Applications shortcut beside it
  3. In Terminal:
       xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app
  4. Open it from Launchpad

Line 3 is what lets macOS run it, and it has to come after the drag. Nothing else to run:
no installer, no script of mine on your Mac.

INSTALL.txt on the image says all of this at length, including what the app asks you before
it touches Claude Code's settings.
```

Replace `<version>` with the number in the file name. Paste it as it is — the command is a
constant, whatever the browser did with the download.

**The app is built as a universal binary**, `arm64` and `x86_64`, so the image runs on an Intel
Mac as well — that is a thing to be sure of before handing the file over, not after. It is two
builds joined with `lipo` rather than `swift build --arch`, whose xcbuild path needs the full
Xcode; the Command Line Tools stay the only requirement, and a build takes about twice as long.
`build-dmg.sh` refuses to pack a bundle that is not universal or whose signature does not
verify. Details and the orderings that matter: [Scripts/Scripts.md](Scripts/Scripts.md).

`swift test` does not work here: both Swift test frameworks ship inside Xcode, and this package
is built with the Command Line Tools alone. The suite is an executable target with a small
harness instead — see
[Tests/SessionHealthTests/SessionHealthTests.md](Tests/SessionHealthTests/SessionHealthTests.md).

Each module has its documentation next to the code:
[SessionHealthCore](Sources/SessionHealthCore/SessionHealthCore.md) (the rules),
[AgentFiles](Sources/AgentFiles/AgentFiles.md) (the files and their formats),
[Phrasing](Sources/Phrasing/Phrasing.md) (every English string and what it may claim),
[LLMInformBureau](Sources/LLMInformBureau/LLMInformBureau.md) (the app),
[Handout](Sources/Handout/Handout.md) (the PDF description handed out with a release),
[Scripts](Scripts/Scripts.md) (building and installing).
