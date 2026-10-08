#!/usr/bin/env bash
# look-ledger.sh — which built pages are owed a LOOK, and which screenshots were actually seen.
#
#   bin/look-ledger.sh owe <script.mdl>   called by bin/exec.sh after a script lands
#   bin/look-ledger.sh seen               PostToolUse(Read) hook; reads the hook JSON on stdin
#   bin/look-ledger.sh status             prints one line per owed page: SEEN or OWED
#   bin/look-ledger.sh unseen             owed pages nothing accounts for (exec.sh's LOOK guard reads this)
#   bin/look-ledger.sh creates <script>   pages a script CREATEs (not ALTERs)
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
# the Stage 5 "done" claim. Since #232 bin/exec.sh also refuses a script that CREATEs pages while
# more than LOOK_OWED_MAX are unseen (`unseen` below); fixes (ALTER PAGE) always run. Otherwise
# nothing here blocks a write — only the claim that a module is done while a page in it has never been looked at.
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
  awk -v creates_only="${LOOK_CREATES_ONLY:-0}" '
    /^[[:space:]]*\/\*/ { inc=1 }
    inc { if ($0 ~ /\*\//) inc=0; next }
    /^[[:space:]]*--/ { next }
    { l=toupper($0) }
    l ~ /^[[:space:]]*(CREATE([[:space:]]+OR[[:space:]]+(REPLACE|MODIFY))?|ALTER)[[:space:]]+PAGE[[:space:]]/ {
      s=$0; sub(/^[[:space:]]*/, "", s)
      if (creates_only == 1 && toupper(s) ~ /^ALTER[[:space:]]/) next
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

# look_unseen — the owed pages nothing accounts for, one Module.Page per line (exec.sh refuses on
# the count; gate-check.sh Stage 5 computes the same join inline). A page is accounted for by a
# screenshot the Read hook saw (status SEEN), a PROOF-OF-LOOK citation in a ui-review report
# (screenshot >=10KB, newer than the build) — evidence this script did not create — or a
# `Waived obligation look/<Module or Module.Page>` register line.
look_unseen() {
  local st page epoch rep line shot f sz mt proofs="" reg="$PROJECT_ROOT/PROJECT.md"
  for rep in "$PROJECT_ROOT"/design/ui-reviews/ui-review-*.html; do
    [ -f "$rep" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      page=$(printf '%s' "$line" | sed 's/^PROOF-OF-LOOK:[[:space:]]*//;s/[[:space:]]*=.*$//')
      shot=$(printf '%s' "$line" | sed 's/^.*=[[:space:]]*//')
      case "$shot" in /*) f="$shot" ;; *) f="$(dirname "$rep")/$shot" ;; esac
      [ -f "$f" ] || continue
      sz=$(wc -c < "$f" 2>/dev/null | tr -d ' '); [ "${sz:-0}" -ge 10240 ] || continue
      proofs="$proofs$page	$(_mtime "$f")
"
    done <<EOF
$(tr -d '\r' < "$rep" | grep -oE 'PROOF-OF-LOOK:[[:space:]]*[^=<]+=[[:space:]]*[^<>[:space:]]+')
EOF
  done
  while IFS=$'\t' read -r st page epoch; do
    [ "$st" = OWED ] || continue
    if [ -n "$proofs" ] && printf '%s' "$proofs" \
         | awk -F'\t' -v p="$page" -v e="$epoch" '$1==p && $2+0>=e+0 {f=1} END {exit !f}'; then continue; fi
    if [ -f "$reg" ] && grep -qiE "Waived obligation look(/${page%%.*}(\.${page#*.})?)?[[:space:]]*:" "$reg" 2>/dev/null; then continue; fi
    echo "$page"
  done <<EOF
$(look_status)
EOF
}

case "${1:-}" in
  owe)    shift; cmd_owe "$@" ;;
  seen)   cmd_seen ;;
  status) look_status ;;
  pages)  shift; look_pages_in "${1:-/dev/null}" ;;
  creates) shift; LOOK_CREATES_ONLY=1 look_pages_in "${1:-/dev/null}" ;;
  unseen)  look_unseen ;;
  *) echo "usage: $0 owe <script.mdl> | seen < hook-json | status | unseen | pages|creates <script.mdl>" >&2; exit 2 ;;
esac
exit 0
