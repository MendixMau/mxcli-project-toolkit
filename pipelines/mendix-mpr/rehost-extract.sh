#!/usr/bin/env bash
# rehost-extract.sh — read an existing Mendix .mpr, emit each own module as MDL, replay it into a
# fresh target .mpr of the same Mendix version, and write the fidelity ledger.
#
#   pipelines/mendix-mpr/rehost-extract.sh <source.mpr> <target.mpr> <out-dir> [Module ...]
#
#   <out-dir>/captures/   verbatim mxcli output (golden fixtures: list modules, show <type> <Module>,
#                         project-tree.json, check/exec logs, timings.tsv per module, phases.tsv per phase)
#   <out-dir>/mdl/        <Module>.mdl (source describe), <Module>.ordered.mdl (what was executed),
#                         target-<Module>.mdl (describe of the target afterwards), _settings/_userroles
#   <out-dir>/fidelity-ledger.tsv   one row per source document (denominator in the header)
#
# Modules default to every module `list modules` shows with an empty Source column except System.
# The target must already exist (`mxcli new <App> --version <same> --theme none`); this script
# creates nothing but model content. It does NOT run the build gate — run project-bin/exec.sh's
# mxbuild gate or `~/.mxcli/mxbuild/<ver>/modeler/mx check <target.mpr>` afterwards.
#
# Field run (2026-10-12, mxcli v0.26.0, Linux container): a public banking sample app
# (Mendix 11.13.0, one own module of 151 documents + MyFirstModule 4) -> `mxcli new --version 11.13.0`.
# 155/155 catalog documents emitted, 154 identical on target describe, 1 documentation drift,
# `mx check` and `mxbuild --target=deploy` clean. Everything in here was exercised on that run:
#   - the whole-module emitter is the MDL statement `describe module <M> with all` run through -c;
#     the `mxcli describe module <M>` SUBCOMMAND emits only the module and its roles (0.26.0).
#   - describe emits microflows in catalog order, so `check` reported 14 MDL-ORDER01 (callee
#     created after caller) and exec refused the file; lib/topo-order-mdl.py reorders flow units
#     (create + its grant execute statements) and the reordered file checked clean.
#   - `describe module … with all` omits image collections (MyFirstModule.Images) — described
#     separately below so the ledger has the row.
#   - demo users describe with Password: '***' and exec refuses the placeholder; project security
#     level describes as a report, not MDL. Both are ledger hand-off rows, never executed here.
# Not exercised: nanoflows, Java/JavaScript actions, snippets, workflows, REST/OData, marketplace
# install (the blank template already carried the source's seven modules at the same versions).
# Portability: bash 3.2 (stock macOS) — no mapfile, no associative arrays; timing goes through
# Python because `date +%s.%N` and `bc` are missing there. Only Linux runs are field-proven.
set -euo pipefail

SRC="${1:?usage: rehost-extract.sh <source.mpr> <target.mpr> <out-dir> [Module ...]}"
TGT="${2:?target.mpr}"
OUT="${3:?out-dir}"
shift 3
HERE="$(cd "$(dirname "$0")" && pwd)"
MXCLI="${MXCLI:-$(command -v mxcli || true)}"
[ -x "$MXCLI" ] || { echo "mxcli not found: set MXCLI=/path/to/mxcli" >&2; exit 2; }
PY="${PYTHON:-python3}"
# the source is read-only: a target that resolves to the same file would be overwritten by exec
_real() { "$PY" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
[ "$(_real "$SRC")" != "$(_real "$TGT")" ] || { echo "source and target are the same file: $SRC — refusing" >&2; exit 2; }
mkdir -p "$OUT/captures" "$OUT/mdl"
mx() { "$MXCLI" "$@" 2>&1 | grep -v 'vibe-coded PoC'; }   # one warning line per call, drop it
log() { printf '%s\n' "$*" >&2; }

T_START=$("$PY" -c 'import time; print("%.3f" % time.time())')
phase() { "$PY" -c 'import sys, time; t = time.time(); print("%s\t%.1f" % (sys.argv[1], t - float(open(sys.argv[2]).read() or sys.argv[3])))' "$1" "$OUT/captures/.phase-mark" "$T_START" >> "$OUT/captures/phases.tsv"; "$PY" -c 'import time; print("%.3f" % time.time())' > "$OUT/captures/.phase-mark"; }
printf 'phase\tseconds\n' > "$OUT/captures/phases.tsv"; : > "$OUT/captures/.phase-mark"
# ---- 1. inventory (golden captures) ---------------------------------------------------------
mx -p "$SRC" list modules > "$OUT/captures/list-modules.txt"
"$MXCLI" -p "$SRC" project-tree --json 2>/dev/null > "$OUT/captures/project-tree.json"
if [ $# -eq 0 ]; then
  # own module = empty Source column, not System
  MODULES=(); while IFS= read -r _m; do MODULES+=("$_m"); done < <(awk -F'|' -f "$HERE/lib/own-modules.awk" "$OUT/captures/list-modules.txt")
else
  MODULES=("$@")
fi
# bash 3.2 under set -u dies on "${MODULES[@]}" when the array is empty
[ ${#MODULES[@]} -gt 0 ] || { log "no own modules in captures/list-modules.txt — name them as arguments"; exit 2; }
log "own modules: ${MODULES[*]}"
for M in "${MODULES[@]}"; do
  for t in entities associations enumerations microflows nanoflows pages snippets javaactions; do
    mx -p "$SRC" show "$t" "$M" | grep -v '^Connected to' > "$OUT/captures/show-$t-$M.txt"
  done
done

phase inventory
# ---- 2. extract -------------------------------------------------------------------------------
# describe_module <mpr> <Module> <out.mdl>: `describe module … with all` plus every describable
# document of the module that the whole-module emitter omits, described one by one from the
# project tree. On 0.26.0 `with all` omits image collections (banking sample run) and, on a public
# GenAI showcase app (48 modules), nanoflows, snippets, JavaScript actions, JSON structures, import/export
# mappings, task queues, scheduled events and some pages. Used for the source and, in step 4, for
# the target, so both sides carry the same document set.
describe_module() {
  local mpr="$1" M="$2" out="$3"
  # `|| true`: on the target side the module may not exist at all (its check failed) — the ledger says so
  "$MXCLI" -p "$mpr" -c "describe module $M with all" 2>/dev/null | grep -v 'vibe-coded PoC' > "$out" || true
  # 0.26.0 cuts `-c` output at 10 000 lines without saying so (two modules of the GenAI showcase app
  # both ended mid-page at line 10 001). Keep only complete statements; the tree fill-in
  # below then describes every document the cut swallowed, one by one.
  "$PY" -I - "$out" "$HERE/lib" <<'PYEOF' >&2
import sys; sys.path.insert(0, sys.argv[2])
from mdlsplit import split_statements
text = open(sys.argv[1], encoding='utf-8', newline='').read()
stmts, tail = split_statements(text)
if tail.strip():
    open(sys.argv[1], 'w', encoding='utf-8', newline='').write('\n'.join(stmts) + '\n')
    print('describe module truncated at %d lines (incomplete last statement dropped: %s)' % (text.count('\n'), tail.strip().split('\n')[0][:80]))
PYEOF
  "$MXCLI" -p "$mpr" project-tree --json 2>/dev/null > "$out.tree.json"
  "$PY" -I - "$M" "$out" "$out.tree.json" <<'PYEOF' | while read -r t q; do
import json,re,sys
M, out, tree = sys.argv[1], sys.argv[2], sys.argv[3]
have = set(re.findall(r'^create or modify [a-z -]+? (' + re.escape(M) + r'\.[A-Za-z0-9_]+)', open(out, encoding='utf-8', newline='').read(), re.M))
def walk(n):
    for x in n:
        q = x.get('qualifiedName', '')
        if x.get('describable') and q.startswith(M + '.') and q not in have and x.get('type') not in ('modulerole',):
            print(x['type'], q)
        walk(x.get('children', []))
walk(json.load(open(tree)))
PYEOF
    "$MXCLI" -p "$mpr" describe "$t" "$q" 2>/dev/null | grep -v 'vibe-coded PoC' | sed '1{/^mdl 1;$/d}' >> "$out"
  done
  rm -f "$out.tree.json"
}
# timing in Python: `date +%s.%N` and `bc` do not exist on stock macOS
now() { "$PY" -c 'import time; print("%.3f" % time.time())'; }
since() { "$PY" -c 'import sys, time; print("%.1f" % (time.time() - float(sys.argv[1])))' "$1"; }
diff_s() { "$PY" -c 'import sys; print("%.1f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"; }
TIMES="$OUT/captures/timings.tsv"
printf 'module\tdescribe_s\ttopo_s\tcheck_s\texec_s\tdescribe_target_s\n' > "$TIMES"
# per-module timings live in files, not associative arrays (bash 3.2 has none)
TDIR="$OUT/captures/.t"; mkdir -p "$TDIR"
tset() { printf '%s' "$3" > "$TDIR/$1.$2"; }        # tset <KEY> <Module> <value>
tget() { cat "$TDIR/$1.$2" 2>/dev/null || true; }   # tget <KEY> <Module>
# REHOST_REUSE_MDL=1 skips the source describes when <out>/mdl/<M>.mdl already exists (a rerun after
# fixing the check/exec side; the describes are the slow part — 36 modules took 30 min on the GenAI showcase app).
for M in "${MODULES[@]}"; do
  t0=$(now)
  if [ "${REHOST_REUSE_MDL:-0}" = 1 ] && [ -s "$OUT/mdl/$M.mdl" ]; then log "reusing mdl/$M.mdl"; else describe_module "$SRC" "$M" "$OUT/mdl/$M.mdl"; fi
  t1=$(now)
  "$PY" -I "$HERE/lib/topo-order-mdl.py" "$OUT/mdl/$M.mdl" "$OUT/mdl/$M.ordered.mdl" 2>>"$OUT/captures/describe-$M.stderr"
  "$PY" -I "$HERE/lib/fix-describe-output.py" "$OUT/mdl/$M.ordered.mdl" "$OUT/mdl/$M.ordered.mdl" 2>>"$OUT/captures/describe-$M.stderr"
  tset DESC "$M" "$(diff_s "$t0" "$t1")"; tset TOPO "$M" "$(since "$t1")"
done
# module order: replay the modules so that each is created after every listed module it references
# (qualified-name mention in its describe output); REHOST_KEEP_ORDER=1 keeps the order given. A cycle
# between modules is reported and left in the given order — exec then fails on the forward reference
# and the ledger says so.
if [ "${REHOST_KEEP_ORDER:-0}" = 0 ]; then
  _order=$("$PY" -I - "$OUT/mdl" "${MODULES[@]}" <<'PYEOF'
import re,sys
d, mods = sys.argv[1], sys.argv[2:]
body = {m: open('%s/%s.mdl' % (d, m), encoding='utf-8', newline='').read() for m in mods}
deps = {m: {o for o in mods if o != m and re.search(r'\b' + re.escape(o) + r'\.[A-Za-z0-9_]', body[m])} for m in mods}
order, placed, rest = [], set(), list(mods)
while rest:
    ready = [m for m in rest if deps[m] <= placed]
    if not ready:
        sys.stderr.write('module cycle among: %s (left in catalog order)\n' % ', '.join(rest)); order += rest; break
    for m in ready: order.append(m); placed.add(m); rest.remove(m)
print('\n'.join(order))
PYEOF
  )
  MODULES=(); while IFS= read -r _m; do [ -n "$_m" ] && MODULES+=("$_m"); done <<EOF_ORDER
$_order
EOF_ORDER
  log "replay order: ${MODULES[*]}"
fi
"$MXCLI" -p "$SRC" describe settings Settings 2>/dev/null | grep -v 'vibe-coded PoC' > "$OUT/mdl/_settings.mdl"
mx -p "$SRC" -c "show user roles" > "$OUT/captures/show-userroles.txt"
: > "$OUT/mdl/_userroles.mdl"
awk -F'|' 'NR>3 && NF>3 { gsub(/ /,"",$2); if ($2!="") print $2 }' "$OUT/captures/show-userroles.txt" | while read -r r; do
  "$MXCLI" -p "$SRC" describe userrole "$r" 2>/dev/null | grep -v 'vibe-coded PoC' >> "$OUT/mdl/_userroles.mdl"
done

phase describe_topo_userroles
# ---- 3. check, then exec into the target (modules in replay order) ---------------------------
# check is all-or-nothing per file, so a statement it rejects is moved to mdl/<M>.deferred.mdl
# (lib/quarantine-mdl.py) and the rest of the module is executed; the deferred statements are retried
# below until no retry makes progress, because most rejections are forward references into a module
# that is created later (cross-module cycles) or into a statement deferred for a syntax error.
status=0
check_exec() {   # check_exec <label> <script.mdl> <deferred.mdl>  — returns 0 when something was executed
  local L="$1" f="$2" d="$3" round moved
  : >> "$d"
  for round in $(seq 1 40); do
    if mx check -p "$TGT" "$f" > "$OUT/captures/check-$L.txt"; then
      if mx exec -p "$TGT" "$f" > "$OUT/captures/exec-$L.txt"; then return 0; fi
      # exec stops at the first statement it cannot write: defer that one, keep going with the rest
      cp "$OUT/captures/exec-$L.txt" "$OUT/captures/exec-$L.round$round.txt"
      moved=$("$PY" -I "$HERE/lib/exec-resume.py" "$f" "$OUT/captures/exec-$L.txt" "$d")
      [ "$moved" -gt 0 ] || { exec_each "$L" "$f" "$d"; return $?; }
      log "exec $L: 1 statement deferred, resuming after it (round $round)"
      [ "$(grep -c '^create\|^grant\|^revoke\|^alter' "$f")" -gt 0 ] || return 0
      continue
    fi
    cp "$OUT/captures/check-$L.txt" "$OUT/captures/check-$L.round$round.txt"
    moved=$("$PY" -I "$HERE/lib/quarantine-mdl.py" "$f" "$OUT/captures/check-$L.txt" "$d")
    [ "$moved" -gt 0 ] || { exec_each "$L" "$f" "$d"; return $?; }
    log "check $L: $moved statement(s) deferred (round $round)"
    [ "$(grep -c '^create\|^grant\|^revoke\|^alter' "$f")" -gt 0 ] || { log "check $L: nothing left to execute"; return 1; }
  done
  log "check $L still failing after $round rounds — see captures/check-$L.txt"; exec_each "$L" "$f" "$d"
}
# exec_each: the error could not be placed on a statement — execute the rest one statement at a time,
# deferring each failure with its verbatim error (GenAI showcase run, 2026-10-12: this used to drop
# 7 whole modules silently)
exec_each() {
  local L="$1" f="$2" d="$3" r
  log "check/exec $L: error not mappable to a statement — executing one statement at a time (captures/exec-each-$L.txt)"
  r=$("$PY" -I "$HERE/lib/exec-each.py" "$MXCLI" "$TGT" "$f" "$d" "$OUT/captures/exec-each-$L.txt")
  log "exec-each $L: ${r% *} landed, ${r#* } deferred"
  [ "${r% *}" -gt 0 ]
}
for M in "${MODULES[@]}"; do
  t0=$(now); : > "$OUT/mdl/$M.deferred.mdl"
  check_exec "$M" "$OUT/mdl/$M.ordered.mdl" "$OUT/mdl/$M.deferred.mdl" || status=1
  tset CHECK "$M" "$(since "$t0")"; tset EXEC "$M" in_check
done
phase check_exec
# retry the deferred statements until a full pass defers everything it tried again
for pass in 1 2 3 4 5 6; do
  progress=0
  for M in "${MODULES[@]}"; do
    d="$OUT/mdl/$M.deferred.mdl"
    [ "$(grep -c '^create\|^grant\|^revoke\|^alter' "$d")" -gt 0 ] || continue
    mv "$d" "$OUT/mdl/$M.retry.mdl"; : > "$d"
    before=$(grep -c '^create\|^grant\|^revoke\|^alter' "$OUT/mdl/$M.retry.mdl")
    # progress = fewer statements deferred, not "check_exec returned 0": on the GenAI showcase nightly run passes
    # 3-6 re-tried the same 758 statements for ~60 min because a clean exec of nothing counted as progress
    check_exec "$M.retry$pass" "$OUT/mdl/$M.retry.mdl" "$d" || true
    after=$(grep -c '^create\|^grant\|^revoke\|^alter' "$d" || true)
    [ "$after" -lt "$before" ] && progress=1
    log "deferred $M: $before tried, $after still deferred (pass $pass)"
  done
  [ "$progress" = 1 ] || break
done
for M in "${MODULES[@]}"; do
  n=$(grep -c '^-- deferred:' "$OUT/mdl/$M.deferred.mdl" || true)
  [ "$n" -gt 0 ] && { log "$M: $n statement(s) never executed — mdl/$M.deferred.mdl"; status=1; }
done
mx exec -p "$TGT" "$OUT/mdl/_settings.mdl"  > "$OUT/captures/exec-_settings.txt"  || status=1
mx exec -p "$TGT" "$OUT/mdl/_userroles.mdl" > "$OUT/captures/exec-_userroles.txt" || status=1

phase deferred_retries_settings
# ---- 4. compare and ledger ---------------------------------------------------------------------
{
  echo "# Fidelity ledger — $(basename "$SRC") -> $(basename "$TGT"), $(mx --version | head -1), $(date +%F)"
  echo "# verdicts: emitted-identical | emitted-drift | failed-exec | not-emitted | target-extra | not-expressible (app-level hand-offs)"
  echo "module	document	type	verdict	evidence"
} > "$OUT/fidelity-ledger.tsv"
for M in "${MODULES[@]}"; do
  t0=$(now); describe_module "$TGT" "$M" "$OUT/mdl/target-$M.mdl"; tset TDESC "$M" "$(since "$t0")"
  "$PY" -I "$HERE/lib/compare-mdl.py" "$OUT/mdl/$M.mdl" "$OUT/mdl/target-$M.mdl" "$M" 2>/dev/null >> "$OUT/fidelity-ledger.tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$M" "$(tget DESC "$M")" "$(tget TOPO "$M")" "$(tget CHECK "$M")" "$(tget EXEC "$M")" "$(tget TDESC "$M")" >> "$TIMES"
done
# app-level rows the model export cannot carry — always hand-off, never silent
printf '(app)\tDemoUsers\tdemouser\tnot-expressible\tdescribe prints Password: '"'"'***'"'"' and exec refuses it — recreate by hand with real passwords (describe demouser <name> for the role/entity)\n' >> "$OUT/fidelity-ledger.tsv"
printf '(app)\tProjectSecurity\tprojectsecurity\tnot-expressible\tdescribe projectsecurity is a report; write `alter app security (SecurityLevel: …)` by hand and drop the blank template'"'"'s user role User + demo users before mx check under Production\n' >> "$OUT/fidelity-ledger.tsv"
printf '(app)\ttheme\ttheme\tnot-expressible\tnot in the model: copy theme/ and themesource/<module>/ by hand\n' >> "$OUT/fidelity-ledger.tsv"
# denominator: describable documents of the own modules in the source tree
"$PY" -I - "$OUT/captures/project-tree.json" "$OUT/fidelity-ledger.tsv" "${MODULES[@]}" <<'PYEOF'
import json,sys
tree=json.load(open(sys.argv[1])); mods=sys.argv[3:]
def walk(n):
    for x in n:
        if x.get('describable') and any(x.get('qualifiedName','').startswith(m+'.') for m in mods): yield x['qualifiedName']
        yield from walk(x.get('children',[]))
cat=set(walk(tree))
rows=[l.split('\t') for l in open(sys.argv[2]) if not l.startswith('#') and not l.startswith('module\t')]
covered={r[1] for r in rows}
missing=sorted(cat-covered)
with open(sys.argv[2],'a') as f:
    for q in missing: f.write('%s\t%s\t?\tnot-emitted\tin source catalog, no describe statement on either side\n'%(q.split('.')[0],q))
    f.write('# denominator: %d describable documents in the source catalog for %s; %d covered by rows, %d listed as not-emitted\n'%(len(cat),','.join(mods),len(cat&covered),len(missing)))
print('catalog=%d covered=%d not-emitted=%d'%(len(cat),len(cat&covered),len(missing)))
PYEOF
phase target_describe_ledger; rm -f "$OUT/captures/.phase-mark"; rm -rf "$TDIR"
log "ledger: $OUT/fidelity-ledger.tsv"
exit $status
