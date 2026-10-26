#!/usr/bin/env bash
# metrics-ledger.sh — one row per exec: outcome, speed, lint total, quality score.
#
# WHY. The toolkit measured its own OUTPUT (lint findings per rule, gate verdicts) but never
# its OUTCOME: is the app getting better, and is the build getting faster, as the rules and
# skills change. BUILD-LOG.md has the verdict per exec but as prose in a markdown table;
# lint-ledger.tsv has findings per rule but no score and no timing; `mxcli report` scores the
# model 0-100 but nobody stored the number, so no project can say what its score was a month
# ago. This file joins the three on the only event every build goes through — an exec — so
# "did the score move, did gate failures fall, did execs get faster" is a `metrics-trend.sh`
# call, per project and (via bin/harvest-learnings.sh) across projects.
#
# PRODUCES .claude/loop/metrics-ledger.tsv (append-only). Read with project-bin/metrics-trend.sh.
# PRODUCER: project-bin/exec.sh calls `score` after a clean mxbuild and `exec` from log_build on
# EVERY outcome, so a row exists for blocked and failed execs too — a ledger of only the good
# runs would show a rising score and hide the ten restores it cost.
#
#   ts  script  gate  result  elapsed_s  mxbuild_errors  lint_rc  lint_total  restored
#   score  security  quality  architecture  performance  naming  design  other  violations  model_commit
#
# `result` is a short class, not the BUILD-LOG wording: applied · applied-lint-rose · applied-lint-blind ·
# applied-dirty · applied-unverified · partial · gate-failed · gate-not-run · rolled-back ·
# blocked · refused · patch-failed · other. Score columns are empty when `score` did not run
# this exec (a failed or blocked write is not scored — the model was restored or never written).
# `lint_total` is read from .claude/loop/lint-last.json, which lint-gate.sh rewrites every run,
# only when the caller says lint ran (--lint-rc 0|1|3); otherwise empty, never 0.
#
# Usage:
#   bin/metrics-ledger.sh score            runs ./mxcli report --format json (≈7 s on an 876-flow
#                                          model, 2026-10-12; it refreshes the catalog) and writes
#                                          .claude/loop/report-last.json. Exit 0 wrote · 3 no mxcli
#                                          or report failed (the exec row then has empty scores).
#   bin/metrics-ledger.sh exec --script NAME --gate STATE --result 'BUILD-LOG status' \
#        --elapsed SECONDS [--mxbuild-errors N] [--lint-rc N] [--restored 0|1] [--scored 0|1]
#                                          appends the row. Exit 0 · 2 bad invocation.
#   MXTK_NO_SCORE=1                        exec.sh skips `score` (slow machine, CI); rows still land.
#
# Golden input: tests/wave2/fixtures/mxcli-report-0.26.0.json is a redacted verbatim capture
# of `mxcli report --format json` (0.26.0): 7 categories, "Other" included, scores are
# integers, overallScore a float, JSON starts at byte 0 (banner goes to stderr, unlike lint's
# text mode). Keep bash-3.2 compatible.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$ROOT"
LOOP="$ROOT/.claude/loop"
LEDGER="$LOOP/metrics-ledger.tsv"
REPORT_LAST="$LOOP/report-last.json"
LINT_LAST="$LOOP/lint-last.json"

if [ -f "$(dirname "${BASH_SOURCE[0]}")/_common.sh" ]; then
  . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
fi
if ! type require_py >/dev/null 2>&1; then
  require_py() {
    _c=""
    for _c in python3 python py; do  # portability-ok: this IS the interpreter probe
      case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
      if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
        PY="$_c"; export PY; return 0
      fi
    done
    echo "metrics-ledger: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
    exit 2
  }
fi
if ! type find_mpr >/dev/null 2>&1; then
  find_mpr() { ls "$PROJECT_ROOT"/*.mpr "$PROJECT_ROOT"/app/*.mpr "$PROJECT_ROOT"/apps/*/*.mpr 2>/dev/null | head -1; }
fi
if ! type find_project_mxcli >/dev/null 2>&1; then
  find_project_mxcli() { [ -x "$PROJECT_ROOT/mxcli" ] && echo "$PROJECT_ROOT/mxcli"; }
fi
require_py

MODE="${1:-}"; shift 2>/dev/null || true
case "$MODE" in
  -h|--help|"") sed -n '2,45p' "$0"; [ "$MODE" = "" ] && exit 2; exit 0 ;;
  score|exec) ;;
  *) echo "metrics-ledger: unknown mode '$MODE' (score|exec)" >&2; exit 2 ;;
esac

if [ "$MODE" = "score" ]; then
  MXCLI="${MXCLI_BIN:-$(find_project_mxcli 2>/dev/null || true)}"
  MPR="$(find_mpr 2>/dev/null || true)"
  if [ -z "$MXCLI" ] || [ ! -x "$MXCLI" ] || [ -z "$MPR" ]; then
    echo "metrics-ledger: no ./mxcli or no .mpr — score not taken" >&2; exit 3
  fi
  mkdir -p "$LOOP"
  _tmp="$LOOP/.report-last.tmp"
  if ! "$MXCLI" report -p "$MPR" --format json >"$_tmp" 2>/dev/null; then
    rm -f "$_tmp"; echo "metrics-ledger: mxcli report failed — score not taken" >&2; exit 3
  fi
  # Accept a banner-prefixed body too (lint's text mode does that; report 0.26.0 does not).
  if ! "$PY" - "$_tmp" "$REPORT_LAST" <<'PYEOF'
import json, sys
raw = open(sys.argv[1]).read()
try:
    d = json.loads(raw[raw.index("{"):])
except (ValueError, IndexError):
    sys.exit(1)
if "overallScore" not in d or "categories" not in d:
    sys.exit(1)
d.pop("violations", None)            # per-finding rows live in lint-last.json; keep this small
json.dump(d, open(sys.argv[2], "w"), indent=2); open(sys.argv[2], "a").write("\n")
print("score=%s categories=%d violations=%d" % (d["overallScore"], len(d["categories"]), d.get("summary", {}).get("total", 0)))
PYEOF
  then
    rm -f "$_tmp"; echo "metrics-ledger: report output was not the expected JSON — score not taken" >&2; exit 3
  fi
  rm -f "$_tmp"; exit 0
fi

# ---- exec: append the row ----------------------------------------------------------------
SCRIPT=""; GATE=""; RESULT=""; ELAPSED=""; MXB_ERR=""; LINT_RC=""; RESTORED="0"; SCORED="0"
while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT="${2:-}"; shift ;;
    --gate) GATE="${2:-}"; shift ;;
    --result) RESULT="${2:-}"; shift ;;
    --elapsed) ELAPSED="${2:-}"; shift ;;
    --mxbuild-errors) MXB_ERR="${2:-}"; shift ;;
    --lint-rc) LINT_RC="${2:-}"; shift ;;
    --restored) RESTORED="${2:-0}"; shift ;;
    --scored) SCORED="${2:-0}"; shift ;;
    *) echo "metrics-ledger: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$SCRIPT" ] && [ -n "$GATE" ] && [ -n "$RESULT" ] && [ -n "$ELAPSED" ] || {
  echo "metrics-ledger: exec needs --script --gate --result --elapsed" >&2; exit 2; }

MODEL_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "")"
mkdir -p "$LOOP"
"$PY" - "$LEDGER" "$SCRIPT" "$GATE" "$RESULT" "$ELAPSED" "$MXB_ERR" "$LINT_RC" "$RESTORED" \
       "$SCORED" "$REPORT_LAST" "$LINT_LAST" "$MODEL_COMMIT" <<'PYEOF'
import datetime, json, os, sys
(ledger, script, gate, result, elapsed, mxb_err, lint_rc, restored,
 scored, report_last, lint_last, commit) = sys.argv[1:13]

def classify(s):
    t = s.lower()
    if "patch failed" in t: return "patch-failed"
    if "rolled back" in t: return "rolled-back"
    if "gate could not run" in t: return "gate-not-run"
    if "gate failed" in t: return "gate-failed"
    if "blocked" in t: return "blocked"
    if "refused" in t: return "refused"
    if "partial" in t: return "partial"
    if "lint rose" in t: return "applied-lint-rose"
    if "lint blind" in t: return "applied-lint-blind"   # a rule inspected nothing: not a clean pass
    if "dirty" in t: return "applied-dirty"
    if "unverified" in t: return "applied-unverified"
    if "applied" in t: return "applied"
    return "other"

lint_total = ""
if lint_rc in ("0", "1", "3") and os.path.exists(lint_last):   # 3 = ran, a rule was blind
    try:
        lint_total = str(json.load(open(lint_last)).get("total", ""))
    except (OSError, ValueError):
        lint_total = ""

CATS = ["Security", "Quality", "Architecture", "Performance", "Naming", "Design", "Other"]
score = ""; cats = {c: "" for c in CATS}; violations = ""
if scored == "1" and os.path.exists(report_last):
    try:
        d = json.load(open(report_last))
        score = str(d.get("overallScore", ""))
        for c in d.get("categories", []):
            if c.get("name") in cats:
                cats[c["name"]] = str(c.get("score", ""))
        violations = str(d.get("summary", {}).get("total", ""))
    except (OSError, ValueError):
        pass

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
header = ("ts\tscript\tgate\tresult\telapsed_s\tmxbuild_errors\tlint_rc\tlint_total\trestored\t"
          "score\tsecurity\tquality\tarchitecture\tperformance\tnaming\tdesign\tother\tviolations\tmodel_commit\n")
row = [ts, script.replace("\t", " "), gate, classify(result), elapsed, mxb_err, lint_rc, lint_total, restored,
       score] + [cats[c] for c in CATS] + [violations, commit]
new = not os.path.exists(ledger)
with open(ledger, "a") as f:
    if new: f.write(header)
    f.write("\t".join(row) + "\n")
PYEOF
