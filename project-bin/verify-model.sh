#!/usr/bin/env bash
# verify-model.sh — run the mxbuild gate on the model AS IT IS, and stamp it if clean.
#
#   ./bin/verify-model.sh            # mxbuild --target=deploy, print the error count, stamp on 0
#   ./bin/verify-model.sh --no-stamp # just the verdict
#
# The standalone half of the verification stamp (bin/model-stamp.sh). exec.sh stamps the
# model after its own gate passes; this stamps it after any OTHER kind of change — a
# Studio Pro save, a merge, a bare `mxcli exec` someone ran anyway, a fresh clone. It is
# the remedy the pre-commit hook (bin/install-project-hooks.sh) names when it refuses
# (rule 7: a guard never blocks the action that resolves it). It is NOT, by itself, the
# rule-6 evidence — model-stamp.sh, verify-model.sh and install-project-hooks.sh all ship
# in the same change, so a stamp only one of them can write is still "its own stamp
# file" collectively. The hook's independent evidence is a recent PASS row in
# docs/BUILD-LOG.md, written by exec.sh (pre-existing, unrelated code path) — see
# install-project-hooks.sh for that check.
#
# Same gate as exec.sh: mxbuild --target=deploy --write-errors, output captured to a file
# (never $(...) — Studio Pro 11's mxbuild.exe leaves a deno child holding stdout), stdin
# closed, empty errors file + exit 0 = 0 errors (SP 11 writes the file only when there
# are errors). When mxbuild is missing it is downloaded first (mxtk_ensure_mxbuild).
# Exit 0 = clean and stamped; 1 = errors; 2 = the gate could not run (nothing verified).
set -e
. "$(dirname "$0")/_common.sh"

MPR="$(find_mpr)" || exit 2
cd "$PROJECT_ROOT"
STAMP=1; [ "${1:-}" = "--no-stamp" ] && STAMP=0

MXBUILD="$(mxtk_ensure_mxbuild "$MPR" || true)"
JAVA_HOME="$(find_java 2>/dev/null || true)"
JAVA_EXE="$(find_java_exe 2>/dev/null || true)"
if [ ! -x "${MXBUILD:-/nonexistent}" ] || [ ! -x "${JAVA_EXE:-/nonexistent}" ]; then
  echo "✗ the mxbuild gate cannot run on this machine — NOTHING was verified."
  [ -x "${MXBUILD:-/nonexistent}" ]  || echo "    mxbuild: ${MXBUILD:-<none>}   (MXBUILD_PATH= overrides; bin/doctor.sh --install downloads it)"
  [ -x "${JAVA_EXE:-/nonexistent}" ] || echo "    java:    ${JAVA_EXE:-<none>}  (JAVA_HOME= overrides)"
  exit 2
fi

PY="$(resolve_py || true)"
if [ -z "$PY" ]; then
  echo "✗ no working Python 3 — the gate cannot read mxbuild's errors file. NOTHING was verified."  # portability-ok: diagnostic
  exit 2
fi

echo "→ mxbuild gate on $(basename "$MPR") ($MXBUILD)..."
ERR="$(mktemp "${TMPDIR:-/tmp}/verify-model-errors.XXXXXX")"; OUT="$(mktemp "${TMPDIR:-/tmp}/verify-model-out.XXXXXX")"
RC=0
"$MXBUILD" --java-home="$JAVA_HOME" --java-exe-path="$JAVA_EXE" --write-errors="$ERR" --target=deploy "$MPR" > "$OUT" 2>&1 < /dev/null || RC=$?

if [ ! -s "$ERR" ] && [ "$RC" -eq 0 ]; then
  COUNT=0; CODES=""
elif [ -s "$ERR" ]; then
  COUNT="$("$PY" -c "import json;d=json.load(open('$(native_path "$ERR")'));print(len([x for x in d.get('problems',[]) if x.get('severity')=='Error']))" 2>/dev/null || echo "?")"
  CODES="$("$PY" -c "import json;d=json.load(open('$(native_path "$ERR")'));print(','.join(sorted({x.get('errorCode','?') for x in d.get('problems',[]) if x.get('severity')=='Error'})))" 2>/dev/null || echo "?")"
else
  COUNT="?"; CODES=""
fi

if [ "$COUNT" = "?" ]; then
  echo "✗ mxbuild exited $RC and its errors file could not be read — NOTHING was verified."
  grep -v '^$' "$OUT" | tail -15 | sed 's/^/    /'
  rm -f "$ERR" "$OUT"; exit 2
fi
if [ "$COUNT" != "0" ]; then
  echo "✗ mxbuild: $COUNT error(s) [$CODES] — the model is NOT clean."
  "$PY" -c "import json;d=json.load(open('$(native_path "$ERR")'))
for x in [p for p in d.get('problems',[]) if p.get('severity')=='Error'][:15]:
    print('    %s  %s  %s' % (x.get('errorCode','?'), x.get('documentName') or x.get('document') or '', (x.get('message') or '')[:140]))" 2>/dev/null || true
  [ "$STAMP" = 1 ] && ./bin/model-stamp.sh clear >/dev/null 2>&1 || true
  rm -f "$ERR" "$OUT"; exit 1
fi
echo "✓ mxbuild: 0 errors — model is clean."
rm -f "$ERR" "$OUT"
[ "$STAMP" = 1 ] && ./bin/model-stamp.sh write pass "verify-model.sh"
exit 0
