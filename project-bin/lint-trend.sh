#!/usr/bin/env bash
# lint-trend.sh — did a lint rule ever fire here, and is its count going down?
#
# Reads the append-only ledger project-bin/lint-gate.sh writes on every run
# (.claude/loop/lint-ledger.tsv: ts, verdict, rule, count, severity, blind) and prints one
# line per rule: runs it fired in, first and last count with dates, best and worst, and how
# many of those runs it was blind (a `_rule` self-check finding — it inspected nothing).
#
# This is the evidence the rollout plan (process/lint-backlog.md) asks for before a warning
# becomes an error: a rule that fired and whose count fell is doing its job; a rule that
# never fired is either clean here or wrong, and the blind column says which. Without this
# file the only trace of a rule's history was lint-baseline.json in git, which records the
# count that was ACCEPTED, not what each run saw.
#
# Usage:
#   project-bin/lint-trend.sh              # one line per rule, worst first
#   project-bin/lint-trend.sh --rule UX001 # every run's count for one rule, oldest first
#   project-bin/lint-trend.sh --runs       # the run rows only (ts, verdict, total, blind)
#
# Exit 0 with output; 2 when there is no ledger yet (the gate has never run here). Read-only.
# Keep bash-3.2 compatible.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER="$ROOT/.claude/loop/lint-ledger.tsv"

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
    echo "lint-trend: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
    exit 2
  }
fi
require_py

MODE="rules"; RULE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rule) MODE="one"; RULE="${2:-}"; [ -n "$RULE" ] || { echo "lint-trend: --rule needs an id" >&2; exit 2; }; shift ;;
    --runs) MODE="runs" ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "lint-trend: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$LEDGER" ]; then
  echo "lint-trend: no ledger at $LEDGER — the lint gate has not run here yet (project-bin/lint-gate.sh writes it)." >&2
  exit 2
fi

LEDGER="$LEDGER" MODE="$MODE" RULE="$RULE" "$PY" - <<'PY'
import csv, os, sys
rows = []
with open(os.environ["LEDGER"]) as f:
    for r in csv.DictReader(f, delimiter="\t"):
        try:
            r["count"] = int(r["count"]); r["blind"] = int(r.get("blind") or 0)
        except ValueError:
            continue
        rows.append(r)
mode, want = os.environ["MODE"], os.environ["RULE"]

if mode == "runs":
    print("%-20s %-18s %6s %s" % ("ts", "verdict", "total", "blind"))
    for r in rows:
        if r["rule"] == "_run":
            print("%-20s %-18s %6d %s" % (r["ts"], r["verdict"], r["count"], "yes" if r["blind"] else ""))
    sys.exit(0)

runs = [r for r in rows if r["rule"] == "_run"]
if mode == "one":
    hits = [r for r in rows if r["rule"] == want]
    if not hits:
        print("%s: never fired in %d run(s) here." % (want, len(runs)))
        sys.exit(0)
    print("%-20s %6s %-8s %s" % ("ts", "count", "severity", "blind"))
    for r in hits:
        print("%-20s %6d %-8s %s" % (r["ts"], r["count"], r["severity"], "yes" if r["blind"] else ""))
    sys.exit(0)

by = {}
for r in rows:
    if r["rule"] == "_run":
        continue
    by.setdefault(r["rule"], []).append(r)
if not by:
    print("No rule has fired in %d run(s) here." % len(runs))
    sys.exit(0)
print("%d run(s), first %s, last %s" % (len(runs), runs[0]["ts"][:10] if runs else "?", runs[-1]["ts"][:10] if runs else "?"))
print("%-10s %-8s %5s %-18s %-18s %5s %5s %s" % ("rule", "severity", "runs", "first", "last", "best", "worst", "blind"))
for rule, hs in sorted(by.items(), key=lambda kv: -kv[1][-1]["count"]):
    counts = [h["count"] for h in hs]
    trend = "" if len(hs) < 2 else ("  down" if counts[-1] < counts[0] else ("  UP" if counts[-1] > counts[0] else "  flat"))
    blind = sum(h["blind"] for h in hs)
    print("%-10s %-8s %5d %-18s %-18s %5d %5d %s%s" % (
        rule, hs[-1]["severity"], len(hs),
        "%d @ %s" % (counts[0], hs[0]["ts"][:10]), "%d @ %s" % (counts[-1], hs[-1]["ts"][:10]),
        min(counts), max(counts), ("%d BLIND" % blind) if blind else "", trend))
PY
