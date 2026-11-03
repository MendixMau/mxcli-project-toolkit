#!/usr/bin/env python3
"""exec-resume.py <script.mdl> <exec-output.txt> <deferred.mdl>

`mxcli exec` stops at the first statement it cannot write; everything before it is in the target,
everything after it is not. Find the statement the `Error:` line names (its qualified name, or the
bare document name mxcli prints as `/<Name>.ObjectCollection` for a flow), move it to <deferred.mdl>
with the verbatim error, and rewrite <script.mdl> to the statements AFTER it, so the caller can carry
on instead of losing the rest of the module. Prints 1 when it could do that, 0 when the error names
no statement it can find (the caller then reports the module as failed).

GenAI showcase app 2026-10-12: `Error: export mapping GenAICommons.EM_Reference: message definition
"GenAICommons.MD_Reference.Reference" not found — this project has no message definitions` (0.26.0 has
no message-definition document at all) would otherwise have cost GenAICommons its 170 remaining statements.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdlsplit import split_statements, strip_deferred

src, out, deferred = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding='utf-8', newline='').read()
stmts, tail = split_statements(text)
if tail.strip(): stmts.append(tail)
report = open(out, encoding='utf-8', errors='replace').read()
err = next((l for l in report.split('\n') if l.startswith('Error:')), '')
if not err: print(0); sys.exit(0)
head_re = re.compile(r'^(?:@[^\n]*\n|/\*\*.*?\*/\s*)*create or modify ([a-z][a-z -]*?) ([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', re.M | re.S)
grant_re = re.compile(r'^grant .*? on (?:[a-z ]+?) ([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', re.M)
qns = set(re.findall(r'\b([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', err))
bare = set(re.findall(r'/([A-Za-z0-9_]+)\.ObjectCollection', err))
hit = None
for i, s in enumerate(stmts):
    m = head_re.search(s); g = grant_re.search(s.strip())
    name = m.group(2) if m and m.group(1) != 'module' else (g.group(1) if g else None)
    if not name: continue
    if name in qns or name.split('.')[1] in bare:
        if g and not m and not err.startswith('Error: failed to grant') and 'grant' not in err: continue
        hit = i; break
if hit is None: print(0); sys.exit(0)
# The statement that NAMES the document is not always the one that failed. `Error: microflow not found:
# X` + `hint: X is defined later in this script` comes from an EARLIER statement that references X
# (GenAI 2026-10-13: entity ExampleMicroflows.Ticket with `on before commit call …BCo_Ticket`); deferring
# X's definition and resuming after it silently dropped every statement between the two (E5: 5
# documents). So: on a forward-reference error, defer the first statement that mentions X without
# defining it; and resume from the earliest statement that mentions any name in the error, not after
# the deferred one — `create or modify` re-runs of statements that already landed are idempotent.
fwd = re.search(r'\b([A-Za-z0-9_]+\.[A-Za-z0-9_]+) is defined later in this script|references [a-z ]+? ([A-Za-z0-9_]+\.[A-Za-z0-9_]+) before it is created', report)
names = qns | {q for q in re.findall(r'\b([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', report) if fwd and q == (fwd.group(1) or fwd.group(2))}
def mentions(s, q): return re.search(r'\b' + re.escape(q) + r'\b', s)
lo = min([i for i, s in enumerate(stmts) if any(mentions(s, q) for q in names) or
          any(re.search(r'/' + re.escape(b) + r'\b', s) for b in bare)] + [hit])
if fwd:
    x = fwd.group(1) or fwd.group(2)
    for i in range(lo, len(stmts)):
        m = head_re.search(stmts[i])
        if mentions(stmts[i], x) and not (m and m.group(2) == x): hit = i; break
with open(deferred, 'a', encoding='utf-8', newline='') as f:
    if os.path.getsize(deferred) == 0: f.write('mdl 1;\n')
    f.write('-- deferred: exec refused this statement: %s\n%s\n' % (err[:400].replace('\n', ' '), strip_deferred(stmts[hit])))
rest = [s for i, s in enumerate(stmts) if i >= lo and i != hit]
open(src, 'w', encoding='utf-8', newline='').write('mdl 1;\n' + '\n'.join(s for s in rest if s.strip() != 'mdl 1;') + '\n')
print(1)
