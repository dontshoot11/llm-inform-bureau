#!/bin/sh
# Connects the statusLine wrapper to Claude Code — the only way this app can see Claude's
# subscription limits and the size of its context window.
#
# Claude Code has exactly one statusLine slot. If something is already in it, that command is
# saved and the wrapper keeps calling it with the same payload, so nothing is taken away. This
# script never changes anything without showing it first: run it to see the plan, run it with
# --apply to carry the plan out, and with --uninstall to put things back.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
support="$HOME/Library/Application Support/LLMInformBureau"
installed="$support/statusline-wrapper.sh"
previous="$support/previous-statusline"
settings="$HOME/.claude/settings.json"
mode="${1:-preview}"

python=$(command -v python3 || true)
if [ -z "$python" ]; then
	echo "python3 is needed to edit $settings without rewriting the rest of it." >&2
	echo "It ships with the Xcode Command Line Tools, which this project already needs." >&2
	exit 1
fi

# Reading and writing settings.json goes through python3 rather than through sed: the file is
# the user's, it holds far more than this one key, and a regex edit of someone else's config
# is how a working setup gets broken silently.
current=$("$python" - "$settings" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as handle:
        print((json.load(handle).get("statusLine") or {}).get("command", ""))
except (OSError, ValueError):
    print("")
PY
)

saved=""
[ -s "$previous" ] && saved=$(cat "$previous")

case "$mode" in
preview | --preview | --apply)
	echo "statusLine wrapper"
	echo
	echo "  copy   $root/Scripts/statusline-wrapper.sh"
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
	elif [ "$current" = "$installed" ] || [ "$current" = "'$installed'" ]; then
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
	restore="$saved"
	echo "Restoring the statusLine that was there before:"
	echo "      ${restore:-(none — the key will be removed)}"
	"$python" - "$settings" "$restore" <<'PY'
import json, sys
path, restore = sys.argv[1], sys.argv[2]
try:
    with open(path) as handle:
        settings = json.load(handle)
except (OSError, ValueError):
    settings = {}
status = settings.get("statusLine")
if restore:
    settings["statusLine"] = {
        **(status if isinstance(status, dict) else {}),
        "type": "command",
        "command": restore,
    }
else:
    settings.pop("statusLine", None)
with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
	rm -f "$previous"
	echo "Done. The payload files under $support/claude-status are left alone."
	exit 0
fi

mkdir -p "$support" "$(dirname "$settings")"

# Saved before the settings are touched, and never when the wrapper is already the command:
# saving the wrapper as its own predecessor would make it call itself forever.
if [ -n "$current" ] && [ "$current" != "$installed" ] && [ "$current" != "'$installed'" ]; then
	printf '%s' "$current" >"$previous"
fi

cp "$root/Scripts/statusline-wrapper.sh" "$installed"
chmod +x "$installed"

[ -f "$settings" ] && cp "$settings" "$settings.backup-$(date +%Y%m%d%H%M%S)"

"$python" - "$settings" "$installed" <<'PY'
import json, shlex, sys
path, wrapper = sys.argv[1], sys.argv[2]
try:
    with open(path) as handle:
        settings = json.load(handle)
except (OSError, ValueError):
    settings = {}
status = settings.get("statusLine")
settings["statusLine"] = {
    # Anything else the user had set here — padding, refreshInterval — is theirs and stays.
    **(status if isinstance(status, dict) else {}),
    "type": "command",
    # Claude Code runs this through a shell, and the path contains "Application Support".
    "command": shlex.quote(wrapper),
}
with open(path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY

echo "Connected. The next answer in any Claude session fills in its limits and window size."
