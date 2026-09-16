#!/bin/sh
# Builds the menu bar app into a .app bundle and, with --run, restarts it.
#
# SwiftPM produces a bare executable; a menu bar app needs a bundle with an Info.plist
# (LSUIElement, so it has no Dock icon). Nothing else goes inside it: the same binary is also
# Claude Code's status line command, and the thresholds travel in SwiftPM's resource bundle, so
# the app on the receiving Mac needs no scripts beside it.
#
# The binary inside is universal. The bundle built here is the one that travels on the disk
# image to another Mac, and that Mac may be an Intel one — a fact nobody discovers on this
# side, where everything runs. Two builds and lipo rather than `swift build --arch`: that flag
# drives xcbuild and needs the full Xcode, and this package is built on the Command Line Tools
# alone.
#
# The ad-hoc signature is applied last, after lipo — lipo writes a new binary and would throw
# away a signature made before it. It is not about distribution: the notification centre
# ignores a bundle whose signing identifier does not match its CFBundleIdentifier, and
# SwiftPM's linker signature does not.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$root/Scripts/Info.plist")
app="$root/.build/app/LLMInformBureau.app"
arch_build="$root/.build/arch"

# Each architecture gets a scratch path of its own: one directory cannot hold two builds, and
# sharing it would mean a full rebuild on every switch. The deployment target in the triple is
# the one Package.swift declares.
#
# Progress goes to stderr: the only thing this script writes to stdout is the path of the
# bundle, so that another script can capture it.
for arch in arm64 x86_64; do
	echo "Building $arch" >&2
	swift build -c release --product LLMInformBureau --package-path "$root" \
		--triple "$arch-apple-macosx13.0" --scratch-path "$arch_build/$arch" >&2
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create \
	"$arch_build/arm64/release/LLMInformBureau" \
	"$arch_build/x86_64/release/LLMInformBureau" \
	-output "$app/Contents/MacOS/LLMInformBureau"
# The thresholds the app ships with travel in SwiftPM's resource bundle. It holds no code, so
# the two architectures produce the same one and either copy will do.
for resources in "$arch_build"/arm64/release/*.bundle; do
	[ -e "$resources" ] && cp -R "$resources" "$app/Contents/Resources/"
done

# Checked, because the app has no marks at all without it and nothing on this machine would
# ever say so. SwiftPM's own `Bundle.module` finds the copy in the build directory, which
# exists here and nowhere else; what the app actually reads on somebody else's Mac is this
# one, in Contents/Resources (see `ThresholdConfigLoader.bundledConfigURL`). A build that
# packed no bundle would run perfectly here and die on launch there.
found=""
for resources in "$app/Contents/Resources"/*.bundle; do
	[ -f "$resources/thresholds.json" ] && found="$resources"
done
if [ -z "$found" ]; then
	echo "No resource bundle with thresholds.json in $app/Contents/Resources" >&2
	echo "  The app would launch without its marks on any Mac but this one." >&2
	exit 1
fi
cp "$root/Scripts/Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null

codesign --force --sign - --identifier "$bundle_id" "$app" 2>/dev/null

echo "$app"

if [ "${1:-}" = "--run" ]; then
	pkill -f "$app/Contents/MacOS/LLMInformBureau" 2>/dev/null || true
	open "$app"
fi
