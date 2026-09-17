# AgentFiles

Everything this app knows about where Claude Code and Codex leave their traces on disk, and
nothing about what those traces mean. The rules live in `SessionHealthCore`; this module's
only job is to turn files into the value types those rules take.

It also writes, and it is the only module that does. Claude hands its subscription limits to a
status line command and to nothing else, so the app has to *be* that command to see them — and
what it is handed has to be put somewhere the panel can read it. That is `StatusLineMode`.
Getting into that slot in the first place means editing a file that belongs to somebody else,
`~/.claude/settings.json`, and that is `StatusLineSlot`. Both are below; the second is the only
place in this project where another program's configuration is written to, and everything about
it is built around that.

## Why the two halves are separate

File formats change with a CLI release; rules change when we learn something. Keeping them
apart means a format change is a fix in one file with its own tests, and the rules never grow
a special case for a field that moved.

It also means the awkward outcomes have a place to be named. Every reader here returns
`SourceReading`, which has three cases rather than two:

| Outcome | When | What the widget shows |
| --- | --- | --- |
| `.value` | the files answered | the numbers, and how old they are |
| `.noData` | nothing has been reported yet — no sessions, none that reached the API, a source not connected | a sentence saying so |
| `.unavailable` | the files are there and no longer parse | a sentence saying the source changed |

"Nothing yet" and "this stopped working" look identical in a widget that can only be empty,
and they call for different reactions: one waits, the other needs a look at the format. An
empty list of sessions is a `.value`, not an absence — "nothing is running" is a fact.

## The three sources

| Source | Gives | Needs installing |
| --- | --- | --- |
| Codex rollouts | Codex limits **and** Codex sessions, window size included | no |
| Claude transcripts | Claude sessions: tokens held, project, turn growth — and the subagents running inside them | no |
| the status line slot | Claude limits, and the size of a Claude context window | **yes** |

Three readers, because Codex says everything in one file and Claude says it in two places —
neither of which is complete on its own.

### Codex: one file says everything

`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Every API response appends an `event_msg` of
type `token_count` carrying `rate_limits` *and* `info.last_token_usage` with
`model_context_window`. So the freshest reading of both is the last such event in the most
recently written rollout. No network call, no login, nothing to keep in sync — and it is
exactly what `/usage` and `/status` show.

Three things found on disk that the reader has to know about:

- **A rollout carries several limit pools.** Only `limit_id: "codex"` is the subscription;
  there is also a reserve pool and a `premium` pool that is usually all nulls. Taking the
  last `rate_limits` line blindly would show an empty pool as 0% spent.
- **`primary` is the short rolling window, `secondary` the weekly one** (300 and 10080
  minutes on this account). They map to `LimitWindow.Kind.short` and `.weekly`, so the rules
  never have to know whose vocabulary this is.
- **`last_token_usage` is the context held, `total_token_usage` is the session total.** The
  second only ever grows and is not a budget; on a long session it runs into the millions
  against a 258K window.

The model is in none of those either. It is on the `turn_context` line that opens each turn,
which is where this reads it from — the same name also appears in a `world_state` line and
three times over inside `session_meta`, and one place to read it from is what keeps the reader
from disagreeing with itself. Per turn rather than per session on purpose: Codex lets the model
be changed mid-session, and the row should say the one it is on now.

The session's working directory is not in any of that — it is in the `session_meta` line at
the head of the file, which is why this reader reads both ends of a rollout.

### Claude: two sources, neither complete

A transcript (`~/.claude/projects/**/*.jsonl`) is always there and never knows the size of the
context window. The status line knows the size and the subscription limits, and is only there
once the slot has been connected — and the status line is this app itself, run by Claude Code
in `--status-line` mode. So:

- **tokens held** always come from the transcript: `input_tokens +
  cache_creation_input_tokens + cache_read_input_tokens` of the last assistant line, the same
  sum the status line's own `used_percentage` is calculated from;
- **the window size** is filled in from the status line payload for the same session id, when
  there is one. `UsageReader.withWindowSizes` is the whole of that join;
- **the limits** come from the status line alone. There is no file under `~/.claude` that
  carries them, so until the slot is connected the panel offers to connect it instead of
  showing a number — the absence is the truth, not a gap;
- **the model** comes from the transcript, off the same last answer the tokens do
  (`message.model`). The payload names it too, and more exactly — it carries the variant,
  `claude-opus-5[1m]` against the transcript's `claude-opus-5` — but reading it from there
  would make the model appear only for whoever connected the slot, and what the variant
  changes is the window size, which the panel already shows on its own.

Three shapes in a transcript the reader has to know about:

- **Sidechain lines.** Anything a subagent writes into the session's file is marked
  `isSidechain: true`, and its tokens are not the session's context. They are skipped *here* —
  in the agent's own file, below, they are the only thing there is.
- **A `tool_result` is a user line.** Turns are separated by user *prompts*, and a tool result
  is the middle of the turn already running. Growth over "the last turn" is measured from the
  last real prompt, so what the panel shows is what one request of the person's cost.
- **`cwd` moves during a session.** A command run deeper in the tree changes it, and every
  line after that carries the new path — so the project is read from the *first* `cwd` in the
  file, the one the session started in and the one Claude Code named the transcript's own
  directory after. Naming a session after where it wandered to showed one project as two.
  The directory name cannot be decoded back into a path instead: it is the path with every
  `/` and `.` turned into `-`, and `colors.css` and `colors/css` come out the same.

### Whether a session is waiting on its agent

A session's row says not only what it holds but whether the agent owes it an answer right now —
`SessionSnapshot.replyWait`, which the panel and the bar draw on. Three outcomes, not two:
nothing owed, an answer owed and still expected (`.waiting`, the blinking light), and an answer
owed for longer than the fuse (`.stalled`, the figure eight).

Both services answer the question and neither answers it the same way, which is why each reader
holds its own rule: Claude has to be read between the lines, Codex says it outright. The fuse
under both is one threshold and one rule — `SessionActivity.replyWait`.

#### Claude: the turn boundaries are inferred

**Nothing on disk announces a request in flight.** Measured: while a turn is worked on, neither
the transcript nor the statusLine payload is written — 25 seconds of a busy session moved
neither file's modification time. So the state is not observed but derived, from the last thing
that *was* written: does it leave an answer owed.

Two things make that readable:

- **Which entries are asked.** The tail of a transcript is housekeeping written after the
  answer landed — `last-prompt`, `mode`, `atis-latch`, `file-history-*`, `attachment`,
  `system`, none of them carrying a message or a timestamp. "The last line of the file" is
  therefore not the last thing said. Only `assistant` and `user` entries are asked, and only
  the ones belonging to this file: a session's own, or an agent's sidechain entries in the
  agent's own file.
- **What that entry leaves owed.** A user entry owes an answer outright — and a `tool_result`
  is a user entry, which is what keeps the wait unbroken while tools run. An assistant entry
  owes one when it called a tool, and `stop_reason` is what says so, not the content blocks:
  measured over 32,000 assistant entries on this machine, one response is written as several
  entries — `thinking`, then `text`, then `tool_use` — all carrying the same `stop_reason`.
  Reading the blocks would take that middle `text` entry for the end of the turn and break the
  wait in two every time the agent said something before reaching for a tool. Any stop reason
  other than `tool_use` — `end_turn`, and the handful of `stop_sequence` and `max_tokens` —
  is the turn over: whatever happens next waits on the person, not on the agent.
- **What an interrupted turn leaves owed: nothing.** Stopping the agent mid-turn writes an
  ordinary user entry whose text is `[Request interrupted by user]` (or `… for tool use`),
  which the rule above would otherwise read as a question waiting to be answered — and it is
  the opposite: the agent was told to stop, and whatever happens next waits on the person.
  Counted here: of 73 such entries, 69 are followed by the person typing again rather than by
  an answer, a median of 16 seconds later. The words are what is read, not the
  `interruptedMessageId` beside them: that field is on 61 of the 73 and the words are on all
  of them. A *rejected* tool call is not one of these — the agent is handed the refusal and
  answers it, so the wait goes on.
- **How long the entry has owed it.** An entry that owes an answer says the agent was working
  when it was written, not that it still is, so the reading carries the moment rather than a
  flag, and `SessionActivity.replyWait` puts it against the configured fuse
  (`sessions.abandoned_wait_after_minutes`). The moment is the entry's own timestamp and never
  the file's date: measured, a transcript's modification date runs ahead of the last thing
  said in it by a median of a minute and a half and, in 87 files of 385, by more than ten
  minutes — housekeeping keeps touching a file long after the conversation in it stopped.

Two things this rule does not do, and both are honest rather than hidden:

- **A session that has never answered has no row**, so its first turn cannot blink. The
  transcript carries no `usage` until the first answer, and a row with no tokens on it would
  be the zero this app does not invent. It applies to a new session and to one just cleared,
  which starts a file of its own; every turn after the first is covered.
- **A wait that never ends is not believed, and not denied either.** Counted over 382
  transcripts on this machine, 34 end owing an answer that never came — a closed terminal, a
  killed process, a machine that slept. Nothing in a transcript marks any of that, and nothing
  can: a session hard at work leaves exactly the same thing behind. So the reading is true to
  the file and the fuse is time, not a marker — past `sessions.abandoned_wait_after_minutes`
  of silence the row stops saying an answer is expected and starts saying it has been owed a
  long while (`.stalled`), which is the whole of what the file supports. The row stays for as
  long as the activity window says, and the stall ends when an answer arrives or when the row
  does. Verified on a session killed mid-turn: the transcript ends on the question, the row
  reads as waiting, and it turns to a stall the moment the fuse is up.
- **Only a wait can stall.** A session nobody has typed into for an hour owes nothing — its
  turn ended — so it gets a plain dot however long it stays quiet, and leaves by the activity
  window like any other. The same goes for a turn the person stopped: it is over, and staying
  over for longer does not make it something the agent owes an answer for.

#### Codex: the turn boundaries are announced

A rollout brackets every turn: `task_started` opens one, `task_complete` closes it, and
`turn_aborted` closes the one the person cut short. So there is nothing to infer — the last
boundary in the file is either an opening one, and the turn is running, or a closing one, and
nobody is waiting on the agent. Counted over the 133 rollouts on this machine: 870 turns
opened, 825 completed, 39 were aborted, every abort carrying `reason: "interrupted"`.

Everything else about the wait is the same rule as Claude's, for the same reasons:

- **The moment is the last line written, not the opening of the turn.** Codex writes all the
  way through one — reasoning, tool calls, their output, a token count per response — so the
  silence the fuse measures is the silence since the last of those. Measured over 32,804 gaps
  between consecutive lines inside a turn: half under a second, 99% under 27, and 5 of them
  (0.015%) past the ten-minute fuse. The fuse means the same thing here as it does for Claude.
  A rollout's modification date would do as well — measured, it and the last line in the file
  agree to the second, which a Claude transcript's does not — but the line's own timestamp is
  what is read, so one reader's idea of when something happened is not two. When that line's
  moment cannot be read, the file's date stands in for it and an earlier line never does:
  reaching further back would answer with a silence longer than the real one and stall a
  session that is working.
- **The 6 rollouts that end on an opening** are the abandoned waits: terminals closed mid-turn,
  processes killed. Verified on a session killed mid-turn with `SIGKILL` — the row reads as
  waiting and turns to a stall the moment the fuse is up.
- **A session that has not reported a `token_count` yet has no row**, so its first turn cannot
  blink — the same limitation, arrived at from the other side: the row's tokens come from that
  event, and a row with no tokens on it is the zero this app does not invent.
- **A turn whose opening is further back than the half megabyte read from the end of the file
  is not claimed as a wait.** That takes a tool output running to megabytes; on a guess the
  light stays steady rather than blinking.

### Claude: the subagents of a session

A subagent is not in its session's transcript at all. Claude Code writes it beside the session:
`<session id>/subagents/agent-<id>.jsonl`, with `agent-<id>.meta.json` next to it carrying
`agentType`, the `description` whoever started it gave, and `spawnDepth`.

- **Every line in that file is a sidechain line** — the very thing a session's reading throws
  away. So the rule is not "skip sidechain lines" but "a sidechain line is not the *session's*
  context": in the agent's own file it is the whole of it.
- **They are found through their session, not by the walk.** Agent files are written after the
  session they belong to, so counting them among the newest transcripts spent the budget of
  files to look at on one busy session and pushed other projects' sessions off the list. The
  walk skips anything in a `subagents` directory; each active session is then asked for its own.
- **An agent ends on `end_turn`.** A session is closed off by a `cost-state` line; an agent has
  no equivalent, and is over when its last message is a final answer. One that was interrupted
  never writes one, so the activity rule still applies to it — and an agent never outlives the
  session it was started from.
- **The metadata file may not be there** — around one agent in forty on this machine. The row
  stays, with the plain word "Subagent" for a name.
- **The window size is inherited.** The metadata names a `model` only when one was set for the
  agent (`inherit` being a fork saying it kept the session's), and that is the signal: no model
  named means the session's window, a named one means the size is unknown. An alias like `opus`
  cannot be matched against the identifier of a variant (`claude-opus-5[1m]`), and the model on
  an agent's own lines never carries the variant either — so a percentage would be a percentage
  of somebody else's window. The model written on the agent's lines is the safety net under
  that: if it disagrees with the session's, nothing is inherited.

`/clear` starts a new transcript file, so a cleared session reads as a new session with no
context yet. The old file does *not* simply age out: `/clear` writes the finished session's
cost into it as a last line, which touches the file and makes the activity rule count it as
being worked on for another half hour — the session that has just ended sitting in the panel
beside the one that replaced it, looking equally alive.

That same line is how they are told apart. A transcript is over when its last `cost-state`
line comes after the last line of the conversation (`user` or `assistant`): resuming a session
appends messages after the marker and the session counts again, while the housekeeping lines
that can follow it carry no message and leave it closed. Codex has no equivalent — a rollout
ends on `task_complete`, which is the end of a turn, not of the session — so there the
activity rule is still the only answer.

## Reading the ends of a large file

Rollouts and transcripts reach hundreds of megabytes. `FileTail` reads the end of one —
512 KB for a rollout, 1 MB for a transcript — and drops both the first and the last incomplete
line: the first because the window starts in the middle of one, the last because a file being
appended to right now ends in half a line rather than in a broken one.

Each reader widens once when the first window did not answer: 8 MB for a rollout, 16 MB for a
transcript, and only for the number that was missing. The tokens held are always on the last
line; it is the beginning of a long turn that can be far back, and a long turn is exactly the
one whose growth is worth showing. `FileTail.headLines` reads the other end for Codex's
`session_meta`, which carries the whole system prompt and runs to tens of kilobytes on its own.

Which files are opened at all is the activity rule's decision, applied to the modification date
before anything is read. A refresh therefore costs what is running, not what the machine has
stored.

## Reading only what changed

The activity rule decides which files are worth opening. `FileMemory` decides which of those
have anything new to say, and that is a second question with an answer of its own: a turn is
dozens of file system events, every one of them a line appended to *one* file, and a pass used
to re-read every active file from the beginning whichever one had moved. Measured on a set of
six sessions: one pass cost 1.2–1.4 s of CPU, and a working agent held the app at a third of a
core with nothing on screen changing. Measured again on twenty real transcripts: a pass that
finds nothing changed now costs 0.005 s against 1.27 s, and a pass where one file grew costs
0.08 s — the price of what moved, which is the whole point.

**A file is the same file when its identifier, its size and its modification date all are.**
The date carries nanoseconds on APFS (`1787242588.223001172`), so appending always moves it;
the identifier (`fileResourceIdentifier`, the volume id and the inode) is what catches a file
deleted and written again under the same name, which keeps neither. Any one of the three
differing means the file is read again from scratch — grown, shortened or replaced alike.

**A hit is never a way of being out of date.** The bytes behind a matching stamp are the bytes
that were read, so a remembered answer is what a re-read would have said — including
`.unavailable`, which is a verdict on a file and not a failure to reach one. Nothing here ever
holds a stale reading back as better than none.

**What a later line cannot change is remembered by identity alone.** The directory a session
started in comes from the *first* `cwd` in the transcript, so appending cannot move it — and
finding it costs a quarter of a megabyte and a JSON parse per line, on every pass, for the same
answer. It is kept until the file is not that file any more. A head with no `cwd` in it yet is
not remembered at all: a transcript one line long would otherwise keep its fallback name for
as long as it lives.

**Nothing bounds it but the walk.** Entries are made only for files a walk found, and the walk
is bounded — the newest `filesToScan`, plus the subagents of each active session. At the end of
a pass, everything that pass did not ask about is dropped, so a session that ended or fell off
the list leaves no record. There is no size to tune, no expiry to get wrong, and nothing is
written to disk: the memory lives in the process and dies with it.

**The trap underneath all of this: a `URL` caches the resource values it is asked for.** One
kept from an earlier pass answers with the size the file had when it was first asked —
measured, `size=2` for a file that had grown to 200 bytes. A memory built on such a `URL` would
never see a change at all. So the stamp is taken during the walk, off the `URL` the enumerator
has just made, and the walk asks for date, size and identifier together so that one `stat`
answers the whole of it.

The reader has to outlive a pass for any of this to be worth anything, which is why `UsageModel`
owns one `UsageReader` for the life of the app instead of making one per refresh.

## Noticing that something changed

Both CLIs append to a file as a turn ends, so the end of a turn is a file system event and
nothing has to be polled for it. `SourceWatcher` watches the three trees with FSEvents and says
only *that* something changed — which files to re-read is decided where it was already being
decided, from modification dates.

Two details that are not obvious from the API:

- **A directory that does not exist yet is watched through its parent.** FSEvents resolves a
  path when the stream is created, so a machine that has not run Codex would otherwise need a
  restart once it has. One level up only — above that lies the home directory.
- **Paths are resolved before they are watched.** A watch registered through a symlink never
  fires, and `/var`, `/tmp` and every temporary directory on macOS are symlinks.

## An agent that is not on this machine

Not everyone runs both. `UsageReading.installed` answers that separately from every reading,
from whether the CLI's own directory exists — `~/.claude/projects`, `~/.codex/sessions`. The
distinction it draws is between two absences that used to look identical:

| On disk | What it means | What the panel says |
| --- | --- | --- |
| no directory | the agent is not on this machine | "Not installed on this Mac — nothing to connect." |
| a directory, no files | the agent is here and has not answered yet | "No Codex sessions yet — one appears the first time Codex answers." |

An empty tree is deliberately *installed*: telling someone to install what they already have is
the worse of the two mistakes. The readers themselves do not draw this line — for them both are
`.noData`, because the difference is about the machine and not about a file.

## Being the status line command

The only source on the list that has to be connected, and the only place this app writes into
something another program will run. Claude Code calls the status line command after every
answer with a JSON payload on stdin; `rate_limits` and the size of the context window exist
there and in no file on the machine.

`StatusLineMode` is the app in that role. It saves the payload under `claude-status/`, one file
per session, written through a temporary file because the panel reads the directory whenever it
likes and half a payload would read as a format that changed. Then it answers what should be
printed — either the output of the command that held the slot before, byte for byte, or a
`Reading` for the app's own line.

Three rules hold it together, and each one is somebody else's problem if it breaks:

- **The slot is one, and it was theirs first.** A command found in `previous-statusline` is run
  with the same payload and its output is passed on unchanged. Taking the slot takes nothing
  away.
- **Nothing here fails.** Claude Code takes the exit code and the stdout of this command on
  every turn, so a payload that will not parse is simply not written — rather than written
  broken, which the panel would go on to report as a source that changed format.
- **The session id is checked, not trusted.** It becomes a file name and it comes from outside;
  anything that is not a plain name is filed under `unknown-session`.

The line the app prints for itself is `StatusLineText`, in `Phrasing` — this module decides
what happened, that one decides what English it is said in.

## Taking the slot, and giving it back

`StatusLineSlot` is the other half: what puts the command above into
`~/.claude/settings.json` and what takes it out again. It is the one file this project writes
that belongs to somebody else, and three things follow from that.

**Nothing is written without being shown first.** `change(for:)` returns a `StatusLineChange` —
the file, the line going in, the command being displaced — and writes nothing. The panel puts
that in front of the person, and only `apply` writes. There is no path here that edits the file
and reports afterwards.

**The file is edited as text, not re-serialised.** Reading it back out through
`JSONSerialization` changes three things nobody asked to change — it loses the order of the
keys, escapes every slash in every path, and puts a space before every colon. Measured on the
real file on this machine: a one-key edit came back as a diff across two hundred lines. So
`JSONText` scans for where the value of the key sits and replaces those bytes; everything
around them is copied across untouched, including anything else inside `statusLine` such as
`padding`. A file that does not parse is refused outright — replacing somebody's configuration
with a guess about what they meant is worse than saying so and stopping — and a copy is kept
beside the file before every write, the way the shell installer this replaces did it.

**The slot is one and it was theirs first.** A command found in it is saved to
`previous-statusline`, which is the same file `StatusLineMode` reads to know whom to pass the
payload on to; disconnecting puts it back and forgets it. Disconnecting a slot that is *not*
the app's does nothing at all: without that guard, an empty saved file would read as "put
nothing back" and take somebody's own status line away.

The command written into the slot ends in `|| true`. It names a binary inside the app bundle,
and the day that bundle goes to the trash without being disconnected first, the alternative is
an error at the bottom of every turn instead of an empty status line.

**A slot holding this app's own command from another copy is a case of its own.** Two ways it
happens: the release that had an installer put a shell wrapper in Application Support and its
path in the slot, and a second copy of the binary — a build directory beside an installed
bundle, an app dragged somewhere new — writes a command naming its own path. Either way
`state()` answers `.oursElsewhere` rather than `.somebodyElse`, and connecting neither saves it
nor drops what is underneath: one line of `settings.json` changes, and the orphaned script is
deleted if that is what was there.

Telling those two apart is not a nicety, and this is not theory. Saved as "the command that was
here before", that copy's command goes into the file **every** copy reads — so the app calls
itself, reads the same file, and calls itself again. It happened here on 2026-09-16, with a
build directory and an installed bundle both on disk: two thousand processes in seventy seconds
and a panel announcing every context jump they wrote.

The recognition is by two questions. The path of `statusline-wrapper.sh` in this app's own
directory, written bare or single-quoted — the two spellings that installer produced. Or, for a
copy of the binary, `StatusLineMode.isOwnInvocation`: the private `--status-line` argument and
this app's executable name, both in the one command. Either alone would answer yes to somebody
else's tool that takes a flag of the same name or mentions this app in a path.

The same question is asked once more, on the way out of the file: a `previous-statusline` that
names this app — written by an older build, or by hand — is read as nothing saved, by both
`StatusLineSlot.savedCommand()` and the mode itself. A file that cannot be fixed by a rule in
one place should not be able to start the loop from the other.

Because limits keep arriving all the while, this is the one offer the panel makes *underneath*
a working reading rather than in place of a missing one — `StatusLineSlotState.needsTakingOver`
against `isConnectable`.

The state and the change are `SessionHealthCore`'s types (`StatusLineSlotState`,
`StatusLineChange`) and the English is `Phrasing`'s (`SlotPhrasing`), for the reason everything
else here is split that way.

## Before there is anything to read

`SetupInspector` answers the one question that comes before every reading: has each source
written anything at all. It is not a fourth reader — it opens nothing and parses nothing, it
only looks for one file of each kind. The difference it draws is the one a person needs on the
first day: a source that has never written is either waiting for the CLI to be used, or waiting
for the slot to be connected, and those call for different reactions. What that turns into
on screen is the first-run window; the words are `Briefing`'s, in `Phrasing`.

`WelcomeRecord` sits next to it for the same reason — it is the other question about the
machine rather than about a reading: whether that explanation has already been shown.

## Using it

```swift
let reader = UsageReader()                              // kept, not made per pass — see above
let reading = reader.read(config: load.config)

switch reading.claudeLimits {
case .value(let snapshot):     show(snapshot)           // snapshot.observedAt is its age
case .noData(let explanation): show(explanation)        // e.g. nothing has reported yet
case .unavailable(let reason): show(reason)
}

reading.sessions(of: .codex).value ?? []                // an empty list means nothing is running
```

Every store takes the directory it reads as an initialiser argument, which is how the tests
run against fixtures instead of against whatever the machine happens to have.

## Files

| File | Holds |
| --- | --- |
| `SourceReading.swift` | The three outcomes every reader returns |
| `UsageReader.swift` | Both services read at once, and the join between the two Claude sources |
| `CodexRollouts.swift` | Codex limits and Codex sessions, out of the rollouts — including whether one is waiting on its agent |
| `ClaudeTranscripts.swift` | Claude sessions and the subagents running inside them, out of the transcripts — including whether one is waiting on its agent |
| `ClaudeStatus.swift` | Claude limits and window sizes, out of the payloads the status line command leaves |
| `StatusLineMode.swift` | The app run as that command: the payload saved, and the command that held the slot before called |
| `StatusLineSlot.swift` | Getting into Claude Code's one status line slot and back out of it, keeping whatever was there |
| `ClaudeSettings.swift` | `~/.claude/settings.json`: what it says about the slot, and the only writes this app makes to it |
| `JSONText.swift` | Setting one key of a JSON file without rewriting the rest of it |
| `SessionFiles.swift` | Finding the files a service has most recently written, and telling a session's transcript from a subagent's |
| `FileTail.swift` | Reading the ends of a large file without loading it |
| `FileMemory.swift` | What a file said while it still looks the way it did when it said it |
| `Timestamps.swift` | The one way a written moment is read, shared by both readers |
| `SourceWatcher.swift` | Noticing that one of the trees changed, which is how a finished turn is noticed |
| `Setup.swift` | Which sources have written anything at all, and whether the first run has been explained |

Tests: `Tests/SessionHealthTests/`, run with `swift run SessionHealthTests`.
