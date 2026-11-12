#!/usr/bin/env python3
"""layoutdiff.py: compare the layout of the old and the new app per page, widget by widget (the .geo.json files that
geometry.js writes next to each screenshot), so a page that shows the same data in a broken layout cannot PASS.

Why: LineApp 10.24.13 -> 11.12.6 React. Every journey PASSed and the gate said 0 regressions, while the Task List
gallery rendered at half the page width and converted Image widgets grew to the width of their container. shotdiff.py
had the old and new journey shots, but 139 of 278 pairs were REVIEW (dates, data, dialogs) and the rung only read the
smoke shots. Widget widths do not depend on the data, so they can be compared strictly.

  layoutdiff.py OLD NEW [--accept accept.txt] [--md out.md] [--json out.json]

OLD and NEW are folders; *.geo.json files pair by relative path (a trailing -NOT-REACHED, -STUCK, -LOADING or
-ACTION-FAILED is not part of the name). Per pair:
  WIDTH   a named widget that is at least 40 px wide on the old app changed width by more than 24 px and 20%. Only the
          outermost changed widgets are listed (a child of a changed widget changes with it).
  CUT     a text that fits on the old app is cut off on the new app (same widget chain and text).
  IMAGE   an image (same widget chain and file) covers more than 3 times the area it had, and is wider than 48 px.
  FAIL    any of the three; PASS* when every finding matches an accept line; PASS when there is none.
  MISSING the old run saved the page and the new run did not (counts as a failure).
  INVALID the viewports differ, or a side has no widgets (not a page). Widgets only on one side are counted, not judged
          (data and dialogs differ between runs).
Accept file: one 'relative/path/pattern # what you saw' per line (fnmatch on the pair name), the reason is required.
Exit: 0 every page PASS or PASS*, 1 any FAIL or MISSING, 3 no FAIL but a page is INVALID (not judged, never a pass),
2 usage or nothing paired.
"""
import argparse, fnmatch, json, os, re, sys

SUFFIX = re.compile(r'-(NOT-REACHED|STUCK|LOADING|ACTION-FAILED)(?=\.geo\.json$)')

def collect(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            if f.endswith('.geo.json'):
                p = os.path.join(d, f); out[SUFFIX.sub('', os.path.relpath(p, root))] = p
    return out

def outermost(keys):
    ks = sorted(keys, key=lambda k: k.count('/'))
    keep = []
    for k in ks:
        base = k.split('#')[0]
        if not any(base.startswith(o.split('#')[0] + '/') for o in keep): keep.append(k)
    return keep

def align(old, new):
    # The client can add or drop a named wrapper anywhere in the chain: React names the main scroll container
    # layoutContainer and page scroll containers scrollContainer1, Dojo did not. Without this almost no key pairs and the
    # page PASSes blind. A name that appears in no key of the other side is such a wrapper: drop it from this side's keys.
    def names(d): return {seg for part in ('widgets', 'cuts', 'images') for x in d.get(part, []) for seg in x['key'].split('#')[0].split('/')}
    no, nn = names(old), names(new)
    def rekey(d, other):
        dropped = set()
        def k(key):
            base, _, idx = key.partition('#')
            keep = [seg for seg in base.split('/') if seg in other or dropped.add(seg)]
            return '/'.join(keep) + ('#' + idx if idx else '') if keep else None
        out = dict(d)
        for part in ('widgets', 'cuts', 'images'):
            seen, rows = set(), []
            for x in d.get(part, []):
                key = k(x['key'])
                if not key or (part == 'widgets' and key in seen): continue   # a dropped wrapper itself, or a merged twin
                seen.add(key); rows.append(dict(x, key=key))
            out[part] = rows
        return out, sorted(dropped)
    o, do = rekey(old, nn); n, dn = rekey(new, no)
    return o, n, {'dropped old': do[:6], 'dropped new': dn[:6]}

def judge(old, new):
    if old['viewport'] != new['viewport']: return 'INVALID', [f"viewport {old['viewport']} -> {new['viewport']}"], {}
    if not old['widgets'] or not new['widgets']: return 'INVALID', ['no widgets on one side'], {}
    old, new, wrap = align(old, new)
    ow = {w['key']: w for w in old['widgets']}; nw = {w['key']: w for w in new['widgets']}
    changed = [k for k in ow if k in nw and ow[k]['w'] >= 40 and abs(nw[k]['w'] - ow[k]['w']) > max(24, 0.2 * ow[k]['w'])]
    finds = [f"WIDTH {k}: {ow[k]['w']} -> {nw[k]['w']} px" for k in outermost(changed)]
    oc = {(c['key'], c['text']) for c in old['cuts']}
    finds += [f"CUT {c['key']}: \"{c['text']}\"" for c in new['cuts'] if (c['key'], c['text']) not in oc]
    oi = {}
    for i in old['images']: oi.setdefault((i['key'], i['src']), i)
    for i in new['images']:
        o = oi.get((i['key'], i['src']))
        if o and i['w'] > 48 and i['w'] * i['h'] > 3 * max(1, o['w'] * o['h']):
            finds.append(f"IMAGE {i['key']} {i['src']}: {o['w']}x{o['h']} -> {i['w']}x{i['h']}")
    counts = {'widgets old': len(ow), 'widgets new': len(nw), 'only old': len(set(ow) - set(nw)), 'only new': len(set(nw) - set(ow)),
              'wrapper': wrap}
    return ('FAIL' if finds else 'PASS'), finds, counts

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0]); ap.add_argument('old'); ap.add_argument('new')
    ap.add_argument('--accept'); ap.add_argument('--md'); ap.add_argument('--json')
    a = ap.parse_args()
    acc = []
    if a.accept and os.path.exists(a.accept):
        for l in open(a.accept):
            l = l.strip()
            if not l or l.startswith('#'): continue
            if '#' not in l: sys.exit(f'accept line without a reason: {l}')
            acc.append([x.strip() for x in l.split('#', 1)])
    O, N = collect(a.old), collect(a.new)
    pairs = sorted(set(O) & set(N))
    if not pairs: print('layout: nothing paired'); return 2
    # a page the old run reached but the new run did not save at all is a failure, not a page to skip
    rows = [{'pair': p, 'verdict': 'MISSING', 'findings': ['no new layout for this page'], 'counts': {}} for p in sorted(set(O) - set(N))]
    for p in pairs:
        v, finds, counts = judge(json.load(open(O[p])), json.load(open(N[p])))
        if v == 'FAIL':
            why = [r for pat, r in acc if fnmatch.fnmatch(p, pat)]
            if why: v, finds = 'PASS*', finds + [f'accepted: {why[0]}']
        rows.append({'pair': p, 'verdict': v, 'findings': finds, 'counts': counts})
    tally = {k: sum(r['verdict'] == k for r in rows) for k in ('FAIL', 'MISSING', 'INVALID', 'PASS*', 'PASS')}
    line = (f"layout: {len(rows)} pages, {tally['PASS']} PASS, {tally['PASS*']} PASS*, {tally['FAIL']} FAIL, "
            f"{tally['MISSING']} MISSING, {tally['INVALID']} INVALID")
    md = [f'# layoutdiff {os.path.abspath(a.old)} -> {os.path.abspath(a.new)}', '', line, '']
    for r in sorted(rows, key=lambda r: ['FAIL', 'MISSING', 'INVALID', 'PASS*', 'PASS'].index(r['verdict'])):
        md.append(f"{r['verdict']:8}{r['pair']}" + (f"  ({r['counts']['only old']} widgets only old, {r['counts']['only new']} only new)" if r['counts'] else ''))
        md += [f'          {f}' for f in r['findings'][:12]] + ([f"          ... {len(r['findings']) - 12} more"] if len(r['findings']) > 12 else [])
    if a.md: open(a.md, 'w').write('\n'.join(md) + '\n')
    if a.json: json.dump({'summary': line, 'pairs': rows}, open(a.json, 'w'), indent=1)
    print('\n'.join(md[2:]) if not a.md else line)
    if tally['FAIL'] or tally['MISSING']: return 1
    return 3 if tally['INVALID'] else 0

if __name__ == '__main__': sys.exit(main())
