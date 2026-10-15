#!/usr/bin/env bash
# Fixture for #294: project-bin/mxpatch.py (find a unit / element, get / set a value, write +
# ContentsHash, dry-run / already-applied / refuse-if-drifted), mxunit_bson.py's BSON 0x09, and
# the two wf-*.py patchers ported onto it.
#
# usage: bash tests/wave2/test-mxpatch.sh /path/to/project-bin/exec.sh
#   (any file in project-bin, or the directory itself; run-all.sh only resolves a named
#   .sh/.md subject, so the usage line names exec.sh and the fixture tests its directory)
#
# Golden input is captured, never written: fixtures/mxpatch/model/ is a real MPR v2 model
# (Studio Pro-authored base + units mxcli v0.21.0 / v0.26.0 wrote), and the expected verdicts
# are verbatim `mxcli fix hashes` captures on that same model (fixtures/mxpatch/CAPTURE.txt).
# The ContentsHash check in this file is its OWN code (sha256 + base64 against the sqlite
# index), never the subject's mxpatch, so it can judge any version of the patchers.
#
# Positive control: against master's project-bin (before 2026-10-14) every mxpatch case fails
# (no mxpatch.py), the 0x09 case fails (the codec raises), and the patcher cases fail on
# "index stale after --apply" — the defect, reproduced. [guard] marks regression guards.
set -uo pipefail
BIN="${1:?usage: test-mxpatch.sh /path/to/project-bin/exec.sh}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
[ -f "$BIN" ] && BIN="$(dirname "$BIN")"
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/mxpatch"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mxpatch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
. "$TK/bin/lib/portable.sh"; require_py
# Backups land here, never in the system temp dir (case P checks the default separately).
export MXPATCH_BACKUP_DIR="$WORK/bak"

WF=056b39ea-2e14-4d12-8ae1-87fa4b3c038a      # Workflows$Workflow MyFirstModule.Approval
SE=c54d8347-a8ec-40ba-b88e-873bfec0a493      # ScheduledEvents$ScheduledEvent (StartDateTime is 0x09)
DM=84776610-13b2-48cb-a265-d5e984d63129      # DomainModels$DomainModel
upath() { printf 'mprcontents/%s/%s/%s.mxunit' "${1:0:2}" "${1:2:2}" "$1"; }

# model <dir> — the captured model, its .mpr rebuilt from the committed sqlite dump.
model() {
  rm -rf "$1"; mkdir -p "$1"; cp -r "$FX/model/mprcontents" "$1/"
  "$PY" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.executescript(open(sys.argv[2]).read()); c.commit()' \
    "$1/TestApp.mpr" "$FX/model/TestApp.mpr.sql"
}
# idx <dir> — this fixture's own index check: "<KIND> <uuid>" per problem, then "checked N".
IDX_PY='
import sys, os, glob, sqlite3, hashlib, base64, uuid
d = sys.argv[1]; c = sqlite3.connect(os.path.join(d, "TestApp.mpr"))
rows = [(bytes(u), h) for u, h in c.execute("SELECT UnitID, ContentsHash FROM Unit")]
seen = set()
for u, h in rows:
    n = str(uuid.UUID(bytes_le=u)); seen.add(n)
    p = os.path.join(d, "mprcontents", n[:2], n[2:4], n + ".mxunit")
    if not os.path.isfile(p): print("MISSING", n); continue
    f = base64.b64encode(hashlib.sha256(open(p, "rb").read()).digest()).decode()
    if f != h: print("MISMATCH", n, f)
for p in glob.glob(os.path.join(d, "mprcontents", "*", "*", "*.mxunit")):
    n = os.path.basename(p)[:-7]
    if n not in seen: print("ORPHAN", n)
print("checked", len(rows))
'
idx() { "$PY" -c "$IDX_PY" "$1"; }
stored() { "$PY" -c 'import sqlite3,sys,uuid; print(sqlite3.connect(sys.argv[1]).execute("SELECT ContentsHash FROM Unit WHERE UnitID=?",(uuid.UUID(sys.argv[2]).bytes_le,)).fetchone()[0])' "$1/TestApp.mpr" "$2"; }
MXP() { "$PY" "$BIN/mxpatch.py" "$@"; }

echo "== H: the hash routine agrees with mxcli on the captured model =="
M="$WORK/h"; model "$M"
OUT="$(idx "$M")"
[ "$OUT" = "checked 27" ] && grep -q '^Checked 27 unit(s)' "$FX/verify-clean-v0.26.0.out" \
  && ok "[guard] rebuilt model: 27/27 stored hashes = base64(sha256(file)), as mxcli v0.26.0 found" || bad "rebuilt model" "$OUT"
OUT="$(MXP verify "$M/TestApp.mpr" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^0 mismatch(es), 0 missing file(s), 0 orphan file(s)\.$' \
  && ok "mxpatch verify: clean, mxcli's summary line" || bad "mxpatch verify clean rc=$RC" "$OUT"
"$PY" -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(\"UPDATE Unit SET ContentsHash='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' WHERE UnitID=?\",(bytes.fromhex('10667784B213CB48A265D5E984D63129'),)); c.commit()" "$M/TestApp.mpr"
WANT="$(grep -E '^ +stored ' "$FX/verify-stale-v0.26.0.out" | sed 's/.*, file //')"
OUT="$(MXP verify "$M/TestApp.mpr" 2>&1)"; RC=$?
[ "$RC" -eq 5 ] && printf '%s' "$OUT" | grep -q "MISMATCH  $DM  stored AAAA.*, file $WANT" \
  && ok "stale row: MISMATCH on $DM with the file hash mxcli printed ($WANT)" || bad "stale rc=$RC" "$OUT"
M="$WORK/o"; model "$M"
cp "$M/$(upath $DM)" "$M/mprcontents/84/77/11111111-2222-3333-4444-555555555555.mxunit"
rm "$M/$(upath 3f64baa2-b85c-4999-9a3c-3cc38382eb54)"
OUT="$(MXP verify "$M/TestApp.mpr" 2>&1)"
GOT="$(printf '%s\n' "$OUT" | awk '/^  (MISSING|ORPHAN)/{print $1, $2}' | sort | tr '\n' ' ')"
EXP="$(awk '/^  MISSING/{print $1, $2} /^  ORPHAN/{n=$2; sub(/.*\//,"",n); sub(/\.mxunit$/,"",n); print $1, n}' "$FX/verify-orphan-missing-v0.26.0.out" | sort | tr '\n' ' ')"
[ -n "$EXP" ] && [ "$GOT" = "$EXP" ] && ok "MISSING + ORPHAN: the same units mxcli reported" || bad "missing/orphan" "got: $GOT"$'\n'"exp: $EXP"

echo "== B: mxunit_bson reads and re-encodes BSON 0x09 (UTC datetime) =="
M="$WORK/b"; model "$M"
OUT="$("$PY" -c '
import sys, glob, os; sys.path.insert(0, sys.argv[1]); import mxunit_bson as m
n = same = 0
for p in glob.glob(os.path.join(sys.argv[2], "mprcontents", "*", "*", "*.mxunit")):
    b = open(p, "rb").read(); d, _ = m.dec_doc(b, 0); n += 1; same += m.enc_doc(d) == b
d = m.load(sys.argv[3]); print(n, same, [ (hex(t), v) for t, k, v in d if k == "StartDateTime"])
' "$BIN" "$M" "$M/$(upath $SE)" 2>&1)"
[ "$OUT" = "27 27 [('0x9', -62135596800000)]" ] && ok "27/27 units byte-identical; StartDateTime = 0x09 int64 ms" || bad "codec" "$OUT"

echo "== F: find a unit (byte pre-filter + decode), by type, name and module =="
M="$WORK/f"; model "$M"
OUT="$(MXP find "$M/TestApp.mpr" --type 'Workflows$Workflow' 2>&1)"
[ "$OUT" = "$(printf 'Workflows$Workflow\tMyFirstModule.Approval\tmprcontents/05/6b/%s.mxunit' "$WF")" ] && ok "by type: the workflow, with its module" || bad "find type" "$OUT"
OUT="$(MXP find "$M/TestApp.mpr" --name NightlyCleanup 2>&1)"
printf '%s' "$OUT" | grep -q "^ScheduledEvents\$ScheduledEvent	MyFirstModule.NightlyCleanup	" && ok "by name alone" || bad "find name" "$OUT"
MXP find "$M/TestApp.mpr" --type 'Workflows$Workflow' --name Approval --module Nope >/dev/null 2>&1; RC=$?
[ "$RC" -eq 4 ] && ok "wrong module: exit 4" || bad "wrong module rc=$RC"
OUT="$(MXP get "$M/TestApp.mpr" --type 'Workflows$Workflow' --name Approval --element Nope --key Caption 2>&1)"; RC=$?
[ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q 'no element named Nope' && ok "missing element: exit 4, named" || bad "missing element rc=$RC" "$OUT"
OUT="$(MXP get "$M/TestApp.mpr" --type 'Workflows$Workflow' --name Approval --element ACT_Approval_Notify --key Caption 2>&1)"
[ "$OUT" = "ACT_Approval_Notify" ] && ok "get an element's value by key" || bad "get" "$OUT"

echo "== S: set — dry run, apply + hash, already applied, refuse-if-drifted =="
M="$WORK/s"; model "$M"; BEFORE="$(cat "$M/$(upath $SE)" | "$PY" -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
SET_SE() { MXP set "$M/TestApp.mpr" --type 'ScheduledEvents$ScheduledEvent' --name NightlyCleanup --key Enabled --value false --expect true "$@"; }
OUT="$(SET_SE 2>&1)"; RC=$?
AFTER="$(cat "$M/$(upath $SE)" | "$PY" -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
[ "$RC" -eq 0 ] && [ "$BEFORE" = "$AFTER" ] && printf '%s' "$OUT" | grep -q 'Dry run' && ok "dry run: exit 0, unit untouched" || bad "dry rc=$RC" "$OUT"
[ "$(idx "$M")" = "checked 27" ] && ok "[guard] dry run: index untouched" || bad "dry run index"
OUT="$(SET_SE --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(idx "$M")" = "checked 27" ] && ok "apply: file and ContentsHash written together (index clean)" || bad "apply rc=$RC" "$OUT"$'\n'"$(idx "$M")"
OUT="$(MXP set "$M/TestApp.mpr" --type 'Workflows$Workflow' --name Approval --element ACT_Approval_Notify --key Caption \
        --value 'Notify the requester' --expect ACT_Approval_Notify --apply 2>&1)"
# The two hashes mxcli v0.26.0 verified clean after the same two writes (CAPTURE.txt, after-mxpatch-set).
[ "$(stored "$M" $SE)" = "V77jJhY1rHPZmUik9MNfog/UcINc2Zh95K9OVcaC1zU=" ] && [ "$(stored "$M" $WF)" = "Vp32DjJUjMa/yvpHOoloJq38zHdez18DBK3VJI+cwWU=" ] \
  && grep -q 'The ContentsHash index matches every unit file' "$FX/after-mxpatch-set-v0.26.0.out" \
  && ok "the written hashes are the ones mxcli v0.26.0 verified on the same writes" || bad "hashes vs capture" "$(stored "$M" $SE) $(stored "$M" $WF)"
OUT="$(SET_SE --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'already applied, skipped' && ok "re-run: already applied, skipped" || bad "already rc=$RC" "$OUT"
H1="$(stored "$M" $SE)"
OUT="$(MXP set "$M/TestApp.mpr" --type 'ScheduledEvents$ScheduledEvent' --name NightlyCleanup --key OnOverlap --value SkipNext --expect SomethingElse --apply 2>&1)"; RC=$?
[ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q "refusing: .*OnOverlap is 'DelayNext'" && [ "$(stored "$M" $SE)" = "$H1" ] \
  && ok "drifted: exit 3, refused, nothing written" || bad "drift rc=$RC" "$OUT"
OUT="$(MXP set "$M/TestApp.mpr" --type 'ScheduledEvents$ScheduledEvent' --name NightlyCleanup --key StartDateTime --value 0 --apply 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q '0x09, which mxpatch does not set' && ok "a type it does not set: refused, not guessed" || bad "0x09 set rc=$RC" "$OUT"

echo "== P: the ported patchers keep the index in step =="
M="$WORK/p"; model "$M"
OUT="$("$PY" "$BIN/wf-add-path-terminators.py" "$M/$(upath $WF)" --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'terminators to add   : 2' && ok "[guard] terminators: 2 added (v0.21.0-written split)" || bad "terminators rc=$RC" "$OUT"
I="$(idx "$M")"; [ "$I" = "checked 27" ] && ok "terminators --apply (unit-path form): index clean" || bad "terminators: index stale after --apply" "$I"
# Field run #390: the backup was <unit>.mxunit.bak inside mprcontents/, an untracked file in the
# model tree that `git add mprcontents` commits. It must land outside the model tree.
BAKS_IN="$(find "$M/mprcontents" -name '*.bak' | wc -l | tr -d ' ')"
[ "$BAKS_IN" = 0 ] && ok "no *.bak left under mprcontents/ after a successful patch" || bad "$BAKS_IN *.bak under mprcontents/" "$(find "$M/mprcontents" -name '*.bak')"
BAK="$(ls "$MXPATCH_BACKUP_DIR"/$WF.mxunit.*.bak 2>/dev/null | head -1)"
[ -n "$BAK" ] && cmp -s "$BAK" "$FX/model/$(upath $WF)" && printf '%s' "$OUT" | grep -qF "backup (outside mprcontents/): $BAK" \
  && ok "[guard] backup kept in MXPATCH_BACKUP_DIR, the unit's old bytes, path printed" || bad "backup not in MXPATCH_BACKUP_DIR" "$(ls -la "$MXPATCH_BACKUP_DIR" 2>&1)"$'\n'"$OUT"
OUT="$("$PY" "$BIN/wf-add-path-terminators.py" "$M/$(upath $WF)" --apply 2>&1)"
printf '%s' "$OUT" | grep -q 'Every path is already terminated' && ok "[guard] re-run: idempotent" || bad "re-run" "$OUT"
OUT="$("$PY" "$BIN/wf-set-call-captions.py" "$M/$(upath $WF)" --captions MyFirstModule.ACT_Approval_Review='Review the request' --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '2 x MyFirstModule.ACT_Approval_Review' && ok "[guard] captions: 2 call sites set" || bad "captions rc=$RC" "$OUT"
I="$(idx "$M")"; [ "$I" = "checked 27" ] && ok "captions --apply: index clean" || bad "captions: index stale after --apply" "$I"
M="$WORK/q"; model "$M"   # the exec.sh --patch form: <model.mpr> <Module.Workflow>
OUT="$( cd "$M" && "$PY" "$BIN/wf-add-path-terminators.py" TestApp.mpr MyFirstModule.Approval --apply 2>&1 \
     && "$PY" "$BIN/wf-set-call-captions.py" TestApp.mpr MyFirstModule.Approval --captions MyFirstModule.ACT_Approval_Review='Review the request' --apply 2>&1)"; RC=$?
I="$(idx "$M")"; [ "$RC" -eq 0 ] && [ "$I" = "checked 27" ] && ok "exec.sh --patch form (.mpr + qualified name): both applied, index clean" || bad "patch form rc=$RC" "$OUT"$'\n'"$I"
[ "$(find "$M/mprcontents" -name '*.bak' | wc -l | tr -d ' ')" = 0 ] && ok "exec.sh --patch form: no *.bak under mprcontents/ either" || bad "patch form left a .bak in mprcontents/"
M="$WORK/t"; model "$M"; mkdir -p "$WORK/tmpdir"   # no MXPATCH_BACKUP_DIR: the temp dir, not the model tree
OUT="$( cd "$M" && env -u MXPATCH_BACKUP_DIR TMPDIR="$WORK/tmpdir" "$PY" "$BIN/wf-add-path-terminators.py" TestApp.mpr MyFirstModule.Approval --apply 2>&1)"; RC=$?
DEFB="$(ls -d "$WORK/tmpdir"/mxpatch-bak-*/ 2>/dev/null | head -1)"; DEFB="${DEFB%/}"
[ "$RC" -eq 0 ] && [ -n "$DEFB" ] && ls "$DEFB/TestApp/$WF.mxunit."*.bak >/dev/null 2>&1 && [ "$(find "$M" -name '*.bak' | wc -l | tr -d ' ')" = 0 ] \
  && ok "default backup dir: <tempdir>/mxpatch-bak-<uid>/<model>/, nothing in the model tree" || bad "default backup rc=$RC" "$OUT"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;   # no POSIX modes there
  *) PERM="$("$PY" -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$DEFB" 2>/dev/null)"
     [ "$PERM" = 0o700 ] && ok "[guard] default backup dir is private (0700), not a shared predictable /tmp dir" || bad "default backup dir mode: ${PERM:-<none>}" ;;
esac
# Two writes to the same unit within one second keep two backups (the name was one-second resolution).
M="$WORK/b2"; model "$M"; rm -rf "$WORK/bak2"
MXPATCH_BACKUP_DIR="$WORK/bak2" "$PY" -c '
import sys; sys.path.insert(0, sys.argv[1]); import mxpatch
m = mxpatch.Model(sys.argv[2])
for v in ("First", "Second"):        # one process, well inside one second
    u = m.find_unit("Workflows$Workflow", "Approval")
    mxpatch.set_value(mxpatch.find_element(u.doc, "ACT_Approval_Notify"), "Caption", v)
    m.write_unit(u, apply=True, backup=True, log=lambda s: None)
' "$BIN" "$M/TestApp.mpr" >/dev/null 2>&1
NB="$(ls "$WORK/bak2" 2>/dev/null | wc -l | tr -d ' ')"
[ "$NB" = 2 ] && ok "[guard] two writes in the same second: 2 backups, none overwritten" || bad "same-second backups: $NB" "$(ls -la "$WORK/bak2" 2>&1)"
M="$WORK/r"; model "$M"; F0="$("$PY" -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$M/$(upath $WF)")"
OUT="$( cd "$M" && MXPATCH_BACKUP_DIR="$M/mprcontents/bak" "$PY" "$BIN/wf-add-path-terminators.py" TestApp.mpr MyFirstModule.Approval --apply 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && [ ! -e "$M/mprcontents/bak" ] && [ "$(idx "$M")" = "checked 27" ] && printf '%s' "$OUT" | grep -q 'is inside' \
  && [ "$F0" = "$("$PY" -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$M/$(upath $WF)")" ] \
  && ok "[guard] MXPATCH_BACKUP_DIR inside mprcontents/: refused before anything is written" || bad "inside-mprcontents rc=$RC" "$OUT"
# The same refusal through a symlink into mprcontents/, and through another case spelling
# (MPRCONTENTS/ is mprcontents/ on macOS and Windows; refused everywhere, which only refuses more).
ln -s "$M/mprcontents" "$WORK/mc-link"
for probe in "$WORK/mc-link/x" "$M/MPRCONTENTS/x"; do
  OUT="$( cd "$M" && MXPATCH_BACKUP_DIR="$probe" "$PY" "$BIN/wf-add-path-terminators.py" TestApp.mpr MyFirstModule.Approval --apply 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'is inside' && [ "$(idx "$M")" = "checked 27" ] \
    && [ "$(find "$M/mprcontents" -name '*.bak' | wc -l | tr -d ' ')" = 0 ] && [ ! -e "$M/MPRCONTENTS" ] \
    && ok "[guard] MXPATCH_BACKUP_DIR=${probe#$WORK/}: refused, nothing written" || bad "probe ${probe#$WORK/} rc=$RC" "$OUT"
done
grep -q 'The ContentsHash index matches every unit file' "$FX/after-ported-patchers-v0.26.0.out" && grep -q "MISMATCH  $WF" "$FX/after-master-patchers-v0.26.0.out" \
  && ok "[guard] captured: mxcli v0.26.0 found master's patchers stale and these clean, on this model" || bad "capture files"

echo "== W: write order — every crash state is one fix hashes reports and a re-run repairs (#374 review) =="
# FAULT_PY <bin> <model> <mode>: runs `mxpatch set Enabled=false` on the scheduled event with one
# fault injected. kill = os._exit between the index commit and the file swap (a SIGKILL there);
# swapfail = os.replace raises; tmpfail = the temp write raises; commitfail = the index commit raises.
FAULT_PY='
import sys, os, builtins
sys.path.insert(0, sys.argv[1]); import mxpatch
mode, mpr = sys.argv[3], os.path.join(sys.argv[2], "TestApp.mpr")
if mode == "kill":
    real = mxpatch._atomic_write
    def aw(path, data):
        if path.endswith(".mxunit"): os._exit(9)
        return real(path, data)
    mxpatch._atomic_write = aw
elif mode == "swapfail":
    def rep(a, b): raise OSError("injected: replace failed")
    mxpatch.os.replace = rep
elif mode == "tmpfail":
    ropen = builtins.open
    class F(object):
        def __init__(s, fh): s.fh = fh
        def __enter__(s): return s
        def __exit__(s, *a): s.fh.close()
        def write(s, d): s.fh.write(d[:10]); raise OSError("injected: disk full")
    def op(path, mode_="r", *a, **k):
        fh = ropen(path, mode_, *a, **k)
        return F(fh) if str(path).endswith(".mxpatch-tmp") else fh
    builtins.open = op
elif mode == "commitfail":
    rdb = mxpatch.Model._db
    class C(object):
        def __init__(s, c): s.c = c
        def execute(s, *a): return s.c.execute(*a)
        def commit(s): raise RuntimeError("injected: database is locked")
        def rollback(s): return s.c.rollback()
        def close(s): return s.c.close()
    mxpatch.Model._db = lambda self: C(rdb(self))
try:
    sys.exit(mxpatch.main(["set", mpr, "--type", "ScheduledEvents$ScheduledEvent", "--name", "NightlyCleanup",
                           "--key", "Enabled", "--value", "false", "--expect", "true", "--apply"]))
except BaseException as e:
    print("raised:", type(e).__name__, e); sys.exit(1)
'
fault() { "$PY" -c "$FAULT_PY" "$BIN" "$1" "$2" >"$WORK/fault.$2" 2>&1; }
filesum() { "$PY" -c 'import sys,hashlib; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
M="$WORK/w1"; model "$M"; F0="$(filesum "$M/$(upath $SE)")"
fault "$M" kill; RC=$?
I="$(idx "$M")"
[ "$RC" -eq 9 ] && [ "$(filesum "$M/$(upath $SE)")" = "$F0" ] && printf '%s' "$I" | grep -q "^MISMATCH $SE " \
  && ok "kill between index commit and swap: old unit intact, index MISMATCH (what fix hashes reports)" || bad "kill rc=$RC" "$I"
OUT="$(MXP set "$M/TestApp.mpr" --type 'ScheduledEvents$ScheduledEvent' --name NightlyCleanup --key Enabled --value false --expect true --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(idx "$M")" = "checked 27" ] && printf '%s' "$OUT" | grep -q 'already stale' \
  && [ "$(stored "$M" $SE)" = "V77jJhY1rHPZmUik9MNfog/UcINc2Zh95K9OVcaC1zU=" ] && ok "re-run after the kill repairs it: index clean, the captured hash" || bad "repair rc=$RC" "$OUT"$'\n'"$(idx "$M")"
for mode in swapfail tmpfail commitfail; do
  M="$WORK/w-$mode"; model "$M"; F0="$(filesum "$M/$(upath $SE)")"
  fault "$M" $mode; RC=$?
  LEFT="$(find "$M/mprcontents" -name '*.mxpatch-tmp' | wc -l | tr -d ' ')"
  [ "$RC" -ne 0 ] && [ "$(filesum "$M/$(upath $SE)")" = "$F0" ] && [ "$(idx "$M")" = "checked 27" ] && [ "$LEFT" = 0 ] \
    && ok "$mode: unit unchanged, index consistent, no .mxpatch-tmp left" || bad "$mode rc=$RC tmp=$LEFT" "$(cat "$WORK/fault.$mode")"$'\n'"$(idx "$M")"
done

echo "== U: no model path is a usage error, not a traceback =="
OUT="$(MXP set --type 'Workflows$Workflow' --name Approval --key Caption --value x 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'usage: mxpatch.py set <model.mpr>' && ! printf '%s' "$OUT" | grep -q Traceback \
  && ok "set without a model: exit 2, usage" || bad "no model rc=$RC" "$OUT"

echo "== D: the ported patchers refuse drift =="
M="$WORK/d"; model "$M"
MXP set "$M/TestApp.mpr" --type 'Workflows$Workflow' --name Approval --element ACT_Approval_Notify --key Caption --value 'Hand edited' --apply >/dev/null 2>&1
H0="$(stored "$M" $WF)"; F0="$(filesum "$M/$(upath $WF)")"
OUT="$(cd "$M" && "$PY" "$BIN/wf-set-call-captions.py" TestApp.mpr MyFirstModule.Approval --captions MyFirstModule.ACT_Approval_Notify='Notify' --apply 2>&1)"; RC=$?
[ "$RC" -eq 3 ] && [ "$(filesum "$M/$(upath $WF)")" = "$F0" ] && [ "$(stored "$M" $WF)" = "$H0" ] && printf '%s' "$OUT" | grep -q "REFUSED" \
  && ok "captions: a hand-edited caption is refused, exit 3, nothing written" || bad "captions drift rc=$RC" "$OUT"
OUT="$(cd "$M" && "$PY" "$BIN/wf-set-call-captions.py" TestApp.mpr MyFirstModule.Approval --captions MyFirstModule.ACT_Approval_Notify='Notify' --expect-caption MyFirstModule.ACT_Approval_Notify='Hand edited' --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(idx "$M")" = "checked 27" ] && ok "captions: --expect-caption names it, applied, index clean" || bad "expect-caption rc=$RC" "$OUT"
F0="$(filesum "$M/$(upath $WF)")"
OUT="$(cd "$M" && "$PY" "$BIN/wf-add-path-terminators.py" TestApp.mpr MyFirstModule.Approval --expect-paths 3 --apply 2>&1)"; RC=$?
[ "$RC" -eq 3 ] && [ "$(filesum "$M/$(upath $WF)")" = "$F0" ] && ok "terminators: --expect-paths 3 on a 2-path split: exit 3, nothing written" || bad "paths drift rc=$RC" "$OUT"
OUT="$(cd "$M" && "$PY" "$BIN/wf-add-path-terminators.py" TestApp.mpr MyFirstModule.Approval --expect-paths 2 --apply 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(idx "$M")" = "checked 27" ] && ok "terminators: --expect-paths 2: applied, index clean" || bad "expect-paths rc=$RC" "$OUT"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
