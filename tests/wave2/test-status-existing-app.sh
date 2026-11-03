#!/usr/bin/env bash
# test-status-existing-app.sh — bin/status.sh in existing-app-change mode (#301) and the manual
# Studio Pro step count (#298).
#
# Usage: bash tests/wave2/test-status-existing-app.sh bin/status.sh
#
# GOLDEN INPUT IS THE REAL SCAFFOLD. Every PROJECT.md here is written by the real
# bin/init-project.sh (agent stubs with their unfilled slots included); the fixture adds only an
# "Entry mode:" line, a BUILD-LOG and the sections under test. The baseline is status.sh as it was
# at BASE_REF (the commit before this change), run from the SAME toolkit copy as the subject, so the
# two outputs differ only by the script.
#
#   T1  pipeline project (migration), --brief and full: byte-identical to the baseline, with the
#       agent-slot and done- stall WATCH items present in both (control: the noise is real there)
#   T2  pipeline project carrying a "## Rounds" section: still byte-identical (the section is
#       read in existing-app-change mode only)
#   T3  existing-app-change, rounds recorded: ROUND line is the LAST row, with stories and the
#       delivered count; full screen carries it too
#   T4  existing-app-change: no "agent slots unfilled" in WATCH, but "done- stalled" stays (the
#       build loop runs unchanged at Stages 5-6); the baseline DID print the slot item
#   T5  existing-app-change, no Rounds section: the ROUND line says none recorded and where to add it
#   T6  Rounds table without a Stories column: no stories part, no crash
#   T6b a "## Rounds of review" section is not the Rounds table
#   T7  docs/manual-steps.md: unticked Done lines counted, ticked ones in the total, the fenced
#       example ignored — on --brief STATE and on the full screen
#   T8  the shipped template copied as-is counts 0 of 0 (its example is fenced)
#   T9  NEXT drops final-look ONLY, and only under gate-check's derived stage readout below its
#       from-stage: (a) derived Stage P keeps every other pending pass; (b) a module opened under
#       that lagging line keeps look/sweep/journeys; (c) a hand-written line filters nothing;
#       (d) the FIRST "Stage N" on the line is the stage, not a later one

export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1
export MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail

SUT="${1:?usage: test-status-existing-app.sh /path/to/bin/status.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"
BASE_REF="${BASE_REF:-b9cf37c44884a74a357b7b14bc595ea78304a0b2}"
W="$(mktemp -d "${TMPDIR:-/tmp}/statusea.XXXXXX")" || exit 2
trap 'rm -rf "$W"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# One toolkit copy, not a git checkout, so the toolkit sha reads "?" for both scripts alike.
mkdir -p "$W/tk"
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$W/tk" && tar -xf -)
cp "$SUT" "$W/tk/bin/status.sh"
HAVE_BASE=0
if git -C "$SRC" show "$BASE_REF:bin/status.sh" > "$W/tk/bin/status-baseline.sh" 2>/dev/null; then
  chmod +x "$W/tk/bin/status-baseline.sh"; HAVE_BASE=1
fi
NEW="$W/tk/bin/status.sh"; OLD="$W/tk/bin/status-baseline.sh"
# Run from the project root, as a session does: from anywhere else status.sh adds a CWD line
# (#447), which is not what these cases compare.
in_proj() { local sut="$1" p="$2"; shift 2; ( cd "$p" && "$sut" "$p" "$@" ); }

mkproj() {  # mkproj <name> <entry mode text>
  local d="$W/$1"; mkdir -p "$d/mdlsource" "$d/docs"; : > "$d/Fixture.mpr"
  "$W/tk/bin/init-project.sh" "$d" >/dev/null 2>&1
  # Entry mode the way a register records it, right under the Current stage heading.
  awk -v m="$2" '{print} /^## Current stage/ {getline; print; print ""; print "Entry mode: " m " CONFIRMED"}' \
    "$d/PROJECT.md" > "$d/PROJECT.md.new" && mv "$d/PROJECT.md.new" "$d/PROJECT.md"
  # Three gate-passed scripts, none renamed done- — the "done- stalled" condition.
  local s
  # Header and row shape as project-bin/exec.sh log_build() writes them (gate column = GATE_STATE).
  { echo "| when (ISO-8601 local) | script | gate | result | detail |"; echo "|---|---|---|---|---|"; } > "$d/docs/BUILD-LOG.md"
  for s in 010-a 020-b 030-c; do
    echo "-- $s" > "$d/mdlsource/$s.mdl"
    echo "| 2026-10-13T10:00:00+0200 | \`$s.mdl\` | pass | ✅ applied | $s.mdl; lint ok |" >> "$d/docs/BUILD-LOG.md"
  done
  echo "$d"
}
# The doctor receipt's age ("0 min ago") can tick over between the two runs; it is the only
# wall-clock text on the screen, so it is masked for the byte comparison and nothing else is.
norm() { sed -E 's/[0-9]+ (min|h|days) ago/N \1 ago/g'; }
add_rounds() {  # add_rounds <proj>  (table on stdin) — appended as its own section
  { printf '\n## Rounds\n\n'; cat; } >> "$1/PROJECT.md"
}

echo "== bin/status.sh — existing-app-change rounds (#301) + manual steps (#298) =="

# --- T1 / T2: pipeline modes are untouched -------------------------------------------------------
P="$(mkproj pipe "migration")"
if [ "$HAVE_BASE" = 1 ]; then
  for mode in --brief ""; do
    o="$(in_proj "$OLD" "$P" $mode 2>&1 | norm)"; n="$(in_proj "$NEW" "$P" $mode 2>&1 | norm)"
    [ "$o" = "$n" ] && ok "T1 pipeline project ${mode:-full}: byte-identical to baseline" \
                    || bad "T1 pipeline project ${mode:-full} output changed" "$(diff <(echo "$o") <(echo "$n"))"
  done
  case "$o" in *"agent slots unfilled"*"done- stalled"*|*"done- stalled"*"agent slots unfilled"*) ok "T1 control: the pipeline screen carries agent-slot + done- stall WATCH items";;
    *) bad "T1 control: expected both WATCH items on the pipeline project (fixture no longer exercises them)" "$o";; esac
  printf '| Round | Title | Stories | State |\n|---|---|---|---|\n| 1 | Export fixes | S-1 | in test |\n' | add_rounds "$P"
  for mode in --brief ""; do
    o="$(in_proj "$OLD" "$P" $mode 2>&1 | norm)"; n="$(in_proj "$NEW" "$P" $mode 2>&1 | norm)"
    [ "$o" = "$n" ] && ok "T2 pipeline project with a Rounds section ${mode:-full}: byte-identical" \
                    || bad "T2 Rounds section changed a pipeline screen (${mode:-full})" "$(diff <(echo "$o") <(echo "$n"))"
  done
else
  bad "T1/T2 NOT RUN: baseline $BASE_REF not in this checkout's history (fetch full history)"
fi

# --- T3 / T4: existing-app-change with rounds ------------------------------------------------
E="$(mkproj eac "Change an existing app")"
printf '%s\n' '| Round | Title | Stories | State |' '|---|---|---|---|' \
  '| 1 | Export fixes | S-101, S-102 | delivered |' \
  '| 2 | Approval rework | S-110, S-111 | in test |' | add_rounds "$E"
b="$(in_proj "$NEW" "$E" --brief 2>&1)"
exp='ROUND   Round 2: Approval rework — in test · stories: S-110, S-111 · 1 of 2 round(s) delivered'
printf '%s\n' "$b" | grep -qxF "$exp" && ok "T3 --brief ROUND line is the last row, with stories and delivered count" \
  || bad "T3 --brief ROUND line" "$b"
[ "$(printf '%s\n' "$b" | sed -n 2p | cut -c1-5)" = "ROUND" ] && ok "T3 ROUND sits right under WHERE" || bad "T3 ROUND line position" "$b"
f="$(in_proj "$NEW" "$E" 2>&1)"
printf '%s\n' "$f" | grep -qF 'ROUND     Round 2: Approval rework — in test' && ok "T3 full screen carries the ROUND line" || bad "T3 full screen ROUND line" "$f"
case "$b$f" in *"agent slots unfilled"*) bad "T4 agent-slot noise still printed in existing-app mode" "$b";; *) ok "T4 no agent-slot WATCH item";; esac
case "$b" in *"done- stalled"*) ok "T4 done- stall still reported (Stages 5-6 run the build loop unchanged in this mode)";; *) bad "T4 done- stall dropped in existing-app mode — it must stay" "$b";; esac
if [ "$HAVE_BASE" = 1 ]; then
  o="$(in_proj "$OLD" "$E" --brief 2>&1)"
  case "$o" in *"agent slots unfilled"*) ok "T4 control: the baseline printed the agent-slot noise on this same project";;
    *) bad "T4 control: baseline did not print agent-slot noise — case cannot fail" "$o";; esac
  case "$o" in *ROUND*) bad "T4 control: baseline already has a ROUND line?" "$o";; *) ok "T4 control: the baseline has no ROUND line";; esac
fi

# --- T5: no Rounds section -------------------------------------------------------------------
E2="$(mkproj eac-none "existing-app-change")"
b="$(in_proj "$NEW" "$E2" --brief 2>&1)"
printf '%s\n' "$b" | grep -q '^ROUND   none recorded — add a row to PROJECT.md "## Rounds"' && ok "T5 no rounds: says none recorded and where" || bad "T5 no-rounds line" "$b"

# --- T6: no Stories column ------------------------------------------------------------------
E3="$(mkproj eac-nostories "Change an existing app")"
printf '%s\n' '| Round | Title | State |' '|---|---|---|' '| 1 | Login tweak | building |' | add_rounds "$E3"
b="$(in_proj "$NEW" "$E3" --brief 2>&1)"
printf '%s\n' "$b" | grep -qxF 'ROUND   Round 1: Login tweak — building · 0 of 1 round(s) delivered' && ok "T6 no Stories column: no stories part" || bad "T6 no-Stories-column ROUND line" "$b"

# --- T6b: a "## Rounds of review" heading is a different section ------------------------------
printf '\n## Rounds of review\n\n| Round | Title | State |\n|---|---|---|\n| 9 | Peer review | done |\n' >> "$E3/PROJECT.md"
b="$(in_proj "$NEW" "$E3" --brief 2>&1)"
printf '%s\n' "$b" | grep -qxF 'ROUND   Round 1: Login tweak — building · 0 of 1 round(s) delivered' && ok "T6b \"## Rounds of review\" is not read as the Rounds table" || bad "T6b a look-alike heading was read" "$b"

# --- T7: manual steps count ----------------------------------------------------------------
cat > "$E/docs/manual-steps.md" <<'EOF'
# Manual Studio Pro steps

```markdown
- [ ] Done — example, fenced, must not count
```

### MS-01 — a
- [x] Done — by hand (commit abc1234)
### MS-02 — b
- [ ] Done — pending
### MS-03 — c
- [ ] **Done** — pending
Not a step: - [ ] Done mid-line
EOF
b="$(in_proj "$NEW" "$E" --brief 2>&1)"
printf '%s\n' "$b" | grep '^STATE' | grep -qF '· manual steps pending 2 of 3' && ok "T7 --brief STATE: manual steps pending 2 of 3" || bad "T7 --brief manual count" "$b"
f="$(in_proj "$NEW" "$E" 2>&1)"
printf '%s\n' "$f" | grep -qF 'manual steps pending 2 of 3 (docs/manual-steps.md)' && ok "T7 full screen: manual count with its file" || bad "T7 full manual count" "$f"

# --- T8: the shipped template counts nothing ------------------------------------------------
cp "$W/tk/templates/manual-steps.md" "$E2/docs/manual-steps.md" 2>/dev/null
b="$(in_proj "$NEW" "$E2" --brief 2>&1)"
printf '%s\n' "$b" | grep -qF 'manual steps pending 0 of 0' && ok "T8 template copied as-is: 0 of 0" || bad "T8 template count" "$b"

# --- T9: final-look leaves NEXT only on a derived readout below Stage 6 (reviews of #303, #326) --
# A scaffold always has gate-check "Needs attention" items, which win NEXT before the obligation
# rule is reached. tk2's gate-check.sh runs the REAL gate-check and drops only that block and its
# count, so the obligation lines status.sh reads are real output, not typed here. The stage line
# is the one the real gate-check derives and writes (a fresh scaffold derives "Stage P").
mkdir -p "$W/tk2"; (cd "$W/tk" && tar -cf - .) | (cd "$W/tk2" && tar -xf -)
mv "$W/tk2/bin/gate-check.sh" "$W/tk2/bin/gate-check-real.sh"
cat > "$W/tk2/bin/gate-check.sh" <<'WRAP'
#!/usr/bin/env bash
"$(dirname "$0")/gate-check-real.sh" "$@" 2>/dev/null \
  | awk '/^Needs attention/{s=1;next} /^Next up:|^Approved over a failing gate:/{s=0} !s' \
  | sed -E 's/[0-9]+ need attention/0 need attention/'
WRAP
chmod +x "$W/tk2/bin/gate-check.sh"
[ "$HAVE_BASE" = 1 ] && cp "$OLD" "$W/tk2/bin/status-baseline.sh"
nextof() { "$1" "$2" --brief 2>/dev/null | sed -n 's/^NEXT    //p'; }
stage_of() { awk '/^## Current stage/{f=1;next} f && /^\*\*Stage/{print;exit}' "$1/PROJECT.md"; }
setline() { MXTK_L="$2" awk '/^## Current stage/{f=1} f && /^\*\*Stage/ && !d {print ENVIRON["MXTK_L"]; d=1; next} {print}' "$1/PROJECT.md" > "$1/p.new" && mv "$1/p.new" "$1/PROJECT.md"; }
P9="$W/ob"; mkdir -p "$P9"; : > "$P9/Fixture.mpr"; "$W/tk2/bin/init-project.sh" "$P9" >/dev/null 2>&1
printf '\nEntry mode: migration\n' >> "$P9/PROJECT.md"
"$W/tk2/bin/gate-check-real.sh" "$P9" >/dev/null 2>&1   # writes the derived readout
DERIVED="$(stage_of "$P9")"
case "$DERIVED" in *"(derived by gate-check"*) ok "T9 setup: real gate-check wrote a derived readout";; *) bad "T9 setup: no derived readout" "$DERIVED";; esac

# T9a derived Stage P, no module opened: final-look out of NEXT, the other pending passes stay.
n="$(nextof "$W/tk2/bin/status.sh" "$P9")"
case "$n" in "discharge:"*) ok "T9a derived Stage P: NEXT still discharges what is pending";; *) bad "T9a expected a discharge NEXT" "$n";; esac
case "$n" in *final-look*) bad "T9a derived Stage P: NEXT still names final-look" "$n";; *) ok "T9a derived Stage P: final-look not in NEXT";; esac
case "$n" in *skeleton*) ok "T9a only final-look is filtered (skeleton, also above Stage P, stays)";; *) bad "T9a filter dropped more than final-look" "$n";; esac
f="$("$W/tk2/bin/status.sh" "$P9" 2>/dev/null)"
# Once obligation-check.sh itself reports final-look NOT YET DUE under an early derived readout
# (#321), final-look is no longer pending at all: then it must be ABSENT from the pending line, and
# the baseline control cannot apply (the old status.sh would not name it either). Before #321, the
# pending line keeps listing it and the baseline control shows the old NEXT sent the project there.
# Captured first: under pipefail, `gate-check | grep -q` reads as false when grep exits early.
GC9="$("$W/tk2/bin/gate-check-real.sh" --no-html "$P9" 2>/dev/null)"
if printf '%s\n' "$GC9" | grep -E '^Obligation final-look +NOT YET DUE' >/dev/null; then
  printf '%s\n' "$f" | grep -q 'obligations pending:.*final-look' \
    && bad "T9a final-look is NOT YET DUE in gate-check but still listed as pending" "$(printf '%s\n' "$f" | grep 'obligations pending')" \
    || ok "T9a gate-check says final-look NOT YET DUE: absent from the obligations pending line"
  ok "T9a control: not applicable — gate-check already reports final-look NOT YET DUE (#321)"
else
  printf '%s\n' "$f" | grep -q 'obligations pending:.*final-look' && ok "T9a the screen still lists final-look under obligations pending" || bad "T9a obligations pending line lost final-look"
  if [ "$HAVE_BASE" = 1 ]; then
    o="$(nextof "$W/tk2/bin/status-baseline.sh" "$P9")"
    case "$o" in *final-look*) ok "T9a control: the baseline sent a Stage P project to final-look";; *) bad "T9a control: baseline did not name final-look — case cannot fail" "$o";; esac
  fi
fi

# T9b a module opened under the same lagging derived line: the module passes stay in NEXT.
mkdir -p "$P9/.claude/loop/verify/Orders"
n="$(nextof "$W/tk2/bin/status.sh" "$P9")"
case "$n" in *look*sweep*journeys*|*look*journeys*sweep*) ok "T9b module opened under a lagging line: look/sweep/journeys still in NEXT";; *) bad "T9b owed module passes hidden from NEXT" "$n";; esac
rm -rf "$P9/.claude/loop/verify"

# T9c a hand-written (non-derived) Stage 1 line: no filtering at all.
setline "$P9" "**Stage 1 — Analysis**, in progress."
n="$(nextof "$W/tk2/bin/status.sh" "$P9")"
case "$n" in *final-look*) ok "T9c hand-written stage line: final-look stays in NEXT";; *) bad "T9c a hand-written line must not filter" "$n";; esac

# T9d the FIRST "Stage N" on the line decides: the real derived line with its stage set to 6 and a
# later "Stage 2" in its text keeps final-look (owed from 6) in NEXT; reading the last one would
# drop it. From Stage 5 the skeleton and agent-stub rules win NEXT first, so this case records a
# proven skeleton and fills the stub slots — both are what a real Stage 6 project has.
printf '\nSkeleton proven 2026-10-13\n' >> "$P9/PROJECT.md"
for _f in "$P9"/.claude/agents/*.md "$P9/CLAUDE.local.md"; do
  [ -f "$_f" ] && sed -E 's/\{\{[^}]*\}\}/filled/g' "$_f" > "$_f.new" && mv "$_f.new" "$_f"
done
setline "$P9" "$(printf '%s' "$DERIVED" | sed -E 's/Stage P — Kickoff/Stage 6 — Verify/; s/gates passed: [^(]*/gates passed: P-5, Stage 2 re-opened /')"
case "$(stage_of "$P9")" in *"Stage 6"*"Stage 2"*"(derived by gate-check"*) : ;; *) bad "T9d setup" "$(stage_of "$P9")";; esac
n="$(nextof "$W/tk2/bin/status.sh" "$P9")"
case "$n" in "discharge:"*final-look*) ok "T9d first Stage N wins: Stage 6 keeps final-look despite a later Stage 2";;
  *) bad "T9d expected final-look in a discharge NEXT (first Stage N is 6)" "$n";; esac

echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
