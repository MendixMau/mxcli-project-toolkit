#!/usr/bin/env bash
# test-stage6-report-read.sh — Stage 6 reads docs/report.json, it does not just find it (#719).
# usage: test-stage6-report-read.sh /path/to/gate-check.sh
#
# Golden input: tests/wave2/fixtures/stage6-report/report.json — rows captured verbatim from a real
# run (see PROVENANCE.txt there). Positive control: the pre-fix script prints PASS for every case.
#   T1  a report with a `fail` and `fault` rows            -> FAIL naming the counts
#   T2  the same report cut to its pass rows               -> PASS, no warning when the .mpr is older
#   T3  green rows but the .mpr saved after run.startedAt  -> PASS carrying a WARNING (option 1:
#       staleness warns, it does not block)
#   T4  a report whose run is aborted                      -> FAIL
#   T5  a legacy test-report.html with no report.json      -> unchanged PASS (no verdicts to read)
set -uo pipefail
GATE="${1:?usage: test-stage6-report-read.sh /path/to/gate-check.sh}"
FIX="$(cd "$(dirname "$0")" && pwd)/fixtures/stage6-report/report.json"
WORK="$(mktemp -d /tmp/stage6.XXXXXX)"; PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/docs/verification" "$d/reports/ui-reviews"
  printf 'Toolkit commit: none\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' > "$d/PROJECT.md"
  echo '<html>r</html>' > "$d/docs/verification/report.html"
  echo '<html>r</html>' > "$d/reports/ui-reviews/ui-review-2026-11-10.html"
  : > "$d/App.mpr"; touch -d '2026-11-10 02:02:00' "$d/App.mpr"   # saved before startedAt 02:06:54
  echo "$d"
}
v() { "$GATE" --no-html "$1" 6 2>&1 | grep '^Stage 6 ' | head -1; }

echo "== T1: fail/fault rows are FAIL, not green-by-existence =="
P="$(mkproj t1)"; cp "$FIX" "$P/docs/report.json"
V="$(v "$P")"
case "$V" in *FAIL*'1 fail, 2 fault'*) ok "FAIL names the counts" ;; *) bad "T1: $V" ;; esac

echo "== T2: pass rows only, .mpr older than the run =="
P="$(mkproj t2)"; jq '.checks|=map(select(.verdict=="pass"))' "$FIX" > "$P/docs/report.json"
V="$(v "$P")"
case "$V" in *PASS*'3 of 3 checks pass'*) case "$V" in *WARNING*) bad "T2 warned: $V" ;; *) ok "green fresh report passes" ;; esac ;; *) bad "T2: $V" ;; esac

echo "== T3: .mpr saved after the run -> PASS with a warning =="
touch -d '2026-11-10 03:00:00' "$P/App.mpr"
V="$(v "$P")"
case "$V" in *PASS*WARNING*'predates the last .mpr save'*) ok "stale report warns" ;; *) bad "T3: $V" ;; esac

echo "== T4: aborted run =="
P="$(mkproj t4)"; jq '.checks|=map(select(.verdict=="pass"))|.aborted="signal SIGINT"' "$FIX" > "$P/docs/report.json"
V="$(v "$P")"
case "$V" in *FAIL*aborted*) ok "aborted run FAILs" ;; *) bad "T4: $V" ;; esac

echo "== T5: legacy test-report.html only =="
P="$(mkproj t5)"; rm -rf "$P/docs"; echo '<html>r</html>' > "$P/test-report.html"
V="$(v "$P")"
case "$V" in *PASS*) ok "legacy surface unchanged" ;; *) bad "T5: $V" ;; esac

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"; [ "$FAIL" -eq 0 ]
