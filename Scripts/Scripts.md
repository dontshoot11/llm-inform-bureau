# Scripts

Five scripts: one builds the file that is handed out, one installs what is in it, one builds
the app bundle, two connect it to Claude Code.

| Script | Run by | Does |
| --- | --- | --- |
| `build-dmg.sh` | the author | Builds the disk image that is handed out: the app, the installer and the instructions |
| `install.sh` | a person | Shows the installation of the bundle beside it as a plan, and with `--apply` carries it out |
| `build-app.sh` | the author | Builds the `.app` bundle, and with `--run` restarts it |
| `install-statusline.sh` | a person | Shows what connecting the wrapper would change, and with `--apply` does it |
| `statusline-wrapper.sh` | Claude Code | Saves each statusLine payload for the app, and calls whatever command was there before |

Building and installing are two scripts and not one on purpose. Everything that needs a
compiler happens on the author's machine, in `build-dmg.sh`; what the recipient runs only
copies files. That is what makes "download, then two commands" true on a Mac with no Xcode
Command Line Tools on it.

## Building the file that is handed out

```sh
Scripts/build-dmg.sh    # prints the path of the image it built
```

It builds the app, puts it on a disk image beside a copy of `install.sh` and an `INSTALL.txt`,
and writes `.build/LLMInformBureau-<version>.dmg`. The version is read from
`Scripts/Info.plist` — `CFBundleShortVersionString` — so the number in the file name and the
number in the app are one number, and there is no second place to remember to change.

The volume is called `LLMInformBureau`, without spaces, because the recipient's first command
names the mount point and has to survive being retyped.

Before anything is packed the script checks the bundle it was given: the binary carries both
architectures, and the signature verifies. Both of those are only ever wrong on the other
side — an Intel Mac, or a notification centre that quietly refuses — so the check belongs on
the last line where a Mac to test on is still this one.

## Installing it

```sh
sh /Volumes/LLMInformBureau/install.sh            # prints the plan and changes nothing
sh /Volumes/LLMInformBureau/install.sh --apply    # carries it out
```

Four steps, each printed before any of them happens: install the bundle lying beside the
script to `/Applications`, put an editable copy of the thresholds in Application Support,
connect the statusLine wrapper (by running `install-statusline.sh`, whose own plan is printed
inside this one), and start the app.

The script installs the bundle **next to itself** and cannot build one: run it where there is
no `LLMInformBureau.app` beside it — in `Scripts/`, for instance — and it says so and stops,
naming the way out. The author installs from the image like everyone else, which is why there
is no second installation path in the repository to keep working.

`sh` in front of the command is not decoration. A file that arrived over the network and is
run directly off the mounted image is blocked by Gatekeeper with a dialog and no output;
handed to an interpreter, it runs.

The statusLine step runs `install-statusline.sh` from beside the script or from inside the
bundle. Neither is on the image yet — the wrapper still lives only in the repository — so from
a downloaded image that step says it is skipping and the rest of the installation finishes.

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

## Connecting the wrapper

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

**The binary is universal**, `arm64` and `x86_64`, because the image goes to a Mac that may be
an Intel one and there is no Intel Mac here to find that out on. It is built twice, once per
triple into a scratch path of its own, and the two are joined with `lipo`. Not
`swift build --arch arm64 --arch x86_64`: that flag drives xcbuild and fails on the Command
Line Tools with `xcbuild executable ... does not exist`, and the Command Line Tools are all
this package asks for. A build takes about twice as long as it used to, which is the price.

The Intel half has an expiry date, and macOS says so. Running it on Apple Silicon — which only
happens if it is forced, with `arch -x86_64` — brings up "Support Ending for Intel-based Apps",
because Apple has announced the end of Rosetta. Nobody on Apple Silicon sees that in ordinary
use: the `arm64` half runs and Rosetta is not involved. Someone on an Intel Mac will, and
fairly. When Rosetta goes, `x86_64` goes out of the image with it.

Two orderings inside the script are load-bearing:

- **Signing comes after `lipo`.** `lipo` writes a new binary; a signature applied before it is
  simply gone, and `codesign -v` stops passing.
- **The resource bundle is copied from the `arm64` build.** It holds no code, so the two builds
  produce the same one — the choice is arbitrary, not meaningful.
