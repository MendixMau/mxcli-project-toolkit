#!/usr/bin/env python3
"""score.py — score a toolkit project (after Stages 0-2 on the synthetic corpus) against answer-key.json.

    score.py <project-dir> --key answer-key.json [--json] [--toolkit DIR] [--brd-dir DIR]
                           [--manifest MANIFEST.json] [--include-analysis] [--no-run]
    score.py --self-test [--key answer-key.json] [--keep]

What it reads (the toolkit's own conventions, nothing invented):
  * BRDs — `*.brd.json` under any of <project>/analysis/*/knowledge-base/brd,
    <project>/analysis/knowledge-base/brd, <project>/knowledge-base/brd (bin/lib/discover-brds.sh),
    or --brd-dir.
  * PROJECT.md — the decision register: Decisions and Open questions tables, "## Current stage".
  * analysis/sme-questions.md, analysis/triage.md.
  * bin/source-ledger.sh check --json, when the toolkit can be found (--toolkit, $MXTK_TOOLKIT,
    the "Toolkit root" row of CLAUDE.local.md, this file's grandparent, ~/Mendix/mxcli-project-toolkit).
  * bin/gate-check.sh <project> 1 and 2 (same discovery), plus docs/BUILD-LOG.md and .claude/ receipts.

Metrics: requirement recall/precision (fuzzy: stemmed keyword overlap >= 0.6 of the key statement's
tokens, or an explicit id cite such as "R012", or a page-file cite with overlap >= 0.5; negation-aware), entity and
attribute recall, association recall, business-rule recall (a rule counts only when its
`must_contain` thresholds/states are present), contradictions surfaced as questions/decisions (0-3),
screenshot-only requirements found (0-2), phantom claims, ledger verdict counts, gate status.

Python 3 standard library only.
"""
import argparse
import glob
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------------------------
# text normalisation
# ----------------------------------------------------------------------------------------
STOP = set("""a an the and or of to in on at for by with from as is are be been being was were it its this that these those
there their they them then than which who whom whose what when where while into onto over under up down out off
do does did done can could may might must shall should will would has have had having also any all each per via
so such if else about after before during until whenever whether one's own same other another more most very
i you he she we us our your his her""".split())
NEG = {'not', 'no', 'never', 'cannot', 'only', 'without'}
STOP -= NEG
NUMWORDS = {'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5', 'six': '6', 'seven': '7',
            'eight': '8', 'nine': '9', 'ten': '10', 'eleven': '11', 'twelve': '12', 'twenty': '20', 'thirty': '30',
            'fifty': '50', 'ninety': '90', 'hundred': '100'}
SUFFIXES = ['ations', 'ation', 'ising', 'izing', 'ness', 'ments', 'ment', 'ings', 'ing', 'ions', 'ion', 'ies', 'ied',
            'ers', 'er', 'ed', 'es', 'al', 'ly', 's', 'e']
TOKEN_RE = re.compile(r'\d+(?:\.\d+)?|[a-z]+')
SYNONYMS = {'draft': 'draught', 'auto': 'automatic', 'harbourmaster': 'harbour', 'e': 'email'}


def stem(w):
    if w in NUMWORDS:
        return NUMWORDS[w]
    if w[0].isdigit():
        return w
    w = SYNONYMS.get(w, w)
    for suf in SUFFIXES:
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            if suf == 's' and (w.endswith('ss') or w.endswith('us')):
                break
            w = w[:-len(suf)]
            break
    if len(w) >= 4 and w[-1] == w[-2] and w[-1] not in 'aeiou':
        w = w[:-1]
    return w


def tokens(text):
    out = set()
    for t in TOKEN_RE.findall(text.lower()):
        if t in STOP or (len(t) == 1 and not t.isdigit()):
            continue
        out.add(stem(t))
    return out


NEG_MARKERS = NEG | {'manual', 'manually'}


def overlap(key_tokens, cand_tokens):
    """Share of the key statement's tokens present in the candidate. Negation-aware: a key statement
    that carries a negation (no / not / never / cannot / only / without) is capped below the match
    threshold unless the candidate carries one too (or says 'manual') — otherwise 'there is NO automatic
    approval' matches its positive near-twin 'officers review every request'."""
    if not key_tokens:
        return 0.0
    ov = len(key_tokens & cand_tokens) / len(key_tokens)
    if (key_tokens & NEG_MARKERS) and not (cand_tokens & NEG_MARKERS):
        ov = min(ov, 0.59)
    return ov


def has_must(text, must_contain):
    """Every group present; a group is 'a|b' alternatives; numbers must be whole tokens."""
    low = ' ' + re.sub(r'[^a-z0-9.%]+', ' ', text.lower()) + ' '
    for group in must_contain or []:
        ok = False
        for alt in group.split('|'):
            alt = alt.strip().lower()
            if not alt:
                continue
            if alt[0].isdigit():
                if re.search(r'(?<![0-9.])' + re.escape(alt) + r'(?![0-9])', low):
                    ok = True; break
            elif alt in low:
                ok = True; break
        if not ok:
            return False
    return True


# ----------------------------------------------------------------------------------------
# harvesting the project
# ----------------------------------------------------------------------------------------
CLAIM_KEYS = {'requirements', 'functionalrequirements', 'businessrules', 'rules', 'validations', 'hiddenrules',
              'nonfunctionalrequirements', 'constraints', 'acceptancecriteria'}
TEXT_FIELDS = ('text', 'statement', 'description', 'rule', 'requirement', 'title', 'name', 'question', 'summary', 'purpose')
CITE_FIELDS = ('source', 'sources', 'sourceref', 'sourcerefs', 'section', 'sections', 'page', 'pages', 'heading', 'ref',
               'refs', 'reference', 'references', 'sourcekb', 'evidence', 'origin', 'citation', 'id', 'sourceid')


def discover_brds(project, brd_dir=None):
    if brd_dir:
        return sorted(glob.glob(os.path.join(brd_dir, '*.brd.json')))
    out = []
    for pat in ('analysis/*/knowledge-base/brd', 'analysis/knowledge-base/brd', 'knowledge-base/brd'):
        for d in sorted(glob.glob(os.path.join(project, pat))):
            out += sorted(glob.glob(os.path.join(d, '*.brd.json')))
    return out


class Statement:
    __slots__ = ('text', 'cite', 'file', 'path', 'kind', 'toks')

    def __init__(self, text, cite, file, path, kind):
        self.text = text; self.cite = cite; self.file = file; self.path = path; self.kind = kind
        self.toks = tokens(text)

    def where(self):
        return '%s:%s' % (os.path.basename(self.file), self.path)


def _obj_text(o):
    if isinstance(o, str):
        return o, ''
    if isinstance(o, dict):
        parts = [str(o[k]) for k in TEXT_FIELDS if k in o and isinstance(o[k], (str, int, float))]
        cite = ' '.join(str(o[k]) for k in o if k.lower() in CITE_FIELDS and isinstance(o[k], (str, int, float, list)))
        return ' '.join(parts), cite
    return '', ''


def harvest_brd(path):
    with open(path, encoding='utf-8') as f:
        doc = json.load(f)
    stmts = []

    def walk(node, jpath, under_claim, parent_cite):
        if isinstance(node, dict):
            cite = ' '.join(str(node[k]) for k in node if k.lower() in CITE_FIELDS and isinstance(node[k], (str, int, float, list)))
            cite = (parent_cite + ' ' + cite).strip()
            for k, v in node.items():
                kl = k.lower()
                claim_here = under_claim or kl in CLAIM_KEYS
                if isinstance(v, str):
                    if len(v.strip()) < 8:
                        continue
                    kind = 'claim' if (kl in CLAIM_KEYS or (under_claim and kl in TEXT_FIELDS) or (re.search(r'usecases\[\d+\]$', jpath.lower()) and kl == 'title')) else 'context'
                    stmts.append(Statement(v, cite, path, '%s.%s' % (jpath, k) if jpath else k, kind))
                elif isinstance(v, (list, dict)):
                    walk(v, '%s.%s' % (jpath, k) if jpath else k, claim_here, cite)
        elif isinstance(node, list):
            for i, v in enumerate(node):
                if isinstance(v, str):
                    if len(v.strip()) < 8:
                        continue
                    stmts.append(Statement(v, parent_cite, path, '%s[%d]' % (jpath, i), 'claim' if under_claim else 'context'))
                else:
                    walk(v, '%s[%d]' % (jpath, i), under_claim, parent_cite)
    walk(doc, '', False, '')
    # an object inside a claim array becomes ONE claim (text fields joined) so a {id, text, source} row
    # is scored once, not per field
    merged = []
    seen = set()
    for s in stmts:
        if s.kind == 'claim' and s.path.endswith(']') is False and '[' in s.path:
            base = s.path.rsplit('.', 1)[0]
            if base in seen:
                continue
            seen.add(base)
            sib = [t for t in stmts if t.kind == 'claim' and t.path.rsplit('.', 1)[0] == base]
            if len(sib) > 1:
                text = ' '.join(t.text for t in sib)
                cite = ' '.join(t.cite for t in sib)
                merged.append(Statement(text, cite, s.file, base, 'claim'))
                continue
        merged.append(s)
    return doc, merged


def md_table_rows(text):
    rows = []
    for line in text.splitlines():
        if line.startswith('|') and not re.match(r'^\|\s*-', line) and not re.match(r'^\|\s*(#|Stage|Decision)\s*\|', line):
            cells = [c.strip() for c in line.strip('|').split('|')]
            rows.append(' | '.join(cells))
    return rows


def read(path):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except OSError:
        return ''


def find_toolkit(project, explicit=None):
    cands = []
    if explicit:
        cands.append(explicit)
    if os.environ.get('MXTK_TOOLKIT'):
        cands.append(os.environ['MXTK_TOOLKIT'])
    loc = read(os.path.join(project, 'CLAUDE.local.md'))
    m = re.search(r'^\|\s*Toolkit root\s*\|\s*`?([^`|]+)`?\s*\|', loc, re.M)
    if m:
        cands.append(os.path.expanduser(m.group(1).strip()))
    cands.append(os.path.abspath(os.path.join(HERE, '..', '..')))
    cands.append(os.path.abspath(os.path.join(HERE, '..')))
    cands.append(os.path.expanduser('~/Mendix/mxcli-project-toolkit'))
    for c in cands:
        if os.path.isfile(os.path.join(c, 'bin', 'source-ledger.sh')) and os.path.isfile(os.path.join(c, 'bin', 'gate-check.sh')):
            return c
    return None


def ledger_from_run_report(project):
    """Read the verdict the RUN ITSELF recorded, from analysis/source-ledger.html.

    Re-running `source-ledger.sh check` against a handed-in project is wrong: the hand-in
    excludes sources/, so the checker sees an empty source root and reports 0 extracted /
    FAIL for a run whose ledger actually passed. Measured 2026-09-09 — all three A/B arms
    were reported FAIL this way while their own reports said PASS (a1 41 extracted + 159
    waived, b1 and c1 200 extracted). The run's own report is the only honest record.
    """
    rep = os.path.join(project, 'analysis', 'source-ledger.html')
    if not os.path.isfile(rep):
        return None
    try:
        raw = open(rep, encoding='utf-8', errors='replace').read()
    except OSError:
        return None
    import html as _html
    txt = _html.unescape(re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', raw)))
    counts = {}
    for kw in ('inventoried', 'extracted', 'waived', 'sensitive', 'superseded', 'pending', 'fault'):
        m = re.search(r'(\d+)\s+' + kw, txt)
        if m:
            counts['total' if kw == 'inventoried' else kw] = int(m.group(1))
    m = re.search(r'Source ledger:\s*(PASS|FAIL|BLOCKED)', txt, re.I)
    status = m.group(1).upper() if m else ('FAIL' if counts.get('pending') or counts.get('fault') else 'PASS')
    return {'ran': True, 'source': 'run report (analysis/source-ledger.html)',
            'status': status, 'counts': counts, 'rows': []}


def run_ledger(toolkit, project):
    own = ledger_from_run_report(project)
    if own is not None:
        return own
    if not os.path.isdir(os.path.join(project, 'sources')) and not os.path.isdir(os.path.join(project, 'source')):
        return {'ran': False, 'error': 'no source root in the hand-in and no analysis/source-ledger.html to read'}
    try:
        r = subprocess.run(['bash', os.path.join(toolkit, 'bin', 'source-ledger.sh'), 'check', project, '--json'],
                           capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {'ran': False, 'error': str(e)}
    out = r.stdout.strip()
    try:
        start = out.index('{')
        doc = json.loads(out[start:])
    except (ValueError, json.JSONDecodeError):
        return {'ran': True, 'exit': r.returncode, 'error': 'no JSON on stdout', 'stdout_tail': out[-400:], 'stderr_tail': r.stderr[-400:]}
    doc['ran'] = True
    doc['exit'] = r.returncode
    return doc


def run_gate(toolkit, project, stage):
    try:
        r = subprocess.run(['bash', os.path.join(toolkit, 'bin', 'gate-check.sh'), project, str(stage)],
                           capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {'ran': False, 'error': str(e)}
    text = (r.stdout + '\n' + r.stderr)
    # the stage's own line looks like "Stage 1 (Analysis): PENDING · Surface MISSING: ..." — everything
    # else in the output (obligations, artifacts, ledger rows) carries its own verdict word and is noise here
    m = re.search(r'^Stage %d \(([^)]*)\):\s*(PASS|FAIL|PENDING|WAIVED|MANUAL|BLOCKED|ADOPTED)\b(.*)$' % stage, text, re.M)
    ledger = re.search(r'^(Source ledger|LEDGER)[^\n]*$', text, re.M | re.I)
    return {'ran': True, 'exit': r.returncode, 'verdict': m.group(2) if m else 'UNPARSED',
            'stage_name': m.group(1) if m else '', 'detail': (m.group(3).strip(' ·—-') if m else '')[:200],
            'ledger_line': ledger.group(0)[:200] if ledger else ''}


# ----------------------------------------------------------------------------------------
# scoring
# ----------------------------------------------------------------------------------------
def best_match(key_text, key_id, stmts, section=None, must_contain=None):
    kt = tokens(key_text)
    best = (0.0, None, 'none')
    id_re = re.compile(r'(?<![A-Za-z0-9])' + re.escape(key_id) + r'(?![A-Za-z0-9])') if key_id else None
    page = (section or {}).get('file', '')
    page_stem = page.rsplit('.', 1)[0] if page else None
    for s in stmts:
        if must_contain and not has_must(s.text, must_contain):
            continue
        ov = overlap(kt, s.toks)
        how = 'overlap'
        if id_re and (id_re.search(s.text) or id_re.search(s.cite)):
            ov = max(ov, 1.0); how = 'id-cite'
        elif page_stem and ov >= 0.5 and (page_stem in s.cite or page_stem in s.text):
            ov = max(ov, 0.6); how = 'section-cite'   # page cited AND half the key tokens present
        if ov > best[0]:
            best = (ov, s, how)
    return best


def norm_name(n):
    return re.sub(r'[^a-z0-9]', '', str(n).lower())


def score_project(project, key, brd_dir=None, toolkit=None, manifest=None, include_analysis=False, no_run=False):
    res = {'project': os.path.abspath(project)}
    brd_files = discover_brds(project, brd_dir)
    res['brd_files'] = [os.path.relpath(b, project) for b in brd_files]
    stmts = []
    brds = []
    for b in brd_files:
        try:
            doc, st = harvest_brd(b)
        except (OSError, json.JSONDecodeError) as e:
            res.setdefault('brd_errors', []).append('%s: %s' % (os.path.relpath(b, project), e))
            continue
        brds.append(doc); stmts += st

    # register / questions
    reg = read(os.path.join(project, 'PROJECT.md'))
    reg_rows = md_table_rows(reg)
    sme = read(os.path.join(project, 'analysis', 'sme-questions.md')) + ''.join(read(p) for p in glob.glob(os.path.join(project, 'analysis', '*', 'sme-questions.md')))
    triage = read(os.path.join(project, 'analysis', 'triage.md'))
    question_texts = list(reg_rows)
    question_texts += [l for l in sme.splitlines() if l.strip()]
    for s in stmts:
        if 'openquestions' in s.path.lower() or 'opengaps' in s.path.lower() or 'gaps' in s.path.lower():
            question_texts.append(s.text + ' ' + s.cite)
    for p in glob.glob(os.path.join(project, 'analysis', '**', '*.md'), recursive=True):
        for l in read(p).splitlines():
            if re.search(r'contradict|conflict|inconsisten|disagree|ambigu', l, re.I):
                question_texts.append(l)
    # merge BRD openQuestions objects into one text each (question + answer + notes)
    for doc in brds:
        for q in doc.get('openQuestions', []) or []:
            if isinstance(q, dict):
                question_texts.append(' '.join(str(v) for v in q.values() if isinstance(v, (str, int, float))))

    extra = []
    if include_analysis:
        for p in glob.glob(os.path.join(project, 'analysis', '**', '*.md'), recursive=True):
            for i, l in enumerate(read(p).splitlines()):
                if len(l.strip()) >= 12:
                    extra.append(Statement(l, '', p, 'L%d' % (i + 1), 'context'))
    pool = stmts + extra

    # --- requirements ---
    req_rows = []
    hit = 0
    for r in key['requirements']:
        ov, s, how = best_match(r['text'], r['id'], pool, r.get('section'))
        matched = ov >= 0.6
        hit += matched
        req_rows.append({'id': r['id'], 'matched': matched, 'score': round(ov, 2), 'how': how if matched else '',
                         'where': s.where() if s else '', 'candidate': (s.text[:110] if s else ''), 'page': r['section']['file']})
    res['requirements'] = {'total': len(key['requirements']), 'found': hit, 'recall': round(hit / len(key['requirements']), 3), 'rows': req_rows}

    # --- business rules ---
    rule_rows = []
    rhit = 0
    for b in key['business_rules']:
        ov, s, how = best_match(b['text'], b['id'], pool, b.get('section'), must_contain=b.get('must_contain'))
        ov_loose, s2, _ = best_match(b['text'], b['id'], pool, b.get('section'))
        matched = ov >= 0.6
        rhit += matched
        rule_rows.append({'id': b['id'], 'matched': matched, 'score': round(ov, 2), 'how': how if matched else '',
                          'where': s.where() if s else '', 'candidate': (s.text[:110] if s else ''),
                          'note': ('' if matched or ov_loose < 0.6 else 'statement found but threshold/state (%s) missing' % ', '.join(b['must_contain']))})
    res['business_rules'] = {'total': len(key['business_rules']), 'found': rhit, 'recall': round(rhit / len(key['business_rules']), 3), 'rows': rule_rows}

    # --- screenshot-only ---
    shot_rows = []
    shits = 0
    all_lines = [s.text for s in pool] + reg_rows + question_texts + [l for l in triage.splitlines()]
    for sh in key['screenshot_only']:
        found = None
        kt = tokens(sh['text'])
        for t in all_lines:
            if has_must(t, sh['must_contain']) and overlap(kt, tokens(t)) >= 0.6:
                found = t[:110]; break
        shits += bool(found)
        shot_rows.append({'id': sh['id'], 'found': bool(found), 'evidence': found or '', 'image': sh['image'], 'mode': sh['mode']})
    res['screenshot_only'] = {'total': len(key['screenshot_only']), 'found': shits, 'rows': shot_rows}

    # --- contradictions ---
    con_rows = []
    chits = 0
    for c in key['contradictions']:
        ids = c['requirements']
        ev = None
        for t in question_texts:
            low = t.lower()
            both = all(re.search(r'(?<![A-Za-z0-9])' + re.escape(i) + r'(?![A-Za-z0-9])', t) for i in ids)
            terms = all(any(term.lower() in low for term in group) for group in c['detect_terms'])
            if both or terms:
                ev = t[:140]; break
        chits += bool(ev)
        con_rows.append({'id': c['id'], 'surfaced': bool(ev), 'evidence': ev or '', 'requirements': ids, 'pages': c['pages']})
    res['contradictions'] = {'total': len(key['contradictions']), 'surfaced': chits, 'rows': con_rows}

    # --- phantoms / precision ---
    key_pool = [(r['id'], r['text']) for r in key['requirements']] + [(b['id'], b['text']) for b in key['business_rules']] + \
               [(s['id'], s['text']) for s in key['screenshot_only']]
    key_toks = [(i, tokens(t)) for i, t in key_pool]
    claims = [s for s in stmts if s.kind == 'claim']
    phantoms = []
    grounded = 0
    for s in claims:
        best = 0.0; bid = None
        for i, kt in key_toks:
            ov = overlap(kt, s.toks)
            if ov > best:
                best, bid = ov, i
            if re.search(r'(?<![A-Za-z0-9])' + re.escape(i) + r'(?![A-Za-z0-9])', s.text + ' ' + s.cite):
                best, bid = 1.0, i
        if best >= 0.5:
            grounded += 1
        else:
            phantoms.append({'where': s.where(), 'text': s.text[:110], 'best': round(best, 2), 'nearest': bid})
    res['claims'] = {'total': len(claims), 'grounded': grounded, 'phantoms': len(phantoms),
                     'precision': (round(grounded / len(claims), 3) if claims else None), 'phantom_rows': phantoms[:40]}

    # --- entities / attributes / associations ---
    brd_entities = []
    for doc in brds:
        for e in doc.get('domainEntities', []) or []:
            if not isinstance(e, dict) or not e.get('name'):
                continue
            attrs = [a.get('name') if isinstance(a, dict) else a for a in (e.get('attributes') or [])]
            brd_entities.append({'name': e['name'], 'attrs': [norm_name(a) for a in attrs if a],
                                 'assocs': [(a.get('target') or a.get('to') or '') for a in (e.get('associations') or []) if isinstance(a, dict)]})
    ent_rows = []
    ehit = 0; attr_total = 0; attr_hit = 0
    used = set()
    for ke in key['entities']:
        kn = norm_name(ke['name'])
        cand = None
        for be in brd_entities:
            if id(be) in used:
                continue
            bn = norm_name(be['name'])
            if bn == kn:
                cand = be; break
        if cand is None:
            for be in brd_entities:
                bn = norm_name(be['name'])
                if id(be) not in used and len(bn) >= 4 and (kn.endswith(bn) or (bn.endswith(kn) and len(kn) >= 5)):
                    cand = be; break
        found_attrs = []
        missing = []
        for a in ke['attributes']:
            attr_total += 1
            an = norm_name(a['name'])
            ok = cand is not None and any(an == x or (len(x) >= 3 and (an.startswith(x) or x.startswith(an) or an.endswith(x))) for x in cand['attrs'])
            attr_hit += ok
            (found_attrs if ok else missing).append(a['name'])
        if cand:
            used.add(id(cand)); ehit += 1
        ent_rows.append({'entity': ke['name'], 'matched': cand['name'] if cand else '', 'attributes_total': len(ke['attributes']),
                         'attributes_found': len(found_attrs), 'missing_attributes': missing})
    # associations: unordered entity pairs
    key_pairs = {frozenset((norm_name(a['from']), norm_name(a['to']))) for a in key['associations']}
    brd_pairs = set()
    for be in brd_entities:
        for t in be['assocs']:
            t = str(t).split('.')[-1]
            if t:
                brd_pairs.add(frozenset((norm_name(be['name']), norm_name(t))))
    for doc in brds:
        for a in doc.get('associations', []) or []:
            if isinstance(a, dict):
                f = str(a.get('from') or a.get('owner') or a.get('source') or '').split('.')[-1]
                t = str(a.get('to') or a.get('target') or '').split('.')[-1]
                if f and t:
                    brd_pairs.add(frozenset((norm_name(f), norm_name(t))))
    ahit = sum(1 for p in key_pairs if p in brd_pairs)
    res['entities'] = {'total': len(key['entities']), 'found': ehit, 'recall': round(ehit / len(key['entities']), 3),
                       'brd_entities': len(brd_entities), 'attributes_total': attr_total, 'attributes_found': attr_hit,
                       'attribute_recall': round(attr_hit / attr_total, 3) if attr_total else None,
                       'associations_total': len(key_pairs), 'associations_found': ahit,
                       'association_recall': round(ahit / len(key_pairs), 3), 'rows': ent_rows}

    # --- roles & screens (cheap presence check over BRD actors/pages + register) ---
    blob = ' '.join(s.text for s in stmts).lower() + ' '.join(str(doc.get('actors', '')) for doc in brds).lower()
    res['roles'] = {'total': len(key['roles']), 'found': sum(1 for r in key['roles'] if r['label'].lower() in blob or norm_name(r['name']) in norm_name(blob))}
    res['screens'] = {'total': len(key['screens']), 'found': sum(1 for s in key['screens'] if s['label'].lower() in blob or norm_name(s['name']) in norm_name(blob))}

    # --- stage artifacts, ledger, gates ---
    res['artifacts'] = {'triage.md': bool(triage.strip()), 'PROJECT.md': bool(reg.strip()),
                        'sme-questions.md': bool(sme.strip()), 'brd_count': len(brd_files)}
    tk = None if no_run else find_toolkit(project, toolkit)
    res['toolkit'] = tk
    ledger = run_ledger(tk, project) if tk else {'ran': False, 'error': 'toolkit not found (pass --toolkit)'}
    lsum = {'ran': ledger.get('ran', False), 'status': ledger.get('status'), 'note': ledger.get('note') or ledger.get('error'),
            'counts': ledger.get('counts', {})}
    rows = ledger.get('rows', []) or []
    if rows:
        chrome = set(key['corpus'].get('pages') and [p['file'] for p in key['corpus']['pages'] if p['chrome']])
        by_kind = {'chrome_pages': {}, 'content_pages': {}, 'sidecar_images': {}, 'sidecar_support': {}, 'markdown': {}, 'other': {}}
        shot_rel = os.path.basename(key['screenshot_only'][0]['image'])
        shot_verdict = None
        for r in rows:
            rel = r.get('rel', '')
            base = os.path.basename(rel)
            v = r.get('verdict', '?')
            if base == shot_rel:
                shot_verdict = v
            if base in chrome:
                k = 'chrome_pages'
            elif base.endswith('.html'):
                k = 'content_pages'
            elif '_files/' in rel and base.lower().endswith(('.png', '.jpg', '.jpeg')):
                k = 'sidecar_images'
            elif '_files/' in rel:
                k = 'sidecar_support'
            elif base.endswith('.md'):
                k = 'markdown'
            else:
                k = 'other'
            by_kind[k][v] = by_kind[k].get(v, 0) + 1
        lsum['by_kind'] = by_kind
        lsum['screenshot_image_verdict'] = shot_verdict
        if manifest:
            try:
                mf = json.load(open(manifest))
                lsum['manifest_files'] = mf['totals']['files']
                lsum['inventoried_rows'] = len(rows)
            except (OSError, KeyError, json.JSONDecodeError):
                pass
    res['ledger'] = lsum

    gates = {}
    m = re.search(r'^## Current stage\s*\n+(.+)$', reg, re.M)
    gates['register_current_stage'] = m.group(1).strip() if m else ''
    gates['register_lines'] = [l.strip() for l in reg.splitlines() if re.match(r'^\s*(Adopted at stage|Waived stage|Waived artifact|Waived source)\b', l, re.I)][:20]
    bl = read(os.path.join(project, 'docs', 'BUILD-LOG.md'))
    gates['build_log_stage_lines'] = [l.strip()[:120] for l in bl.splitlines() if re.search(r'\bStage [012]\b', l)][:10]
    gates['claude_receipts'] = sorted(os.path.basename(p) for p in glob.glob(os.path.join(project, '.claude', '.*')) + glob.glob(os.path.join(project, '.claude', '*')) if os.path.isfile(p))
    gates['gate_check'] = {str(s): run_gate(tk, project, s) for s in (1, 2)} if tk else {'ran': False}
    res['gates'] = gates
    return res


# ----------------------------------------------------------------------------------------
# rendering
# ----------------------------------------------------------------------------------------
def pct(x):
    return '—' if x is None else '%.0f%%' % (100 * x)


def render_md(res):
    L = []
    L.append('# Score — %s' % res['project'])
    L.append('')
    L.append('BRDs read: %d (%s)' % (len(res['brd_files']), ', '.join(res['brd_files']) or 'none'))
    if res.get('brd_errors'):
        L.append('BRD errors: ' + '; '.join(res['brd_errors']))
    L.append('')
    r, b, e, c, s, sh = res['requirements'], res['business_rules'], res['entities'], res['claims'], res['contradictions'], res['screenshot_only']
    L.append('| Metric | Value | Detail |')
    L.append('|---|---|---|')
    L.append('| Requirement recall | %s | %d / %d |' % (pct(r['recall']), r['found'], r['total']))
    L.append('| Requirement precision | %s | %d grounded of %d claims, %d phantom |' % (pct(c['precision']), c['grounded'], c['total'], c['phantoms']))
    L.append('| Business-rule recall | %s | %d / %d (threshold/state required) |' % (pct(b['recall']), b['found'], b['total']))
    L.append('| Entity recall | %s | %d / %d (%d BRD entities) |' % (pct(e['recall']), e['found'], e['total'], e['brd_entities']))
    L.append('| Attribute recall | %s | %d / %d |' % (pct(e['attribute_recall']), e['attributes_found'], e['attributes_total']))
    L.append('| Association recall | %s | %d / %d |' % (pct(e['association_recall']), e['associations_found'], e['associations_total']))
    L.append('| Contradictions surfaced | %d / %d | as open questions or decisions |' % (s['surfaced'], s['total']))
    L.append('| Screenshot-only requirements found | %d / %d | |' % (sh['found'], sh['total']))
    L.append('| Roles / screens named | %d / %d, %d / %d | |' % (res['roles']['found'], res['roles']['total'], res['screens']['found'], res['screens']['total']))
    lg = res['ledger']
    if lg.get('ran') and lg.get('counts'):
        cn = lg['counts']
        L.append('| Source ledger | %s | %s |' % (lg.get('status'), ', '.join('%s=%s' % (k, cn[k]) for k in ('total', 'extracted', 'waived', 'pending', 'fault', 'drift') if k in cn)))
    else:
        L.append('| Source ledger | not run | %s |' % (lg.get('note') or ''))
    g = res['gates']
    gc = g.get('gate_check', {})
    if gc.get('1'):
        L.append('| Gate check | stage 1: %s; stage 2: %s | register: %s |' % (gc['1'].get('verdict', gc['1'].get('error')), gc['2'].get('verdict', gc['2'].get('error')), g['register_current_stage']))
    else:
        L.append('| Gate check | not run | register: %s |' % g['register_current_stage'])
    L.append('')
    L.append('## Requirements')
    L.append('')
    L.append('| Id | Page | Found | Score | How | Where | Nearest BRD statement |')
    L.append('|---|---|---|---|---|---|---|')
    for row in r['rows']:
        L.append('| %s | %s | %s | %.2f | %s | %s | %s |' % (row['id'], row['page'], 'yes' if row['matched'] else 'NO', row['score'], row['how'], row['where'], row['candidate'].replace('|', '/')))
    L.append('')
    L.append('## Business rules')
    L.append('')
    L.append('| Id | Found | Score | Where | Nearest | Note |')
    L.append('|---|---|---|---|---|---|')
    for row in b['rows']:
        L.append('| %s | %s | %.2f | %s | %s | %s |' % (row['id'], 'yes' if row['matched'] else 'NO', row['score'], row['where'], row['candidate'].replace('|', '/'), row['note']))
    L.append('')
    L.append('## Entities')
    L.append('')
    L.append('| Key entity | BRD entity | Attributes found | Missing |')
    L.append('|---|---|---|---|')
    for row in e['rows']:
        L.append('| %s | %s | %d / %d | %s |' % (row['entity'], row['matched'] or '—', row['attributes_found'], row['attributes_total'], ', '.join(row['missing_attributes'])))
    L.append('')
    L.append('## Contradictions')
    L.append('')
    for row in s['rows']:
        L.append('- %s (%s on %s): %s%s' % (row['id'], ' vs '.join(row['requirements']), ' / '.join(row['pages']), 'SURFACED' if row['surfaced'] else 'not surfaced', (' — "%s"' % row['evidence'].replace('|', '/')) if row['evidence'] else ''))
    L.append('')
    L.append('## Screenshot-only requirements')
    L.append('')
    for row in sh['rows']:
        L.append('- %s (%s, %s): %s%s' % (row['id'], row['mode'], row['image'], 'FOUND' if row['found'] else 'not found', (' — "%s"' % row['evidence']) if row['evidence'] else ''))
    if lg.get('screenshot_image_verdict'):
        L.append('- ledger verdict on the sidecar screenshot image: %s' % lg['screenshot_image_verdict'])
    L.append('')
    if c['phantom_rows']:
        L.append('## Phantom claims (BRD statements matching nothing in the key; first %d)' % len(c['phantom_rows']))
        L.append('')
        for p in c['phantom_rows']:
            L.append('- %s — "%s" (best %.2f vs %s)' % (p['where'], p['text'].replace('|', '/'), p['best'], p['nearest']))
        L.append('')
    if lg.get('by_kind'):
        L.append('## Ledger by file kind')
        L.append('')
        L.append('| Kind | Verdicts |')
        L.append('|---|---|')
        for k, v in lg['by_kind'].items():
            if v:
                L.append('| %s | %s |' % (k, ', '.join('%s=%d' % kv for kv in sorted(v.items()))))
        if 'manifest_files' in lg:
            L.append('')
            L.append('Manifest says %d files; ledger inventoried %d rows.' % (lg['manifest_files'], lg['inventoried_rows']))
        L.append('')
    L.append('## Gates')
    L.append('')
    L.append('- Register "Current stage": %s' % (g['register_current_stage'] or '(none)'))
    if g['register_lines']:
        L.append('- Register waiver/adoption lines: ' + '; '.join(g['register_lines']))
    if g['build_log_stage_lines']:
        L.append('- BUILD-LOG stage lines: ' + '; '.join(g['build_log_stage_lines']))
    if g['claude_receipts']:
        L.append('- .claude receipts: ' + ', '.join(g['claude_receipts']))
    for st in ('1', '2'):
        if gc.get(st) and gc[st].get('ran'):
            L.append('- gate-check %s (%s): %s — %s' % (st, gc[st]['stage_name'], gc[st]['verdict'], gc[st]['detail'].replace('|', '/')))
            if gc[st].get('ledger_line'):
                L.append('  - %s' % gc[st]['ledger_line'].replace('|', '/'))
    return '\n'.join(L) + '\n'


# ----------------------------------------------------------------------------------------
# self-test
# ----------------------------------------------------------------------------------------
def fabricate_brds(key, brd_dir, fraction=1.0, phantoms=0, contradictions=True, screenshots=True):
    os.makedirs(brd_dir, exist_ok=True)
    reqs = key['requirements']; rules = key['business_rules']; ents = key['entities']
    n_req = int(round(len(reqs) * fraction)); n_rule = int(round(len(rules) * fraction)); n_ent = int(round(len(ents) * fraction))
    reqs = reqs[:n_req]; rules = rules[:n_rule]; ents = ents[:n_ent]
    ent_names = {e['name'] for e in ents}
    chunks = [reqs[i::4] for i in range(4)]
    rule_chunks = [rules[i::4] for i in range(4)]
    ent_chunks = [ents[i::4] for i in range(4)]
    phantom_texts = ['The portal shows a weather widget for the harbour entrance.', 'Users can choose between a light and a dark colour theme.',
                     'A tug is dispatched automatically for vessels over 300 metres.', 'The application supports Dutch and German user interfaces.',
                     'Bookings can be paid by credit card at submission time.', 'The system prints a boarding pass for the pilot.']
    files = []
    for i in range(4):
        brd = {'id': 'F%03d' % (i + 1), 'title': 'Harbour Berth Booking part %d' % (i + 1), 'modules': ['HarbourBerthBooking'],
               'actors': [r['label'] for r in key['roles']], 'provenance': 'documents',
               'useCases': [{'id': 'UC%03d' % (j + 1), 'title': r['text'], 'actors': ['Shipping Agent'], 'preconditions': [], 'postconditions': [],
                             'mainFlow': ['1. See ' + r['section']['file'] + ' ' + r['section']['heading']], 'screens': [s['label'] for s in key['screens']], 'mdlRefs': [],
                             'source': r['section']['file'] + ' #' + r['section']['heading']} for j, r in enumerate(chunks[i])],
               'businessRules': [{'id': b['id'], 'text': b['text'], 'source': b['section']['file']} for b in rule_chunks[i]],
               'domainEntities': [{'name': e['name'], 'module': 'HarbourBerthBooking', 'persistent': True,
                                   'attributes': [{'name': a['name'], 'type': a['type'].split('(')[0], 'mandatory': a['required']} for a in e['attributes']],
                                   'associations': [{'name': a['name'], 'target': a['to'], 'type': a['type'], 'owner': a['from']} for a in key['associations'] if a['from'] == e['name'] and a['to'] in ent_names]}
                                  for e in ent_chunks[i]],
               'microflows': [], 'pages': [], 'integrations': [], 'openQuestions': [], 'sourceKB': ['workshop-notes.md']}
        if i == 0 and phantoms:
            brd['businessRules'] += [{'id': 'X%03d' % k, 'text': t} for k, t in enumerate(phantom_texts[:phantoms])]
        if i == 1 and screenshots:
            brd['microflows'].append({'name': 'VAL_BookingRequest', 'module': 'HarbourBerthBooking', 'purpose': 'form validation',
                                      'validations': [s['text'] for s in key['screenshot_only']]})
        if i == 2 and contradictions:
            brd['openQuestions'] = [{'id': 'D%d' % k, 'question': 'Contradiction between %s and %s: %s' % (c['requirements'][0], c['requirements'][1], c['summary']),
                                     'status': 'RAISED', 'raisedAtGate': 'Stage 2 gate'} for k, c in enumerate(key['contradictions'])]
        p = os.path.join(brd_dir, '%s-part-%d.brd.json' % (brd['id'], i + 1))
        with open(p, 'w') as f:
            json.dump(brd, f, indent=2)
        files.append(p)
    return files


def self_test(key_path, keep=False):
    spec = importlib.util.spec_from_file_location('gen_corpus', os.path.join(HERE, 'gen-corpus.py'))
    gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
    with open(key_path, encoding='utf-8') as f:
        key = json.load(f)
    tmp = tempfile.mkdtemp(prefix='ab-fixture-selftest-')
    failures = []

    def check(cond, msg):
        print(('  ok   ' if cond else '  FAIL ') + msg)
        if not cond:
            failures.append(msg)
    try:
        corpus = os.path.join(tmp, 'corpus')
        m = gen.generate(corpus, 7, key, write_manifest=True)
        t = m['totals']
        print('self-test: corpus generated in %s — %d files, %.1f MB' % (corpus, t['files'], t['bytes'] / 1e6))
        check(8e6 <= t['bytes'] <= 20e6, 'corpus size within 8-20 MB (%.1f MB)' % (t['bytes'] / 1e6))
        check(t['html_pages'] == 36 and t['chrome_pages'] == 6, '36 HTML pages incl. 6 chrome')
        leak = []
        for p in glob.glob(os.path.join(corpus, '**', '*'), recursive=True):
            if os.path.isfile(p) and p.endswith(('.html', '.md', '.css', '.js')):
                low = read(p).lower()
                for s in key['screenshot_only']:
                    if s['text'].lower() in low:
                        leak.append((s['id'], os.path.basename(p)))
        check(not leak, 'screenshot-only text appears in no text file (%s)' % (leak or 'clean'))
        byid = {x['id']: x for x in key['requirements'] + key['business_rules']}
        missing = [i for i, x in byid.items() if x['text'] not in read(os.path.join(corpus, x['section']['file']))]
        check(not missing, 'every key statement is on its page (%s)' % (missing or 'all placed'))
        big = [p['file'] for p in m['pages'] if p['minified']]
        ok_min = all(max(len(l) for l in read(os.path.join(corpus, f)).splitlines()) > 20000 for f in big)
        check(ok_min and len(big) >= 6, '%d pages carry a one-line block > 20 KB' % len(big))

        # perfect project
        proj = os.path.join(tmp, 'perfect')
        os.makedirs(os.path.join(proj, 'analysis'), exist_ok=True)
        fabricate_brds(key, os.path.join(proj, 'analysis', 'knowledge-base', 'brd'))
        with open(os.path.join(proj, 'PROJECT.md'), 'w') as f:
            f.write('# PROJECT.md\n\n## Current stage\n\n**Stage 2 — complete (self-test)**\n\n## Decisions\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n\n## Open questions\n\n| # | Question | Raised at | Status |\n|---|---|---|---|\n')
        with open(os.path.join(proj, 'analysis', 'triage.md'), 'w') as f:
            f.write('# Source Triage: self-test\n')
        res = score_project(proj, key, no_run=True)
        print(render_md(res).split('\n## Requirements')[0])
        check(res['requirements']['recall'] == 1.0, 'perfect set: requirement recall 1.0 (%s)' % res['requirements']['recall'])
        check(res['claims']['precision'] == 1.0, 'perfect set: precision 1.0 (%s)' % res['claims']['precision'])
        check(res['business_rules']['recall'] == 1.0, 'perfect set: rule recall 1.0 (%s)' % res['business_rules']['recall'])
        check(res['entities']['recall'] == 1.0 and res['entities']['attribute_recall'] == 1.0, 'perfect set: entity + attribute recall 1.0')
        check(res['entities']['association_recall'] == 1.0, 'perfect set: association recall 1.0 (%s)' % res['entities']['association_recall'])
        check(res['contradictions']['surfaced'] == 3, 'perfect set: 3 contradictions surfaced')
        check(res['screenshot_only']['found'] == 2, 'perfect set: 2 screenshot-only requirements found')

        # half project (+3 phantoms, no contradictions raised)
        proj2 = os.path.join(tmp, 'half')
        os.makedirs(os.path.join(proj2, 'analysis'), exist_ok=True)
        fabricate_brds(key, os.path.join(proj2, 'analysis', 'knowledge-base', 'brd'), fraction=0.5, phantoms=3, contradictions=False, screenshots=False)
        res2 = score_project(proj2, key, no_run=True)
        print(render_md(res2).split('\n## Requirements')[0])
        check(0.4 <= res2['requirements']['recall'] <= 0.6, 'half set: requirement recall ~0.5 (%s)' % res2['requirements']['recall'])
        check(0.4 <= res2['business_rules']['recall'] <= 0.6, 'half set: rule recall ~0.5 (%s)' % res2['business_rules']['recall'])
        check(0.4 <= res2['entities']['recall'] <= 0.6, 'half set: entity recall ~0.5 (%s)' % res2['entities']['recall'])
        check(res2['claims']['phantoms'] == 3, 'half set: exactly the 3 planted phantoms counted (%d)' % res2['claims']['phantoms'])
        check(res2['contradictions']['surfaced'] == 0 and res2['screenshot_only']['found'] == 0, 'half set: 0 contradictions, 0 screenshot-only')

        # paraphrase robustness: rules with thresholds reworded, and one with the threshold dropped
        proj3 = os.path.join(tmp, 'para')
        bd = os.path.join(proj3, 'analysis', 'knowledge-base', 'brd'); os.makedirs(bd)
        para = {'id': 'F001', 'modules': ['X'], 'provenance': 'documents', 'useCases': [
            {'id': 'UC1', 'title': 'Suspend an agent automatically once it has 3 overdue invoices'},
            {'id': 'UC2', 'title': 'Add VAT to every berth fee'},
            {'id': 'UC3', 'title': 'Cancelling is free of charge up to 24h before the ETA (see 10-cancellation-and-changes)'},
            {'id': 'UC4', 'title': 'Vessels arriving > 2 hours late pay a 15 percent surcharge on the berth fee'}]}
        json.dump(para, open(os.path.join(bd, 'F001.brd.json'), 'w'))
        res3 = score_project(proj3, key, no_run=True)
        rr = {r['id']: r for r in res3['business_rules']['rows']}
        check(rr['B004']['matched'], 'paraphrase: B004 (three->3, reworded) matched (%s)' % rr['B004']['score'])
        check(not rr['B010']['matched'] and 'threshold' in rr['B010']['note'], 'paraphrase: B010 without its 21% threshold is NOT counted')
        check(rr['B008']['matched'], 'paraphrase: B008 reworded with both thresholds matched (%s)' % rr['B008']['score'])
        r14 = {r['id']: r for r in res3['requirements']['rows']}['R014']
        check(r14['matched'], 'paraphrase: R014 reworded matched (%s via %s)' % (r14['score'], r14['how']))

        # empty project
        proj4 = os.path.join(tmp, 'empty'); os.makedirs(proj4)
        res4 = score_project(proj4, key, no_run=True)
        check(res4['requirements']['recall'] == 0.0 and res4['claims']['precision'] is None, 'empty project: recall 0, precision n/a')

        # ledger integration, only if the toolkit is reachable
        tk = find_toolkit(proj)
        if tk:
            src = os.path.join(proj, 'sources', 'portal')
            shutil.copytree(corpus, src)
            os.remove(os.path.join(src, 'MANIFEST.json'))
            r = subprocess.run(['bash', os.path.join(tk, 'bin', 'source-sufficiency.sh'), 'init', proj], capture_output=True, text=True, timeout=300)
            lg = run_ledger(tk, proj)
            cn = lg.get('counts', {})
            print('  ledger via %s: %s' % (tk, lg.get('note')))
            check(lg.get('ran') and cn.get('total', 0) >= t['files'] - 1, 'ledger inventoried the whole corpus (%s rows vs %d files)' % (cn.get('total'), t['files'] - 1))
            check(cn.get('pending', 0) == cn.get('total', 0), 'fresh inventory: every row PENDING (nobody extracted anything yet)')
        else:
            print('  skip ledger integration (toolkit not found; set MXTK_TOOLKIT to run it)')
    finally:
        if keep:
            print('kept', tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        print('SELF-TEST FAILED: %d assertion(s)' % len(failures))
        return 1
    print('SELF-TEST PASSED')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('project', nargs='?')
    ap.add_argument('--key', default=os.path.join(HERE, 'answer-key.json'))
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--toolkit', help='toolkit root (for source-ledger.sh / gate-check.sh)')
    ap.add_argument('--brd-dir', help='override BRD discovery')
    ap.add_argument('--manifest', help='MANIFEST.json of the corpus the project was run on (ledger cross-check)')
    ap.add_argument('--include-analysis', action='store_true', help='also match against analysis/**/*.md lines (recall only)')
    ap.add_argument('--no-run', action='store_true', help='do not run the toolkit scripts')
    ap.add_argument('--self-test', action='store_true')
    ap.add_argument('--keep', action='store_true', help='self-test: keep the temp dir')
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test(a.key, keep=a.keep)
    if not a.project:
        ap.error('project dir required (or --self-test)')
    with open(a.key, encoding='utf-8') as f:
        key = json.load(f)
    res = score_project(a.project, key, brd_dir=a.brd_dir, toolkit=a.toolkit, manifest=a.manifest, include_analysis=a.include_analysis, no_run=a.no_run)
    if a.json:
        print(json.dumps(res, indent=2))
    else:
        print(render_md(res))
    return 0


if __name__ == '__main__':
    sys.exit(main())
