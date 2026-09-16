# AGENTS.md

Instructions for AI agents working in this repository.

## Language

- README, in-app strings, issue and PR text: **English**.
- Planning documents under `TODO/` (git-ignored): Russian.

## Updating the thresholds

The widget compares what it reads to four marks — the context scale, the limit scale, an
expensive request and a limit window about to reset — and decides which sessions to list by a
fifth number. Every one of them lives in
`Sources/SessionHealthCore/Resources/thresholds.json`, not in the code. The format and where
the current numbers came from are documented in `Sources/SessionHealthCore/Thresholds.md`.
Keeping them current is a deliberate, human-reviewed step, not an automated fetch.

The two scales are one scale: both lights of both services run 40 / 60 / 90. Changing one of
them and not the other makes a colour mean two things, which is the thing the scale exists to
prevent — so change both, or neither.

**The app never fetches anything at runtime.** It works offline and holds no credentials.
Threshold updates land in the repository as commits.

### When to update

- A vendor moves where its CLI compacts. The red mark sits just below that point, and if
  Claude Code stops compacting near the end of the window, 90% stops meaning "last warning".
- Somebody finally publishes a measured length at which the current generation of models
  answers worse. That would be a reason to add a mark back, not to move one — see
  `Thresholds.md`, "What the marks claim, and what they do not".
- Experience corrects a number the config admits it never measured: the expensive-request
  ceilings, the limit percentages, and the share of a window that counts as "about to reset".
- The session-activity window stops matching how the machine is used — sessions that are
  running drop off the list, or finished ones linger on it.
- More than ~3 months passed since the `measured_at` date of an entry that has one.

### How to update

1. Change the number in the config, and change `ThresholdConfig.builtIn` to match — a test
   fails if the two drift apart. The built-in copy is the floor under a corrupted bundle,
   not a second source of truth.
2. Rewrite that entry's `rationale` in the same commit. It is one sentence, written for the
   next person: what the number is and what it follows from.
3. Add `measurement` **only** when there is a published source with a date. An entry without
   one is honest and the interface can say "not measured"; an entry with an invented source
   lies silently and nothing will ever catch it.
4. **Do not justify a number by what this machine looks like.** The app is meant to be handed
   to other people, and a threshold tuned to one person's sessions means something else on
   theirs — silently, because nothing about it looks wrong. A measurement taken here is a
   reason to go looking for a published one, not a rationale to ship: say "not measured — a
   sensible default" and describe what would make it wrong, so the next person can tell.
5. Do not add a number for something nobody published. Every mark in this config is ours, and
   the file says so; a `measurement` on any of them would be an invented source, and nothing
   downstream could catch it.
6. Changing the shape of the file — a new entry, a renamed key — means raising
   `ThresholdConfig.currentVersion` and the `version` in the file together, because the app
   falls back wholesale on a version it does not read.

   Nobody has to be told: the file ships inside the app and is the only one it reads. A copy
   in Application Support, left over from the release that had an installer, is not read at
   all, and the panel says nothing about any of it — a reader who never chose a number has
   nothing to do about one. Choosing them from the app's own settings is a task of its own
   (`TODO/thresholds-in-settings/`).

   To run against marks other than the shipped ones, name a file:
   `LLM_INFORM_BUREAU_THRESHOLDS=/path/to/thresholds.json`. That override is the only way
   anything else is read, and it is for the tests and for a working copy.
7. Commit the config change on its own, with the source in the commit message.

### Running this as an agent task

Either CLI can do the update non-interactively. The user runs the command; the app never
runs it on its own.

```sh
claude -p "Follow AGENTS.md: check whether Claude Code still compacts near the end of the \
context window and at the 200K boundary, update the threshold config and its rationale if \
that moved, and report the source and its date. If nothing moved, change nothing and say so."
```

```sh
codex exec "Follow AGENTS.md: check whether Claude Code still compacts near the end of the \
context window and at the 200K boundary, update the threshold config and its rationale if \
that moved, and report the source and its date. If nothing moved, change nothing and say so."
```

Report what you changed and where the number came from. If you could not find a published
source, say that plainly and leave the config alone — a guessed number is worse than the
one already there.

## What not to do

- Do not add network calls to the app in order to refresh thresholds. `OfflineTests` fails if a
  network API so much as appears in `Sources` — that test is the reason "it works with the
  network off" can be claimed at all.
- Do not hardcode a threshold in the rules. Every mark comes from the config; `BudgetRules`
  compares, it does not decide.
- Do not let a broken config throw. A badly edited file must degrade to the values below it and
  list what it got wrong in `load.problems`, for whoever is editing it — never take the menu
  bar down. Nothing of this reaches the interface: the marks are the app's own, and the panel
  has nothing to say to a reader about them.
- Do not put a file, a setting or a step in front of the reader that the app can do without.
  Installing this app is a drag and one command, and everything it needs it either ships with
  or asks for by a button in the panel.
- Do not present any of this as a measure of answer quality. The widget reports how full a
  window is, and every mark on that scale is the project's own. There is no signal for "this
  session has degraded" in the data the app can read — no vendor publishes one, and the
  measurements that exist are for older models and disagree with each other by a factor of
  two. The interface must not imply otherwise.
- Do not argue with a vendor in the interface. The reasoning about what nobody has published
  belongs here and in `Thresholds.md`, where the next person deciding a number will read it.
  What the app says is what a number means — "the window is 92% full, and the fuller it gets
  the more of it is history that weighs on what the model concludes" — not who disagrees with
  whom about it.
- Do not describe a scale the app could show instead. Marks are rendered as the lights they
  turn on, with the percentage beside each dot; a paragraph explaining that 60% is orange asks
  the reader to hold a fact and match it to a colour later, and it goes stale the moment
  somebody edits the config.
