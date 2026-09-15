#!/bin/sh
# Builds the menu bar app into a .app bundle and, with --run, restarts it.
#
# SwiftPM produces a bare executable; a menu bar app needs a bundle with an Info.plist
# (LSUIElement, so it has no Dock icon). The ad-hoc signature at the end is not about
# distribution: the notification centre ignores a bundle whose signing identifier does not
# match its CFBundleIdentifier, and SwiftPM's linker signature does not.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$root/Scripts/Info.plist")
app="$root/.build/app/LLMInformBureau.app"

# Progress goes to stderr: the only thing this script writes to stdout is the path of the
# bundle, so that another script can capture it.
swift build -c release --product LLMInformBureau --package-path "$root" >&2

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/release/LLMInformBureau" "$app/Contents/MacOS/LLMInformBureau"
# The thresholds the app ships with travel in SwiftPM's resource bundle.
for resources in "$root"/.build/release/*.bundle; do
	[ -e "$resources" ] && cp -R "$resources" "$app/Contents/Resources/"
done
cp "$root/Scripts/Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

codesign --force --sign - --identifier "$bundle_id" "$app" 2>/dev/null

echo "$app"

if [ "${1:-}" = "--run" ]; then
	pkill -f "$app/Contents/MacOS/LLMInformBureau" 2>/dev/null || true
	open "$app"
fi
