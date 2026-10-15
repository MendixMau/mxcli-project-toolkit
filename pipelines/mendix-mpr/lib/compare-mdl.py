#!/usr/bin/env python3
"""Per-document comparison of two `describe module … with all` scripts (source, target).
Statements are grouped per document (a create plus the grant/index statements that
name the same document), keyed by (type, qualified name); order is ignored.
Prints TSV rows: module, document, type, verdict, evidence."""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdlsplit import split_statements
def units(path):
    stmts, _ = split_statements(open(path, encoding='utf-8', newline='').read())
    # any document type (`java action`, `json structure`, `task queue`, …); names may carry digits (AmazonS3Connector.Step2)
    head = re.compile(r'^(?:@[^\n]*\n)*create or modify (?:([a-z][a-z -]*?) ([A-Za-z0-9_]+\.[A-Za-z0-9_]+)|(module) ([A-Za-z0-9_]+));?', re.M)
    grant = re.compile(r'^grant .*? on (?:[a-z ]+?) ([A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b', re.M)
    docs, last = {}, None
    for s in stmts:
        body = re.sub(r'/\*\*.*?\*/\s*', '', s, flags=re.S)   # doc comment compared separately
        doc = re.search(r'/\*\*(.*?)\*/', s, re.S)
        m = head.search(body)
        if m:
            t, name = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
            t = t.replace('non-persistent entity','entity').replace('persistent entity','entity').replace('view entity','entity')
            last = (t, name); docs[last] = {'body': body.strip(), 'doc': (doc.group(1).strip() if doc else ''), 'grants': []}
            continue
        g = grant.search(body)
        if g and last and g.group(1) == last[1]: docs[last]['grants'].append(body.strip()); continue
        if g:
            key = next((k for k in docs if k[1] == g.group(1)), None)
            if key: docs[key]['grants'].append(body.strip()); continue
        sys.stderr.write('unattached statement in %s: %s\n' % (path, body.strip()[:80]))
    return docs
src, tgt = units(sys.argv[1]), units(sys.argv[2])
module = sys.argv[3]
def firstdiff(a, b):
    al, bl = a.split('\n'), b.split('\n')
    for i, (x, y) in enumerate(zip(al, bl)):
        if x != y: return 'line %d: %r -> %r' % (i+1, x.strip()[:70], y.strip()[:70])
    return 'length %d -> %d lines' % (len(al), len(bl))
for k in sorted(src, key=lambda k: (k[0], k[1])):
    t, name = k
    if k not in tgt:
        print('\t'.join([module, name, t, 'failed-exec', 'absent from target describe'])); continue
    s, g = src[k], tgt[k]
    ev = []
    if s['body'] != g['body']: ev.append('body: ' + firstdiff(s['body'], g['body']))
    if sorted(s['grants']) != sorted(g['grants']): ev.append('grants: %d -> %d' % (len(s['grants']), len(g['grants'])))
    if s['doc'] != g['doc']: ev.append('documentation: ' + firstdiff(s['doc'], g['doc']))
    # describe marks a widget it cannot author with `-- … NOT re-executable`; the document lands without it
    nre = re.findall(r'-- (\S+ \(\S+\))  -- NOT re-executable', s['body'])
    if nre: print('\t'.join([module, name, t, 'not-expressible', 'describe marks %d widget(s) NOT re-executable: %s%s' % (len(nre), ', '.join(nre[:3]), '; ' + '; '.join(ev) if ev else '')])); continue
    # a flow whose branches cross: describe says the text is NOT equivalent and must not be re-executed (mxcli #923)
    neq = re.search(r'-- WARNING: (the decision at \([^)]*\)[^\n]*?)\. This description is NOT equivalent', s['body'])
    if neq: print('\t'.join([module, name, t, 'not-expressible', 'describe: %s — NOT equivalent, must not be re-executed (mxcli #923)%s' % (neq.group(1), '; ' + '; '.join(ev) if ev else '')])); continue
    print('\t'.join([module, name, t, 'emitted-drift' if ev else 'emitted-identical', '; '.join(ev) if ev else 'describe on target identical (body, grants, documentation)']))
for k in sorted(set(tgt) - set(src)):
    print('\t'.join([module, k[1], k[0], 'target-extra', 'present in target only (not in source describe)']))
