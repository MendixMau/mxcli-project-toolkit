#!/usr/bin/env bash
# test-greenfield-retired.sh — greenfield is retired; sync-project.sh maps an old register.
#
# usage: bash tests/wave2/test-greenfield-retired.sh [path-to-sync-project.sh]
#
# Owner decision (2026-11-17): two doors replace greenfield — a real app is requirements-driven
# with the conversation as the source, a demo is Build type: poc. An existing register saying
# `Entry mode: greenfield` is mapped at sync to requirements-driven, adopted at the stage its
# readout shows, with the reason in the register and BUILD-LOG; under Interview mode: auto the
# adoption is a ✋ human-pending decision. An unsynced register is never treated as a valid mode.
#
#   U  unsynced: gate-check and status print the one "run sync" line; no stage is excused by it
#   M  sync maps the line (old line kept as a comment), adopts at the readout's stage, writes
#      ENTRY-MODE-MAPPED + TOOLKIT-ADOPTED-AT to docs/BUILD-LOG.md, says so once
#   A  under auto the adoption also writes the ASSUMED consentBy: auto-mode Stage-4 row
#   I  a second sync maps nothing; a readout at Stage P maps without adopting
#   G  a real scaffold (init-project.sh) whose readout gate-check itself wrote (Stage P or 0 — the
#      greenfield norm: Stage 0 was never excused): with model work (a mdlsource/*.mdl script, or
#      an exec row in docs/BUILD-LOG.md) sync adopts at 5, Stage 4 is not PENDING and an exec
#      under Interview mode: auto is not refused; with none, nothing is adopted and the owed
#      stages are said out loud — never "not re-owed" (found in the #792 review)
#
# Golden register: fixtures/entry-mode-plan-rule/PROJECT.md (captured from init-project.sh).
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC="${1:-$TOOLKIT/bin/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
GOLD="$TOOLKIT/tests/wave2/fixtures/entry-mode-plan-rule"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gf-retired.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SYNC"
export MXTK_NO_GUIDE=1 HOME="$WORK/home" MXTK_LEAKGUARD_DENYFILE="$WORK/denylist"   # init-project.sh (case G) must not touch the real one

# mkproj <readout stage> <extra register lines> -> P
N=0
mkproj() {
  N=$((N+1)); P="$WORK/p$N"; mkdir -p "$P"
  cp "$GOLD/PROJECT.md" "$GOLD/intake.md" "$P/"
  awk -v st="$1" '/^\*\*Stage P / { print "**Stage " st " — Build**, in progress."; next } { print }' \
    "$GOLD/PROJECT.md" > "$P/PROJECT.md"
  printf '%b' "$2" >> "$P/PROJECT.md"
  ( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm f ) >/dev/null 2>&1
}

echo "-- U: unsynced"
mkproj 5 'Entry mode: greenfield\n'
G="$("$TOOLKIT/bin/gate-check.sh" "$P" 2>&1)"
case "$G" in *"Entry mode greenfield is retired: run bin/sync-project.sh"*) ok "U gate-check says run sync" ;; *) bad "U gate-check says run sync" ;; esac
case "$G" in *"not owed (mode: greenfield)"*) bad "U greenfield excused stages" ;; *) ok "U greenfield excuses no stage" ;; esac
S="$("$TOOLKIT/bin/status.sh" "$P" --brief 2>&1)"
case "$S" in *"Entry mode greenfield is retired"*) ok "U status says so" ;; *) bad "U status says so" ;; esac

echo "-- M: the mapping"
mkproj 5 'Entry mode: greenfield\n'
"$SYNC" "$P" > "$WORK/s1" 2>&1
[ "$(grep -c 'Mapped: PROJECT.md Entry mode greenfield → requirements-driven' "$WORK/s1")" = 1 ] && ok "M said once" || bad "M said once" "$(grep -c Mapped "$WORK/s1")"
grep -q '^Entry mode: requirements-driven$' "$P/PROJECT.md" && ok "M register line mapped" || bad "M register line mapped"
grep -q '^<!-- was: Entry mode: greenfield — greenfield retired, mapped at sync ' "$P/PROJECT.md" && ok "M old line kept as a comment" || bad "M old line kept as a comment"
grep -q '^Adopted at stage: 5 — greenfield retired, mapped at sync$' "$P/PROJECT.md" && ok "M adopted at the readout's stage" || bad "M adopted at the readout's stage" "$(grep -n Adopted "$P/PROJECT.md")"
grep -q 'ENTRY-MODE-MAPPED greenfield -> requirements-driven: greenfield retired, mapped at sync (adopted at stage 5)' "$P/docs/BUILD-LOG.md" \
  && grep -q 'TOOLKIT-ADOPTED-AT 5 reason: greenfield retired, mapped at sync' "$P/docs/BUILD-LOG.md" && ok "M BUILD-LOG rows" || bad "M BUILD-LOG rows"
grep -q 'consentBy: auto-mode' "$P/PROJECT.md" && bad "M no ✋ row without auto" || ok "M no ✋ row without auto"

echo "-- A: under auto"
mkproj 5 'Entry mode: greenfield\nInterview mode: auto\n'
"$SYNC" "$P" > /dev/null 2>&1
grep -qE '^\| 4 \| Adopted at stage 5 .*greenfield retired, mapped at sync \| ASSUMED \| consentBy: auto-mode' "$P/PROJECT.md" \
  && ok "A ✋ human-pending Stage-4 row" || bad "A ✋ human-pending Stage-4 row"

echo "-- I: idempotent, and Stage P"
"$SYNC" "$P" > "$WORK/s2" 2>&1
grep -q 'Mapped: PROJECT.md' "$WORK/s2" && bad "I second sync maps again" || ok "I second sync maps nothing"
[ "$(grep -c '^Adopted at stage' "$P/PROJECT.md")" = 1 ] && ok "I one adoption line" || bad "I one adoption line"
mkproj P 'Entry mode: greenfield\n'
"$SYNC" "$P" > /dev/null 2>&1
grep -q '^Entry mode: requirements-driven$' "$P/PROJECT.md" && ! grep -q '^Adopted at stage' "$P/PROJECT.md" \
  && ok "I Stage P readout: mapped, not adopted" || bad "I Stage P readout: mapped, not adopted"

echo "-- G: real scaffold, readout written by gate-check (Stage P/0), model work decides"
S0="$WORK/scaffold"
"$TOOLKIT/bin/init-project.sh" "$S0" > /dev/null 2>&1 || bad "G init-project.sh scaffold"
printf 'Entry mode: greenfield\nInterview mode: auto\n' >> "$S0/PROJECT.md"
mkdir -p "$S0/mprcontents"; printf 'not a real model\n' > "$S0/App.mpr"; printf 'bson\n' > "$S0/mprcontents/a.mxunit"
cat > "$S0/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in check) echo check >> "$CALLS"; echo "stub refuses [STUB01]" >&2; exit 1 ;; esac
exit 0
MXCLI
chmod +x "$S0/mxcli"
# gfproj <name> <work: mdl|log|none> -> P, scaffold copy with its readout stamped by gate-check
gfproj() {
  P="$WORK/$1"; cp -R "$S0" "$P"
  case "$2" in
    mdl) mkdir -p "$P/mdlsource"; printf 'CREATE ENTITY Orders.Thing (Name: String);\n' > "$P/mdlsource/01-thing.mdl" ;;
    log) mkdir -p "$P/docs"; printf '| when | script | gate | result | detail |\n|---|---|---|---|---|\n| 2026-11-01T10:00:00+0000 | `01-thing.mdl` | pass | ✓ applied | x |\n' > "$P/docs/BUILD-LOG.md" ;;
  esac
  ( cd "$P" && { [ -d .git ] || git init -q .; } && git add -A && git -c user.email=t@t -c user.name=t commit -qm f -n ) >/dev/null 2>&1
  "$TOOLKIT/bin/gate-check.sh" "$P" > /dev/null 2>&1
  GF_RO="$(sed -n 's/^\*\*Stage \([P0-7]\) .*/\1/p' "$P/PROJECT.md" | head -1)"
}
gfproj g1 mdl
case "$GF_RO" in P|0) ok "G gate-check's own readout is Stage $GF_RO" ;; *) bad "G gate-check's own readout" "Stage '$GF_RO'" ;; esac
"$SYNC" "$P" > "$WORK/sg1" 2>&1
grep -q '^Adopted at stage: 5 — greenfield retired, mapped at sync$' "$P/PROJECT.md" && ok "G model work (mdlsource) → adopted at stage 5" || bad "G model work (mdlsource) → adopted at stage 5" "$(grep -n 'Adopted\|Mapped' "$WORK/sg1" "$P/PROJECT.md" | head -3)"
"$TOOLKIT/bin/gate-check.sh" "$P" > "$WORK/gg1" 2>&1
grep -q '^Stage 4 ([^)]*): PENDING' "$WORK/gg1" && bad "G Stage 4 not PENDING" "$(grep '^Stage 4' "$WORK/gg1" | cut -c1-120)" || ok "G Stage 4 not PENDING"
( cd "$P" && CALLS="$WORK/calls-g1" SP_RESTART=0 MXTK_NO_INSTALL=1 SKIP_DOCTOR=1 TMPDIR="$WORK" ./bin/exec.sh mdlsource/01-thing.mdl ) > "$WORK/eg1" 2>&1
grep -q 'Plan rule (Interview mode: auto)' "$WORK/eg1" && bad "G exec under auto not refused by the plan rule" || \
  { [ -s "$WORK/calls-g1" ] && ok "G exec under auto not refused by the plan rule (reached mxcli check)" || bad "G exec reached mxcli check" "$(tail -3 "$WORK/eg1")"; }
gfproj g2 log
"$SYNC" "$P" > /dev/null 2>&1
grep -q '^Adopted at stage: 5 — greenfield retired, mapped at sync$' "$P/PROJECT.md" && ok "G model work (BUILD-LOG exec row) → adopted at stage 5" || bad "G model work (BUILD-LOG exec row) → adopted at stage 5"
gfproj g3 none
"$SYNC" "$P" > "$WORK/sg3" 2>&1
grep -q '^Adopted at stage' "$P/PROJECT.md" && bad "G no model work → not adopted" || ok "G no model work → not adopted"
grep -q 'stages 0-4 are now OWED' "$WORK/sg3" && ok "G no model work → owed stages said out loud" || bad "G no model work → owed stages said out loud"
grep -q 'not re-owed' "$WORK/sg3" && bad "G no adoption → never says 'not re-owed'" || ok "G no adoption → never says 'not re-owed'"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
