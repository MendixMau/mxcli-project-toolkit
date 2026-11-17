#!/usr/bin/env bash
# ready.sh — the ONE way a module or an app is called READY / done. It runs the checks, prints
# K of N for each, writes the READY line itself and commits the evidence behind it.
#
# Usage: bin/ready.sh <project-root> [--module <M> | --app <A>] [--no-commit]
#   --module M   scope every check to module M (its pages, its must-have list, its review)
#   --app A      the whole app, labelled A (default: the whole project, labelled "app")
#   --no-commit  write the files, leave committing to the caller
# Exit 0 READY, 1 NOT READY, 2 usage. Bash 3.2 compatible.
#
# WHY (two field runs, 2026-11, both unattended). Run 1: the build agent wrote READY into its own
# status file and was graded done with 0 of ~78 built pages ever looked at. The look ledger was
# installed and active, and gate-check.sh's Stage 5 check would have FAILed the claim — but
# nobody ran it before claiming, and .claude/loop/ is git-ignored, so the orchestrator and the
# reviewers looking at the repo saw nothing (gate-check on a copy said MANUAL). Every look that
# did happen was the builder judging its own screens. Run 2, another kit, marked itself ready
# 3 hours before its time cap with no styling or review pass. A READY anyone may write by hand
# is a claim; this script makes it a verdict, and puts the evidence in git.
#
# THE CHECKS (each row prints K of N; a row nobody measured is NOT MEASURED and fails — never
# green-by-absence):
#   gate 5     gate-check.sh <root> 5. PASS/WAIVED, or MANUAL with the look accounted for (Stage 5
#              is MANUAL by design once the look is clear — its other half is a Decisions row).
#   gate 6     only when the register's "## Current stage" line is at Stage 6 or later.
#   look       pages owed a LOOK vs seen, per gate-check's own join (screenshots opened,
#              PROOF-OF-LOOK citations, waivers — evidence this script did not create, guard
#              rule 6). No page ever recorded as built and no `Waived obligation look` line:
#              NOT MEASURED, a fail.
#   must-have  the per-module must-have list, when the project has one: K ticked of N. Absent:
#              reported "not present", not counted.
#   review     only under `Interview mode: auto` (bin/interview-mode.sh): a verdict file written
#              by a DIFFERENT agent (skills/module-review.md "Independent look"), every page of
#              the scope scored 1-5 after its last build; a page below 4, or unscored, blocks.
#
# WHAT IT WRITES (all tracked, all small, no images):
#   docs/progress/ready-<date>-<scope>.md   the evidence: verdict, each row, owed vs seen per
#                                           module, unseen pages, the screenshot names relied on
#   docs/progress/ready.log                 one line per run: <iso> READY|NOT-READY <scope> <file>
#                                           — the READY line. An agent never writes it by hand.
#   docs/progress/look-summary.tsv          the git-ignored ledger's summary (look-ledger.sh summary)
# then `git commit -- <those paths>` (explicit paths: other sessions share the index).
#
# Producer for every consumer (CLAUDE.md "Shipping an instrument" rule 5): owed.tsv is written by
# exec.sh (the mandatory write path), seen.tsv by the Read hook install-claude-permissions.sh
# installs, the review file by the reviewer the lead dispatches (module-review.md), the must-have
# list by its own skill. ready.sh blocks nothing but the claim; it never blocks a write or a fix
# (guard rule 7): run it again after the fix.

set -u
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { echo "usage: ready.sh <project-root> [--module <M> | --app <A>] [--no-commit]" >&2; exit 2; }

ROOT=""; MOD=""; APP=""; COMMIT=1
while [ $# -gt 0 ]; do
  case "$1" in
    --module) shift; MOD="${1:-}"; [ -n "$MOD" ] || usage ;;
    --app)    shift; APP="${1:-}"; [ -n "$APP" ] || usage ;;
    --no-commit) COMMIT=0 ;;
    -h|--help) usage ;;
    -*) echo "ready.sh: unknown option $1" >&2; usage ;;
    *) [ -z "$ROOT" ] && ROOT="$1" || usage ;;
  esac
  shift
done
[ -n "$ROOT" ] && [ -d "$ROOT" ] || usage
[ -n "$MOD" ] && [ -n "$APP" ] && { echo "ready.sh: --module and --app are exclusive" >&2; usage; }
ROOT="$(cd "$ROOT" && pwd)"
REG="$ROOT/PROJECT.md"
if [ -n "$MOD" ]; then SCOPE="module $MOD"; elif [ -n "$APP" ]; then SCOPE="app $APP"; else SCOPE="app"; fi
SLUG="$(printf '%s' "${MOD:-${APP:-app}}" | tr -c 'A-Za-z0-9_-' '-' | sed 's/-*$//')"
DATE="$(date -u +%Y-%m-%d)"; ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVID_REL="docs/progress/ready-$DATE-$SLUG.md"; LOG_REL="docs/progress/ready.log"
LEDGER="$TOOLKIT_ROOT/project-bin/look-ledger.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ready.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

N_ROWS=0; N_OK=0
: > "$TMP/rows.md"
# row <ok|fail|info> <name> <detail> — prints and records one check row
row() {
  local mark
  case "$1" in ok) mark="PASS"; N_OK=$((N_OK+1)); N_ROWS=$((N_ROWS+1)) ;;
               fail) mark="FAIL"; N_ROWS=$((N_ROWS+1)) ;;
               *) mark="n/a" ;; esac
  printf '  %-4s  %-9s %s\n' "$mark" "$2" "$3"
  printf '| %s | %s | %s |\n' "$2" "$mark" "$(printf '%s' "$3" | sed 's/|/\\|/g')" >> "$TMP/rows.md"
}

_epoch() {  # ISO-8601 UTC -> epoch, GNU then BSD; 0 when unparseable
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0
}

echo "ready.sh — $SCOPE in $ROOT ($ISO)"

# --- multi-app: a per-app scope needs the multi-app resolver; never guess it -------------------
if [ -n "$APP" ] && ls "$ROOT"/apps/*/*.mpr >/dev/null 2>&1; then
  row fail scope "NOT MEASURED — $ROOT holds several apps (apps/*/); per-app scoping of the look ledger is not resolved yet, so no check here can be read for app $APP alone"
fi

# --- gate 5 ---------------------------------------------------------------------------------
GC="$TOOLKIT_ROOT/bin/gate-check.sh"
g5="$(MXTK_LOOK_MODULE="$MOD" bash "$GC" --no-html "$ROOT" 5 2>&1)"; rc5=$?
l5="$(printf '%s\n' "$g5" | grep -m1 '^Stage 5 (' | sed 's/^Stage 5 ([^)]*): //')"
v5="$(printf '%s' "$l5" | awk '{print $1}')"
look5="$(printf '%s' "$l5" | grep -o 'look: .*' | head -1)"
case "$rc5" in
  0) row ok gate5 "Stage 5 $v5" ;;
  2) if printf '%s' "$look5" | grep -q 'accounted for'; then row ok gate5 "Stage 5 MANUAL with the look accounted for (its sign-off is a Decisions row)"
     else row fail gate5 "Stage 5 MANUAL with nothing measured — no page recorded as built"; fi ;;
  *) row fail gate5 "Stage 5 ${v5:-exit $rc5}: $(printf '%s' "$l5" | sed 's/^[A-Z]* · //; s/^Surface MISSING: [^—]*— //' | cut -c1-200)" ;;
esac

# --- gate 6, where the register's position calls for it --------------------------------------
pos=""
[ -f "$REG" ] && pos="$(awk '/^## Current stage/{f=1;next} f && /^\*\*/{print;exit}' "$REG")"
case "$pos" in
  *"Stage 6"*|*"Stage 7"*|*"All gates passed"*)
    bash "$GC" --no-html "$ROOT" 6 > "$TMP/g6" 2>&1; rc6=$?
    l6="$(grep -m1 '^Stage 6 (' "$TMP/g6" | sed 's/^Stage 6 ([^)]*): //')"
    if [ "$rc6" = 0 ]; then row ok gate6 "Stage 6 $(printf '%s' "$l6" | awk '{print $1}') (register position: Stage 6 or later)"
    else row fail gate6 "Stage 6 $(printf '%s' "$l6" | cut -c1-200)"; fi ;;
  *) row info gate6 "not owed — the register's position is before Stage 6" ;;
esac

# --- look: K of N, from gate-check's own join -------------------------------------------------
waived_look() {
  [ -f "$REG" ] || return 1
  grep -qiE "^[-*[:space:]]*Waived obligation look(/${MOD:-__none__})?[[:space:]]*:" "$REG"
}
if printf '%s' "$look5" | grep -q 'never looked at'; then
  un="$(printf '%s' "$look5" | sed -n 's/^look: \([0-9]*\) of \([0-9]*\) .*/\1/p')"
  tot="$(printf '%s' "$look5" | sed -n 's/^look: \([0-9]*\) of \([0-9]*\) .*/\2/p')"
  row fail look "$((tot-un)) of $tot page(s) looked at since their last build — unseen: $(printf '%s' "$look5" | sed 's/^.*since their last build\( ([^)]*)\)\{0,1\}: //; s/ — screenshot.*//')"
elif printf '%s' "$look5" | grep -q 'accounted for'; then
  tot="$(printf '%s' "$look5" | sed -n 's/^look: \([0-9]*\) of .*/\1/p')"
  row ok look "$tot of $tot page(s) accounted for ($(printf '%s' "$look5" | sed -n 's/.*accounted for (\([^)]*\)).*/\1/p'))"
elif waived_look; then
  row ok look "WAIVED — Waived obligation look${MOD:+/$MOD} in PROJECT.md"
else
  row fail look "NOT MEASURED — no page${MOD:+ of $MOD} recorded as built (.claude/loop/look/owed.tsv, or the committed docs/progress/look-summary.tsv): the denominator is unknown. Build pages through exec.sh, or --waive look${MOD:+/$MOD} --reason \"...\" for a module with no pages"
fi

# per-page facts for the evidence file and the review join: state, page, built-epoch, shot
if [ -s "$ROOT/.claude/loop/look/owed.tsv" ]; then
  PROJECT_ROOT="$ROOT" bash "$LEDGER" summary --write >/dev/null 2>&1
  PROJECT_ROOT="$ROOT" bash "$LEDGER" status > "$TMP/st" 2>/dev/null
  PROJECT_ROOT="$ROOT" bash "$LEDGER" status --shots > "$TMP/shots" 2>/dev/null
else
  : > "$TMP/st"; : > "$TMP/shots"
fi
if [ -n "$MOD" ]; then
  for f in st shots; do awk -F'\t' -v m="$MOD" 'index($2, m ".") == 1' "$TMP/$f" > "$TMP/$f.x"; mv "$TMP/$f.x" "$TMP/$f"; done
fi

# --- must-have list (when the project has one) -----------------------------------------------
MH=""
for f in ${MXTK_MUST_HAVES:-} ${MOD:+"$ROOT/architecture/modules/$MOD/must-haves.md"} "$ROOT/docs/must-haves.md"; do
  [ -f "$f" ] && { MH="$f"; break; }
done
if [ -n "$MH" ]; then
  # a module's own file counts whole; the shared file counts the lines naming the module (or all)
  mh="$(awk -v m="$MOD" -v own="$( [ -n "$MOD" ] && [ "$MH" = "$ROOT/architecture/modules/$MOD/must-haves.md" ] && echo 1 || echo 0)" '
    /^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/ {
      if (m != "" && own != 1 && index($0, m) == 0) next
      n++; if ($0 ~ /\[[xX]\]/) k++
    } END { print k+0 " " n+0 }' "$MH")"
  k="${mh% *}"; n="${mh#* }"
  if [ "$n" -eq 0 ]; then row fail must-have "0 of 0 — ${MH#"$ROOT"/} lists no checkbox item${MOD:+ for $MOD}: an empty list proves nothing"
  elif [ "$k" -lt "$n" ]; then row fail must-have "$k of $n ticked in ${MH#"$ROOT"/}"
  else row ok must-have "$n of $n ticked in ${MH#"$ROOT"/}"; fi
else
  row info must-have "not present — no must-have list at ${MOD:+architecture/modules/$MOD/must-haves.md or }docs/must-haves.md"
fi

# --- independent review, unattended mode only -------------------------------------------------
MODE="$(bash "$TOOLKIT_ROOT/bin/interview-mode.sh" "$ROOT" 2>/dev/null)"
RV_DIR="$ROOT/docs/progress/look-reviews"
: > "$TMP/scores"
if [ "$MODE" = auto ]; then
  for f in "$RV_DIR"/*.md; do
    [ -f "$f" ] || continue
    rvr="$(sed -n 's/^Reviewer:[[:space:]]*//p' "$f" | head -1 | tr -d '\r')"
    bld="$(sed -n 's/^Builder:[[:space:]]*//p' "$f" | head -1 | tr -d '\r')"
    at="$(sed -n 's/^Reviewed:[[:space:]]*//p' "$f" | head -1 | tr -d '\r' | awk '{print $1}')"
    # a self-review is no review: both names present and different, or the file is not read
    if [ -z "$rvr" ] || [ -z "$bld" ] || [ "$rvr" = "$bld" ]; then
      echo "  note  review file ${f#"$ROOT"/} ignored: needs distinct Reviewer: and Builder: lines" >&2; continue
    fi
    ep="$(_epoch "$at")"
    # table rows: | Module.Page | screenshot | target | score | note |  — Score column found by header
    tr -d '\r' < "$f" | awk -F'|' -v ep="$ep" -v fn="${f#"$ROOT"/}" '
      sc == 0 && /^\|/ { for (i=2; i<NF; i++) { h=tolower($i); gsub(/[[:space:]]/, "", h); if (h == "score") sc=i }; next }
      sc > 0 && /^\|/ { p=$2; gsub(/[[:space:]`]/, "", p); s=$sc; gsub(/[^0-9]/, "", s)
                        if (p ~ /^[A-Za-z0-9_]+\.[A-Za-z0-9_]+$/ && s != "") print p "\t" s "\t" ep "\t" fn }' >> "$TMP/scores"
  done
  if [ ! -s "$TMP/st" ]; then
    row fail review "NOT MEASURED — no owed page to review${MOD:+ in $MOD}; the reviewer's denominator is the look ledger's pages"
  else
    # each owed page: the newest score given after its last build
    # scores read in BEGIN, not as a first file: with an empty first file NR==FNR holds for the
    # second one too, and the page list would be read as scores (0 of 0, "pass")
    awk -F'\t' -v scf="$TMP/scores" '
      BEGIN { while ((getline line < scf) > 0) { split(line, f, "\t")
                if (!(f[1] in at) || f[3]+0 > at[f[1]]) { at[f[1]]=f[3]+0; sc[f[1]]=f[2]+0 } } }
      { p=$2; built=$3+0; n++
        if (!(p in at) || at[p] < built) { miss++; ml=ml (ml ? ", " : "") p; next }
        if (sc[p] < 4) { low++; ll=ll (ll ? ", " : "") p "=" sc[p]; next }
        k++ }
      END { printf "%d|%d|%d|%d|%s|%s\n", k, n, miss, low, ml, ll }' "$TMP/st" > "$TMP/rv"
    IFS='|' read -r k n miss low ml ll < "$TMP/rv"   # not a tab: IFS whitespace collapses empty fields
    if [ "$k" = "$n" ]; then row ok review "$n of $n page(s) scored 4+ by an independent reviewer (docs/progress/look-reviews/)"
    else row fail review "$k of $n page(s) scored 4+ by an independent reviewer${ml:+ — unscored since last build: $ml}${ll:+ — below 4: $ll}. Dispatch a fresh reviewer (skills/module-review.md \"Independent look\")"; fi
  fi
else
  row info review "not owed — Interview mode is ${MODE:-steering}, not auto (a human sees the screens)"
fi

# --- verdict, evidence, READY line -------------------------------------------------------------
if [ "$N_OK" -eq "$N_ROWS" ] && [ "$N_ROWS" -gt 0 ]; then VERDICT=READY; else VERDICT=NOT-READY; fi
echo "$VERDICT — $N_OK of $N_ROWS checks pass ($SCOPE)"

mkdir -p "$ROOT/docs/progress"
{
  echo "# ${VERDICT/-/ }: $SCOPE"
  echo
  echo "$VERDICT: $SCOPE — $ISO — $N_OK of $N_ROWS checks — written by bin/ready.sh, never by hand"
  echo
  echo "| Check | Verdict | Detail |"
  echo "|---|---|---|"
  cat "$TMP/rows.md"
  echo
  echo "## Pages owed a LOOK vs seen (look ledger)"
  echo
  if [ -s "$TMP/st" ]; then
    echo "| Module | Owed | Seen |"
    echo "|---|---|---|"
    awk -F'\t' '{ m=$2; sub(/\..*/, "", m); if (!(m in o)) ord[++k]=m; o[m]++; if ($1=="SEEN") s[m]++ }
      END { for (i=1; i<=k; i++) printf "| %s | %d | %d |\n", ord[i], o[ord[i]], s[ord[i]]+0 }' "$TMP/st"
    echo
    un="$(awk -F'\t' '$1=="OWED" { print $2 }' "$TMP/st")"
    if [ -n "$un" ]; then
      echo "Unseen since their last build ($(printf '%s\n' "$un" | wc -l | tr -d ' ')):"
      printf '%s\n' "$un" | head -40 | sed 's/^/- /'
      echo
    fi
    sh="$(awk -F'\t' '$1=="SEEN" && $3 != "" { b=$3; sub(/.*[\/\\]/, "", b); print "- " $2 ": " b }' "$TMP/shots")"
    if [ -n "$sh" ]; then echo "Screenshots relied on:"; printf '%s\n' "$sh"; echo; fi
  else
    echo "No look ledger in this checkout (.claude/loop/look/ is git-ignored); see docs/progress/look-summary.tsv if committed."
    echo
  fi
  if [ -n "$MH" ]; then echo "Must-have list: ${MH#"$ROOT"/}"; echo; fi
  if [ -s "$TMP/scores" ]; then
    echo "Review files read: $(cut -f4 "$TMP/scores" | sort -u | tr '\n' ' ')"
    echo
  fi
} > "$ROOT/$EVID_REL"
printf '%s\t%s\t%s\t%s\t%s of %s\n' "$ISO" "$VERDICT" "$SCOPE" "$EVID_REL" "$N_OK" "$N_ROWS" >> "$ROOT/$LOG_REL"
echo "evidence: $EVID_REL · log: $LOG_REL"

# --- commit the evidence (explicit paths only) --------------------------------------------------
if [ "$COMMIT" = 1 ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  paths="$EVID_REL $LOG_REL"
  [ -f "$ROOT/docs/progress/look-summary.tsv" ] && paths="$paths docs/progress/look-summary.tsv"
  # shellcheck disable=SC2086
  if ( cd "$ROOT" && git add -- $paths && git commit -q -m "ready: $SCOPE $VERDICT ($N_OK of $N_ROWS checks)" -- $paths ) >/dev/null 2>&1; then
    echo "committed: $(git -C "$ROOT" log -1 --format='%h %s')"
  else
    echo "  note  the evidence was written but not committed (git refused) — commit these paths: $paths" >&2
  fi
fi

[ "$VERDICT" = READY ]
