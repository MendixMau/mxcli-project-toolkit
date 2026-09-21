#!/usr/bin/env bash
# Fixture: the "## Current stage" line in PROJECT.md is a readout gate-check.sh writes on a
# full run, from the verdicts it just produced — never something an agent has to remember.
#
# Before 2026-09-14 the line init-project.sh wrote ("**Stage P — Kickoff**, in progress.")
# was never touched again by anything: every token-path A/B hand-in (nine projects, gates P–4
# passed) still read Stage P. Run this against the pre-fix script as the positive control —
# T1, T2, T5 and T6 fail there.
#
#   tests/wave2/test-stage-header.sh /path/to/gate-check.sh
#
# NOTE: gate-check.sh derives TOOLKIT_DIR from BASH_SOURCE; keep it under the toolkit's bin/.
set -uo pipefail

GATE="${1:?usage: test-stage-header.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/stagehdr.XXXXXX")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

mkproj() { # mkproj <name> — a flat project with the init-project.sh header shape
  d="$WORK/$1"; mkdir -p "$d/analysis/Live/knowledge-base"
  cat > "$d/PROJECT.md" <<'MD'
# PROJECT.md — t Decision Register

## Current stage

**Stage P — Kickoff**, in progress.

Toolkit commit: none

<!-- Where this project joins the pipeline: nothing recorded. -->

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
MD
  echo "$d"
}
answered_intake() { # answered_intake <proj> — every intake question carries a marker → Stage P PASS
  printf '\n## 1. Where is the source?\n\nAnswered (CONFIRMED): src/.\n\n## 2. Which ERP?\n\nAnswered (ASSUMED): none.\n' > "$1/intake.md"
}
header() { awk '/^## Current stage/ { f = 1; next } f && /^\*\*/ { print; exit }' "$1/PROJECT.md"; }
run_full() { "$GATE" "$1" >/dev/null 2>&1; }

echo "== T1: a fresh project gets the derived line, still at Stage P =="
P="$(mkproj t1)"; run_full "$P"; H="$(header "$P")"
case "$H" in
  "**Stage P — Kickoff**, in progress — gates passed: none yet (derived by gate-check on "*) ok "Stage P, none passed, stamped: $H" ;;
  *) bad "unexpected header: $H" ;;
esac

echo "== T2: Stage P passes → header advances to Stage 0 and lists P as passed =="
P="$(mkproj t2)"; answered_intake "$P"; run_full "$P"; H="$(header "$P")"
case "$H" in
  "**Stage 0 — "*"**, in progress — gates passed: P (derived"*) ok "advanced: $H" ;;
  *) bad "did not advance to Stage 0: $H" ;;
esac

echo "== T3: a stage query is read-only — the header is not written =="
P="$(mkproj t3)"; answered_intake "$P"
"$GATE" "$P" 0 >/dev/null 2>&1; H="$(header "$P")"
[ "$H" = "**Stage P — Kickoff**, in progress." ] && ok "stage query left the header alone" || bad "stage query rewrote it: $H"

echo "== T4: idempotent — a second full run leaves the file byte-identical =="
P="$(mkproj t4)"; answered_intake "$P"; run_full "$P"; cp "$P/PROJECT.md" "$WORK/t4.first"; run_full "$P"
cmp -s "$P/PROJECT.md" "$WORK/t4.first" && ok "second run made no change" || bad "second run changed PROJECT.md"

echo "== T5: --adopt 3 waives 0–2 → header lands on Stage 3 with P, 0, 1, 2 passed =="
P="$(mkproj t5)"; answered_intake "$P"
"$GATE" --adopt 3 --reason "joined late" "$P" >/dev/null 2>&1; run_full "$P"; H="$(header "$P")"
case "$H" in
  "**Stage 3 — "*"gates passed: P, 0, 1, 2 (derived"*) ok "adoption reflected: $H" ;;
  *) bad "adoption not reflected: $H" ;;
esac

echo "== T6: a manual stage holds the position until a later stage has something in it =="
P="$(mkproj t6)"; answered_intake "$P"
"$GATE" --adopt 5 --reason "joined at build" "$P" >/dev/null 2>&1; run_full "$P"; H="$(header "$P")"
case "$H" in
  "**Stage 5 — Build**, in progress (manual gate"*) ok "held at Stage 5 (Build): $H" ;;
  *) bad "did not hold at the manual stage: $H" ;;
esac

echo "== T7: no '## Current stage' section → nothing is written =="
P="$(mkproj t7)"; sed -i.bak 's/^## Current stage/## Position/' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
cp "$P/PROJECT.md" "$WORK/t7.before"; run_full "$P"
cmp -s "$P/PROJECT.md" "$WORK/t7.before" && ok "untouched without the section" || bad "wrote into a register without the section"

echo "== T8: a hand-written header is never replaced — the disagreement is printed instead =="
P="$(mkproj t8)"; answered_intake "$P"
sed -i.bak 's/^\*\*Stage P — Kickoff\*\*, in progress\.$/**Stage 5 verdict: COMPLETE** — all stages pass, signed off by the client./' "$P/PROJECT.md"; rm -f "$P/PROJECT.md.bak"
OUT="$("$GATE" "$P" 2>&1)"; H="$(header "$P")"
[ "$H" = "**Stage 5 verdict: COMPLETE** — all stages pass, signed off by the client." ] && ok "hand-written line untouched" || bad "hand-written line was rewritten: $H"
case "$OUT" in *"hand-written and left alone"*"gates derive: Stage 0"*) ok "disagreement printed with the derived position" ;; *) bad "no disagreement note in output" ;; esac

echo "== T9: the readout's own line keeps advancing (derived → adopt 3) =="
P="$(mkproj t9)"; answered_intake "$P"; run_full "$P"
"$GATE" --adopt 3 --reason "joined late" "$P" >/dev/null 2>&1; run_full "$P"; H="$(header "$P")"
case "$H" in "**Stage 3 — "*"(derived"*) ok "derived line advanced: $H" ;; *) bad "derived line did not advance: $H" ;; esac

echo "== T10 (issue #108): a stage query for the STAGE THE HEADER ALREADY NAMES, once it passes, advances the header =="
P="$(mkproj t10)"; answered_intake "$P"
"$GATE" "$P" P >/dev/null 2>&1; H="$(header "$P")"
case "$H" in
  "**Stage 0 — "*"gates passed: P (derived"*) ok "single-stage query for P advanced the header: $H" ;;
  *) bad "single-stage query for the currently-named, now-passing stage did not advance it: $H" ;;
esac

echo "== T11 (issue #108): a stage query for the currently-named stage that has NOT resolved PASS/WAIVED yet still leaves the header alone =="
P="$(mkproj t11)"
"$GATE" "$P" P >/dev/null 2>&1; H="$(header "$P")"
[ "$H" = "**Stage P — Kickoff**, in progress." ] && ok "unresolved stage query left the header alone" || bad "unresolved stage query rewrote the header: $H"

echo "== T12 (issue #108): a query for some OTHER stage than the one the header names — even if that other stage passes — still leaves the header alone (T3 covers the still-open case; this covers the passing one) =="
P="$(mkproj t12)"; answered_intake "$P"; run_full "$P"
# header now names Stage 0 (P passed). Adopt+waive stage 3 so a query for it resolves WAIVED,
# then query stage 3 specifically — the header still names Stage 0, not Stage 3.
"$GATE" --waive 3 --reason "not applicable" "$P" >/dev/null 2>&1
H_BEFORE="$(header "$P")"
"$GATE" "$P" 3 >/dev/null 2>&1; H_AFTER="$(header "$P")"
[ "$H_AFTER" = "$H_BEFORE" ] && ok "query for an unrelated (non-named) stage left the header alone" || bad "query for an unrelated stage changed the header: $H_BEFORE -> $H_AFTER"

rm -rf "$WORK"
echo ""
echo "test-stage-header: $PASS ok, $FAIL failed"
[ "$FAIL" -eq 0 ]
