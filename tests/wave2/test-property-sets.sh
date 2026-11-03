#!/usr/bin/env bash
# Fixture for #295: `mxcli fix property-sets` wired into the upgrade path, report first.
#   bin/doctor.sh --property-sets [--if-stale] <dir>   read-only check + receipt
#   bin/doctor.sh --fix-property-sets <dir>            the repair, only through exec.sh --patch
#   bin/doctor.sh --quick <dir>                        receipt vs installed mxcli -> WARN
#   bin/sync-project.sh <dir>                          runs the --if-stale check
# and, for #236, sync-project.sh's known-fix note for a pre-fix bin/model-stamp.sh.
#
# Golden input (tests/wave2/fixtures/property-sets/), captured from the official
# mendixlabs/mxcli linux-amd64 release binaries, never run against a model:
#   version-v0.2{4,5,6}.0.txt              `mxcli --version`
#   fix-help-v0.2{4,5,6}.0.txt             `mxcli fix --help`, verbatim up to "Global Flags:"
#                                          (the global-flags block is identical on every
#                                          subcommand and is not read)
#   fix-property-sets-help-v0.25.0.txt     `mxcli fix property-sets --help` on v0.25.0: exit 0,
#                                          and it is the PARENT's help — why the support probe
#                                          reads `fix --help` instead
#   dry-run-not-found-v0.26.0.{txt,exit}   `fix property-sets -p <missing> --dry-run`: exit 1
#                                          with no unit rows — why exit 1 alone is not "needs"
#   ps-{dryrun-mixed,dryrun-both,apply-both,after-apply-both}-v0.29.0.{out,err,exit}
#                                          REAL v0.29.0 runs on a real model with MIXED rows —
#                                          provenance in CAPTURE.txt beside them (case P11)
# NOT captured: the v0.26.0 clean / NEEDS / FAILED reports, which need a real model. The stub below
# prints them from the format strings in mxcli v0.26.0 cmd/mxcli/cmd_fix_property_sets.go
# (fixPropertySets: "Checked %d unit(s) in %s against the Mendix %d.%d.%d property sets.",
# "  %-9s %s%s: +%d key(s), -%d key(s)", "  FAILED    %s%s: %v"). A field run owes the real ones.
#
# Every project is built under /tmp. No real project is touched; no real mxcli runs.
#
# usage: test-property-sets.sh /path/to/bin/doctor.sh
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_SYNC_SKIP_CLONE_CHECK=1
export MXTK_DOCTOR_SKIP_DOCKER=1

set -uo pipefail

DOCTOR="${1:?usage: test-property-sets.sh /path/to/bin/doctor.sh}"
case "$DOCTOR" in /*) ;; *) DOCTOR="$PWD/$DOCTOR" ;; esac
TK="$(cd "$(dirname "$DOCTOR")/.." && pwd)"
SYNC="$TK/bin/sync-project.sh"
FIX="$TK/tests/wave2/fixtures/property-sets"
WORK="$(mktemp -d /tmp/propsets.XXXXXX)"
trap 'rm -f "$MXTK_LEAKGUARD_DENYFILE"; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# The stub mxcli. STUB_VER picks the captured version; the model state lives in .stub-state.
mkstub() {
  cat > "$1/mxcli" <<'STUB'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
F="$STUB_FIX"; V="$(cat "$D/.stub-ver" 2>/dev/null || echo v0.26.0)"
echo "$*" >> "$D/.stub-log"
case "${1:-}" in
  --version) cat "$F/version-$V.txt"; exit 0 ;;
  --help)    echo "mxcli (stub)"; exit 0 ;;
  fix) shift
    case "${1:-}" in
      --help) [ -f "$D/.stub-helpfail" ] && { echo "panic: stub"; exit 2; }
              cat "$F/fix-help-$V.txt"; exit 0 ;;
      property-sets)
        dry=0; mpr=""; prev=""
        for a in "$@"; do [ "$a" = --dry-run ] && dry=1; [ "$prev" = -p ] && mpr="$a"; prev="$a"; done
        b="$(basename "$mpr")"
        echo "WARNING: This is a vibe-coded PoC, alpha quality, use with caution." >&2
        # v0.29.0 states replay real captures (CAPTURE.txt); "both" -> its write leaves "mixed".
        rp() { cat "$F/$1-v0.29.0.out"; return "$(cat "$F/$1-v0.29.0.exit")"; }
        if [ "$dry" = 0 ] && [ "$(cat "$D/.stub-state")" = both ]; then
          echo mixed > "$D/.stub-state"; rp ps-apply-both; exit $?
        fi
        if [ "$dry" = 0 ]; then
          echo "Checked 3 unit(s) in $b against the Mendix 11.12.1 property sets."
          echo "  FIXED     0d6c3a3e-0000-4000-8000-000000000001 [Microflows\$Microflow Orders.ACT_Save]: +4 key(s), -0 key(s)"
          echo ""; echo "Completed 1 unit(s): 4 key(s) added, 0 stripped."
          echo clean > "$D/.stub-state"; exit 0
        fi
        case "$(cat "$D/.stub-state")" in
          clean) echo "Checked 3 unit(s) in $b against the Mendix 11.12.1 property sets."
                 echo "Every unit already has the property names Studio Pro writes."; exit 0 ;;
          needs) echo "Checked 3 unit(s) in $b against the Mendix 11.12.1 property sets."
                 echo "  NEEDS     0d6c3a3e-0000-4000-8000-000000000001 [Microflows\$Microflow Orders.ACT_Save]: +4 key(s), -0 key(s)"
                 echo ""; echo "Would complete 1 unit(s): 4 key(s) added, 0 stripped."
                 echo "Run 'mxcli fix property-sets -p $mpr' to write them."; exit 1 ;;
          failed) echo "Checked 3 unit(s) in $b against the Mendix 11.12.1 property sets."
                  echo "  FAILED    0d6c3a3e-0000-4000-8000-000000000002 [Pages\$Page Orders.Order_Edit]: key Foo holds a value"
                  echo "1 unit(s) could not be normalized and were left as they are."; exit 1 ;;
          notfound) cat "$F/dry-run-not-found-v0.26.0.txt"; exit 1 ;;
          mixed) rp ps-dryrun-mixed; exit $? ;;
          both)  rp ps-dryrun-both; exit $? ;;
          noversion) echo "$b has no readable Mendix version; nothing is normalized without one."; exit 0 ;;
          slow) exec sleep 6; echo "Checked 3 unit(s) in $b against the Mendix 11.12.1 property sets."; exit 0 ;;
        esac ;;
    esac ;;
esac
exit 0
STUB
  chmod +x "$1/mxcli"
}
mkproj() {   # <name> [app]  — a bare project dir: .mpr (root or app/), stub mxcli, git
  d="$WORK/$1"; mkdir -p "$d"
  if [ "${2:-}" = app ]; then mkdir -p "$d/app"; : > "$d/app/App.mpr"; else : > "$d/App.mpr"; fi
  mkstub "$d"; echo needs > "$d/.stub-state"
  git -C "$d" init -q . 2>/dev/null
  echo "$d"
}
export STUB_FIX="$FIX"

echo "== P1 support probe reads 'fix --help', from the real captures =="
grep -qE '^[[:space:]]+property-sets[[:space:]]' "$FIX/fix-help-v0.26.0.txt" && ok "v0.26.0 capture lists property-sets" || bad "v0.26.0 capture lacks property-sets"
grep -q 'property-sets' "$FIX/fix-help-v0.25.0.txt" && bad "v0.25.0 capture lists property-sets" || ok "v0.25.0 capture does not list it"
head -1 "$FIX/fix-property-sets-help-v0.25.0.txt" | grep -q "model-fixing tools" && ok "v0.25.0 'fix property-sets --help' is the parent's help (why it is not the probe)" || bad "capture shape changed"
for v in v0.24.0 v0.25.0; do
  P="$(mkproj old-$v)"; echo "$v" > "$P/.stub-ver"
  OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
  [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q "arrived in v0.26.0" && ok "$v: exit 3, says v0.26.0 is needed" || bad "$v: rc=$RC" "$OUT"
  grep -q -- '--dry-run' "$P/.stub-log" && bad "$v: ran the dry-run on a binary without the command" || ok "$v: no dry-run attempted"
done

echo "== P2 clean model =="
P="$(mkproj clean)"; echo clean > "$P/.stub-state"
OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "ok    property sets: Checked 3 unit(s)" && ok "clean: exit 0 with the Checked line" || bad "clean: rc=$RC" "$OUT"
R="$P/.claude/.property-sets-receipt"
sed -n 1p "$R" 2>/dev/null | grep -q " clean " && sed -n 2p "$R" | grep -qx "mxcli: mxcli version v0.26.0 (2026-10-11T18:37:07Z)" \
  && ok "receipt records result and mxcli version" || bad "receipt wrong" "$(cat "$R" 2>&1)"
grep -qx '/.claude/.property-sets-receipt' "$P/.gitignore" 2>/dev/null && ok "receipt is gitignored (machine-local)" || bad "receipt not gitignored"
printf '%s' "$OUT" | grep -q "added /.claude/.property-sets-receipt to the project's .gitignore" && ok "the .gitignore append is announced" || bad "silent .gitignore append" "$OUT"
grep -q -- 'property-sets -p .*/App.mpr --dry-run' "$P/.stub-log" && ok "the check is the --dry-run" || bad "dry-run not used" "$(cat "$P/.stub-log")"

echo "== P2b a clean dry-run below Mendix 10.24.24 is not proof (mendixlabs/mxcli#1595) =="
. "$TK/bin/lib/portable.sh"; require_py
setver() {   # <project> <version> — give the stub project's .mpr a readable _ProductVersion
  rm -f "$1/App.mpr"
  "$PY" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("create table _MetaData (_ProductVersion text)"); c.execute("insert into _MetaData values (?)",(sys.argv[2],)); c.commit()' "$1/App.mpr" "$2"
}
P="$(mkproj below)"; echo clean > "$P/.stub-state"; setver "$P" 10.24.18.103793
OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "WARN  property sets:.*NOT PROOF.*Mendix 10.24.18.103793.*mxcli#1595" \
  && ok "10.24.18 clean: exit 0 but a WARN saying it proves nothing" || bad "10.24.18 clean: rc=$RC" "$OUT"
printf '%s' "$OUT" | grep -q "every unit has the property names Studio Pro writes" && bad "10.24.18 still prints the false green" "$OUT" || ok "10.24.18: no 'every unit has the property names' line"
printf '%s' "$OUT" | grep -q "mx diff <base>.mpr <mine>.mpr" && ok "names mx diff as the proof" || bad "no mx diff pointer" "$OUT"
sed -n 1p "$P/.claude/.property-sets-receipt" | grep -q " unproven " && ok "receipt records unproven, not clean" || bad "receipt" "$(cat "$P/.claude/.property-sets-receipt" 2>&1)"
n1="$(grep -c -- '--dry-run' "$P/.stub-log")"
OUT="$("$DOCTOR" --property-sets --if-stale "$P" 2>&1)"; n2="$(grep -c -- '--dry-run' "$P/.stub-log")"
[ "$n1" -eq "$n2" ] && printf '%s' "$OUT" | grep -q "WARN  property sets: already checked.*NOT PROOF" && ! printf '%s' "$OUT" | grep -q "ok    already checked" \
  && ok "--if-stale: not re-run, and still a WARN, never an ok" || bad "--if-stale unproven ($n1 -> $n2)" "$OUT"
OUT="$("$DOCTOR" --quick "$P" 2>&1)"
printf '%s' "$OUT" | grep -q "WARN  property sets: last check for this mxcli was clean, but the model is below Mendix 10.24.24" && ok "--quick: WARN, not the ok line" || bad "--quick unproven" "$(printf '%s' "$OUT" | grep -i -A2 'property')"
for v in 10.24.23 9.24.2; do
  P="$(mkproj below-$v)"; echo clean > "$P/.stub-state"; setver "$P" "$v"
  OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"
  printf '%s' "$OUT" | grep -q "NOT PROOF" && ok "$v: below the floor, warned" || bad "$v not warned" "$OUT"
done
for v in 10.24.24 10.25.1 11.12.1; do
  P="$(mkproj at-$v)"; echo clean > "$P/.stub-state"; setver "$P" "$v"
  OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"
  printf '%s' "$OUT" | grep -q "ok    property sets: Checked 3 unit(s).*every unit has the property names" && ! printf '%s' "$OUT" | grep -q "NOT PROOF" \
    && ok "$v: at or above the floor, still ok" || bad "$v wrongly warned" "$OUT"
done

echo "== P3 units need completing =="
P="$(mkproj needs)"
OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "needs: exit 1" || bad "needs: rc=$RC" "$OUT"
printf '%s' "$OUT" | grep -q "WARN  property sets: 1 unit(s) need" && ok "needs: WARN with the count" || bad "needs: no WARN" "$OUT"
printf '%s' "$OUT" | grep -q "NEEDS     0d6c3a3e" && ok "needs: unit row shown" || bad "needs: row missing" "$OUT"
printf '%s' "$OUT" | grep -q -- "--fix-property-sets" && ok "needs: names the gated repair" || bad "needs: no repair hint" "$OUT"
grep -v -- '--dry-run' "$P/.stub-log" | grep -q 'property-sets' && bad "needs: the check WROTE (ran without --dry-run)" || ok "needs: nothing written"

echo "== P4 failed / error / no version — never clean =="
for st in failed notfound noversion; do
  P="$(mkproj st-$st)"; echo "$st" > "$P/.stub-state"
  OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
  want=4; [ "$st" = failed ] && want=1
  [ "$RC" -eq "$want" ] && ! printf '%s' "$OUT" | grep -q "ok    property sets" && ok "$st: exit $want, no ok line" || bad "$st: rc=$RC (want $want)" "$OUT"
done
printf '%s' "$OUT" | grep -q "no Mendix version" && ok "noversion: says nothing was checked" || bad "noversion wording" "$OUT"
for st in notfound noversion; do
  [ -f "$WORK/st-$st/.claude/.property-sets-receipt" ] && bad "$st: an error result was recorded" || ok "$st: error result not recorded"
done
P="$WORK/st-notfound"; "$DOCTOR" --property-sets --if-stale "$P" >/dev/null 2>&1
[ "$(grep -c -- '--dry-run' "$P/.stub-log")" -eq 2 ] && ok "notfound: --if-stale re-checks after an error" || bad "notfound: --if-stale skipped after an error"
P="$(mkproj helpfail)"; touch "$P/.stub-helpfail"
OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q "support is unknown" && [ ! -f "$P/.claude/.property-sets-receipt" ] \
  && ok "failed 'fix --help' probe: error (exit 4), not unsupported, not recorded" || bad "helpfail rc=$RC" "$OUT"
OUT="$("$DOCTOR" --quick "$P" 2>&1)"
printf '%s' "$OUT" | grep -q "could not probe this mxcli" && ! printf '%s' "$OUT" | grep -q "predates 'mxcli fix property-sets'" \
  && ok "--quick, crashed probe: says 'could not probe', not 'predates'" || bad "quick helpfail" "$(printf '%s' "$OUT" | grep -i property)"

echo "== P5 --if-stale: once per mxcli version =="
P="$(mkproj stale)"; echo clean > "$P/.stub-state"
"$DOCTOR" --property-sets --if-stale "$P" >/dev/null 2>&1
n1="$(grep -c -- '--dry-run' "$P/.stub-log")"
OUT="$("$DOCTOR" --property-sets --if-stale "$P" 2>&1)"; RC=$?
n2="$(grep -c -- '--dry-run' "$P/.stub-log")"
[ "$n1" -eq 1 ] && [ "$n2" -eq 1 ] && [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "already checked" \
  && ok "same mxcli: not re-run, exit from the receipt" || bad "same mxcli: n1=$n1 n2=$n2 rc=$RC" "$OUT"
sed -i.bak '2s/.*/mxcli: mxcli version v0.25.0 (2026-10-05T09:18:28Z)/' "$P/.claude/.property-sets-receipt"
"$DOCTOR" --property-sets --if-stale "$P" >/dev/null 2>&1
n3="$(grep -c -- '--dry-run' "$P/.stub-log")"
[ "$n3" -eq 2 ] && ok "mxcli changed since the receipt: re-run" || bad "after a version change n3=$n3"

P="$WORK/needs"; n1="$(grep -c -- '--dry-run' "$P/.stub-log")"
"$DOCTOR" --property-sets --if-stale "$P" >/dev/null 2>&1; n2="$(grep -c -- '--dry-run' "$P/.stub-log")"
[ "$n2" -eq $((n1 + 1)) ] && ok "needs on the receipt: --if-stale re-checks" || bad "needs: --if-stale skipped ($n1 -> $n2)"
P="$WORK/old-v0.25.0"
OUT="$("$DOCTOR" --property-sets --if-stale "$P" 2>&1)"; RC=$?
[ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q "already checked" && ok "recorded unsupported: --if-stale short-circuits, exit 3" || bad "unsupported if-stale rc=$RC" "$OUT"

echo "== P5b the dry-run is bounded; a timeout is NOT RUN and not recorded =="
for mode in timeout-bin watchdog; do
  P="$(mkproj slow-$mode)"; echo slow > "$P/.stub-state"
  nb=0; [ "$mode" = watchdog ] && nb=1
  t0=$(date +%s)
  OUT="$(MXTK_PROPSETS_TIMEOUT=1 MXTK_PROPSETS_NO_TIMEOUT_BIN=$nb "$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
  el=$(( $(date +%s) - t0 ))
  [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q "timed out after 1s" && ok "$mode: exit 2, says it timed out" || bad "$mode: rc=$RC" "$OUT"
  [ "$el" -lt 6 ] && ok "$mode: returned before the slow check finished (${el}s)" || bad "$mode: waited ${el}s"
  [ ! -f "$P/.claude/.property-sets-receipt" ] && ok "$mode: timeout not recorded" || bad "$mode: timeout recorded"
done

echo "== P6 two-tree checkout (.mpr under app/) =="
P="$(mkproj twotree app)"; echo clean > "$P/.stub-state"
"$DOCTOR" --property-sets "$P" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && grep -q -- "-p $P/app/App.mpr --dry-run" "$P/.stub-log" && ok "checks app/App.mpr" || bad "two-tree rc=$RC" "$(cat "$P/.stub-log")"

echo "== P7 --fix-property-sets writes only through exec.sh --patch =="
P="$(mkproj fix-noexec)"
OUT="$("$DOCTOR" --fix-property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "FAIL  property sets: not repaired" && ok "no exec.sh: refused, exit 1" || bad "no exec.sh: rc=$RC" "$OUT"
grep -v -- '--dry-run' "$P/.stub-log" | grep -q 'property-sets' && bad "no exec.sh: wrote anyway" || ok "no exec.sh: nothing written"
mkdir -p "$P/bin"; printf '#!/usr/bin/env bash\n# pre---patch exec.sh\nexit 0\n' > "$P/bin/exec.sh"; chmod +x "$P/bin/exec.sh"
OUT="$("$DOCTOR" --fix-property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "upgrade-bin exec.sh" && ok "exec.sh without --patch: refused, names the upgrade" || bad "old exec.sh: rc=$RC" "$OUT"
# An exec.sh with the --patch contract (project-bin/exec.sh: `bash <script> <model.mpr> [args...]`).
cat > "$P/bin/exec.sh" <<'EX'
#!/usr/bin/env bash
# stub of the --patch contract; PATCH_MODE
echo "exec.sh $*" >> .exec-log
[ "$1" = --patch ] || exit 9
shift; s="$1"; shift
bash "$s" "$(pwd)/App.mpr" "$@"
EX
chmod +x "$P/bin/exec.sh"
OUT="$("$DOCTOR" --fix-property-sets "$P" 2>&1)"; RC=$?
grep -q -- "--patch $TK/bin/doctor.sh --property-sets-apply-step $P/mxcli" "$P/.exec-log" 2>/dev/null \
  && ok "repair dispatched as exec.sh --patch doctor.sh --property-sets-apply-step <mxcli>" || bad "dispatch" "$(cat "$P/.exec-log" 2>&1)"
grep -qx "fix property-sets -p $P/App.mpr" "$P/.stub-log" && ok "the patch step ran the write form on the model" || bad "write form" "$(cat "$P/.stub-log")"
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "re-checking" && sed -n 1p "$P/.claude/.property-sets-receipt" | grep -q " clean " \
  && ok "re-checked after the repair: clean, exit 0" || bad "post-repair rc=$RC" "$OUT"
P="$(mkproj fix-clean)"; echo clean > "$P/.stub-state"; mkdir -p "$P/bin"; cp "$WORK/fix-noexec/bin/exec.sh" "$P/bin/"
"$DOCTOR" --fix-property-sets "$P" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 0 ] && [ ! -f "$P/.exec-log" ] && ok "clean model: no repair dispatched" || bad "clean model dispatched a repair (rc=$RC)"
# exec.sh exit 4 (#443): the patch was kept on a passed gate and only lint rose. Not a failed repair.
P="$(mkproj fix-lint4)"; mkdir -p "$P/bin"
sed 's/^bash "\$s" "\$(pwd)\/App.mpr" "\$@"$/bash "$s" "$(pwd)\/App.mpr" "$@" || exit 1; exit 4/' "$WORK/fix-noexec/bin/exec.sh" > "$P/bin/exec.sh"
chmod +x "$P/bin/exec.sh"; grep -q 'exit 4$' "$P/bin/exec.sh" || bad "P7b stub was not rewritten"
OUT="$("$DOCTOR" --fix-property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "repair kept; exec.sh reports a lint rise" && printf '%s' "$OUT" | grep -q "re-checking" \
  && ! printf '%s' "$OUT" | grep -q "the repair was not kept" \
  && ok "exec.sh exit 4: repair reported kept, re-checked, exit 0" || bad "exit-4 repair rc=$RC" "$OUT"

echo "== P8 --quick compares the receipt with the installed mxcli =="
P="$(mkproj quick)"; echo clean > "$P/.stub-state"
OUT="$("$DOCTOR" --quick "$P" 2>&1)"
printf '%s' "$OUT" | grep -q "WARN  property sets not checked for this mxcli" && ok "no receipt: WARN (exec.sh surfaces it)" || bad "no receipt" "$(printf '%s' "$OUT" | grep -i -A2 'property')"
grep -q -- '--dry-run' "$P/.stub-log" && bad "--quick ran the model check" || ok "--quick did not run the model check"
"$DOCTOR" --property-sets "$P" >/dev/null 2>&1
OUT="$("$DOCTOR" --quick "$P" 2>&1)"
printf '%s' "$OUT" | grep -q "ok    property sets: last check for this mxcli was clean" && ok "receipt current + clean: ok line" || bad "current receipt" "$(printf '%s' "$OUT" | grep -i -A2 'property')"
echo needs > "$P/.stub-state"; "$DOCTOR" --property-sets "$P" >/dev/null 2>&1
OUT="$("$DOCTOR" --quick "$P" 2>&1)"
printf '%s' "$OUT" | grep -q "WARN  property sets: last check for this mxcli:.* needs " && ok "receipt says needs: WARN persists" || bad "needs receipt" "$(printf '%s' "$OUT" | grep -i -A2 'property')"

echo "== P9 sync-project.sh runs the check, never the repair =="
S="$WORK/syncp"; mkdir -p "$S"; : > "$S/App.mpr"
MXTK_NO_GUIDE=1 "$TK/bin/init-project.sh" "$S" >/dev/null 2>&1
[ -f "$S/CLAUDE.local.md" ] || { echo "FIXTURE ERROR: init did not scaffold $S"; exit 2; }
mkstub "$S"; echo needs > "$S/.stub-state"
OUT="$("$SYNC" "$S" --dry-run 2>&1)"
printf '%s' "$OUT" | grep -q "Would run: bin/doctor.sh --property-sets --if-stale" && ok "--dry-run: says it would run the check" || bad "dry-run line" "$(printf '%s' "$OUT" | tail -5)"
[ ! -f "$S/.stub-log" ] || ! grep -q property-sets "$S/.stub-log" && ok "--dry-run: did not run it" || bad "--dry-run ran mxcli"
OUT="$("$SYNC" "$S" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "WARN  property sets: 1 unit(s) need" && ok "plain sync: check runs, its WARN shown" || bad "plain sync rc=$RC" "$(printf '%s' "$OUT" | grep -i -B1 -A3 'property')"
printf '%s' "$OUT" | grep -q "⚠️  property sets: Studio Pro's merge/diff can throw" && ok "plain sync: counted as a sync warning with the repair command" || bad "sync warning" "$(printf '%s' "$OUT" | grep -i 'property')"
grep -v -- '--dry-run' "$S/.stub-log" | grep -q 'property-sets' && bad "sync wrote to the model" || ok "sync did not repair"
n1="$(grep -c -- '--dry-run' "$S/.stub-log")"; "$SYNC" "$S" >/dev/null 2>&1; n2="$(grep -c -- '--dry-run' "$S/.stub-log")"
[ "$n2" -eq $((n1 + 1)) ] && ok "second sync, receipt says needs: re-checked" || bad "needs not re-checked: $n1 -> $n2"
echo clean > "$S/.stub-state"; "$SYNC" "$S" >/dev/null 2>&1
n3="$(grep -c -- '--dry-run' "$S/.stub-log")"; "$SYNC" "$S" >/dev/null 2>&1; n4="$(grep -c -- '--dry-run' "$S/.stub-log")"
[ "$n3" -eq "$n4" ] && ok "sync after a clean check, same mxcli: not re-run" || bad "clean re-ran: $n3 -> $n4"

S3="$WORK/syncold"; mkdir -p "$S3"; : > "$S3/App.mpr"
MXTK_NO_GUIDE=1 "$TK/bin/init-project.sh" "$S3" >/dev/null 2>&1
mkstub "$S3"; echo v0.25.0 > "$S3/.stub-ver"
OUT="$("$SYNC" "$S3" 2>&1)"
psl="$(printf '%s\n' "$OUT" | grep -i 'property' )"
printf '%s' "$psl" | grep -q "info  property sets: .*arrived in v0.26.0" && ! printf '%s' "$psl" | grep -q "WARN  \|⚠️" \
  && ok "sync, mxcli < v0.26: informational line, no WARN, no sync warning" || bad "sync old mxcli" "$psl"

printf '%s' "$OUT" | grep -q "checking property sets (read-only, up to 120s)" && ok "sync announces the check and its 120 s bound" || bad "no announcement" "$(printf '%s' "$OUT" | grep -i property)"
S4="$WORK/syncerr"; mkdir -p "$S4"; : > "$S4/App.mpr"
MXTK_NO_GUIDE=1 "$TK/bin/init-project.sh" "$S4" >/dev/null 2>&1
mkstub "$S4"; echo notfound > "$S4/.stub-state"
OUT="$("$SYNC" "$S4" 2>&1)"
psl="$(printf '%s\n' "$OUT" | grep -i 'property')"
printf '%s' "$psl" | grep -q "could not check property sets: could not classify" && ! printf '%s' "$psl" | grep -q "fix-property-sets\|⚠️\|WARN  " \
  && ok "sync, check errored (exit 4): neutral line, no repair advice, no warning" || bad "sync error case" "$psl"

echo "== P11 mxcli v0.29.0 MIXED rows (real captures): a merge hazard, not 'could not classify' =="
# Against doctor.sh before the v0.29 compat fix: the MIXED-only dry-run is rc 4 "could not
# classify", and the repair's exit 1 (for MIXED alone) rolls the completed NEEDS repair back.
# Measured 2026-10-30: master 74 passed, 7 failed; this fix 81 passed, 0 failed.
P="$(mkproj mixed)"; echo v0.29.0 > "$P/.stub-ver"; echo mixed > "$P/.stub-state"
OUT="$("$DOCTOR" --property-sets "$P" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "WARN  property sets: 1 property name(s) differ between elements of one type (MIXED)" \
  && ok "MIXED only: exit 1, WARN names it" || bad "MIXED only: rc=$RC" "$OUT"
printf '%s' "$OUT" | grep -q 'MIXED     Texts\$Translation.LanguageCode: on 260 of 261' && ok "the MIXED row is shown" || bad "MIXED row not shown" "$OUT"
printf '%s' "$OUT" | grep -q "fix-property-sets cannot clear them" && ! printf '%s' "$OUT" | grep -q "repair (snapshot" \
  && ok "says the repair cannot clear it, offers no repair" || bad "MIXED remedy" "$OUT"
sed -n 1p "$P/.claude/.property-sets-receipt" 2>/dev/null | grep -q " mixed " && ok "receipt records mixed" || bad "receipt" "$(cat "$P/.claude/.property-sets-receipt" 2>&1)"
P="$(mkproj both)"; echo v0.29.0 > "$P/.stub-ver"; echo both > "$P/.stub-state"; mkdir -p "$P/bin"; cp "$WORK/fix-noexec/bin/exec.sh" "$P/bin/"
OUT="$("$DOCTOR" --fix-property-sets "$P" 2>&1)"; RC=$?
printf '%s' "$OUT" | grep -q "the repair was not kept" && bad "NEEDS + MIXED: the completed repair was rolled back" "$OUT" \
  || ok "NEEDS + MIXED: the repair step's exit 1 for MIXED alone does not fail the patch"
printf '%s' "$OUT" | grep -q "FIXED     84776610" && printf '%s' "$OUT" | grep -q "re-checking" && ok "repair ran and was re-checked" || bad "repair/re-check" "$OUT"
[ "$RC" -eq 1 ] && sed -n 1p "$P/.claude/.property-sets-receipt" | grep -q " mixed " && ok "after the repair: mixed left, exit 1" || bad "post-repair rc=$RC" "$(cat "$P/.claude/.property-sets-receipt" 2>&1)"
S5="$WORK/syncmixed"; mkdir -p "$S5"; : > "$S5/App.mpr"
MXTK_NO_GUIDE=1 "$TK/bin/init-project.sh" "$S5" >/dev/null 2>&1
mkstub "$S5"; echo v0.29.0 > "$S5/.stub-ver"; echo mixed > "$S5/.stub-state"
psl="$("$SYNC" "$S5" 2>&1 | grep -i 'property')"
printf '%s' "$psl" | grep -q "⚠️  property sets: Studio Pro's merge/diff can throw" && ! printf '%s' "$psl" | grep -q "Repair, gated" \
  && ok "sync, MIXED only: a sync warning, no repair command it cannot honour" || bad "sync MIXED" "$psl"

echo "== P10 (#236) sync names a pre-fix bin/model-stamp.sh =="
grep -v 'GIT_WORK_TREE' "$TK/project-bin/model-stamp.sh" > "$S/bin/model-stamp.sh"; chmod +x "$S/bin/model-stamp.sh"
OUT="$("$SYNC" "$S" --dry-run --no-refresh 2>&1)"
printf '%s' "$OUT" | grep -q "bin/model-stamp.sh is LOCALLY MODIFIED" && ok "pre-fix copy reported as modified" || bad "not reported" "$(printf '%s' "$OUT" | grep model-stamp)"
printf '%s' "$OUT" | grep -q "predates the HOOK BLIND-SPOT fix.*--upgrade-bin model-stamp.sh --upgrade-bin _common.sh" && ok "known-fix note names the blind spot and both files" || bad "no HOOK BLIND-SPOT note" "$(printf '%s' "$OUT" | grep -A1 model-stamp)"
{ cat "$TK/project-bin/model-stamp.sh"; echo "# local edit"; } > "$S/bin/model-stamp.sh"
OUT="$("$SYNC" "$S" --dry-run --no-refresh 2>&1)"
printf '%s' "$OUT" | grep -q "HOOK BLIND-SPOT" && bad "a fixed-but-edited copy got the note" || ok "a fixed-but-edited copy gets no note"

echo ""
echo "property-sets: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
