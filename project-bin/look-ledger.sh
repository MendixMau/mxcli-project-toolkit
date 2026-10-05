#!/usr/bin/env bash
# look-ledger.sh — which built pages are owed a LOOK, and which screenshots were actually seen.
#
#   bin/look-ledger.sh owe <script.mdl>   called by bin/exec.sh after a script lands
#   bin/look-ledger.sh seen               PostToolUse(Read) hook; reads the hook JSON on stdin
#   bin/look-ledger.sh status             prints one line per owed page: SEEN or OWED
#
# WHY (2026-10-02). Two unattended builds, run side by side with the same toolkit, built every
# page and never once opened a screenshot of one. Both ran page-fidelity.js, a text score, and
# called the module done. The LOOK was routed (ui-loop.md, module-review.md), had an obligation
# row, and had a PROOF-OF-LOOK rule — and all three are about a REPORT. A build that writes no
# report owes nothing anyone checks at the moment it claims "done", so the pass was skipped
# twice, silently, on the screens a reviewer sees first. Both arms filed the same bug.
#
# So this records two facts, neither of them a judgement:
#   owed  — exec.sh writes one row per page a script CREATEs or ALTERs, when the script lands.
#   seen  — the Read hook writes one row per image file the agent actually opened.
# gate-check.sh's Stage 5 check joins them: a page built after its last seen screenshot FAILs
# the Stage 5 "done" claim. Nothing here blocks a write, a script, or the next page — only the
# claim that a module is done while a page in it has never been looked at.
#
# How a screenshot names its page: the image's file name must contain the page name, compared
# with case and punctuation removed — Orders.Order_Overview is seen by order-overview.png,
# Order_Overview_1280.png or orders_order_overview.png. The screenshot must also be newer than
# the build that owes it, and opened after it: re-reading last week's capture does not count.
# Wireframe renders (any path containing /wireframes/) never count — they are the target, not
# the app.
#
# Files (both TSV, both append-only, both under .claude/loop/look/):
#   owed.tsv   epoch  iso-time  Module.Page  script
#   seen.tsv   epoch  iso-time  image-path   image-mtime  sha256
#
# Producer for every consumer (CLAUDE.md "Shipping an instrument" rule 5): owed.tsv is written
# by bin/exec.sh, the mandatory write path; seen.tsv by the PostToolUse hook that
# bin/install-claude-permissions.sh installs into the project's .claude/settings.json (run by
# init-project.sh and sync-project.sh). gate-check.sh also accepts evidence it did not create:
# a PROOF-OF-LOOK citation in a ui-review report (module-review.md stage 5).
#
# Fail-open everywhere: a hook that errors must never break a Read, and `owe` must never fail
# the exec that called it. Bash 3.2 compatible.

set -u
. "$(dirname "$0")/_common.sh"

LOOK_DIR="$PROJECT_ROOT/.claude/loop/look"
OWED="$LOOK_DIR/owed.tsv"
SEEN="$LOOK_DIR/seen.tsv"

# mtime in whole seconds, GNU first (on GNU `stat -f` succeeds with a different meaning).
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

_sha() {
  { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null; } | awk '{print $1; exit}'
}

# Every page a script writes, as Module.Page, one per line, unquoted, in script order.
# Shapes captured from real build scripts: CREATE / CREATE OR REPLACE / CREATE OR MODIFY / ALTER,
# either case, each half of the name quoted or bare. Block comments and -- lines are skipped so a
# commented-out page is not owed.
look_pages_in() {
  awk '
    /^[[:space:]]*\/\*/ { inc=1 }
    inc { if ($0 ~ /\*\//) inc=0; next }
    /^[[:space:]]*--/ { next }
    { l=toupper($0) }
    l ~ /^[[:space:]]*(CREATE([[:space:]]+OR[[:space:]]+(REPLACE|MODIFY))?|ALTER)[[:space:]]+PAGE[[:space:]]/ {
      s=$0; sub(/^[[:space:]]*/, "", s)
      n=split(s, w, /[[:space:]]+/)
      for (i=1; i<=n; i++) if (toupper(w[i])=="PAGE") { name=w[i+1]; break }
      sub(/[(;{].*$/, "", name); gsub(/"/, "", name)
      if (name ~ /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/) print name
    }' "$1" 2>/dev/null | awk '!seen[$0]++'
}

cmd_owe() {
  local script="${1:-}" now iso p n=0
  [ -f "$script" ] || return 0
  mkdir -p "$LOOK_DIR" 2>/dev/null || return 0
  now=$(date +%s); iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$now" "$iso" "$p" "${script#"$PROJECT_ROOT"/}" >> "$OWED" && n=$((n+1))
  done <<EOF
$(look_pages_in "$script")
EOF
  if [ "$n" -gt 0 ]; then
    echo "  👁  $n page(s) built — each is owed a LOOK: screenshot it, open the PNG, compare to its"
    echo "     wireframe (skills/ui-loop.md). Stage 5 will not pass while one is unseen."
  fi
  return 0
}

cmd_seen() {
  local input path src mt
  input=$(cat 2>/dev/null) || return 0
  if command -v jq >/dev/null 2>&1; then
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  else
    path=$(printf '%s' "$input" | tr -d '\n' \
      | sed -n 's/.*"tool_input"[[:space:]]*:[[:space:]]*{[^}]*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | sed 's/\\\\/\\/g')
  fi
  [ -n "$path" ] || return 0
  case "$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')" in
    png|jpg|jpeg|webp|gif) ;;
    *) return 0 ;;
  esac
  path=$(mxtk_posix_path "$path")
  # shrink-image-read.sh may have swapped the Read onto a downscaled copy; it leaves the
  # original path beside the copy, so the ledger names the screenshot the agent meant.
  src="${path%.*}.src"
  [ -s "$src" ] && path=$(head -1 "$src")
  case "$path" in */wireframes/*) return 0 ;; esac
  [ -f "$path" ] || return 0
  mkdir -p "$LOOK_DIR" 2>/dev/null || return 0
  mt=$(_mtime "$path")
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$path" "$mt" "$(_sha "$path")" >> "$SEEN" 2>/dev/null
  return 0
}

# look_status — one line per owed page, newest build only:  SEEN|OWED <TAB> Module.Page <TAB> epoch
# One awk pass over both ledgers: a per-row fork costs ~150ms under Git Bash on Windows, and a
# join of 50 pages against 300 reads would otherwise take minutes (obligation-check.sh, 2026-08-25).
look_status() {
  [ -s "$OWED" ] || return 0
  local seenf=/dev/null
  [ -s "$SEEN" ] && seenf="$SEEN"
  # The seen ledger is read with getline in BEGIN, not as a first file: FNR==NR is also true
  # for the second file when the first is empty, which would read owed rows as screenshots.
  awk -F'\t' -v seenf="$seenf" '
    function norm(s) { s=tolower(s); gsub(/[^a-z0-9]/, "", s); return s }
    BEGIN {
      while ((getline line < seenf) > 0) {
        if (split(line, f, "\t") < 5) continue
        n++; at[n]=f[1]+0; mt[n]=f[4]+0; b=f[3]; sub(/.*[\/\\]/, "", b); base[n]=norm(b)
      }
    }
    NF>=3 { if (!($3 in last) || $1+0 > last[$3]) last[$3]=$1+0 }
    END {
      for (p in last) {
        short=p; sub(/^[^.]*\./, "", short); short=norm(short); ok=0
        for (i=1; i<=n; i++)
          if (at[i]>=last[p] && mt[i]>=last[p] && index(base[i], short)) { ok=1; break }
        print (ok ? "SEEN" : "OWED") "\t" p "\t" last[p]
      }
    }' "$OWED" 2>/dev/null | sort -k2,2
}

case "${1:-}" in
  owe)    shift; cmd_owe "$@" ;;
  seen)   cmd_seen ;;
  status) look_status ;;
  pages)  shift; look_pages_in "${1:-/dev/null}" ;;
  *) echo "usage: $0 owe <script.mdl> | seen < hook-json | status | pages <script.mdl>" >&2; exit 2 ;;
esac
exit 0
