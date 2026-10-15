#!/usr/bin/env bash
# exec.sh — the guard chain around a model write.
#
#   STOP-row scan → concurrent-writer guard → module-brief advisory → mxcli check → snapshot → baseline → exec
#   → mxbuild delta gate → auto-restore only on a NEW error → lint ratchet → SP reopen
#
# The mxbuild gate is a DELTA gate, not an absolute "0 errors" one: a write is kept
# when the post-exec error set is the pre-flight baseline exactly, or a strict
# SUBSET of it (every post-exec error already existed before this script ran —
# nothing new, even if some were cleared). Only a set containing something new
# triggers the snapshot restore. See "Delta gate" below. An error is identified by
# code + message + where (module / document / element), counted, not deduplicated.
#
# Usage: ./bin/exec.sh [--commit-first] <script.mdl>
#        ./bin/exec.sh [--commit-first] --patch <script> [args...]
#        ./bin/exec.sh --change-class <script.mdl>   (advisory ui-only/logic tag; writes nothing)
#        ./bin/exec.sh --watch-compat <script.mdl>   (advisory: can `run --local --watch` apply
#                                                     this, or does the app need a restart; writes nothing)
#        ./bin/exec.sh --cr CR-07 <script.mdl>        (any mode: tag the run with its change request)
#        Leading flags (--cr, --commit-first, then --patch) may come in any order.
#
# --cr (2026-10-13): names the PROJECT.md "## Change log" row this run applies
# (skills/change-intake.md). It lands in the BUILD-LOG detail cell as "cr: CR-07", the same way
# the change-class tag does; the metrics-ledger columns are unchanged. Optional — a planned build
# step has no CR. Its value: a BUILD-LOG row with a cr tag is the Closed-by evidence the change
# log asks for, and an exec with neither a plan step nor a cr is the MDL-first change signature.
#
# --patch (2026-09-27): the same chain around a one-off script that edits the model directly
# (a Python BSON patch for something mxcli cannot express, e.g. an association owner change).
# Run bare, such a script got no snapshot, no gate, no restore and no BUILD-LOG row. In auto
# permission mode, Claude Code's classifier also refused it as "Irreversible Local Destruction".
# This mode runs it as `<interpreter> <script> <model.mpr> [args...]`. The interpreter comes from
# the extension: .py runs under Python 3, .sh under bash, anything else must be executable.
# MXTK_MPR and MXTK_MODEL_DIR are exported too. What differs from an MDL run: there is no
# `mxcli check` and no module-brief advisory, since neither can read the script. A patch is
# also opaque, so it is kept ONLY on a verified gate. A non-zero exit is restored at once,
# without spending an mxbuild on it. A gate that fails, cannot run, or reports `unverified` is
# restored too, and ALLOW_UNVERIFIED does not apply. A dirty model with the same errors as
# before is kept, same as for MDL (the delta gate).
# What it does NOT guard: anything the script touches besides the model. `./bin/exec.sh` is on
# the project's allow-list (install-claude-permissions.sh), so in auto mode Claude Code's
# classifier does not review the script. Read what a patch does outside the .mpr before running it.
#
# Refuses to run while the model has UNCOMMITTED changes (by design: the snapshot
# taken below would not cover them, so a later auto-restore could silently lose
# that work) — commit the model first, or FORCE_EXEC=1 to override at that risk.
# --commit-first (or MXTK_COMMIT_FIRST=1) does that commit for you, opt-in only: it prints
# the model paths it will commit, stages and commits ONLY the .mpr and mprcontents/
# (`git commit -- <paths>`, so anything else already staged stays staged and uncommitted),
# then goes on. It refuses while Studio Pro holds the model, even under FORCE_EXEC, because
# SP's in-memory model is not what is on disk. The project's pre-commit model-stamp hook
# still applies; if it refuses, nothing is executed and its remedy is printed.
# WHY: in a 20-task UX-fix field run (2026-10-12) 26 of 148 exec.sh runs applied nothing
# because of this refusal, and each one cost a turn to commit and re-run (#287 item 4).
#
# One exec.sh at a time PER PROJECT: .mpr-snapshots/.exec.lock holds "<pid> <epoch> <script>".
# A lock whose pid is dead (a crash, a SIGKILL, a closed terminal) is stale and is taken over
# with a printed note — never a manual rm. A running `mxcli exec` belonging to some other
# project on the same machine is NOT a conflict and no longer blocks (#287 item 3: a test run
# on a scratch copy of a different project blocked an unrelated exec).
# bin/test-scratch.sh takes the same lock while it copies the model for `mxcli test` (#278).
#
# Overrides: FORCE_EXEC=1 (skip refusals), SKIP_CHECK=1 (skip the pre-exec
#            mxcli check), SKIP_BASELINE=1 (skip pre-flight mxbuild),
#            MXBUILD_PATH=..., MENDIX_APP=..., MPR_FILE=...,
#            MXTK_GATE_TIMEOUT=<seconds> (default 0 = UNBOUNDED — each mxbuild
#            run via _common.sh's mxtk_mxbuild_error_count waits for a real
#            build to finish, however long that takes; set this to bound it.
#            bin/doctor.sh's own gate self-test is the one caller that DOES
#            default to a bound, 300s via DOCTOR_GATE_TIMEOUT, because that
#            run is a throwaway scratch copy, not a real build worth waiting on)
#            ALLOW_UNVERIFIED=1 (write even though the mxbuild gate cannot run —
#            the write is then refused by default, see "Gate must be able to run"),
#            MXTK_NO_INSTALL=1 (never download mxbuild; offline CI)
#            MXTK_SCAN_OVERRIDE="<reason>" (the user only: run despite a blocking STOP-row scan hit, #349)
set -e
_T0=$(date +%s)

# ── Change class (advisory, added 2026-10-13) ────────────────────────────────
# Tags each run `ui-only` or `logic`, so the run summary can say which TEST LANE applies
# (skills/testing-shape.md §3 "After the base set"). ui-only = every top-level statement is a
# page/snippet/layout write (CREATE|ALTER|DROP|MOVE PAGE|SNIPPET|LAYOUT, ALTER STYLING, UPDATE
# WIDGETS); read-only statements (SHOW, DESCRIBE, ...) are neutral. Anything else — a microflow,
# an entity, an enum, an association, a GRANT, navigation, settings, an unknown verb — is
# `logic`, and so is a script with no page statement at all: when unsure, the heavier lane.
# A GRANT on a page is security, so a page script that also grants is `logic`.
#
# WHY. A 20-task UX-fix retro (toolkit issue #274) re-proved UI-only changes 5-10x each — the
# implementer's journey plus 4-5 regression journeys of other modules, reviewer re-runs, a full
# `mxcli test` (~6 min) at every batch close — and 143 min of microflow tests found stale
# strings and credential problems, not logic bugs. The tag puts the lane in front of whoever
# reads the run, instead of leaving "how much to re-test" to habit.
#
# ADVISORY ONLY: it never blocks, never changes a gate, and is not a test. It is a grep over
# statement heads, not a parser: comments ("--", "//", "/* */") and quoted strings are blanked
# first, then only lines at bracket depth 0 are read, so widget lines inside { } and property
# lines inside ( ) never count as statements. Continuation lines whose first word is not a verb
# are ignored. Golden input: real MDL — skills/agents-examples/*.mdl,
# examples/stylegallery/mdlsource/gallery/*.mdl, tests/wave2/fixtures/page-fidelity-mocks/*.mdl
# (tests/wave2/test-exec-change-class.sh). Plain awk: bash 3.2 / BSD awk / Git Bash.
#
#   ./bin/exec.sh --change-class <script.mdl>   prints `ui-only` or `logic`, then a tab and the
#                                               deciding statement head (line N: ...); exit 0.
#                                               Touches nothing, needs no .mpr.
# The lexer both advisory classifiers share (change class above, watch-compat below): blanks
# comments ("--", "//", "/* */"), $$-bodies and '...' literals, strips identifier quotes, and
# tracks ( { ) } depth. lex_line(line) sets `clean` (the line with all that removed) and
# `start_depth` (the bracket depth the line STARTS at — 0 means it can be a statement head).
# Assigned single-quoted, invoked double-quoted: awk's $0 must survive the shell.
_MXTK_MDL_LEX='
    function lex_line(line,    n, i, c, c2, tmp, o, cl) {
      clean = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); c2 = substr(line, i, 2)
        if (inblock)   { if (c2 == "*/") { inblock = 0; i += 2 } else i++; continue }
        if (indollar)  { if (c2 == "$$") { indollar = 0; i += 2 } else i++; continue }
        if (c2 == "/*") { inblock = 1; i += 2; continue }
        if (c2 == "$$") { indollar = 1; i += 2; continue }
        if (c2 == "--" || c2 == "//") break
        if (c == "\047") {                        # a string literal: blanked, so a caption that
          i++                                      # says "create microflow" is not a statement
          while (i <= n && substr(line, i, 1) != "\047") i++
          i++; clean = clean "\047\047"; continue
        }
        if (c == "\"") { i++; continue }           # a quoted identifier: keep the name, drop quotes
        clean = clean c; i++
      }
      start_depth = depth
      tmp = clean; o = gsub(/[({]/, "", tmp); tmp = clean; cl = gsub(/[)}]/, "", tmp)
      depth += o - cl; if (depth < 0) depth = 0
    }'
mxtk_change_class() {  # $1 = MDL script; prints "<class>\t<why>"
  awk "$_MXTK_MDL_LEX"'
    function head_class(w1, w2, w4,    obj) {
      if (w1 ~ /^(SHOW|DESCRIBE|CONNECT|DISCONNECT|REFRESH|SEARCH|HELP|SELECT|LIST|USE|EXIT|QUIT)$/) return "neutral"
      if (w1 == "UPDATE" && w2 == "WIDGETS") return "ui"
      if (w1 == "ALTER" && w2 == "STYLING") return "ui"
      if (w1 ~ /^(CREATE|ALTER|DROP|MOVE)$/) {
        obj = w2
        if (w1 == "CREATE" && w2 == "OR") obj = w4
        if (obj ~ /^(PAGE|SNIPPET|LAYOUT)$/) return "ui"
        return "logic"
      }
      if (w1 ~ /^(GRANT|REVOKE|UPDATE|INSERT|DELETE|SQL|IMPORT|EXPORT|EXECUTE|RENAME|SET|CALL|COMMIT|CHANGE|RETRIEVE|DECLARE)$/) return "logic"
      return "skip"   # a continuation line (to Role;  returns Boolean ...) — not a statement head
    }
    BEGIN { depth = 0; inblock = 0; indollar = 0; ui = 0; logic = ""; }
    {
      lex_line($0)
      t = clean; gsub(/^[ \t]+/, "", t)
      if (start_depth == 0 && t ~ /^[A-Za-z]/) {
        split(toupper(t), w, /[ \t(;{]+/)
        k = head_class(w[1], w[2], w[4])
        if (k == "ui") ui++
        else if (k == "logic" && logic == "") {
          h = t; if (length(h) > 60) h = substr(h, 1, 60) "..."
          logic = "line " NR ": " h
        }
      }
    }
    END {
      if (logic != "")  { printf "logic\t%s\n", logic; exit }
      if (ui == 0)      { printf "logic\tno page/snippet/layout statement found\n"; exit }
      printf "ui-only\t%d page/snippet/layout statement(s), nothing else\n", ui
    }' "$1"
}
# Leading flags, parsed in ONE loop before anything needs a project, in any order:
# --cr CR-NN, --commit-first, then optionally --patch (whose next word is the script) or one of
# the advisory modes. A malformed --cr id, an unknown --flag, or a script name starting with
# `--` is refused here, before the lock, the commit or the snapshot. WHY (review of #306): --cr
# was only honoured as the FIRST argument, though the usage line documents
# `[--commit-first] [--cr CR-NN]`; in that order commit-first committed the model and the run
# went on with "--cr" as its script path.
CR_ID=""; COMMIT_FIRST="${MXTK_COMMIT_FIRST:-0}"; PATCH_MODE=0; ADVISORY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cr)
      CR_ID="${2:-}"
      case "$CR_ID" in
        CR-[0-9]*) case "${CR_ID#CR-}" in *[!0-9]*) CR_ID="!" ;; esac ;;
        *) CR_ID="!" ;;
      esac
      if [ "$CR_ID" = "!" ]; then
        echo "✗ --cr takes a change-log id like CR-07 (PROJECT.md '## Change log', skills/change-intake.md); got '${2:-}'" >&2
        exit 2
      fi
      shift 2 ;;
    --commit-first) COMMIT_FIRST=1; shift ;;
    --patch) PATCH_MODE=1; shift; break ;;
    --change-class|--watch-compat) ADVISORY="$1"; shift; break ;;
    *) break ;;
  esac
done
case "${1:-}" in
  --*)
    echo "✗ Unknown option or misplaced flag '$1' — nothing was committed, snapshotted or executed." >&2
    echo "  Usage: ./bin/exec.sh [--commit-first] [--cr CR-NN] <script.mdl>" >&2
    echo "         ./bin/exec.sh [--commit-first] [--cr CR-NN] --patch <script> [args...]" >&2
    exit 2 ;;
esac
if [ "$ADVISORY" = "--change-class" ]; then
  [ -f "${1:-}" ] || { echo "Usage: ./bin/exec.sh --change-class <script.mdl>" >&2; exit 2; }
  mxtk_change_class "$1"
  exit 0
fi

# ── Watch compatibility (advisory, added 2026-10-13) ─────────────────────────
# After a write, can a running `mxcli run --local --watch` apply it, or will the app keep
# serving the OLD model until someone restarts it? skills/ui-loop.md § "What watch picks up"
# holds the covers / does-not-cover table and the stale-runtime symptom list; this is the
# mechanical half of it, so it names the same change classes and nothing else.
#
# WHY. In a 20-task UX-fix run over three apps (2026-10-12; #284, #275, #289) watch silently
# missed recreated microflows, new grants, new attributes, new pages and page URLs, and theme
# SCSS/JS edits: ~26 restarts, and stale code that read as product defects (a security error
# on a page, NoClassDefFoundError on a widget class, deep links landing on Home) cost a
# diagnosis round each before anyone suspected the runtime.
#
# Restart class (statement heads read with the change-class lexer above, so comments, strings
# and widget/property lines never count):
#   CREATE [OR MODIFY|REPLACE] MICROFLOW, DROP MICROFLOW     → microflow created/recreated/dropped
#   CREATE ... ENTITY                                        → entity (new attributes)
#   ALTER ENTITY ... ADD ...                                 → attribute added
#   GRANT / REVOKE                                           → access rule changed
#   CREATE ... MODULE ROLE | USER ROLE, ALTER USER ROLE      → role added/changed
#   CREATE PAGE (no OR — a new page)                         → new page
#   a Url property on a page (create header, `set Url = ...`) → page URL (route table)
# Watch-safe (the ONLY statements reported `watch can apply this`, ui-loop.md's left column):
#   ALTER PAGE / ALTER SNIPPET, CREATE [OR ...] SNIPPET, CREATE OR REPLACE|MODIFY PAGE (no Url).
# Read-only heads (SHOW, DESCRIBE, ...) are neutral. Any other statement — CREATE ASSOCIATION,
# CREATE ENUMERATION, ALTER ENTITY ... MODIFY, a Java action, a constant, navigation, DROP PAGE,
# UPDATE WIDGETS — is on neither column and prints `unknown — restart if behaviour looks stale`
# (independent review of #304: these all used to say "watch can apply this", a claim nobody had
# checked).
# `CREATE OR REPLACE|MODIFY PAGE` without a Url is reported as reloadable, with a note that
# it needs a restart IF the page is new — a script cannot tell new from replaced. Theme
# SCSS/JS is not in the script; exec.sh checks those files against the running app's boot
# (see watch_theme_changes below).
#
# ADVISORY ONLY: never blocks, never changes a gate or a verdict. Golden input: real MDL
# (tests/wave2/test-exec-lock-watch.sh).
#
#   ./bin/exec.sh --watch-compat <script.mdl>   prints `restart needed: <reasons>`,
#                                               `unknown — restart if behaviour looks stale: <heads>`
#                                               or `watch can apply this`, exit 0. Touches nothing.
mxtk_watch_compat() {  # $1 = MDL script; prints "restart\t<reasons>" | "unknown\t<heads>" | "watch\t<note>"
  awk "$_MXTK_MDL_LEX"'
    function add(label, nr) {
      if (!(label in cnt)) { order[++nlab] = label; first[label] = nr }
      cnt[label]++
    }
    BEGIN { depth = 0; inblock = 0; indollar = 0; cur_page = 0; nlab = 0; maybe = ""; unk = ""; nunk = 0 }
    {
      lex_line($0)
      t = clean; gsub(/^[ \t]+/, "", t)
      if (start_depth == 0 && t ~ /^[A-Za-z]/) {
        n = split(toupper(t), w, /[ \t(;{]+/)
        v = w[1]
        if (v ~ /^(CREATE|ALTER|DROP|MOVE|GRANT|REVOKE|UPDATE|INSERT|DELETE|SQL|IMPORT|EXPORT|EXECUTE|RENAME|SET|CALL|COMMIT|CHANGE|RETRIEVE|DECLARE)$/) {
          j = 2; if (v == "CREATE" && w[2] == "OR") j = 4
          o1 = w[j]; o2 = w[j+1]; o3 = w[j+2]
          cur_page = ((v == "CREATE" || v == "ALTER") && o1 == "PAGE")
          attr = 0
          if (v == "ALTER" && o1 == "ENTITY") for (k = 3; k <= n; k++) if (w[k] == "ADD") { attr = 1; break }
          if ((v == "CREATE" || v == "DROP") && o1 == "MICROFLOW")
            add(v == "DROP" ? "microflow dropped" : "microflow created or recreated", NR)
          else if (v == "CREATE" && (o1 == "ENTITY" || o2 == "ENTITY"))
            add("entity created or changed (new attributes)", NR)
          else if (attr)
            add("attribute added", NR)
          else if (v == "GRANT" || v == "REVOKE")
            add("access rule changed (" v ")", NR)
          else if ((v == "CREATE" && ((o1 == "MODULE" && o2 == "ROLE") || (o1 == "USER" && o2 == "ROLE"))) \
                   || (v == "ALTER" && o1 == "USER" && o2 == "ROLE"))
            add("module/user role added or changed", NR)
          else if (v == "CREATE" && o1 == "PAGE" && j == 2)
            add("new page", NR)
          else if (v == "CREATE" && o1 == "PAGE") {
            if (maybe == "") maybe = "line " NR ": " substr(t, 1, 60)
          }
          # The watch-safe list (skills/ui-loop.md "What watch picks up", left column): an
          # ALTER PAGE / ALTER SNIPPET edit, a new or changed snippet. Everything else that is
          # not on either column is UNKNOWN, never "watch can apply this".
          else if ((v == "ALTER" && (o1 == "PAGE" || o1 == "SNIPPET")) || (v == "CREATE" && o1 == "SNIPPET"))
            ;
          # Neutral: microflow-body activities (their CREATE MICROFLOW head already decides),
          # a folder, a move into a folder.
          else if (v ~ /^(DECLARE|CHANGE|RETRIEVE|COMMIT|CALL)$/ || (v == "CREATE" && o1 == "FOLDER") \
                   || (v == "MOVE" && toupper(t) ~ /[ \t]TO[ \t]+FOLDER([ \t]|$)/))
            ;
          else if (nunk < 3) {
            h = t; if (length(h) > 50) h = substr(h, 1, 50) "..."
            unk = unk (nunk++ ? "; " : "") "line " NR ": " h
          } else nunk++
        }
      }
      # A Url property on a page: the create header `(..., Url: ...)` or `set Url = ...` in an
      # ALTER PAGE body. The identifier must stand alone, so ImageUrl never matches.
      if (cur_page && clean ~ /(^|[^A-Za-z0-9_])Url[ \t]*[:=]/) add("page URL added or changed (route table)", NR)
    }
    END {
      if (nlab > 0) {
        s = ""
        for (i = 1; i <= nlab; i++) {
          l = order[i]; s = s (i > 1 ? "; " : "") l (cnt[l] > 1 ? " x" cnt[l] : "") " (line " first[l] ")"
        }
        printf "restart\t%s\n", s; exit
      }
      if (nunk > 0) { printf "unknown\t%s%s\n", unk, (nunk > 3 ? " (+" (nunk - 3) " more)" : ""); exit }
      if (maybe != "") { printf "watch\tunless the page is new: create or replace/modify page, %s\n", maybe; exit }
      printf "watch\t\n"
    }' "$1"
}
if [ "$ADVISORY" = "--watch-compat" ]; then
  [ -f "${1:-}" ] || { echo "Usage: ./bin/exec.sh --watch-compat <script.mdl>" >&2; exit 2; }
  _wc="$(mxtk_watch_compat "$1")"
  case "${_wc%%	*}" in
    restart) echo "restart needed: ${_wc#*	}" ;;
    unknown) echo "unknown — restart if behaviour looks stale: ${_wc#*	}" ;;
    *) _n="${_wc#*	}"
       if [ -n "$_n" ]; then echo "watch can apply this — $_n"; else echo "watch can apply this"; fi ;;
  esac
  exit 0
fi

. "$(dirname "$0")/_common.sh"

MPR="$(find_mpr)" || exit 1
MPR_BASE="$(basename "$MPR")"
NAME="$(basename "$MPR" .mpr)"
SCRIPT="${1:-}"
[ $# -gt 0 ] && shift
# Remaining args go to the patch script, after the model path. An MDL run takes none.
LOG_NAME="$(basename "$SCRIPT")"
[ "$PATCH_MODE" = "1" ] && LOG_NAME="patch: $LOG_NAME"

if [ -z "$SCRIPT" ]; then
  echo "Usage: ./bin/exec.sh [--commit-first] [--cr CR-NN] <script.mdl>"
  echo "       ./bin/exec.sh [--commit-first] [--cr CR-NN] --patch <script> [args...]"
  exit 1
fi
if [ "$PATCH_MODE" = "1" ]; then
  # Resolve the path BEFORE the cd below, so a path relative to the caller's cwd keeps working.
  [ -f "$SCRIPT" ] || { echo "✗ --patch: no such file: $SCRIPT"; exit 1; }
  SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
  case "$SCRIPT" in
    *.py|*.sh) ;;
    *) [ -x "$SCRIPT" ] || { echo "✗ --patch: $SCRIPT is not .py, not .sh and not executable — cannot tell how to run it."; exit 1; } ;;
  esac
fi

# Change class of THIS run (mxtk_change_class, top of file). Computed before the cd, while a
# script path relative to the caller still resolves. Advisory: an unreadable script just gets
# no tag, and the guard chain below reports the real problem.
CHANGE_CLASS=""; CHANGE_WHY=""
if [ "$PATCH_MODE" = "1" ]; then
  CHANGE_CLASS="logic"; CHANGE_WHY="--patch script (opaque to the classifier)"
elif [ -r "$SCRIPT" ]; then
  _cc="$(mxtk_change_class "$SCRIPT" 2>/dev/null || true)"
  CHANGE_CLASS="${_cc%%	*}"; CHANGE_WHY="${_cc#*	}"
fi
change_lane() {
  case "$CHANGE_CLASS" in
    ui-only) echo "re-run the journeys of every page the change reaches (embedders of a changed snippet/layout) once + a LOOK. No .test.mdl; reviewers read the artifacts, they do not re-run" ;;
    logic)   echo "re-run only the tests whose subject this change touched (changed microflows + their SHOW CALLERS, changed pages' journeys). Full mxcli test at module close, not here" ;;
  esac
}
[ -n "$CR_ID" ] && echo "→ Change request: $CR_ID (PROJECT.md '## Change log'; cite this run's commit in its Closed-by)"
if [ -n "$CHANGE_CLASS" ]; then
  echo "→ Change class: $CHANGE_CLASS ($CHANGE_WHY)"
  echo "  test lane (skills/testing-shape.md §3): $(change_lane)"
fi

cd "$PROJECT_ROOT"

# ── Build log (auto) ─────────────────────────────────────────────────────────
# One line per exec, written by the script rather than by hand, so it stays true
# when someone forgets. Added after cross-workstream collisions where a session
# left the model non-building and it was only found by running something else.
BUILD_LOG="$PROJECT_ROOT/docs/BUILD-LOG.md"

# Declared HERE, above log_build, not next to the gate: a row must be able to
# carry a gate verdict even when the gate block below is never reached.
GATE_STATE="not-run"   # not-run | skipped | unverified | pass | fail
GATE_ERRORS="?"        # mxbuild error count behind a pass (0 = clean); recorded in the stamp
MXB_WHY=""             # mxbuild's errors[] reason when it exited without checking the model

# ── Exec approval (auto records itself) ──────────────────────────────────────
# bin/exec-approval.sh decides ask vs auto; the ASKING happens before exec.sh ever runs (in
# chat), so this script does not ask either way. What it must do is tell the truth about which
# mode ran, because under `auto` this BUILD-LOG row IS the safety net that used to be a
# question — see interview-protocol.md's "Exec approval is a separate knob". Resolved the same
# way exec.sh already resolves the toolkit for doctor.sh: $MXTK_ROOT, else the "Toolkit root"
# row this project's CLAUDE.local.md was wired with. bin/exec-approval.sh is not copied
# per-project (same as bin/interview-mode.sh), so it has to be found in the toolkit, not here.
# Never fatal: if it cannot be found, or errors, the row is written exactly as it always was.
_EXEC_APPROVAL_SUFFIX=""
for _ea in "${MXTK_ROOT:-}/bin/exec-approval.sh" \
           "$(sed -nE 's/^\| *Toolkit root *\| *`([^`]+)`.*/\1/p' "$PROJECT_ROOT/CLAUDE.local.md" 2>/dev/null | head -1)/bin/exec-approval.sh"; do
  [ -x "$_ea" ] || continue
  _ea_out="$("$_ea" "$PROJECT_ROOT" --explain 2>/dev/null)" || continue
  _ea_mode="$(printf '%s\n' "$_ea_out" | sed -n 's/^mode: //p')"
  _ea_from="$(printf '%s\n' "$_ea_out" | sed -n 's/^from: //p')"
  [ "$_ea_mode" = "auto" ] && _EXEC_APPROVAL_SUFFIX=" · approval: auto ($_ea_from)"
  break
done

log_build() {   # $1=status  $2=detail
  mkdir -p "$(dirname "$BUILD_LOG")"
  [ -f "$BUILD_LOG" ] || cat > "$BUILD_LOG" <<'HDR'
# Build log — auto-appended by bin/exec.sh

One line per exec against the model. Written by the script, not by hand, so it is
true even when someone forgets. Read this before assuming the model builds.

`gate` is the mxbuild verdict, and it is never blank:
`pass` verified clean · `fail` verified broken · `skipped` mxbuild/java missing ·
`unverified` errors file unparseable, or mxbuild exited non-zero without checking the
model (wrong version, JDK) · `not-run` the gate was never reached.
Only `pass` means anything looked at the model. A zero exit does not.

| when (ISO-8601 local) | script | gate | result | detail |
|---|---|---|---|---|
HDR
  # One-time migration: logs written before the gate column existed keep their
  # 4-column header, and 5-column rows would render ragged under it. Start a
  # fresh table rather than rewrite history.
  if ! grep -q '| when (ISO-8601 local) |' "$BUILD_LOG"; then
    cat >> "$BUILD_LOG" <<'HDR2'

<!-- gate column added; rows above this line predate it -->

| when (ISO-8601 local) | script | gate | result | detail |
|---|---|---|---|---|
HDR2
  fi
  # The gate cell is read from GATE_STATE rather than passed in, so no caller
  # can omit it — a blank cell in this table reads as "fine", which is the exact
  # false-green the gate exists to prevent.
  _detail="$2${CHANGE_CLASS:+ · change: $CHANGE_CLASS}${CR_ID:+ · cr: $CR_ID}${SCAN_NOTE:+ · $SCAN_NOTE}$_EXEC_APPROVAL_SUFFIX"
  printf '| %s | `%s` | %s | %s | %s |\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$LOG_NAME" \
    "${GATE_STATE:-not-run}" "$1" "$_detail" >> "$BUILD_LOG"
  record_metrics "$1"
}

# ── Metrics ledger (added 2026-10-12) ────────────────────────────────────────
# Every BUILD-LOG row also lands as one TSV row in .claude/loop/metrics-ledger.tsv — outcome
# class, elapsed seconds, mxbuild error count, lint verdict and total, whether a snapshot was
# restored, and the `mxcli report` score when one was taken this run. The BUILD-LOG is for a
# human reading one project; the ledger is for project-bin/metrics-trend.sh ("is the score
# moving, are gate failures falling, are execs getting faster") and for bin/harvest-learnings.sh,
# which carries the numbers into the toolkit so the question can be asked across projects.
# Hooked HERE so no outcome can skip it: a ledger with only the good runs would show a rising
# score and hide the restores it cost. Failure to append never fails the exec.
SCORED=0
record_metrics() {  # $1=status text (as given to log_build)
  [ -x "$PROJECT_ROOT/bin/metrics-ledger.sh" ] || return 0
  bash "$PROJECT_ROOT/bin/metrics-ledger.sh" exec \
    --script "$LOG_NAME" --gate "${GATE_STATE:-not-run}" --result "$1" \
    --elapsed "$(( $(date +%s) - _T0 ))" --mxbuild-errors "${GATE_ERRORS:-}" \
    --lint-rc "${LINT_RC_FOR_LEDGER:-}" --restored "${RESTORED:-0}" --scored "$SCORED" 2>/dev/null || true
}
# `mxcli report` scores the model (0-100, ≈7 s on an 876-flow model, 2026-10-12). Taken only
# after a clean mxbuild — a failed write is restored or never happened, so there is nothing
# new to score. MXTK_NO_SCORE=1 skips it (slow machine, CI); the row still lands, scores empty.
take_score() {
  [ -z "${MXTK_NO_SCORE:-}" ] || { echo "  · score skipped (MXTK_NO_SCORE)"; return 0; }
  [ -x "$PROJECT_ROOT/bin/metrics-ledger.sh" ] || return 0
  echo "→ Scoring the model (bin/metrics-ledger.sh score → mxcli report)..."
  if _sc=$(bash "$PROJECT_ROOT/bin/metrics-ledger.sh" score 2>&1); then
    SCORED=1; echo "  ✓ $_sc"
  else
    echo "  ⚠ ${_sc:-score not taken}"
  fi
}

# ── STOP-row scan (added 2026-10-14, #349) ───────────────────────────────────
# The toolkit's bin/mdl-scan.sh greps the script for the STOP rows of learned-mdl-preflight.md
# that a text pattern identifies — each one a script that passed `mxcli check`, cost a full
# apply and failed at mxbuild or on Studio Pro open. It runs first, before the lock, the
# commit, `mxcli check` and the snapshot: a hit costs milliseconds here and 22-65 s plus a
# restore after the apply. Each rule has a severity (bin/lib/mdl-scan-rules.tsv, whose header
# says when a rule may move from warn to block):
#   warn  (scan exit 3) — the hits are printed as warnings, the BUILD-LOG row notes them, and
#         the exec goes on. Every rule ships as warn until a field run proves it.
#   block (scan exit 1) — the exec is refused before anything is touched. FORCE_EXEC and
#         SKIP_CHECK do not skip it. The only override is MXTK_SCAN_OVERRIDE="<reason>", for
#         the user: printed and logged. Hardening it against an agent setting it is #348's job.
# Found like exec-approval.sh: $MXTK_ROOT, else the "Toolkit root" row of CLAUDE.local.md.
# Not found, or the scan itself errors (exit 2) → one warning, and the exec goes on: mxcli
# check and the mxbuild gate still stand behind it.
SCAN_NOTE=""
if [ "$PATCH_MODE" != "1" ]; then
  _SCAN=""
  for _s in "${MXTK_ROOT:-}/bin/mdl-scan.sh" \
            "$(sed -nE 's/^\| *Toolkit root *\| *`([^`]+)`.*/\1/p' "$PROJECT_ROOT/CLAUDE.local.md" 2>/dev/null | head -1)/bin/mdl-scan.sh"; do
    [ -f "$_s" ] && { _SCAN="$_s"; break; }
  done
  scan_ids() { printf '%s\n' "$_scan_out" | grep " \[$1\]\$" | sed -n 's/^\(STOP-[0-9a-z]*\) .*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
  if [ -z "$_SCAN" ]; then
    echo "⚠ STOP-row scan skipped: bin/mdl-scan.sh not found (set MXTK_ROOT to the toolkit)." >&2
  else
    _scan_rc=0; _scan_out="$(bash "$_SCAN" "$SCRIPT" 2>&1)" || _scan_rc=$?   # set -e: keep the rc
    case "$_scan_rc" in
      0) ;;
      3)
        printf '%s\n' "$_scan_out" | sed 's/^/⚠ /' >&2
        echo "  STOP-row scan: warnings only (rules not yet proven in the field) — going on. Read each line;" >&2
        echo "  each names its learned-mdl-preflight.md row and the rewrite." >&2
        SCAN_NOTE="scan warn: $(scan_ids warn)" ;;
      1)
        echo "$_scan_out"
        case "${MXTK_SCAN_OVERRIDE:-}" in
          ""|1|true|yes)
            echo ""
            echo "✗ STOP-row scan: refusing exec on a blocking rule. NOTHING was locked, snapshotted or written."
            echo "  Each line above names its learned-mdl-preflight.md row and the rewrite. Fix the script."
            echo "  Only the user may override, with a reason: MXTK_SCAN_OVERRIDE=\"<why>\" ./bin/exec.sh $SCRIPT"
            log_build "🚫 blocked" "STOP-row scan: $(printf '%s\n' "$_scan_out" | grep -c ' \[block\]$') blocking hit(s), $(scan_ids block) — nothing written"
            exit 1 ;;
          *)
            echo "⚠ STOP-row scan OVERRIDDEN by MXTK_SCAN_OVERRIDE: ${MXTK_SCAN_OVERRIDE}" >&2
            echo "  Only the user sets this. An agent that set it has broken the preflight rule." >&2
            SCAN_NOTE="scan overridden ($(scan_ids block)): $(printf '%s' "$MXTK_SCAN_OVERRIDE" | tr '|' '/')" ;;
        esac ;;
      *) echo "⚠ STOP-row scan could not run (exit $_scan_rc): $_scan_out" >&2 ;;
    esac
  fi
fi

# ── Concurrent-writer guard ──────────────────────────────────────────────────
# The .mpr must have exactly ONE writer. Two mxcli/SP writers on the same file
# silently clobber each other and have caused near-total module loss.
# Override (at your own risk): FORCE_EXEC=1 ./bin/exec.sh <script>
# The model tree (.mpr + mprcontents/) is NOT always $PROJECT_ROOT — on a two-tree
# checkout the app lives under app/. Every mprcontents/ path below goes through
# MODEL_DIR; see the find_model_dir header in _common.sh for what silently broke
# when they did not.
MODEL_DIR="$(find_model_dir 2>/dev/null || echo "$PROJECT_ROOT")"

LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
mkdir -p "$(dirname "$LOCK")"
FORCE="${FORCE_EXEC:-0}"

# 1. Studio Pro must not hold the project open (SP's in-memory model vs a direct
#    file write = split-brain).
SP_OPEN=0
if [ -f "$MPR.lock" ]; then
  SP_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
  if [ -n "$SP_PID" ] && kill -0 "$SP_PID" 2>/dev/null; then
    SP_OPEN=1
    echo "✗ Studio Pro has $NAME open (lock PID $SP_PID alive) — refusing exec (split-brain corruption risk)."
    echo "  → Close the project in Studio Pro (or quit SP), then re-run."
    echo "    Override (NOT recommended): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
    [ "$FORCE" = "1" ] || exit 1
    echo "  (FORCE_EXEC set — proceeding despite open SP)"
  elif [ -n "$SP_PID" ]; then
    echo "  (stale $MPR_BASE.lock from dead PID $SP_PID — SP not actually open, proceeding)"
  fi
fi

# 2. One exec.sh at a time on THIS project (e.g. a second agent session on the same model).
#
#    The lock is per project — $PROJECT_ROOT/.mpr-snapshots/.exec.lock — and holds
#    "<pid> <epoch> <script>". It is taken atomically (noclobber: O_EXCL, bash 3.2 / Git Bash /
#    macOS alike; no flock, which macOS and Git Bash do not ship), so two sessions starting in
#    the same second cannot both win. A lock whose pid is dead is STALE — a SIGKILL, a crash or
#    a closed terminal never runs the EXIT trap — and is taken over with a printed note; a
#    guard that needs a manual `rm` to recover blocks its own remedy (CLAUDE.md, instrument
#    rule 7). Where `ps -o args=` can show the pid's command line and it is not an exec.sh, the
#    pid was reused by an unrelated process and the lock is stale too; where it cannot (Git
#    Bash), `kill -0` alone decides. A lock file in the pre-2026-10-13 format (a bare pid) reads
#    the same way.
exec_lock_live() {  # $1 = pid from the lock; 0 iff that process is alive and plausibly exec.sh
  [ -n "$1" ] || return 1
  case "$1" in *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  # Linux: an unreaped zombie still answers kill -0; /proc/<pid>/stat says Z after the "(comm) ".
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  _args="$(ps -o args= -p "$1" 2>/dev/null || true)"
  case "$_args" in ""|*exec.sh*|*test-scratch.sh*) return 0 ;; esac   # test-scratch.sh holds it while copying
  return 1
}
exec_lock_try() { ( set -o noclobber; printf '%s %s %s\n' "$$" "$(date +%s)" "$LOG_NAME" > "$LOCK" ) 2>/dev/null; }
exec_lock_release() {  # the trap: remove the lock only while it is still ours
  _own="$(cat "$LOCK" 2>/dev/null || true)"
  [ "${_own%% *}" = "$$" ] && rm -f "$LOCK"
  return 0
}
# Taking over a stale lock is serialised through a second O_EXCL file, $LOCK.takeover. Under
# it the lock is re-read and removed ONLY if it still holds exactly the stale line judged above;
# nothing else ever removes a lock that is not its own, so the compare-then-rm cannot hit a
# fresh lock. WHY (independent review of #304): the old takeover moved the lock aside and put
# it back with `mv -f` when it found a fresh one there — check-then-act. With 3+ contenders, B
# moved A's fresh lock aside, C's noclobber write landed in the gap, B saw a lock and deleted
# A's: 12 contenders gave up to 3 holders at once (tests/wave2/test-exec-lock-watch.sh).
# A takeover file left by a holder killed inside those few microseconds is stale once its pid is
# dead or it is older than 10 s (an EMPTY one once it is over a minute old — `find -mmin +1`;
# `+0` matched a file created a second ago, so a live contender's fresh takeover file was judged
# stale and a third contender got in: review of #324). It is moved aside, and put back with `ln`
# (never clobbers; left on disk if that fails) if what was moved is not the one judged stale.
# The holder removes the takeover file only while it still holds the line it wrote.
exec_lock_takeover() {  # $1 = the stale lock line; 0 iff it was removed (or already gone)
  _tk="$LOCK.takeover"; _mine="$$ $(date +%s)"
  if ! ( set -o noclobber; printf '%s\n' "$_mine" > "$_tk" ) 2>/dev/null; then
    _t="$(head -1 "$_tk" 2>/dev/null || true)"; _tpid="${_t%% *}"; _tsince="${_t#* }"
    case "$_tsince" in ''|*[!0-9]*) _tsince=0 ;; esac
    _tstale=0
    if [ -n "$_t" ]; then
      { ! kill -0 "$_tpid" 2>/dev/null || [ $(( $(date +%s) - _tsince )) -gt 10 ]; } && _tstale=1
    elif [ -n "$(find "$_tk" -mmin +1 2>/dev/null)" ]; then
      _tstale=1   # empty for over a minute: its creator died between the create and the write
    fi
    if [ "$_tstale" = 1 ]; then
      if mv "$_tk" "$_tk.stale.$$" 2>/dev/null; then
        # Remove what was moved ONLY if it is what was judged stale; anything else is someone's
        # live takeover file: put it back (ln never clobbers), and if that fails leave it be.
        # Same body as test-scratch.sh's take_over() — keep the two in step (PR #322).
        if [ "$(head -1 "$_tk.stale.$$" 2>/dev/null || true)" = "$_t" ]; then rm -f "$_tk.stale.$$"
        else ln "$_tk.stale.$$" "$_tk" 2>/dev/null && rm -f "$_tk.stale.$$"; fi
      fi
    fi
    return 1
  fi
  _now="$(head -1 "$LOCK" 2>/dev/null || true)"
  [ "$_now" = "$1" ] && rm -f "$LOCK"
  [ "$(head -1 "$_tk" 2>/dev/null || true)" = "$_mine" ] && rm -f "$_tk"   # only our own takeover file
  return 0
}
LOCK_TAKEN=0
for _try in 1 2 3 4 5 6; do
  if exec_lock_try; then LOCK_TAKEN=1; break; fi
  _held="$(head -1 "$LOCK" 2>/dev/null || true)"
  if [ -z "$_held" ] && [ "$_try" -lt 3 ]; then sleep 1; continue; fi   # being written right now
  _hpid="${_held%% *}"
  if exec_lock_live "$_hpid"; then
    _hrest="${_held#* }"; _hsince="${_hrest%% *}"; _hscript="${_hrest#* }"
    _age=""
    case "$_hsince" in ''|*[!0-9]*) ;; *) _age=" for $(( $(date +%s) - _hsince ))s" ;; esac
    [ "$_hrest" = "$_held" ] && _hscript="?"
    echo "✗ Another session holds this project's exec lock (PID $_hpid, running$_age, script: $_hscript)."
    echo "  → Wait for it to finish, then re-run. Nothing was written."
    echo "    (A dead holder is detected and taken over automatically — no manual rm is ever needed.)"
    exit 1
  fi
  if exec_lock_takeover "$_held"; then
    echo "  (stale exec lock from PID ${_hpid:-?}, which is not running — taking it over)"
  else
    sleep 1   # another contender is taking it over right now; look again
  fi
done
if [ "$LOCK_TAKEN" != 1 ]; then
  echo "✗ Could not take the exec lock $LOCK after 6 attempts — another session keeps re-taking it."
  echo "  → Wait for the other exec to finish, then re-run. Nothing was written."
  exit 1
fi
trap 'exec_lock_release' EXIT

# 3. A raw `mxcli exec` elsewhere on the machine is NOT this project's business. The old guard
#    here (`pgrep -fl "mxcli exec"`) matched every exec on the machine, so a test run on a
#    scratch copy of a different project blocked an unrelated write (#287 item 3, compare
#    #228). Concurrency on THIS model is the lock above; this is a note, never a refusal.
if command -v pgrep >/dev/null 2>&1; then
  _raw="$(pgrep -f "mxcli exec" 2>/dev/null | grep -vx "$$" | head -3 | tr '\n' ' ' || true)"
  [ -n "$_raw" ] && echo "  note: an 'mxcli exec' is running elsewhere on this machine (PID ${_raw% }) — not blocking; only another exec.sh on this project is."
fi

# 4. Uncommitted model changes. The snapshot taken below would not cover them,
#    so a failed gate would auto-restore to a state pre-dating those changes and
#    silently lose work. --commit-first (opt-in) commits exactly the model paths first.
MODEL_PATHS="$MPR"
[ -e "$MODEL_DIR/mprcontents" ] && MODEL_PATHS="$MODEL_PATHS
$MODEL_DIR/mprcontents"
commit_model_first() {
  if [ "$SP_OPEN" = 1 ]; then
    echo "✗ --commit-first refused: Studio Pro holds $NAME (PID $SP_PID). Its in-memory model is not"
    echo "  what is on disk, so a commit now would record a state nobody is looking at."
    echo "  → Save and close the project in Studio Pro, then re-run. Nothing was committed or executed."
    log_build "🚫 blocked" "--commit-first refused: Studio Pro holds the model"
    return 1
  fi
  echo "→ --commit-first: committing ONLY these model paths (nothing else is staged or committed):"
  echo ""
  echo "$MPR_DIRTY" | sed 's/^/    /'
  echo ""
  set -f; _IFS="$IFS"; IFS='
'
  # shellcheck disable=SC2086
  _other=$(( $(git diff --cached --name-only 2>/dev/null | grep -c . || true) - $(git diff --cached --name-only -- $MODEL_PATHS 2>/dev/null | grep -c . || true) ))
  [ "$_other" -gt 0 ] && echo "  ($_other other staged path(s) stay staged and are NOT part of this commit.)"
  if ! git add -- $MODEL_PATHS; then
    IFS="$_IFS"; set +f
    echo "✗ --commit-first: git add of the model paths failed — nothing was committed or executed."
    log_build "🚫 blocked" "--commit-first: git add failed"
    return 1
  fi
  if ! _cout="$(git commit -q -m "model: commit pending model changes before exec.sh $LOG_NAME" \
        -m "Committed by bin/exec.sh --commit-first so the pre-exec snapshot covers them. Model paths only." \
        -- $MODEL_PATHS 2>&1)"; then
    IFS="$_IFS"; set +f
    printf '%s\n' "$_cout" | sed 's/^/    /'
    echo "✗ --commit-first: git commit was refused — nothing was executed. The model paths are left staged."
    echo "  If the model-stamp hook refused it: ./bin/verify-model.sh (one mxbuild, stamps a clean model),"
    echo "  then re-run with --commit-first."
    log_build "🚫 blocked" "--commit-first: git commit refused"
    return 1
  fi
  IFS="$_IFS"; set +f
  echo "  ✓ committed $(git rev-parse --short HEAD 2>/dev/null) — model paths only"
  return 0
}
MPR_DIRTY=$(git status --porcelain "$MPR" "$MODEL_DIR/mprcontents" 2>/dev/null | grep -v "^$" || true)
if [ -n "$MPR_DIRTY" ] && [ "$COMMIT_FIRST" = 1 ]; then
  commit_model_first || exit 1
  MPR_DIRTY=$(git status --porcelain "$MPR" "$MODEL_DIR/mprcontents" 2>/dev/null | grep -v "^$" || true)
fi
if [ -n "$MPR_DIRTY" ]; then
  echo "✗ Uncommitted model changes — refusing exec to prevent snapshot regression."
  echo ""
  echo "$MPR_DIRTY" | sed 's/^/    /'
  echo ""
  echo "  → git add $MPR $MODEL_DIR/mprcontents && git commit -m 'Commit model changes before exec'"
  echo "  → or let exec.sh make exactly that commit, model files only: ./bin/exec.sh --commit-first $SCRIPT"
  echo "  Override (accepts silent-loss risk): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
  if [ "$FORCE" != "1" ]; then
    # A refusal here is otherwise invisible in docs/BUILD-LOG.md — nothing runs
    # after this exit, so the row has to be written before it, same shape as
    # every other blocked-exec row this script writes.
    log_build "🚫 blocked" "uncommitted model changes — refusing exec to prevent snapshot regression"
    exit 1
  fi
  echo "  (FORCE_EXEC set — proceeding despite uncommitted changes)"
fi

# 5. Module brief advisory (WARNS, never blocks).
#
# WHY THE BRIEF. It is the mdl-agent's single per-module input: the access-table slice,
# screens-per-role, field-level validation rules, edge cases, and the wireframe->page map.
# Nothing else in the project carries them. Without it the agent synthesises them from
# training data, and every access-rights / wrong-binding / invented-validation incident
# traces back to that. Real incident (a customer training round, 2026-08-25): 12 domain
# scripts and 13 feature scripts executed against a module whose architecture/modules/<M>/
# held only definition.md.
#
# WHY THIS ONLY WARNS. The brief is a build-plan artifact — "write the module brief" is a
# numbered row at the head of each phase (brd-to-build-plan.md Step 5). That is where the
# ordering guarantee belongs, because that is the document every build follows. exec.sh is
# not the pipeline's gatekeeper and must not become one: the toolkit is deliberately usable
# a la carte, and refusing a write is the wrong answer to "this project chose not to run the
# pipeline". A hard block here would also have needed FORCE_EXEC on every legitimate
# non-pipeline write, and a guard routinely overridden teaches people to override guards.
#
# So: no architecture/build-plan.md means the project never opted in, and this block says
# nothing at all. With a build plan, a missing brief means a row was skipped — worth saying
# once, out loud, and then getting out of the way.
#
# Satisfied by EITHER form, because single-module projects merge the brief into the plan
# rather than maintaining two documents that overlap ~70%:
#   a) architecture/modules/<Module>/module-brief.md
#   b) a "## Module brief - <Module>" heading in architecture/build-plan.md
#
# Platform and marketplace modules are skipped - this project does not author their briefs.
brief_missing=""
if [ "$PATCH_MODE" != "1" ] && [ -f "$SCRIPT" ] && [ -f "$PROJECT_ROOT/architecture/build-plan.md" ]; then
  # Comments FIRST, before any pattern match. A `-- ... CREATE MODULE errors if ...` line in a
  # real workshop script otherwise yielded a module named "errors" and would have demanded a
  # brief for it forever. A guard that cries wolf gets switched off — same reasoning as
  # bin/check-portability.sh's "NOT on the denylist" note. POSIX awk, no python/perl: Git Bash
  # on Windows has to run this too.
  # Assigned single-quoted, invoked double-quoted: bash does not re-expand the *result* of a
  # variable expansion, so awk's $0 survives. The alternative (inlining the program in quotes)
  # was tried and mangled it — $0 expanded to the shell script's own name.
  awk_strip_comments='
    {
      s = $0; out = ""; i = 1
      while (i <= length(s)) {
        c = substr(s, i, 2)
        if (!inblk && c == "/*") { inblk = 1; i += 2; continue }
        if (inblk  && c == "*/") { inblk = 0; i += 2; continue }
        if (!inblk && c == "--") { break }
        if (!inblk) out = out substr(s, i, 1)
        i++
      }
      print out
    }'
  script_body=$(awk "$awk_strip_comments" "$SCRIPT" 2>/dev/null)

  # Modules written to by this script: the qualified name on a create/alter/drop target.
  script_modules=$(printf '%s\n' "$script_body" \
    | grep -oiE '(create|alter|drop)[[:space:]]+(or[[:space:]]+modify[[:space:]]+)?(persistent[[:space:]]+|non-persistent[[:space:]]+)?[a-z_ ]*[[:space:]]"?([A-Za-z_][A-Za-z0-9_]*)"?\.' \
    | grep -oE '"?[A-Za-z_][A-Za-z0-9_]*"?\.$' | tr -d '".' | sort -u)
  # DELIBERATELY NOT `CREATE MODULE <X>` on its own. Creating an empty module is scaffolding; the
  # brief describes what goes *inside* one, so demanding it before the module exists is backwards.
  # It also keeps tests/wave2/test-bug07-08.sh working — its fixture project execs
  # `CREATE MODULE "Nope";` with no architecture/ at all, and would otherwise fail every case.
  #
  # Everything else about a module DOES need the brief first, including `create or modify module
  # role <M>.<Role>` — module roles are the subject of the brief's access table, so authoring them
  # unspecified is the exact gap this guard exists to close. Replaying that round's real day
  # 1 (28 scripts, empty architecture/) the first refusal lands on script 1, at the module-role
  # line in 01-app-scaffold.mdl. That is the intended blast radius: the brief is row 0, so nothing
  # numbered after it may run first.

  for m in $(echo "$script_modules" | grep -v '^$' | sort -u); do
    case "$m" in
      System|Administration|Atlas_Core|Atlas_Web_Content|Atlas_UI_Resources|MxModelReflection      |CommunityCommons|Encryption|NanoflowCommons|WebActions|DeepLink|MxTest) continue ;;
    esac
    [ -f "$PROJECT_ROOT/architecture/modules/$m/module-brief.md" ] && continue
    grep -qiE "^#+[[:space:]]*Module brief[[:space:]]*(—|-|:)[[:space:]]*$m[[:space:]]*$" \
      "$PROJECT_ROOT/architecture/build-plan.md" 2>/dev/null && continue
    brief_missing="$brief_missing $m"
  done
fi
if [ -n "$brief_missing" ]; then
  echo "⚠ No module brief for:$brief_missing — proceeding, but nothing has specified this module."
  echo ""
  for m in $brief_missing; do
    echo "    $m — expected architecture/modules/$m/module-brief.md"
    echo "         or a '## Module brief - $m' section in architecture/build-plan.md"
  done
  echo ""
  echo "  This project has a build plan, so a row was skipped: the brief is the first row of"
  echo "  this module's phase. It carries the access table, screens-per-role, validation rules,"
  echo "  edge cases, wireframe->page map and test plan — see module-brief.md."
  echo "  → Write it before the next script, or the MDL after this one is guesswork too."
  echo ""
fi

# (The exec lock is taken in guard 2 above, with its EXIT trap, so it covers the commit-first
# step and every refusal in between.)
# ─────────────────────────────────────────────────────────────────────────────

# ── Stale gate artefact ──────────────────────────────────────────────────────
# last-mxbuild-errors.json is written only on the failure paths below and was
# never removed, so after one bad run it outlived every clean run that followed
# while iterative-build-loop.md still points readers at it for "full error
# detail". Clear it HERE, at the start, rather than on success: a run killed
# mid-flight (Ctrl-C, crash, SP taking the lock) reaches no success path and
# would otherwise leave the old file looking like a report on the run that died.
# One generation is archived as .prev — the previous failure's detail is often
# still wanted after a re-run.
LAST_ERRS="$PROJECT_ROOT/.mpr-snapshots/last-mxbuild-errors.json"
if [ -f "$LAST_ERRS" ]; then
  mv -f "$LAST_ERRS" "$LAST_ERRS.prev" 2>/dev/null || rm -f "$LAST_ERRS"
fi


# ── Lint ratchet ─────────────────────────────────────────────────────────────
# Added 2026-09-24. mxbuild proves the model compiles; it says nothing about how it
# is built. On a field project a migration microflow shipped with three commits
# inside loops (mxcli lint CONV011) under a "✅ applied · mxbuild clean" row, because
# nothing on this path ever ran lint: the gate-agent listed lint as optional and had
# been spawned 0 times against 21 exec.sh runs, and lint-gate.sh had only ever been
# run by hand to seed its baseline. An instrument that lives in an agent definition
# is a suggestion; one that lives here runs. So lint runs HERE, after a clean
# mxbuild, and its verdict lands in the same BUILD-LOG row as the mxbuild verdict.
#
# Semantics: a rise vs the committed baseline exits 1 but does NOT restore the
# snapshot — lint findings are about shape, not corruption, and the write is
# fixable by a follow-up script; a restore here would teach people to skip it.
# SKIP_LINT=<reason> is the only override and the reason is written into the row.
# A project without bin/lint-gate.sh gets a "lint not installed" cell, never a
# blank one — a blank cell reads as fine, which is the false-green this exists
# to stop. ~13 s measured on a 10k-finding project.
LINT_RC=0; LINT_DETAIL="lint not-run"
run_lint_gate() {
  if [ -n "${SKIP_LINT:-}" ]; then
    LINT_DETAIL="lint SKIPPED (SKIP_LINT=$SKIP_LINT)"
    echo "  ⚠ lint ratchet skipped: SKIP_LINT=$SKIP_LINT"; return
  fi
  if [ ! -x "$PROJECT_ROOT/bin/lint-gate.sh" ]; then
    LINT_RC=2; LINT_DETAIL="lint not installed (bin/lint-gate.sh missing — sync-project.sh installs it)"
    echo "  ⚠ $LINT_DETAIL"; return
  fi
  echo "→ Running lint ratchet (bin/lint-gate.sh, read-only)..."
  _lo=$(mktemp /tmp/lint-gate-out.XXXXXX)
  # exec.sh runs under set -e: a bare failing command here aborts the script with no BUILD-LOG
  # row at all (measured on the first wired run in a real project, 2026-09-24). Capture explicitly.
  LINT_RC=0
  bash "$PROJECT_ROOT/bin/lint-gate.sh" >"$_lo" 2>&1 || LINT_RC=$?
  # lint-gate's non-blocking SEC014 note (#312: rule installed, decision not made) is otherwise
  # visible only on a failing run, because the capture above is shown only then. Always echo it.
  [ -f "$_lo" ] && { grep '^note: SEC014' "$_lo" 2>/dev/null | sed 's/^/    /' || true; }
  case "$LINT_RC" in
    0) LINT_DETAIL="lint unchanged vs baseline"; echo "  ✓ lint: no rule rose vs baseline" ;;
    1) # Rule ids are matched as [A-Z][A-Z0-9-]*[0-9]+, not [A-Z]+[0-9]+: mxcli's built-in
       # rules include hyphenated ids (MDL-FLOW01), and the old pattern dropped them from every
       # row — three field apps logged 475 ROSE rows and not one named MDL-FLOW01 (2026-10-12).
       _rules=$(grep -E '^ +[A-Z][A-Z0-9-]*[0-9]+ +[a-z]+ +[0-9]+ -> [0-9]+ +\(\+[0-9]+\)' "$_lo" \
                 | awk '{printf "%s %s ", $1, $6}')
       _blind=$(sed -n '/^!! A RULE COULD NOT READ/,/^$/p' "$_lo" \
                 | grep -oE '^ +[A-Z][A-Z0-9-]*[0-9]+:' | tr -d ' :' | sort -u | paste -sd, -)
       _reverted=$(sed -n '/^!! LINT RULES REVERTED TO STOCK/,/^$/p' "$_lo" \
                    | grep -oE '^ +[A-Za-z0-9_.-]+\.star:' | tr -d ' :' | paste -sd, -)
       if grep -q '^BLIND — lint rules reverted to stock' "$_lo"; then
         # `mxcli init` re-seeded the toolkit rules (#264): lint-gate did not lint. Logging this
         # as a rise blamed the next script for CONV010 26 -> 169 on flows it never touched.
         LINT_RC=3
         LINT_DETAIL="lint BLIND: rules reverted to stock (${_reverted:-see output}) — run sync-project.sh; delta not attributable"
         echo "  ✗ lint: toolkit rules reverted to stock (${_reverted:-see output}) — not linted, not a rise"
         sed -n '/^!! LINT RULES REVERTED TO STOCK/,/^BLIND/p' "$_lo" | head -16 | sed 's/^/    /'
       elif [ -z "$_rules" ] && grep -q '^PASS' "$_lo"; then
         # lint-gate exits 1 for PASS-BLIND too. Logging that as "ROSE: see output" made a rule
         # that inspected nothing look like a rise with no rule named — 20 such rows in two
         # field apps whose CONV020 shipped unconfigured (#229). It is an instrument fault.
         LINT_RC=3
         LINT_DETAIL="lint BLIND: ${_blind:-a rule} inspected nothing (instrument fault, not a rise)"
         echo "  ✗ lint: nothing rose, but ${_blind:-a rule} could not read the model — a clean count means nothing"
         sed -n '/^!! A RULE COULD NOT READ/,/^$/p' "$_lo" | head -12 | sed 's/^/    /'
         echo "    Configure or fix the rule (see the message above); do not re-baseline over it."
       else
         LINT_DETAIL="lint ROSE: ${_rules:-see output}${_blind:+; BLIND: $_blind}"
         echo "  ✗ lint: rule(s) rose vs baseline — ${_rules:-see below}"
         sed -n '/^FAIL/,$p' "$_lo" | head -60 | sed 's/^/    /'
         echo "    Fix the script and re-run. Accepting the debt is the user's call, made in chat:"
         echo "    bin/lint-gate.sh --update-baseline --reason \"<why>\" (a security-tier rise also"
         echo "    needs --approved-in-chat). The acceptance is logged to .claude/lint-acceptances.tsv."
       fi ;;
    *) LINT_DETAIL="lint could not run (lint-gate exit $LINT_RC)"; echo "  ⚠ $LINT_DETAIL"
       tail -5 "$_lo" | sed 's/^/    /' ;;
  esac
  rm -f "$_lo"
}
# One place decides the applied-row wording, so both mxbuild-clean branches agree.
log_applied() {  # $1 = mxbuild detail
  run_lint_gate
  LINT_RC_FOR_LEDGER="$LINT_RC"
  take_score
  if [ "$LINT_RC" -eq 1 ]; then
    log_build "⚠️ applied, LINT ROSE" "$1; $LINT_DETAIL"
  elif [ "$LINT_RC" -eq 3 ]; then
    log_build "⚠️ applied, LINT BLIND" "$1; $LINT_DETAIL"
  else
    log_build "✅ applied" "$1; $LINT_DETAIL"
  fi
}

# ── Pre-exec syntax gate ─────────────────────────────────────────────────────
# `mxcli check --references` is the ONLY gate that can reject a bad script
# before it mutates the .mpr. Every gate after this one recovers by snapshot
# restore. It was mandated in prose (CLAUDE.md, learned-mdl-preflight.md) and
# enforced nowhere — the pipeline went snapshot → exec → mxbuild. Costs ~2s on
# a passing build. SKIP_CHECK=1 for the rare script mxcli's parser rejects but
# the model accepts (log why, in the script).
PMXCLI="$(find_project_mxcli 2>/dev/null || true)"
if [ "$PATCH_MODE" = "1" ]; then
  echo "→ --patch: no pre-exec mxcli check (not MDL). The mxbuild gate below is this write's only check."
elif [ "${SKIP_CHECK:-0}" != "1" ] && [ -n "$PMXCLI" ]; then
  echo "→ Pre-exec check: mxcli check (grammar + references)..."
  if ! "$PMXCLI" check "$SCRIPT" -p "$MPR" --references; then
    echo ""
    echo "  ✗ mxcli check failed — refusing to exec. NOTHING was written to the model."
    echo "    Fix the script, or re-run with SKIP_CHECK=1 if you know why the parser is wrong."
    log_build "🚫 blocked" "mxcli check failed pre-exec — nothing written to the model"
    exit 1
  fi
  echo "  ✓ check clean"
fi

# ── Gate must be able to run ─────────────────────────────────────────────────
# Discovery happens BEFORE the snapshot and the write, because the answer decides whether
# there is a write at all. Until 2026-09-17 a missing mxbuild produced a warning and the
# script was applied anyway, "gate=skipped". Nobody acts on a skip: on one field project every exec.sh
# run in a cloud container skipped, a CE0117 that only mxbuild can see went in, and it
# reached the Team Server. So now: (1) a missing mxbuild is DOWNLOADED, right here, through
# the project's own ./mxcli (the same download doctor --install runs; mxtk_ensure_mxbuild);
# (2) if the gate still cannot run, the write is REFUSED, before anything is touched. Guard
# rules 6/7 hold — the remedy is performed, not blocked, and ALLOW_UNVERIFIED=1 says out
# loud "write anyway"; that write then carries no verification stamp, so the pre-commit
# hook refuses it until ./bin/verify-model.sh has seen it.
MXBUILD="$(mxtk_ensure_mxbuild "$MPR" || true)"
# Was: JAVA_HOME=$(/usr/libexec/java_home ...) — a macOS-only binary, so on Windows
# JAVA_HOME came back empty, JAVA_EXE was the literal "/bin/java", the gate guard
# below failed its -x test and the entire mxbuild block was skipped on every run.
# find_java/find_java_exe (project-bin/_common.sh) resolve per platform and prefer
# Studio Pro's own bundled JRE, which is the one paired with this mxbuild.
JAVA_HOME="$(find_java 2>/dev/null || true)"
JAVA_EXE="$(find_java_exe 2>/dev/null || true)"

# Say WHY the gate will be skipped, at the point we can still name the cause. The
# gate's own "skipped" verdict is honest but arrives without a reason, and a skip
# nobody can explain is a skip nobody acts on — which is how Windows machines ran
# unverified execs for an entire training round.
if [ ! -x "$MXBUILD" ] || [ ! -x "$JAVA_EXE" ]; then
  if [ "${ALLOW_UNVERIFIED:-0}" = "1" ] && [ "$PATCH_MODE" != "1" ]; then
    echo "⚠ ALLOW_UNVERIFIED=1: mxbuild gate will be SKIPPED — this exec will NOT be model-verified." >&2
    [ -x "$MXBUILD" ]  || echo "    mxbuild not found/executable: ${MXBUILD:-<none>}   (set MXBUILD_PATH=)" >&2
    [ -x "$JAVA_EXE" ] || echo "    java not found/executable:    ${JAVA_EXE:-<none>}  (set JAVA_HOME=)" >&2
  else
    echo "" >&2
    echo "✗ REFUSING to exec: the mxbuild gate cannot run on this machine, so nothing could verify the write." >&2
    [ -x "$MXBUILD" ]  || echo "    mxbuild not found/executable: ${MXBUILD:-<none>}   (MXBUILD_PATH= overrides; bin/doctor.sh --install <project> downloads it)" >&2
    [ -x "$JAVA_EXE" ] || echo "    java not found/executable:    ${JAVA_EXE:-<none>}  (JAVA_HOME= overrides; install a JDK)" >&2
    echo "  NOTHING was written to the model. Fix the gate (bin/doctor.sh --install <project>), then re-run." >&2
    if [ "$PATCH_MODE" = "1" ]; then
      echo "  --patch keeps a write only on a verified gate, so ALLOW_UNVERIFIED does not apply to it." >&2
    else
      echo "  To write anyway, unverified: ALLOW_UNVERIFIED=1 ./bin/exec.sh $SCRIPT  — the commit hook will then" >&2
      echo "  refuse the result until ./bin/verify-model.sh has run the gate over it." >&2
    fi
    log_build "✗ refused" "mxbuild gate cannot run (mxbuild: $([ -x "$MXBUILD" ] && echo ok || echo missing), java: $([ -x "$JAVA_EXE" ] && echo ok || echo missing)); nothing written"
    exit 1
  fi
fi

echo "→ Snapshotting model..."
./bin/snapshot-mpr.sh

# ── Restore (one implementation) ─────────────────────────────────────────────
# Rolls the model back to the snapshot just taken, through restore-mpr.sh. exec.sh used to
# carry an inline copy of it that had only the mprcontents/ (v2) arm, so on a v1 single-file
# model (field project, 152 MB, 2026-09-26) every failed gate printed "Snapshot has no
# mprcontents/ — refusing to restore" and left the broken model in place. Sets RESTORED=1 on
# success; prints the manual recovery line otherwise. Used by the failed gate and by --patch.
RESTORED=0
RESTORE_TRIED=0
restore_snapshot() {
  RESTORE_TRIED=1
  NEWEST_SNAP=$(ls -dt "$PROJECT_ROOT/.mpr-snapshots"/[0-9]*/ 2>/dev/null | head -1)
  RESTORER="$(dirname "$0")/restore-mpr.sh"
  if [ -z "$NEWEST_SNAP" ] || [ ! -f "$NEWEST_SNAP/$MPR_BASE" ]; then
    echo "  ⚠  No usable snapshot to restore from — the model is left as the script wrote it."
  elif [ ! -f "$RESTORER" ]; then
    echo "  ⚠  bin/restore-mpr.sh is not installed — cannot auto-restore (run sync-project.sh)."
  elif R_OUT=$(bash "$RESTORER" "$NEWEST_SNAP" 2>&1); then
    RESTORED=1
    printf '%s\n' "$R_OUT" | sed 's/^/  → /'
    echo "  → Auto-restored from: $NEWEST_SNAP"
  else
    printf '%s\n' "$R_OUT" | sed 's/^/     /'
    echo "  ⚠  RESTORE FAILED from $NEWEST_SNAP."
  fi
  if [ "$RESTORED" -ne 1 ]; then
    if [ -d "$MODEL_DIR/mprcontents" ]; then
      echo "     Recover with: git checkout HEAD -- $MPR_BASE mprcontents/   (or ./bin/restore-mpr.sh)"
    else
      echo "     Recover with: git checkout HEAD -- $MPR_BASE   (or ./bin/restore-mpr.sh)"
    fi
  fi
}

# ── JSON reader ──────────────────────────────────────────────────────────────
# The mxbuild gate reads its verdict out of a JSON errors file, so it needs a
# JSON parser. `python3` is not guaranteed: a bare macOS has no /usr/bin/python3
# until the Command Line Tools are installed, and some minimal Linux images ship
# only `python`. Hardcoding `python3` meant that on such a machine all three
# helpers below silently fell back to their "unknown" sentinels, the gate
# reported `unverified` on every run, and the message the user saw blamed the
# errors file — pointing the diagnosis away from the actual cause.
#
# Resolve once, say so loudly if there is nothing to resolve to. Override with
# PYTHON=/path/to/python3.
#
# The probe itself is _common.sh's resolve_py — the non-fatal twin of require_py, which
# would exit 2 here and take the write with it. This script must still apply and snapshot
# your changes on a machine with no interpreter; only the GATE is unavailable, and saying
# that plainly is the whole point of the block below.
#
# resolve_py probes by RUNNING each candidate, never `command -v`: on a Mac without the
# Command Line Tools /usr/bin/python3 is a prompt-only stub, and on Windows `python3` is
# usually the Store alias stub. Both satisfy a presence test and neither runs anything, so
# a presence test would set PY and the warning below would never fire on exactly the
# machines it was written for.
#
# Guarded fallback, not a second implementation: sync-project.sh installs a missing
# _common.sh but REPORTS a locally-modified one rather than overwriting it, so a project
# that hardened its crash net before resolve_py existed would receive this script and die
# on "resolve_py: command not found". Same reason lint-gate.sh carries one.
if ! type resolve_py >/dev/null 2>&1; then
  resolve_py() {
    _c=""
    for _c in "${PYTHON:-}" python3 python py; do  # portability-ok: this IS the interpreter probe
      [ -n "$_c" ] || continue
      case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
      if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
        echo "$_c"; return 0
      fi
    done
    return 1
  }
fi
PY="$(resolve_py || true)"
if [ -z "$PY" ]; then
  echo "  ⚠  No WORKING Python 3 found (tried python3, python, py by running each one)."  # portability-ok: names in a diagnostic
  echo "     The mxbuild gate cannot read its results. Your changes are still written and"
  echo "     snapshotted, but the gate will report 'unverified' on every run: NOTHING is"
  echo "     being verified."
  echo "     Fix: install Python 3 (macOS: xcode-select --install), or set PYTHON=/path/to/python3"  # portability-ok: names in a diagnostic
fi

# The path goes through native_path (_common.sh): on Git Bash the mktemp'd
# /tmp/... spelling is inside a Python -c string, where MSYS does not convert
# it, and a native Windows Python cannot open it. Before this, every helper
# below answered "?" on Windows and a real CE degraded to "unverified" with
# the broken model left in place (field run 2026-09-14, Studio Pro 11.12.4).
err_count() {  # $1=errors json
  [ -n "$PY" ] || { echo "?"; return; }
  "$PY" -c "import json;d=json.load(open('$(native_path "$1")'));print(len([x for x in d.get('problems',[]) if x.get('severity')=='Error']))" 2>/dev/null || echo "?"
}
err_codes() {
  [ -n "$PY" ] || { echo "?"; return; }
  "$PY" -c "import json;d=json.load(open('$(native_path "$1")'));print(','.join(sorted({x.get('errorCode','?') for x in d.get('problems',[]) if x.get('severity')=='Error'})))" 2>/dev/null || echo "?"
}
# err_set <errors.json> — one key per Error problem: a short hash of errorCode + message +
# every location's module / document / element, sorted, duplicates KEPT, joined with "|".
# The key used to be the message text alone. On a real 22-error model (Mendix 11.12.1),
# 20 of the 22 shared two messages ("Could not find widget 'Markdown viewer' …" x15,
# "… 'Events' …" x5), and mxbuild's CE0117 message is always "Error(s) in expression." —
# so while one CE0117 or one missing widget was in the baseline, a script could add any
# number more and the gate kept it.
# Names, not elementId GUIDs: a CREATE OR REPLACE re-mints the GUIDs of a microflow whose
# pre-existing error it leaves in place, and that must still read as pre-existing. A rename
# does read as new, and restores — the safe direction. Hex tokens: no "|" or glob characters,
# whatever the message says. ERRKEY_PY is the one definition of that key: err_set and
# err_report both prepend it, so "new" in the verdict and "NEW" in the report cannot drift.
ERRKEY_PY='import hashlib
def errkey(x):
    locs = sorted("\x1e".join(str(l.get(k) or "") for k in ("module", "document", "element"))
                  for l in (x.get("locations") or []))
    raw = "\x1f".join([x.get("errorCode") or "", x.get("message") or ""] + locs)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]'
err_set() {
  [ -n "$PY" ] || { echo ""; return; }
  { printf '%s\n' "$ERRKEY_PY"; cat <<'ERRSETPY'; } | "$PY" - "$(native_path "$1")" 2>/dev/null || echo ""
import json, sys
d = json.load(open(sys.argv[1]))
print('|'.join(sorted(errkey(x) for x in d.get('problems', []) if x.get('severity') == 'Error')))
ERRSETPY
}

# err_report count|print <errors.json> — splits the post-exec errors against BASELINE_SET,
# counted the same way is_subset_of counts. Only when the baseline was measured
# (BASE_KNOWN=1); otherwise every error is listed as before, with no new/old split.
#   count → "<new count> <new codes, comma-joined>", or "?" when the baseline is unknown.
#   print → the NEW errors in full (code, message, where, expression detail), then the
#           pre-existing ones as one line per code + message with a count.
# Why (field run, 2026-09-29): a restore on a 22-error model printed "22 error(s) found"
# and all 22 with locations; the one the script added was not marked, and the count was
# the same as before the script ran.
err_report() {
  [ -n "$PY" ] || { [ "$1" = count ] && echo "?"; return; }
  { printf '%s\n' "$ERRKEY_PY"; cat <<'ERRREPPY'; } | "$PY" - "$1" "$(native_path "$2")" "$BASELINE_SET" "${BASE_KNOWN:-0}" 2>/dev/null || { [ "$1" = count ] && echo "?"; }
import json, sys
from collections import Counter
mode, known = sys.argv[1], sys.argv[4] == '1'
d = json.load(open(sys.argv[2]))
left = Counter(k for k in sys.argv[3].split('|') if k)
new, old = [], []
for x in d.get('problems', []):
    if x.get('severity') != 'Error':
        continue
    k = errkey(x)
    if known and left[k] > 0:
        left[k] -= 1
        old.append(x)
    else:
        new.append(x)
if mode == 'count':
    print('%d %s' % (len(new), ','.join(sorted(set(x.get('errorCode') or '?' for x in new)))) if known else '?')
    sys.exit(0)
if known:
    print('   NEW, from this script (%d):' % len(new))
for e in new:
    print('  ', e.get('errorCode', '?'), e.get('message', ''))
    for loc in e.get('locations', []) or []:
        print('      at', loc.get('module', '-'), '/', loc.get('document', '-'), '/', loc.get('element', '-'))
    md = e.get('metadata') or {}
    if md.get('expressionErrors'):
        print('      expression:', md['expressionErrors'])
if old:
    print('   Already there before this script, not why it was undone (%d):' % len(old))
    for (code, msg), n in sorted(Counter((e.get('errorCode', '?'), e.get('message', '')) for e in old).items()):
        print('  ', code, msg, ('x%d' % n) if n > 1 else '')
ERRREPPY
}

# is_subset_of <candidate> <superset> — both are err_set's "|"-joined sorted key lists.
# True (exit 0) when <candidate> is a sub-MULTISET of <superset>: each key in <candidate>
# consumes one occurrence in <superset>, so a baseline holding an error once does not
# excuse the same error twice. An empty <candidate> (0 post-exec errors) is trivially a
# subset. Bash-native, no extra Python call. Word-splitting on IFS='|' and ${var/pat/rep},
# no arrays or `read -a` — bash 3.2 / Git Bash safe.
is_subset_of() {
  _cand="$1"
  [ -z "$_cand" ] && return 0
  _super="|$2|"
  _oldIFS="$IFS"
  IFS='|'
  for _e in $_cand; do
    IFS="$_oldIFS"
    [ -z "$_e" ] && continue
    case "$_super" in
      *"|$_e|"*) _super="${_super/|$_e|/|}" ;;
      *) return 1 ;;
    esac
    IFS='|'
  done
  IFS="$_oldIFS"
  return 0
}

# ── Doctor freshness (warn-only) ─────────────────────────────────────────────
# doctor.sh used to run once, at install, and never again. A machine that drifts mid-project
# (new mxcli, a wrong-arch mxbuild, an endpoint agent slowing every fork) then reads as "the
# toolkit is broken" — the pilot of 2026-09-04 found a build gate that had reported 0 errors
# for several commits with an mxbuild that could not execute. So: if the receipt is missing,
# older than a day, or its fingerprint (mxcli version | mxbuild | arch) no longer matches, run
# `doctor.sh --quick` here. It NEVER blocks (guard rules 6 and 7): it prints, and the exec goes on.
_DR="$PROJECT_ROOT/.claude/.doctor-receipt"
_DOCTOR=""
for _c in "${MXTK_ROOT:-}/bin/doctor.sh" "$(sed -nE 's/^\| *Toolkit root *\| *`([^`]+)`.*/\1/p' "$PROJECT_ROOT/CLAUDE.local.md" 2>/dev/null | head -1)/bin/doctor.sh"; do
  [ -x "$_c" ] && { _DOCTOR="$_c"; break; }
done
if [ -n "$_DOCTOR" ] && [ "${SKIP_DOCTOR:-0}" != "1" ]; then
  _why=""
  if [ ! -f "$_DR" ]; then _why="no doctor receipt in this project"
  elif [ -n "$(find "$_DR" -mmin +1440 2>/dev/null)" ]; then _why="doctor receipt is older than a day"
  else
    _fp_now="$( [ -x "$PROJECT_ROOT/mxcli" ] && "$PROJECT_ROOT/mxcli" --version 2>/dev/null | head -1 || echo none) | ${MXBUILD:-no-mxbuild} | $(uname -sm)"
    _fp_old="$(sed -n '2s/^fingerprint: //p' "$_DR")"
    [ "$_fp_now" = "$_fp_old" ] || _why="environment changed since doctor last ran ($_fp_old → $_fp_now)"
  fi
  if [ -n "$_why" ]; then
    echo "→ $_why — running doctor --quick (warn-only, SKIP_DOCTOR=1 to skip)"
    "$_DOCTOR" --quick "$PROJECT_ROOT" 2>&1 | grep -E '^\s+(WARN|FAIL)|^\s+Ready|^\s+NOT ready' | sed 's/^/    /' || true
  fi
fi

# ── Pre-flight baseline ──────────────────────────────────────────────────────
# Capture the CURRENT error set before touching anything, so the gate can tell
# "this script broke it" from "it was already broken". Costs one extra mxbuild;
# skip with SKIP_BASELINE=1 when you know the tree is clean.
#
# The extra mxbuild is also skipped when the verification stamp (bin/model-stamp.sh)
# says THIS exact model state already passed mxbuild with 0 errors: the baseline is
# then known to be empty without measuring it. Any change since (Studio Pro, a test
# run, a bare exec) changes the fingerprint and the baseline runs as before.
# WHY (field run 2026-10-07, requirements-driven build): exec.sh was 22% of all tool
# time, with two mxbuilds per exec; the baseline one re-measured a model the previous
# exec had just verified, in most of 100 execs.
BASELINE_SET=""
BASE_KNOWN=0
if [ "${SKIP_BASELINE:-0}" != "1" ] && [ -x ./bin/model-stamp.sh ] \
   && ./bin/model-stamp.sh check -q --clean >/dev/null 2>&1; then
  echo "→ Pre-flight: model unchanged since its last clean mxbuild (verification stamp) — baseline 0, not re-measured"
  _BC=0; _BCODES=""; BASE_KNOWN=1
  SKIP_BASELINE=1
fi
if [ "${SKIP_BASELINE:-0}" != "1" ] && [ -x "$MXBUILD" ] && [ -x "$JAVA_EXE" ]; then
  echo "→ Pre-flight: checking whether the model already has errors..."
  _BF=$(mktemp /tmp/mxbuild-baseline.XXXXXX)
  # Run+capture is mxtk_mxbuild_error_count (_common.sh) — the same sequence
  # used below by the main gate and the restore-rebuild check, so this and
  # bin/doctor.sh's gate self-test trust identical code, not three copies that
  # can drift apart. Its own printed count is discarded here: this call site
  # already has err_set/err_count/err_codes on hand and needs BASELINE_SET
  # (the message set, not just a count) for the delta-gate comparison below.
  mxtk_mxbuild_error_count "$MPR" "${MXTK_GATE_TIMEOUT:-0}" "$_BF" >/dev/null || true
  # Studio Pro 11's mxbuild (its --help says so) writes --write-errors "only if the
  # project has errors": on a clean model the mktemp'd file stays EMPTY, json.load
  # fails, and this read "Model ALREADY has ? error(s) [?]" on every clean run
  # (2026-09-14, 11.12.4). The gate below already treats empty-file + exit 0 as
  # clean; the baseline does the same rather than reporting "?" as a warning.
  if [ ! -s "$_BF" ] && [ "$MXTK_MXBUILD_EXIT" -eq 0 ]; then
    BASELINE_SET=""; _BC=0; _BCODES=""
  else
    BASELINE_SET=$(err_set "$_BF")
    _BC=$(err_count "$_BF"); _BCODES=$(err_codes "$_BF")
    # Non-zero exit, 0 Error problems: mxbuild refused the model without checking it
    # (version mismatch, JDK) — the baseline was NOT measured. It used to print
    # "baseline clean" here (field project 2026-09-26, run A2: mxbuild 11.14.0, model 11.12.2).
    [ "$_BC" = "0" ] && [ "$MXTK_MXBUILD_EXIT" -ne 0 ] && _BC="?"
  fi
  rm -f "$_BF"
  case "$_BC" in ''|*[!0-9]*) ;; *) BASE_KNOWN=1 ;; esac
  if [ "$_BC" = "?" ]; then
    echo "  ⚠  Baseline NOT measured: mxbuild exited $MXTK_MXBUILD_EXIT without checking the model."
    [ -n "${MXTK_MXBUILD_WHY:-}" ] && echo "     mxbuild says: $MXTK_MXBUILD_WHY"
  elif [ "$_BC" != "0" ]; then
    echo "  ⚠  Model ALREADY has $_BC error(s) [$_BCODES] before this script runs."
    echo "     Not yours. The gate will keep your changes if you add nothing new."
  else
    echo "  ✓ baseline clean"
  fi
fi

# ── Execute ──────────────────────────────────────────────────────────────────
# The exit status is CAPTURED, not allowed to trip `set -e`.
#
# This is the fix for a defect that fired three times before anyone traced it:
# with a bare `./mxcli exec`, a mid-script failure aborted exec.sh instantly —
# skipping the mxbuild gate, the restore, and the build-log entry. And mxcli is
# NOT transactional across statements, so every statement before the failing one
# was already applied. The result was live, ungated, unlogged model changes,
# arrived at by the guard chain exiting through the one path with no guards on
# it. A failed exec is precisely when the gate matters most.
echo "→ Executing $SCRIPT..."
EXEC_STATUS=0
if [ "$PATCH_MODE" = "1" ]; then
  export MXTK_MPR="$MPR" MXTK_MODEL_DIR="$MODEL_DIR"
  case "$SCRIPT" in
    *.py) if [ -n "$PY" ]; then "$PY" "$SCRIPT" "$MPR" "$@" || EXEC_STATUS=$?
          else echo "  ✗ no working Python 3 to run a .py patch"; EXEC_STATUS=127; fi ;;
    *.sh) bash "$SCRIPT" "$MPR" "$@" || EXEC_STATUS=$? ;;
    *)    "$SCRIPT" "$MPR" "$@" || EXEC_STATUS=$? ;;
  esac
  if [ "$EXEC_STATUS" -ne 0 ]; then
    # An opaque script that failed half-way is not worth an mxbuild: roll it back now.
    echo ""
    echo "  ✗ patch script exited $EXEC_STATUS — restoring the snapshot (a half-run patch is never kept)."
    restore_snapshot
    if [ -x ./bin/model-stamp.sh ]; then ./bin/model-stamp.sh clear >/dev/null 2>&1 || true; fi
    if [ "$RESTORED" -eq 1 ]; then
      log_build "❌ patch failed" "script exit $EXEC_STATUS — rolled back, gate not run"
    else
      log_build "❌ patch failed" "script exit $EXEC_STATUS — NOT rolled back (restore did not run)"
    fi
    exit "$EXEC_STATUS"
  fi
else
  "${PMXCLI:-./mxcli}" exec "$SCRIPT" -p "$MPR" || EXEC_STATUS=$?
fi

if [ "$EXEC_STATUS" -ne 0 ]; then
  echo ""
  echo "  ✗ mxcli exec exited $EXEC_STATUS — PARTIAL APPLICATION LIKELY."
  echo "    mxcli is not transactional across statements: everything before the"
  echo "    failing statement is already in the model. Running the gate anyway."
fi

echo ""
echo "→ Running mxbuild model check (catches BSON corruption before SP opens)..."
echo "  (mxbuild: $MXBUILD)"

# Three states, not two. "did not fail" is not "passed": the gate can be
# skipped entirely (no mxbuild) or produce an unparseable result, and reporting
# either as clean is the same false-green this script exists to prevent.
# GATE_STATE is declared alongside log_build above so the gate column can never
# be blank, even on a path that never reaches this block.

if [ -x "$MXBUILD" ] && [ -x "$JAVA_EXE" ]; then
  ERRORS_FILE=$(mktemp /tmp/mxbuild-errors.XXXXXX)
  # Run+capture is mxtk_mxbuild_error_count (_common.sh): status captured
  # directly (never reset to 0 by a stray `|| true`), output through a file
  # never `$(...)` (Studio Pro 11's mxbuild.exe on Windows starts a helper
  # deno.exe that inherits stdout and never closes it — a command substitution
  # then waits forever for EOF that never comes), stdin closed. Unbounded by
  # default (MXTK_GATE_TIMEOUT=0, i.e. no timeout) so a real build is never
  # cut short — set MXTK_GATE_TIMEOUT to bound a truly stuck mxbuild instead.
  # Same function as the baseline above and the restore-rebuild check below —
  # one implementation, not three that can quietly drift apart — and the one
  # bin/doctor.sh's gate self-test also calls, so doctor proves the SAME code
  # the real gate trusts, not a second copy. Its own printed count is
  # discarded here: this call site keeps its own file-presence/exit-code
  # branching below unchanged, computing CE_COUNT via err_count once it knows
  # which branch applies.
  mxtk_mxbuild_error_count "$MPR" "${MXTK_GATE_TIMEOUT:-0}" "$ERRORS_FILE" >/dev/null || true
  MXBUILD_EXIT="$MXTK_MXBUILD_EXIT"
  MXBUILD_OUT="$MXTK_MXBUILD_OUT"
  MXB_WHY="${MXTK_MXBUILD_WHY:-}"

  if [ -f "$ERRORS_FILE" ] && [ -s "$ERRORS_FILE" ]; then
    CE_COUNT=$(err_count "$ERRORS_FILE")
    if [ "$CE_COUNT" = "?" ]; then
      GATE_STATE="unverified"
      echo "  ⚠  mxbuild errors file could not be parsed — check manually."
      echo "$MXBUILD_OUT" | grep -v "^$\|icon\|Microsoft\|Assembly\|__" | head -10 || true
    elif [ "$CE_COUNT" = "0" ] && [ "$MXBUILD_EXIT" -ne 0 ]; then
      # Non-empty errors file, 0 Error problems, NON-ZERO exit: mxbuild never checked the
      # model. The reason sits in errors[], which err_count does not read, e.g. (verbatim,
      # field project 2026-09-26, exit 3): "Project version '11.12.2' does not exactly
      # match MxBuild version '11.14.0'". The same shape comes from a JDK the deploy build's
      # gradle cannot run under. This branch used to fall through to the one below and log
      # "pass · mxbuild clean" — 29 of 29 execs on one machine, one of them shipping a
      # CE0066. An exit code and a problem count are two facts; 0 problems from a tool that
      # exited non-zero means NOT MEASURED.
      GATE_STATE="unverified"
      echo "  ✗ mxbuild exited $MXBUILD_EXIT and listed 0 model problems — it did NOT check the model."
      echo "    ${MXB_WHY:-no reason in errors[]; mxbuild output follows}"
      [ -z "$MXB_WHY" ] && { echo "$MXBUILD_OUT" | grep -v "^$\|icon\|Microsoft\|Assembly\|__" | tail -10 || true; }
      echo "    A version mismatch is fixed by the matching mxbuild: ./mxcli setup mxbuild -p $MPR_BASE"
      echo "    (find_mxbuild prefers it once cached), or MXBUILD_PATH=<that mxbuild>."
    elif [ "$CE_COUNT" = "0" ]; then
      # mxbuild ALWAYS writes an errors file, even on success ({"problems":[]}).
      # A guard that tested only "file is non-empty" therefore took the restore
      # branch on a clean build and rolled back good work, while printing
      # "0 error(s) found". Test the parsed count, never the file's existence.
      GATE_STATE="pass"; GATE_ERRORS=0
      echo "  ✓ mxbuild: 0 errors — model is clean."
      [ "$EXEC_STATUS" -eq 0 ] && log_applied "mxbuild clean"
    else
      # ── Delta gate ─────────────────────────────────────────────────────────
      # A shared model means another workstream can leave it non-building; an
      # absolute "zero errors" gate would then block every good script forever.
      # Keeps the write when the POST-exec error set is the baseline exactly
      # (nothing changed), OR a STRICT SUBSET of it (every post-exec error
      # already existed pre-exec — nothing new, even though some pre-existing
      # ones may have been cleared). An error is code + message + location,
      # counted (see err_set), so a second copy of a baseline error is new.
      # Only a set with something NEW in it restores the snapshot.
      # Real incident: a script that took 34
      # pre-existing errors down to 1 was rolled back and logged
      # "blocked: PRE-EXISTING CE1613" because the gate could only recognise
      # "unchanged," never "reduced."
      POST_SET=$(err_set "$ERRORS_FILE")
      DELTA_KIND=""
      if [ -n "$BASELINE_SET" ] && [ "$BASELINE_SET" = "$POST_SET" ]; then
        DELTA_KIND="identical"
      elif [ -n "$BASELINE_SET" ] && is_subset_of "$POST_SET" "$BASELINE_SET"; then
        DELTA_KIND="subset"
      fi
      if [ -n "$DELTA_KIND" ]; then
        GATE_STATE="pass"; GATE_ERRORS="$CE_COUNT"
        KEEP_CODES=$(err_codes "$ERRORS_FILE")
        if [ "$DELTA_KIND" = "subset" ]; then
          echo "  ⚠  mxbuild: $CE_COUNT error(s) — a STRICT SUBSET of the $_BC pre-flight baseline error(s), no new ones."
          echo "     Pre-existing [$KEEP_CODES] remain; this script reduced the error count. KEEPING the changes."
          echo "     The model still will not deploy until those are cleared in Studio Pro."
          [ "$EXEC_STATUS" -eq 0 ] && log_build "⚠️ applied (dirty model, reduced)" "errors ${_BC}→${CE_COUNT} (pre-existing, reduced); remaining [$KEEP_CODES] still blocks deploy"
        else
          echo "  ⚠  mxbuild: $CE_COUNT error(s) — IDENTICAL to the pre-flight baseline."
          echo "     Pre-existing [$KEEP_CODES], not introduced by this script. KEEPING the changes."
          echo "     The model still will not deploy until those are cleared in Studio Pro."
          [ "$EXEC_STATUS" -eq 0 ] && log_build "⚠️ applied (dirty model)" "no new errors; pre-existing $KEEP_CODES still blocks deploy"
        fi
        cp "$ERRORS_FILE" "$LAST_ERRS"
        rm -f "$ERRORS_FILE"
      else
        GATE_STATE="fail"
        CE_CODES=$(err_codes "$ERRORS_FILE")
        read -r NEW_COUNT NEW_CODES <<EOF
$(err_report count "$ERRORS_FILE")
EOF
        case "$NEW_COUNT" in
          ''|*[!0-9]*)
            NEW_COUNT="?"
            echo "  ✗ mxbuild: $CE_COUNT error(s) found — restoring snapshot to avoid loading a corrupt MPR." ;;
          *)
            _OLD=$(( CE_COUNT - NEW_COUNT ))
            if [ "$_OLD" -gt 0 ]; then
              echo "  ✗ mxbuild: this script added $NEW_COUNT new error(s) [$NEW_CODES] ($CE_COUNT in total, $_OLD were already there) — undoing it."
            else
              echo "  ✗ mxbuild: this script added $NEW_COUNT new error(s) [$NEW_CODES] — undoing it."
            fi ;;
        esac
        # restore_snapshot (above) is the one restore implementation, through restore-mpr.sh.
        # Without it the attribution check below rebuilt the SAME broken model and blamed the
        # error on "PRE-EXISTING" (v1 model, 2026-09-26). RESTORED gates that check.
        restore_snapshot
        # Print WHERE, not just WHAT: mxbuild's problems[] carries module/document/element and,
        # for CE0117, the expression parser's own message under metadata.expressionErrors. The
        # old one-liner printed "CE0117 Error(s) in expression." and nothing else, so the reader
        # had to re-run mxbuild by hand on a scratch copy to learn which activity (greenfield
        # pilot, 2026-09-04: an unqualified enum value in a CHANGE, found only that way).
        # With a measured baseline, the NEW errors come first and the rest are summarised.
        err_report print "$ERRORS_FILE" || true
        cp "$ERRORS_FILE" "$LAST_ERRS"
        echo "  → Full error detail: .mpr-snapshots/last-mxbuild-errors.json"

        if [ "$RESTORED" -ne 1 ]; then
          # Nothing was rolled back, so rebuilding now would measure the script's own
          # output and call its error PRE-EXISTING. Say what happened instead.
          echo ""
          echo "  ✗ The model still holds this script's changes and fails with [$CE_CODES]."
          log_build "❌ gate failed" "$CE_COUNT error(s): $CE_CODES — NOT rolled back (restore did not run)"
        else
          # ── Whose error is it? ───────────────────────────────────────────────
          # The model is now back at its pre-exec state. If it STILL fails, the
          # error predates this script, which was merely the first thing to hit
          # it. Costs one extra mxbuild, only on the failure path.
          BASE_ERRS=$(mktemp /tmp/mxbuild-base.XXXXXX)
          # Same shared run+capture as the pre-flight baseline and the main gate
          # above (mxtk_mxbuild_error_count, _common.sh) — one implementation.
          mxtk_mxbuild_error_count "$MPR" "${MXTK_GATE_TIMEOUT:-0}" "$BASE_ERRS" >/dev/null || true
          # Same empty-file rule as the pre-flight baseline: SP 11 mxbuild writes no
          # errors file on a clean build, and that plus exit 0 is a verified 0.
          if [ ! -s "$BASE_ERRS" ] && [ "$MXTK_MXBUILD_EXIT" -eq 0 ]; then
            BASE_COUNT=0; BASE_CODES=""
          else
            BASE_COUNT=$(err_count "$BASE_ERRS"); BASE_CODES=$(err_codes "$BASE_ERRS")
          fi
          rm -f "$BASE_ERRS"

          echo ""
          if [ "$NEW_COUNT" != "?" ] && [ "$BASE_COUNT" != "0" ] && [ "$BASE_COUNT" != "?" ]; then
            # The baseline was measured and this script added errors on top of it. The old
            # branch below said "NOT the cause. Nothing will exec until that is cleared" here,
            # which was false twice over: the script added the error, and the delta gate keeps
            # any later script that adds nothing new (field run, 2026-09-29).
            echo "  → Undone: this script added $NEW_COUNT new error(s) [$NEW_CODES]. Fix those and re-run."
            echo "     The model is back to its $BASE_COUNT earlier error(s) [$BASE_CODES]. Those did not cause this; a script"
            echo "     that adds nothing new is kept even while they remain."
            log_build "❌ gate failed" "$NEW_COUNT new error(s): $NEW_CODES — script rolled back; $BASE_COUNT pre-existing remain"
          elif [ "$BASE_COUNT" != "0" ] && [ "$BASE_COUNT" != "?" ]; then
            echo "  ⚠  PRE-EXISTING: the restored model already fails with $BASE_COUNT error(s) [$BASE_CODES]."
            echo "     This script is NOT the cause. Nothing will exec until that is cleared."
            case "$BASE_CODES" in
              *CE0066*|*CE0463*)
                echo "     Those codes are Studio-Pro-only fixes:"
                echo "       CE0066  security overview → update entity access"
                echo "       CE0463  right-click a widget → Update all widgets" ;;
            esac
            log_build "🚫 blocked" "PRE-EXISTING $BASE_CODES — not caused by this script; needs Studio Pro"
          elif [ "$BASE_COUNT" = "?" ]; then
            echo "  → The restored model could not be measured, so whose error it is stays open: [$CE_CODES]."
            log_build "❌ gate failed" "$CE_COUNT error(s): $CE_CODES — script rolled back; restored model not measured"
          else
            echo "  → The restored model builds clean, so this script introduced [$CE_CODES]."
            log_build "❌ gate failed" "$CE_COUNT error(s): $CE_CODES — script rolled back"
          fi
        fi
        rm -f "$ERRORS_FILE"
      fi
    fi
  elif [ "$MXBUILD_EXIT" -ne 0 ]; then
    GATE_STATE="fail"
    echo "  ✗ mxbuild failed to run (exit $MXBUILD_EXIT) — gate could not verify the model."
    [ -n "$MXB_WHY" ] && echo "    mxbuild says: $MXB_WHY"
    echo "$MXBUILD_OUT" | grep -v "^$\|icon\|Microsoft\|Assembly\|__" | head -20 || true
    echo "  → Snapshot preserved. Open in SP to verify manually before proceeding."
    # --patch logs its own row below, after rolling back; one row per run.
    [ "$PATCH_MODE" = "1" ] || log_build "❌ gate could not run" "mxbuild exit $MXBUILD_EXIT"
  else
    GATE_STATE="pass"; GATE_ERRORS=0
    echo "  ✓ mxbuild: 0 errors — model is clean."
    # No errors file, or an empty one. The comment at the CE_COUNT=0 branch says
    # mxbuild ALWAYS writes one; on Mendix 11.13 it does not, so THIS is where
    # the ordinary clean build lands. It was the only outcome with no log_build
    # call: PROJECT-A hit 7 consecutive clean execs that produced 0 log rows
    # (2026-08-06) and patched it locally before the template caught up.
    [ "$EXEC_STATUS" -eq 0 ] && log_applied "mxbuild clean (no errors file written)"
  fi
  rm -f "$ERRORS_FILE"
else
  GATE_STATE="skipped"
  echo "  ✗ mxbuild or java not found — GATE SKIPPED. Paths checked:"
  echo "    MXBUILD=$MXBUILD (exists+exec: $([ -x "$MXBUILD" ] && echo YES || echo NO))"
  echo "    JAVA_EXE=$JAVA_EXE (exists+exec: $([ -x "$JAVA_EXE" ] && echo YES || echo NO))"
  echo "  → Override with MXBUILD_PATH=/path/to/mxbuild, or MENDIX_APP=/Applications/....app"
  echo "  → Verify manually in SP before proceeding."
fi

# ── --patch: keep only a verified write ──────────────────────────────────────
# A failed gate has already restored above (RESTORE_TRIED=1). What is left is a gate that could
# not run or could not verify — which an MDL run keeps, flagged, and a patch does not.
if [ "$PATCH_MODE" = "1" ] && [ "$GATE_STATE" != "pass" ] && [ "$RESTORE_TRIED" -eq 0 ]; then
  echo ""
  echo "  ✗ --patch: gate $GATE_STATE — nothing verified the patch, so it is rolled back."
  restore_snapshot
  if [ -x ./bin/model-stamp.sh ]; then ./bin/model-stamp.sh clear >/dev/null 2>&1 || true; fi
  if [ "$RESTORED" -eq 1 ]; then
    log_build "↩ patch rolled back" "gate $GATE_STATE${MXB_WHY:+ (mxbuild: $MXB_WHY)} — an unverified patch is not kept"
  else
    log_build "❌ patch unverified" "gate $GATE_STATE — NOT rolled back (restore did not run)"
  fi
  exit 1
fi

# ── v1 leak guard ────────────────────────────────────────────────────────────
# `mxcli exec` repacks v2 (small .mpr + mprcontents/ across thousands of
# .mxunit files) into v1 (one large SQLite blob). A FAILED gate restores v2; a
# SUCCESSFUL one never did, so every clean exec silently left the repo in v1:
#   * `git add mprcontents/` fails — the directory is gone
#   * `git add -A` commits a ~100 MB blob and deletes thousands of tracked files
#   * Studio Pro refuses to open, throwing InvalidOperationException at
#     LibGit2RepositoryProvider.WriteBaseFile, because git HEAD describes files
#     that no longer exist on disk
# mxbuild validates the model, not the on-disk format, so the gate passes and
# nothing looks wrong until git or SP is touched.
if [ ! -d "$MODEL_DIR/mprcontents" ]; then
  MPR_BYTES=$(wc -c < "$MPR" | tr -d ' ')
  echo ""
  echo "  ⚠️  PROJECT IS IN v1 SINGLE-FILE FORMAT — DO NOT COMMIT AS-IS."
  echo ""
  echo "     mprcontents/ is absent and $MPR_BASE is $(( MPR_BYTES / 1048576 )) MB."
  echo "     mxcli exec repacked v2 -> v1. Expected after a successful exec;"
  echo "     it is not corruption and no work has been lost."
  echo ""
  if git -C "$PROJECT_ROOT" ls-tree -r HEAD --name-only 2>/dev/null | grep -q '\.mxunit$'; then
    echo "     git HEAD still describes the v2 tree, so disk and git disagree."
    echo "     Studio Pro WILL crash on open in this state (WriteBaseFile null ref)."
    echo ""
    echo "     Pick one:"
    echo "       • Open in Studio Pro and save — SP writes v2 natively. Best option;"
    echo "         first make git agree with disk, or SP cannot open at all."
    echo "       • Discard this exec:  git checkout HEAD -- $MPR_BASE mprcontents/"
  else
    echo "     git HEAD is also v1, so git and disk agree — SP will open."
    echo "     Save in SP to get back to v2 before the next commit."
  fi
  echo ""
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
# A non-zero exec is never reported as success, even when the gate is clean:
# the model then holds a PARTIAL script, which builds fine and is still wrong.
if [ "$EXEC_STATUS" -ne 0 ]; then
  echo ""
  echo "✗ mxcli exec FAILED (exit $EXEC_STATUS) — $NAME holds a PARTIAL application."
  case "$GATE_STATE" in
    pass)
      echo "  The gate passed, so what landed is structurally valid — but it is only"
      echo "  the statements up to the failure. Review the model before continuing."
      log_build "⚠️ PARTIAL" "mxcli exec exit $EXEC_STATUS; gate passed; statements before the failure are live"
      ;;
    fail)
      echo "  The gate also failed; see above for whether it was restored."
      ;;
    *)
      # Never say "clean" here. The gate did not run, so nothing has looked at
      # what landed — and a partial application is exactly when you need it to.
      echo "  AND THE GATE DID NOT RUN ($GATE_STATE) — nothing has verified what landed."
      echo "  Do not treat this as applied. Install mxbuild or set MXBUILD_PATH, then"
      echo "  re-check the model before continuing."
      log_build "⚠️ PARTIAL, UNVERIFIED" "mxcli exec exit $EXEC_STATUS; gate $GATE_STATE; model not verified"
      ;;
  esac
  # A partial application is never a verified model state, whatever the gate said.
  # Explicit `if`, not `[ -x … ] && …`: under `set -e` the AND-list's own failure — which is
  # what a model-stamp.sh that exists but exits non-zero produces — ended the script right
  # here with exit 1, throwing away $EXEC_STATUS. The exec's real exit code is the one thing
  # this branch exists to report.
  if [ -x ./bin/model-stamp.sh ]; then
    ./bin/model-stamp.sh clear >/dev/null 2>&1 || true
  fi
  exit "$EXEC_STATUS"
fi

# ── Verification stamp ───────────────────────────────────────────────────────
# bin/model-stamp.sh records "this exact model state passed the gate"; the pre-commit hook
# (bin/install-project-hooks.sh) refuses model commits without it. Written ONLY on a clean
# pass of a fully applied script; every other outcome clears it, because the model on disk
# is no longer the one anything verified.
if [ -x ./bin/model-stamp.sh ]; then
  if [ "$GATE_STATE" = "pass" ] && [ "$EXEC_STATUS" -eq 0 ]; then
    MXTK_STAMP_ERRORS="$GATE_ERRORS" ./bin/model-stamp.sh write pass "exec.sh $([ "$PATCH_MODE" = 1 ] && echo '--patch ')$(basename "$SCRIPT")" || true
  else
    ./bin/model-stamp.sh clear >/dev/null 2>&1 || true
  fi
fi

if [ "$GATE_STATE" = "fail" ]; then
  exit 1
fi

# ── LOOK owed ────────────────────────────────────────────────────────────────
# Every page this script wrote is now owed a LOOK (look-ledger.sh header: two unattended builds
# built every page and opened no screenshot of any). Written here, after the restore branch,
# because a restored script built nothing. Never blocks this exec or the next one — only
# gate-check.sh's Stage 5 "done" claim reads it. Not for --patch: a patch is opaque.
if [ "$PATCH_MODE" = 0 ] && [ -f "$(dirname "$0")/look-ledger.sh" ]; then
  bash "$(dirname "$0")/look-ledger.sh" owe "$SCRIPT" || true
fi

# ── Build plan page ──────────────────────────────────────────────────────────
# Refresh architecture/build-plan.html so it tracks the build without anyone remembering to
# (its only trigger used to be iterative-build-loop.md step 16, so a page written at Stage 4
# stayed empty for the whole build). --refresh is quiet, writes only over a page that script
# generated, and leaves the file alone when nothing but the timestamp would change.
if [ -f "$(dirname "$0")/build-plan-status.sh" ]; then
  bash "$(dirname "$0")/build-plan-status.sh" "$PROJECT_ROOT" --refresh >/dev/null 2>&1 || true
fi

# ── Watch compatibility (advisory) ───────────────────────────────────────────
# The script was applied and kept. Say whether a running `run --local --watch` can apply it or
# the app needs a restart — mxtk_watch_compat (top of file) for the statements, plus theme
# SCSS/JS edited since the running app booted (the handshake's mtime is its boot, the same
# reference test-stack-up.sh uses). Never blocks, never changes the exit code.
watch_theme_changes() {  # prints up to 3 theme files newer than the run --local handshake
  _hs=""
  for _d in "$(cd "$(dirname "$MPR")" && pwd)" "$MODEL_DIR"; do
    [ -f "$_d/.mxcli/run-local.json" ] && { _hs="$_d/.mxcli/run-local.json"; break; }
  done
  [ -n "$_hs" ] || return 0
  for _t in "$MODEL_DIR/theme" "$MODEL_DIR/themesource"; do
    [ -d "$_t" ] || continue
    find "$_t" -type d -name node_modules -prune -o -type f \( -name '*.scss' -o -name '*.js' \) \
      -newer "$_hs" -print 2>/dev/null
  done | head -3 | sed "s|^$MODEL_DIR/||"
}
print_watch_compat() {
  if [ "$PATCH_MODE" = 1 ]; then
    _wc="restart	--patch script (opaque to the classifier — assume it needs one)"
  else
    _wc="$(mxtk_watch_compat "$SCRIPT" 2>/dev/null || true)"
  fi
  _why="${_wc#*	}"
  _theme="$(watch_theme_changes 2>/dev/null | tr '\n' ' ' || true)"
  if [ -n "$_theme" ]; then
    [ "${_wc%%	*}" = restart ] && _why="$_why; " || _why=""
    _wc="restart"; _why="${_why}theme SCSS/JS changed since the app booted: ${_theme% }"
  fi
  echo ""
  case "${_wc%%	*}" in
    restart)
      echo "→ Watch: restart needed: $_why"
      echo "  run --local --watch keeps serving the OLD model for these. Restart this app only:"
      echo "  ./bin/app-restart.sh   (stale-runtime symptoms + what watch covers: toolkit skills/ui-loop.md)" ;;
    unknown)
      echo "→ Watch: unknown — restart if behaviour looks stale: $_why"
      echo "  Not on the watch-safe list (toolkit skills/ui-loop.md \"What watch picks up\"); if the app"
      echo "  still behaves as before this change: ./bin/app-restart.sh" ;;
    watch)
      if [ -n "$_why" ]; then echo "→ Watch: watch can apply this — $_why"
      else echo "→ Watch: watch can apply this"; fi ;;
  esac
}
print_watch_compat || true

if [ "$GATE_STATE" != "pass" ]; then
  echo ""
  echo "⚠️  Script applied to $MPR_BASE, but THE GATE DID NOT RUN ($GATE_STATE)."
  echo "    Nothing has verified the model, and it carries no verification stamp: the commit"
  echo "    hook will refuse it until ./bin/verify-model.sh has run the gate over it."
  log_build "⚠️ applied, UNVERIFIED" "gate $GATE_STATE${MXB_WHY:+ (mxbuild exit ${MXBUILD_EXIT:-?}: $MXB_WHY)} — model not verified"
  exit 0
fi

if [ "$LINT_RC" -eq 3 ]; then
  echo ""
  echo "✗ Script applied and mxbuild is clean, but a LINT RULE IS BLIND — this is not a pass."
  echo "  $LINT_DETAIL"
  echo "  The write is kept. Fix the rule's configuration before trusting any lint result."
  exit 1
fi
if [ "$LINT_RC" -eq 1 ]; then
  echo ""
  echo "✗ Script applied and mxbuild is clean, but LINT ROSE — this is not a pass."
  echo "  $LINT_DETAIL"
  echo "  The write is kept (lint is shape, not corruption). Fix it before calling the task done."
  exit 1
fi

echo ""
echo "✓ Script applied to $MPR_BASE."
echo ""
_EL=$(( $(date +%s) - _T0 ))
echo "  elapsed: ${_EL}s (check + snapshot + exec + mxbuild gate)"
[ -n "$CHANGE_CLASS" ] && echo "  change class: $CHANGE_CLASS — test lane: $(change_lane)"
# A budget, not a gate: a normal run is 30-90 s on a healthy machine. Past 4 minutes the
# usual cause is the machine (Defender scanning every fork, OneDrive, a slow disk), and
# doctor --quick names which — the reader should not have to guess "is it me or the toolkit".
[ "$_EL" -gt 240 ] && echo "  ⚠  slower than a healthy run — run doctor.sh --quick $PROJECT_ROOT to see why (spawn speed, path, OneDrive)"
echo "  Gate passed (mxbuild-clean). If the happy path / coverage checklist is ALSO"
echo "  verified for this script, rename it now: git mv <path> <path>/done-<name>"
echo "  (skills/iterative-build-loop.md — a clean gate is necessary, not sufficient)"
echo ""

# --- Close the loop in Studio Pro -------------------------------------------
# An mxcli write never reaches a RUNNING Studio Pro — SP holds the model in
# memory. Printing "please restart" left the loop open and made the last step
# the user's chore, which is also how a build gets declared "done" without
# anyone ever seeing it run.
#
#   SP_RESTART=1  reopen Studio Pro after applying (opt in per run)
#   unset / 0     never touch SP, just print the hint  ← DEFAULT
#
# This used to prompt "[Y/n]" when it had a TTY, defaulting to YES. Reopening
# Studio Pro force-quits it, which DISCARDS whatever the user had unsaved — so
# the most destructive option was the one you got by pressing Enter, on a
# prompt that appears after a script has already succeeded and attention has
# moved on. That also contradicted the SP Lifecycle Rule stated twice in
# iterative-build-loop.md. Closing the loop is not worth owning the user's
# unsaved work: make reopening explicit, and never infer consent from Enter.
#
# restart-sp.sh targets only the SP holding THIS project's .mpr (via lsof), so
# a second project open in another window is unaffected.
RESTART_SP="${SP_RESTART:-0}"

if [ "$RESTART_SP" = "1" ] && [ -x "$(dirname "$0")/restart-sp.sh" ]; then
  echo "→ Reopening Studio Pro..."
  # AUTO_SP=1: reaching here now requires an explicit SP_RESTART=1, so consent
  # was given deliberately rather than inferred from a keypress, and a second
  # confirm would only be unanswerable from a non-interactive caller.
  if AUTO_SP=1 "$(dirname "$0")/restart-sp.sh"; then
    echo ""
    echo "  ▶ Studio Pro is reopening with your changes. Click Run Locally when it finishes loading."
  else
    echo ""
    echo "  ⚠️  Reopen failed — restart Studio Pro by hand before continuing."
  fi
else
  echo "  ⚠️  Studio Pro needs a restart to pick up these changes."
  echo "      Close $NAME in Studio Pro, reopen it, then click Run Locally."
  echo "      Or: ./bin/restart-sp.sh   (or re-run with SP_RESTART=1)"
fi
echo ""
