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

Four marks, all of them in an editable config file:

| Mark | Fires for | Default |
| --- | --- | --- |
| Context window filled | both services | 60%, then 90% |
| Subscription limit spent | both services | 60%, then 90% |
| One expensive request | both services | +10% of the window, or +20K tokens, in a single request |
| A limit window about to reset | both services | under 5% of the window's length left — its marks stay quiet |

**Yellow never notifies.** Nearly every session and nearly every limit window passes 40%, so it
colours a light and says nothing; an alert there would only teach you to ignore the ones that
matter.

A mark is said once per session; `/clear` starts a new session, so it can be said again there.
Nothing is said twice about the same crossing.

## Install

**Before you start:** macOS 13 or newer. That is the whole list. Nothing is compiled on your
Mac, so the Xcode Command Line Tools are not needed; there is nothing to sign in to, and the
app makes no network calls at any point — during installation or after it.

What you are given is one file, `LLMInformBureau-<version>.dmg`, holding the built app, the
installer and an `INSTALL.txt` saying everything this section says. Building it yourself
instead is one command — see [Development](#development).

### Step 1 — Mount the image

Double-click the downloaded `.dmg`, or:

```sh
hdiutil attach ~/Downloads/LLMInformBureau-*.dmg
```

The volume is called `LLMInformBureau`, which is what makes the command below a constant
rather than something depending on where your browser puts downloads.

### Step 2 — Two commands, in this order

```sh
sh /Volumes/LLMInformBureau/install.sh --apply                        # installs it
xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app    # lets macOS run it
```

Run the first one without `--apply` to read the whole plan and change nothing. It is someone
else's shell script and one of its steps edits a file of Claude Code's, so reading it once is
worth the minute.

Four steps, each printed before it happens:

1. **Install the app to `/Applications`** — the bundle lying on the image, copied as it is.
   Nothing is compiled here.
2. **Copy the thresholds to `~/Library/Application Support/LLMInformBureau/thresholds.json`** —
   the editable copy. Editing it changes the marks with no rebuild. An existing one is left
   exactly as it is.
3. **Connect the statusLine wrapper** (see below) — the one step that touches a file of
   Claude Code's. It prints the change, keeps a timestamped backup, and preserves whatever
   command was there before. The wrapper travels inside the app, so this works with no clone
   and no Command Line Tools.
4. **Start the app** — unless macOS has the copy quarantined, in which case the installer
   prints the second command instead of opening anything.

**The order does not swap.** macOS marks everything that arrives over the network, and the mark
travels with a copy: clearing it on the disk image still leaves the copy in `/Applications`
marked. Run the second command first and there is nothing to clear — `xattr` answers
`No such file` and stops.

**`sh` in front of the first command is not decoration.** A script run straight off a mounted
image is blocked by Gatekeeper with a dialog and no output; handed to an interpreter, it runs.

### Step 3 — If you opened the app too early

macOS shows **"LLMInformBureau Not Opened — Apple could not verify…"**. Nothing is wrong with
the download. The bundle is signed ad-hoc rather than with a paid Apple developer account, and
anything so signed that arrived over the network is refused until the mark is cleared.

**Do not press the blue button.** It reads **Move to Trash**, it is the default one, and it
removes the app rather than the mark. Press **Done**, then run the second command.

On macOS 26 that command is the only way through: the dialog leaves no "Open Anyway" entry in
System Settings → Privacy & Security — checked on a downloaded image. The routes usually named
for older systems — that same "Open Anyway" entry on macOS 15, Control-click in Finder →
**Open** on macOS 13 and 14 — are **not verified here**, there was no Mac on those versions to
try them on. The command works on all of them.

### Step 4 — The first run

Open it from Launchpad or `/Applications`, or with `open -a LLMInformBureau`. The installer
starts the app itself, but not while the quarantine mark is on it — so after a download the
first launch is yours to make.

The app opens one window explaining where each of its numbers comes from and what is not
connected yet. It carries the **Open at login** checkbox; afterwards the same checkbox lives
behind the `?` icon in the panel. Nothing is installed as a background service or a daemon:
this is a normal application that happens to have no windows, and unticking the checkbox is
all it takes to stop it starting.

### Step 5 — Check the menu bar

Two lights per service. What you should expect to see on a fresh install:

| What you see | What it means |
| --- | --- |
| Codex lights are lit | Codex needs nothing connected — it is read from its own rollouts |
| Claude's limits light is missing | Either the wrapper is not connected yet, or the current session has not answered since |
| A service shows one line saying it is not installed | That agent is not on this Mac. Nothing to do |

Claude's limits appear only on a **Pro or Max** subscription, and only after the first answer
of a session — that field is not written on other plans at all. Open the panel for the numbers
behind the lights.

### The statusLine wrapper

Claude's subscription limits and the size of its context window are handed to the statusLine
command and to nothing else — no file under `~/.claude` carries them. Reading them means
occupying that slot, and **there is exactly one slot.**

So the wrapper is a wrapper and not a replacement. Whatever command was configured before is
saved, called with the same payload, and its output printed unchanged:

```
Claude Code ──payload──▶ wrapper ──┬──▶ ~/Library/Application Support/…/claude-status/<session>.json
                                   └──▶ the command that was there before ──▶ the status line
```

The installer shows exactly what it will change in `~/.claude/settings.json` before changing
it, keeps a timestamped backup, and can be undone with `--uninstall`. One consequence it says
out loud: **with any statusLine configured, Claude Code stops showing most footer hints**,
`esc to interrupt` among them. That is Claude Code's behaviour and the real cost of connecting
the wrapper.

Step 3 of the installation runs it, and it can be run on its own at any time afterwards. It
lives inside the installed app, which is the whole copy of this repository a recipient needs:

```sh
sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh            # the plan
sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --apply       # connect it
sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --uninstall   # put the old command back
```

From a clone the same script is `Scripts/install-statusline.sh`; both copies behave the same,
because each one takes the wrapper from beside itself.

Without it the app still shows Codex in full and Claude's context from the transcripts — and
says "no data" for Claude's limits rather than showing them as 0%.

### Keeping it up to date

Download the new image and run the same two commands. The installed copy is replaced, a running
one is quit first, and **your edited `thresholds.json` is left exactly as it is** — it is the
file the app reads, and overwriting your marks during an update is the one thing the installer
will not do. If a release changes the shape of that file, the app falls back to the built-in
values and the panel says "default thresholds applied"; the installer prints the one `cp` that
takes the new ones.

### Removing it

Untick **Open at login**, quit from the panel, then, in this order:

```sh
sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --uninstall
rm -rf /Applications/LLMInformBureau.app
rm -rf ~/Library/Application\ Support/LLMInformBureau
```

The first line puts your previous statusLine command back where it was, and it has to run
before the second: the script it names lives inside the bundle that the second line deletes.
The third removes the thresholds you edited, the saved payloads and the copy of the wrapper —
everything this app ever wrote.

## Where the data comes from

Everything is read from files this Mac already has. The app makes no network calls, holds no
credentials, and writes nothing outside its own folder in Application Support. A test fails if
a network API ever appears in the sources.

| Service | Source | Gives | Needs installing |
| --- | --- | --- | --- |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` | limits, context, window size | no |
| Claude Code | `~/.claude/projects/**/*.jsonl` | context held, turn growth, project | no |
| Claude Code | `~/.claude/projects/**/<session>/subagents/agent-*.jsonl` | a subagent's context, its kind and its task | no |
| Claude Code | [statusLine contract](https://code.claude.com/docs/en/statusline) via the wrapper | limits, context window size | **yes** |

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
Which numbers, what they rest on and what would make them wrong:
[Thresholds.md](Sources/SessionHealthCore/Thresholds.md); how to change one:
[AGENTS.md](AGENTS.md).

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
```

`Scripts/build-dmg.sh` is the release: it builds the app, checks it, and writes
`.build/LLMInformBureau-<version>.dmg`, the single file that is handed to anybody else. The
version in the file name is `CFBundleShortVersionString` from `Scripts/Info.plist`, so there is
no second place to remember. The recipient's instructions ride inside the image as
`INSTALL.txt`, written by that same script — there is no second copy of them to keep in step.

**The author installs from the image like everybody else**, with the two commands in
[Install](#install). There is no developer-only installation path in this repository, which is
why the one path there is stays working.

### What to send with the link

Everything the recipient is given in writing rides inside the image — including the part that
says to mount it, which is no use to somebody who has not. So the message carrying the link
carries the first steps too:

```
Download the image, then, in Terminal:

  1. open ~/Downloads/LLMInformBureau-<version>.dmg
  2. sh /Volumes/LLMInformBureau/install.sh --apply
  3. xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app
  4. open -a LLMInformBureau

Line 2 installs it, line 3 lets macOS run it — that order, and both are needed. Line 4 is
yours to run because the installer will not open an app macOS still has marked.

INSTALL.txt on the image says all of this at length, and what to do when a step fails.
Worth the two minutes before line 2: it is someone else's shell script.
```

Replace `<version>` with the number in the file name. Paste it as it is — the commands are
constants, because the volume is always `/Volumes/LLMInformBureau` no matter where the browser
put the download.

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
[Scripts](Scripts/Scripts.md) (building and installing).
