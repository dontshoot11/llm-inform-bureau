#!/bin/sh
# Connects the statusLine wrapper to Claude Code — the only way this app can see Claude's
# subscription limits and the size of its context window.
#
# Claude Code has exactly one statusLine slot. If something is already in it, that command is
# saved and the wrapper keeps calling it with the same payload, so nothing is taken away. This
# script never changes anything without showing it first: run it to see the plan, run it with
# --apply to carry the plan out, and with --uninstall to put things back.
#
# It ships in two places and works the same in both: beside the wrapper in Scripts/, and beside
# the wrapper inside the installed app's Resources. Whoever downloaded the disk image and has
# no repository connects the wrapper from the bundle — that is why everything here is found
# next to this script and nothing is looked for in a repository layout.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
wrapper="$here/statusline-wrapper.sh"
support="$HOME/Library/Application Support/LLMInformBureau"
installed="$support/statusline-wrapper.sh"
previous="$support/previous-statusline"
settings="$HOME/.claude/settings.json"
mode="${1:-preview}"

if [ ! -f "$wrapper" ]; then
	echo "There is no statusline-wrapper.sh next to this script." >&2
	echo "  looked in: $here" >&2
	echo "" >&2
	echo "The wrapper is the thing being installed, so there is nothing to connect without" >&2
	echo "it. Inside the installed app both files sit together:" >&2
	echo "  sh /Applications/LLMInformBureau.app/Contents/Resources/install-statusline.sh --apply" >&2
	exit 1
fi

# Reading and writing settings.json goes through osascript's JavaScript rather than through
# sed: the file is the user's, it holds far more than this one key, and a regex edit of someone
# else's config is how a working setup gets broken silently. Not python3, which did this job
# before: it arrives with the Xcode Command Line Tools, and on the Mac this app is handed to
# there are none — /usr/bin/python3 there opens an installer dialog instead of working.
# osascript is part of macOS itself.
current=$(osascript -l JavaScript - "$settings" <<'JS'
ObjC.import('Foundation');
function run(argv) {
	const text = $.NSString.stringWithContentsOfFileEncodingError($(argv[0]), $.NSUTF8StringEncoding, $());
	if (text.isNil()) return "";
	try {
		return (JSON.parse(ObjC.unwrap(text)).statusLine || {}).command || "";
	} catch (error) {
		return "";
	}
}
JS
)

saved=""
[ -s "$previous" ] && saved=$(cat "$previous")

# The slot holds our wrapper. Written shell-quoted, so both spellings count.
wrapper_connected() {
	[ "$current" = "$installed" ] || [ "$current" = "'$installed'" ]
}

# settings.json is the user's file and holds far more than this one key, so every branch that
# writes to it leaves a copy behind first — including --uninstall, which is the branch that
# removes things.
backup_settings() {
	# The operation goes in the name along with the timestamp. Seconds are not fine enough on
	# their own: --apply and --uninstall run back to back land on the same second, and the
	# second copy would overwrite the first — which is the one holding the user's original
	# command, the only state actually worth keeping.
	#
	# Explicitly 0: under set -e a function ending on a failed test takes the script down, and
	# "there is no settings.json yet" is a normal first install, not a failure.
	[ -f "$settings" ] && cp "$settings" "$settings.backup-$(date +%Y%m%d%H%M%S)-$1"
	return 0
}

case "$mode" in
preview | --preview | --apply)
	echo "statusLine wrapper"
	echo
	echo "  copy   $wrapper"
	echo "      to $installed"
	echo
	echo "  set    statusLine.command in $settings"
	echo "      to '$installed'"
	echo
	if [ -z "$current" ]; then
		echo "  No statusLine is configured now, so nothing of yours is being replaced."
		echo "  The wrapper will print a short line of its own: model, context, limits."
		echo
		echo "  One thing this changes for you: with any statusLine configured, Claude Code"
		echo "  stops showing most footer hints, including 'esc to interrupt'."
	elif wrapper_connected; then
		echo "  The wrapper is already connected."
		if [ -n "$saved" ]; then
			echo "  Your own command is saved and still being called:"
			echo "      $saved"
		fi
	else
		echo "  Your statusLine command is:"
		echo "      $current"
		echo
		echo "  It will be saved to $previous, and the wrapper will keep calling it with the"
		echo "  same payload and print its output unchanged. Your status line keeps working."
	fi
	echo
	;;
--uninstall)
	echo "statusLine wrapper — removing"
	echo
	if ! wrapper_connected; then
		echo "  The wrapper is not in the statusLine slot, so there is nothing of this app's"
		echo "  to take out of it."
		if [ -n "$current" ]; then
			echo "  What is there now, and what this will NOT touch:"
			echo "      $current"
		else
			echo "  No statusLine is configured at all."
		fi
		echo
		exit 0
	fi
	echo "  restore statusLine.command in $settings"
	echo "        to ${saved:-(nothing — the key will be removed, as there was none before)}"
	echo
	echo "  A copy of $settings is kept beside it first."
	echo
	;;
*)
	echo "usage: $0 [--apply | --uninstall]" >&2
	exit 1
	;;
esac

if [ "$mode" = "preview" ] || [ "$mode" = "--preview" ]; then
	echo "This was a preview and nothing has changed. Run with --apply to do it."
	exit 0
fi

if [ "$mode" = "--uninstall" ]; then
	# Guarded above: this branch is only reached with the wrapper actually in the slot. Without
	# that guard an empty $saved means "delete the key", and $previous is gone after the first
	# run — so a second --uninstall, or one on a Mac that never had the wrapper, would take the
	# user's own statusLine command away instead of this app's.
	restore="$saved"
	echo "Restoring the statusLine that was there before:"
	echo "      ${restore:-(none — the key will be removed)}"
	backup_settings uninstall
	osascript -l JavaScript - "$settings" "$restore" <<'JS'
ObjC.import('Foundation');
function run(argv) {
	const path = argv[0];
	const restore = argv.length > 1 ? argv[1] : "";
	const text = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, $());
	let settings = {};
	if (!text.isNil()) {
		try {
			settings = JSON.parse(ObjC.unwrap(text)) || {};
		} catch (error) {
			settings = {};
		}
	}
	if (restore) {
		const status = (settings.statusLine && typeof settings.statusLine === "object") ? settings.statusLine : {};
		settings.statusLine = Object.assign({}, status, { type: "command", command: restore });
	} else {
		delete settings.statusLine;
	}
	$(JSON.stringify(settings, null, 2) + "\n")
		.writeToFileAtomicallyEncodingError($(path), true, $.NSUTF8StringEncoding, $());
	return "";
}
JS
	rm -f "$previous"
	echo "Done. The payload files under $support/claude-status are left alone."
	exit 0
fi

mkdir -p "$support" "$(dirname "$settings")"

# Saved before the settings are touched, and never when the wrapper is already the command:
# saving the wrapper as its own predecessor would make it call itself forever.
if [ -n "$current" ] && ! wrapper_connected; then
	printf '%s' "$current" >"$previous"
fi

cp "$wrapper" "$installed"
chmod +x "$installed"

backup_settings apply

osascript -l JavaScript - "$settings" "$installed" <<'JS'
ObjC.import('Foundation');
// Claude Code runs the command through a shell, and its path contains "Application Support".
function quote(value) {
	return "'" + value.replace(/'/g, "'\\''") + "'";
}
function run(argv) {
	const path = argv[0], wrapper = argv[1];
	const text = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, $());
	let settings = {};
	if (!text.isNil()) {
		try {
			settings = JSON.parse(ObjC.unwrap(text)) || {};
		} catch (error) {
			settings = {};
		}
	}
	// Anything else the user had set here — padding, refreshInterval — is theirs and stays.
	const status = (settings.statusLine && typeof settings.statusLine === "object") ? settings.statusLine : {};
	settings.statusLine = Object.assign({}, status, { type: "command", command: quote(wrapper) });
	$(JSON.stringify(settings, null, 2) + "\n")
		.writeToFileAtomicallyEncodingError($(path), true, $.NSUTF8StringEncoding, $());
	return "";
}
JS

echo "Connected. The next answer in any Claude session fills in its limits and window size."
