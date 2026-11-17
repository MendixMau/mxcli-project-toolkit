#!/usr/bin/env bash
# test-mode-contract.sh — the mode contract under Interview mode: auto, the ✋ adoption, POC's
# "not owed (mode)", and init/sync laying down a register over a hand-written PROJECT.md.
#
# usage: bash tests/wave2/test-mode-contract.sh [path-to-exec.sh]
#
# Owner design input (2026-11-17): unattended is the primary case. Field basis: two field runs
# (2026-11, auto, requirements-driven) built ~78 pages with no plan; one had a hand-written
# 10-line PROJECT.md that init-project.sh then skipped in silence.
#
#   A  auto + requirements-driven, no build-ready: EVERY write refused (no refuse-once), a plan
#      on disk does not clear it, the build-ready stamp does, an --adopt 5 does
#   H  --adopt 5 under auto writes an ASSUMED consentBy: auto-mode Stage-4 row, and gate-check
#      lists it as a ✋ decision to confirm; without auto no row is written
#   K  Build type: poc → gate-check reads Stages 0-4, 6, 7 "not owed (mode: Build type: poc)";
#      artifact rows not listed for poc read "not owed (mode poc"
#   G  init-project.sh over a hand-written PROJECT.md appends Current stage, Decisions, Open
#      questions and Change log, says so, and keeps the hand-written lines
#
# Golden register + intake: fixtures/entry-mode-plan-rule/ (captured from init-project.sh).
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
GOLD="$TOOLKIT/tests/wave2/fixtures/entry-mode-plan-rule"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/mode-contract.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"

# mkproj <layout single|multi> <register line or ""> -> sets P
N=0
mkproj() {
  N=$((N+1)); P="$WORK/p$N"; local m="$P"
  mkdir -p "$P/bin" "$P/mdlsource"
  [ "$1" = multi ] && m="$P/apps/Orders"
  mkdir -p "$m/mprcontents"
  printf 'not a real model\n' > "$m/$( [ "$1" = multi ] && echo Orders || echo Fixture ).mpr"
  printf 'bson\n' > "$m/mprcontents/a.mxunit"
  cp "$GOLD/PROJECT.md" "$GOLD/intake.md" "$P/"
  [ -n "$2" ] && printf '%s\n' "$2" >> "$P/PROJECT.md"
  printf 'CREATE ENTITY Orders.Thing (Name: String);\n' > "$P/mdlsource/01-thing.mdl"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/_position.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/exec.sh"
  printf '#!/usr/bin/env bash\necho "Snapshot saved: none"\n' > "$P/bin/snapshot-mpr.sh"
  cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in
  check) echo check >> "$CALLS"; echo "✗ stub refuses [STUB01]" >&2; exit 1 ;;
  exec)  echo exec >> "$CALLS"; exit 0 ;;
esac
exit 0
MXCLI
  chmod +x "$P/bin/"*.sh "$P/mxcli"
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
}
# run [exec args...] -> OUT, ROW, CALLS_N (check calls)
run() {
  rm -rf "$P/docs" "$WORK/calls"
  ( cd "$P" && CALLS="$WORK/calls" SP_RESTART=0 MXTK_NO_INSTALL=1 SKIP_DOCTOR=1 TMPDIR="$WORK" \
      ./bin/exec.sh "${@:-mdlsource/01-thing.mdl}" ) >"$WORK/out" 2>&1
  OUT="$(cat "$WORK/out")"
  ROW="$(grep '^| ' "$P/docs/BUILD-LOG.md" 2>/dev/null | tail -1)"
  CALLS_N="$(grep -c check "$WORK/calls" 2>/dev/null)"; CALLS_N="${CALLS_N:-0}"
}
refused() { case "$OUT" in *"✗ Plan rule"*) [ "$CALLS_N" = 0 ] && case "$OUT" in *"MXTK-RESULT exec verdict=refused applied=no"*) return 0 ;; esac ;; esac; return 1; }
passed()  { case "$OUT" in *"✗ Plan rule"*) return 1 ;; esac; [ "$CALLS_N" = 1 ]; }


autorefused() { case "$OUT" in *"✗ Plan rule (Interview mode: auto)"*) [ "$CALLS_N" = 0 ] ;; *) return 1 ;; esac; }
GC="$TOOLKIT/bin/gate-check.sh"

echo "-- A: auto mode"
mkproj single "Entry mode: requirements-driven"
printf 'Interview mode: auto\n' >> "$P/PROJECT.md"
run; autorefused && ok "A first write refused" || bad "A first write refused" "calls=$CALLS_N"
case "$OUT" in *"✋ human-pending"*) ok "A remedy says an adoption is ✋ human-pending" ;; *) bad "A remedy says an adoption is ✋ human-pending" ;; esac
run; autorefused && ok "A second write refused too (no refuse-once under auto)" || bad "A second write refused too" "calls=$CALLS_N"
mkdir -p "$P/architecture/modules/Orders"; printf '# Build plan\n' > "$P/architecture/build-plan.md"; printf '# Module brief — Orders\n' > "$P/architecture/modules/Orders/module-brief.md"
run; autorefused && ok "A a plan on disk alone does not clear it under auto" || bad "A plan on disk alone" "calls=$CALLS_N"
mkdir -p "$P/.mpr-snapshots"; printf 'x build-ready PASS\n' > "$P/.mpr-snapshots/.build-ready-pass"
run; passed && ok "A the build-ready record clears it" || bad "A the build-ready record clears it" "calls=$CALLS_N"
mkproj single "Entry mode: migration"
printf 'Interview mode: auto\n' >> "$P/PROJECT.md"
CLAUDE_INTERVIEW_MODE= "$GC" "$P" --adopt 5 --reason "plan kept outside the toolkit" > "$WORK/adopt.out" 2>&1
run; passed && ok "A --adopt 5 clears it" || bad "A --adopt 5 clears it" "calls=$CALLS_N"

echo "-- H: the ✋ adoption"
grep -qE '^\| 4 \| Adopted at stage 5 .*\| ASSUMED \| consentBy: auto-mode · consentAt: [0-9]' "$P/PROJECT.md" \
  && ok "H ASSUMED auto-mode Stage-4 row written" || bad "H ASSUMED auto-mode Stage-4 row written" "$(grep -n 'Adopted' "$P/PROJECT.md")"
grep -q "human-pending" "$WORK/adopt.out" && ok "H --adopt says it is human-pending" || bad "H --adopt says it is human-pending"
G="$("$GC" "$P" 2>&1)"
case "$G" in *"✋ decision(s) assumed by auto-mode"*"(Stage 4)"*) ok "H gate-check lists it to confirm" ;; *) bad "H gate-check lists it to confirm" ;; esac
mkproj single "Entry mode: migration"
"$GC" "$P" --adopt 5 --reason "plan kept outside the toolkit" >/dev/null 2>&1
grep -q "consentBy: auto-mode" "$P/PROJECT.md" && bad "H no ✋ row without auto" || ok "H no ✋ row without auto"

echo "-- K: Build type: poc"
mkproj single "Entry mode: requirements-driven"
sed -i.bak 's/^Build type: full$/Build type: poc/' "$P/PROJECT.md" && rm -f "$P/PROJECT.md.bak"
G="$("$GC" "$P" 2>&1)"
n="$(printf '%s\n' "$G" | grep -cE '^Stage [0-4] .*not owed \(mode: Build type: poc\)|^Stage [67] .*not owed \(mode: Build type: poc\)')"
[ "$n" = 7 ] && ok "K stages 0-4, 6, 7 not owed (mode) — 7 of 7" || bad "K stages 0-4, 6, 7 not owed (mode)" "$n of 7"
case "$G" in *"not owed (mode poc"*) ok "K artifact rows say not owed (mode poc)" ;; *) bad "K artifact rows say not owed (mode poc)" ;; esac

echo "-- G: init over a hand-written PROJECT.md"
Q="$WORK/hand"; mkdir -p "$Q"; ( cd "$Q" && git init -q . )
printf '# My project\n\nEntry mode: requirements-driven\nRequirements live in specs/.\n' > "$Q/PROJECT.md"
MXTK_NO_GUIDE=1 HOME="$WORK/home" "$TOOLKIT/bin/init-project.sh" "$Q" > "$WORK/init.out" 2>&1
case "$(cat "$WORK/init.out")" in *"PROJECT.md already existed WITHOUT the decision-register structure — appended: Current stage, Decisions, Open questions, Change log"*) ok "G init says what it appended" ;;
  *) bad "G init says what it appended" "$(grep -m1 PROJECT.md "$WORK/init.out")" ;; esac
for h in "## Current stage" "## Decisions" "## Open questions" "## Change log"; do
  grep -q "^$h" "$Q/PROJECT.md" && ok "G $h present" || bad "G $h present"; done
grep -q '^Requirements live in specs/\.$' "$Q/PROJECT.md" && ok "G hand-written lines kept" || bad "G hand-written lines kept"
MXTK_NO_GUIDE=1 HOME="$WORK/home" "$TOOLKIT/bin/init-project.sh" "$Q" 2>&1 | grep -q "Skip: PROJECT.md already exists" \
  && ok "G a second init appends nothing" || bad "G a second init appends nothing"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
