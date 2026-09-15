#!/bin/sh
# The statusLine command LLM Inform Bureau installs, and the only way it can see Claude's
# subscription limits and context window size: there is no file under ~/.claude that carries
# them, and Claude Code hands them to the status line command and nowhere else.
#
# It does two things on every run. It saves the payload where the app can read it, and it
# calls whatever status line command was configured before, passing the same payload through
# and printing its output unchanged — so installing this takes nothing away.
#
# Installed and connected by install-statusline.sh; run by Claude Code, not by a person.
set -eu

support="$HOME/Library/Application Support/LLMInformBureau"
payloads="$support/claude-status"
previous="$support/previous-statusline"

input=$(cat)
# Every field is looked for on one line: the payload is JSON, and the line breaks in it are
# not ours to rely on.
flat=$(printf '%s' "$input" | tr -d '\n')

field() {
	printf '%s' "$flat" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" | head -n 1
}

# A percentage inside one named object. Every object read this way has no nested object of its
# own, so stopping at the first closing brace stops in the right place.
nested_percentage() {
	printf '%s' "$flat" |
		sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*{[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" |
		head -n 1
}

session=$(printf '%s' "$flat" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$session" ] || session="unknown-session"

# Written through a temporary file: the app reads this directory whenever it likes, and a
# half-written payload would read as a source that changed format.
mkdir -p "$payloads"
temporary="$payloads/.$session.$$.tmp"
printf '%s' "$input" >"$temporary"
mv -f "$temporary" "$payloads/$session.json"

# Sessions end without saying so; their payloads would otherwise stay forever.
find "$payloads" -name '*.json' -mtime +1 -delete 2>/dev/null || true

if [ -s "$previous" ]; then
	# The status line slot is one, and it was theirs first. Their command gets the same
	# payload on stdin and its output is what the status line shows.
	printf '%s' "$input" | sh -c "$(cat "$previous")"
	exit 0
fi

# Nothing was configured before, so this prints a short line of its own rather than leaving
# the status line blank.
line=$(printf '%s' "$flat" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -n "$line" ] || line="Claude"

held=$(field total_input_tokens)
window=$(field context_window_size)
if [ -n "$held" ] && [ -n "$window" ] && [ "$window" -gt 0 ] 2>/dev/null; then
	if [ "$window" -ge 1000000 ]; then
		size="$((window / 1000000))M"
	else
		size="$((window / 1000))K"
	fi
	line="$line · $((held / 1000))K/$size ($((held * 100 / window))%)"
fi

five=$(nested_percentage five_hour)
week=$(nested_percentage seven_day)
[ -n "$five" ] && line="$line · 5h ${five%.*}%"
[ -n "$week" ] && line="$line · 7d ${week%.*}%"

printf '%s\n' "$line"
