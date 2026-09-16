#!/bin/sh
# Installs what is lying next to it: the app, its editable thresholds, and the statusLine
# wrapper that is the only local source of Claude's limits.
#
# It installs a built bundle and cannot build one. Building is build-dmg.sh's job, on the
# author's machine; the person running this one may have no compiler at all, and the whole
# point of the disk image is that they do not need one. The author installs the same way,
# from the same image, so there is no second installation path to keep working.
#
# Nothing here happens without being shown first. Run it to read the plan, run it with --apply
# to carry the plan out. Each step says what it will touch, and a step that is already done
# says so instead of doing it again.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
bundle="$here/LLMInformBureau.app"
support="$HOME/Library/Application Support/LLMInformBureau"
applications="/Applications"
app="$applications/LLMInformBureau.app"
thresholds="$support/thresholds.json"
shipped="$bundle/Contents/Resources/LLMInformBureau_SessionHealthCore.bundle/thresholds.json"
mode="${1:-preview}"

case "$mode" in
preview | --preview | --apply) ;;
*)
	echo "usage: $0 [--apply]" >&2
	exit 1
	;;
esac

if [ ! -d "$bundle" ]; then
	echo "There is no LLMInformBureau.app next to this script." >&2
	echo "  looked in: $here" >&2
	echo "" >&2
	echo "This script installs a built app; it does not build one." >&2
	echo "  Downloaded the disk image? Open it and run the copy of this script from the" >&2
	echo "  mounted volume, where the app sits beside it:" >&2
	echo "    sh /Volumes/LLMInformBureau/install.sh --apply" >&2
	echo "  Working in the repository? Scripts/build-dmg.sh builds the image, and you install" >&2
	echo "  from it the same way everyone else does." >&2
	exit 1
fi

# The statusLine installer travels with the app, not with this script: on a downloaded image
# there is no repository to take it from. Beside this script is the repository layout; inside
# the bundle is the installed one. It is run through sh for the same reason this script is:
# a file executed straight off a mounted image is stopped by Gatekeeper with a dialog and no
# output.
statusline=""
for candidate in "$here/install-statusline.sh" "$bundle/Contents/Resources/install-statusline.sh"; do
	if [ -f "$candidate" ]; then
		statusline="$candidate"
		break
	fi
done

# The format version out of a thresholds file, or nothing if it has none. The app falls back to
# its built-in values wholesale on a version it does not read, so an installed copy left behind
# by an older release stops doing anything — and a step that overwrote it without asking would
# be exactly the behaviour this app refuses everywhere else.
version_of() {
	[ -f "$1" ] || return 0
	sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" | head -1
}

step() {
	echo ""
	echo "$1"
}

# ---------------------------------------------------------------- the plan

echo "LLM Inform Bureau — install"

step "1. Install the app to $applications"
echo "   Copies $bundle"
echo "        to $app"
echo "   Nothing is compiled: the bundle is already built."
if [ -d "$app" ]; then
	echo "   Replaces the copy already there. A running one is quit first."
else
	echo "   A fresh copy. Nothing is there now."
fi
if [ ! -w "$applications" ]; then
	echo "   WARNING: $applications is not writable by this account — this step will fail."
fi

step "2. Install the thresholds where they can be edited"
if [ -f "$thresholds" ]; then
	echo "   $thresholds already exists and is left exactly as it is."
	echo "   Yours is the one the app reads; the copy inside the bundle is only the floor under it."
	installed_version=$(version_of "$thresholds")
	shipped_version=$(version_of "$shipped")
	if [ -n "$installed_version" ] && [ -n "$shipped_version" ] && [ "$installed_version" != "$shipped_version" ]; then
		echo ""
		echo "   NOTE: yours is format $installed_version and this release reads $shipped_version."
		echo "   The app will ignore it whole and run on its built-in marks, saying so in the panel."
		echo "   Your edits are not lost — the file is left alone. To take this release's marks:"
		echo "     cp \"$app/Contents/Resources/LLMInformBureau_SessionHealthCore.bundle/thresholds.json\" \"$thresholds\""
	fi
else
	echo "   Copy the thresholds out of the bundle to $thresholds"
	echo "   Editing that file changes the marks the app watches without rebuilding anything."
fi

step "3. Connect the statusLine wrapper"
if [ -n "$statusline" ]; then
	echo "   Runs $statusline, which prints its own plan below."
	echo ""
	# Its closing "run with --apply" line is dropped: this script says that once, at the end,
	# and the sub-command is not run separately.
	sh "$statusline" --preview | grep -v "^This was a preview" | sed 's/^/   /'
else
	echo "   SKIPPED: install-statusline.sh is not beside this script or inside the bundle,"
	echo "   so Claude's subscription limits cannot be connected from here. Everything else"
	echo "   below still works; the panel will simply have nothing to show for Claude."
fi

step "4. Start the app"
echo "   It lives at the right-hand end of the menu bar, with no Dock icon. On its first run"
echo "   it opens one window explaining where each of its numbers comes from and what is not"
echo "   connected yet. Starting with the Mac is a checkbox in that window — and afterwards"
echo "   in the panel behind the menu bar item."

if [ "$mode" != "--apply" ]; then
	echo ""
	echo "This was a preview and nothing has changed. Run with --apply to do it."
	exit 0
fi

# ---------------------------------------------------------------- doing it

echo ""
echo "Applying."

echo ""
echo "1. Installing to $applications."
# Quit whatever is running first: copying over a running bundle is how a half-replaced app
# keeps running until it crashes.
pkill -f "LLMInformBureau.app/Contents/MacOS/LLMInformBureau" 2>/dev/null || true
rm -rf "$app"
# ditto, not cp -R: it is the tool for bundles, and it carries the signature and the extended
# attributes across intact.
ditto "$bundle" "$app"
echo "   $app"

echo ""
echo "2. Thresholds."
mkdir -p "$support"
if [ -f "$thresholds" ]; then
	echo "   $thresholds left as it is."
	installed_version=$(version_of "$thresholds")
	shipped_version=$(version_of "$shipped")
	if [ -n "$installed_version" ] && [ -n "$shipped_version" ] && [ "$installed_version" != "$shipped_version" ]; then
		echo "   NOTE: it is format $installed_version, this release reads $shipped_version — the app will run on its"
		echo "   built-in marks and say so. To take this release's marks:"
		echo "     cp \"$app/Contents/Resources/LLMInformBureau_SessionHealthCore.bundle/thresholds.json\" \"$thresholds\""
	fi
else
	cp "$app/Contents/Resources/LLMInformBureau_SessionHealthCore.bundle/thresholds.json" "$thresholds"
	echo "   $thresholds"
fi

echo ""
echo "3. statusLine wrapper."
if [ -n "$statusline" ]; then
	sh "$statusline" --apply | sed 's/^/   /'
else
	echo "   Skipped: install-statusline.sh is not here. Claude's limits stay unconnected."
fi

echo ""
echo "4. Starting."
open "$app"
echo "   Running. Look for it at the right-hand end of the menu bar."
