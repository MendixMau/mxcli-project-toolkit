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
#   K  Build type: poc (its own axis, not an entry-mode token) → gate-check reads Stages 0-4,
#      6, 7 "not owed (mode: Build type: poc)"
#   V  every token in artifact-manifest.tsv col 6 / obligations.tsv col 10 is one the reader emits
#   W  `Interview mode: auto (...)` / `unattended — ...` read as auto (first word) in exec.sh and
#      in gate-check.sh's --adopt ✋ check; `autopilot` is not
#   U  no Entry mode under auto is refused every write; attended keeps the banner only
#   X  exec.sh called by relative paths from inside apps/<App> (../../bin/exec.sh
#      ../../mdlsource/x.mdl) is refused under auto exactly as the absolute call is
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

echo "-- X: exec.sh called by RELATIVE paths from inside an app folder (review of #789)"
# _XD="${0%/*}" was relative (../../bin); after exec.sh's cd to the project root the plan-rule
# guard [ -f "$_XD/_position.sh" ] failed in silence and the unattended write went through, while
# the same call by absolute path was refused. A relative script path broke the same way.
# runat <cwd> <exec> <script> -> OUT, CALLS_N
runat() {
  rm -rf "$P/docs" "$WORK/calls"
  ( cd "$1" && CALLS="$WORK/calls" SP_RESTART=0 MXTK_NO_INSTALL=1 SKIP_DOCTOR=1 TMPDIR="$WORK" \
      bash "$2" "$3" ) >"$WORK/out" 2>&1
  OUT="$(cat "$WORK/out")"
  CALLS_N="$(grep -c check "$WORK/calls" 2>/dev/null)"; CALLS_N="${CALLS_N:-0}"
}
mkproj multi "Entry mode: requirements-driven"
printf 'Interview mode: auto\n' >> "$P/PROJECT.md"
runat "$P/apps/Orders" ../../bin/exec.sh ../../mdlsource/01-thing.mdl
autorefused && ok "X relative exec + script from apps/Orders → refused" || bad "X relative exec + script from apps/Orders → refused" "calls=$CALLS_N"
runat "$P/apps/Orders" "$P/bin/exec.sh" "$P/mdlsource/01-thing.mdl"
autorefused && ok "X the same call by absolute paths → refused" || bad "X absolute paths → refused" "calls=$CALLS_N"
mkdir -p "$P/.mpr-snapshots"; printf 'build-ready PASS\n' > "$P/.mpr-snapshots/.build-ready-pass"
runat "$P/apps/Orders" ../../bin/exec.sh ../../mdlsource/01-thing.mdl
passed && ok "X after build-ready the relative call reaches the check (the script resolved)" || bad "X relative call after build-ready" "calls=$CALLS_N"
echo "-- W: auto read by its first word, not the exact value (one helper: mxtk_auto_word)"
# Field smoke run: `Interview mode: auto (gate questions go to questions.md ...)` was read as attended,
# so the second write got past the plan rule on refuse-once.
for line in "Interview mode: auto (gate questions go to questions.md, answered later)" "Interview mode: unattended — questions logged" "- **Interview mode**: Auto"; do
  mkproj single "Entry mode: requirements-driven"
  printf '%s\n' "$line" >> "$P/PROJECT.md"
  run; run
  autorefused && ok "W '$line' → still refused on the second write" || bad "W '$line' → still refused on the second write" "calls=$CALLS_N"
done
mkproj single "Entry mode: requirements-driven"
printf 'Interview mode: autopilot\n' >> "$P/PROJECT.md"
run; case "$OUT" in *"Plan rule (Interview mode: auto)"*) bad "W 'autopilot' is not auto" ;; *) ok "W 'autopilot' is not auto (attended refuse-once instead)" ;; esac
mkproj single "Entry mode: migration"
printf 'Interview mode: auto (gate questions go to questions.md)\n' >> "$P/PROJECT.md"
"$GC" "$P" --adopt 5 --reason "plan kept outside the toolkit" >/dev/null 2>&1
grep -q 'consentBy: auto-mode' "$P/PROJECT.md" && ok "W --adopt under 'auto (...)' writes the ✋ row" || bad "W --adopt under 'auto (...)' writes the ✋ row"

echo "-- U: no Entry mode under auto is refused; attended keeps the banner only"
mkproj single ""
printf 'Interview mode: auto\n' >> "$P/PROJECT.md"
run; run
case "$OUT" in *"✗ Plan rule (Interview mode: auto): no Entry mode declared"*) [ "$CALLS_N" = 0 ] && ok "U undeclared + auto → refused every write" || bad "U undeclared + auto reached check" ;;
  *) bad "U undeclared + auto → refused every write" "calls=$CALLS_N" ;; esac
mkproj single ""
run; passed && ok "U undeclared + attended → banner, not refused" || bad "U undeclared + attended → banner, not refused" "calls=$CALLS_N"

echo "-- G: init over a hand-written PROJECT.md"
Q="$WORK/hand"; mkdir -p "$Q"; ( cd "$Q" && git init -q . )
printf '# My project\n\nEntry mode: requirements-driven\nRequirements live in specs/.\n' > "$Q/PROJECT.md"
MXTK_NO_GUIDE=1 HOME="$WORK/home" "$TOOLKIT/bin/init-project.sh" "$Q" > "$WORK/init.out" 2>&1
case "$(cat "$WORK/init.out")" in *"PROJECT.md already existed WITHOUT the decision-register structure — appended: Current stage, Decisions, Open questions, Change log"*) ok "G init says what it appended" ;;
  *) bad "G init says what it appended" "$(grep -m1 PROJECT.md "$WORK/init.out")" ;; esac
for h in "## Current stage" "## Decisions" "## Open questions" "## Change log"; do
  grep -q "^$h" "$Q/PROJECT.md" && ok "G $h present" || bad "G $h present"; done
grep -q '^Requirements live in specs/\.$' "$Q/PROJECT.md" && ok "G hand-written lines kept" || bad "G hand-written lines kept"
# Captured to a file, not piped into grep -q: under pipefail, grep -q closing the pipe early
# SIGPIPEs init-project.sh and the pipeline reads as a failure.
MXTK_NO_GUIDE=1 HOME="$WORK/home" "$TOOLKIT/bin/init-project.sh" "$Q" > "$WORK/init2.out" 2>&1
grep -q "Skip: PROJECT.md already exists" "$WORK/init2.out" \
  && ok "G a second init appends nothing" || bad "G a second init appends nothing"

echo "-- V: one vocabulary across both tables (drift guard)"
# Every token in artifact-manifest.tsv column 6 and obligations.tsv's modes column (column 10, when
# the table has one) must be a value the boundary reader _art_entry_mode can produce from a real
# register line — otherwise a row reads "not owed (mode)" for the very mode that owes it: a silent
# pass. The emitted set is computed, not listed, so a tokeniser change moves it too.
EMIT="$(bash -c '. "$1/bin/lib/entry-mode.sh"; . "$1/bin/lib/artifact-check.sh"
  for m in migration requirements-driven greenfield "Change an existing app" a-la-carte; do
    d="$(mktemp -d)"; printf "Entry mode: %s\n" "$m" > "$d/PROJECT.md"; _art_kv_load "$d/PROJECT.md" 2>/dev/null
    _art_entry_mode "$d/PROJECT.md" 2>/dev/null; rm -rf "$d"; done' _ "$TOOLKIT" | sort -u | tr '\n' ' ')"
[ -n "$EMIT" ] && ok "V emitted set: $EMIT" || bad "V could not compute the emitted token set"
for spec in "bin/lib/artifact-manifest.tsv:6" "bin/lib/obligations.tsv:10"; do
  f="$TOOLKIT/${spec%%:*}"; col="${spec##*:}"; [ -f "$f" ] || continue
  hdr="$(grep -m1 -v '^#' "$f" | awk -F'\t' -v c="$col" '{print $c}')"
  [ "$hdr" = modes ] || { echo "  skip ${spec%%:*}: column $col is not 'modes' here"; continue; }
  bad_t="$(grep -v '^#' "$f" | awk -F'\t' -v c="$col" 'NR>1 && NF>=c {n=split($c,a,","); for(i=1;i<=n;i++) print a[i]}' \
    | sort -u | while read -r t; do case " $EMIT " in (*" $t "*) ;; (*) printf '%s ' "$t" ;; esac; done)"
  [ -z "$bad_t" ] && ok "V ${spec%%:*} modes tokens all emitted by the tokeniser" || bad "V ${spec%%:*} has tokens nothing emits" "$bad_t"
done

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
