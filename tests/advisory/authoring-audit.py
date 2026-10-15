#!/usr/bin/env python3
"""authoring-audit.py -- maintainer-side, ADVISORY authoring audit. Never ships to projects.

  dupes    near-duplicate rules across skills/, agents/, CLAUDE.md and README "Baseline routing"
           (sparse TF-IDF cosine on 1-2-grams). Each hit is a rule stated twice: pick the canonical
           home and make the other a pointer, or allowlist it in dupes-allow.tsv with a reason.
  routing  BM25 over the trigger text (column 3) of bin/lib/skill-routing.tsv, scored against the
           labelled phrasings in routing-phrasings.tsv -- CLAUDE.md "Adding new skills", rule 8.

Python 3 standard library only. Exit 0 always, except `routing --strict` (a must_hit phrasing missed
its top 3). Calibration on master 484e7ff: dupes top 40 held 19 true duplicates (82.5% not false
positives, 69 hand-judged pairs); routing top-3 46/55.

Usage: authoring-audit.py dupes   [--root DIR] [--top N]
       authoring-audit.py routing [--root DIR] [--phrasings FILE] [--strict]
"""
import argparse, fnmatch, glob, math, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
# sklearn's English list is not available without sklearn; this covers the high-df function words.
STOP = set("""a about above after again against all also am an and any are as at be because been
before being below between both but by can could did do does doing down during each else few for
from further had has have having he her here hers him his how i if in into is it its itself just
me more most my no nor not now of off on once only or other our ours out over own same she should
so some such than that the their them then there these they this those through to too under until
up very was we were what when where which while who whom why will with would you your yours""".split())

# ---------------------------------------------------------------- chunking
LIST_RE = re.compile(r'^\s*([-*+]|\d+[.)])\s+')
def chunks_of(lines, lo=0, hi=None):
    """Rule-sized chunks: one per table row, one per bullet (with its indented continuation), and
    paragraphs capped at ~120 words. Code fences, headings and ROUTING:BEGIN/END blocks skipped."""
    out, para, pstart = [], [], None
    hi = len(lines) if hi is None else hi
    i, incode, inroute = lo, False, False
    def flush():
        nonlocal para, pstart
        if para: out.append((pstart, ' '.join(para)))
        para, pstart = [], None
    while i < hi:
        raw = lines[i].rstrip('\n'); s = raw.strip()
        if 'ROUTING:BEGIN' in s: inroute = True
        if 'ROUTING:END' in s: inroute = False; i += 1; continue
        if inroute: i += 1; continue
        if s.startswith('```'): flush(); incode = not incode; i += 1; continue
        if incode: i += 1; continue
        if not s or s.startswith('#'): flush(); i += 1; continue
        if s.startswith('|'):
            flush()
            if not re.fullmatch(r'\|[\s:\-|]+\|?', s): out.append((i + 1, s))
            i += 1; continue
        if LIST_RE.match(raw):
            flush(); buf, start = [s], i + 1; i += 1
            while (i < hi and lines[i].strip() and lines[i].startswith('  ')
                   and not re.match(r'^\s*([-*+]|\d+[.)]|\||#|```)', lines[i])):
                buf.append(lines[i].strip()); i += 1
            out.append((start, ' '.join(buf))); continue
        if pstart is None: pstart = i + 1
        para.append(s.lstrip('> ').strip()); i += 1
        if len(' '.join(para).split()) > 120: flush()
    flush()
    return out

def corpus(root):
    files = sorted(glob.glob(os.path.join(root, 'skills', '**', '*.md'), recursive=True))
    files += sorted(glob.glob(os.path.join(root, 'agents', '*.md'))) + [os.path.join(root, 'CLAUDE.md')]
    out = []
    def add(rel, lines, lo=0, hi=None):
        for ln, t in chunks_of(lines, lo, hi):
            if len(re.findall(r'\w+', t)) >= 10: out.append((rel, ln, t))
    for f in files:
        if os.path.isfile(f):
            with open(f, encoding='utf-8') as fh: add(os.path.relpath(f, root).replace(os.sep, '/'), fh.readlines())
    with open(os.path.join(root, 'README.md'), encoding='utf-8') as fh: L = fh.readlines()
    st = next((i for i, l in enumerate(L) if l.startswith('#### Baseline routing')), None)
    if st is not None:
        en = next((i for i in range(st + 1, len(L)) if re.match(r'^#{2,4} ', L[i])), len(L))
        add('README.md', L, st + 1, en)
    return out

# ---------------------------------------------------------------- dupes
def tfidf(texts):
    """Sparse, L2-normalised TF-IDF over 1-2-grams (sublinear tf, smoothed idf). Returns dicts."""
    grams = []
    for t in texts:
        w = [x for x in re.findall(r'\b\w\w+\b', re.sub(r'[`*_|>]', ' ', t).lower()) if x not in STOP]
        grams.append(Counter(w + [a + ' ' + b for a, b in zip(w, w[1:])]))
    df = Counter(g for c in grams for g in c)
    n = len(texts); vecs = []
    for c in grams:
        v = {g: (1 + math.log(tf)) * (math.log((1 + n) / (1 + df[g])) + 1) for g, tf in c.items()}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        vecs.append({g: x / norm for g, x in v.items()})
    return vecs

def load_allow(path):
    rows = []
    if os.path.isfile(path):
        for l in open(path, encoding='utf-8'):
            if l.strip() and not l.startswith('#'):
                p = l.rstrip('\n').split('\t')
                if len(p) >= 3: rows.append((p[0], p[1], p[2].lower()))
    return rows

def allowed(allow, fa, fb, ta, tb):
    for ga, gb, m in allow:
        if ((fnmatch.fnmatch(fa, ga) and fnmatch.fnmatch(fb, gb)) or
                (fnmatch.fnmatch(fa, gb) and fnmatch.fnmatch(fb, ga))):
            if m == '*' or m in ta.lower() or m in tb.lower(): return True
    return False

def cmd_dupes(a):
    t0 = time.time()
    C = corpus(a.root); V = tfidf([t for _, _, t in C])
    isag = [f.startswith('agents/') for f, _, _ in C]
    post = defaultdict(list)                       # inverted index -> sparse dot products
    for i, v in enumerate(V):
        for g, x in v.items(): post[g].append((i, x))
    cand = []
    for i, v in enumerate(V):
        acc = defaultdict(float)
        for g, x in v.items():
            for j, y in post[g]:
                if j > i: acc[j] += x * y
        best = sorted(((s, j) for j, s in acc.items()
                       if C[j][0] != C[i][0] and not (isag[i] and isag[j])), reverse=True)[:5]
        cand += [(s, i, j) for s, j in best if s > 0]
    cand.sort(key=lambda c: (-c[0], c[1], c[2]))
    allow = load_allow(os.path.join(HERE, 'dupes-allow.tsv'))
    per, shown, skipped = Counter(), 0, 0
    print(f'dupes: {len(C)} chunks from {len({f for f, _, _ in C})} files; top {a.top} cross-file pairs '
          f'(max 3 per file pair), allowlist {len(allow)} rows')
    for s, i, j in cand:
        (fa, la, ta), (fb, lb, tb) = C[i], C[j]
        key = tuple(sorted((fa, fb)))
        if allowed(allow, fa, fb, ta, tb): skipped += 1; continue   # before the cap: never spends it
        if per[key] >= 3: continue
        per[key] += 1
        shown += 1
        print(f'{shown:3d}  {s:.3f}  {fa}:{la}  <>  {fb}:{lb}\n       A: {ta[:110]}\n       B: {tb[:110]}')
        if shown >= a.top: break
    print(f'dupes: {shown} shown, {skipped} allowlisted, {time.time() - t0:.1f}s')
    return 0

# ---------------------------------------------------------------- routing
def stem(w):
    for s in ('ing', 'ed', 'es', 's'):
        if len(w) > 4 and w.endswith(s): return w[:-len(s)]
    return w
QSTOP = set('a an the of to and or in on for is it be at by as this that with i my me we our you '
            'your its are was can do if not no'.split())
def tok(t): return [stem(w) for w in re.findall(r'[a-z0-9]+', t.lower()) if w not in QSTOP]

class BM25:                                        # Okapi, k1=1.5 b=0.75, idf floor eps*mean
    def __init__(self, docs, k1=1.5, b=0.75, eps=0.25):
        self.tf = [Counter(d) for d in docs]; self.dl = [len(d) for d in docs]
        self.avg = sum(self.dl) / len(docs); self.k1, self.b = k1, b
        df = Counter(w for d in docs for w in set(d)); n = len(docs)
        self.idf = {w: math.log(n - c + 0.5) - math.log(c + 0.5) for w, c in df.items()}
        floor = eps * sum(self.idf.values()) / len(self.idf)
        self.idf = {w: (x if x >= 0 else floor) for w, x in self.idf.items()}
    def scores(self, q):
        out = []
        for tf, dl in zip(self.tf, self.dl):
            s = 0.0
            for w in q:
                f = tf.get(w, 0)
                if f: s += self.idf[w] * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * dl / self.avg))
            out.append(s)
        return out

def cmd_routing(a):
    t0 = time.time()
    rows = [l.rstrip('\n').split('\t') for l in open(os.path.join(a.root, 'bin/lib/skill-routing.tsv'), encoding='utf-8')
            if l.strip() and not l.startswith('#')]
    paths = [r[1] for r in rows]; bm = BM25([tok(r[2]) for r in rows])
    qs = [l.rstrip('\n').split('\t') for l in open(a.phrasings, encoding='utf-8') if l.strip() and not l.startswith('#')]
    top1 = top3 = 0; misses = []; strict_fail = []
    for q in qs:
        phr, exp = q[0], q[1]
        ok = {exp} | {x for x in (q[2] if len(q) > 2 else '').split(',') if x and x != '-'}
        s = bm.scores(tok(phr))
        order = [paths[i] for i in sorted(range(len(s)), key=lambda i: (-s[i], i))[:3]]
        rank = min([order.index(p) + 1 for p in ok if p in order], default=99)
        top1 += rank == 1; top3 += rank <= 3
        if rank > 3:
            must = len(q) > 3 and q[3].strip() == 'must_hit'
            misses.append((phr, exp, order, must)); strict_fail += [phr] if must else []
    n = len(qs)
    print(f'routing: {len(rows)} rows, {n} phrasings: top-1 {top1}/{n}  top-3 {top3}/{n}  ({time.time() - t0:.1f}s)')
    for phr, exp, order, must in misses:
        print(f'  MISS{" (must_hit)" if must else ""}: "{phr}"\n        want {exp}; got {", ".join(order)}')
    return 1 if (a.strict and strict_fail) else 0

def main():
    p = argparse.ArgumentParser(description='Advisory authoring audit (maintainer-side; never ships).')
    p.add_argument('--root', default=os.path.abspath(os.path.join(HERE, '..', '..')))
    sp = p.add_subparsers(dest='cmd', required=True)
    d = sp.add_parser('dupes'); d.add_argument('--top', type=int, default=40)
    r = sp.add_parser('routing'); r.add_argument('--strict', action='store_true')
    r.add_argument('--phrasings', default=os.path.join(HERE, 'routing-phrasings.tsv'))
    a = p.parse_args()
    sys.exit(cmd_dupes(a) if a.cmd == 'dupes' else cmd_routing(a))

if __name__ == '__main__':
    main()
