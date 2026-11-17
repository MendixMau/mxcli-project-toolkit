#!/usr/bin/env bash
# test-entry-mode-plan-rule.sh — the declared-position banner and the pipeline-mode plan rule.
#
# usage: bash tests/wave2/test-entry-mode-plan-rule.sh [path-to-exec.sh]
#
# Field (two field runs, 2026-11, unattended, requirements-driven, full spec + prototypes): the
# agent built ~78 pages with no BRDs, blueprint, wireframes or plan; PROJECT.md had no entry-mode
# or position line, and nothing in the toolkit said so. project-bin/_position.sh + exec.sh now:
#
#   B  no Entry mode and no adoption line → the banner on exec.sh, gate-check.sh's summary and
#      status.sh, and "no entry mode declared" in the BUILD-LOG row; the write is NOT refused
#   R  Entry mode: requirements-driven (or migration, also via the intake answer), no plan →
#      refused ONCE (nothing written, MXTK-RESULT refused); the re-run goes on, row tagged "no plan"
#   C  cleared without a refusal by: gate-check.sh --adopt 5 (the real command), a build plan +
#      module brief (root, or apps/<App>/architecture/), a brief inline in the plan
#   N  never refused: a-la-carte, greenfield, Build type: poc, Change an existing app, --patch
#
# Both layouts: single tree (<root>/Fixture.mpr) and multi-app (<root>/apps/Orders/Orders.mpr,
# PROJECT.md at the root). Golden register + intake: fixtures/entry-mode-plan-rule/ (captured from
# init-project.sh, see its README). The stub mxcli REFUSES `check`, so "the write got past the plan
# rule" is observable as exactly one check call, and nothing real is ever written.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
GOLD="$TOOLKIT/tests/wave2/fixtures/entry-mode-plan-rule"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/entry-plan.XXXXXX")" && pwd -P)" || exit 2
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

for L in single multi; do
  echo "-- layout: $L"
  # B — nothing declared
  mkproj "$L" ""
  run
  case "$OUT" in *"No entry mode declared: the toolkit treats this project as Stage P, not started."*) ok "B[$L] exec prints the banner" ;;
    *) bad "B[$L] exec prints the banner" "$(head -5 "$WORK/out")" ;; esac
  passed && ok "B[$L] undeclared is warned, not refused" || bad "B[$L] undeclared is warned, not refused" "calls=$CALLS_N"
  case "$ROW" in *"no entry mode declared"*) ok "B[$L] BUILD-LOG row carries the tag" ;; *) bad "B[$L] BUILD-LOG row carries the tag" "$ROW" ;; esac

  # R — requirements-driven, no plan: refused once, then goes on
  mkproj "$L" "Entry mode: requirements-driven"
  run
  refused && ok "R[$L] first write refused, nothing reached check" || bad "R[$L] first write refused" "calls=$CALLS_N $(grep -m2 'Plan rule\|MXTK-RESULT' "$WORK/out")"
  case "$OUT" in *"--adopt 5 --reason"*) ok "R[$L] remedy names --adopt 5" ;; *) bad "R[$L] remedy names --adopt 5" ;; esac
  case "$ROW" in *"🚫 blocked"*"plan rule"*) ok "R[$L] refusal logged" ;; *) bad "R[$L] refusal logged" "$ROW" ;; esac
  case "$OUT" in *"No entry mode declared"*) bad "R[$L] no banner once the mode is declared" ;; *) ok "R[$L] no banner once the mode is declared" ;; esac
  run
  passed && ok "R[$L] second write goes on (refused once only)" || bad "R[$L] second write goes on" "calls=$CALLS_N"
  case "$ROW" in *"no plan (Entry mode requirements-driven"*) ok "R[$L] re-run row tagged no plan" ;; *) bad "R[$L] re-run row tagged no plan" "$ROW" ;; esac

  # C — the real clearing command, on a project that was refused
  mkproj "$L" "Entry mode: requirements-driven"
  run
  "$TOOLKIT/bin/gate-check.sh" "$P" --adopt 5 --reason "plan kept outside the toolkit" >/dev/null 2>&1
  grep -q '^Adopted at stage: 5' "$P/PROJECT.md" && ok "C[$L] --adopt 5 writes the register line" || bad "C[$L] --adopt 5 writes the register line"
  rm -f "$P/.mpr-snapshots/.plan-rule-refused"
  run
  passed && ok "C[$L] adopted at 5 → no refusal" || bad "C[$L] adopted at 5 → no refusal" "calls=$CALLS_N"
  case "$ROW" in *"no plan"*) bad "C[$L] no 'no plan' tag after adoption" "$ROW" ;; *) ok "C[$L] no 'no plan' tag after adoption" ;; esac

  # C — a build plan + a module brief (outside evidence, not the toolkit's stamp)
  mkproj "$L" "Entry mode: migration"
  if [ "$L" = multi ]; then A="$P/apps/Orders/architecture"; else A="$P/architecture"; fi
  mkdir -p "$A/modules/Orders"
  printf '# Build plan\n\n| # | Step |\n|---|---|\n| 1 | Orders domain |\n' > "$A/build-plan.md"
  printf '# Module brief — Orders\n' > "$A/modules/Orders/module-brief.md"
  run
  passed && ok "C[$L] build plan + brief → no refusal" || bad "C[$L] build plan + brief → no refusal" "calls=$CALLS_N"
done

echo "-- single tree only"
# C — brief inline in the plan
mkproj single "Entry mode: requirements-driven"
mkdir -p "$P/architecture"; printf '# Build plan\n\n## Module brief — Orders\n\nScreens: list, detail.\n' > "$P/architecture/build-plan.md"
run; passed && ok "C inline '## Module brief' heading → no refusal" || bad "C inline brief heading" "calls=$CALLS_N"
# the aggregate waiver gate-check honours clears it too; one without a reason does not
mkproj single "Entry mode: requirements-driven"
printf 'Waived stages: 1, 2, 3, 4 — analysis and plan were done in the client workshop\n' >> "$P/PROJECT.md"
run; passed && ok "C 'Waived stages: 1, 2, 3, 4 — reason' → no refusal" || bad "C aggregate waiver with a reason" "calls=$CALLS_N"
mkproj single "Entry mode: requirements-driven"
printf 'Waived stages: 1, 2, 3\n' >> "$P/PROJECT.md"
printf 'docs/\n.claude/\n' > "$P/.gitignore"   # as a fresh repo has it: .mpr-snapshots/ not yet ignored
run; refused && ok "R 'Waived stages' without 4 or a reason still refuses" || bad "R aggregate waiver without 4" "calls=$CALLS_N"
# the stamp folder is git-ignored before the stamp is written
grep -qx '/.mpr-snapshots/' "$P/.gitignore" && ok "R .mpr-snapshots/ ignored before the stamp" || bad "R .mpr-snapshots/ ignored before the stamp"
# a build plan without any brief is not a plan the rule accepts
mkproj single "Entry mode: requirements-driven"
mkdir -p "$P/architecture"; printf '# Build plan\n' > "$P/architecture/build-plan.md"
run; refused && ok "R a plan with no brief is still refused" || bad "R a plan with no brief is still refused" "calls=$CALLS_N"

# R — migration declared only in the intake answer (no register line)
mkproj single ""
awk '{ print } /^## 1\. Entry mode/ { print ""; print "Answered: migration" }' "$P/intake.md" > "$P/intake.new" && mv "$P/intake.new" "$P/intake.md"
grep -q '^Answered: migration' "$P/intake.md" || bad "setup: intake answer not written"
run; refused && ok "R migration via the intake answer is refused once" || bad "R migration via intake" "calls=$CALLS_N"

# N — modes that never refuse
for line in "Entry mode: a-la-carte" "Entry mode: greenfield" "Entry mode: Change an existing app"; do
  mkproj single "$line"
  run
  passed && ok "N '$line' → no refusal" || bad "N '$line' → no refusal" "calls=$CALLS_N"
  case "$OUT" in *"No entry mode declared"*|*"Plan rule"*) bad "N '$line' → silent" "$(grep -m1 'declared\|Plan rule' "$WORK/out")" ;; *) ok "N '$line' → silent" ;; esac
done
mkproj single "Entry mode: requirements-driven"
sed -i.bak 's/^Build type: full$/Build type: poc/' "$P/PROJECT.md" && rm -f "$P/PROJECT.md.bak"
grep -q '^Build type: poc$' "$P/PROJECT.md" || bad "setup: Build type: poc not written"
run; passed && ok "N Build type: poc → no refusal" || bad "N Build type: poc → no refusal" "calls=$CALLS_N"
# --patch: opaque repair path, never the plan rule (the script itself fails; we only look for the rule)
mkproj single "Entry mode: requirements-driven"
printf '#!/usr/bin/env bash\nexit 3\n' > "$P/patch.sh"; chmod +x "$P/patch.sh"
run --patch patch.sh
case "$OUT" in *"Plan rule"*) bad "N --patch never meets the plan rule" "$(grep -m1 'Plan rule' "$WORK/out")" ;; *) ok "N --patch never meets the plan rule" ;; esac
[ -f "$P/.mpr-snapshots/.plan-rule-refused" ] && bad "N --patch left a refusal stamp" || ok "N --patch left no refusal stamp"

echo "-- gate-check.sh summary and status.sh"
mkproj single ""
GC="$("$TOOLKIT/bin/gate-check.sh" "$P" 2>&1)"
case "$GC" in *"Summary:"*"No entry mode declared"*) ok "B gate-check summary carries the banner" ;; *) bad "B gate-check summary carries the banner" ;; esac
ST="$("$TOOLKIT/bin/status.sh" "$P" --brief 2>&1)"
case "$ST" in *"No entry mode declared"*) ok "B status --brief carries the banner" ;; *) bad "B status --brief carries the banner" ;; esac
# On a fresh scaffold gate-check already flags intake §1 "Entry mode", and that needs-attention rule
# outranks the banner rule in status.sh's NEXT order; either line names the entry mode.
case "$ST" in *"NEXT    declare the entry mode"*|*"NEXT    fix what gate-check flags"*"Entry mode"*) ok "B status NEXT names the entry mode" ;;
  *) bad "B status NEXT names the entry mode" "$(printf '%s\n' "$ST" | grep NEXT)" ;; esac
mkproj single "Entry mode: requirements-driven"
GC="$("$TOOLKIT/bin/gate-check.sh" "$P" 2>&1)"
case "$GC" in *"No entry mode declared"*) bad "gate-check silent once declared" ;; *) ok "gate-check silent once declared" ;; esac
mkproj single "Entry mode: a-la-carte"
GC="$("$TOOLKIT/bin/gate-check.sh" "$P" 3 2>&1)"
case "$GC" in *"a-la-carte entry mode — no pipeline"*) ok "a-la-carte stages read WAIVED with the reason" ;; *) bad "a-la-carte stages read WAIVED with the reason" "$(printf '%s\n' "$GC" | grep -m2 '^Stage [0-3]')" ;; esac

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
