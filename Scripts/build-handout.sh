#!/bin/sh
# Builds the description that goes out with the release: an English PDF saying what the app is
# for, what its lights mean and how it is installed.
#
# It is the second of the two files handed over — the image is the app, this is the page
# somebody reads before deciding to install it. Nothing is needed for it beyond the Command
# Line Tools this package already asks for: the source is HTML in the repository and AppKit
# does the rendering (Sources/Handout/Handout.md has why, and what was tried instead).
#
# The version is read from the same plist the image takes it from, so the number on the page,
# the number in the file name and the number in the app are one number.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Scripts/Info.plist")
pdf="$root/.build/LLMInformBureau-$version.pdf"

# Progress goes to stderr: the only thing this script writes to stdout is the path of the PDF,
# so that the release script, or a person, can capture it.
echo "Building the description for $version" >&2

# swift run, the same way the test suite is run: BuildHandout is a target and not a product of
# the package, because nothing outside this repository has any use for it. Everything the run
# prints goes to stderr — the build log and the path the tool reports — and the line below is
# the one thing on stdout.
swift run -c release --package-path "$root" BuildHandout "$version" "$pdf" >&2

echo "$pdf"
