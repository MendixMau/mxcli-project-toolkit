#!/usr/bin/env bash
# cut-release.sh — turn CHANGELOG.md's `## Unreleased` section into a dated release and tag it.
#
#   bin/cut-release.sh                 # today's date: vYYYY.MM.DD
#   bin/cut-release.sh v2026.09.22     # an explicit name (must match vYYYY.MM.DD[-suffix])
#   bin/cut-release.sh --dry-run       # print what would happen, touch nothing
#
# The release cycle it implements is defined at the top of CHANGELOG.md, nowhere else: new lines
# land under `## Unreleased`; every few days this script renames that heading to `## vYYYY.MM.DD`,
# commits CHANGELOG.md alone (explicit path — this tree is shared by several sessions), tags the
# commit, and opens a fresh empty `## Unreleased` above it. It does NOT push: look at the commit
# and the tag, then `git push origin master vYYYY.MM.DD` yourself.
#
# Refuses (exit 2) rather than guesses when: not on master, CHANGELOG.md has uncommitted edits,
# `## Unreleased` is missing or empty, or the tag already exists. Bash 3.2, no sed -i.
set -eu

DRY=0; NAME=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    v*) NAME="$a" ;;
    *) echo "cut-release.sh: unknown argument '$a'" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CL="$ROOT/CHANGELOG.md"
[ -n "$NAME" ] || NAME="v$(date +%Y.%m.%d)"

die() { echo "cut-release.sh: $*" >&2; exit 2; }

case "$NAME" in
  v[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]|v[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]-*) ;;
  *) die "release name must look like vYYYY.MM.DD (got '$NAME')" ;;
esac

branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
[ "$branch" = "master" ] || die "cut releases from master only (on '$branch')"
[ -z "$(git -C "$ROOT" status --porcelain -- CHANGELOG.md)" ] || die "CHANGELOG.md has uncommitted changes — commit or drop them first"
git -C "$ROOT" rev-parse -q --verify "refs/tags/$NAME" >/dev/null && die "tag $NAME already exists"
grep -q '^## Unreleased$' "$CL" || die "no '## Unreleased' heading in CHANGELOG.md"

# Entries (`- kind(area): ...` lines) between `## Unreleased` and the next `## ` heading. Zero = nothing to release.
count="$(awk '/^## Unreleased$/{on=1; next} on && /^## /{exit} on && /^- /{n++} END{print n+0}' "$CL")"
[ "$count" -gt 0 ] || die "'## Unreleased' is empty — nothing to release"

echo "Release $NAME: $count entr$( [ "$count" -eq 1 ] && echo y || echo ies) under '## Unreleased' become '## $NAME'"
if [ "$DRY" -eq 1 ]; then
  echo "(--dry-run: nothing written, no commit, no tag)"
  exit 0
fi

tmp="$CL.tmp.$$"
awk -v name="$NAME" '
  /^## Unreleased$/ && !done { print "## Unreleased"; print ""; print "## " name; done=1; next }
  { print }
' "$CL" > "$tmp" && mv "$tmp" "$CL"

git -C "$ROOT" add -- CHANGELOG.md
git -C "$ROOT" commit -q -m "Release $NAME" -- CHANGELOG.md
git -C "$ROOT" tag -a "$NAME" -m "Toolkit release $NAME"
echo "Committed $(git -C "$ROOT" rev-parse --short HEAD) and tagged $NAME. Review, then:"
echo "  git push origin master $NAME"
