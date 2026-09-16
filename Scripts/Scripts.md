# Scripts

Two scripts, both the author's: one builds the app bundle, one builds the file that is handed
out. Nothing here is run by the person who receives the app — they drag a bundle into
`/Applications` and run one command, and the app does the rest of its setting up itself.

| Script | Run by | Does |
| --- | --- | --- |
| `build-dmg.sh` | the author | Builds the disk image that is handed out: the app and the instructions |
| `build-app.sh` | the author | Builds the `.app` bundle and, with `--run`, restarts it |

There used to be three more — an installer, a statusLine installer and a shell wrapper Claude
Code ran. All three are gone, and so is most of what they did: the marks the app watches ship
inside it and are nobody's to install, and the status line slot is taken from the app's own
panel, which shows the edit to `~/.claude/settings.json` before making it. See
[AgentFiles.md](../Sources/AgentFiles/AgentFiles.md) for the slot and
[Thresholds.md](../Sources/SessionHealthCore/Thresholds.md) for the marks.

That is the point of the arrangement, not a tidying-up. The old path asked somebody to run two
hundred lines of someone else's `sh` against their own machine, and the only way to judge it
was to read them. What replaces it is a gesture macOS already taught them and a change they are
shown before it happens.

## Building the file that is handed out

```sh
Scripts/build-dmg.sh    # prints the path of the image it built
```

It builds the app, puts it on a disk image beside an `INSTALL.txt`, and writes
`.build/LLMInformBureau-<version>.dmg`. The version is read from `Scripts/Info.plist` —
`CFBundleShortVersionString` — so the number in the file name and the number in the app are one
number, and there is no second place to remember to change.

`INSTALL.txt` is written here, as a heredoc, rather than kept as a file to copy: it carries the
version it was built with, and a copy sitting in the repository is a copy that goes out of step
with the script it describes. It is everything the recipient is given in writing — mounting the
image, the drag, the one command and why it comes after the drag, the Gatekeeper dialog and
which of its buttons not to press, the first run, connecting Claude's limits from the panel,
updating, removing.

It has been read once from the outside — by a reader given this text and nothing else, no
repository behind it — and the gaps that reading found are closed here: the image has to be
mounted before anything names a volume, the quarantine command has to name the installed copy
and not the one on the image, and after it nobody has started the app, so the text says to.

The volume is called `LLMInformBureau`, without spaces, because it is named in the instructions
and has to survive being retyped.

What the image cannot carry is the step that opens it: a person holding a `.dmg` has nowhere to
read "mount this first". That part travels in the message with the link, and the text to paste
there is kept in README, under [What to send with the link](../README.md#what-to-send-with-the-link).

Before anything is packed the script checks the bundle it was given: the binary carries both
architectures, and the signature verifies. Both of those are only ever wrong on the other
side — an Intel Mac, or a notification centre that quietly refuses — so the check belongs on
the last line where a Mac to test on is still this one.

## Building the app

```sh
Scripts/build-app.sh        # prints the path of the built .app
Scripts/build-app.sh --run  # and restarts it
```

SwiftPM produces a bare executable; a menu bar app needs a bundle with an `Info.plist` and
`LSUIElement`. The script assembles one, copies SwiftPM's resource bundle with the marks into
it, and re-signs it ad-hoc with the identifier from that plist — the notification centre
ignores a bundle whose signing identifier does not match its `CFBundleIdentifier`.

**The build fails if that bundle did not get packed.** It is the only copy of the marks the
app has, and `Bundle.module` would have found the one in the build directory and run
perfectly — here, and nowhere else. `ThresholdConfigLoader.bundledConfigURL` is the other half
of that; `Thresholds.md` has the measurement.

Nothing else goes inside the bundle. The same binary is also Claude Code's status line command
(`LLMInformBureau --status-line`), so there is no script for it to carry, and the marks it
watches travel in the resource bundle.

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
