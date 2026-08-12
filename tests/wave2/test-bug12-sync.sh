#!/usr/bin/env bash
# Fixtures for wave-2 #12 (sync-project.sh never refreshes the project's bin/, then reports
# success) and wave-2 #1 (a stale intake Q9 can never be repaired, because the guard tests the
# HEADING while 12828e4 changed the BODY).
#
# Run against the PRE-fix script — `git show 2ea198c:bin/sync-project.sh` written into the
# toolkit's bin/ — and it must fail T1..T8. A suite that has only ever seen the fix cannot show
# that it discriminates.
#
# Every fixture is built by the REAL bin/init-project.sh, under /tmp. No real project is touched.
set -uo pipefail

SYNC="${1:?usage: test-bug12-sync.sh /path/to/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
TK="$(cd "$(dirname "$SYNC")/.." && pwd)"
INIT="$TK/bin/init-project.sh"
GATE="$TK/bin/gate-check.sh"
WORK="$(mktemp -d /tmp/bug12.XXXXXX)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# A fingerprint of the whole tree: path, size, exec bit, content hash. Anything a run writes
# shows up here — "wrote nothing" is otherwise unfalsifiable.
fingerprint() {
  find "$1" -type f 2>/dev/null | LC_ALL=C sort | while read -r f; do
    if [ -x "$f" ]; then x=x; else x=-; fi
    printf '%s %s %s\n' "${f#$1}" "$x" "$(md5 -q "$f" 2>/dev/null || md5sum "$f" | cut -d' ' -f1)"
  done
}

mkproj() {
  d="$WORK/$1"; mkdir -p "$d"; : > "$d/Fixture.mpr"
  MXTK_NO_GUIDE=1 "$INIT" "$d" >/dev/null 2>&1
  echo "$d"
}

# The pre-12828e4 Q9 body, byte-for-byte. Must match gate-check.sh's q9_stale_scaffold_text().
stale_q9() {
  cat <<'EOF'
## 9. Interview mode: attended (default) or unattended?

Attended unless the user explicitly says otherwise. Attended = every gate question is asked
in chat and the agent waits for the answer. Unattended (opt-in only) = recommended options
are applied as ASSUMED and questions are logged in PROJECT.md for later reconciliation.
EOF
}
# Replace the current Q9 section of $1 with the text on stdin.
set_q9() {
  awk '/^## 9\./{insec=1; next} insec && /^## /{insec=0} insec{next} {print}' "$1" > "$1.hd"
  mv "$1.hd" "$1"
  cat >> "$1"
}

echo "== T0: a pristine init'd project produces no warnings and no writes =="
P="$(mkproj t0)"
B="$(fingerprint "$P")"
OUT="$("$SYNC" "$P" --strict 2>&1)"; RC=$?
A="$(fingerprint "$P")"
[ "$B" = "$A" ] && ok "pristine project unmodified" || bad "pristine project was WRITTEN to"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '⚠️'; then
  ok "no false alarm on a pristine project (exit 0)"
else
  bad "false alarm on a pristine project (exit $RC)"
fi

echo "== T1: a MISSING crash-net script is installed =="
P="$(mkproj t1)"
rm -f "$P/bin/restore-mpr.sh"
"$SYNC" "$P" >/dev/null 2>&1
if [ -f "$P/bin/restore-mpr.sh" ] && [ -x "$P/bin/restore-mpr.sh" ]; then
  ok "restore-mpr.sh installed and executable"
else
  bad "missing crash-net script NOT installed"
fi

echo "== T2: a lost exec bit on an otherwise identical script is repaired =="
P="$(mkproj t2)"
chmod -x "$P/bin/snapshot-mpr.sh"
"$SYNC" "$P" >/dev/null 2>&1
[ -x "$P/bin/snapshot-mpr.sh" ] && ok "exec bit repaired" || bad "exec bit NOT repaired"

echo "== T3: a LOCALLY MODIFIED script is never overwritten without the flag =="
# The destructive case. exec.sh is locally modified in all 6 projects on this machine that have
# one; WMS-Demo's carries a build-rollback fix that never went upstream. A sync that overwrites
# here destroys real work in six projects at once.
P="$(mkproj t3)"
printf '#!/usr/bin/env bash\n# LOCAL HARDENING — do not lose this\nexit 0\n' > "$P/bin/exec.sh"
MINE="$(cat "$P/bin/exec.sh")"
OUT="$("$SYNC" "$P" 2>&1)"
if [ "$MINE" = "$(cat "$P/bin/exec.sh")" ]; then
  ok "locally-modified exec.sh survived"
else
  bad "locally-modified exec.sh was DESTROYED"
fi
# Surviving by accident (never looking at bin/) is the bug. The offer must be on screen.
if printf '%s' "$OUT" | grep -q 'LOCALLY MODIFIED' && printf '%s' "$OUT" | grep -q -- '--upgrade-bin exec.sh'; then
  ok "drift reported with the exact command to accept it"
else
  bad "drift not reported (silently skipped bin/)"
fi
# ...and no backup litter from a run that was supposed to write nothing to bin/.
if [ -z "$(find "$P/bin" -name '*.local-*' 2>/dev/null)" ]; then
  ok "no backup file written by a non-upgrade run"
else
  bad "non-upgrade run left a backup file behind"
fi

echo "== T4: --upgrade-bin accepts the toolkit version and backs the local copy up =="
P="$(mkproj t4)"
printf '#!/usr/bin/env bash\n# LOCAL HARDENING\nexit 0\n' > "$P/bin/exec.sh"
MINE="$(cat "$P/bin/exec.sh")"
"$SYNC" "$P" --upgrade-bin exec.sh >/dev/null 2>&1
BAK="$(find "$P/bin" -name 'exec.sh.local-*' | head -1)"
if cmp -s "$TK/project-bin/exec.sh" "$P/bin/exec.sh"; then
  ok "exec.sh upgraded to the toolkit version"
else
  bad "exec.sh not upgraded"
fi
if [ -n "$BAK" ] && [ "$MINE" = "$(cat "$BAK")" ] && [ ! -x "$BAK" ]; then
  ok "local copy preserved in a non-executable backup"
else
  bad "local copy not preserved (backup missing, wrong, or executable)"
fi

echo "== T5: --dry-run reports everything and writes nothing; --strict exits 3 =="
P="$(mkproj t5)"
rm -f "$P/bin/restore-mpr.sh"; chmod -x "$P/bin/snapshot-mpr.sh"
printf 'stale\n' > "$P/bin/exec.sh"
B="$(fingerprint "$P")"
OUT="$("$SYNC" "$P" --dry-run --strict 2>&1)"; RC=$?
A="$(fingerprint "$P")"
[ "$B" = "$A" ] && ok "--dry-run wrote nothing at all" || bad "--dry-run WROTE to the project"
if printf '%s' "$OUT" | grep -q 'Would install' && printf '%s' "$OUT" | grep -q 'Would chmod'; then
  ok "--dry-run reported the install and the chmod"
else
  bad "--dry-run did not report the pending actions"
fi
[ "$RC" -eq 3 ] && ok "--strict exited 3 over the drift warning" || bad "--strict exited $RC, expected 3"

echo "== T6: the run is idempotent — a second run changes nothing =="
P="$(mkproj t6)"
rm -f "$P/bin/restore-mpr.sh" "$P/bin/_common.sh"; chmod -x "$P/bin/snapshot-mpr.sh"
"$SYNC" "$P" >/dev/null 2>&1
B="$(fingerprint "$P")"
OUT2="$("$SYNC" "$P" 2>&1)"
A="$(fingerprint "$P")"
[ "$B" = "$A" ] && ok "second run wrote nothing" || bad "second run wrote again (not idempotent)"
if printf '%s' "$OUT2" | grep -qE '^[0-9]+ artifact\(s\) updated'; then
  bad "second run still claims artifacts were updated"
else
  ok "second run claims no changes"
fi

echo "== T7: a stale Q9 is OFFERED a repair, then repaired, and the gate goes green =="
P="$(mkproj t7)"
stale_q9 | set_q9 "$P/intake.md"
printf 'Toolkit commit: none\n' >> "$P/PROJECT.md"
# Positive control: the instrument must be red BEFORE the repair, or nothing below means anything.
# Capture first: gate-check exits 1 on any red stage and `set -o pipefail` would make
# `gate-check | grep -q` report failure even when the grep matched.
GOUT="$("$GATE" "$P" P 2>&1)"
if printf '%s' "$GOUT" | grep -q 'Stage P.*FAIL'; then
  ok "control: stale-Q9 project fails gate-check P"
else
  bad "control: stale-Q9 project does NOT fail gate-check P — instrument is blind"
fi
B="$(fingerprint "$P")"
OUT="$("$SYNC" "$P" 2>&1)"
A="$(fingerprint "$P")"
if printf '%s' "$OUT" | grep -q 'OFFER:' && printf '%s' "$OUT" | grep -q -- '--repair-intake'; then
  ok "plain run OFFERS the repair"
else
  bad "plain run said nothing about the stale Q9"
fi
[ "$B" = "$A" ] && ok "plain run did not touch intake.md" || bad "plain run rewrote intake.md unasked"
"$SYNC" "$P" --repair-intake >/dev/null 2>&1
GOUT="$("$GATE" "$P" P 2>&1)"
if printf '%s' "$GOUT" | grep -q 'Stage P.*PASS'; then
  ok "--repair-intake heals Q9; gate-check P now passes"
else
  bad "after --repair-intake the project still fails gate-check P"
fi

echo "== T8: an EDITED Q9 is left alone even with --repair-intake =="
# The stale text reads like an answer. Rewriting a section a human has touched is data loss.
P="$(mkproj t8)"
{ stale_q9; printf '\nWe run this attended, always. -- MV\n'; } | set_q9 "$P/intake.md"
MINE="$(cat "$P/intake.md")"
OUT="$("$SYNC" "$P" --repair-intake 2>&1)"
if [ "$MINE" = "$(cat "$P/intake.md")" ]; then
  ok "hand-edited Q9 survived --repair-intake"
else
  bad "hand-edited Q9 was REWRITTEN — data loss"
fi
if printf '%s' "$OUT" | grep -q 'has been edited'; then
  ok "the refusal is explained on screen"
else
  bad "refused silently (or never looked)"
fi

echo "== T9: the ui-review-loop guard fires on a project with no routing table =="
# G3. sync's own Wiring block contains the literal 'ui-review-loop.md', so a guard grepping for
# that string is permanently satisfied by sync's OWN output — silent forever on a project that
# has no Baseline routing at all. The guard must test a string sync does not itself write.
P="$WORK/t9"; mkdir -p "$P"
cat > "$P/CLAUDE.local.md" <<'EOF'
# CLAUDE.local.md

## Session-start ritual (mandatory, before any pipeline work)

1. pull the toolkit.

Route every question through `skills/query-the-model.md` before asking the user.
EOF
"$SYNC" "$P" >/dev/null 2>&1                 # run 1 appends the Wiring block
OUT="$("$SYNC" "$P" --strict 2>&1)"; RC=$?
if [ "$(grep -c 'Baseline routing' "$P/CLAUDE.local.md")" -eq 0 ]; then
  if printf '%s' "$OUT" | grep -q 'ui-preflight-pages'; then
    ok "guard still fires after sync injected 'ui-review-loop.md' itself"
  else
    bad "guard silenced by sync's own output (routing genuinely absent)"
  fi
  [ "$RC" -eq 3 ] && ok "--strict exited 3 on the silenced-guard project" || bad "exit $RC, expected 3"
else
  bad "fixture invalid: a routing table appeared"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
