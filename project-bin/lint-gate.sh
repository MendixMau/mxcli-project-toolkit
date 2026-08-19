#!/usr/bin/env bash
# lint-gate.sh — run mxcli lint on OUR modules and fail only when a rule gets worse.
#
# Why a ratchet and not a threshold:
#   This project has ~500 pre-existing findings and 0 errors. Promoting severities to
#   "error" would fail every gate forever and the gate would be switched off within a
#   day — which is exactly how lint died here the first time. Instead we freeze today's
#   per-rule counts as a baseline and fail only on an INCREASE. Debt is tolerated;
#   adding to it is not.
#
# READ-ONLY. `mxcli lint` does not write to the .mpr (verified by md5 before/after,
# 2026-08-14). This script therefore does not need RULE 1 approval, unlike exec/test.
#
# Usage:
#   bin/lint-gate.sh                    # check against baseline; exit 1 if any rule rose
#   bin/lint-gate.sh --update-baseline  # accept current counts as the new baseline
#   bin/lint-gate.sh --full             # ignore the vendor exclusion (rarely useful)
#
# Exit codes: 0 clean or unchanged · 1 a rule increased · 2 could not run

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

# Python is resolved, not assumed: a bare `python3` is the Store alias stub on Windows and a
# prompt-only stub on a Mac without the CLT. Both satisfy `command -v` and neither runs anything.
#
# require_py lives in _common.sh, but this script MUST NOT assume a sibling of its own vintage.
# sync-project.sh installs a missing _common.sh and REPORTS a locally-modified one rather than
# overwriting it — deliberately, since projects harden their crash net. So every project that
# has already tuned _common.sh would receive this script and have it die on line 1 with
# "require_py: command not found". Measured on WMS-Demo-main before this fallback existed.
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
    echo "lint-gate: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
    exit 2
  }
fi
require_py

# The .mpr is discovered, not hardcoded. A per-project default here is how this script
# was previously un-promotable: it named WMS-Demo.mpr and silently linted nothing anywhere
# else (mxcli exits 0 on a missing project, so the gate reported a clean PASS).
if [ -z "${MPR:-}" ]; then
  MPR="$(ls "$ROOT"/*.mpr 2>/dev/null | head -1)"
  MPR="$(basename "${MPR:-}")"
fi
if [ -z "$MPR" ] || [ ! -f "$ROOT/$MPR" ]; then
  echo "lint-gate: no .mpr found in $ROOT — set MPR=<name>.mpr" >&2
  exit 2
fi
if [ "$(ls "$ROOT"/*.mpr 2>/dev/null | wc -l | tr -d " ")" -gt 1 ] && [ -z "${MPR_EXPLICIT:-}" ]; then
  echo "lint-gate: several .mpr files here; linting $MPR. Set MPR=<name>.mpr to choose." >&2
fi
VENDOR_FILE="$ROOT/.claude/lint-vendor-modules.txt"
BASELINE="$ROOT/.claude/lint-baseline.json"
OUT="${TMPDIR:-/tmp}/lint-gate-$$.json"
trap 'rm -f "$OUT"' EXIT

UPDATE=0
FULL=0
for a in "$@"; do
  case "$a" in
    --update-baseline) UPDATE=1 ;;
    --full) FULL=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "lint-gate: unknown argument '$a'" >&2; exit 2 ;;
  esac
done

[ -x ./mxcli ] || { echo "lint-gate: ./mxcli not found in $ROOT" >&2; exit 2; }
[ -e "$MPR" ]  || { echo "lint-gate: $MPR not found" >&2; exit 2; }

# Build the --exclude list from the vendor file (comments and blanks stripped).
EXCLUDE=""
if [ "$FULL" -eq 0 ] && [ -f "$VENDOR_FILE" ]; then
  EXCLUDE="$(grep -v '^[[:space:]]*#' "$VENDOR_FILE" | grep -v '^[[:space:]]*$' | paste -sd, -)"
fi

# LINT_JSON=<file> skips mxcli entirely and reads pre-captured lint output. This makes
# the comparison logic testable against fixtures with no .mpr, no mxcli and no catalog
# (a full cold run costs ~12 min on a project whose catalog needs rebuilding).
if [ -n "${LINT_JSON:-}" ]; then
  [ -f "$LINT_JSON" ] || { echo "lint-gate: LINT_JSON=$LINT_JSON not found" >&2; exit 2; }
  echo "==> using captured lint output: $LINT_JSON"
  cp "$LINT_JSON" "$OUT"
else
  echo "==> linting $MPR${EXCLUDE:+ (excluding vendor modules)}"
  # First run on a cold catalog can take MINUTES (measured: 717s on VB-USI, 2s warm) --
  # the catalog rebuild dominates, not the lint. Do not treat a slow first run as a hang.
  if [ -n "$EXCLUDE" ]; then
    ./mxcli lint -p "$MPR" -e "$EXCLUDE" --format json > "$OUT" 2>/dev/null
  else
    ./mxcli lint -p "$MPR" --format json > "$OUT" 2>/dev/null
  fi
fi
[ -s "$OUT" ] || { echo "lint-gate: lint produced no output" >&2; exit 2; }

BASELINE="$BASELINE" OUT="$OUT" UPDATE="$UPDATE" "$PY" - <<'PY'
import json, os, sys, collections

out_path  = os.environ["OUT"]
base_path = os.environ["BASELINE"]
update    = os.environ["UPDATE"] == "1"

# mxcli prints a plaintext progress banner before the JSON; slice from the first brace.
raw = open(out_path).read()
try:
    data = json.loads(raw[raw.index("{"):])
except (ValueError, IndexError):
    print("lint-gate: could not parse lint JSON", file=sys.stderr)
    sys.exit(2)

viol = data.get("violations") or []
counts = collections.Counter(v["ruleId"] for v in viol)
sev    = {v["ruleId"]: v["severity"] for v in viol}

# A rule that did not actually run is a false PASS, not a clean result. Two forms,
# and keying on only the first was a real bug in this script:
#   1. Self-reported blindness: CONV010/CONV020 emit module="_rule" when they inspect
#      documents but activities_for() hands back nothing.
#   2. A hard Starlark crash: mxcli reports these as severity=error with an EMPTY
#      module and a "Starlark rule error:" message prefix -- NOT as "_rule". Observed
#      on TFC-TCXGraphPOC 2026-08-14: CONV018 died with '"page" struct has no .widgets
#      attribute'. Keying only on "_rule" meant the gate baselined a crashed rule as a
#      legitimate error-severity finding and then reported PASS while CONV018 saw
#      nothing at all. A crashed rule must never be ratcheted.
blind = [v for v in viol
         if v.get("module") == "_rule"
         or "Starlark rule error" in (v.get("message") or "")]

# Crashed rules are excluded from the ratchet counts entirely: baselining a crash
# would make the crash the expected state.
crashed = {v["ruleId"] for v in viol if "Starlark rule error" in (v.get("message") or "")}
if crashed:
    viol = [v for v in viol if v["ruleId"] not in crashed]
    counts = collections.Counter(v["ruleId"] for v in viol)

if update:
    json.dump({"counts": dict(sorted(counts.items())),
               "total": len(viol),
               "note": "Per-rule finding counts on OUR modules. Gate fails when any rises."},
              open(base_path, "w"), indent=2)
    open(base_path, "a").write("\n")
    print("==> baseline written: %d findings across %d rules" % (len(viol), len(counts)))
    for r, c in counts.most_common():
        print("      %5d  %-8s %s" % (c, sev[r], r))
    sys.exit(0)

if not os.path.exists(base_path):
    print("lint-gate: no baseline at %s — run: bin/lint-gate.sh --update-baseline" % base_path,
          file=sys.stderr)
    sys.exit(2)

base = json.load(open(base_path)).get("counts", {})
rose, fell = [], []
for r in sorted(set(counts) | set(base)):
    now, was = counts.get(r, 0), base.get(r, 0)
    if now > was: rose.append((r, was, now))
    elif now < was: fell.append((r, was, now))

print("==> %d findings on our modules (baseline %d)" % (len(viol), sum(base.values())))

if blind:
    print("\n!! A RULE COULD NOT READ THE MODEL — a clean result here means nothing:")
    for v in blind:
        print("   %s" % v["message"][:160])

if fell:
    print("\n   improved:")
    for r, was, now in fell:
        print("      %-8s %d -> %d" % (r, was, now))

# COLLAPSE GUARD. A ratchet that only watches for increases treats "lint saw nothing"
# as the best possible result. If the catalog is empty, the module filter is wrong, or
# the .star rules failed to load, every count drops to zero and the gate prints
# "PASS -- 28 rule(s) improved". Silence is not success. A drop this broad is a
# malfunction until proven otherwise; a genuine cleanup that large is deliberate and
# its author can re-baseline explicitly.
zeroed = [r for r, was, now in fell if now == 0 and was > 0]
base_total = sum(base.values())
collapsed = (len(zeroed) >= 5 and base_total > 0
             and len(viol) < base_total * 0.5)

if collapsed:
    print("\nFAIL — IMPLAUSIBLE DROP. %d rules went to zero and the total fell %d -> %d."
          % (len(zeroed), base_total, len(viol)))
    print("       This is what a broken lint run looks like, not a cleanup. Check that")
    print("       the catalog is populated, the .star rules loaded, and the module")
    print("       filter is not excluding everything, before you believe this.")
    print("       Rules zeroed: %s" % ", ".join(zeroed[:12]) + (" ..." if len(zeroed) > 12 else ""))
    print("       If the cleanup is real, re-baseline deliberately: --update-baseline")
    sys.exit(1)

if not rose:
    print("\nPASS — nothing got worse.")
    if fell:
        print("       %d rule(s) improved. Run --update-baseline to lock the gain in." % len(fell))
    sys.exit(1 if blind else 0)

print("\nFAIL — %d rule(s) got worse:\n" % len(rose))
for r, was, now in rose:
    print("   %-8s %-8s %d -> %d  (+%d)" % (r, sev.get(r, "?"), was, now, now - was))
    for v in [x for x in viol if x["ruleId"] == r][:3]:
        print("        %s | %s" % (v.get("module") or "(project)", v["message"][:120]))
    print()
sys.exit(1)
PY
