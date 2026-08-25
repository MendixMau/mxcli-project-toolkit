#!/usr/bin/env bash
# Fixture for wave-2 #6: protocol staleness NOTIFIES, it does not block.
#
# The bug: a project with a signed-off Stage 0 was BLOCKED at every gate because someone ELSE
# pushed a two-word typo fix to a Stage 3 skill — while the board printed "Stage 0: PASS"
# directly above the block. Nothing in the blocked project had changed.
#
# The resolution is not a better-calibrated block; it is no block. A stale ack never changes an
# exit code and never suppresses a stage verdict. What it does is print a notice that leads with
# the CHOICE (lettered options A/B). Relevance still exists, but it now decides VOLUME — full
# notice vs one quiet line — not gating.
#
# THAT MOVES THE FAILURE MODE. The old risk was a false block; the only risk left is SILENCE, so
# the positive controls (T3, T4, T5, T8, T12, T13, T15) no longer assert exit codes. Each asserts
# that a visible notice appears, names the right files, and offers a route out. A case that goes
# quiet is now the bug. Exit codes are asserted in the opposite direction: they must be the
# stage's OWN verdict, unperturbed by any freshness state (T16).
#
#   tests/wave2/test-bug06-freshness.sh /path/to/gate-check.sh
#
# Unlike the other wave-2 fixtures this one COPIES the script under test into a synthetic
# toolkit clone under /tmp. That is deliberate and inverted from test-bug03's note: gate-check.sh
# derives TOOLKIT_DIR from BASH_SOURCE, and a synthetic toolkit — bare origin plus a working
# clone, so `git fetch` runs for real — is the only way to author the protocol history each case
# needs. Real toolkit history cannot be made to contain a two-word typo fix on demand.
set -uo pipefail

GATE="${1:?usage: test-bug06-freshness.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d /tmp/bug06.XXXXXX)"

# Portability: python is used here only to allocate a pty. The test already skips without
# one; resolve_py just makes the probe honest on a machine where Python 3 is not called
# `python3`, where the old check skipped a test that could in fact have run.
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

SKILLS="conversion-runbook.md query-the-model.md source-triage.md design-artifacts.md
        learned-mdl-preflight.md iterative-build-loop.md close-the-loop.md e2e-harness-base.md"

# Build a fresh synthetic toolkit (bare origin + clone) and a project acked to its tip.
# Every case gets its own, so no case can inherit another's history.
setup() {
  CASE="$WORK/$1"; ORIGIN="$CASE/origin.git"; TK="$CASE/tk"; PROJ="$CASE/proj"
  mkdir -p "$CASE"
  git init -q --bare "$ORIGIN"
  git init -q "$TK"; mkdir -p "$TK/bin" "$TK/skills" "$TK/agents"
  cp "$GATE" "$TK/bin/gate-check.sh"; chmod +x "$TK/bin/gate-check.sh"
  for s in $SKILLS; do printf '# %s\n\noriginal body.\n' "$s" > "$TK/skills/$s"; done
  printf '# test-agent\n' > "$TK/agents/test-agent.md"
  git -C "$TK" add -A >/dev/null; git -C "$TK" commit -qm init
  git -C "$TK" remote add origin "$ORIGIN"
  git -C "$TK" push -q -u origin HEAD:refs/heads/main 2>/dev/null
  git -C "$TK" branch -q --set-upstream-to=origin/main 2>/dev/null
  ACKED="$(git -C "$TK" rev-parse --short HEAD)"

  mkdir -p "$PROJ"
  printf '# PROJECT.md\n\nToolkit commit: %s\n\n## Decisions\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' \
    "$ACKED" > "$PROJ/PROJECT.md"
  printf '# Triage\n\n## Sign-off\n\nConfirmed by: A Tester on 2026-08-12\n' > "$PROJ/triage.md"
  GC="$TK/bin/gate-check.sh"
}

# Someone ELSE pushes a change to the shared toolkit. The project is not touched.
push_change() {  # push_change <relative-path> <mode: edit|add|rename-to>
  case "$2" in
    edit)   printf 'a two-word typo fix.\n' >> "$TK/$1" ;;
    add)    printf '# brand new\n' > "$TK/$1" ;;
    *)      git -C "$TK" mv "$1" "$2" ;;
  esac
  git -C "$TK" add -A >/dev/null; git -C "$TK" commit -qm "someone else's push" >/dev/null
  git -C "$TK" push -q origin HEAD:refs/heads/main
}

# --verbose on the helpers (2026-08-26). The default rendering became plain-language by decision:
# gate-check now leads with "Toolkit updates: ..." and words, and puts commit ids, file paths and
# diffstat behind --verbose, because the people running this in enablement sessions are not the
# people who diff skill files. Every technical assertion below is about that verbose surface and
# still holds verbatim against it. The plain default gets its own control at the end of the file.
run()  { "$GC" --no-html --verbose "$PROJ" ${1:+$1} 2>&1; }
# `run X | grep -q ...` is a TRAP under `set -o pipefail`: grep -q exits on the first match and
# SIGPIPEs gate-check, whose 141 then becomes the pipeline's status — so a matching pattern
# reports NO MATCH. It cost three false "CONTROL BROKEN" results while writing this file. Every
# content assertion below therefore goes through this helper, which uses a herestring, not a pipe.
saw()  { grep -q "$2" <<<"$1"; }
rc()   { "$GC" --no-html --verbose "$PROJ" ${1:+$1} >/dev/null 2>&1; echo "$?"; }
sync_status() { run "${1:-}" | grep '^Sync' | sed 's/^Sync (Protocol freshness): \([A-Z]*\).*/\1/'; }
# A notice is only useful if a human sees the choice. Every control checks all three parts.
notice_ok() { # notice_ok <output> <label> <file-that-must-be-named>
  local o="$1" label="$2" f="$3"
  saw "$o" ' A)' || { bad "$label: no lettered option A"; return 1; }
  saw "$o" ' B)' || { bad "$label: no lettered option B"; return 1; }
  saw "$o" 'ack-protocol' || { bad "$label: no route out named"; return 1; }
  if [ -n "$f" ] && ! saw "$o" "$f"; then bad "$label: notice does not name $f"; return 1; fi
  ok "$label"
}

echo "== T1: baseline — an in-sync ack is silent =="
setup t1
[ "$(sync_status 0)" = "PASS" ] && ok "Sync PASS when the ack is current" || bad "Sync not PASS: $(sync_status 0)"
[ "$(rc 0)" = "0" ] && ok "Stage 0 gate passes" || bad "Stage 0 exit $(rc 0)"
saw "$(run 0)" ' A)' && bad "printed a notice with nothing to notify about" || ok "no notice when current"

echo "== T2: THE REPORTED BUG — a Stage-3 skill moves, a Stage-0 gate is requested =="
setup t2; push_change skills/design-artifacts.md edit
S="$(sync_status 0)"; R="$(rc 0)"; O="$(run 0)"
if [ "$S" = "WARN" ] && [ "$R" = "0" ]; then
  ok "not blocked — the colleague's project proceeds (WARN, exit 0)"
else
  bad "expected WARN/exit 0, got $S/exit $R"
fi
# Quiet, but NOT silent: relevance controls volume, and a change the reader never hears about
# is how a stale ack becomes permanent.
saw "$O" 'design-artifacts.md' && ok "the quiet line still names the changed file" \
                               || bad "went completely silent about a real change"
saw "$O" 'ack-protocol' && ok "the quiet line still offers the ack" || bad "no route out offered"
saw "$O" ' A)' && bad "escalated an irrelevant change to the full notice (wallpaper risk)" \
               || ok "no full banner for an irrelevant change"

echo "== T3: POSITIVE CONTROL — a Stage-0 skill moves, Stage 0 requested =="
setup t3; push_change skills/source-triage.md edit
S="$(sync_status 0)"; O="$(run 0)"
[ "$S" = "NOTICE" ] && ok "stage-relevant change raises a NOTICE" || bad "CONTROL: expected NOTICE, got $S"
notice_ok "$O" "notice names the file and both options" "source-triage.md"
[ "$(rc 0)" = "0" ] && ok "and does NOT block — Stage 0's own verdict stands" || bad "still blocked (exit $(rc 0))"

echo "== T4: POSITIVE CONTROL — conversion-runbook.md moves (governs EVERY stage) =="
setup t4; push_change skills/conversion-runbook.md edit
for st in 0 3 7; do
  S="$(sync_status $st)"
  [ "$S" = "NOTICE" ] && notice_ok "$(run $st)" "runbook change notifies at stage $st" "conversion-runbook.md" \
                      || bad "CONTROL: runbook change went quiet at stage $st ($S)"
done

echo "== T4b: POSITIVE CONTROL — agents/ is ALWAYS relevant, at every stage =="
# An agent definition governs HOW work is done, not what one stage produces, so there is no
# stage at which a stale read of it is safe.
setup t4b; push_change agents/test-agent.md edit
for st in 0 3 5; do
  S="$(sync_status $st)"
  [ "$S" = "NOTICE" ] && notice_ok "$(run $st)" "agents/ change notifies at stage $st" "test-agent.md" \
                      || bad "CONTROL: agents/ change went quiet at stage $st ($S)"
done

echo "== T5: POSITIVE CONTROL — a build skill moves, Stage 5 requested =="
setup t5; push_change skills/learned-mdl-preflight.md edit
S="$(sync_status 5)"; O="$(run 5)"
[ "$S" = "NOTICE" ] && ok "Stage 5 notifies on a STOP-rule change" || bad "CONTROL: expected NOTICE, got $S"
notice_ok "$O" "the notice names the STOP-rule file" "learned-mdl-preflight.md"
saw "$O" 'insertion' && ok "the notice reports HOW MUCH changed" || bad "no line count in the notice"

echo "== T6: the same change, Stage 0 requested — relevance sets VOLUME =="
setup t6; push_change skills/learned-mdl-preflight.md edit
S="$(sync_status 0)"; O="$(run 0)"
[ "$S" = "WARN" ] && ok "a build-stage change is quiet at a triage gate" || bad "expected WARN, got $S"
saw "$O" 'learned-mdl-preflight.md' && ok "still named, just not shouted" || bad "silently dropped"

echo "== T7: a brand-new skill FILE is added — cannot invalidate a read that already happened =="
setup t7; push_change skills/some-new-skill.md add
[ "$(sync_status 0)" = "WARN" ] && ok "added file is a quiet line, not a notice" || bad "got $(sync_status 0)"

echo "== T8: POSITIVE CONTROL — an UNMAPPED protocol file fails SAFE (full notice) =="
# The map has no upstream source and will rot. A file matching nothing in it must be treated as
# relevant, so a stale map degrades toward MORE noise, never toward silence.
setup t8
printf '# unmapped\n' > "$TK/skills/totally-unmapped-skill.md"
git -C "$TK" add -A >/dev/null; git -C "$TK" commit -qm add >/dev/null
git -C "$TK" push -q origin HEAD:refs/heads/main
# Re-ack to the commit that ADDED it, so the later edit shows up as M and not as A.
ACKED="$(git -C "$TK" rev-parse --short HEAD)"
sed "s/^Toolkit commit: .*/Toolkit commit: $ACKED/" "$PROJ/PROJECT.md" > "$PROJ/p.tmp" && mv "$PROJ/p.tmp" "$PROJ/PROJECT.md"
push_change skills/totally-unmapped-skill.md edit   # now MODIFIED, not merely added
S="$(sync_status 0)"; O="$(run 0)"
if [ "$S" = "NOTICE" ]; then
  ok "unmapped file raises the full notice (fail-safe)"
  saw "$O" 'nmapped' && ok "and says the map is why, naming the row to add" \
                     || bad "notified, but never says the map is the reason"
else
  bad "FAIL-SAFE BROKEN: an unmapped protocol file produced $S"
fi

echo "== T15: POSITIVE CONTROL — a RENAMED skill still notifies =="
setup t15; push_change skills/source-triage.md skills/source-triage-v2.md
[ "$(sync_status 0)" = "NOTICE" ] && notice_ok "$(run 0)" "a rename of a stage-relevant skill notifies" "source-triage" \
                                  || bad "CONTROL: rename went quiet ($(sync_status 0))"

echo "== T12: POSITIVE CONTROL — no PROJECT.md at all =="
setup t12; rm -f "$PROJ/PROJECT.md"
S="$(sync_status 0)"; O="$(run 0)"
[ "$S" = "NOTICE" ] && ok "missing register raises a NOTICE" || bad "CONTROL: missing register produced $S"
saw "$O" 'init-project.sh' && ok "and points at the scaffold that fixes it" || bad "no route out for a missing register"
[ "$(rc 0)" = "1" ] && ok "Stage 0 still FAILs on its OWN merits (no triage.md sign-off is unreadable)" \
                    || ok "Stage 0 verdict returned $(rc 0) on its own merits"

echo "== T13: POSITIVE CONTROL — the acked SHA is absent from the clone =="
setup t13
sed 's/^Toolkit commit: .*/Toolkit commit: dead1234/' "$PROJ/PROJECT.md" > "$PROJ/p.tmp" && mv "$PROJ/p.tmp" "$PROJ/PROJECT.md"
S="$(sync_status 0)"; O="$(run 0)"
[ "$S" = "NOTICE" ] && ok "an unknown acked sha raises a NOTICE" || bad "CONTROL: unknown sha produced $S"
saw "$O" 'never seen' && ok "and says the clone has never seen it" || bad "does not explain the unknown sha"
notice_ok "$O" "unknown-sha notice offers both options" ""

echo "== T16: freshness NEVER perturbs the exit code — the stage verdict is its own =="
# The load-bearing regression guard for the whole redesign. Same project, same stage, once
# current and once maximally stale: the exit code must be identical.
setup t16
BEFORE_PASS="$(rc 0)"; BEFORE_MANUAL="$(rc 5)"; BEFORE_FAIL="$(rc 7)"
push_change skills/conversion-runbook.md edit          # relevant to every stage
[ "$(rc 0)" = "$BEFORE_PASS" ]   && ok "a PASSing stage still exits $BEFORE_PASS when stale"   || bad "PASS stage changed: $BEFORE_PASS -> $(rc 0)"
[ "$(rc 5)" = "$BEFORE_MANUAL" ] && ok "a MANUAL stage still exits $BEFORE_MANUAL when stale"  || bad "MANUAL stage changed: $BEFORE_MANUAL -> $(rc 5)"
[ "$(rc 7)" = "$BEFORE_FAIL" ]   && ok "a FAILing stage still exits $BEFORE_FAIL when stale"   || bad "FAIL stage changed: $BEFORE_FAIL -> $(rc 7)"
saw "$(run 0)" 'Stage 0 (Triage)' && ok "the stage verdict is still reported, not suppressed" \
                                  || bad "stale ack suppressed the stage verdict"

echo "== T17: --strict-protocol is the opt-in that restores blocking =="
setup t17; push_change skills/source-triage.md edit
[ "$(rc 0)" = "0" ] && ok "default: not blocked" || bad "default blocked (exit $(rc 0))"
"$GC" --no-html --strict-protocol "$PROJ" 0 >/dev/null 2>&1
[ "$?" = "1" ] && ok "--strict-protocol blocks" || bad "--strict-protocol did not block"
MXTK_STRICT_PROTOCOL=1 "$GC" --no-html "$PROJ" 0 >/dev/null 2>&1
[ "$?" = "1" ] && ok "MXTK_STRICT_PROTOCOL=1 is equivalent" || bad "env form did not block"
OUT="$("$GC" --no-html --strict-protocol "$PROJ" 0 2>&1)"
saw "$OUT" 'force-stale' && ok "the strict block names the bypass" || bad "strict block offers no bypass"
# strict mode must not resurrect blocking for the IRRELEVANT case
setup t17b; push_change skills/design-artifacts.md edit
"$GC" --no-html --strict-protocol "$PROJ" 0 >/dev/null 2>&1
[ "$?" = "0" ] && ok "strict still does not block on an irrelevant change" || bad "strict blocked on WARN"

echo "== T9: --force-stale clears a STRICT block, and leaves a record =="
setup t9; push_change skills/source-triage.md edit
"$GC" --no-html --strict-protocol --force-stale "$PROJ" 0 >/dev/null 2>&1; R=$?
[ "$R" = "0" ] && ok "--force-stale reaches the Stage 0 verdict under strict" || bad "--force-stale still blocked (exit $R)"
if grep -q 'PROTOCOL-BYPASS' "$PROJ/docs/BUILD-LOG.md" 2>/dev/null; then
  ok "PROTOCOL-BYPASS written to docs/BUILD-LOG.md"
  grep -q 'gate=0' "$PROJ/docs/BUILD-LOG.md" && ok "the bypass records WHICH gate" || bad "bypass does not record the gate"
else
  bad "bypass left no record — an invisible bypass is the failure mode this exists to prevent"
fi
setup t9b; push_change skills/source-triage.md edit
MXTK_STRICT_PROTOCOL=1 MXTK_ACK_STALE=1 "$GC" --no-html "$PROJ" 0 >/dev/null 2>&1
[ "$?" = "0" ] && ok "MXTK_ACK_STALE=1 is equivalent" || bad "MXTK_ACK_STALE=1 did not bypass"
# With nothing blocking, --force-stale must be a harmless no-op rather than a spurious log line.
setup t9c; push_change skills/source-triage.md edit
"$GC" --no-html --force-stale "$PROJ" 0 >/dev/null 2>&1
[ -f "$PROJ/docs/BUILD-LOG.md" ] && bad "logged a BYPASS when nothing was blocked" \
                                 || ok "no-op (and no log) when nothing is blocked"

echo "== T10: --ack-protocol REFUSES without a TTY, and names the logged alternative =="
setup t10; push_change skills/source-triage.md edit
OUT="$("$GC" --no-html --ack-protocol "$PROJ" </dev/null 2>&1)"; R=$?
if [ "$R" != "0" ] && saw "$OUT" 'non-interactively'; then
  ok "refuses a headless ack"
  saw "$OUT" 'force-stale'  && ok "directs the caller to the bypass" || bad "refuses but offers no path forward"
  saw "$OUT" 'BUILD-LOG'    && ok "says the bypass will be logged"   || bad "does not say it is logged"
else
  bad "acked without a human present (exit $R) — PROTOCOL-ACK now means nothing"
fi
[ -f "$PROJ/docs/BUILD-LOG.md" ] && bad "a refused ack still wrote to the build log" \
                                 || ok "a refused ack wrote nothing"
grep -q "Toolkit commit: $ACKED" "$PROJ/PROJECT.md" && ok "register untouched by the refusal" \
                                                    || bad "register was rewritten by a refused ack"

echo "== T11: --ack-protocol under a TTY updates the register and logs WHAT and HOW MUCH =="
setup t11; push_change skills/source-triage.md edit
NEWREF="$(git -C "$TK" rev-parse --short HEAD)"
# Driving the prompt needs a REAL pty, because the ack deliberately refuses without one.
# script(1) is not usable here: on BSD/macOS it delivers an EOF ahead of the piped input, so the
# first `read` returns empty and the ack aborts — the prompt echoes "^Dy". A python pty driver
# feeds the answer only after the prompt has actually appeared, which is also a stronger test:
# it proves the prompt is reached and readable rather than merely that the process exited.
PTY_DRIVER="$WORK/drive_pty.py"
cat > "$PTY_DRIVER" <<'PYDRIVER'
import os, pty, select, sys, time
cmd = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.environ["GIT_PAGER"] = "cat"; os.environ["PAGER"] = "cat"
    os.execvp(cmd[0], cmd)
buf, sent, deadline = b"", False, time.time() + 20
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        if not sent and b"[d=diff" in buf:
            os.write(fd, b"y\n"); sent = True
    if os.waitpid(pid, os.WNOHANG)[0] == pid:
        break
sys.stdout.write(buf.decode("utf-8", "replace"))
PYDRIVER
if [ -n "$PY" ]; then
  "$PY" "$PTY_DRIVER" "$GC" --no-html --ack-protocol "$PROJ" > "$WORK/ack.out" 2>&1
  grep -q 'd=diff' "$WORK/ack.out" && ok "the ack prompt is reached under a TTY" \
                                   || bad "never reached the prompt: $(tail -1 "$WORK/ack.out")"
  if grep -q "Toolkit commit: $NEWREF" "$PROJ/PROJECT.md"; then
    ok "register stamped with the new commit"
  else
    bad "register not stamped: $(grep -m1 'Toolkit commit' "$PROJ/PROJECT.md")"
  fi
  if grep -q 'PROTOCOL-ACK' "$PROJ/docs/BUILD-LOG.md" 2>/dev/null; then
    ok "PROTOCOL-ACK logged"
    # The log entry is the ONLY thing separating a read from a rubber stamp, so it must carry
    # the file list AND the line count — not merely the fact that an ack happened.
    grep -q 'source-triage.md' "$PROJ/docs/BUILD-LOG.md" && ok "log records WHICH files" \
                                                         || bad "log does not name the files"
    grep -qE 'insertion|deletion' "$PROJ/docs/BUILD-LOG.md" && ok "log records HOW MUCH changed" \
                                                            || bad "log has no line count"
  else
    bad "no PROTOCOL-ACK line in docs/BUILD-LOG.md"
  fi
  [ "$(sync_status 0)" = "PASS" ] && ok "the notice stops after the ack" || bad "still notifying: $(sync_status 0)"
else
  echo "  skip (no Python 3 to allocate a pty)"
fi

echo "== T14: an informational run is unaffected =="
setup t14; push_change skills/conversion-runbook.md edit
[ "$(rc "")" = "0" ] && ok "bare run exits 0" || bad "bare run exited $(rc "")"
saw "$(run "")" ' A)' && ok "and still shows the notice" || bad "informational run swallowed the notice"

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]

# ── Control: the plain-language default ──────────────────────────────────────
# The notice a non-developer actually meets. It must state the situation in words, say plainly
# that nothing is blocked, tell the agent to ask rather than decide, and point at --verbose for
# anyone who wants the identifiers. It must NOT lead with a commit id.
PLAIN="$("$GC" --no-html "$PROJ" 0 2>&1)"
saw "$PLAIN" '^Toolkit updates:' && ok "plain default leads with a plain verdict line" \
  || bad "plain default did not print a 'Toolkit updates:' line"
saw "$PLAIN" 'Sync (Protocol freshness)' && bad "plain default still prints the jargon verdict" \
  || ok "plain default suppresses the jargon verdict line"
if saw "$PLAIN" ' A)'; then
  saw "$PLAIN" 'nothing is blocked' && ok "plain notice says nothing is blocked" \
    || bad "plain notice does not say nothing is blocked"
  saw "$PLAIN" 'verbose' && ok "plain notice points at --verbose" \
    || bad "plain notice offers no route to the detail"
  saw "$PLAIN" 'approved-in-chat' && ok "plain notice names the no-terminal ack path" \
    || bad "plain notice does not name --approved-in-chat"
  saw "$PLAIN" 'do not ask them to type anything' && ok "plain notice tells the agent not to delegate typing" \
    || bad "plain notice does not tell the agent to relay"
fi
