#!/bin/sh
# Builds the one file that is handed to someone else: a disk image holding the built app and
# the instructions for installing it.
#
# It exists so that the path to a working app on another Mac is "drag it in, then one command",
# with no repository, no compiler, no Command Line Tools and no shell script of somebody else's
# on that side. Everything that needs building happens here, on the author's machine; the other
# side drags a bundle into /Applications the way it drags any other app, and the app does the
# rest of its setting up itself, on its first run and by its own buttons.
#
# The volume is named without spaces on purpose: it is named in the instructions, and a path
# that has to be quoted is a path people retype wrong.
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

# The other half of the drag. Without it the instructions ask somebody to find their own
# Applications folder and arrange two windows; with it both ends of the gesture are in the one
# window that opened. A symlink survives hdiutil and mounts as a folder the Finder treats as
# the real /Applications — checked on an image built this way.
ln -s /Applications "$staging/Applications"

# The whole of what the recipient is given in writing. It lives here, in the script that packs
# the image, because it has to be right for the version being packed and there is nowhere else
# on the image to keep it. It answers why there is a command at all after a drag, because a
# person who does not know that meets the Gatekeeper dialog with no idea what it wants.
cat > "$staging/INSTALL.txt" <<TXT
LLM INFORM BUREAU $version

A menu bar app that reads how much of your Claude and Codex subscription is left, and how full
the context window of each running session is. Everything comes from files this Mac already
has: it makes no network calls, holds no credentials, and writes nothing outside its own
folder in Application Support and one key of Claude Code's settings, which it asks you about
first.

It needs macOS 13 or newer and runs on both Apple Silicon and Intel. Nothing is compiled on
your side: no Xcode, no Command Line Tools, no account to sign in to. No script of anybody
else's runs on your Mac either — installing this is a drag and one command.


FIRST, MOUNT THE IMAGE

Double-click the file you downloaded, $volume-$version.dmg. It opens as a volume
named $volume. The same from the terminal:

  hdiutil attach ~/Downloads/$volume-$version.dmg


THEN DRAG IT IN, AND RUN ONE COMMAND

The window that opened holds LLMInformBureau.app, a shortcut to your Applications folder, and
this file. Drag the app onto that shortcut — the same gesture as for any other app, with both
ends of it in the one window. Then paste this into Terminal:

  xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app

That command is the whole of the setting up. macOS marks everything that arrives over the
network, and the mark travels with the copy, so it has to name the copy in /Applications and
has to run after the drag, not before: run it first and it answers "No such file" and stops.

There is nothing else to set up. The marks the app watches come with it, and Claude's
subscription limits it offers to connect from its own panel, showing you the change first —
see below.


IF YOU OPEN THE APP BEFORE THAT COMMAND

macOS says: "LLMInformBureau Not Opened — Apple could not verify ...". Nothing is wrong with
the download. This app is signed ad-hoc rather than with a paid Apple developer account, and
anything so signed that came over the network is refused until the mark is cleared.

DO NOT PRESS THE BLUE BUTTON. It reads "Move to Trash", it is the default one, and it removes
the app rather than the mark. Press "Done" instead, then run the command.

The command works on every version this app supports, and on macOS 26 it is the only way
through: that dialog leaves no "Open Anyway" entry in System Settings > Privacy & Security —
checked on 26.6. The routes usually named for older systems are NOT verified here, for want
of a Mac on those versions: the same "Open Anyway" entry on macOS 15, and Control-click the
app in Finder > Open on macOS 13 and 14.


THE FIRST RUN

Open it from Launchpad or /Applications, or with:

  open -a LLMInformBureau

The app has no Dock icon. It appears at the right-hand end of the menu bar and opens one
window explaining where each of its numbers comes from and what is not connected yet. That
window carries the "Open at login" checkbox; afterwards the same checkbox lives behind the ?
icon in the panel. Nothing is installed as a daemon or a background service — it is an
ordinary application that happens to have no windows.


CLAUDE'S SUBSCRIPTION LIMITS

Claude's limits and context window size are handed to the statusLine command and to nothing
else — no file under ~/.claude carries them. Reading them means occupying that slot, and there
is exactly one slot.

So the app asks. Open the panel, and where Claude's limits would be there is a "Connect limits"
button instead of an empty reading. Pressing it shows you the exact line it would put into
~/.claude/settings.json and changes nothing until you say yes; a copy of that file is kept
beside it first. Whatever command was configured there before is saved and goes on being
called with the same payload, its output printed unchanged: a status line you already have
keeps working. The same panel gives the slot back — the icon beside the ? in its bottom row.

The payload — the JSON Claude Code hands its status line — is saved one file per session in
~/Library/Application Support/LLMInformBureau/, deleted a day after a session falls silent. It
is where the panel's Claude numbers come from, and, along with the command it kept for you, the
only thing this app ever writes. No credentials pass through it.

One consequence, said out loud because it surprises people: with any statusLine configured,
Claude Code stops showing most footer hints, "esc to interrupt" among them. That is Claude
Code's own behaviour and the real cost of connecting. Start a new Claude Code session after
connecting to see the status line change.

Without it the app still shows Codex in full and Claude's context from the transcripts; it says
"no data" for Claude's limits rather than showing them as zero. Claude's limits arrive on a Pro
or Max subscription only, and only after the first answer of a session.


A NEW VERSION

Unmount the old image first, if it is still mounted:

  hdiutil detach /Volumes/$volume

Every version uses the same volume name, and macOS mounts a second one alongside the first as
"$volume 1" — so a window you thought was the new image can be the old one. The version
is on the first line of this file, on the image you actually opened.

Then download the new image and drag the app onto the Applications shortcut again, over the
old one, letting the Finder replace it. Quit the running copy from its panel first. The command above is needed again: the mark is on
the new copy too.

Nothing of yours is carried across because nothing of yours is involved: the app brings its own
marks. The connected status line stays connected; a copy set up by an older version of this app,
which used a shell wrapper, is offered an update in the panel and keeps whatever command you had
underneath it.


IF SOMETHING GOES WRONG

Nothing in the menu bar — it is not running. Open it as above.

"no data" where Claude's limits should be — the slot is not connected yet, or the session has
not answered since, or the subscription is not Pro or Max. Codex numbers do not depend on any
of this.


REMOVING IT

Untick "Open at login". Disconnect the status line from the panel, so your previous command
goes back where it was and Claude Code is not left calling something that has gone. Then quit
from the panel and:

  rm -rf /Applications/LLMInformBureau.app
  rm -rf ~/Library/Application\ Support/LLMInformBureau

The second line removes the saved payloads and the command the app kept for you — everything
this app ever wrote for itself.
TXT

rm -f "$dmg"
hdiutil create -volname "$volume" -srcfolder "$staging" -format UDZO "$dmg" >&2

echo "$dmg"
