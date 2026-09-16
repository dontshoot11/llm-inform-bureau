#!/bin/sh
# Builds the one file that is handed to someone else: a disk image holding the built app, the
# script that installs it, and the instructions for both.
#
# It exists so that the path to a working app on another Mac is "download, then two commands",
# with no repository, no compiler and no Command Line Tools on that side. Everything that
# needs building happens here, on the author's machine; install.sh on the other side only
# copies what this script packed.
#
# The volume is named without spaces on purpose: the recipient's first command names the
# mount point, and a command with a quoted path in it is a command people retype wrong.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
volume="LLMInformBureau"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Scripts/Info.plist")
staging="$root/.build/dmg/$volume"
dmg="$root/.build/$volume-$version.dmg"

# Progress goes to stderr: the only thing this script writes to stdout is the path of the
# image, so that another script, or a person, can capture it.
echo "Building $volume $version" >&2

app=$("$root/Scripts/build-app.sh")

# Checked here, before anything is packed, because both of these are only ever wrong on the
# other side: a single-architecture binary fails on an Intel Mac, and a signature broken by
# lipo takes the notification centre down with it. Neither shows up on the machine that built
# it.
archs=$(lipo -archs "$app/Contents/MacOS/LLMInformBureau")
for arch in arm64 x86_64; do
	case " $archs " in
	*" $arch "*) ;;
	*)
		echo "The binary is $archs, not universal — it would not run on every Mac" >&2
		exit 1
		;;
	esac
done
codesign --verify --strict "$app"
echo "Universal: $archs, signature valid" >&2

rm -rf "$root/.build/dmg"
mkdir -p "$staging"
# ditto, not cp: it is the tool for bundles, and it carries the ad-hoc signature and the
# extended attributes across intact.
ditto "$app" "$staging/LLMInformBureau.app"
ditto "$root/Scripts/install.sh" "$staging/install.sh"
chmod +x "$staging/install.sh"

# The whole of what the recipient is given in writing. It lives here, in the script that packs
# the image, because it has to be right for the version being packed and there is nowhere else
# on the image to keep it. It answers why there are two commands and not one, because a person
# who does not know that will try to merge them and then wonder why the app is refused.
cat > "$staging/INSTALL.txt" <<TXT
LLM INFORM BUREAU $version

A menu bar app that reads how much of your Claude and Codex subscription is left, and how full
the context window of each running session is. Everything comes from files this Mac already
has: it makes no network calls, holds no credentials, and writes nothing outside its own
folder in Application Support.

It needs macOS 13 or newer and runs on both Apple Silicon and Intel. Nothing is compiled on
your side: no Xcode, no Command Line Tools, no account to sign in to.


FIRST, MOUNT THE IMAGE

Double-click the file you downloaded, $volume-$version.dmg. It opens as a volume
named $volume, and that is the path both commands below start from. The same from
the terminal:

  hdiutil attach ~/Downloads/$volume-$version.dmg


THEN TWO COMMANDS, IN THIS ORDER

  1.  sh /Volumes/$volume/install.sh --apply

  2.  xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app

The first installs the app, the second allows macOS to run it. Paste them into Terminal one at
a time; neither of them asks you anything back.

Worth doing once before command 1: run it without --apply. It then prints its four steps — the
app, the thresholds, Claude's status line, the start — and changes nothing. It is someone
else's shell script, and one of those steps edits a file of yours: ~/.claude/settings.json,
where Claude Code keeps its settings.

The order does not swap, and the second command has to name the installed copy. macOS marks
everything that arrives over the network, and the mark travels with a copy of the file:
clearing it on the disk image still leaves the copy in /Applications marked. Run the second
command first and it has nothing to clear — it answers "No such file" and stops.

The "sh" in front of the first command is not decoration. A script run straight off a mounted
disk image is stopped by Gatekeeper with a dialog and no output; handed to an interpreter, it
runs.


IF YOU OPEN THE APP BEFORE THE SECOND COMMAND

macOS says: "LLMInformBureau Not Opened — Apple could not verify ...". Nothing is wrong with
the download. This app is signed ad-hoc rather than with a paid Apple developer account, and
anything so signed that came over the network is refused until the mark is cleared.

DO NOT PRESS THE BLUE BUTTON. It reads "Move to Trash", it is the default one, and it removes
the app rather than the mark. Press "Done" instead, then run the second command.

Command 2 works on every version this app supports, and on macOS 26 it is the only way
through: that dialog leaves no "Open Anyway" entry in System Settings > Privacy & Security —
checked on 26.6. The routes usually named for older systems are NOT verified here, for want
of a Mac on those versions: the same "Open Anyway" entry on macOS 15, and Control-click the
app in Finder > Open on macOS 13 and 14.


THE FIRST RUN

After command 2 the app is installed but not running. The installer starts it itself, except
when it finds the quarantine mark on the copy it has just made — which is exactly this case:
it prints the second command and stops there rather than walk you into the dialog above. So
open it yourself, from Launchpad or /Applications, or with:

  open -a LLMInformBureau

The app has no Dock icon. It appears at the right-hand end of the menu bar and opens one
window explaining where each of its numbers comes from and what is not connected yet. That
window carries the "Open at login" checkbox; afterwards the same checkbox lives behind the ?
icon in the panel. Nothing is installed as a daemon or a background service — it is an
ordinary application that happens to have no windows.


CLAUDE'S SUBSCRIPTION LIMITS

Claude's limits and context window size are handed to the statusLine command and to nothing
else — no file under ~/.claude carries them. Reading them means occupying that slot, and there
is exactly one slot, so the third step of the installer puts a wrapper in it. Whatever command
was configured before is saved and called with the same payload, and its output is printed
unchanged: a status line you already have keeps working.

That payload — the JSON Claude Code hands its status line — is what the wrapper saves, one
file per session in ~/Library/Application Support/LLMInformBureau/, deleted a day after a
session falls silent. It is where the panel's Claude numbers come from, and, along with your
thresholds, the only thing this app ever writes. No credentials pass through it.

One consequence, said out loud because it surprises people: with any statusLine configured,
Claude Code stops showing most footer hints, "esc to interrupt" among them. That is Claude
Code's own behaviour and the real cost of connecting the wrapper. Start a new Claude Code
session after the install to see the status line change.

The installer asks nothing: the preview shows what would go into that slot, and --apply puts
it there along with the rest. To undo that, or to connect the wrapper later, run its own
installer from inside the app:

  # print what would change, change nothing
  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh

  # connect the wrapper, keeping whatever command is in the slot
  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --apply

  # put your previous command back
  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --uninstall

Without the wrapper the app still shows Codex in full and Claude's context from the
transcripts; it says "no data" for Claude's limits rather than showing them as zero. Claude's
limits arrive on a Pro or Max subscription only, and only after the first answer of a session.


A NEW VERSION

Unmount the old image first, if it is still mounted:

  hdiutil detach /Volumes/$volume

This matters more than it looks. Every version uses the same volume name, and macOS
mounts a second one alongside the first as "$volume 1" — so command 1 would keep
finding the old volume and reinstall the version you already have, without any sign
that it did. The installer prints the version it is about to install on its first
line; if that number is not the new one, an old image is still mounted.

Then download the new image and run the same two commands. The running app does not need
quitting: the installer quits it before replacing the bundle. The status line wrapper stays
connected and needs nothing redone.

Your edited thresholds are left exactly as they are: the file the app reads is
~/Library/Application Support/LLMInformBureau/thresholds.json, and the installer never
overwrites it. If a release changes the format of that file, the app ignores it whole, runs on
its built-in marks and says so in the panel; the installer notices the same thing and prints
the one command that replaces your file with this release's marks — your call whether to run
it, and your edits are gone when you do.


IF SOMETHING GOES WRONG

"There is no LLMInformBureau.app next to this script" — the image is not mounted, or an old
volume is. Check what is in /Volumes.

A WARNING that /Applications is not writable — this account may not install applications. Use
one that may; the app has to sit in /Applications for the commands here to name it.

Nothing in the menu bar after command 2 — it is not running. Open it as above.

"no data" where Claude's limits should be — the wrapper is not in the slot, or the session has
not answered yet, or the subscription is not Pro or Max. Codex numbers do not depend on any of
this.


REMOVING IT

Untick "Open at login", quit from the panel, then, in this order:

  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --uninstall
  rm -rf /Applications/LLMInformBureau.app
  rm -rf ~/Library/Application\ Support/LLMInformBureau

The first line puts your previous statusLine command back, and it has to run before the second:
the script it names lives inside the bundle the second line deletes. The third removes the
thresholds you edited, the saved payloads and the copy of the wrapper — everything this app
ever wrote.
TXT

rm -f "$dmg"
hdiutil create -volname "$volume" -srcfolder "$staging" -format UDZO "$dmg" >&2

echo "$dmg"
