#!/bin/bash
# gate.sh: the gate driver of steps/gate.md (N1-13). One script runs the rungs in order through the toolkit's own
# instruments, records every rung's rc and a one-line verdict, and writes gate-summary.md. Before N1-13 every worker
# hand-wrote a gate.sh; the copies drifted: the journeys lines pointed to a folder that did not exist, and an rc=2
# scrolled by unreported.
#
#   gate.sh [--config FILE] [KEY=VALUE ...] [--dry-run] [--only RUNG,RUNG [--seed-from GATE_DIR]] [--skip RUNG=reason]
#
# Config: a file of KEY=VALUE lines (# comments; no quotes needed; relative paths are relative to the config file)
# and/or KEY=VALUE arguments (relative to the current folder; arguments win). An unknown key is an error (a typo
# must not silently switch a rung off). Keys, grouped by rung:
#   WORK LABEL            work folder ($W) and rung label; evidence goes to $WORK/gate$LABEL/ (GATE_DIR=... overrides)
#   build      BUILD_LOG                              the mx check / mxbuild output of step 4 (needs BUILD SUCCEEDED)
#   idcheck    OLD_MDA NEW_MDA [APPROVED]
#   const      OLD_MDA NEW_MDA [CONST_OVERRIDES CONST_ALLOW]
#   data       BEFORE_JSON AFTER_JSON [ALLOW LOG_ALLOW]
#   rest       REST_BEFORE REST_AFTER                  folders of saved documents (restcontract.py); optional rung
#   logdiff    OLD_LOG NEW_LOG [LOG_ALLOW]   OLD_LOG = the OLD app's start log of the baseline: runapp.py saves every
#              start also as logs/runtime-<name>.<db>.log, so OLD_LOG=logs/runtime-old.<baseline db>.log needs no hand
#              copy (B4N1-16: the numbered runtime-old-<n>.log moved with every later save of that name)
#   smoke      SMOKE_URL SMOKE_BEFORE SMOKE_PLAN|SMOKE_APP_DIR  SMOKE_USER=Role=user:pass (repeat) [SMOKE_REPEAT=N] [SMOKE_LOGIN_PATH=/login-without-sso.html]
#              SMOKE_REPEAT: smokewalk --repeat N, every role walked N times; a step not PASS in every walk is listed (T6R-9)
#              (T7R-12, T8R-8); walk SMOKE_BEFORE with the same N
#   journeys   JOURNEYS_DIR JOURNEYS_BEFORE USERS PORT ADMIN_PORT ADMIN_PASS [PAUSE JOURNEY_SHOT_ACCEPT JOURNEYS_REJUDGE=1]
#              [JOURNEY_PSQL JOURNEY_EFFECT_ACCEPT]   JOURNEY_PSQL = the new app's psql command, run_journeys --psql
#              (E2E-9: the data rung and the effect record; unset, they are INVALID); a PGPASSWORD= in it is masked
#              [ACTIONS | ACTIONS_WAIVE JOURNEY_EVIDENCE]   E2E-11: ACTIONS = the OLD model's actions.json (action_inventory.py),
#              run_journeys --actions, the coverage denominator; without it and without ACTIONS_WAIVE=<reason> the rung is
#              INVALID (coverage unknown), with the waiver at best PASS*; JOURNEY_EVIDENCE = --baseline-evidence
#              [JOURNEY_BAR=processes]   B5-3, run_journeys --bar: PASS = the confirmed key-user processes pass, 0
#              REGRESSION / FAIL / REVIEW anywhere; coverage and other INVALID journeys are reported, not blocking
#              SMOKE_REJUDGE=1 (L55): judge the stored $GATE_DIR/smoke-after.json against SMOKE_BEFORE again, no browser (smokewalk.js
#              --rejudge); needs only SMOKE_BEFORE. With --only the pipeline's diff step still carries the afterwalk's smoke verdict.
#   Report-only keys (no rung): GATE_NOTES=<file> (L56: every non-empty non-# line is listed as "needs a decision" and counted in Progress;
#              it never changes a verdict), HEAL_JSON=<work>/heal.json (the heal step's "heal:" summary line).
#   screens    SMOKE_BEFORE_SHOTS [SMOKE_SHOT_ACCEPT]  compares against $GATE_DIR/smoke-after-shots (the smoke rung's)
#   layout     LAYOUT_OLD LAYOUT_NEW [LAYOUT_ACCEPT]   layoutdiff.py on the folders layoutwalk.js wrote for the old and the new app
#              (widget widths, cut text and image sizes per page; data independent). Optional rung: without LAYOUT_OLD / LAYOUT_NEW it
#              says NOT RUN and is never a PASS. A page FAIL or MISSING (saved on the old app, absent on the new) = rung FAIL; a page
#              that could not be judged = INVALID. Why: a squeezed gallery has every card and value, so journeys and the smoke shots pass it.
#   release    RELEASE_IMPACT
#   apis       APIMOCK=<state dir>|off [EXCLUDE_SYSTEMS=Teamcenter,...]   optional rung (E2E-13, E2E-14): the state folder
#              of `apimock.py serve` (the local stand-in for every external API; start it, and the apps with its
#              overrides.json as CONST_OVERRIDES, in PRE_ commands). The rung runs `apimock.py check`: every endpoint
#              MOCKED and every request answered, else INVALID. B4N1-11: the row carries `requests seen: N`; MOCKED
#              endpoints with 0 requests are INVALID (a single one only with an UNEXERCISED waiver; 0 requests in all,
#              never). B4T2-6: an add-on module is UNKNOWN until a LOCATION line points it at the stand-in (steps/gate.md
#              item 12). APIMOCK also gives the journeys rung the request log;
#              EXCLUDE_SYSTEMS (needs APIMOCK) names the systems no stand-in can replace: a journey, smoke step or
#              endpoint that fails ONLY on a call into one of them is NOT CHECKED, listed by name, never PASS.
#              E2E-15: the stand-in is a stopgap, not the standard. With APIMOCK set the driver asks `apimock.py standin`
#              which endpoints the stand-in answered for; any = the overall verdict is never plain PASS (see Exit)
#   widgets    WIDGETS_APP=<app dir|.mpr> [WIDGETS_WAIVE=<file> WIDGETS_RENDERED=<file>]   optional rung (MC-19): bin/widgetcover.py
#              lists every widgets/*.mpk that a page uses and that no smoke step ($GATE_DIR/smoke-after.json) and no journey
#              (JOURNEYS_DIR) renders; one of them is INVALID (rc 3, "not checked"), never PASS. A widget that crashes on the new
#              client passes every other rung when no walked page holds it (Asset Console 3D viewer, React error #525).
#              WIDGETS_WAIVE: lines "package or widget id # reason"; WIDGETS_RENDERED: pages a hand-written walk opens
#   trail      TRAIL_REQUIRED=1   optional rung (STEP-RECORDS-PLAN.md slice 9), on whenever <work>/steps.jsonl exists: bin/steps.py trail asks that
#              every step has a proposal, an approval (assumed counts, flagged), a change or a written gap, a test result or a written gap,
#              and that every D row names a step. While optional a miss is a NOT RUN row that starts with WARNING (verdict unchanged).
#              TRAIL_REQUIRED=1 makes a miss INVALID and a run without step records a required NOT RUN (slice 10).
#   PRE_<rung>=cmd    run before that rung (start the new app on a fresh copy of X_frozen, take the snapshot);
#                     a key it produces (AFTER_JSON, NEW_LOG, SMOKE_URL's app) is then not required up front, for that
#                     rung and every later one (N1R2-9, T2R3-10: NEW_LOG written by PRE_data was refused for logdiff
#                     unless a PRE_logdiff copied it); a key still missing when its rung starts is INVALID
#   POST_CMD=cmd      run after the last rung, always (stop the app)
#   RUN=id            the invocation id, default the UTC time (YYYYmmddHHMMSS); every "{RUN}" in any value is replaced
#                     by it, so PRE commands get a database name per invocation (opc_after_{RUN}) without a hand-made
#                     GN= variable (T2R3-10: the snapshot ledger refuses a database name used before)
# PRE_* and POST_CMD run in bash with G (= GATE_DIR), WORK, LABEL, RUN and every key above exported (N1R2-9: a PRE that
# wrote to its own $W/gate/after.json missed GATE_DIR, the data rung was INVALID); write '$G/after.json' in the value.
# CONST_OVERRIDES is also an environment variable runapp.py reads itself (B4T2-12: the exported path was read as JSON,
# PRE_data/smoke/journeys rc 1): runapp.py accepts the path, and an UNSET key does not clear a CONST_OVERRIDES the caller
# exported (it is exported only when set here). `CONST_OVERRIDES="$(cat f)" python3 runapp.py ...` keeps working.
#
# Change ledger (trust.md section 3, not a rung): APP_REPO=folder is the app's git repo (default $WORK/app when it has a .git).
# When known, bin/changelog.py writes $WORK/CHANGES.md and the summary carries `Changes: N (toolkit a, agent b, person c,
# unlabelled d)` after the Progress line; d > 0 adds a "needs a decision" item. It never changes a rung or the verdict.
#
# Rungs, in steps/gate.md order: build idcheck const data rest logdiff smoke layout journeys screens release apis widgets trail.
# layout runs BEFORE journeys (LAY-9): journeys change data (pager counts, edited or deleted rows), so a layout compare made after them
# differs from a baseline walked on fresh data. Walk the layout on the old and the new app before any journey touches the data.
# --only RUNG,... runs those rungs and MERGES into an existing gate-summary.md of the same GATE_DIR (T2R3-10, N1R2-9:
# it overwrote the file, so the final summary had to be one full invocation): the other rungs keep their earlier row,
# marked "(earlier run <time>)", and the overall verdict is computed over the merged table.
# --seed-from DIR (RT-11, with --only): a new GATE_DIR (a remedy trial's own label) has no summary to merge into, so the
# untouched rungs came out NOT RUN; this copies DIR/gate-summary.md into GATE_DIR first when GATE_DIR has none yet.
# A rung whose keys are all unset is NOT RUN ("not configured"); a rung with some keys set and others missing, or a
# path that does not exist, stops the driver BEFORE anything runs: exit 2, the key and the path named (and the
# summary lists every rung NOT RUN with that reason). "NOT RUN is legal, silence is not": every rung appears in
# gate-summary.md as PASS, PASS*, FAIL, INVALID or NOT RUN with its reason.
#
# Verdicts: an instrument's rc 0 = PASS (PASS* when its output reports accepted lines), 1 = FAIL (open FAIL or REVIEW),
# anything else (2, timeout, crash, a PRE command failing) = INVALID; release_impact rc 1 is INVALID (gate.md 10);
# run_journeys rc 3 ("INVALID only": nothing FAILed, journeys or screens INVALID, baselines that fail) is INVALID with
# the instrument's advice as the line (N1R2-8, T2R3-11: SCREEN INVALID pairs made the rung FAIL with 0 journeys failed).
# EXCEPT (E2E-14, only with EXCLUDE_SYSTEMS): the journeys rung exits 4 (its only non-PASS journeys are NOT CHECKED), the
# smoke rung's FAIL steps each called only an excluded system (apimock.py attribute-smoke exit 4), or the apis rung
# exits 4 (endpoints excluded). Every NOT CHECKED item is listed by name in gate-summary.md. rc 4 without
# EXCLUDE_SYSTEMS, or an EXCEPT rung that names no item, is INVALID.
# Exit: 0 only if every required rung is PASS or PASS* (rest, apis, widgets and, until TRAIL_REQUIRED=1, trail are the optional rungs: NOT RUN is allowed there);
#       1 on any FAIL; 2 on INVALID or NOT RUN (or an input error); 4 = "PASS (except <systems>: N items)": nothing
#       FAILs or is INVALID, but N items are NOT CHECKED because they need an excluded system (E2E-14; never plain
#       PASS, never 0), and/or "PASS (on stand-in APIs: <systems>)": APIMOCK is set and the stand-in answered for at
#       least one endpoint, so real-system behaviour was not checked (E2E-15; a conditional PASS, to be run again on
#       the vendors' test systems before go-live). Both: "PASS (on stand-in APIs: Opcenter; except Teamcenter: 3
#       items)". APIMOCK set but the stand-in's inventory unreadable = INVALID. --dry-run prints each rung's command and exits 0 when the inputs check out; it runs and
#       writes nothing.
# Env: UPG_GATE_BIN (instrument folder, default: this one; controls use stubs), UPG_PYTHON, UPG_NODE,
#      GATE_TIMEOUT (seconds per instrument, default 900; smokewalk 600 unless set). A rung that hits it is INVALID and
#      its line says "raise GATE_TIMEOUT" (RT-11: a 7-role repeat-3 smoke walk needed 1500).
set -u
here=$(cd "$(dirname "$0")" && pwd)
B=${UPG_GATE_BIN:-$here}; PY=${UPG_PYTHON:-python3}; NODE=${UPG_NODE:-node}
RUNGS="build idcheck const data rest logdiff smoke layout journeys screens release apis widgets trail"
KEYS="WORK LABEL GATE_DIR BUILD_LOG OLD_MDA NEW_MDA APPROVED CONST_OVERRIDES CONST_ALLOW BEFORE_JSON AFTER_JSON ALLOW LOG_ALLOW
 REST_BEFORE REST_AFTER OLD_LOG NEW_LOG SMOKE_URL SMOKE_BEFORE SMOKE_PLAN SMOKE_APP_DIR SMOKE_BEFORE_SHOTS SMOKE_REPEAT SMOKE_LOGIN_PATH JOURNEYS_DIR
 JOURNEYS_BEFORE JOURNEYS_REJUDGE USERS PORT ADMIN_PORT ADMIN_PASS PAUSE SMOKE_SHOT_ACCEPT JOURNEY_SHOT_ACCEPT JOURNEY_PSQL LAYOUT_OLD LAYOUT_NEW LAYOUT_ACCEPT
 JOURNEY_EFFECT_ACCEPT ACTIONS ACTIONS_WAIVE JOURNEY_EVIDENCE JOURNEY_BAR RELEASE_IMPACT POST_CMD RUN APIMOCK APIDIRECT EXCLUDE_SYSTEMS WIDGETS_APP WIDGETS_WAIVE WIDGETS_RENDERED
 APP_REPO SMOKE_REJUDGE GATE_NOTES HEAL_JSON TRAIL_REQUIRED PRE_build PRE_idcheck PRE_const PRE_data PRE_rest PRE_logdiff PRE_smoke PRE_journeys PRE_screens PRE_layout PRE_release PRE_apis PRE_widgets"
PATHKEYS="WORK GATE_DIR BUILD_LOG OLD_MDA NEW_MDA APPROVED CONST_OVERRIDES CONST_ALLOW BEFORE_JSON AFTER_JSON ALLOW LOG_ALLOW
 REST_BEFORE REST_AFTER OLD_LOG NEW_LOG SMOKE_BEFORE SMOKE_PLAN SMOKE_APP_DIR SMOKE_BEFORE_SHOTS JOURNEYS_DIR JOURNEYS_BEFORE
 USERS SMOKE_SHOT_ACCEPT JOURNEY_SHOT_ACCEPT JOURNEY_EFFECT_ACCEPT LAYOUT_OLD LAYOUT_NEW LAYOUT_ACCEPT ACTIONS JOURNEY_EVIDENCE RELEASE_IMPACT APIMOCK APIDIRECT WIDGETS_APP WIDGETS_WAIVE WIDGETS_RENDERED APP_REPO GATE_NOTES HEAL_JSON"
unset ENV_CONST_OVERRIDES; [ -z "${CONST_OVERRIDES+x}" ] || ENV_CONST_OVERRIDES=$CONST_OVERRIDES   # B4T2-12: the caller's own value, for runapp.py in PRE commands
for k in $KEYS; do eval "V_$k="; done
SMOKE_USERS=()
die() { echo "gate: $*" >&2; exit 2; }
inlist() { case " $2 " in *" $1 "*) return 0;; esac; return 1; }
KEYS1=$(echo $KEYS); PATHKEYS1=$(echo $PATHKEYS)

# setkey KEY VALUE BASEDIR  (BASEDIR empty = leave as given)
setkey() {
  local k=$1 v=$2 base=$3
  inlist "$k" "$KEYS1" || [ "$k" = SMOKE_USER ] || die "unknown key '$k' (known: $KEYS1 SMOKE_USER)"
  if [ -n "$base" ] && [ -n "$v" ] && [ "$v" != off ] && inlist "$k" "$PATHKEYS1"; then case $v in /*|'$G'|'$G'/*|'${G}'|'${G}'/*) ;; *) v=$base/$v;; esac; fi
  if [ "$k" = SMOKE_USER ]; then SMOKE_USERS+=("$v"); else eval "V_$k=\$v"; fi
}

dry=0; only=""; config=""; SKIPS=""; ARGKV=(); seed=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift;;
    --config) [ $# -ge 2 ] || die "--config needs a file"; config=$2; shift 2;;
    --only) [ $# -ge 2 ] || die "--only needs a rung list"; only=$2; shift 2;;
    --seed-from) [ $# -ge 2 ] || die "--seed-from needs a gate folder"; seed=$2; shift 2;;
    --skip) [ $# -ge 2 ] || die "--skip needs RUNG=reason"; SKIPS="$SKIPS
$2"; shift 2;;
    -h|--help) awk 'NR>1{if(!/^#/)exit; print}' "$0"; exit 0;;
    [A-Za-z_]*=*) ARGKV+=("$1"); shift;;
    *) die "unknown argument '$1' (see gate.sh --help)";;
  esac
done
if [ -n "$config" ]; then
  [ -f "$config" ] || die "config file not found: $config"
  cdir=$(cd "$(dirname "$config")" && pwd)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    case "$line" in *=*) ;; *) die "$config: not KEY=VALUE: $line";; esac
    setkey "${line%%=*}" "${line#*=}" "$cdir"
  done < "$config"
fi
for kv in ${ARGKV[@]+"${ARGKV[@]}"}; do setkey "${kv%%=*}" "${kv#*=}" "$PWD"; done
for r in $(echo "$only" | tr ',' ' '); do inlist "$r" "$RUNGS" || die "--only: unknown rung '$r' (rungs: $RUNGS)"; done
[ -n "$V_RUN" ] || V_RUN=$(date -u +%Y%m%d%H%M%S)
case $V_RUN in *[!A-Za-z0-9_]*) die "RUN=$V_RUN: letters, digits and _ only (it goes into database names)";; esac
for k in $KEYS; do eval "case \$V_$k in *'{RUN}'*) V_$k=\${V_$k//\{RUN\}/\$V_RUN};; esac"; done   # T2R3-10
SMOKE_USERS=(${SMOKE_USERS[@]+"${SMOKE_USERS[@]//\{RUN\}/$V_RUN}"})
[ -n "$V_WORK" ] || V_WORK=$PWD
[ "$V_APIMOCK" = off ] && V_APIMOCK=""   # E2E-13: APIMOCK=off is the same as unset
[ -z "$V_EXCLUDE_SYSTEMS" ] || [ -n "$V_APIMOCK" ] || die "EXCLUDE_SYSTEMS=$V_EXCLUDE_SYSTEMS needs APIMOCK (no request log, nothing can be attributed to an excluded system)"
case $V_EXCLUDE_SYSTEMS in *[!A-Za-z0-9_,.-]*) die "EXCLUDE_SYSTEMS=$V_EXCLUDE_SYSTEMS: comma list of system names (letters, digits, _ . -)";; esac
G=${V_GATE_DIR:-$V_WORK/gate$V_LABEL}
if [ -n "$seed" ]; then   # RT-11: seed a new GATE_DIR so --only has a summary to merge into
  [ -n "$only" ] || die "--seed-from needs --only (a full run writes every rung itself)"
  [ -f "$seed/gate-summary.md" ] || die "--seed-from $seed: no gate-summary.md there"
  if [ $dry = 0 ] && [ ! -f "$G/gate-summary.md" ]; then
    mkdir -p "$G" && cp "$seed/gate-summary.md" "$G/gate-summary.md" || die "--seed-from: could not copy into $G"
    echo "gate: seeded $G/gate-summary.md from $seed (the rungs outside --only keep that run's rows)" >&2
  fi
fi
# U11: a literal $G / ${G} in a config or command-line value (not a PRE_/POST_ command, which expands it itself from the
# exported G) means the gate folder: it used to be taken as a relative path under the config folder (work/$G/after.json).
for k in $KEYS; do case $k in PRE_*|POST_CMD) continue;; esac
  eval "case \$V_$k in *'\$G'*|*'\${G}'*) V_$k=\${V_$k//'\${G}'/\$G}; V_$k=\${V_$k//'\$G'/\$G};; esac"
done

get() { eval "printf '%s' \"\$V_$1\""; }
setst() { eval "ST_$1=\$2; RC_$1=\$3; LN_$1=\$4"; }

# --- per-rung inputs: TRIG (any key set = the rung is wanted), NEEDS "KEY:kind[:p]" (f file, d dir, v value, p = produced
# by PRE_<rung> when that is set), OPTS "KEY:kind" (checked when set)
spec() {
  TRIG=""; NEEDS=""; OPTS=""
  case $1 in
    build) TRIG="BUILD_LOG"; NEEDS="BUILD_LOG:f:p";;
    idcheck) TRIG="OLD_MDA NEW_MDA"; NEEDS="OLD_MDA:f NEW_MDA:f"; OPTS="APPROVED:f";;
    const) TRIG="OLD_MDA NEW_MDA"; NEEDS="OLD_MDA:f NEW_MDA:f"; OPTS="CONST_OVERRIDES:f CONST_ALLOW:f";;
    data) TRIG="BEFORE_JSON AFTER_JSON"; NEEDS="BEFORE_JSON:f AFTER_JSON:f:p"; OPTS="ALLOW:f LOG_ALLOW:f";;
    rest) TRIG="REST_BEFORE REST_AFTER"; NEEDS="REST_BEFORE:d REST_AFTER:d:p";;
    logdiff) TRIG="OLD_LOG NEW_LOG"; NEEDS="OLD_LOG:f NEW_LOG:f:p"; OPTS="LOG_ALLOW:f";;
    smoke) TRIG="SMOKE_URL SMOKE_BEFORE SMOKE_PLAN SMOKE_APP_DIR"; NEEDS="SMOKE_URL:v SMOKE_BEFORE:f"; OPTS="SMOKE_PLAN:f SMOKE_APP_DIR:d"
      # SMOKE_REJUDGE (L55): judge the stored $G/smoke-after.json against SMOKE_BEFORE again, no browser (smokewalk.js --rejudge),
      # so a gate run with --only still carries the afterwalk's smoke verdict instead of "NOT RUN, not selected"
      if [ -n "$(get SMOKE_REJUDGE)" ]; then TRIG="SMOKE_BEFORE"; NEEDS="SMOKE_BEFORE:f"; OPTS=""; fi;;
    journeys) TRIG="JOURNEYS_DIR JOURNEYS_BEFORE"; NEEDS="JOURNEYS_DIR:d JOURNEYS_BEFORE:d:p"; OPTS="JOURNEY_SHOT_ACCEPT:f JOURNEY_EFFECT_ACCEPT:f ACTIONS:f JOURNEY_EVIDENCE:f"
      if [ -z "$(get JOURNEYS_REJUDGE)" ]; then NEEDS="$NEEDS USERS:f PORT:v ADMIN_PORT:v ADMIN_PASS:v"; fi;;
    screens) TRIG="SMOKE_BEFORE_SHOTS"; NEEDS="SMOKE_BEFORE_SHOTS:d"; OPTS="SMOKE_SHOT_ACCEPT:f";;
    layout) TRIG="LAYOUT_OLD LAYOUT_NEW"; NEEDS="LAYOUT_OLD:d LAYOUT_NEW:d:p"; OPTS="LAYOUT_ACCEPT:f";;
    release) TRIG="RELEASE_IMPACT"; NEEDS="RELEASE_IMPACT:f:p";;
    apis) TRIG="APIMOCK"; NEEDS="APIMOCK:d:p";;
    widgets) TRIG="WIDGETS_APP"; NEEDS="WIDGETS_APP:v"; OPTS="WIDGETS_WAIVE:f WIDGETS_RENDERED:f";;
  esac
}
optional() { [ "$1" = rest ] || [ "$1" = apis ] || [ "$1" = widgets ] || [ "$1" = layout ] || { [ "$1" = trail ] && [ "$V_TRAIL_REQUIRED" != 1 ]; }; }
reason_for() { # a --skip reason or an --only exclusion, else empty
  local r=$1 s
  if [ -n "$only" ] && [ "$r" != trail ] && ! inlist "$r" "$(echo "$only" | tr ',' ' ')"; then echo "not selected (--only $only)"; return; fi
  s=$(printf '%s\n' "$SKIPS" | sed -n "s/^$r=//p" | head -1)
  [ -n "$s" ] && echo "skipped on request: $s"
}

# --- 1. up-front: every wanted rung's inputs exist, before anything runs
ERRS=""; PRIOR_PRE=""   # PRIOR_PRE: a PRE command of this or an earlier wanted rung may produce a :p key (N1R2-9)
for r in $RUNGS; do
  setst "$r" "NOT RUN" "-" ""
  why=$(reason_for $r); [ -z "$why" ] || { setst "$r" "NOT RUN" "-" "$why"; continue; }
  if [ $r = trail ]; then   # not run in the loop: it needs every other rung's row first (see "the trail rung" below)
    if [ -f "$V_WORK/steps.jsonl" ]; then setst trail "NOT RUN" "-" "not evaluated in a dry run"; TRAIL_ON=1; else setst trail "NOT RUN" "-" "no step records in this run (no steps.jsonl in the work folder)"; fi
    continue
  fi
  spec $r; wanted=0
  for k in $TRIG; do [ -n "$(get $k)" ] && wanted=1; done
  [ "$r" = smoke ] && [ ${#SMOKE_USERS[@]} -gt 0 ] && [ -z "$V_SMOKE_REJUDGE" ] && wanted=1
  if [ $wanted = 0 ]; then setst "$r" "NOT RUN" "-" "not configured (no $(echo $TRIG | tr ' ' '/') given)"; continue; fi
  eval "pre=\$V_PRE_$r"; [ -n "$pre" ] && PRIOR_PRE="$PRIOR_PRE PRE_$r"; pre=$PRIOR_PRE
  for n in $NEEDS $OPTS; do
    k=${n%%:*}; rest=${n#*:}; kind=${rest%%:*}; v=$(get $k); isopt=0; inlist "$n" "$OPTS" && isopt=1
    if [ -z "$v" ]; then
      [ $isopt = 1 ] && continue
      case $n in *:p) [ -n "$pre" ] && continue;; esac
      ERRS="$ERRS
rung $r: $k is not set"; continue
    fi
    case $kind in
      f) [ -f "$v" ] || { case $n in *:p) [ -n "$pre" ] && continue;; esac; ERRS="$ERRS
rung $r: $k: no such file: $v"; };;
      d) [ -d "$v" ] || { case $n in *:p) [ -n "$pre" ] && continue;; esac; ERRS="$ERRS
rung $r: $k: no such folder: $v"; };;
    esac
  done
  if [ $r = smoke ] && [ -z "$V_SMOKE_REJUDGE" ]; then
    [ ${#SMOKE_USERS[@]} -gt 0 ] || ERRS="$ERRS
rung smoke: no SMOKE_USER (Role=user:pass) given"
    [ -n "$V_SMOKE_PLAN$V_SMOKE_APP_DIR" ] || ERRS="$ERRS
rung smoke: neither SMOKE_PLAN nor SMOKE_APP_DIR is set"
    [ -n "$V_SMOKE_PLAN" ] || [ -z "$V_SMOKE_APP_DIR" ] || [ -f "$B/smokewalk_gen.py" ] || ERRS="$ERRS
rung smoke: instrument missing: $B/smokewalk_gen.py"
  fi
  case $r in
    build) ;;
    idcheck) tool=idcheck.py;; const) tool=constcheck.py;; data) tool=diff.py;; rest) tool=restcontract.py;;
    logdiff) tool=logdiff.py;; smoke) tool=smokewalk.js;; journeys) tool=run_journeys.py;; screens) tool=shotdiff.py;; layout) tool=layoutdiff.py;;
    release) tool=release_impact.py;; apis) tool=apimock.py;; widgets) tool=widgetcover.py;;
  esac
  [ $r = build ] || [ -f "$B/$tool" ] || ERRS="$ERRS
rung $r: instrument missing: $B/$tool"
  setst "$r" "WANTED" "-" ""
done
if [ -n "$ERRS" ]; then
  printf 'gate: INPUT ERROR, nothing was run:%s\n' "$ERRS" >&2
  for r in $RUNGS; do eval "s=\$ST_$r"; [ "$s" = WANTED ] && setst "$r" "NOT RUN" "-" "not run: an input check failed (see the driver's error)"; done
  SUMMARY_NOTE="Input check failed; nothing ran:$(printf '%s' "$ERRS" | sed 's/^/\n- /')"
  if [ $dry = 0 ] && [ -d "$V_WORK" ]; then mkdir -p "$G" 2>/dev/null; fi
  FAILED_INPUT=1
else FAILED_INPUT=0; SUMMARY_NOTE=""; fi

# --- command building ---------------------------------------------------------------------------------------------
# Each cmd_<rung> fills CMD (array). SHOW is the printable form with secrets masked.
mask() {
  local s=$1 u secret q
  if [ -n "$V_ADMIN_PASS" ]; then q=$(printf %q "$V_ADMIN_PASS"); s=${s//"$q"/***}; s=${s//"$V_ADMIN_PASS"/***}; fi
  for u in ${SMOKE_USERS[@]+"${SMOKE_USERS[@]}"}; do
    secret=${u#*:}; [ -n "$secret" ] || continue
    q=$(printf %q "$secret"); s=${s//"$q"/***}; s=${s//"$secret"/***}
  done
  printf '%s' "$s" | sed -E 's/(PGPASSWORD=|password=)[^ ]*/\1***/g'   # E2E-9: a JOURNEY_PSQL with its password
}
opt() { [ -n "$2" ] && CMD+=("$1" "$2"); }   # opt FLAG VALUE: only when VALUE is set
cmd_rung() {
  CMD=()
  case $1 in
    build) CMD=(bash -c 'grep -q "BUILD SUCCEEDED" "$1" || exit 1; n=$(grep -c "^ERROR at" "$1"); [ "$n" = 0 ] || { echo "$n ERROR at lines"; exit 1; }' _ "$V_BUILD_LOG");;
    idcheck) CMD=("$PY" "$B/idcheck.py" "$V_OLD_MDA" "$V_NEW_MDA"); opt --approved "$V_APPROVED"; CMD+=(--md "$G/idcheck.md");;
    const) CMD=("$PY" "$B/constcheck.py" "$V_OLD_MDA" "$V_NEW_MDA"); opt --overrides "$V_CONST_OVERRIDES"; opt --allow "$V_CONST_ALLOW"; CMD+=(--md "$G/constants.md");;
    data) CMD=("$PY" "$B/diff.py" "$V_BEFORE_JSON" "$V_AFTER_JSON"); opt --allow "$V_ALLOW"; opt --log-allow "$V_LOG_ALLOW"; CMD+=(--md "$G/diff.md");;
    rest) CMD=("$PY" "$B/restcontract.py" "$V_REST_BEFORE" "$V_REST_AFTER");;
    logdiff) CMD=("$PY" "$B/logdiff.py" "$V_OLD_LOG" "$V_NEW_LOG"); opt --allow "$V_LOG_ALLOW"; CMD+=(--md "$G/logdiff.md");;
    smoke)
      local plan=$V_SMOKE_PLAN u
      if [ -n "$V_SMOKE_REJUDGE" ]; then CMD=("$NODE" "$B/smokewalk.js" --rejudge "$G/smoke-after.json" --compare "$V_SMOKE_BEFORE"); return; fi
      CMD=("$NODE" "$B/smokewalk.js" --plan "${plan:-$G/plan.json}" --url "$V_SMOKE_URL" --microflows)
      for u in ${SMOKE_USERS[@]+"${SMOKE_USERS[@]}"}; do CMD+=(--user "$u"); done
      opt --repeat "$V_SMOKE_REPEAT"; opt --login-path "$V_SMOKE_LOGIN_PATH"   # T5
      CMD+=(--compare "$V_SMOKE_BEFORE" --out "$G/smoke-after.json" --shots "$G/smoke-after-shots");;
    journeys)
      CMD=("$PY" "$B/run_journeys.py" "$V_JOURNEYS_DIR" --label after --work "$G/e2e-after")
      if [ -z "$V_JOURNEYS_REJUDGE" ]; then CMD+=(--port "$V_PORT" --admin-port "$V_ADMIN_PORT" --admin-pass "$V_ADMIN_PASS" --users "$V_USERS"); opt --pause "$V_PAUSE"; opt --psql "$V_JOURNEY_PSQL"; else CMD+=(--rejudge); fi
      CMD+=(--compare "$V_JOURNEYS_BEFORE"); opt --shot-accept "$V_JOURNEY_SHOT_ACCEPT"; opt --effect-accept "$V_JOURNEY_EFFECT_ACCEPT"
      opt --actions "$V_ACTIONS"; opt --no-actions "$V_ACTIONS_WAIVE"; opt --baseline-evidence "$V_JOURNEY_EVIDENCE"   # E2E-11
      opt --bar "$V_JOURNEY_BAR"   # B5-3
      [ -z "$V_APIMOCK" ] || { CMD+=(--apimock-log "$V_APIMOCK/requests.jsonl"); opt --exclude-systems "$V_EXCLUDE_SYSTEMS"; };;   # E2E-14
    screens) CMD=("$PY" "$B/shotdiff.py" "$V_SMOKE_BEFORE_SHOTS" "$G/smoke-after-shots"); opt --accept "$V_SMOKE_SHOT_ACCEPT"; CMD+=(--md "$G/shotdiff-smoke.md");;
    layout) CMD=("$PY" "$B/layoutdiff.py" "$V_LAYOUT_OLD" "$V_LAYOUT_NEW"); opt --accept "$V_LAYOUT_ACCEPT"; CMD+=(--md "$G/layoutdiff.md");;
    release) CMD=("$PY" "$B/release_impact.py" --check "$V_RELEASE_IMPACT");;
    widgets) CMD=("$PY" "$B/widgetcover.py" "$V_WIDGETS_APP"); [ -f "$G/smoke-after.json" ] && CMD+=(--smoke "$G/smoke-after.json")
      [ -z "$V_JOURNEYS_DIR" ] || CMD+=(--journeys "$V_JOURNEYS_DIR"); opt --rendered "$V_WIDGETS_RENDERED"; opt --waive "$V_WIDGETS_WAIVE";;
    apis) CMD=("$PY" "$B/apimock.py" check --state "$V_APIMOCK"); opt --exclude-systems "$V_EXCLUDE_SYSTEMS"; opt --direct "$V_APIDIRECT";;
  esac
}
show_cmd() { local s; s=$(printf '%q ' "${CMD[@]}"); mask "${s% }"; }

# --- verdicts -----------------------------------------------------------------------------------------------------
PASSSTAR='(PASS\* [1-9]|[1-9][0-9]* PASS\*)'
oneline() { # the rung's own summary line(s): its counts, else the last line
  local f=$1 l
  l=$( { grep -m1 '^bar: ' "$f" 2>/dev/null; grep -E -m4 '^(verdict|layout: [0-9]+ pages|apis [0-9]+ found|requests seen: [0-9]+|direct API test: |findings|pairs|journeys|actions [0-9?]|coverage: |screens|steps|auto:|release-impact check|INVALID [0-9]+ \| FAIL|.*FAIL [0-9]+ \||constcheck|logdiff|BUILD)' "$f" 2>/dev/null; } | tr '\n' ';' | sed 's/;$//')
  [ -n "$l" ] || l=$(grep -v '^[[:space:]]*$' "$f" 2>/dev/null | tail -1)
  printf '%s' "${l:-no output}" | cut -c1-200
}
verdict_of() { # RUNG RC OUTFILE -> prints verdict word
  local r=$1 rc=$2 f=$3
  if [ "$rc" = 124 ]; then echo INVALID; return; fi
  case $rc in
    0) if grep -Eq "$PASSSTAR" "$f" 2>/dev/null; then echo 'PASS*'; else echo PASS; fi;;
    1) if [ "$r" = release ]; then echo INVALID; else echo FAIL; fi;;
    4) if [ -n "$V_EXCLUDE_SYSTEMS" ] && inlist "$r" "smoke journeys apis"; then echo EXCEPT; else echo INVALID; fi;;   # E2E-14
    *) echo INVALID;;
  esac
}

# Report words (research/design-2026-10-14/positive-verdict.md): a human layer over the machine verdict; codes and exit never change.
# human_of RUNG STATUS -> closed | regression | decision | unmeasured | standin | none.
# FAIL is a decision only when the rung's own output positively shows REVIEW > 0 and no FAIL / REGRESSION / START_FAILED /
# NEW_ERROR / GUID_CHANGED count > 0; anything unparsable is a regression (never softened). INVALID is a decision only
# for an open human item (release rows open, widgets UNRENDERED); every other INVALID / required NOT RUN is unmeasured.
# A per-item line tagged "BASELINE DEFECT" failed on the OLD app too (a defect of the journey or the old app, listed for
# the owner): it never counts as a FAIL / REGRESSION of the upgrade (run 6: 35 such lines made "0 FAIL" read as a regression).
has_pos() { # WORD FILE: WORD occurs with a count above zero ("3 WORD", "WORD 3", or a line that starts with WORD and names an item)
  { if [ "$1" = REVIEW ]; then cat "$2"; else grep -v 'BASELINE DEFECT' "$2"; fi; } 2>/dev/null | grep -Eq "(^|[^A-Za-z0-9_])(($1[ :=]+[1-9][0-9]*)|([1-9][0-9]* $1))([^A-Za-z0-9_]|\$)|^[[:space:]]*$1[[:space:]]+[^0-9[:space:]|:=]"
}
# fail_all_baseline FILE: the journeys summary counts N FAIL and every per-item FAIL line is tagged BASELINE DEFECT (it
# failed on the old app too, evidence or not): those FAILs are no regression of the upgrade but a decision for the owner
# (field run: two journeys failing the same way on old and new, without an evidence line, read as "1 regression").
fail_all_baseline() {
  awk '/^journeys: / { if (match($0, /[0-9]+ FAIL/)) n = substr($0, RSTART, RLENGTH) + 0 }
       /^[[:space:]]+FAIL[[:space:]]/ { if (/BASELINE DEFECT/) b++; else u++ }
       END { exit !(n > 0 && u == 0 && n <= b) }' "$1" 2>/dev/null
}
human_of() {
  local r=$1 s=$2 f="$G/$1.out" w fb=1
  case $s in
    PASS|'PASS*') echo closed;;
    EXCEPT) echo standin;;
    FAIL)
      fail_all_baseline "$f" && fb=0
      for w in REGRESSION FAIL START_FAILED NEW_ERROR GUID_CHANGED; do
        [ $w = FAIL ] && [ $fb = 0 ] && continue
        has_pos $w "$f" && { echo regression; return; }
      done
      if has_pos REVIEW "$f" || [ $fb = 0 ]; then echo decision; else echo regression; fi;;
    INVALID)
      if { [ $r = release ] && grep -Eq 'open: [1-9]' "$f" 2>/dev/null; } || { [ $r = widgets ] && grep -q 'UNRENDERED' "$f" 2>/dev/null; }; then echo decision; else echo unmeasured; fi;;
    'NOT RUN') if optional $r; then echo none; else echo unmeasured; fi;;
    *) echo unmeasured;;
  esac
}

# --- 2. run -------------------------------------------------------------------------------------------------------
TO=${GATE_TIMEOUT:-900}
# run_limited SECS OUTFILE: run "${CMD[@]}" with a time limit, output to OUTFILE, rc 124 on timeout. C6: macOS has no
# `timeout`; the rung used to run unlimited there and a hung rung hung the gate. GNU timeout, else gtimeout (Homebrew
# coreutils), else a bash watchdog that kills the process group; never silently unlimited.
# (GATE_NO_TIMEOUT_BIN=1 forces the watchdog: the control for it.)
run_limited() {
  local t=$1 o=$2 tb=""
  if [ -n "${GATE_NO_TIMEOUT_BIN:-}" ]; then tb=""; elif command -v timeout >/dev/null 2>&1; then tb=timeout; elif command -v gtimeout >/dev/null 2>&1; then tb=gtimeout; fi
  if [ -n "$tb" ]; then "$tb" "$t" "${CMD[@]}" > "$o" 2>&1; return $?; fi
  local pid wd rc
  # PV-12: once per gate run, not once per rung (run_limited runs in the gate's own shell, so the flag persists)
  if [ -z "${WD_WARNED:-}" ]; then
    echo "gate: WARN no timeout or gtimeout on PATH (macOS: brew install coreutils); using a bash watchdog for every rung, limit ${t}s" >&2
    WD_WARNED=1
  fi
  if command -v setsid >/dev/null 2>&1; then setsid "${CMD[@]}" > "$o" 2>&1 & else "${CMD[@]}" > "$o" 2>&1 & fi
  pid=$!
  ( sleep "$t"; : > "$o.timedout"; kill -TERM -- "-$pid" "$pid" 2>/dev/null; sleep 2; kill -KILL -- "-$pid" "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid"; rc=$?
  if [ -e "$o.timedout" ]; then rm -f "$o.timedout"; rc=124; else kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null; fi
  return $rc
}
hookenv() { # export G, WORK, LABEL, RUN and every key for a PRE_* / POST_CMD shell (N1R2-9); call it in a subshell
  local k; export G GATE_DIR="$G" WORK="$V_WORK" LABEL="$V_LABEL" RUN="$V_RUN"
  for k in $KEYS; do case $k in PRE_*|POST_CMD|GATE_DIR|WORK|LABEL|RUN) ;; *) eval "export $k=\"\$V_$k\"";; esac; done
  [ -n "$V_CONST_OVERRIDES" ] || { [ -n "${ENV_CONST_OVERRIDES+x}" ] && export CONST_OVERRIDES="$ENV_CONST_OVERRIDES" || unset CONST_OVERRIDES; }   # B4T2-12
}
run_pre() { # RUNG ; returns 0 when absent or ok
  eval "local pre=\$V_PRE_$1"; [ -n "$pre" ] || return 0
  if [ $dry = 1 ]; then echo "[$1] PRE: $(mask "$pre")"; return 0; fi
  echo "[$1] PRE: $(mask "$pre")"
  ( hookenv; bash -c "$pre" ) > "$G/$1.pre.out" 2>&1; local rc=$?
  [ $rc = 0 ] || { echo "[$1] PRE command failed rc=$rc (see $G/$1.pre.out)"; return $rc; }
}
[ $FAILED_INPUT = 0 ] && for r in $RUNGS; do
  eval "s=\$ST_$r"; [ "$s" = WANTED ] || continue
  [ $dry = 1 ] || mkdir -p "$G"
  if [ $r = smoke ] && [ -z "$V_SMOKE_PLAN" ] && [ -z "$V_SMOKE_REJUDGE" ] && [ -n "$V_SMOKE_APP_DIR" ]; then
    if [ $dry = 1 ]; then echo "[smoke] GEN: $PY $B/smokewalk_gen.py $V_SMOKE_APP_DIR -o $G/plan.json"; fi
  fi
  run_pre $r; prc=$?
  if [ $prc != 0 ]; then setst $r INVALID "$prc" "PRE_$r failed rc=$prc (see $G/$r.pre.out)"; continue; fi
  if [ $r = smoke ] && [ -z "$V_SMOKE_PLAN" ] && [ -z "$V_SMOKE_REJUDGE" ] && [ $dry = 0 ]; then   # a re-judge writes nothing: the stored shots stay
    rm -rf "$G/smoke-after-shots"
    "$PY" "$B/smokewalk_gen.py" "$V_SMOKE_APP_DIR" -o "$G/plan.json" > "$G/smoke-gen.out" 2>&1 || { setst smoke INVALID $? "plan generation failed (see $G/smoke-gen.out)"; continue; }
  fi
  # inputs a PRE command was to produce must exist now
  miss=""; spec $r
  for n in $NEEDS; do k=${n%%:*}; kind=${n#*:}; kind=${kind%%:*}; v=$(get $k)
    case $kind in f) [ -f "$v" ] || miss="$k: no such file: $v";; d) [ -d "$v" ] || miss="$k: no such folder: $v";; esac
  done
  if [ -n "$miss" ] && [ $dry = 0 ]; then
    eval "pre=\$V_PRE_$r"; [ -n "$pre" ] && by="PRE_$r" || by="the earlier PRE commands"
    setst $r INVALID 2 "input missing after $by: $miss"; continue
  fi
  if [ $r = screens ] && [ $dry = 0 ] && [ ! -d "$G/smoke-after-shots" ]; then
    setst screens "NOT RUN" "-" "no $G/smoke-after-shots (the smoke rung did not produce screenshots)"; continue
  fi
  if [ $r = smoke ] && [ -n "$V_SMOKE_REJUDGE" ] && [ $dry = 0 ] && [ ! -f "$G/smoke-after.json" ]; then
    setst smoke "NOT RUN" "-" "SMOKE_REJUDGE set but no $G/smoke-after.json to judge again (the afterwalk step writes it)"; continue
  fi
  if [ $r = journeys ] && [ -n "$V_JOURNEYS_REJUDGE" ] && [ $dry = 0 ] && [ ! -d "$G/e2e-after" ]; then
    setst journeys "NOT RUN" "-" "JOURNEYS_REJUDGE set but no $G/e2e-after to judge again"; continue
  fi
  cmd_rung $r
  if [ $dry = 1 ]; then echo "[$r] $(show_cmd)"; setst $r "DRY" "-" ""; continue; fi
  out=$G/$r.out
  if [ $r = build ]; then "${CMD[@]}" > "$out" 2>&1; rc=$?
    if [ $rc = 0 ]; then v=PASS; elif [ $rc = 1 ]; then v=FAIL; else v=INVALID; fi
    ln="BUILD SUCCEEDED and 0 \"ERROR at\" lines: $( [ $rc = 0 ] && echo yes || echo "no ($(head -1 "$out"))") in $V_BUILD_LOG"
  else
    t=$TO; [ $r = smoke ] && t=${GATE_TIMEOUT:-600}
    echo "[$r] $(show_cmd)"
    run_limited "$t" "$out"; rc=$?   # C6: the limit always applies (timeout, gtimeout, else a bash watchdog); rc 124 = timed out
    if [ $r = smoke ] && [ "$rc" = 1 ] && [ -n "$V_EXCLUDE_SYSTEMS" ]; then   # E2E-14: FAIL steps that only called an excluded system
      "$PY" "$B/apimock.py" attribute-smoke "$G/smoke-after.json" --state "$V_APIMOCK" --exclude-systems "$V_EXCLUDE_SYSTEMS" >> "$out" 2>&1
      [ $? = 4 ] && rc=4
    fi
    v=$(verdict_of $r $rc "$out"); ln=$(oneline "$out")
    if [ $r = journeys ] && [ "$rc" = 3 ]; then   # INVALID only: the instrument's verdict and advice (N1R2-8, T2R3-11)
      ln="$(grep -m1 '^verdict: INVALID only' "$out" | sed 's/^verdict: //')$(grep -m1 '^  baseline: ' "$out" | sed 's/^ */; /')"
      ln="$ln$(grep '^  coverage INVALID: ' "$out" | sed 's/^ */; /' | tr -d '\n')$(grep -m1 '^actions [0-9?]' "$out" | sed 's/^/; /')"   # E2E-11
      [ -n "$ln" ] || ln=$(oneline "$out")
    fi
    [ "$rc" = 124 ] && { ln="timed out after ${t}s (raise GATE_TIMEOUT); $ln"; echo "gate: rung $r timed out after ${t}s: raise GATE_TIMEOUT (smoke: steps x roles x repeat)" >&2; }
    if [ "$v" = EXCEPT ]; then
      nci=$(grep -c '^ *NOT CHECKED (excluded: ' "$out")   # item lines only, not a count line
      if [ "$nci" = 0 ]; then v=INVALID; ln="rc 4 but no NOT CHECKED item named; $ln"; else ln="$nci NOT CHECKED (excluded: $V_EXCLUDE_SYSTEMS); $ln"; fi
    fi
  fi
  setst $r "$v" "$rc" "$ln"
  echo "[$r] $v rc=$rc  $ln"
done
if [ $dry = 0 ] && [ $FAILED_INPUT = 0 ] && [ -n "$(get POST_CMD)" ]; then ( hookenv; bash -c "$V_POST_CMD" ) > "$G/post.out" 2>&1 || echo "gate: POST_CMD failed (see $G/post.out)" >&2; fi
if [ $dry = 1 ] && [ -n "$(get POST_CMD)" ]; then echo "[post] $(mask "$V_POST_CMD")"; fi

# --- 3. verdict and summary ---------------------------------------------------------------------------------------
# --only merges (T2R3-10, N1R2-9): a rung not selected keeps its row from the earlier gate-summary.md of this GATE_DIR
MERGED=""
if [ -n "$only" ] && [ $dry = 0 ] && [ -f "$G/gate-summary.md" ]; then
  when=$(sed -n 's/^Work: .* \([0-9T:-]*Z\)$/\1/p' "$G/gate-summary.md" | head -1)
  while IFS= read -r row; do
    row=${row//\\|/$'\001'}                               # an escaped | inside the line
    IFS=$'\002' read -r _ _ pr pv pc pl _ <<< "${row//|/$'\002'}"
    pr=${pr// /}; pv=${pv// /}; pc=${pc// /}; pl=${pl# }; pl=${pl% }; pl=${pl//$'\001'/|}
    inlist "$pr" "$RUNGS" || continue
    case $pv in PASS|'PASS*'|FAIL|INVALID|EXCEPT) ;; *) continue;; esac   # an earlier NOT RUN carries nothing
    eval "s=\$ST_$pr"; [ "$s" = "NOT RUN" ] || continue
    reason_for "$pr" | grep -q '^not selected' || continue
    pl=${pl% (optional rung)}
    case $pl in '(earlier run '*) ;; *) pl="(earlier run ${when:-?}) $pl";; esac
    setst "$pr" "$pv" "$pc" "$pl"; MERGED="$MERGED $pr"
  done < <(grep -E '^\| [0-9]+ \| ' "$G/gate-summary.md")
fi
# The trail rung (STEP-RECORDS-PLAN.md slice 9): are the step records complete? It runs after every other rung has its row, because
# "tested" is judged from the gate's own links: the other rows are written to a scratch summary, steps.py tested --gate links them to
# the steps, then steps.py trail reads the records. Optional: a miss is a NOT RUN row that starts with WARNING, so it never moves the
# verdict. TRAIL_REQUIRED=1 (slice 10) turns a miss into INVALID and no step records into a required NOT RUN.
if [ "${TRAIL_ON:-0}" = 1 ] && [ $dry = 0 ] && [ $FAILED_INPUT = 0 ] && ! reason_for trail | grep -q .; then
  mkdir -p "$G"; tdir=$(mktemp -d)
  { echo "| # | rung | verdict | rc | one line |"; echo "|---|---|---|---|---|"; ti=0
    for tr in $RUNGS; do ti=$((ti + 1)); [ $tr = trail ] && continue; eval "ts=\$ST_$tr; tc=\$RC_$tr; tl=\$LN_$tr"
      printf '| %s | %s | %s | %s | %s |\n' "$ti" "$tr" "$ts" "$tc" "$(printf '%s' "$tl" | sed 's/|/\\|/g')"; done; } > "$tdir/gate-summary.md"
  mkdir -p "$tdir/w"; cp "$V_WORK/steps.jsonl" "$tdir/w/"; dec=""; for dc in "$V_WORK/AGENT-DECISIONS.md" "$(dirname "$V_WORK")/AGENT-DECISIONS.md"; do [ -f "$dc" ] && { dec=$dc; break; }; done   # a copy: the real links are written once, after the verdict
  "$PY" "$here/steps.py" tested --work "$tdir/w" --gate "$G" --summary "$tdir/gate-summary.md" --by gate > /dev/null 2>&1 || true
  "$PY" "$here/steps.py" trail --work "$tdir/w" ${dec:+--decisions "$dec"} > "$G/trail.out" 2>&1; trc=$?
  tline=$(tail -1 "$G/trail.out" | cut -c1-200); rm -rf "$tdir"
  if [ $trc = 0 ]; then setst trail PASS 0 "$tline"
  elif [ "$V_TRAIL_REQUIRED" = 1 ]; then setst trail INVALID $trc "$tline"
  else setst trail "NOT RUN" "-" "WARNING: $tline"; fi
  eval "echo \"[trail] \$ST_trail: \$LN_trail\""
fi
nfail=0; ninv=0; nnot=0; npass=0; nexc=0; NC_ITEMS=""
for r in $RUNGS; do
  eval "s=\$ST_$r"
  case $s in
    PASS|'PASS*') npass=$((npass + 1));;
    FAIL) nfail=$((nfail + 1));;
    INVALID) ninv=$((ninv + 1));;
    EXCEPT) items=$(grep -h '^ *NOT CHECKED (excluded: ' "$G/$r.out" 2>/dev/null | sed 's/^ *//')   # E2E-14: listed by name
      if [ -z "$items" ]; then setst $r INVALID "$(eval echo \$RC_$r)" "EXCEPT but $G/$r.out names no NOT CHECKED item"; ninv=$((ninv + 1))
      else nexc=$((nexc + 1)); NC_ITEMS="$NC_ITEMS$(printf '%s\n' "$items" | sed "s/^/$r: /")
"; fi;;
    'NOT RUN') optional $r || nnot=$((nnot + 1));;
  esac
done
# E2E-15: a pass on the stand-in is never a pass on the real system: which endpoints did apimock.py answer for?
SI_ITEMS=""; SI_SYS=""
if [ -n "$V_APIMOCK" ] && [ $FAILED_INPUT = 0 ] && [ $dry = 0 ]; then
  mkdir -p "$G"; "$PY" "$B/apimock.py" standin --state "$V_APIMOCK" > "$G/apis-standin.out" 2>&1; sirc=$?
  if [ $sirc != 0 ] || ! grep -q '^stand-in endpoints [0-9]' "$G/apis-standin.out"; then
    ninv=$((ninv + 1))   # unknown stays INVALID: it cannot be shown that only real systems answered
    SUMMARY_NOTE="${SUMMARY_NOTE:+$SUMMARY_NOTE
}APIMOCK is set but \`apimock.py standin --state $V_APIMOCK\` failed (rc $sirc, see $G/apis-standin.out): which APIs were stood in is unknown, INVALID (E2E-15)."
  else
    SI_ITEMS=$(grep '^ *STAND-IN (' "$G/apis-standin.out" | sed 's/^ *//')
    SI_SYS=$(sed -n 's/^stand-in systems: //p' "$G/apis-standin.out" | head -1)
    [ -z "$SI_ITEMS" ] || [ -n "$SI_SYS" ] || SI_SYS=$(printf '%s\n' "$SI_ITEMS" | sed -n 's/^STAND-IN (\([^)]*\)).*/\1/p' | sort -u | paste -sd, - | sed 's/,/, /g')
  fi
fi
nsi=$(printf '%s' "$SI_ITEMS" | grep -c .)
nitems=$(printf '%s' "$NC_ITEMS" | grep -c .)
excsys=$(printf '%s' "$NC_ITEMS" | sed -n 's/.*NOT CHECKED (excluded: \([^)]*\)).*/\1/p' | tr ',' '\n' | sed 's/^ *//' | sort -u | paste -sd, - | sed 's/,/, /g')
if [ $nfail -gt 0 ]; then overall=FAIL; rc=1; elif [ $ninv -gt 0 ] || [ $nnot -gt 0 ]; then overall=INVALID; rc=2
elif [ $nexc -gt 0 ] || [ $nsi -gt 0 ]; then   # E2E-14, E2E-15: never plain PASS, never 0
  q=""; [ $nsi -gt 0 ] && q="on stand-in APIs: $SI_SYS"
  [ $nexc -gt 0 ] && q="${q:+$q; }except $excsys: $nitems items"
  overall="PASS ($q)"; rc=4
else overall=PASS; rc=0; fi

# Progress (positive-verdict.md): checks closed / checks owed. A check = one rung in scope (required, or optional and
# configured) plus one fixed "owner sign-off" item that no machine closes, so 100% is unreachable by the gate alone.
# Numerator is npass only (a written decision never closes a check); floor division, the fraction is always printed.
nowed=1; nreg=0; ndec=0; nmeas=0; REPORT_LINES=""
for r in $RUNGS; do
  eval "s=\$ST_$r; l=\$LN_$r"; h=$(human_of $r "$s")
  case $h in none) continue;; esac
  nowed=$((nowed + 1))
  case $h in
    regression) nreg=$((nreg + 1)); REPORT_LINES="$REPORT_LINES$r: REGRESSION to fix: $l; worked on the old app, not on the new one
";;
    decision) ndec=$((ndec + 1)); REPORT_LINES="$REPORT_LINES$r: needs a decision: $l (steps/decide.md, or the accept file named in the rung's report)
";;
    unmeasured) nmeas=$((nmeas + 1)); REPORT_LINES="$REPORT_LINES$r: not measured yet: $l
";;
    standin) REPORT_LINES="$REPORT_LINES$r: verified except the items that need the excluded system: $l
";;
  esac
done
# L56: a notes file (GATE_NOTES) lists what the run's people or agents wrote down as still open. The gate never read it, so a
# run could print "nothing open" while the notes held a decision. Every non-empty line that is not a comment is a decision item.
NOTES_N=0
if [ -n "$V_GATE_NOTES" ] && [ -f "$V_GATE_NOTES" ]; then
  while IFS= read -r nl || [ -n "$nl" ]; do
    [ -n "${nl//[[:space:]]/}" ] || continue
    case "$nl" in '#'*) continue;; esac
    NOTES_N=$((NOTES_N + 1)); REPORT_LINES="${REPORT_LINES}notes: needs a decision: $nl (from $V_GATE_NOTES)
"
  done < "$V_GATE_NOTES"
  ndec=$((ndec + NOTES_N))
fi
HEAL_LINE=""
if [ -n "$V_HEAL_JSON" ] && [ -f "$V_HEAL_JSON" ] && [ -f "$here/heal.py" ]; then HEAL_LINE=$("$PY" "$here/heal.py" summary --work "$(dirname "$V_HEAL_JSON")" 2>/dev/null | tail -1); fi
nclosed=$npass
# one machine line for grade.py: the same classes, so Progress and GRADE count a rung the same way
CLASSES=""; for r in $RUNGS; do eval "s=\$ST_$r"; CLASSES="$CLASSES $r=$(human_of $r "$s")"; done
PROGRESS="Progress: $nclosed of $nowed checks closed ($((100 * nclosed / nowed))%). $nreg with REGRESSIONS to fix, $ndec need a decision, $nmeas not measured yet, owner sign-off pending."
[ $nexc -gt 0 ] && PROGRESS="$PROGRESS $nexc verified except on an excluded system (real system pending)."
# trust spec section 2: a run whose upgrade proposal nobody signed (unattended) says so in every report. Only when the
# propose step wrote PROPOSAL.md; a work folder without one (an older run, a gate-only run) keeps its summary as it was.
PROPOSAL_NOTE=""
if [ -f "$V_WORK/PROPOSAL.md" ]; then
  case "$("$PY" "$here/proposal.py" --status --work "$V_WORK" 2>/dev/null)" in
    signed) ;;
    *) PROPOSAL_NOTE="proposal not signed: $V_WORK/PROPOSAL.md has no Signed-off line, so this verdict is not an owner-approved upgrade (steps/propose.md)"
       PROGRESS="$PROGRESS Proposal not signed." ;;
  esac
fi

# Change ledger: measurement only, like the cost ledger; a failing changelog.py never changes a verdict or rc.
CHANGES_LINE=""
ledger_app=$V_APP_REPO; [ -n "$ledger_app" ] || { [ -e "$V_WORK/app/.git" ] && ledger_app=$V_WORK/app; }
if [ $dry = 0 ] && [ -n "$ledger_app" ] && [ -f "$here/changelog.py" ]; then
  acc=(); seen=" "
  for k in ALLOW LOG_ALLOW CONST_ALLOW SMOKE_SHOT_ACCEPT JOURNEY_SHOT_ACCEPT JOURNEY_EFFECT_ACCEPT LAYOUT_ACCEPT APPROVED WIDGETS_WAIVE ACTIONS_WAIVE; do
    f=$(get $k); [ -n "$f" ] && [ -f "$f" ] || continue
    case "$seen" in *" $f "*) continue;; esac; seen="$seen$f "; acc+=(--accept "$k=$f")
  done
  dec=(); [ -f "$V_WORK/DECISIONS.md" ] && dec=(--decisions "$V_WORK/DECISIONS.md")
  CHANGES_LINE=$("$PY" "$here/changelog.py" --app "$ledger_app" --work "$V_WORK" ${acc[@]+"${acc[@]}"} ${dec[@]+"${dec[@]}"} 2>/dev/null | tail -1)
  case "$CHANGES_LINE" in
    "Changes: "*)
      nunl=$(printf '%s' "$CHANGES_LINE" | sed -n 's/.*unlabelled \([0-9][0-9]*\)).*/\1/p')
      if [ "${nunl:-0}" -gt 0 ]; then
        REPORT_LINES="${REPORT_LINES}changes: needs a decision: $nunl commit(s) in the app repo carry no Changed-By / Upgrade-Change trailers (listed as unlabelled in $V_WORK/CHANGES.md; say who made them and why, steps/decide.md)
"
      fi;;
    *) CHANGES_LINE="Changes: not written (changelog.py failed on $ledger_app; measurement only, verdict unchanged)";;
  esac
fi

table() {
  echo "| # | rung | verdict | rc | one line |"; echo "|---|---|---|---|---|"
  local i=0 r
  for r in $RUNGS; do
    i=$((i + 1)); eval "s=\$ST_$r; c=\$RC_$r; l=\$LN_$r"
    [ "$s" = DRY ] && s="(dry-run)"
    [ "$s" = "NOT RUN" ] && optional $r && l="$l (optional rung)"
    printf '| %s | %s | %s | %s | %s |\n' "$i" "$r" "$s" "$c" "$(printf '%s' "$l" | sed 's/|/\\|/g')"
  done
}
if [ $dry = 1 ]; then
  echo; echo "dry-run: nothing was run or written. Rungs without a command above are NOT RUN:"; table
  [ $FAILED_INPUT = 0 ] && exit 0 || exit 2
fi
mkdir -p "$G" 2>/dev/null
{
  echo "# Gate summary"; echo
  echo "Overall: **$overall** (exit $rc): $npass PASS/PASS*, $nexc EXCEPT, $nfail FAIL, $ninv INVALID, $nnot required NOT RUN."
  echo "$PROGRESS"
  [ -z "$CHANGES_LINE" ] || { echo "$CHANGES_LINE"; echo "Change ledger: \`$V_WORK/CHANGES.md\`"; }
  [ -z "$HEAL_LINE" ] || echo "$HEAL_LINE (details: \`$(dirname "$V_HEAL_JSON")/heal.md\`)"
  # machine line for grade.py (read anywhere in the file): after the two lines people read first
  echo "Classes:$CLASSES"
  echo "Work: \`$V_WORK\`, evidence: \`$G\`, instruments: \`$B\`, run $V_RUN. $(date -u +%Y-%m-%dT%H:%MZ)"; echo
  [ -n "$SUMMARY_NOTE" ] && { echo "$SUMMARY_NOTE"; echo; }
  [ -n "$PROPOSAL_NOTE" ] && { echo "$PROPOSAL_NOTE"; echo; }
  [ -n "$MERGED" ] && { echo "Merged (--only $only): rungs$MERGED keep their row from the earlier summary; the overall verdict counts them."; echo; }
  table; echo
  if [ -n "$NC_ITEMS" ]; then
    echo "NOT CHECKED (excluded systems, E2E-14): $nitems items. Each needs the real system; none of them is a PASS:"
    printf '%s' "$NC_ITEMS" | sed 's/^/- /'; echo
  fi
  if [ -n "$SI_ITEMS" ]; then
    echo "ON STAND-IN APIs (E2E-15): $nsi endpoints were answered by apimock.py, not by the real system ($SI_SYS)."
    echo "Real-system behaviour was NOT checked. This is a conditional PASS: run the gate again against the vendors' test systems before go-live."
    printf '%s\n' "$SI_ITEMS" | sed 's/^/- /'; echo
  fi
  echo "Report words: PASS = verified; PASS* = verified with accepted differences; FAIL = REGRESSION to fix only when something that passed on the old app fails on the new one, needs a decision when only REVIEW lines are open; INVALID / NOT RUN = not measured yet (or needs a decision when a human item is open)."
  if [ -n "$REPORT_LINES" ]; then echo; echo "Not closed, in report words (REGRESSIONS first):"; printf '%s' "$REPORT_LINES" | grep '^[^:]*: REGRESSION' | sed 's/^/- /'; printf '%s' "$REPORT_LINES" | grep -v '^[^:]*: REGRESSION' | sed 's/^/- /'; echo; fi
  echo "PASS* = accepted in writing (allow or accept file; each reason is in the rung's report). FAIL = an open FAIL or REVIEW."
  echo "INVALID = the rung could not judge (instrument rc 2, journeys rc 3, timeout, failed PRE command); it blocks DONE and is never PASS."
  echo "NOT RUN = the rung was skipped or its inputs were not given; for a required rung that blocks DONE too."
  echo "EXCEPT = the rung's only non-PASS items failed on a call into an excluded system (EXCLUDE_SYSTEMS): NOT CHECKED, listed above; the overall verdict is then PASS (except ...), exit 4, never plain PASS."
  echo "PASS (on stand-in APIs: ...) = APIMOCK answered for the listed endpoints; exit 4, never plain PASS: plain PASS needs the real (test) systems."
} > "$G/gate-summary.md" 2>/dev/null || echo "gate: could not write $G/gate-summary.md" >&2
echo; echo "gate: $overall (exit $rc): $npass PASS/PASS*, $nexc EXCEPT, $nfail FAIL, $ninv INVALID, $nnot required NOT RUN; summary: $G/gate-summary.md"
echo "$PROGRESS"
[ -z "$CHANGES_LINE" ] || echo "$CHANGES_LINE"
[ -z "$HEAL_LINE" ] || echo "$HEAL_LINE"
[ -z "$PROPOSAL_NOTE" ] || echo "  $PROPOSAL_NOTE"
[ -z "$SI_ITEMS" ] || echo "  on stand-in APIs ($SI_SYS): $nsi endpoints answered by apimock.py; real-system behaviour NOT checked (E2E-15)"
for r in $RUNGS; do eval "s=\$ST_$r; c=\$RC_$r; l=\$LN_$r"; case $s in PASS|'PASS*') ;; *) printf '  %-9s %-8s rc=%s  %s\n' "$r" "$s" "$c" "$l"; case $(human_of $r "$s") in regression) echo "            -> REGRESSION to fix";; decision) echo "            -> needs a decision";; unmeasured) echo "            -> not measured yet";; esac;; esac; done
# completion grade (steps/report.md): how many of the required rungs are done, printed next to the verdict and stamped into
# gate-summary.md as one Grade: line. Information only: a failing grade.py never changes the verdict or rc.
if [ -f "$G/gate-summary.md" ]; then "$PY" "$here/grade.py" "$G/gate-summary.md" --stamp 2>&1 | sed 's/^/  /' || true; fi
# step records (STEP-RECORDS-PLAN.md slice 6): after the rungs, each step's closes_by rungs are linked to their rows in
# gate-summary.md (and heal.json) as a pass, a fail or a gap. Information only: a failing steps.py never changes the verdict or rc.
if [ -f "$V_WORK/steps.jsonl" ] && [ -f "$G/gate-summary.md" ]; then
  "$PY" "$here/steps.py" tested --work "$V_WORK" --gate "$G" --by gate 2>&1 | sed 's/^/  /' || true
fi
# cost-ledger (quality-judgement-plan.md item 4): measurement only. The per-layer cost lines of this work folder are printed
# when the ledger exists; a failing report never changes the verdict or rc.
if [ -f "$V_WORK/cost-ledger.tsv" ]; then
  echo; python3 "$here/cost_ledger.py" report --work "$V_WORK" 2>&1 || echo "gate: cost-ledger report failed (measurement only, verdict unchanged)"
fi
exit $rc
