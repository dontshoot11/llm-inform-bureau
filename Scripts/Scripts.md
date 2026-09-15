# Scripts

Four scripts: one installs everything, one builds the app, two connect it to Claude Code.

| Script | Run by | Does |
| --- | --- | --- |
| `install.sh` | a person | Shows the whole installation as a plan, and with `--apply` carries it out |
| `build-app.sh` | a person | Builds the `.app` bundle, and with `--run` restarts it |
| `install-statusline.sh` | a person | Shows what connecting the wrapper would change, and with `--apply` does it |
| `statusline-wrapper.sh` | Claude Code | Saves each statusLine payload for the app, and calls whatever command was there before |

## Installing the whole thing

```sh
Scripts/install.sh            # prints the plan and changes nothing
Scripts/install.sh --apply    # carries it out
```

Five steps, each printed before any of them happens: build the bundle, install it to
`/Applications`, put an editable copy of the thresholds in Application Support, connect the
statusLine wrapper (by running `install-statusline.sh`, whose own plan is printed inside this
one), and start the app.

Two of the steps refuse to repeat themselves: an existing `thresholds.json` is left exactly as
it is — it is the one the app reads, and overwriting someone's edited marks during an update
would be the worst thing this script could do — and the wrapper step says "already connected"
rather than saving the wrapper as its own predecessor.

Starting with the Mac is not done here: it is a checkbox, offered in the window the app opens
on its first run and afterwards in the panel. `SMAppService` registers the bundle where it is
at that moment, which is why the app is copied to `/Applications` first and started from
there.

## Why a wrapper at all

Claude's subscription limits and the size of its context window are handed to the statusLine
command and to nothing else — there is no file under `~/.claude` that carries them. Reading
them means occupying that slot.

**There is exactly one slot.** So the wrapper is a wrapper and not a replacement: whatever
command was configured before is saved, and the wrapper calls it with the same payload on
stdin and prints its output unchanged. A person who already has a status line keeps it.

```
Claude Code ──payload──▶ wrapper ──┬──▶ ~/Library/Application Support/.../claude-status/<session>.json
                                   └──▶ the command that was there before ──▶ the status line
```

With nothing there before, the wrapper prints a short line of its own — model, context,
limits — rather than leaving the status line blank.

## Installing it

```sh
Scripts/install-statusline.sh            # shows the plan and changes nothing
Scripts/install-statusline.sh --apply    # carries it out
Scripts/install-statusline.sh --uninstall
```

The preview is the point: the script edits `~/.claude/settings.json`, which is the user's file
and holds much more than this one key, so it says what it will copy where, what the current
command is, and where that command will be saved — before doing any of it. `--apply` keeps a
timestamped backup of the settings file next to it.

Two things the preview says out loud because they surprise people:

- **With any statusLine configured, Claude Code stops showing most footer hints**, `esc to
  interrupt` among them. That is Claude Code's behaviour, not this app's, and it is the real
  cost of connecting the wrapper.
- The wrapper is copied into Application Support rather than run from the repository, so
  moving or deleting the working copy does not break the status line. Re-run `--apply` after
  changing the wrapper.

`settings.json` is edited through `python3` — the file is the user's, and a regex edit of
someone else's config is how a working setup breaks silently. The command is written
shell-quoted, because Claude Code runs it through a shell and its path contains a space.

## What the wrapper writes

One file per session, `<session_id>.json`, holding the payload verbatim. Written through a
temporary file and moved into place, so the app never reads half of one. Payloads older than a
day are deleted on the next run: sessions end without saying so.

`~/Library/Application Support/LLMInformBureau/` is the only place this app writes, and it holds
three other things: `previous-statusline` — the command to keep calling — your editable
`thresholds.json`, and `welcome-shown`, the note that keeps the first-run window to one
appearance. Deleting that note brings the window back on the next launch.

## Building the app

```sh
Scripts/build-app.sh        # prints the path of the built .app
Scripts/build-app.sh --run  # and restarts it
```

SwiftPM produces a bare executable; a menu bar app needs a bundle with an `Info.plist` and
`LSUIElement`. The script assembles one, copies SwiftPM's resource bundle with the default
thresholds into it, and re-signs it ad-hoc with the identifier from that plist — the
notification centre ignores a bundle whose signing identifier does not match its
`CFBundleIdentifier`.
