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

rm -rf "$root/.build/dmg"
mkdir -p "$staging"
# ditto, not cp: it is the tool for bundles, and it carries the ad-hoc signature and the
# extended attributes across intact.
ditto "$app" "$staging/LLMInformBureau.app"
ditto "$root/Scripts/install.sh" "$staging/install.sh"
chmod +x "$staging/install.sh"

cat > "$staging/INSTALL.txt" <<TXT
LLM Inform Bureau $version

Two commands, in this order. The first installs the app, the second allows macOS to run it.

  1.  sh /Volumes/$volume/install.sh --apply
  2.  xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app

The order is not interchangeable. The second command clears the mark macOS puts on everything
that arrives over the network, and it has to be run on the installed copy — clearing it here,
on the disk image, changes nothing: the copy that install.sh makes carries the mark anyway.

Run the first command without --apply to read what it is going to do and change nothing.

The app has no Dock icon. It appears at the right-hand end of the menu bar, and opens one
window on its first run explaining where each of its numbers comes from.
TXT

rm -f "$dmg"
hdiutil create -volname "$volume" -srcfolder "$staging" -format UDZO "$dmg" >&2

echo "$dmg"
