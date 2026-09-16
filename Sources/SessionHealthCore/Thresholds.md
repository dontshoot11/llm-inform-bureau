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
   working copy.
2. `~/Library/Application Support/LLMInformBureau/thresholds.json` — the installed copy.
   Editing it changes behaviour on the next read, with no rebuild.
3. The copy inside the app bundle — the floor, so a fresh install works before anything has
   been installed.
4. `ThresholdConfig.builtIn` — the values compiled into the app, in case even the bundled
   copy is unreadable. A test fails if they ever drift from the bundled file.

## A broken file never takes the app down

Nothing in the loader throws. Each entry is read on its own, and an entry that is missing,
malformed or self-contradictory (marks out of order, a percentage above 100) falls back to the
copy below it while the rest of the file is still used. Every substitution shows up in
`load.problems`, and the dropdown says "default thresholds applied" — the one thing the app
must not do is behave differently from the file the user is looking at without saying so.

A `version` that is not the one this app reads makes the whole file fall back, because a
changed schema means the keys no longer mean what they used to. Version 3 — two marks per
light, plus the Claude token mark — is exactly that case, and it is covered by a test.

## Format

```json
{
  "version": 5,
  "context": {
    "window_fill_percent": { "notice": 40, "elevated": 60, "high": 90, "rationale": "…" },
    "expensive_turn": { "window_share_percent": 10, "tokens": 20000, "rationale": "…" }
  },
  "limits": {
    "percent": { "notice": 40, "elevated": 60, "high": 90, "rationale": "…" },
    "quiet_when_window_remaining_percent": { "remaining_percent": 5, "rationale": "…" }
  },
  "sessions": {
    "active_within_minutes": { "minutes": 30, "rationale": "…" },
    "abandoned_wait_after_minutes": { "minutes": 10, "rationale": "…" }
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
| `context.expensive_turn` | 10% of the window **or** 20 000 tokens | **Not measured.** Either ceiling is enough. The absolute one is not a fallback for an unknown window: on a 1M window a tenth is 100K, so a share-only rule went quiet on exactly the longest sessions. |
| `limits.percent` | 40 / 60 / 90 | **Not measured.** The same scale as the context, so a colour means one thing everywhere. The 60 / 80 this replaces was ours too, and the yellow mark moved 30 → 40 on 2026-09-15 together with the context scale. |
| `limits.quiet_when_window_remaining_percent` | 5 | **Not measured.** Below this share of a window's own length, its marks stay quiet: a window about to come back on its own is not worth interrupting anyone for. A share rather than a number of minutes, because five hours and a week are not comparable in absolute time. |
| `sessions.active_within_minutes` | 30 | **Not measured — a sensible default.** Thirty minutes is where a session being worked on stops looking like one that is finished. |
| `sessions.abandoned_wait_after_minutes` | 10 | **Not measured — a sensible default.** A session owing an answer this long without a word is presumed abandoned, and its light stops blinking. It only has to be longer than the longest silence inside a turn that is really running, and short enough that nobody watches a dead session blink. |

Not one of the six carries a `measurement`, and that is the honest state of this subject
rather than a gap to be filled. The alternative — inventing a date and a link so every field
looks equally solid — is exactly the silent lie `AGENTS.md` forbids.

## The two entries that are not marks

`sessions.active_within_minutes` decides which sessions the widget lists, not what it warns
about. It is here because it has the same problem as the marks: it will need correcting, and a
number in the code cannot be corrected without a rebuild. Correct it if sessions that are
running drop off the list, or finished ones linger on it.

`sessions.abandoned_wait_after_minutes` decides how long a light goes on blinking for an answer
that may never come. Nothing on disk says a session died: a closed terminal, a killed process
and an agent hard at work all leave the same thing behind — an entry owing an answer and
nothing after it — so the only thing separating them is how long ago that entry was written.
The silence is counted from the last entry of the conversation and never from the file's date:
measured on this machine, a transcript's modification date runs ahead of the last thing said in
it by a median of a minute and a half, and by more than ten minutes in 87 files of 385, because
housekeeping keeps touching a file long after the conversation in it stopped.

The two are deliberately far apart, and the shorter one is the blink. A session that has gone
quiet is still a session being worked on and keeps its row for the full half hour; what it
loses after ten minutes is only the claim that somebody is waiting on it right now.

## What is no longer here

- **A table of context-length thresholds per model**, derived from published MRCR retention
  figures. Half of it had no vendor equivalent, the two models this app's author uses had no
  published measurement, and one honest number beat a table with nothing under it.
- **`context.claude_recommended_tokens`** — Anthropic's 150K compaction default. Re-checked and
  still documented; removed because it says when the API compacts, not when answers get worse,
  and the widget was using it as the second thing. See "What the marks claim" above.
- **Two marks per light.** Yellow and red had to carry three meanings between them — starting
  to fill, worth saying, act now — and the middle one always lost.
