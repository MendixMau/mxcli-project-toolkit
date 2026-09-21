#!/usr/bin/env bash
# sync-labels.sh — apply .github/labels.yml to a GitHub repo's label set, idempotently.
#
# Input: .github/labels.yml (a flat YAML list of `- name: / color: / description:` entries;
# schema documented in that file's own header). That file is produced and maintained by hand —
# edit it, then run this script; do not create or edit labels in the GitHub UI, or the next
# sync cannot tell your change from drift and will not revert it.
#
#   bin/sync-labels.sh                    # apply via `gh label create --force` (idempotent:
#                                          #   creates a missing label, updates an existing
#                                          #   one's color/description, never removes a label
#                                          #   this file doesn't list)
#   bin/sync-labels.sh --dry-run          # print exactly what would run/be printed, do nothing
#   bin/sync-labels.sh --repo OWNER/NAME  # override the repo (default: `gh repo view` when gh
#                                          # is present, otherwise the curl fallback requires it)
#
# When the `gh` CLI is not on PATH (or not authenticated), this NEVER calls the GitHub REST API
# itself — it prints the equivalent `curl` calls to stdout instead, so a maintainer without `gh`
# installed can still see, review and run them by hand. This is a deliberate scope limit, not a
# missing feature: printing avoids embedding a second, unauthenticated HTTP code path that would
# need its own error handling and its own leak-guard review for a token in a command line.
#
# Bash 3.2 compatible (macOS ships 3.2.57): no mapfile, no associative arrays, no ${var,,}.
# No python — labels.yml's shape (one `- name:` / `color:` / `description:` triple per entry,
# no nested lists, no multi-line values) is simple enough to parse with awk alone; reaching for
# a YAML library would trade a portability dependency for no real parsing benefit here.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LABELS_FILE="$ROOT/.github/labels.yml"

DRY=0
REPO=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --repo) REPO="__NEXT__" ;;
    *)
      if [ "$REPO" = "__NEXT__" ]; then REPO="$a";
      else
        case "$a" in
          -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
          *) echo "sync-labels.sh: unknown argument '$a'" >&2; exit 2 ;;
        esac
      fi
      ;;
  esac
done
[ "$REPO" = "__NEXT__" ] && { echo "sync-labels.sh: --repo needs a value (OWNER/NAME)" >&2; exit 2; }

[ -f "$LABELS_FILE" ] || { echo "sync-labels.sh: $LABELS_FILE not found" >&2; exit 2; }

HAVE_GH=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  HAVE_GH=1
fi

if [ -z "$REPO" ] && [ "$HAVE_GH" -eq 1 ]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [ -z "$REPO" ] && [ "$HAVE_GH" -eq 0 ]; then
  REPO="OWNER/REPO"
  echo "sync-labels.sh: gh not present/authenticated and no --repo given — using a placeholder" >&2
  echo "  repo name 'OWNER/REPO' in the printed curl calls below; pass --repo to fix that." >&2
fi

# Parse labels.yml into TSV (name<TAB>color<TAB>description), one line per label entry.
rows="$(awk '
  /^- name:/ {
    if (name != "") { print name "\t" color "\t" desc }
    name = $0; sub(/^- name: */, "", name)
    color = ""; desc = ""
    next
  }
  /^  color:/    { color = $0; sub(/^  color: */, "", color); next }
  /^  description:/ { desc = $0; sub(/^  description: */, "", desc); next }
  END { if (name != "") print name "\t" color "\t" desc }
' "$LABELS_FILE")"

[ -n "$rows" ] || { echo "sync-labels.sh: no '- name:' entries parsed from $LABELS_FILE" >&2; exit 2; }

echo "$rows" | while IFS="$(printf '\t')" read -r name color desc; do
  [ -n "$name" ] || continue
  if [ "$HAVE_GH" -eq 1 ]; then
    if [ "$DRY" -eq 1 ]; then
      echo "[dry-run] gh label create \"$name\" --color \"$color\" --description \"$desc\" --force --repo \"$REPO\""
    else
      gh label create "$name" --color "$color" --description "$desc" --force --repo "$REPO"
    fi
  else
    # PUT is idempotent server-side (create-or-update semantics differ by GitHub API version,
    # so this documents the two-step create-then-update sequence that always works): try
    # create, and note that a 422 (already exists) means re-run with PATCH against
    # /labels/<name> instead. Printed only — never executed — per the header note above.
    echo "curl -sS -X POST -H \"Authorization: token \$GH_TOKEN\" -H \"Accept: application/vnd.github+json\" \\"
    echo "  https://api.github.com/repos/$REPO/labels \\"
    echo "  -d '{\"name\":\"$name\",\"color\":\"$color\",\"description\":\"$desc\"}'"
    echo "# if that 422s (label already exists), instead:"
    echo "curl -sS -X PATCH -H \"Authorization: token \$GH_TOKEN\" -H \"Accept: application/vnd.github+json\" \\"
    echo "  \"https://api.github.com/repos/$REPO/labels/$(printf '%s' "$name" | sed 's/ /%20/g')\" \\"
    echo "  -d '{\"new_name\":\"$name\",\"color\":\"$color\",\"description\":\"$desc\"}'"
  fi
done

n="$(printf '%s\n' "$rows" | grep -c .)"
if [ "$HAVE_GH" -eq 1 ]; then
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] would sync $n labels to $REPO via gh label create --force"
  else
    echo "Synced $n labels to $REPO"
  fi
else
  echo "# $n labels above — gh not present/authenticated, nothing was sent"
fi
