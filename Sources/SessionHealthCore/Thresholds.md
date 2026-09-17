# The threshold config

`Resources/thresholds.json` holds every number the rules compare against. It is a data file,
not code, for one reason: these numbers change faster than anything around them, and a mark
that cannot be corrected without a rebuild will eventually be wrong and stay wrong.

When and how to update it is in `AGENTS.md` at the repository root. This file describes the
format and where the current numbers came from.

## One scale, everywhere

Both lights of both services are read against the same three marks: **40% / 60% / 90%** of a
window. The window is a subscription limit under one light and a session's context under the
other, and a colour means the same thing under either. That is the point of a scale — a reader
should not have to remember which light counts differently.

| Colour | Past | Says |
| --- | --- | --- |
| green | — | nothing worth a glance |
| yellow | 40% | this has started to fill up. **Never notifies** |
| orange | 60% | worth saying once |
| red | 90% | worth acting on |

Yellow is deliberately silent. Nearly every session passes this mark, and a notification there
would teach the reader to ignore the ones that matter. It sat at 30% until 2026-09-15 and was
raised to 40% for the same reason it does not notify, one step further: a third of a window —
of a session's context or of a subscription window — is so ordinary that a colour there says
nothing by the time it is lit.

A limit window with nothing left is drawn as a **cross**, not a fourth colour: red says the end
is close, and a spent window says the work has stopped. That is arithmetic rather than a mark,
so it is not in the config.

## What the marks claim, and what they do not

The premise is the whole claim: **the fuller a window, the more of it is history nobody needs
any more, and the more of it there is, the more the model works around it.** That is a
direction, not a measurement, and the config does not pretend otherwise.

There is no mark here for "the context got too long". There was one — Anthropic's 150K
compaction default — and it is gone. Not because the number moved: it is still documented, and
it was re-checked on 2026-09-15. It is gone because it is a statement about when the API
compacts, not about when a model answers worse, and this widget kept presenting it as the
second thing.

Nothing published supports an absolute mark for the current generation of models:

- The vendor's own position is the opposite. Anthropic documents Claude Opus 5 as holding
  "consistent instruction following, tool calling, and reasoning throughout the window".
- Independent long-context measurements exist only for earlier models, and they do not carry
  over. On MRCR v2 at 1M, Opus 4.6 scores 76–78% and Opus 4.7 scores 32.2% — two adjacent
  versions from one vendor, a factor of two apart.
- Where an effective limit has been measured across task types (MECW, arXiv 2509.21361), it
  lands so low and varies so much by task that a mark built on it would be lit permanently.

So the marks measure what the app can actually read: how full the window is.

## Where the file is read from

In order:

1. `$LLM_INFORM_BUREAU_THRESHOLDS`, if set — used by the tests and when running against a
   working copy. It is the only way the app ever reads a *config* that is not its own, and it
   takes the whole of one: a run that names a file reads that file and no choices.
2. The copy inside the app — what every ordinary run uses.
3. `ThresholdConfig.builtIn` — the values compiled into the app, in case even the shipped
   copy is unreadable. A test fails if they ever drift from the shipped file.

On top of whichever of those was read come **the marks the person moved themselves**, in the
settings window behind the gear: both scales, each on a bar of its own, and the three marks
that are one number of minutes — how long a wait goes on expecting an answer, how long a
request for the person stands before it is announced, and how long a session stays on the list.
The quiet rule about a limit window about to reset is not among them: nothing there is anybody's
choice, it only keeps the app from interrupting somebody over a window that comes back on its
own.

In the file both scales ship as the same three numbers on purpose, and what a person does with
them afterwards is their own: a full context and a spent quota are different dangers, and
somebody who wants to hear about them at different points is choosing their own colour language
rather than breaking a rule. One scale for both **services** is the rule, and it is not theirs
to change.

**There is no editable copy of this file in Application Support**, nothing is created on a first
launch, and one left behind by the release that had an installer is not read. Nobody was going
to hand-edit JSON to move a percentage. What Application Support does hold is
`chosen-thresholds.json` — the *choice* and nothing else: which mark was moved and where to
(`ThresholdChoices`). That is the difference that matters on an update. A copy of the config
with one number changed would freeze every later improvement at the release somebody happened
to edit, and a change of format would throw their number away with it; a choice against a named
mark survives both, and every mark they left alone arrives new with the app.

A moved mark loses the rationale that shipped under it. The sentence was written about a
different number, and leaving it there would be the app justifying a mark nobody measured —
the one thing the rules below forbid. Nothing is written in its place: the window puts a "Reset
to default" button beside a mark that is not where the app had it, which says the same thing
and also undoes it.

Inside the app the file travels in SwiftPM's resource bundle, in `Contents/Resources`, and
`ThresholdConfigLoader.bundledConfigURL` is what finds it there. Not `Bundle.module`:
SwiftPM's accessor looks beside the `.app` and at the absolute path of the build directory,
which on anybody else's Mac is neither, and it calls `fatalError` rather than returning nil.
`build-app.sh` fails the build if no bundle with the file in it was packed.

## A broken file is the author's problem, not the reader's

Nothing in the loader throws. Each entry is read on its own, and an entry that is missing,
malformed or self-contradictory (marks out of order, a percentage above 100) falls back to the
copy below it while the rest of the file is still used. Every substitution shows up in
`load.problems` — for whoever is editing the file, which is the author with the test suite in
front of them. The panel shows none of it.

A `version` that is not the one this app reads makes the whole file fall back, because a
changed schema means the keys no longer mean what they used to — and it does so without a
word anywhere. Version 3 — two marks per light, plus the Claude token mark — is exactly that
case, and it is covered by a test.

## Format

```json
{
  "version": 7,
  "context": {
    "window_fill_percent": { "notice": 40, "elevated": 60, "high": 90, "rationale": "…" }
  },
  "limits": {
    "percent": { "notice": 40, "elevated": 60, "high": 90, "rationale": "…" },
    "quiet_when_window_remaining_percent": { "remaining_percent": 5, "rationale": "…" }
  },
  "sessions": {
    "active_within_minutes": { "minutes": 30, "rationale": "…" },
    "abandoned_wait_after_minutes": { "minutes": 10, "rationale": "…" },
    "attention_notice_after_minutes": { "minutes": 2, "rationale": "…" }
  }
}
```

- `notice`, `elevated` and `high` are one ascending scale, all exclusive: a reading sitting
  exactly on a mark has not crossed it. `notice` colours a light and never notifies.
- `rationale` is required of every entry and is written for the next person to edit the file:
  what the number is, and what it follows from.
- `measurement` is optional, and its absence is the point: an entry without one is a number
  nobody measured, and the app can say so rather than implying a source it does not have.
  **Every entry in the shipped file is currently without one**, and that is not an oversight.

## Where the current numbers came from

| Entry | Value | Where it comes from |
| --- | --- | --- |
| `context.window_fill_percent` | 40 / 60 / 90 | **Ours.** The red one is placed against a published fact rather than derived from it: Claude Code compacts at about 967K on a native 1M window and at the 200K boundary on a 200K one ([model-config](https://code.claude.com/docs/en/model-config), checked 2026-09-15), so 90% is the last point at which a warning arrives before the CLI rewrites the session itself. Codex configures its own compaction point and does not publish it. |
| `limits.percent` | 40 / 60 / 90 | **Not measured.** The same scale as the context, so a colour means one thing everywhere. The 60 / 80 this replaces was ours too, and the yellow mark moved 30 → 40 on 2026-09-15 together with the context scale. |
| `limits.quiet_when_window_remaining_percent` | 5 | **Not measured.** Below this share of a window's own length, its marks stay quiet: a window about to come back on its own is not worth interrupting anyone for. A share rather than a number of minutes, because five hours and a week are not comparable in absolute time. |
| `sessions.active_within_minutes` | 30 | **Not measured — a sensible default.** Thirty minutes is where a session being worked on stops looking like one that is finished. |
| `sessions.abandoned_wait_after_minutes` | 10 | **Not measured — a sensible default.** A session owing an answer this long without a word stops being one an answer is expected out of: the light stops blinking and is drawn as a figure eight. It only has to be longer than the longest silence inside a turn that is really running, and short enough that nobody watches a dead session blink. |
| `sessions.attention_notice_after_minutes` | 2 | **Not measured — a sensible default.** How long an agent may be waiting on the person before a notification says so. The pause sign appears at once; only the notification waits, so that a question answered at the keyboard is never announced at all. Two minutes is about as long as somebody sitting at the terminal takes to answer by themselves. |

Not one of the seven carries a `measurement`, and that is the honest state of this subject
rather than a gap to be filled. The alternative — inventing a date and a link so every field
looks equally solid — is exactly the silent lie `AGENTS.md` forbids.

## The three entries that are not marks

`sessions.active_within_minutes` decides which sessions the widget lists, not what it warns
about. It is here because it has the same problem as the marks: it will need correcting, and a
number in the code cannot be corrected without a rebuild. Correct it if sessions that are
running drop off the list, or finished ones linger on it.

`sessions.abandoned_wait_after_minutes` decides how long a light goes on blinking for an answer
that may never come — and what it does afterwards, which is not to go steady but to become a
figure eight. Nothing on disk says a session died: a closed terminal, a killed process
and an agent hard at work all leave the same thing behind — an entry owing an answer and
nothing after it — so the only thing separating them is how long ago that entry was written.
The silence is counted from the last entry of the conversation and never from the file's date:
measured on this machine, a transcript's modification date runs ahead of the last thing said in
it by a median of a minute and a half, and by more than ten minutes in 87 files of 385, because
housekeeping keeps touching a file long after the conversation in it stopped.

Those two are deliberately far apart, and the shorter one is the blink. A session that has gone
quiet is still a session being worked on and keeps its row for the full half hour; what it
loses after ten minutes is only the claim that an answer is on its way. The answer is still
owed, the sign says so, and nothing here decides when that stops being true — an answer
arriving does, or the half hour running out.

`sessions.attention_notice_after_minutes` decides nothing about a light at all: the pause sign
is drawn the moment the agent asks for something, and this is the delay on the notification
alone. The delay is the whole of the rule — under it no alert is made, so a question the person
answers without leaving the terminal is never announced rather than announced and then taken
back. Waits on the person were counted while this was placed — 215 of them on the machine it
was written on, half answered inside 64 seconds and a quarter running past five minutes — and
that count lives in the task's research rather than here, for the reason step 4 of "How to
update" gives. What makes the number wrong is visible from the outside, and that is what is
worth saying: notifications about questions you were about to answer anyway means it is too
short, learning about a question long after it was asked means it is too long.

Unlike the fuse above, nothing here expires. A request does not go stale — the person simply
has not come back yet — so one wait is announced once, however long it stands, and the next
request in the same session is announced again as the new thing it is.

## What is no longer here

- **A table of context-length thresholds per model**, derived from published MRCR retention
  figures. Half of it had no vendor equivalent, the two models this app's author uses had no
  published measurement, and one honest number beat a table with nothing under it.
- **`context.claude_recommended_tokens`** — Anthropic's 150K compaction default. Re-checked and
  still documented; removed because it says when the API compacts, not when answers get worse,
  and the widget was using it as the second thing. See "What the marks claim" above.
- **Two marks per light.** Yellow and red had to carry three meanings between them — starting
  to fill, worth saying, act now — and the middle one always lost.
