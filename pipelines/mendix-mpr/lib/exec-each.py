#!/usr/bin/env python3
"""exec-each.py <mxcli> <target.mpr> <script.mdl> <deferred.mdl> <capture.txt>

Last resort of rehost-extract.sh's check_exec, for a script that `mxcli check` rejects in a way
lib/quarantine-mdl.py cannot map onto a statement, or whose exec error lib/exec-resume.py cannot place.
Executes the script ONE STATEMENT AT A TIME (each through `mxcli exec`, which runs check first), in
order: a statement that lands is in the target; one that fails is appended to <deferred.mdl> with
its verbatim error and retried by the caller's deferred passes. <script.mdl> is emptied (to
`mdl 1;`) — every statement has either landed or reached the deferred file, so nothing is dropped.

GenAI showcase app 2026-10-12 (field run defect E2): when quarantine mapped nothing, check_exec returned 1 and
left the remainder in <M>.ordered.mdl, never retried — 7 modules, 1040 statements, 1520 ledger rows
silently lost. Slow by design (one mxcli process per statement, ~1-2 s each); it runs only when the
mapping fails. Prints "<landed> <deferred>".
"""
import os, re, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdlsplit import split_statements, strip_deferred

mxcli, tgt, src, deferred, cap = sys.argv[1:6]
stmts, tail = split_statements(open(src, encoding='utf-8', newline='').read())
if tail.strip(): stmts.append(tail)
body = [strip_deferred(s) for s in stmts if s.strip() != 'mdl 1;']
body = [s for s in body if re.search(r'^(create|grant|revoke|alter|drop|delete)\b', s, re.M)]
landed = failed = 0
fd, one = tempfile.mkstemp(suffix='.mdl'); os.close(fd)
with open(cap, 'w', encoding='utf-8') as log, open(deferred, 'a', encoding='utf-8', newline='') as d:
    if os.path.getsize(deferred) == 0: d.write('mdl 1;\n')
    for s in body:
        open(one, 'w', encoding='utf-8', newline='').write('mdl 1;\n' + s + '\n')
        r = subprocess.run([mxcli, 'exec', '-p', tgt, one], capture_output=True, text=True, errors='replace')
        out = '\n'.join(l for l in (r.stdout + r.stderr).split('\n') if 'vibe-coded PoC' not in l)
        head = s.strip().split('\n')[0][:120]
        if r.returncode == 0:
            landed += 1; log.write('OK   %s\n' % head); continue
        failed += 1
        plain = re.sub(r'\x1b\[[0-9;]*m', '', out)
        err = [l.strip() for l in plain.split('\n') if re.match(r'\s*(Error:|statement \d+:|- |✗|.*error)', l)]
        reason = ' '.join(err)[:400] or plain.strip().split('\n')[-1][:400]
        log.write('FAIL %s\n%s\n' % (head, plain))
        d.write('-- deferred: exec (one statement at a time) refused this statement: %s\n%s\n' % (reason, s))
os.unlink(one)
open(src, 'w', encoding='utf-8', newline='').write('mdl 1;\n')
print(landed, failed)
