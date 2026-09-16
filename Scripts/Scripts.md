# Scripts

Five scripts: one builds the file that is handed out, one installs what is in it, one builds
the app bundle, two connect it to Claude Code.

| Script | Run by | Does |
| --- | --- | --- |
| `build-dmg.sh` | the author | Builds the disk image that is handed out: the app, the installer and the instructions |
| `install.sh` | a person | Shows the installation of the bundle beside it as a plan, and with `--apply` carries it out |
| `build-app.sh` | the author | Builds the `.app` bundle — with the two scripts below inside it — and with `--run` restarts it |
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

`INSTALL.txt` is written here, as a heredoc, rather than kept as a file to copy: it carries the
version it was built with, and a copy sitting in the repository is a copy that goes out of step
with the script it describes. It is everything the recipient is given in writing — the two
commands and their order, the Gatekeeper dialog and which of its buttons not to press,
connecting the wrapper, updating, removing.

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

The plan opens with the version being installed and the folder it comes from. That line is
there because the volume name is a constant: mount a second image while the first is still
mounted and macOS calls it `LLMInformBureau 1`, so the command from the instructions keeps
finding the old volume and reinstalls the version already there without a word about it. When
the version on the image matches the one already in `/Applications`, the script says so and
names the `hdiutil detach` that fixes it.

Four steps, each printed before any of them happens: install the bundle lying beside the
script to `/Applications`, put an editable copy of the thresholds in Application Support,
connect the statusLine wrapper (by running `install-statusline.sh`, whose own plan is printed
inside this one), and start the app — or, on a copy that came over the network, not start it.

The script installs the bundle **next to itself** and cannot build one: run it where there is
no `LLMInformBureau.app` beside it — in `Scripts/`, for instance — and it says so and stops,
naming the way out. The author installs from the image like everyone else, which is why there
is no second installation path in the repository to keep working.

`sh` in front of the command is not decoration. A file that arrived over the network and is
run directly off the mounted image is blocked by Gatekeeper with a dialog and no output;
handed to an interpreter, it runs.

The statusLine step runs `install-statusline.sh` from beside the script — the repository
layout — or from inside the bundle, where `build-app.sh` puts it next to the wrapper. On a
downloaded image the second is the one that exists, which is what makes connecting the wrapper
part of the recipient's path rather than a step "for developers only".

It is run through `sh` for the same reason this script is: a file executed straight off a
mounted image is stopped by Gatekeeper with a dialog and no output.

Two of the steps refuse to repeat themselves: an existing `thresholds.json` is left exactly as
it is — it is the one the app reads, and overwriting someone's edited marks during an update
would be the worst thing this script could do — and the wrapper step says "already connected"
rather than saving the wrapper as its own predecessor.

**Step 4 does not open a quarantined app.** It reads `com.apple.quarantine` across the copy it
has just made — the whole tree, not just the top of it, to stay symmetric with the recursive
`xattr -d -r` the instructions hand out — and if the mark is anywhere it prints the unlocking
command and stops. This is not
politeness. Opening such a bundle brings up "LLMInformBureau Not Opened", whose default button
is a blue **Move to Trash** — so the most obvious thing to press deletes what was installed a
second earlier. Ending on a command the person can paste is the only way not to leave them in
front of that dialog.

The mark is read from the installed copy and not from the image, because that is where it
matters: it travels with a copy, so clearing it on the image changes nothing about what ends up
in `/Applications`. Running the unlocking command first therefore has nothing to clear, and the
instructions say so.

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

The same script ships inside the app, beside the wrapper, and someone who never had the
repository runs that copy instead:

```sh
sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --apply
```

There is one script and not two because it looks for the wrapper **next to itself**: in the
repository that is `Scripts/`, in the installed app it is `Contents/Resources/`, and neither
layout is named anywhere in it.

The preview is the point: the script edits `~/.claude/settings.json`, which is the user's file
and holds much more than this one key, so it says what it will copy where, what the current
command is, and where that command will be saved — before doing any of it. `--uninstall` prints
its own plan the same way — what goes back into the slot — and acts straight away rather than
waiting for `--apply`, because putting something back is what it is for.

**`--uninstall` only ever removes this app's wrapper.** If the slot holds something else, or
nothing, it says so and exits without writing: the saved predecessor is deleted once it has been
restored, and an empty one means "remove the key", so an unguarded run would take away the
command it had just put back — or, on a Mac where the wrapper was never connected, somebody
else's. Both writes keep a copy of the settings file beside it, named for the timestamp **and
the operation** (`settings.json.backup-20260916134639-apply`): the two run back to back land on
the same second, and a name without the operation would let the second copy overwrite the first,
which is the one holding the original command.

Two things the preview says out loud because they surprise people:

- **With any statusLine configured, Claude Code stops showing most footer hints**, `esc to
  interrupt` among them. That is Claude Code's behaviour, not this app's, and it is the real
  cost of connecting the wrapper.
- The wrapper is copied into Application Support rather than run from the repository, so
  moving or deleting the working copy does not break the status line. Re-run `--apply` after
  changing the wrapper.

`settings.json` is edited through `osascript -l JavaScript` — the file is the user's, and a
regex edit of someone else's config is how a working setup breaks silently, so it is parsed,
changed and written back whole. It used to be `python3`, and that is exactly the kind of
dependency the disk image cannot have: `/usr/bin/python3` is a Command Line Tools shim, and on
a Mac without them it opens an installer dialog instead of working. `osascript` is part of
macOS. The command is written shell-quoted, because Claude Code runs it through a shell and its
path contains a space.

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

`statusline-wrapper.sh` and `install-statusline.sh` are copied into `Contents/Resources` on the
way, because on the receiving Mac the bundle is the only copy of this repository there is. They
go in **before** the signature, which covers `Resources`: adding them afterwards would break it.

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
