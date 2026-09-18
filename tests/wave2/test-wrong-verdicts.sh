#!/usr/bin/env bash
# Fixture for the "wrong verdict" group — four defects in which a toolkit instrument
# reports a verdict the evidence does not support.
#
#   V1  project-bin/snapshot-mpr.sh dies SILENTLY on a v1 single-file model. `find` on a
#       nonexistent $DEST/mprcontents exits 1, pipefail propagates, set -e kills the script
#       — so the v1-aware refusal further down (which literally says "if the model is
#       genuinely v1 single-file") is unreachable for the case it names. Exit 1, no message,
#       and a half-snapshot left on disk that exec.sh will treat as a net.
#   V2  bin/gate-check.sh check_stage_3() accepts ZERO-BYTE artifacts. resolve_artifact()
#       tests [ -e ]. Four empty files discharge a sign-off gate.
#   V3  the same line rejects a REAL wireframe at design/wireframes/<flow>/list.html,
#       because it is -maxdepth 1. Accepts the empty one, rejects the real one.
#   V4  the entry-mode parsers in bin/gate-check.sh and bin/lib/artifact-check.sh use
#       unanchored globs with first-arm-wins, so "migration (not greenfield)" parses as
#       greenfield and stage_waiver() excuses stages on the wrong label.
#
# Usage: test-wrong-verdicts.sh /path/to/gate-check.sh
#
# The toolkit root is derived from that path, because three of the four subjects live in
# it (gate-check.sh, lib/entry-mode.sh, project-bin/snapshot-mpr.sh).
#
# POSITIVE CONTROL. Run it against a PRE-fix checkout and V1, V2, V3 and V4 must FAIL.
# A suite that has only ever seen the fix cannot show that it discriminates. Cases marked
# [guard] pass on both and are regression guards, not discriminators.
#
# Nothing here touches a real .mpr, a real mxcli or a real mxbuild.
set -uo pipefail

GC="${1:?usage: test-wrong-verdicts.sh /path/to/gate-check.sh}"
case "$GC" in /*) ;; *) GC="$PWD/$GC" ;; esac
TK="$(cd "$(dirname "$GC")/.." && pwd)"
WORK="$(mktemp -d /tmp/wrongverdict.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
trap 'rm -rf "$WORK"' EXIT

# ── V1. snapshot-mpr.sh on a v1 single-file model ────────────────────────────
mk_model() {  # mk_model <dir> <units...>
  local d="$1"; shift
  mkdir -p "$d/bin"; ( cd "$d" && git init -q . )
  printf 'v1 index\n' > "$d/Legacy.mpr"
  cp "$TK/project-bin/_common.sh" "$d/bin/_common.sh"
  cp "$TK/project-bin/snapshot-mpr.sh" "$d/bin/snapshot-mpr.sh"
  chmod +x "$d/bin/snapshot-mpr.sh"
  if [ "$#" -gt 0 ]; then mkdir -p "$d/mprcontents"; for u in "$@"; do printf 'bson\n' > "$d/mprcontents/$u"; done; fi
}

P="$WORK/v1"; mk_model "$P"
OUT="$( cd "$P" && ./bin/snapshot-mpr.sh 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ]; then ok "V1 v1 single-file model snapshots successfully (rc=0)"
else bad "V1 v1 single-file model: rc=$RC, output: ${OUT:-<silent>}"; fi
case "$OUT" in *"v1 single-file"*) ok "V1 success line names the format, so 0 units is not read as half a snapshot";;
                *) bad "V1 success line does not name the v1 format: $OUT";; esac

P="$WORK/v1empty"; mk_model "$P"; mkdir -p "$P/mprcontents"
OUT="$( cd "$P" && ./bin/snapshot-mpr.sh 2>&1 )"; RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'fault, not a format'; then
  ok "V1 empty mprcontents/ is still refused LOUDLY — a fault, not a format"
else bad "V1 empty mprcontents/ not refused with a clear message (rc=$RC): $OUT"; fi

P="$WORK/v2"; mk_model "$P" a.mxunit b.mxunit
OUT="$( cd "$P" && ./bin/snapshot-mpr.sh 2>&1 )"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '2 units'; then ok "V1 [guard] v2 model still snapshots both parts"
else bad "V1 [guard] v2 regression (rc=$RC): $OUT"; fi

# ── V2 / V3. check_stage_3 content tests ─────────────────────────────────────
stage3() { "$GC" "$1" 3 2>&1 | grep -E '^Stage 3' | head -1; }

Z="$WORK/zero"; mkdir -p "$Z/architecture" "$Z/design/wireframes"
: > "$Z/architecture/fit-gap.md"; : > "$Z/design/design-system.html"
: > "$Z/architecture/blueprint.html"; : > "$Z/design/wireframes/a.html"
OUT="$(stage3 "$Z")"
if printf '%s' "$OUT" | grep -qi 'EMPTY (0 bytes)'; then ok "V2 zero-byte artifacts are named as empty, not counted as present"
else bad "V2 zero-byte artifacts accepted: $OUT"; fi
case "$OUT" in *"artifacts exist"*) bad "V2 gate advanced to sign-off on four empty files";; *) ok "V2 gate did not advance to sign-off on empty artifacts";; esac

N="$WORK/nested"; mkdir -p "$N/architecture" "$N/design/wireframes/flow"
printf 'x\n' > "$N/architecture/fit-gap.md"; printf 'x\n' > "$N/design/design-system.html"
printf 'x\n' > "$N/architecture/blueprint.html"; printf '<html>real</html>\n' > "$N/design/wireframes/flow/list.html"
OUT="$(stage3 "$N")"
if printf '%s' "$OUT" | grep -qi 'wireframe.*missing\|NOT STARTED'; then
  bad "V3 a real nested wireframe is still invisible: $OUT"
else ok "V3 nested design/wireframes/<flow>/list.html is found"; fi

M="$WORK/partial"; mkdir -p "$M/architecture" "$M/design/wireframes"
printf 'x\n' > "$M/design/design-system.html"; printf 'x\n' > "$M/architecture/blueprint.html"
printf '<html>w</html>\n' > "$M/design/wireframes/a.html"     # only fit-gap.md absent
OUT="$(stage3 "$M")"
if printf '%s' "$OUT" | grep -q 'present:' && printf '%s' "$OUT" | grep -q 'fit-gap.md'; then
  ok "V3 one line reports what is missing AND what is present, not just the first gap"
else bad "V3 report is still first-failure-only: $OUT"; fi

# ── V4. entry-mode tokeniser ─────────────────────────────────────────────────
if [ -f "$TK/bin/lib/entry-mode.sh" ]; then
  # shellcheck disable=SC1090
  . "$TK/bin/lib/entry-mode.sh"
  check() { local got; got="$(entry_mode_token "$1" 2>/dev/null)"
    if [ "$got" = "$2" ]; then ok "V4 '$1' -> $2"; else bad "V4 '$1' -> '$got', expected '$2'"; fi; }
  check "migration (not greenfield)" "migration"
  check "migration, phase 2"         "migration"
  check "Greenfield"                 "greenfield"
  check "requirements"               "requirements-driven"
  check "existing-app-change"        "existing-app-change"
  # The runbook's own label for the fourth mode. Its first word is "change", so a
  # first-word-only tokeniser resolves it to "" and the mode silently disappears — the
  # same class of bug as the unanchored glob, failing safe instead of loud but still wrong.
  check "Change an existing app"     "existing-app-change"
  check "change an existing app (CONFIRMED)" "existing-app-change"
  # ...and the phrase arm must not swallow a migration that merely mentions "existing".
  check "Migration from an existing Oracle Forms system" "migration"
  check "banana"                     ""
  if entry_mode_token "banana" 2>&1 >/dev/null | grep -q 'not recognised'; then
    ok "V4 an unrecognised mode says so on stderr instead of failing silently"
  else bad "V4 unrecognised mode is still silent"; fi
else
  bad "V4 bin/lib/entry-mode.sh absent — both parsers still carry their own unanchored globs"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
