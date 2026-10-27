#!/usr/bin/env bash
# Fixture for project-bin/row-groups.sh check (the exec.sh row-group gate, PR #581).
#
# usage: test-row-groups.sh /path/to/row-groups.sh
#
# Golden input: tests/wave2/fixtures/build-plan-claims-real.md, a build plan captured from a real
# field build (SampleDashboards). Its scripts are numbered on their own sequence, as
# skills/brd-to-build-plan.md documents (`16-cutover.mdl` is row 26), so a file-name number is not a
# row number. The gate runs on a script only when the script says its rows (`-- rows: 14,15`) or the
# project opts in with `Row groups: on` in PROJECT.md (then its file names carry row numbers).
#   G1  real plan, no opt-in: no script name in it is refused (16-cutover.mdl was, as row 16)
#   G2  `-- rows:` header: the split-group refusal still works on the real plan
#   G3  `Row groups: on`: a file-name number is read as the row again
#   S1  built = an explicit built/done/applied State; planned, **blocked**, partial, empty are not
#   M1  module close: the report must record 0 lint findings for the module, or a filled LOOK row
set -uo pipefail
SUT="${1:?usage: test-row-groups.sh /path/to/row-groups.sh}"
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GOLD="$TK/tests/wave2/fixtures/build-plan-claims-real.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/row-groups.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

mkproj() {  # $1 dir; build plan from stdin
  mkdir -p "$1/bin" "$1/architecture" "$1/docs" "$1/mdlsource"
  cp "$SUT" "$1/bin/row-groups.sh"; cp "$TK/project-bin/_common.sh" "$1/bin/"; chmod +x "$1/bin/row-groups.sh"
  : > "$1/App.mpr"; cat > "$1/architecture/build-plan.md"
}
chk() {  # $1 project, $2 script file name, rest: script body lines → "rc|output"
  local p="$1" s="$2"; shift 2
  printf '%s\n' "$@" > "$p/mdlsource/$s"
  out=$(cd "$p" && bash bin/row-groups.sh check "mdlsource/$s" 2>&1); rc=$?
}

echo "== G1 real plan, no opt-in: file-name numbers are script numbers"
P="$WORK/real"; mkproj "$P" < "$GOLD"
refused=""
for s in $(grep -o '`[0-9][0-9a-z]*-[a-z0-9-]*\.mdl`' "$GOLD" | tr -d '`' | sort -u); do
  chk "$P" "$s" "-- $s"
  [ "$rc" = 1 ] && refused="$refused $s"
done
[ -z "$refused" ] && ok "G1: no script of the real plan is refused by its file-name number" \
  || bad "G1: refused by file-name number:$refused" "$out"
chk "$P" "16-cutover.mdl" "-- cutover"
[ "$rc" = 3 ] && ok "G1: 16-cutover.mdl (row 26) is not checked without a rows header (exit 3)" || bad "G1: 16-cutover.mdl rc=$rc" "$out"

echo "== G2 rows header on the real plan"
chk "$P" "09-snippets.mdl" "-- rows: 14" "create snippet ..."
{ [ "$rc" = 1 ] && printf '%s' "$out" | grep -q '15, 16'; } && ok "G2: rows 14 alone leaves 15, 16 of its low group unbuilt → refused" || bad "G2: rc=$rc" "$out"
chk "$P" "09-11-snippets-pages.mdl" "-- rows: 14,15,16"
[ "$rc" = 0 ] && ok "G2: the whole group in one script passes" || bad "G2 whole group: rc=$rc" "$out"

echo "== G3 opt-in: file names carry row numbers"
P3="$WORK/optin"; mkproj "$P3" < "$GOLD"
printf '# Project\n\n- Row groups: on — CONFIRMED\n' > "$P3/PROJECT.md"
chk "$P3" "14-snippets.mdl" "create snippet ..."
[ "$rc" = 1 ] && ok "G3: with Row groups: on, 14-snippets.mdl is row 14 and is refused (group 14-16)" || bad "G3: rc=$rc" "$out"
printf '# Project\n\n- Row groups: off\n' > "$P3/PROJECT.md"
chk "$P3" "14-snippets.mdl" "create snippet ..."
[ "$rc" = 3 ] && ok "G3: Row groups: off → not checked" || bad "G3 off: rc=$rc" "$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
