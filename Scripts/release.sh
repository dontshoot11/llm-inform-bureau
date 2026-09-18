#!/bin/sh
# Takes a version from this machine to a release page on GitHub: the disk image, the PDF
# description, the tag and the text saying what changed and how it is installed.
#
# It exists because a release is four things that have to agree — the number in the app, the
# number in two file names, the tag and what the page says — and doing them by hand is doing
# them in a different order every time. Here the number is read once, from the same plist the
# image reads it from, and everything else is derived from it.
#
# Everything that can refuse comes before the first irreversible step. The tag is not made
# locally and pushed: `gh release create --target` makes it on GitHub together with the
# release, so an attempt that stops early leaves no tag to delete, no release to withdraw and
# nothing in this repository to clean up.
#
# The author releases from the image like everybody else installs from it — there is no
# developer-only path here either. What this script does that a person cannot is nothing; what
# it does is stop before a half-made release.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

usage() {
	cat >&2 <<'TXT'
Usage: Scripts/release.sh <notes-file>|-

  <notes-file>  What changed in this version, in Markdown: the top of the release page.
                `-` reads it from standard input instead.

A notes file inside the repository would leave the tree dirty, which this script refuses —
so keep it outside, or pipe the text in:

Scripts/release.sh - <<'NOTES'
- The interface speaks Russian as well as English.
NOTES
TXT
}

# 1. What changed. Asked for first because it is the one thing the script cannot work out for
# itself, and because finding out at the end that there is nothing to say would mean finding
# out after the building.
[ $# -eq 1 ] || { usage; exit 1; }
case "$1" in
-)
	notes=$(cat)
	;;
*)
	[ -r "$1" ] || { echo "No notes to publish: cannot read $1" >&2; exit 1; }
	notes=$(cat "$1")
	;;
esac
# Anything that is only whitespace counts as empty: a release page whose first half is blank
# says less than no release page at all.
case "$(printf '%s' "$notes" | tr -d '[:space:]')" in
"") echo "No notes to publish: the notes are empty, and the release page needs to say what changed" >&2; exit 1 ;;
esac

# 2. The tool that publishes. Both halves are checked: installed, and logged in to an account
# that may write here. Without the second, everything below would build and then fail at the
# last line.
command -v gh >/dev/null 2>&1 || {
	echo "gh is not installed — it is what publishes the release (brew install gh)" >&2
	exit 1
}
gh auth status >/dev/null 2>&1 || {
	echo "gh is installed but not logged in — run: gh auth login" >&2
	exit 1
}

# 3. A clean tree. The image is built from the working copy, and the release points at a
# commit: with anything uncommitted those two are different things, and the difference is
# invisible on the page afterwards.
dirty=$(git -C "$root" status --porcelain)
[ -z "$dirty" ] || {
	echo "The tree is not clean — the image would carry changes no commit has:" >&2
	printf '%s\n' "$dirty" >&2
	exit 1
}

# 4. The number, from the one place that has it.
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/Scripts/Info.plist")
[ -n "$version" ] || { echo "No CFBundleShortVersionString in Scripts/Info.plist" >&2; exit 1; }
tag="v$version"

# 5. This version is not out already. Both halves again, because a tag without a release and a
# release without a tag are both states this would otherwise walk into: publishing over a
# release is not possible, and reusing a tag would point a new page at an old commit.
if gh release view "$tag" >/dev/null 2>&1; then
	echo "$tag is already released — bump CFBundleShortVersionString in Scripts/Info.plist" >&2
	exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
	echo "$tag is already a tag on GitHub, without a release — delete the tag or bump the version" >&2
	exit 1
fi

# 6. The commit is on GitHub. The release is made against a sha, and a sha GitHub has never
# seen cannot be tagged there: without this check the refusal arrives from the last line,
# after a full build, wearing gh's wording rather than ours.
sha=$(git -C "$root" rev-parse HEAD)
if ! gh api "repos/{owner}/{repo}/commits/$sha" >/dev/null 2>&1; then
	echo "HEAD ($sha) is not on GitHub — push the branch first: git push" >&2
	exit 1
fi

echo "Releasing $tag from $sha" >&2

# Nothing above this line has changed anything, here or on GitHub. Below it, the two files are
# built locally — still nothing published — and the last command is the whole of the release.
dmg=$("$root/Scripts/build-dmg.sh")
pdf=$("$root/Scripts/build-handout.sh")

# The page's own text. It is written here, as a heredoc, for the reason INSTALL.txt is written
# inside build-dmg.sh: it names the version it is published with, and a copy kept in the
# repository is a copy that drifts from the script that publishes it. The steps are the short
# form — the long form rides on the image as INSTALL.txt, and the page says so.
body=$(mktemp)
trap 'rm -f "$body"' EXIT INT TERM
cat > "$body" <<TXT
$notes

## Install

macOS 13 or newer, Apple Silicon or Intel. Nothing is compiled on your side, there is nothing
to sign in to, and the app makes no network calls. Download \`LLMInformBureau-$version.dmg\`
below, then:

1. Open it. It mounts as a volume named \`LLMInformBureau\`.
2. Drag \`LLMInformBureau.app\` onto the Applications shortcut beside it.
3. In Terminal:

       xattr -d -r com.apple.quarantine /Applications/LLMInformBureau.app

4. Open it from Launchpad. It has no Dock icon — it appears at the right-hand end of the menu
   bar and opens one window explaining where each of its numbers comes from.

Step 3 is what lets macOS run it, and it has to come after the drag, because the mark it
removes is on the installed copy. This app is signed ad-hoc rather than with a paid Apple
developer account, so anything of it that came over the network is refused until that mark is
gone. If you opened the app before running it, macOS says "Apple could not verify" — press
"Done", not the blue button, which removes the app instead of the mark.

No script of anybody else's runs on your Mac: the drag and that one line are the whole of it.

\`INSTALL.txt\` on the image says all of this at length, including what the app asks you before
it touches Claude Code's settings. \`LLMInformBureau-$version.pdf\`, beside the image below,
says what the app is for and what each of its lights means — worth reading before installing
anything.
TXT

# One command, and the only irreversible one: it makes the tag on GitHub, creates the page and
# uploads both files. --target pins it to the commit checked above rather than to whatever the
# default branch has drifted to.
gh release create "$tag" \
	--target "$sha" \
	--title "LLM Inform Bureau $version" \
	--notes-file "$body" \
	"$dmg" "$pdf" >&2

# The only thing on stdout: the page that now exists.
gh release view "$tag" --json url --jq .url
