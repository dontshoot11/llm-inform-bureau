#!/bin/sh
# Installs the whole thing: the app, its editable thresholds, and the statusLine wrapper that
# is the only local source of Claude's limits.
#
# Nothing here happens without being shown first. Run it to read the plan, run it with --apply
# to carry the plan out. Each step says what it will touch, and a step that is already done
# says so instead of doing it again.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
support="$HOME/Library/Application Support/LLMInformBureau"
applications="/Applications"
app="$applications/LLMInformBureau.app"
thresholds="$support/thresholds.json"
shipped="$root/Sources/SessionHealthCore/Resources/thresholds.json"
mode="${1:-preview}"

# The format version out of a thresholds file, or nothing if it has none. The app falls back to
# its built-in values wholesale on a version it does not read, so an installed copy left behind
# by an older release stops doing anything — and a step that overwrote it without asking would
# be exactly the behaviour this app refuses everywhere else.
version_of() {
	[ -f "$1" ] || return 0
	sed -n 's/.*"version"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" | head -1
}

case "$mode" in
preview | --preview | --apply) ;;
*)
	echo "usage: $0 [--apply]" >&2
	exit 1
	;;
esac

step() {
	echo ""
	echo "$1"
}

# ---------------------------------------------------------------- the plan

echo "LLM Inform Bureau — install"

step "1. Build the app bundle"
echo "   swift build -c release, then assemble $app"
echo "   The build needs the Xcode Command Line Tools and nothing else."

step "2. Install it to $applications"
if [ -d "$app" ]; then
	echo "   Replaces the copy already there. A running one is quit first."
else
	echo "   A fresh copy. Nothing is there now."
fi
if [ ! -w "$applications" ]; then
	echo "   WARNING: $applications is not writable by this account — this step will fail."
fi

step "3. Install the thresholds where they can be edited"
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
		echo "     cp \"$shipped\" \"$thresholds\""
	fi
else
	echo "   Copy the shipped thresholds to $thresholds"
	echo "   Editing that file changes the marks the app watches without rebuilding anything."
fi

step "4. Connect the statusLine wrapper"
echo "   Runs Scripts/install-statusline.sh, which prints its own plan below."
echo ""
# Its closing "run with --apply" line is dropped: this script says that once, at the end, and
# the sub-command is not run separately.
"$root/Scripts/install-statusline.sh" --preview | grep -v "^This was a preview" | sed 's/^/   /'

step "5. Start the app"
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
echo "1. Building."
built=$("$root/Scripts/build-app.sh")

echo ""
echo "2. Installing to $applications."
# Quit whatever is running first: copying over a running bundle is how a half-replaced app
# keeps running until it crashes.
pkill -f "LLMInformBureau.app/Contents/MacOS/LLMInformBureau" 2>/dev/null || true
rm -rf "$app"
cp -R "$built" "$app"
echo "   $app"

echo ""
echo "3. Thresholds."
mkdir -p "$support"
if [ -f "$thresholds" ]; then
	echo "   $thresholds left as it is."
	installed_version=$(version_of "$thresholds")
	shipped_version=$(version_of "$shipped")
	if [ -n "$installed_version" ] && [ -n "$shipped_version" ] && [ "$installed_version" != "$shipped_version" ]; then
		echo "   NOTE: it is format $installed_version, this release reads $shipped_version — the app will run on its"
		echo "   built-in marks and say so. To take this release's marks:"
		echo "     cp \"$shipped\" \"$thresholds\""
	fi
else
	cp "$app/Contents/Resources/LLMInformBureau_SessionHealthCore.bundle/thresholds.json" "$thresholds"
	echo "   $thresholds"
fi

echo ""
echo "4. statusLine wrapper."
"$root/Scripts/install-statusline.sh" --apply | sed 's/^/   /'

echo ""
echo "5. Starting."
open "$app"
echo "   Running. Look for it at the right-hand end of the menu bar."
