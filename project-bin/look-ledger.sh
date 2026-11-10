#!/usr/bin/env bash
# look-ledger.sh — which built pages are owed a LOOK, and which screenshots were actually seen.
#
#   bin/look-ledger.sh owe <script.mdl>   called by bin/exec.sh after a script lands
#   bin/look-ledger.sh seen               PostToolUse(Read) hook; reads the hook JSON on stdin
#   bin/look-ledger.sh status             prints one line per owed page: SEEN or OWED
#   bin/look-ledger.sh reshoot [Module] [--all]
#                                         which pages a polish round must re-shoot (390 + 1280): the pages
#                                         built after their last seen LOOK, plus every page when a layout,
#                                         snippet or style file changed after it. K of N, never silence
#   bin/look-ledger.sh shots [findings.json...]
#                                         which owed page a journey run's screenshots already show:
#                                         OPEN <page> <png> (read it), UNREACHED <page> (no journey did)
#
# WHY (2026-10-02). Two unattended builds, run side by side with the same toolkit, built every
# page and never once opened a screenshot of one. Both ran page-fidelity.js, a text score, and
# called the module done. The LOOK was routed (ui-loop.md, module-review.md), had an obligation
# row, and had a PROOF-OF-LOOK rule — and all three are about a REPORT. A build that writes no
# report owes nothing anyone checks at the moment it claims "done", so the pass was skipped
# twice, silently, on the screens a reviewer sees first. Both arms filed the same bug.
#
# So this records two facts, neither of them a judgement:
#   owed  — exec.sh writes one row per page a script CREATEs or ALTERs, when the script lands;
#           a script that DROPs a page removes that page's rows (#681) until one re-creates it.
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
# JOURNEY SHOTS ARE LOOK EVIDENCE TOO (speed experiment E2, 2026-10-29). A journey run already
# screenshots every step it reaches, so a separate screenshot pass re-shot screens it had visited
# (E2: journey shots covered 5 of 8 pages, two minimal gap-fill journeys the other 3, and
# page-audit's role shots reached 4 of 8 and none of the popup/parameter pages). `shots` maps each
# reached step's screenshot to the ONE page whose widgets it landed on (project-bin/look-shots.js)
# and writes shots.tsv. look_status then counts a page SEEN when the agent opened such a shot
# (seen.tsv) after the page's last build, exactly as for a page-named file. Seeing stays the
# reviewer's act; only the "file name must contain the page name" restriction is lifted for
# attributed shots. Every OWED page ends in one of two lists: OPEN (a shot exists, read it) or
# UNREACHED (no journey got there: a short gap-fill journey, or page-audit.js as the fallback).
# Producer: journey-runner.js calls `shots` after it writes its findings (fail-open).
#
# Files (all TSV, under .claude/loop/look/; seen is append-only, owed is append-only except that a
# DROP PAGE removes the dropped page's rows, shots is rewritten):
#   owed.tsv   epoch  iso-time  Module.Page  script
#   seen.tsv   epoch  iso-time  image-path   image-mtime  sha256
#   shots.tsv  epoch  iso-time  Module.Page  image-path   image-mtime  journey  step
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
_lsd="${0%/*}"; [ "$_lsd" != "$0" ] || _lsd=.   # dirname without a process
. "$_lsd/_common.sh"

LOOK_DIR="$PROJECT_ROOT/.claude/loop/look"
OWED="$LOOK_DIR/owed.tsv"
SEEN="$LOOK_DIR/seen.tsv"
SHOTS="$LOOK_DIR/shots.tsv"
SHARED="$LOOK_DIR/shared.tsv"

# mtime in whole seconds, GNU first (on GNU `stat -f` succeeds with a different meaning).
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

_sha() {
  { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null; } | awk '{print $1; exit}'
}

# Every page a script writes, as Module.Page, one per line, unquoted, in script order.
# Shapes captured from real build scripts: CREATE / CREATE OR REPLACE / CREATE OR MODIFY / ALTER,
# either case, each half of the name quoted or bare. Block comments and -- lines are skipped so a
# commented-out page is not owed.
# DROP PAGE [IF EXISTS] <name> (#681): the LAST statement on a page in the script decides. A page
# created then dropped is not printed; `look_pages_in <script> drop` lists the pages the script
# ends without. One dropped then re-created is owed.
look_pages_in() {
  awk -v mode="${2:-owe}" '
    /^[[:space:]]*\/\*/ { inc=1 }
    inc { if ($0 ~ /\*\//) inc=0; next }
    /^[[:space:]]*--/ { next }
    { l=toupper($0); act="" }
    l ~ /^[[:space:]]*(CREATE([[:space:]]+OR[[:space:]]+(REPLACE|MODIFY))?|ALTER)[[:space:]]+PAGE[[:space:]]/ { act="owe" }
    l ~ /^[[:space:]]*DROP[[:space:]]+PAGE[[:space:]]/ { act="drop" }
    act != "" {
      s=$0; sub(/^[[:space:]]*/, "", s)
      n=split(s, w, /[[:space:]]+/); j=0
      for (i=1; i<=n; i++) if (toupper(w[i])=="PAGE") { j=i+1; break }
      if (act=="drop" && toupper(w[j])=="IF" && toupper(w[j+1])=="EXISTS") j+=2
      name=w[j]
      sub(/[(;{].*$/, "", name); gsub(/"/, "", name)
      if (name ~ /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/) { if (!(name in last)) ord[++k]=name; last[name]=act }
    }
    END { for (i=1; i<=k; i++) if (last[ord[i]]==mode) print ord[i] }' "$1" 2>/dev/null
}

# Every layout or snippet a script writes: "<kind> <Module.Name>", one per line (same comment rules as look_pages_in).
look_shared_in() {
  awk '
    /^[[:space:]]*\/\*/ { inc=1 }
    inc { if ($0 ~ /\*\//) inc=0; next }
    /^[[:space:]]*--/ { next }
    { l=toupper($0) }
    l ~ /^[[:space:]]*(CREATE([[:space:]]+OR[[:space:]]+(REPLACE|MODIFY))?|ALTER|DROP)[[:space:]]+(LAYOUT|SNIPPET)[[:space:]]/ {
      s=$0; sub(/^[[:space:]]*/, "", s); n=split(s, w, /[[:space:]]+/)
      for (i=1; i<=n; i++) { u=toupper(w[i]); if (u=="LAYOUT" || u=="SNIPPET") { k=tolower(u); j=i+1; break } }
      if (toupper(w[j])=="IF" && toupper(w[j+1])=="EXISTS") j+=2
      name=w[j]; sub(/[(;{].*$/, "", name); gsub(/"/, "", name)
      if (name ~ /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/) print k "\t" name
    }' "$1" 2>/dev/null
}

# _forget_dropped <script> — remove every owed.tsv row of a page the script ends by dropping
# (#681): a dropped page cannot be looked at, so it leaves the denominator. A later script that
# re-creates it appends a fresh row, which owes again. Rewritten through a temp file + mv.
_forget_dropped() {
  local drops tmp
  [ -s "$OWED" ] || return 0
  drops="$(look_pages_in "$1" drop)"
  [ -n "$drops" ] || return 0
  tmp="$OWED.tmp.$$"
  if printf '%s\n' "$drops" | awk -F'\t' 'NR==FNR { d[$0]=1; next } !($3 in d)' - "$OWED" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$OWED" 2>/dev/null
  fi
  [ -f "$tmp" ] && rm -f -- "$tmp"
  return 0
}

cmd_owe() {
  local script="${1:-}" now iso p n=0
  [ -f "$script" ] || return 0
  [ -d "$LOOK_DIR" ] || mkdir -p "$LOOK_DIR" 2>/dev/null || return 0
  _forget_dropped "$script"
  if [ -n "${EPOCHSECONDS:-}" ]; then now=$EPOCHSECONDS; TZ=UTC printf -v iso '%(%Y-%m-%dT%H:%M:%SZ)T' -1   # bash 5: no date process
  else now=$(date +%s); iso=$(date -u +%Y-%m-%dT%H:%M:%SZ); fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$now" "$iso" "$p" "${script#"$PROJECT_ROOT"/}" >> "$OWED" && n=$((n+1))
  done <<EOF
$(look_pages_in "$script")
EOF
  # A layout or snippet change alters pages this script never names: recorded apart from owed.tsv (it is
  # not a page and cannot be SEEN), read by `reshoot` so a polish round after it re-shoots every page.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$now" "$iso" "$p" "${script#"$PROJECT_ROOT"/}" >> "$SHARED" 2>/dev/null
  done <<EOF
$(look_shared_in "$script")
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
look_status() { _look_status_ex | cut -f1-3; }
# _look_status_ex — look_status plus, for a SEEN page, the epoch and path of its newest matching screenshot
# (cols 4, 5; 0 and empty when OWED). `status` still prints cols 1-3 only: other tools parse those.
_look_status_ex() {
  [ -s "$OWED" ] || return 0
  local seenf=/dev/null shotf=/dev/null
  [ -s "$SEEN" ] && seenf="$SEEN"
  [ -s "$SHOTS" ] && shotf="$SHOTS"
  # The seen ledger is read with getline in BEGIN, not as a first file: FNR==NR is also true
  # for the second file when the first is empty, which would read owed rows as screenshots.
  awk -F'\t' -v seenf="$seenf" -v shotf="$shotf" '
    function norm(s) { s=tolower(s); gsub(/[^a-z0-9]/, "", s); return s }
    BEGIN {
      while ((getline line < seenf) > 0) {
        if (split(line, f, "\t") < 5) continue
        n++; at[n]=f[1]+0; mt[n]=f[4]+0; full[n]=f[3]; b=f[3]; sub(/.*[\/\\]/, "", b); base[n]=norm(b)
      }
      # journey shots attributed to a page (look-shots.js): page SUBSEP path -> image mtime
      while ((getline line < shotf) > 0) {
        if (split(line, g, "\t") < 5) continue
        shotmt[g[3] SUBSEP g[4]] = g[5]+0
      }
    }
    NF>=3 { if (!($3 in last) || $1+0 > last[$3]) last[$3]=$1+0 }
    END {
      for (p in last) {
        short=p; sub(/^[^.]*\./, "", short); short=norm(short); ok=0; sa=0; si=""
        for (i=1; i<=n; i++) {
          if (!(at[i]>=last[p] && mt[i]>=last[p])) continue
          if (index(base[i], short) || (((p SUBSEP full[i]) in shotmt) && shotmt[p SUBSEP full[i]]>=last[p])) {
            ok=1; if (at[i]>=sa) { sa=at[i]; si=full[i] }
          }
        }
        print (ok ? "SEEN" : "OWED") "\t" p "\t" last[p] "\t" sa "\t" si
      }
    }' "$OWED" 2>/dev/null | sort -k2,2
}

# cmd_shots [findings.json...] — rebuild shots.tsv from journey findings, then list every OWED page
# as OPEN (a journey shot of it exists: open the PNG) or UNREACHED (none does). Reads the model
# only with SHOW/DESCRIBE. Fail-open: exit 0 whatever happens, so journey-runner can call it.
cmd_shots() {
  [ -s "$OWED" ] || { echo "look shots: no owed pages (no $OWED)"; return 0; }
  local owed_pages owed_rows mx mpr tmp f found="" rc mods why="" q
  owed_rows="$(look_status | awk -F'\t' '$1 == "OWED" { print $2 "\t" $3 }')"
  owed_pages="$(printf '%s\n' "$owed_rows" | cut -f1 | sed '/^$/d')"
  if [ -z "$owed_pages" ]; then echo "look shots: 0 page(s) owed a LOOK"; return 0; fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/look-shots.XXXXXX")" || return 0
  if [ $# -gt 0 ]; then found="$*"; else
    found="$(find "$PROJECT_ROOT/${LOOK_ARTIFACTS_DIR:-tests/e2e/artifacts}" -maxdepth 3 -name 'journey-findings*.json' ! -name '*-control*.json' 2>/dev/null | sort | tr '\n' ' ')"
  fi
  mx="${MXCLI:-$(find_project_mxcli 2>/dev/null || true)}"; mpr="$(find_mpr 2>/dev/null || true)"
  : > "$tmp/widgets.tsv"; : > "$tmp/pages.tsv"; : > "$tmp/shots.tsv"
  if [ -z "${found// /}" ]; then why="no journey-findings*.json under ${LOOK_ARTIFACTS_DIR:-tests/e2e/artifacts} (no journey run yet)"
  elif [ -z "$mx" ] || [ ! -x "$mx" ] || [ -z "$mpr" ]; then why="no project mxcli or .mpr to read widget names from"
  elif ! command -v node >/dev/null 2>&1; then why="no node"
  else
    # Every page of the owed pages' modules, so "the one page with this widget" is judged against
    # its neighbours, not only against the pages that happen to be owed.
    mods="$(printf '%s\n' "$owed_pages" | sed 's/\..*//' | sort -u)"
    for f in $mods; do
      # the url column is read by header position, not by a guessed offset
      "$mx" -p "$mpr" -c "SHOW PAGES IN $f" 2>/dev/null | awk -F'|' -v OFS='\t' '
        /^\| *Qualified Name/ { for (i=1; i<=NF; i++) { h=$i; gsub(/ /, "", h); if (h == "url") uc=i }; next }
        $2 ~ /^ *[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]* *$/ { n=$2; gsub(/ /, "", n); u=(uc ? $uc : ""); gsub(/ /, "", u); print n, u }' >> "$tmp/pages.tsv"
    done
    cut -f1 "$tmp/pages.tsv" | sort -u > "$tmp/all.txt"
    if [ ! -s "$tmp/all.txt" ]; then why="SHOW PAGES listed no page"
    else
      q=""; while IFS= read -r f; do q="${q:+$q; }DESCRIBE PAGE $f"; done < "$tmp/all.txt"
      "$mx" -p "$mpr" -c "$q" > "$tmp/desc.out" 2>/dev/null; rc=$?
      if [ "$rc" -ne 0 ]; then why="DESCRIBE PAGE exit $rc"
      else
        # "create or modify page Module.Name" opens each page; widget heads are "<type> <name> (" or "{"
        awk -v OFS='\t' '
          /^create or (modify|replace) page / { p=$5; next }
          /^[ \t]*[a-z][a-z0-9]*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*[({]/ && p != "" && $1 != "create" { w=$2; sub(/[({].*/, "", w); print p, w }' "$tmp/desc.out" | sort -u > "$tmp/widgets.tsv"
        [ -s "$tmp/widgets.tsv" ] || why="DESCRIBE PAGE gave no widget names"
      fi
    fi
  fi
  if [ -z "$why" ]; then
    # shellcheck disable=SC2086
    node "$(dirname "$0")/look-shots.js" --root "$PROJECT_ROOT" --widgets "$tmp/widgets.tsv" --pages "$tmp/pages.tsv" --out "$tmp/shots.tsv" --prev "$SHOTS" $found >/dev/null 2>&1 \
      || why="look-shots.js failed"
  fi
  if [ -z "$why" ]; then
    # Image paths the way the Read hook spells them (Git Bash: /c/...), then replace the ledger.
    while IFS='	' read -r e i p img mt j n; do
      [ -n "$p" ] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$e" "$i" "$p" "$(mxtk_posix_path "$img")" "$mt" "$j" "$n"
    done < "$tmp/shots.tsv" > "$tmp/shots.posix"
    mkdir -p "$LOOK_DIR" 2>/dev/null && cp "$tmp/shots.posix" "$SHOTS" 2>/dev/null
  fi
  local total n_open=0 n_un=0 p shot since
  total="$(printf '%s\n' "$owed_pages" | wc -l | tr -d ' ')"
  echo "LOOK from journey screenshots: $total owed page(s)${why:+ (NOT MEASURED: $why)}"
  while IFS='	' read -r p since; do
    [ -n "$p" ] || continue
    shot=""
    # a shot older than the page's last build shows the previous build: not evidence, so UNREACHED
    [ -z "$why" ] && [ -s "$SHOTS" ] && shot="$(awk -F'\t' -v p="$p" -v since="${since:-0}" '$3 == p && $5+0 >= since+0 { s=$4; j=$6; n=$7 } END { if (s != "") print s "\t" j " step " n }' "$SHOTS")"
    if [ -n "$shot" ]; then n_open=$((n_open+1)); printf 'OPEN\t%s\t%s\t(journey %s)\n' "$p" "${shot%%	*}" "${shot#*	}"
    else n_un=$((n_un+1)); printf 'UNREACHED\t%s\tno journey step reached it: write a short gap-fill journey (the first steps of a journey that gets there, ending on a step whose ui.ready is a widget of this page), or run page-audit.js for it\n' "$p"; fi
  done <<LOOKSHOTS_PAGES
$owed_rows
LOOKSHOTS_PAGES
  echo "owed $total = $n_open OPEN (open each PNG; the Read hook then marks the page SEEN) + $n_un UNREACHED (listed above)"
  rm -rf "$tmp"
  return 0
}

# _style_newer_than <image> — the first theme/themesource .scss/.css file modified after that screenshot (relative
# path), or nothing. Per page, because a polish round that restyles after page A's shot but before page B's must
# not re-shoot B.
_style_newer_than() {
  local d f
  for d in "$PROJECT_ROOT/theme" "$PROJECT_ROOT/themesource"; do
    [ -d "$d" ] || continue
    f="$(find "$d" -type f \( -name '*.scss' -o -name '*.css' \) -not -path '*/node_modules/*' -newer "$1" 2>/dev/null | head -1)"
    [ -n "$f" ] && { printf '%s\n' "${f#"$PROJECT_ROOT"/}"; return 0; }
  done
  return 0
}

# cmd_reshoot [Module] [--all] — the pages a polish round re-shoots, and the denominator it closes against.
# A page is RESHOOT when it was built after its last seen LOOK (OWED), or when SEEN but a layout/snippet script
# (shared.tsv) or a theme/themesource .scss/.css file is newer than THAT page's screenshot: a shared change moves
# pages no script named. Everything else is SEEN at its last build and is NOT re-shot. K of N is always printed;
# an empty ledger is "NOT MEASURED" (full LOOK), never "0 of 0 to re-shoot". Reads the ledgers only.
cmd_reshoot() {
  local mod="" all=0 rows n k st pg built sa si iso reason f d
  while [ $# -gt 0 ]; do case "$1" in --all) all=1 ;; *) mod="$1" ;; esac; shift; done
  rows="$(_look_status_ex | awk -F'\t' -v m="$mod" 'm == "" || index($2, m ".") == 1')"
  n="$(printf '%s\n' "$rows" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$n" -eq 0 ]; then
    echo "reshoot ${mod:-all modules}: NOT MEASURED -- no owed page recorded${mod:+ for $mod} in $OWED. The LOOK denominator is unknown: run the full LOOK (390 + 1280, every page), not a narrowed one."
    return 0
  fi
  k=0
  while IFS='	' read -r st pg built sa si; do
    [ -n "$pg" ] || continue
    reason=""
    if [ "$st" = OWED ]; then
      if [ -n "${EPOCHSECONDS:-}" ]; then TZ=UTC printf -v iso '%(%Y-%m-%dT%H:%M:%SZ)T' "${built:-0}"; else iso="$(date -u -d "@${built:-0}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "${built:-0}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$built")"; fi
      reason="built $iso, after its last LOOK"
    elif [ "$all" = 1 ]; then reason="--all"
    elif [ -n "$si" ] && [ ! -f "$si" ]; then reason="its screenshot ${si##*/} is gone, so a style change cannot be ruled out"
    elif [ -n "$si" ] && f="$(_style_newer_than "$si")" && [ -n "$f" ]; then reason="style file changed after its last LOOK: $f"
    elif [ -s "$SHARED" ]; then
      f="$(awk -F'\t' -v sa="${sa:-0}" '$1+0 > sa+0 { print $3 " " $4; exit }' "$SHARED")"
      [ -n "$f" ] && reason="shared $f changed after its last LOOK"
    fi
    [ -n "$reason" ] || continue
    k=$((k+1)); printf 'RESHOOT\t%s\t%s\n' "$pg" "$reason"
  done <<RESHOOT_ROWS2
$rows
RESHOOT_ROWS2
  echo "reshoot ${mod:-all modules}: $k of $n page(s) to re-shoot at 390 and 1280; $((n-k)) SEEN after their last build and untouched by a layout, snippet or style change, so not re-shot. The look report keeps its headline 'N of N pages reviewed' (N=$n) and gains an addendum: its own VALID AT and $k PROOF-OF-LOOK line(s)."
  return 0
}

case "${1:-}" in
  reshoot) shift; cmd_reshoot "$@" ;;
  owe)    shift; cmd_owe "$@" ;;
  seen)   cmd_seen ;;
  status) look_status ;;
  shots)  shift; cmd_shots "$@" ;;
  pages)  shift; look_pages_in "${1:-/dev/null}" ;;
  *) echo "usage: $0 owe <script.mdl> | seen < hook-json | status | reshoot [Module] [--all] | shots [findings.json...] | pages <script.mdl>" >&2; exit 2 ;;
esac
exit 0
