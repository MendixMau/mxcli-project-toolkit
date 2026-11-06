#!/usr/bin/env bash
# metrics-trend.sh — is this project getting better, and is the build getting faster?
#
# Reads .claude/loop/metrics-ledger.tsv (one row per exec, written by project-bin/exec.sh
# through metrics-ledger.sh, plus one module-close row per module from bin/module-close.sh and
# any score-only rows from `metrics-ledger.sh record`) and prints:
#   - outcomes: execs, applied share, gate failures, restores, lint rises
#   - speed: median and worst elapsed, first-half vs second-half median
#   - lint: total findings first → last (only rows where lint ran)
#   - score: `mxcli report` overall and per category, first → last, with the delta, from every
#     row that has one — since 2026-11-05 that is one point per module close, not per exec
#     (exec.sh scores each exec only under `Score: every exec`), so the series is short and each
#     point says where it was taken. Outcomes and speed count exec rows only.
# Numbers only — no script names in the default view, so the output is safe to paste into a
# toolkit inbox file (bin/harvest-learnings.sh does exactly that). `--runs` adds the per-exec
# rows, script names included, for use inside the project.
#
# Usage:
#   project-bin/metrics-trend.sh            # summary
#   project-bin/metrics-trend.sh --runs     # every row, oldest first
#   project-bin/metrics-trend.sh --score    # the score series only (ts, overall, categories)
#   project-bin/metrics-trend.sh --since 2026-10-01   # restrict to rows from that date
#
# Exit 0 with output; 2 when there is no ledger yet (no exec has run here). Read-only.
# Keep bash-3.2 compatible.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="${MXTK_METRICS_LEDGER:-$ROOT/.claude/loop/metrics-ledger.tsv}"

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
    echo "metrics-trend: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
    exit 2
  }
fi
require_py

MODE="summary"; SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) MODE="runs" ;;
    --score) MODE="score" ;;
    --since) SINCE="${2:-}"; [ -n "$SINCE" ] || { echo "metrics-trend: --since needs a date" >&2; exit 2; }; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "metrics-trend: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$LEDGER" ]; then
  echo "metrics-trend: no ledger at $LEDGER — no exec has run here yet (bin/exec.sh writes it)." >&2
  exit 2
fi

"$PY" - "$LEDGER" "$MODE" "$SINCE" <<'PYEOF'
import csv, statistics, sys
ledger, mode, since = sys.argv[1:4]
rows = [r for r in csv.DictReader(open(ledger), delimiter="\t")]
if since:
    rows = [r for r in rows if r["ts"][:10] >= since]
if not rows:
    print("metrics-trend: no rows%s" % (" since " + since if since else "")); sys.exit(0)

def num(v):
    try: return float(v)
    except (TypeError, ValueError): return None

CATS = ["security", "quality", "architecture", "performance", "naming", "design", "other"]
NOT_EXEC = ("module-close", "score-only")      # `metrics-ledger.sh record` rows: a score, not a run
def taken(r):
    return {"module-close": "module close", "score-only": "on demand"}.get(r.get("result", ""), "exec")

if mode == "runs":
    print("ts\tscript\tgate\tresult\telapsed_s\tlint_total\tscore\trestored")
    for r in rows:
        print("\t".join(r.get(k, "") for k in ("ts", "script", "gate", "result", "elapsed_s", "lint_total", "score", "restored")))
    sys.exit(0)

scored = [r for r in rows if num(r.get("score")) is not None]
if mode == "score":
    # `taken` is the last column so a reader of the first ten is unchanged.
    print("ts\toverall\t" + "\t".join(CATS) + "\tviolations\ttaken")
    for r in scored:
        print("\t".join([r["ts"], r["score"]] + [r.get(c, "") for c in CATS] + [r.get("violations", ""), taken(r)]))
    if not scored: print("(no scored rows — no module close has scored yet (bin/module-close.sh <Module>, or bash bin/metrics-ledger.sh record); or no ./mxcli)")
    sys.exit(0)

rows = [r for r in rows if r.get("result") not in NOT_EXEC]
if not rows and not scored:
    print("metrics-trend: no exec rows%s" % (" since " + since if since else "")); sys.exit(0)
n = len(rows)
applied = [r for r in rows if r["result"].startswith("applied")]
clean = [r for r in rows if r["result"] == "applied"]
gate_failed = [r for r in rows if r["result"] in ("gate-failed", "rolled-back", "patch-failed")]
restored = [r for r in rows if r.get("restored") == "1"]
lint_rose = [r for r in rows if r["result"] == "applied-lint-rose"]
blocked = [r for r in rows if r["result"] in ("blocked", "refused")]
el = [num(r["elapsed_s"]) for r in rows if num(r["elapsed_s"]) is not None]

span = rows or scored
print("== metrics-trend: %d execs, %s → %s" % (n, span[0]["ts"][:10], span[-1]["ts"][:10]))
print()
print("outcomes")
def pct(k): return "%d (%d%%)" % (k, round(100.0 * k / n)) if n else "0"
print("  applied, clean gate+lint   %s" % pct(len(clean)))
print("  applied, lint rose         %s" % pct(len(lint_rose)))
print("  applied, other             %s" % pct(len(applied) - len(clean) - len(lint_rose)))
print("  gate failed / rolled back  %s" % pct(len(gate_failed)))
print("  blocked / refused          %s" % pct(len(blocked)))
print("  snapshot restores          %d" % len(restored))
print()
if el:
    half = len(el) // 2
    print("speed (elapsed seconds per exec)")
    print("  median %.0f   worst %.0f   runs %d" % (statistics.median(el), max(el), len(el)))
    if half >= 2:
        a, b = statistics.median(el[:half]), statistics.median(el[half:])
        print("  first half median %.0f → second half median %.0f (%+.0f)" % (a, b, b - a))
    print()
lint = [(r["ts"], num(r["lint_total"])) for r in rows if num(r.get("lint_total")) is not None]
if lint:
    print("lint (total findings, rows where lint ran: %d)" % len(lint))
    print("  first %d (%s) → last %d (%s)   delta %+d" % (lint[0][1], lint[0][0][:10], lint[-1][1], lint[-1][0][:10], lint[-1][1] - lint[0][1]))
    print()
if scored:
    f, l = scored[0], scored[-1]
    where = {}
    for r in scored: where[taken(r)] = where.get(taken(r), 0) + 1
    print("score (mxcli report, 0-100; %d points: %s)" % (len(scored), ", ".join("%d at %s" % (v, k) for k, v in sorted(where.items()))))
    print("  first %s (%s) → last %s (%s)" % (f["ts"][:10], taken(f), l["ts"][:10], taken(l)))
    print("  %-14s %6s → %6s   %s" % ("overall", f["score"], l["score"], "%+.1f" % (num(l["score"]) - num(f["score"]))))
    for c in CATS:
        a, b = num(f.get(c)), num(l.get(c))
        if a is None or b is None: continue
        print("  %-14s %6.0f → %6.0f   %+.0f" % (c, a, b, b - a))
    va, vb = num(f.get("violations")), num(l.get("violations"))
    if va is not None and vb is not None:
        print("  %-14s %6.0f → %6.0f   %+.0f" % ("violations", va, vb, vb - va))
else:
    print("score: no scored rows (taken at each bin/module-close.sh, or on demand: bash bin/metrics-ledger.sh record; per exec only under `Score: every exec`; needs ./mxcli)")
PYEOF
