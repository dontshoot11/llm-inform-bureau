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


TWO COMMANDS, IN THIS ORDER

  1.  sh /Volumes/$volume/install.sh --apply

  2.  xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app

Paste them into Terminal one at a time. The first installs the app, the second allows macOS to
run it. Nothing is compiled and nothing else is needed: no Xcode, no Command Line Tools, no
account to sign in to.

Run the first one without --apply to read exactly what it is going to do and change nothing.
That is worth doing once. It is someone else's shell script and it edits a file of Claude
Code's.

The order does not swap, and the second command has to name the installed copy. macOS marks
everything that arrives over the network, and the mark travels with a copy of the file: clearing
it on the disk image still leaves the copy in /Applications marked. Run the second command
first and it has nothing to clear — it answers "No such file" and stops.

The "sh" in front of the first command is not decoration. A script run straight off a mounted
disk image is stopped by Gatekeeper with a dialog and no output; handed to an interpreter, it
runs.


IF YOU OPEN THE APP BEFORE THE SECOND COMMAND

macOS says: "LLMInformBureau Not Opened — Apple could not verify ...". Nothing is wrong with
the download. This app is signed ad-hoc rather than with a paid Apple developer account, and
anything so signed that came over the network is refused until the mark is cleared.

DO NOT PRESS THE BLUE BUTTON. It reads "Move to Trash", it is the default one, and it removes
the app rather than the mark. Press "Done" instead, then run the second command.

On macOS 26 that is the only way through: the dialog leaves no "Open Anyway" entry in System
Settings > Privacy & Security — checked. On macOS 13 and 14 the usual alternative is to
Control-click the app in Finder and choose Open; that route is NOT verified here, there was no
Mac on those versions to try it on. The command above works on all of them.

The installer knows about all this. If it finds the mark on the copy it has just made, it does
not open the app: it prints the second command and stops there.


CLAUDE'S SUBSCRIPTION LIMITS

Claude's limits and context window size are handed to the statusLine command and to nothing
else — no file under ~/.claude carries them. Reading them means occupying that slot, and there
is exactly one slot, so step 3 of the installer offers to put a wrapper in it. Whatever command
was configured before is saved and called with the same payload, and its output is printed
unchanged: a status line you already have keeps working.

One consequence, said out loud because it surprises people: with any statusLine configured,
Claude Code stops showing most footer hints, "esc to interrupt" among them. That is Claude
Code's own behaviour and the real cost of connecting the wrapper.

The installer shows the change before making it and keeps a backup. You can decline it there
and connect it later, or undo it, from inside the installed app:

  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh
  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --apply
  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --uninstall

Without the wrapper the app still shows Codex in full and Claude's context from the
transcripts; it says "no data" for Claude's limits rather than showing them as zero. Claude's
limits arrive on a Pro or Max subscription only, and only after the first answer of a session.


THE FIRST RUN

The app has no Dock icon. It appears at the right-hand end of the menu bar and opens one window
explaining where each of its numbers comes from and what is not connected yet. That window
carries the "Open at login" checkbox; afterwards the same checkbox lives behind the ? icon in
the panel. Nothing is installed as a daemon or a background service — this is an ordinary
application that happens to have no windows.


A NEW VERSION

Unmount the old image first, if it is still mounted:

  hdiutil detach /Volumes/$volume

This matters more than it looks. Every version uses the same volume name, and macOS mounts a
second one alongside the first as "$volume 1" — so the command above would keep finding the
old volume and reinstall the version you already have, without any sign that it did. The
installer prints the version it is about to install on its first line; if that number is not
the new one, an old image is still mounted.

Then download the new image and run the same two commands. Your edited thresholds are left exactly
as they are: the file the app reads is
~/Library/Application Support/LLMInformBureau/thresholds.json, and the installer never
overwrites it. If a release changes the format of that file, the app falls back to its built-in
marks and says so in the panel; the installer prints the one command that takes the new ones.


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
