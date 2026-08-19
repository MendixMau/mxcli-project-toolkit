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
# Q9 of $1 exactly as the scripts see it: heading, body, trailing blank lines trimmed. This
# mirrors sync-project.sh's q9_section() on purpose — "byte-identical to the template" has to
# be compared the same way the scripts compare it, or the test grades a different string.
q9_of() {
  awk '/^## 9\./{insec=1} insec && /^## /&&!/^## 9\./{insec=0} insec{print}' "$1" \
    | awk '{a[NR]=$0} END{last=NR; while(last>0 && a[last]~/^[ \t]*$/) last--; for(i=1;i<=last;i++) print a[i]}'
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

echo "== T7: a stale Q9 is OFFERED a repair, then repaired into the CURRENT, UNANSWERED template =="
# This test used to end "...and the gate goes green", and that assertion was itself the bug.
# Closed by 0f16140: the template --repair-intake writes is the same Q9 init-project.sh writes,
# and it used to open with "Unverified — how to verify: ...", which check_stage_P() ACCEPTS as
# an answer. So repairing a project — or merely generating one — certified a kickoff interview
# that had never happened. The template now says "_Not yet asked._", which carries no marker.
#
# The contract the repair actually owes is narrower, and that is what is pinned here: swap
# ungradeable boilerplate (prose that no answer marker can ever be found in) for the current,
# GRADEABLE-but-unanswered template. Stage P must stay RED afterwards and must NAME section 9.
# A repair that greens the gate is the false green coming back. The green is a human's to give,
# and the tail of this test proves the repaired text is answerable rather than permanently red.
P="$(mkproj t7)"
# The reference template is read off the fresh scaffold, never copied into this file: a second
# hand-maintained copy of that text is precisely what wave-2 #1 was.
TEMPLATE_Q9="$(q9_of "$P/intake.md")"
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
if [ "$(q9_of "$P/intake.md")" != "$TEMPLATE_Q9" ]; then
  bad "--repair-intake did not write the current Q9 template byte-for-byte"
elif ! printf '%s' "$GOUT" | grep -q 'Stage P.*FAIL'; then
  bad "Stage P went GREEN on a repaired-but-unanswered Q9 — the 0f16140 false green is back"
elif ! printf '%s' "$GOUT" | grep -q '9\. Interview mode'; then
  bad "Stage P fails but never names section 9 — the repaired text is not gradeable"
else
  # Red is only the right answer if it is a red a human can clear. Answer every question the
  # scaffold left open — the marker is what the gate grades, the prose after it is not — and
  # Stage P must go green. Without this tail, "repair leaves it failing" would also be
  # satisfied by a repair that wrote something permanently ungradeable.
  awk '/^_Not yet asked\._/{print "Answered (CONFIRMED): attended."; next} {print}' \
    "$P/intake.md" > "$P/intake.md.ans" && mv "$P/intake.md.ans" "$P/intake.md"
  GOUT="$("$GATE" "$P" P 2>&1)"
  if printf '%s' "$GOUT" | grep -q 'Stage P.*PASS'; then
    ok "--repair-intake writes the gradeable template; Stage P stays RED until answered, then passes"
  else
    bad "Stage P still fails once every question is answered — the repaired Q9 is unanswerable"
  fi
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

echo "== T10: an intake from the OLD question set is reported, then appended to =="
#
# The kickoff set was rewritten 2026-08-19. Projects scaffolded before it answered a different
# set of questions — notably never the entry mode — and nothing said so. What is pinned here is
# the CONTRACT, not just the detection: a sync run after a toolkit pull must not silently flip
# a mid-pipeline project's Stage P from PASS to FAIL.

P10="$(mkproj t10)"
# The pre-redesign question set, written inline rather than recovered from git history: a SHA
# in a test fixture rots the first time history is rewritten, and the fixture only needs to BE
# an old-shaped intake, not to be a specific commit's. The licence/security question is copied
# verbatim from the old template on purpose — it is now Q6, word for word, and it is what pins
# that matching is on question text rather than number.
cat > "$P10/intake.md" <<'OLDINTAKE'
# intake.md — Stage P Kickoff Interview

## 1. Which source folder(s) hold the legacy application?

Answered (CONFIRMED): yes.

## 2. Are there licence/security constraints on storing this client's source in this workspace?

Answered (CONFIRMED): yes.

## 3. Is an SME available, and who?

Answered (CONFIRMED): yes.

## 4. Are there documents outside the source folders (specs, manuals, screenshots) not yet accounted for?

Answered (CONFIRMED): yes.

## 5. Is this a fresh migration or a continuation/re-run of prior work?

Answered (CONFIRMED): yes.

## 6. Target Mendix version / mxbuild setup?

Answered (CONFIRMED): yes.

## 7. Deployment target / environment (DTAP)?

Answered (CONFIRMED): yes.

## 8. Single Mendix app, or does scale suggest a multiple-app split?

Answered (CONFIRMED): yes.

## 9. Interview mode: attended (default) or unattended?

Answered (CONFIRMED): attended.
OLDINTAKE

"$GATE" "$P10" P >/dev/null 2>&1 && ok "control: the old-template project PASSES Stage P" \
                                  || bad "control: the old-template project PASSES Stage P"

# Only intake.md is fingerprinted, not the tree: a plain sync legitimately refreshes agent
# stubs and routing. What must not happen is this file changing, because changing it is what
# would flip a mid-pipeline project's Stage P from PASS to FAIL on a routine post-pull sync.
BEFORE="$(md5 -q "$P10/intake.md" 2>/dev/null || md5sum "$P10/intake.md" | cut -d' ' -f1)"
O="$("$SYNC" "$P10" 2>&1)"
case "$O" in *"predates the current kickoff question set"*) ok "a plain run REPORTS the old set" ;;
              *) bad "a plain run REPORTS the old set" ;; esac
case "$O" in *"Entry mode: migration, requirements-driven, or greenfield?"*)
      ok "  and names the question that matters most" ;;
  *)  bad "  and names the question that matters most" ;; esac
case "$O" in *"licence/security constraints"*)
      bad "  a renumbered but identical question is NOT reported missing" ;;
  *)  ok "  a renumbered but identical question is NOT reported missing" ;; esac
case "$O" in *"--repair-intake"*) ok "  and prints the command to accept it" ;;
              *) bad "  and prints the command to accept it" ;; esac
AFTER="$(md5 -q "$P10/intake.md" 2>/dev/null || md5sum "$P10/intake.md" | cut -d' ' -f1)"
[ "$AFTER" = "$BEFORE" ] \
  && ok "  and left intake.md alone — a pull must not fail a mid-pipeline project's gate" \
  || bad "  and left intake.md alone — a pull must not fail a mid-pipeline project's gate"

"$SYNC" "$P10" --repair-intake >/dev/null 2>&1
[ "$(grep -c '^## 9\. Interview mode' "$P10/intake.md")" = "1" ] \
  && ok "the repair leaves exactly one Q9, still at number 9" \
  || bad "the repair leaves exactly one Q9, still at number 9"
grep -q '^## 10\. Entry mode' "$P10/intake.md" \
  && ok "  new questions continue from 10 rather than renumbering" \
  || bad "  new questions continue from 10 rather than renumbering"
[ "$(grep -c 'Answered (CONFIRMED)' "$P10/intake.md")" = "9" ] \
  && ok "  all nine existing answers survive" || bad "  all nine existing answers survive"
"$GATE" "$P10" P >/dev/null 2>&1 \
  && bad "  Stage P now FAILS on the questions nobody asked" \
  || ok "  Stage P now FAILS on the questions nobody asked"
O="$("$SYNC" "$P10" 2>&1)"
case "$O" in *"predates the current kickoff question set"*)
      bad "  a second sync finds nothing left to append" ;;
  *)  ok "  a second sync finds nothing left to append" ;; esac

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
