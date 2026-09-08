#!/usr/bin/env bash
# test-source-sufficiency-gate.sh — pin that Stage 0 actually blocks when nobody ran
# bin/source-sufficiency.sh, and does not block once it has been.
#
# bin/source-sufficiency.sh existed for a whole project before anything checked it ran. This
# is the "instrument built, never wired to a gate" failure mode Open Questions used to have —
# proven here the same way test-bug03-gates.sh proves the other gates: run the real
# gate-check.sh end to end, not a unit test of a helper function.
#
#   tests/wave2/test-source-sufficiency-gate.sh /path/to/gate-check.sh

set -uo pipefail

GATE="${1:?usage: test-source-sufficiency-gate.sh /path/to/gate-check.sh}"
TOOLKIT="$(cd "$(dirname "$GATE")/.." && pwd)"
SS="$TOOLKIT/bin/source-sufficiency.sh"
WORK="$(mktemp -d /tmp/suffgate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

# A minimal Stage-0-clean project: signed-off triage.md, so any Stage 0 FAIL below is
# attributable to source-sufficiency alone, not to the pre-existing triage.md check.
mkproj() {
  d="$WORK/$1"; mkdir -p "$d/analysis" "$d/sources"
  printf 'source stub\n' > "$d/sources/req.md"
  {
    printf '# Triage\n\n## Sign-off\n\nConfirmed by: Test User on 2026-08-19\n'
  } > "$d/triage.md"
  echo "$d"
}

# rubric <dir> <rating-for-all>
rubric() {
  d=$1; r=$2
  mkdir -p "$d/analysis"
  {
    printf '{"assessedAt":"2026-01-01","sources":["req.md"],'
    printf '"inventory":[{"path":"req.md","bytes":10,"kind":"docs","answers":['
    printf '"actors","domain","processes","rules","ui","integrations","nfr","tenancy",'
    printf '"security_model","data_migration"],"statedScope":"","components":[]}],'
    printf '"dimensions":{'
    first=1
    for k in actors domain processes rules ui integrations nfr tenancy security_model data_migration; do
      [ $first -eq 1 ] || printf ','
      first=0
      printf '"%s":{"demands":"d","rating":"%s","evidence":"e","consequence":"c"}' "$k" "$r"
    done
    printf '},"conflicts":[],"landmines":[]}'
  } > "$d/analysis/source-sufficiency.json"
}

stage0_out() { "$GATE" --no-html "$1" 0 2>&1; }

# T1/T2 asserted a non-zero exit until 2026-09-02. gate-check.sh loosened this to ADVISORY on
# 2026-08-20 ("WARNS, does not block" — see the source-sufficiency block near the exit logic:
# Stage 0's own verdict already fails on an unsigned triage.md, so blocking here added no
# safety and made a Stage 0 query print a refusal on exactly the projects least able to read
# one). The fixture kept the old assertion and failed on master for two weeks unnoticed; found
# when the source-ledger work ran it. What IS pinned now: the sufficiency line reads FAIL and
# the advisory names it — a missing rubric is never reported as assessed.
echo "== T1: no rubric at all -> sufficiency line FAILS, Stage 0 advises (does not block) =="
P="$(mkproj t1-no-rubric)"
OUT="$(stage0_out "$P")"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exits zero (advisory, 2026-08-20 decision)"; else bad "exits zero (advisory)" "got rc=$RC"; fi
case "$OUT" in *"Source sufficiency (assessed?): FAIL"*) ok "sufficiency line reads FAIL" ;; *) bad "sufficiency line reads FAIL" "$OUT" ;; esac
case "$OUT" in
  *"source sufficiency"*|*"Source sufficiency"*) ok "mentions source sufficiency" ;;
  *) bad "mentions source sufficiency" "$OUT" ;;
esac

echo "== T2: rubric initialised but never rated -> sufficiency line FAILS, Stage 0 advises =="
P="$(mkproj t2-unrated)"
[ -x "$SS" ] && "$SS" init "$P" --sources "$P/sources" >/dev/null 2>&1
OUT="$(stage0_out "$P")"; RC=$?
if [ "$RC" -eq 0 ]; then ok "exits zero on unrated rubric (advisory)"; else bad "exits zero on unrated rubric (advisory)" "got rc=$RC"; fi
case "$OUT" in *"Source sufficiency (assessed?): FAIL"*) ok "unrated rubric reads FAIL, never assessed" ;; *) bad "unrated rubric reads FAIL" "$OUT" ;; esac

echo "== T3: rubric fully rated, even thin (absent everywhere) -> Stage 0 does NOT block on this =="
P="$(mkproj t3-thin)"
rubric "$P" "absent"
OUT="$(stage0_out "$P")"
SUFF_LINE="$(printf '%s\n' "$OUT" | grep '^Source sufficiency')"
case "$SUFF_LINE" in
  *"FAIL"*) bad "thin-but-assessed must not FAIL the sufficiency line" "$SUFF_LINE" ;;
  *"PASS"*) ok "thin-but-assessed does not FAIL the sufficiency line" ;;
  *) bad "sufficiency line missing or malformed" "$SUFF_LINE" ;;
esac

echo "== T4: rubric fully rated and thick -> Stage 0 does NOT block on this =="
P="$(mkproj t4-thick)"
rubric "$P" "specified"
OUT="$(stage0_out "$P")"
SUFF_LINE="$(printf '%s\n' "$OUT" | grep '^Source sufficiency')"
case "$SUFF_LINE" in
  *"FAIL"*) bad "thick, assessed rubric must not FAIL the sufficiency line" "$SUFF_LINE" ;;
  *"PASS"*) ok "thick, assessed rubric does not FAIL the sufficiency line" ;;
  *) bad "sufficiency line missing or malformed" "$SUFF_LINE" ;;
esac

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
