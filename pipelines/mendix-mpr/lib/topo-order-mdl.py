#!/usr/bin/env python3
"""Reorder the statements of a `describe module … with all` script so every document is
created before any statement that references it. A unit is one `create or modify <type> <Q.Name>`
statement plus the `grant … on … <Q.Name>` statements that follow it; a unit depends on every
other unit whose qualified name its text mentions. Kahn's sort, stable on the original order;
a cycle (recursion between flows, an entity whose event handler takes the entity) is reported
and its members are left in original order. Usage: topo-order-mdl.py in.mdl out.mdl

Increment 1 ordered microflows only; increment 2 (GenAI showcase app, 48 modules) added nanoflows,
snippets called by pages, JSON structures used by mappings, and names with digits
(`AmazonS3Connector.Step2`), which the first pattern `[A-Za-z_]+` silently skipped."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdlsplit import split_statements
# newline='': annotation text carries CRLF inside string literals; translating it changes the flow and exec refuses the splice
stmts, tail = split_statements(open(sys.argv[1], encoding='utf-8', newline='').read())
QN = r'[A-Za-z0-9_]+\.[A-Za-z0-9_]+'
head_re = re.compile(r'^(?:@[^\n]*\n|/\*\*.*?\*/\s*)*create or modify ([a-z][a-z -]*?) (' + QN + r')\b', re.M | re.S)
grant_re = re.compile(r'^grant .*? on (?:[a-z ]+?) (' + QN + r')\b', re.M)
# a unit = a create statement; a `grant … on <Q.Name>` statement is a unit of its own that depends on
# that document AND on every association of the module its member list names (bare member names:
# `grant read (Name, Credentials_Configuration) on entity M.Credentials` — exec rejects the grant when
# the association does not exist yet: "entity M.Credentials has no member(s) Credentials_Configuration",
# GenAI showcase app EchoConnector 2026-10-12; attaching grants to the entity put them before the association).
units = []
for st in stmts:
    m = head_re.search(st)
    if m and m.group(1) != 'module': units.append((st, m.group(2), None))
    else:
        g = grant_re.search(st.strip())
        units.append((st, None, g.group(1) if g else None))
stmts = [u[0] for u in units]
idx_of = {}                                   # name -> [unit indexes] (a name may carry two documents)
for k, u in enumerate(units):
    if u[1]: idx_of.setdefault(u[1], []).append(k)
# a name carrying two documents (GenAI showcase app: microflow GenAICommons.ConsumedKnowledgeBase_GetCollectionOptions
# wraps a java action of the same name) must create the java/javascript action first — exec resolves
# the call in statement order and a flow created first makes the action "not found", so the flow is refused
LATE = ('microflow', 'nanoflow', 'page', 'snippet', 'layout')
for n, ks in idx_of.items():
    if len(ks) > 1: ks.sort(key=lambda k: (head_re.search(units[k][0]).group(1) in LATE, k))
grant_units = [k for k, u in enumerate(units) if u[2]]
for k in grant_units: idx_of['grant#%d' % k] = [k]
movable = sorted(k for ks in idx_of.values() for k in ks)
pat = {n: re.compile(r'\b' + re.escape(n) + r'\b') for n in idx_of if not n.startswith('grant#')}
deps = {}
for n, ks in idx_of.items():
    body = '\n'.join(stmts[k] for k in ks)
    deps[n] = {o for o in pat if o != n and pat[o].search(body)}
    if n.startswith('grant#'):
        on = units[ks[0]][2]; mod = on.split('.')[0]
        deps[n] |= {on} if on in idx_of else set()
        deps[n] |= {mod + '.' + w for w in re.findall(r'[A-Za-z_][A-Za-z0-9_]*', body) if (mod + '.' + w) in idx_of and (mod + '.' + w) != on}
movable = sorted(k for ks in idx_of.values() for k in ks)
# Kahn, stable on original order. A cycle (mutual recursion; an entity whose access rule names an
# association that names the entity) is broken by forcing the earliest remaining unit in original
# order and carrying on — never by abandoning the order of everything after it (that regressed the
# increment-1 fixture, where one entity/association cycle swallowed all 83 microflows).
order, placed, forced = [], set(), []
remaining = sorted(idx_of, key=lambda n: idx_of[n][0])
while remaining:
    ready = [n for n in remaining if deps[n] <= placed]
    if not ready:
        ready = [remaining[0]]; forced.append(remaining[0])
    for n in ready:
        order.append(n); placed.add(n); remaining.remove(n)
if forced: sys.stderr.write('cycle: forced ahead of an unmet reference: %s\n' % ', '.join(forced))
seq = [k for n in order for k in idx_of[n]]   # unit indexes in the new order
moved = sum(1 for a, b in zip(seq, movable) if a != b)
out = list(stmts)
for slot, k in zip(movable, seq):
    out[slot] = stmts[k]
open(sys.argv[2], 'w', encoding='utf-8', newline='').write('\n'.join(out) + ('\n' + tail if tail.strip() else '\n'))
sys.stderr.write('statements=%d units=%d repositioned=%d\n' % (len(stmts), len(movable), moved))
