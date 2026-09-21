#!/usr/bin/env bash
# Fixture for bin/render-routing.sh — added alongside its two new --check failure modes
# (BAD_TIER's sibling BAD_AGENT, and the LC_ALL=C word-count fix) because no file in tests/
# exercised the script at all before this.
#
# T1: a TSV row whose agents column holds a token that is not "all" and not a real agent stub
#     name (e.g. "any") must make `--check` exit non-zero and name the offending row — the
#     "routed into no agent stub" failure BAD_AGENT exists to catch (see render-routing.sh's
#     own incident note, 2026-09-16: deploy-to-sandbox shipped with agents=any and --check
#     reported "all skills routed" over a skill in 0 of 6 agent stubs).
# T2: the baseline word count `--check` reports must be identical whether the invoking shell's
#     locale is C or C.UTF-8 — the whole point of forcing LC_ALL=C on every `wc -w` inside the
#     script (2026-09-19: a PR passed locally under an unset LANG and failed in CI, which runs
#     C.UTF-8, by 1,427 words no file contained).
#
# Runs entirely against a scratch COPY of the toolkit tree — never the real checkout — so T1's
# deliberately-broken row never touches bin/lib/skill-routing.tsv on disk.

set -uo pipefail

RR="${1:?usage: test-render-routing.sh /path/to/render-routing.sh}"
case "$RR" in /*) ;; *) RR="$PWD/$RR" ;; esac
TK="$(cd "$(dirname "$RR")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/render-routing-fixture.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# A scratch copy of the whole tree (minus VCS metadata) — render-routing.sh derives its own
# ROOT from its own location (`$SCRIPT_DIR/..`), so testing against a mutated table means
# running a mutated COPY of the script's own repo, not pointing env vars at one.
COPY="$WORK/copy"
mkdir -p "$COPY"
( cd "$TK" && tar -cf - --exclude='.git' . ) | ( cd "$COPY" && tar -xf - )

echo "== T1: an unknown agents-column token fails --check and names the row =="
TSV="$COPY/bin/lib/skill-routing.tsv"
[ -f "$TSV" ] || { bad "fixture setup: $TSV missing from scratch copy"; TSV=""; }
if [ -n "$TSV" ]; then
  printf 'zzz-test-bad-agent-fixture\tskills/query-the-model.md\ttest fixture row — never shipped\tany\t-\tondemand\treference\n' >> "$TSV"
  OUT="$("$COPY/bin/render-routing.sh" --check 2>&1)"; RC=$?
  if [ "$RC" -ne 0 ]; then
    ok "exit non-zero on unknown agent token (exit $RC)"
  else
    bad "exit 0 despite an unknown agents-column token" "$OUT"
  fi
  if printf '%s' "$OUT" | grep -q 'UNKNOWN AGENT'; then
    ok "output names the failure as UNKNOWN AGENT"
  else
    bad "output does not mention UNKNOWN AGENT" "$OUT"
  fi
  if printf '%s' "$OUT" | grep -q 'zzz-test-bad-agent-fixture'; then
    ok "output names the offending row by its name column"
  else
    bad "output does not name the offending row" "$OUT"
  fi
  if printf '%s' "$OUT" | grep -q 'bad token: any'; then
    ok "output names the bad token itself"
  else
    bad "output does not name the bad token" "$OUT"
  fi
fi

echo "== T2: baseline word count is identical under LC_ALL=C and LC_ALL=C.UTF-8 =="
# A pristine second copy — T1's copy now carries a deliberately-broken row and would fail
# --check for an unrelated reason, which would make this assertion meaningless.
COPY2="$WORK/copy2"
mkdir -p "$COPY2"
( cd "$TK" && tar -cf - --exclude='.git' . ) | ( cd "$COPY2" && tar -xf - )

OUT_C="$(cd "$COPY2" && LC_ALL=C LANG=C bash bin/render-routing.sh --check 2>&1)"
WORDS_C="$(printf '%s' "$OUT_C" | sed -n 's/.*Baseline: \([0-9]\{1,\}\) words.*/\1/p')"
OUT_UTF8="$(cd "$COPY2" && LC_ALL=C.UTF-8 LANG=C.UTF-8 bash bin/render-routing.sh --check 2>&1)"
WORDS_UTF8="$(printf '%s' "$OUT_UTF8" | sed -n 's/.*Baseline: \([0-9]\{1,\}\) words.*/\1/p')"

if [ -z "$WORDS_C" ] || [ -z "$WORDS_UTF8" ]; then
  bad "could not read a baseline word count from --check output under both locales" "LC_ALL=C: $OUT_C
LC_ALL=C.UTF-8: $OUT_UTF8"
elif [ "$WORDS_C" = "$WORDS_UTF8" ]; then
  ok "baseline word count identical across locales ($WORDS_C words)"
else
  bad "baseline word count differs by locale: C=$WORDS_C C.UTF-8=$WORDS_UTF8"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
