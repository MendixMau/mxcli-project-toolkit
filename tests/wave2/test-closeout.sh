#!/usr/bin/env bash
# Fixture for the stage close-out block (bin/lib/closeout.sh, gate-check.sh --closeout), the
# opt-in artifact rows (artifact-manifest.tsv absence=optin) and the plain-words paragraph on
# every stage-query outcome. Added 2026-09-02.
#
#   tests/wave2/test-closeout.sh /path/to/gate-check.sh
#
# Field run the same day: bin/gate-check.sh --closeout <TFC-TCXGraphPOC> {2,3,4} — Stage 4
# surfaced a PENDING coverage ledger, 2 UNSYNCED markers and 5 open questions whose status
# words ("TO", "REVERSED", "PARKED") sit outside the closed vocabulary; Stage 3 tracked the
# hand-written architecture/workflow-definition.md as an opt-in-by-deed. Those are the shapes
# asserted here on a synthetic register.
set -uo pipefail
GATE="${1:?usage: test-closeout.sh /path/to/gate-check.sh}"
LIB="$(cd "$(dirname "$GATE")" && pwd)/lib"
WORK="$(mktemp -d /tmp/closeout.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
export MXTK_NO_FETCH=1

mkproj() {
  d="$WORK/$1"; mkdir -p "$d/architecture" "$d/design/wireframes" "$d/knowledge-base/brd"
  cat > "$d/PROJECT.md" <<'MD'
# PROJECT.md — fixture
Toolkit commit: none
Entry mode: requirements-driven

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| 1 | Guess about volumes | ASSUMED | risk: index sizing |
| 3 | Module structure: one module | CONFIRMED 2026-09-02 | matches the BRD |
| 3 | Cross-module strategy: none | CONFIRMED | single module |
| 3 | Example data review | PENDING | user has a sheet |

## Open questions

| # | Question | Raised at | Status |
|---|---|---|---|
| Q1 | Where does the BOM live | Stage 1 | ANSWERED 2026-09-01: constant |
| Q2 | Who wires MCP | Stage 1 | Deferred to build |

## Assumptions (ASSUMED, unresolved)

None yet.
MD
  # One clean BRD: enforce_open_questions exits 2 on a project with no BRD at all ("nothing
  # examined is not a pass"), which is the pre-existing rule — the PASS path here needs it.
  printf '{"openQuestions":[]}\n' > "$d/knowledge-base/brd/F001.brd.json"
  echo "$d"
}

echo "== T1: --closeout prints only the block, exits 0 even on a failing stage =="
P="$(mkproj t1)"
printf '# fit-gap\nrow\n' > "$P/architecture/fit-gap.md"
OUT="$("$GATE" --closeout "$P" 3 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC"
case "$(printf '%s' "$OUT" | head -1)" in "## Stage 3 close-out"*) ok "first line is the block heading" ;; *) bad "block not first: $(printf '%s' "$OUT" | head -1)" ;; esac
case "$OUT" in *"Artifact "*"PENDING — owed"*) bad "run output leaked into the block" ;; *) ok "evaluation output captured, not printed" ;; esac

echo "== T2: decisions of THIS stage only, with counts; non-CONFIRMED status words surfaced =="
case "$OUT" in *"stage 3: 2 CONFIRMED, 0 ASSUMED, 1 with another status word"*) ok "counts" ;; *) bad "counts missing: $(printf '%s' "$OUT" | grep 'Decisions made')" ;; esac
case "$OUT" in *"- PENDING · Example data review"*) ok "PENDING row listed" ;; *) bad "PENDING row not listed" ;; esac
case "$OUT" in *"Guess about volumes"*"CONFIRMED · Module"*) bad "stage-1 row listed under stage 3" ;; *) ok "other stages' rows excluded from the decisions list" ;; esac

echo "== T3: carried forward — open question with a loose status word, ASSUMED from any stage =="
case "$OUT" in *"Q2 (DEFERRED) — Who wires MCP"*) ok "open question carried with its status word" ;; *) bad "open question not carried" ;; esac
case "$OUT" in *"Q1 "*"Where does the BOM"*) bad "ANSWERED question carried" ;; *) ok "ANSWERED question not carried" ;; esac
case "$OUT" in *"Decisions still ASSUMED (any stage"*"stage 1 · Guess about volumes"*) ok "ASSUMED decision carried" ;; *) bad "ASSUMED not carried" ;; esac

echo "== T4: artifacts of the stage, plain-words paragraph under the verdict =="
case "$OUT" in *"✅ \`fit-gap\`"*) ok "present artifact ticked" ;; *) bad "fit-gap not ticked" ;; esac
case "$OUT" in *"⬜ \`wireframes\` — PENDING"*) ok "absent artifact pending" ;; *) bad "wireframes not pending" ;; esac
case "$OUT" in *"**In plain words:**"*"The gate needs:"*) ok "plain words present" ;; *) bad "plain words missing" ;; esac
case "$OUT" in *"still missing for this stage: "*"one wireframe per screen"*) ok "missing artifacts named in plain words" ;; *) bad "plain missing list absent" ;; esac

echo "== T5: next-stage open — purpose, skills, optional artifacts on offer =="
case "$OUT" in *"## Next: Stage 4 — Build Plan ✋"*) ok "next stage heading" ;; *) bad "next heading missing" ;; esac
case "$OUT" in *"skills/brd-to-build-plan.md"*) ok "governing skill from routing table" ;; *) bad "routing-derived skill missing" ;; esac
case "$OUT" in *"⬜ \`test-plan\`"*) ok "opt-in artifact offered for stage 4" ;; *) bad "test-plan not offered" ;; esac
case "$OUT" in *"⬜ \`swimlanes\`"*) bad "stage-3 opt-in offered at stage-4 open" ;; *) ok "only next stage's opt-ins offered" ;; esac

echo "== T6: opt-in by register line, opt-in by deed, one summary line in artifact-check =="
P="$(mkproj t6)"
printf 'Opt-in artifact test-plan: demo needs it\n' >> "$P/PROJECT.md"
printf '# swimlanes\nlane\n' > "$P/architecture/swimlanes.md"
OUT="$("$GATE" --closeout "$P" 3 2>&1)"
case "$OUT" in *"✅ \`swimlanes\` — \`architecture/swimlanes.md\`"*) ok "opt-in by deed listed at the Stage-3 close" ;; *) bad "swimlanes not listed" ;; esac
case "$OUT" in *"✅ \`test-plan\` — opted in (demo needs it)"*) ok "register opt-in shown as opted in at the Stage-4 open" ;; *) bad "test-plan opt-in not shown" ;; esac
ART="$("$LIB/artifact-check.sh" "$P" 2>&1)"
case "$ART" in *"Artifact swimlanes "*"PRESENT"*) ok "artifact-check tracks the produced opt-in" ;; *) bad "swimlanes not PRESENT in artifact-check" ;; esac
case "$ART" in *"Artifact test-plan "*"PENDING"*) ok "artifact-check owes the opted-in, absent one" ;; *) bad "test-plan not PENDING: $(printf '%s' "$ART" | grep test-plan)" ;; esac
case "$ART" in *"Artifact erd "*) bad "untaken opt-in listed per row" ;; *) ok "untaken opt-in not listed per row" ;; esac
N="$(printf '%s\n' "$ART" | grep -c '^Artifacts optional, not opted in:')"
[ "$N" -eq 1 ] && ok "exactly one summary line for untaken opt-ins" || bad "summary lines: $N"
case "$ART" in *"not opted in: "*"erd (stage 3)"*"demo-script (stage 5)"*) ok "summary names them" ;; *) bad "summary incomplete" ;; esac

echo "== T7: plain words on the stage-query FAIL and PENDING paths, and on PASS =="
P="$(mkproj t7)"
printf '# fit-gap\nrow\n' > "$P/architecture/fit-gap.md"
printf '# bp\nx\n' > "$P/architecture/blueprint.md"; sleep 1; printf '<html>\n' > "$P/architecture/blueprint.html"
printf '<html>\n' > "$P/design/design-system.html"; printf '<html>\n' > "$P/design/wireframes/a.html"
ERR="$("$GATE" --no-html "$P" 4 2>&1 >/dev/null)"; RC=$?
[ "$RC" -eq 3 ] && ok "stage 4 PENDING exit 3 unchanged" || bad "stage 4 exit $RC"
case "$ERR" in *"In plain words: nothing is wrong, but this stage has not produced"*) ok "PENDING plain words" ;; *) bad "PENDING plain words missing" ;; esac
case "$ERR" in *"still missing for this stage: the numbered build plan"*) ok "PENDING names the missing plan plainly" ;; *) bad "plain missing list absent on PENDING" ;; esac
sed -i.bak 's/| 3 | Module structure: one module | CONFIRMED 2026-09-02 |/| 3 | Module structure: one module | RAISED |/; s/| 3 | Cross-module strategy: none | CONFIRMED |/| 3 | Cross-module strategy: none | RAISED |/' "$P/PROJECT.md"
ERR="$("$GATE" --no-html "$P" 3 2>&1 >/dev/null)"; RC=$?
[ "$RC" -eq 1 ] && ok "stage 3 FAIL exit 1 unchanged" || bad "stage 3 exit $RC: $ERR"
case "$ERR" in *"In plain words: something is there but it is not acceptable yet"*"never answered in chat"*) ok "FAIL plain words name the missing sign-off" ;; *) bad "FAIL plain words: $ERR" ;; esac
mv "$P/PROJECT.md.bak" "$P/PROJECT.md"
OUT="$("$GATE" --no-html "$P" 3 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && ok "stage 3 PASS exit 0" || bad "stage 3 PASS exit $RC"
case "$OUT" in *"In plain words: this stage is done"*) ok "PASS plain words" ;; *) bad "PASS plain words missing" ;; esac

echo "== T8: --closeout without a stage refuses =="
"$GATE" --closeout "$P" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2" || bad "exit $RC"

rm -rf "$WORK"
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
