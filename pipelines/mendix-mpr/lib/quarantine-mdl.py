#!/usr/bin/env python3
"""quarantine-mdl.py <script.mdl> <check-output.txt> <deferred.mdl>

Move the statements that `mxcli check` rejected out of <script.mdl> (rewritten in place) and append
them to <deferred.mdl>, so the rest of the module can be executed instead of nothing at all. check is
all-or-nothing per file: one `-- line N:` syntax error or one `statement N:` reference error blocks
every other statement of the module (GenAI showcase app, 2026-10-12: 1 of 36 modules executed; 25 of
the 35 failures were cascades of 10 modules whose java actions mxcli emits with a trailing `,` inside
a `--` comment). Deferred statements are retried by the caller once the modules they reference exist;
what still fails is a ledger row with the verbatim check error, never a silent drop.

Mapping (GenAI showcase app 2026-10-13, E1): `statement N:` reference errors map by number, verified against
the qualified name on the line and re-mapped by name when the numbered statement does not mention it;
`✗ … [CODE]` lint errors map by the document on the following `at Q.N` line, or by the `Q.N` in the
message when that line is empty. check counts statements without the leading `mdl 1;` (verified
against ChatCompletions_ComplexityReduction "statement 6" and GenAICommons "statement 233"). Each
deferred statement carries one `-- deferred:` line with the verbatim error. Prints the number of
statements moved, 0 when the check output names none it can map (the caller then falls back to
lib/exec-each.py, never drops the module).
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdlsplit import split_statements, strip_deferred

src, chk, deferred = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding='utf-8', newline='').read()
stmts, tail = split_statements(text)
if tail.strip(): stmts.append(tail)
report = re.sub(r'\x1b\[[0-9;]*m', '', open(chk, encoding='utf-8', errors='replace').read())   # check colours its output
lines = report.split('\n')

head_re = re.compile(r'^(?:@[^\n]*\n|/\*\*.*?\*/\s*)*create or modify ([a-z][a-z -]*?) ([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', re.M | re.S)
grant_re = re.compile(r'^(?:grant|revoke) .*? on (?:[a-z ]+?) ([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', re.M)
qn_re = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*)\b')
defined, granted = {}, {}
for i, s in enumerate(stmts):
    m = head_re.search(s)
    if m and m.group(1) != 'module': defined.setdefault(m.group(2), []).append(i)
    g = grant_re.search(s)
    if g and not m: granted.setdefault(g.group(1), []).append(i)

# statement index (0-based into stmts) of each 1-based check statement number: check does not count
# the leading `mdl 1;` (GenAICommons: "statement 233" = the 234th split statement, `mdl 1;` first),
# nor a comment-only tail.
numbered = [i for i, s in enumerate(stmts) if s.strip() != 'mdl 1;' and not all(
    l.strip().startswith('--') or not l.strip() for l in s.split('\n'))]
bad, why = set(), {}
def mark(ks, reason):
    for k in ks:
        bad.add(k); why.setdefault(k, reason)
def detail(at):                       # the error line plus its indented `- ...` continuation lines
    out = [lines[at].strip()]
    for l in lines[at + 1:at + 8]:
        if l.strip().startswith('- '): out.append(l.strip())
        else: break
    return ' '.join(out)

for at, l in enumerate(lines):
    # (1) reference errors: `statement N: <kind> 'Q.N' …`. Map by NUMBER, verified against the first
    # qualified name on the line; when the numbered statement does not mention it, map by NAME (the
    # create, or the grant for a grant line) — a wrong number must never quarantine the wrong statement.
    m = re.match(r'^\s*statement (\d+):(.*)$', l)
    if m:
        n, rest = int(m.group(1)) - 1, m.group(2)
        idx = numbered[n] if 0 <= n < len(numbered) else None
        q = next((x for x in qn_re.findall(rest) if x in defined or x in granted), None)
        if idx is not None and (q is None or re.search(r'\b' + re.escape(q) + r'\b', stmts[idx])):
            mark([idx], detail(at))
        elif q:
            is_grant = re.match(r'\s*(grant|revoke)\b', rest)
            mark((granted.get(q) if is_grant else defined.get(q)) or defined.get(q) or granted.get(q, []), detail(at))
        continue
    # (2) lint errors: `✗ <message> [CODE]`, the document on the NEXT line (`at Q.N`) — or, when that
    # line is empty (`at ` with nothing after it), named in the message itself (`✗ snippet Q.N: …`,
    # `✗ layout 'Q.N' …`). GenAI 2026-10-12: 7 modules dropped because neither form mapped (E1a).
    if l.lstrip().startswith('\u2717') and not re.search(r'\d+ (reference |syntax )?error', l):
        nxt = lines[at + 1].strip() if at + 1 < len(lines) else ''
        cands = qn_re.findall(nxt[2:]) if nxt.startswith('at') else []
        q = next((x for x in cands + qn_re.findall(l) if x in defined), None)
        if q: mark(defined[q], l.strip() + ('' if q in l else ' at ' + q))

# syntax errors come as `line N:M` — map the line onto the statement that holds it
if re.search(r'^Syntax errors found', report, re.M):
    starts, line = [], 1
    for s in stmts:
        starts.append(line); line += s.count('\n') + 1
    for at, l in enumerate(lines):
        m = re.match(r'^\s*- line (\d+)', l)
        if not m: continue
        n = int(m.group(1))
        for i in range(len(stmts) - 1, -1, -1):
            if starts[i] <= n: mark([i], 'syntax error: ' + l.strip()); break
# close over the module's own references: a statement that names a document defined by a deferred
# statement would fail the next round anyway (check skips references to objects created within the
# script, so deferring the definition exposes every caller) — MxGenAIConnector took 15 rounds of one
# layer each before this. The callers go to the deferred file too and come back in the same retry.
grown = True
while grown:
    grown = False
    names = {n for n, ks in defined.items() if any(k in bad for k in ks)}
    for n in names:
        pat = re.compile(r'\b' + re.escape(n) + r'\b')
        for i, s in enumerate(stmts):
            if i in bad or s.strip() == 'mdl 1;': continue
            m = head_re.search(s); g = grant_re.search(s.strip())
            if (m and m.group(1) == 'module'): continue
            if pat.search(s) and not (m and m.group(2) == n and m.group(1) in ('entity', 'non-persistent entity')):
                bad.add(i); grown = True; why.setdefault(i, 'same-module closure: names %s, deferred with it' % n)
if not bad:
    print(0); sys.exit(0)
keep = [s for i, s in enumerate(stmts) if i not in bad]
open(src, 'w', encoding='utf-8', newline='').write('\n'.join(keep) + '\n')
with open(deferred, 'a', encoding='utf-8', newline='') as f:
    if os.path.getsize(deferred) == 0: f.write('mdl 1;\n')
    for i in sorted(bad):
        # one `-- deferred:` line per statement, never nested: a retried statement arrives with its
        # previous reason attached, which used to be wrapped again on every pass (E3, 7x overcount)
        s = strip_deferred(stmts[i])
        f.write('-- deferred: check rejected this statement: %s\n%s\n' % (why.get(i, '?')[:400].replace('\n', ' '), s))
print(len(bad))
