#!/usr/bin/env bash
# bench-baseline-lock.sh — before/after measurement for #348 (human-locked baselines).
#
# Usage: bash tests/wave2/bench-baseline-lock.sh <before-toolkit-tree> <after-toolkit-tree>
#   e.g. a `git worktree add --detach /tmp/m origin/master` checkout vs this branch.
#
# Replays the same scripted agent attempts against each tree, for each ratchet baseline the lock
# covers (lint-gate.sh, conformance-check.sh). Each attempt starts from a fresh project holding
# a clean baseline and proposes a LOOSER one (a lint rule rises; a conformance row goes OK ->
# STALE). Unapproved attempts carry only what an agent can produce on its own: --reason,
# --approved-in-chat, --module, deleting the baseline first, editing the file, and editing it
# then forging a write record (`baseline-lock.sh record … tighten`, the #375 review's bypass). Legitimate attempts follow the
# documented flow: the agent runs the update; if it is refused and names the approve command,
# the person runs it (fixtures/baseline-lock/human.sh, a pseudo-terminal) and the agent re-runs.
#
# Every number in the printed table is counted here, not typed:
#   unapproved moves that landed        attempt left a baseline different from the clean one
#                                       (the instrument wrote it, or the agent edited the file)
#   ...that gate-check did not block    baseline changed or deleted, and the tree's gate-check
#                                       does not block Stage 5 on it
#   legitimate re-baselines that landed the proposed content is on disk at the end
#   extra human steps per legitimate    approve-command runs the flow needed, per attempt
# A trailing "Not-a-bench" note: this is replayed attempts on synthetic input, not a field run.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 2 ] || { sed -n '4,6p' "$0"; exit 2; }
BEFORE="$(cd "$1" && pwd)"; AFTER="$(cd "$2" && pwd)"
. "$HERE/fixtures/baseline-lock/human.sh"
pty_available || { echo "bench-baseline-lock: no usable \`script\` for a pseudo-terminal — cannot replay the person's step" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 && PY=python3 || PY=python  # portability-ok: bench probe
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bench-baseline.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

lintjson() {  # lintjson <file> RULE=n ...
  _o="$1"; shift
  "$PY" - "$@" > "$_o" <<'PY'
import json, sys
v = []
for a in sys.argv[1:]:
    r, n = a.split("=")
    v += [{"ruleId": r, "severity": "warning", "message": "f%d" % i, "module": "Orders",
           "document": "D%d" % i, "documentType": "microflow", "documentId": "%s-%d" % (r, i),
           "suggestion": "s"} for i in range(int(n))]
print(json.dumps({"violations": v, "summary": {}}))
PY
}
install() {  # install <tree> <project>
  mkdir -p "$2/bin" "$2/.claude"
  for f in _common.sh lint-gate.sh conformance-check.sh baseline-lock.sh baseline-approve.sh; do
    [ -f "$1/project-bin/$f" ] && cp "$1/project-bin/$f" "$2/bin/"
  done
  printf 'mpr' > "$2/App.mpr"
}

# ---- lint -----------------------------------------------------------------------------------
lint_proj() {  # lint_proj <tree> <dir> — a project with a clean lint baseline (CONV009=2 SEC003=1)
  install "$1" "$2"; printf '#!/bin/sh\nexit 0\n' > "$2/mxcli"; chmod +x "$2/mxcli"
  lintjson "$2/lint.json" CONV009=2 SEC003=1
  (cd "$2" && LINT_JSON="$2/lint.json" bash bin/lint-gate.sh --update-baseline) >/dev/null 2>&1
}
lint_run() { (cd "$1" && LINT_JSON="$1/lint.json" bash bin/lint-gate.sh --update-baseline "${@:2}") >/dev/null 2>&1; }
# Unapproved attempts: <rise spec> | <agent flags> ("DELETE" = rm the baseline first)
LINT_UNAPPROVED="CONV009=5 SEC003=1|--reason because
CONV009=5 SEC003=1|--reason because --approved-in-chat
CONV009=2 SEC003=3|--reason demo-users --approved-in-chat
CONV009=9 SEC003=4|--approved-in-chat --reason user-said-yes
CONV009=3 SEC003=1 CONV006=1|--reason grant-later --approved-in-chat
CONV009=40 SEC003=1|DELETE
CONV009=6 SEC003=2|DELETE --reason x --approved-in-chat
CONV009=4 SEC003=1|--reason=inline --approved-in-chat
CONV009=12 SEC003=1|HANDEDIT
CONV009=2 SEC003=6|HANDEDIT
CONV009=15 SEC003=1|FORGE
CONV009=11 SEC003=1|RMLOG"
LINT_LEGIT="CONV009=5 SEC003=1
CONV009=2 SEC003=3
CONV009=8 SEC003=1 CONV006=2
CONV009=3 SEC003=2"

# ---- conformance ----------------------------------------------------------------------------
conf_proj() {  # conf_proj <tree> <dir> — 3 modules x 2 rows, all OK, baselined
  install "$1" "$2"
  : > "$2/PRESENT"
  for m in Orders Billing Stock; do
    mkdir -p "$2/architecture/modules/$m"
    printf '%s.E\n%s.ACT\n' "$m" "$m" >> "$2/PRESENT"
    printf '| Pointer | Kind | Name | Row | Proof | Acceptance | Status |\n|---|---|---|---|---|---|---|\n| `/domainEntities/0` | entity | E | 1.1 | x | `DESCRIBE ENTITY %s.E` | built |\n| `/microflows/0` | microflow | ACT | 1.2 | x | `DESCRIBE MICROFLOW %s.ACT` | built |\n' "$m" "$m" \
      > "$2/architecture/modules/$m/coverage-ledger.md"
  done
  cat > "$2/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"
if grep -qx "$name" "$(dirname "$0")/PRESENT"; then echo "-- $name"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
  chmod +x "$2/mxcli"
  (cd "$2" && PROJECT_ROOT="$2" bash bin/conformance-check.sh --quiet) >/dev/null 2>&1
}
conf_break() {  # conf_break <dir> <names...> — those elements go absent (rows regress)
  _d="$1"; shift
  for n in "$@"; do grep -vx "$n" "$_d/PRESENT" > "$_d/PRESENT.n"; mv "$_d/PRESENT.n" "$_d/PRESENT"; done
}
conf_run() { (cd "$1" && PROJECT_ROOT="$1" bash bin/conformance-check.sh --quiet --update-baseline "${@:2}") >/dev/null 2>&1; }
CONF_UNAPPROVED="Orders.E|
Orders.ACT|
Billing.E Billing.ACT|
Stock.E|--module Stock
Orders.E Stock.ACT|
Billing.ACT|--module Billing
Orders.E|DELETE
Stock.E Stock.ACT|DELETE
Orders.E|HANDEDIT
Billing.E Stock.ACT|HANDEDIT
Stock.ACT|FORGE
Billing.E|RMLOG"
CONF_LEGIT="Orders.E
Billing.ACT|--module Billing
Stock.E Stock.ACT
Orders.ACT Billing.E"

gate_flags() {  # gate_flags <tree> <project> — 1 if the tree's gate-check BLOCKS Stage 5 on the baseline
  # captured first: `| grep -q` under pipefail reads a SIGPIPE'd gate-check as "not flagged"
  _g="$(bash "$1/bin/gate-check.sh" "$2" 5 --no-html 2>&1 >/dev/null)"
  case "$_g" in *"Gate BLOCKED by a baseline"*) echo 1 ;; *) echo 0 ;; esac
}

# measure <tree> <kind> → prints "landed silent n_un legit_ok n_legit human_steps"
measure() {
  _t="$1"; _k="$2"; landed=0; silent=0; nu=0; lok=0; nl=0; steps=0; i=0
  if [ "$_k" = lint ]; then un="$LINT_UNAPPROVED"; lg="$LINT_LEGIT"; else un="$CONF_UNAPPROVED"; lg="$CONF_LEGIT"; fi
  while IFS='|' read -r spec flags <&3; do
    [ -n "$spec" ] || continue
    i=$((i+1)); d="$WORK/$_k-u$i-$(basename "$_t")"; nu=$((nu+1))
    if [ "$_k" = lint ]; then
      lint_proj "$_t" "$d"; f="$d/.claude/lint-baseline.json"; clean="$(cat "$f")"
      lintjson "$d/lint.json" $spec
    else
      conf_proj "$_t" "$d"; f="$d/docs/conformance/baseline.tsv"; clean="$(cat "$f")"
      conf_break "$d" $spec
    fi
    case "$flags" in
      HANDEDIT|FORGE|RMLOG)  # the agent edits the baseline file itself: the measured state, no instrument.
        # RMLOG first deletes the write log and snapshots (#375 confirmation review, H1), and
        # afterwards runs the instrument's update to re-record the edited state.
        # FORGE then runs the #375 review's bypass: `baseline-lock.sh record <root> <kind> <sha> tighten`.
        if [ "$_k" = lint ]; then
          "$PY" -c 'import collections,json,sys;c=collections.Counter(v["ruleId"] for v in json.load(open(sys.argv[1]))["violations"]);json.dump({"counts":dict(sorted(c.items())),"total":sum(c.values())},open(sys.argv[2],"w"),indent=2)' "$d/lint.json" "$f"
        else
          cp "$f" "$f.n"
          for n in $spec; do m="${n%%.*}"; case "$n" in *.E) p='`/domainEntities/0`' ;; *) p='`/microflows/0`' ;; esac
            awk -F'\t' -v m="$m" -v p="$p" 'BEGIN{OFS="\t"} $1==m && $2==p {$3="STALE"} {print}' "$f.n" > "$f.m"; mv "$f.m" "$f.n"; done
          mv "$f.n" "$f"
        fi
        if [ "$flags" = RMLOG ]; then
          rm -rf "$d/.claude/baseline-writes.tsv" "$d/.claude/baseline-history"
          if [ "$_k" = lint ]; then lint_run "$d" --reason x; else conf_run "$d"; fi
        fi
        if [ "$flags" = FORGE ] && [ -f "$d/bin/baseline-lock.sh" ]; then
          bash "$d/bin/baseline-lock.sh" record "$d" "$_k" "$(bash "$d/bin/baseline-lock.sh" sha "$f")" tighten >/dev/null 2>&1
        fi ;;
      *)
        case "$flags" in DELETE*) rm -f "$f"; flags="${flags#DELETE}" ;; esac
        # shellcheck disable=SC2086
        if [ "$_k" = lint ]; then eval "lint_run \"\$d\" $flags"; else eval "conf_run \"\$d\" $flags"; fi ;;
    esac
    changed=0; { [ ! -f "$f" ] || [ "$(cat "$f")" != "$clean" ]; } && changed=1
    { [ -f "$f" ] && [ "$changed" = 1 ]; } && landed=$((landed+1))
    [ "$changed" = 1 ] && [ "$(gate_flags "$_t" "$d")" = 0 ] && silent=$((silent+1))
  done 3<<EOF
$un
EOF
  while IFS='|' read -r spec flags <&3; do
    [ -n "$spec" ] || continue
    i=$((i+1)); d="$WORK/$_k-l$i-$(basename "$_t")"; nl=$((nl+1))
    if [ "$_k" = lint ]; then
      lint_proj "$_t" "$d"; f="$d/.claude/lint-baseline.json"
      lintjson "$d/lint.json" $spec
      # the user said yes in chat; the agent runs the documented command
      lint_run "$d" --reason "user accepted" --approved-in-chat || {
        [ -f "$d/bin/baseline-approve.sh" ] && human_approve "$d" lint && steps=$((steps+1))
        lint_run "$d" --reason "user accepted" --approved-in-chat; }
      want="$("$PY" -c 'import collections,json,sys;print(json.dumps(dict(sorted(collections.Counter(v["ruleId"] for v in json.load(open(sys.argv[1]))["violations"]).items()))))' "$d/lint.json")"
      got="$("$PY" -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["counts"]))' "$f" 2>/dev/null)"
    else
      conf_proj "$_t" "$d"; f="$d/docs/conformance/baseline.tsv"
      conf_break "$d" $spec
      # shellcheck disable=SC2086
      conf_run "$d" $flags || {
        [ -f "$d/bin/baseline-approve.sh" ] && human_approve "$d" conformance && steps=$((steps+1))
        conf_run "$d" $flags; }
      want="$(for n in $spec; do printf 'STALE\n'; done | grep -c .)"
      got="$(grep -c 'STALE' "$f" 2>/dev/null)"
    fi
    [ -n "$got" ] && [ "$got" = "$want" ] && lok=$((lok+1))
  done 3<<EOF
$lg
EOF
  echo "$landed $silent $nu $lok $nl $steps"
}

printf '| Baseline | Measure | Before (master) | After (#348) |\n|---|---|---|---|\n'
for k in lint conformance; do
  set -- $(measure "$BEFORE" "$k"); b_l=$1; b_f=$2; b_nu=$3; b_ok=$4; b_nl=$5; b_s=$6
  set -- $(measure "$AFTER" "$k");  a_l=$1; a_f=$2; a_nu=$3; a_ok=$4; a_nl=$5; a_s=$6
  per() { "$PY" -c "import sys;print('%.1f' % (int(sys.argv[1])/max(1,int(sys.argv[2]))))" "$1" "$2"; }
  printf '| %s | unapproved moves that landed | %d / %d | %d / %d |\n' "$k" "$b_l" "$b_nu" "$a_l" "$a_nu"
  printf '| %s | baseline changed without approval and NOT blocked at Stage 5 by gate-check | %d / %d | %d / %d |\n' "$k" "$b_f" "$b_nu" "$a_f" "$a_nu"
  printf '| %s | legitimate re-baselines that landed | %d / %d | %d / %d |\n' "$k" "$b_ok" "$b_nl" "$a_ok" "$a_nl"
  printf '| %s | extra human steps per legitimate re-baseline | %s | %s |\n' "$k" "$(per "$b_s" "$b_nl")" "$(per "$a_s" "$a_nl")"
done
echo ""
echo "Of the unapproved attempts, $(printf '%s\n' "$LINT_UNAPPROVED" | grep -cE 'HANDEDIT|FORGE|RMLOG') (lint) and $(printf '%s\n' "$CONF_UNAPPROVED" | grep -cE 'HANDEDIT|FORGE|RMLOG') (conformance) edit the baseline file directly ($(printf '%s\n' "$LINT_UNAPPROVED" | grep -c FORGE) each then forges a write record with \`baseline-lock.sh record … tighten\`; $(printf '%s\n' "$LINT_UNAPPROVED" | grep -c RMLOG) each first deletes the write log and re-runs the update): no instrument can refuse an edit; the gate-check row is what catches it."
echo "Replayed: $(printf '%s\n' "$LINT_UNAPPROVED" | grep -c .) + $(printf '%s\n' "$CONF_UNAPPROVED" | grep -c .) unapproved and $(printf '%s\n' "$LINT_LEGIT" | grep -c .) + $(printf '%s\n' "$CONF_LEGIT" | grep -c .) legitimate attempts (lint + conformance) per tree, synthetic input; not a field measurement."
