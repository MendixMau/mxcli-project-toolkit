#!/usr/bin/env bash
# Fixture for wave-2 #2: the decision register (PROJECT.md) resolver.
#
# The two BLOCKING checks — protocol freshness and BRD drift-sync — plus both ✋ decision gates
# and Stage 7 used to read "$PROJECT_DIR/PROJECT.md" unconditionally. On a project whose live
# register is nested at analysis/<name>/PROJECT.md while an abandoned stub survives at the root
# (WMS-App-main: 7 rows vs 42), every one of them graded the file nobody had touched.
#
# Run it against the PRE-fix script too — that is the positive control. Expected on the pre-fix
# script (2ea198c): T1, T2, T3, T5 and T6 fail.
#
#   tests/wave2/test-bug02-register.sh /path/to/gate-check.sh
#
# NOTE: gate-check.sh derives TOOLKIT_DIR from BASH_SOURCE, so a copy under /tmp silently
# changes every protocol-freshness verdict — and T2 depends on freshness PASSING. Keep both
# scripts under the toolkit's bin/.
set -uo pipefail

GATE="${1:?usage: test-bug02-register.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/bug02.XXXXXX)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# Resolve the toolkit ref the SAME WAY gate-check.sh does, so the fixtures can record a
# Toolkit commit that makes Sync PASS. Without that, every stage query exits 1 on staleness
# and the drift assertion below would pass for the wrong reason.
TK="$(cd "$(dirname "$GATE")/.." && pwd)"
if git -C "$TK" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 && git -C "$TK" fetch --quiet 2>/dev/null; then
  REF="$(git -C "$TK" rev-parse --short '@{u}' 2>/dev/null)"
else
  REF="$(git -C "$TK" rev-parse --short HEAD 2>/dev/null)"
fi

# $1 dir name, $2 notes cell for the nested (live) register's Stage-4 row.
# Both registers carry an identical Stage-4 CONFIRMED row and an identical Toolkit commit, so
# Stage 4 passes whichever one is graded. The ONLY difference is the notes cell — which is
# where the UNSYNCED marker lives. That isolates the variable to "which register was read".
mksplit() {
  d="$WORK/$1"; mkdir -p "$d/analysis/Live/knowledge-base" "$d/architecture"
  printf '# plan\n' > "$d/architecture/build-plan.md"
  { printf 'Toolkit commit: %s\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' "$REF"
    printf '| 4 | Build plan | CONFIRMED | superseded root stub |\n'
  } > "$d/PROJECT.md"
  { printf 'Toolkit commit: %s\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' "$REF"
    printf '| 4 | Build plan | CONFIRMED | %s |\n' "$2"
  } > "$d/analysis/Live/PROJECT.md"
  echo "$d"
}

driftline() { "$GATE" --no-html "$1" 2>&1 | grep '^Drift' | head -1; }

echo "== T1: two DIFFERING registers — refuse rather than grade a coin flip =="
P="$(mksplit t1 '[sync: F001.brd.json UNSYNCED]')"
OUT="$("$GATE" --no-html "$P" 2>&1)"; RC=$?
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'differing decision registers'; then
  # Naming BOTH candidates is the point — a refusal you cannot act on is just an outage.
  if printf '%s' "$OUT" | grep -q 'analysis/Live/PROJECT.md' && printf '%s' "$OUT" | grep -qE '/t1/PROJECT.md'; then
    ok "refuses with exit 2 and names both candidates"
  else
    bad "refuses but does not name both candidates: $OUT"
  fi
else
  bad "did not refuse over two differing registers (rc=$RC)"
fi

echo "== T2: the drift-blindness case — a live UNSYNCED row must BLOCK stage 4 =="
# Measured on the pre-fix script: exit 0 over a live '[sync: … UNSYNCED]' row, because the
# grep only ever opened the root stub. GATE_REGISTER names the live one.
P="$(mksplit t2 '[sync: F001.brd.json UNSYNCED]')"
OUT="$(GATE_REGISTER=analysis/Live/PROJECT.md "$GATE" --no-html "$P" 4 2>&1)"; RC=$?
D="$(printf '%s\n' "$OUT" | grep '^Drift' | head -1)"
case "$D" in
  *FAIL*) [ "$RC" -ne 0 ] && ok "live UNSYNCED row is seen and blocks (rc=$RC)" \
                          || bad "drift reported FAIL but the gate exited 0" ;;
  *) bad "graded the wrong register — drift reported: $D (rc=$RC)" ;;
esac

echo "== T3: the same fixture via the CLAUDE.local.md wiring row =="
P="$(mksplit t3 '[sync: F001.brd.json UNSYNCED]')"
{ printf '## Wiring\n\n| Key | Path | Notes |\n|---|---|---|\n'
  printf '| Decision register | `analysis/Live/PROJECT.md` | the live one |\n'
} > "$P/CLAUDE.local.md"
D="$(driftline "$P")"
case "$D" in *FAIL*) ok "wiring row selects the live register" ;;
             *) bad "wiring row ignored — drift reported: $D" ;; esac

echo "== T4: identical copies are NOT ambiguous — no cry-wolf refusal =="
# Reconciled against resolve_stage_file(): either copy grades the same, so refusing is noise.
P="$(mksplit t4 'nothing outstanding')"
cp "$P/PROJECT.md" "$P/analysis/Live/PROJECT.md"
OUT="$("$GATE" --no-html "$P" 2>&1)"; RC=$?
if [ "$RC" = "2" ]; then
  bad "refused over two byte-identical registers"
else
  case "$OUT" in *'Drift (BRD sync): PASS'*) ok "identical copies graded without a refusal" ;;
                 *) bad "no refusal but no drift verdict either: $OUT" ;; esac
fi

echo "== T5: no register at all — the drift gate must not report PASS by absence =="
# DRIFT_STATUS initialised to PASS behind an `[ -f … ]` guard, so a missing register produced
# a green "no unsynced markers" — a positive finding manufactured from nothing.
P="$WORK/t5"; mkdir -p "$P"
D="$(driftline "$P")"
case "$D" in *FAIL*) ok "absent register reports FAIL, not a manufactured PASS" ;;
             *) bad "inert by absence — reported: $D" ;; esac

echo "== T6: Stage 0 resolves the live triage.md, and refuses two differing ones =="
# Pre-fix, check_stage_0 read \$PROJECT_DIR/triage.md only: it graded the root template
# (placeholder sign-off) and never saw the signed nested copy.
P="$WORK/t6"; mkdir -p "$P/analysis/Live/knowledge-base"
printf 'Toolkit commit: %s\n' "$REF" > "$P/PROJECT.md"
printf '# Triage\n\n## Sign-off\n\nConfirmed by: [user] on [date]\n' > "$P/triage.md"
printf '# Triage\n\n## Sign-off\n\nConfirmed by: Maurits Visser on 2026-08-11\n' > "$P/analysis/Live/triage.md"
V="$("$GATE" --no-html "$P" 2>&1 | grep '^Stage 0 ' | head -1)"
case "$V" in
  *FAIL*) case "$V" in *'two different triage.md'*) ok "two differing triage.md files are refused, not silently root-graded" ;;
                       *) bad "fails, but not on the ambiguity: $V" ;; esac ;;
  *) bad "PASSED — graded one of two differing triage.md files: $V" ;;
esac

echo "== T7: a nonexistent GATE_REGISTER selection is an error, not a fallback =="
P="$(mksplit t7 'nothing outstanding')"
OUT="$(GATE_REGISTER=analysis/Nope/PROJECT.md "$GATE" --no-html "$P" 2>&1)"; RC=$?
if [ "$RC" = "2" ] && printf '%s' "$OUT" | grep -q 'selected decision register does not exist'; then
  ok "bad selection refuses with exit 2"
else
  bad "bad GATE_REGISTER silently fell back (rc=$RC)"
fi

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
