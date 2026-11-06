#!/usr/bin/env python3
"""rollback-scan.py: engine of rollback-scan.sh. See that script's header for what and why.

Reads .mxcli/catalog.db read-only (REFS call edges, ACTIVITIES, ATTRIBUTES), walks the flows a
test reaches, classifies what it finds with rollback-effects.tsv. Prints; never writes the model.
"""
import fnmatch, json, os, re, sqlite3, sys, time
from collections import deque

CALL_RE = re.compile(r'\b(?:call\s+(?:microflow|nanoflow|java\s+action)|@setup|@teardown)\s+([A-Za-z_]\w*\.[A-Za-z_]\w*)', re.I)
COMMENT_RE = re.compile(r'/\*.*?\*/|--[^\n]*', re.S)
QUAL_RE = re.compile(r'^[A-Za-z_]\w*\.[A-Za-z_]\w*$')
FLOW_TYPES = ('MICROFLOW', 'NANOFLOW', 'WORKFLOW')
U_CAP = 10


def load_effects(path):
    rows = []
    with open(path, encoding='utf-8') as fh:
        for ln in fh:
            if ln.startswith('#') or not ln.strip():
                continue
            c = (ln.rstrip('\n').split('\t') + [''] * 7)[:7]
            rows.append(dict(cls=c[0], effect=c[1], kind=c[2], pattern=c[3],
                             exc=[] if c[4] in ('', '-') else c[4].split(','), proof=c[5], note=c[6]))
    return rows


def roots_from(args):
    roots, files, bad = [], [], []
    for a in args:
        if os.path.isfile(a):
            files.append(a)
            with open(a, encoding='utf-8', errors='replace') as fh:
                for m in CALL_RE.finditer(COMMENT_RE.sub(' ', fh.read())):
                    if m.group(1) not in roots:
                        roots.append(m.group(1))
        elif QUAL_RE.match(a):
            if a not in roots:
                roots.append(a)
        else:
            bad.append(a)
    return roots, files, bad


def stale_note(catalog, mpr):
    if not mpr or not os.path.exists(mpr):
        return ''
    cat = os.path.getmtime(catalog)
    newest = os.path.getmtime(mpr)
    # The .mpr and the mprcontents folder itself only. Walking its ~2,900 per-unit folders cost 2 s
    # on a synced drive, 40 times the scan. Approximate on purpose: --refresh is the sure way.
    d = os.path.join(os.path.dirname(mpr), 'mprcontents')
    if os.path.isdir(d):
        newest = max(newest, os.path.getmtime(d))
    if newest > cat:
        return 'the model is newer than the catalog; refresh it (--refresh) or the result may be stale'
    return ''


def main(argv):
    catalog = mpr = effects_file = None
    as_json = False
    items = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--catalog': catalog = argv[i + 1]; i += 2
        elif a == '--mpr': mpr = argv[i + 1]; i += 2
        elif a == '--effects': effects_file = argv[i + 1]; i += 2
        elif a == '--json': as_json = True; i += 1
        else: items.append(a); i += 1

    roots, files, bad = roots_from(items)
    out = {'catalog': catalog, 'testFiles': files, 'roots': roots, 'reached': 0,
           'effects': [], 'unknownRoots': [], 'ignored': bad, 'warnings': []}

    def emit(text_lines):
        if as_json:
            print(json.dumps(out, indent=2))
        else:
            print('\n'.join(text_lines))

    if not catalog or not os.path.isfile(catalog):
        msg = ('no catalog at %s. Build it once: mxcli -p <App>.mpr -c "refresh catalog full" '
               '(or rerun with --refresh). Nothing scanned; this check is advisory.' % (catalog or '.mxcli/catalog.db'))
        out['warnings'].append(msg)
        emit(['rollback-scan: ' + msg])
        return 0
    if not roots:
        msg = 'no flow to scan: pass a *.test.mdl file or Module.Flow names (a test file that calls no flow has nothing to scan).'
        out['warnings'].append(msg)
        emit(['rollback-scan: ' + msg])
        return 0

    t0 = time.time()
    db = sqlite3.connect('file:%s?mode=ro' % catalog.replace('?', '%3f').replace('#', '%23'), uri=True)
    try:
        n_ref = db.execute("select count(*) from refs").fetchone()[0]
    except sqlite3.Error as e:
        msg = 'catalog unreadable (%s). Rebuild: mxcli -p <App>.mpr -c "refresh catalog full".' % e
        out['warnings'].append(msg)
        emit(['rollback-scan: ' + msg])
        return 0
    if n_ref == 0:
        msg = 'catalog has no references (fast-built catalogs are empty). Rebuild: mxcli -p <App>.mpr -c "refresh catalog full".'
        out['warnings'].append(msg)
        emit(['rollback-scan: ' + msg])
        return 0
    st = stale_note(catalog, mpr)
    if st:
        out['warnings'].append(st)

    eff = load_effects(effects_file)
    call_rules = [e for e in eff if e['kind'] == 'call']
    type_rules = [e for e in eff if e['kind'] == 'calltype']
    ignore = [e['pattern'] for e in eff if e['kind'] == 'ignore']
    act_rules = {e['pattern']: e for e in eff if e['kind'] == 'action'}
    auto_rule = next((e for e in eff if e['kind'] == 'autonumber'), None)
    fd_rule = next((e for e in eff if e['kind'] == 'filedoc'), None)

    def call_match(name):
        for r in call_rules:
            if fnmatch.fnmatchcase(name, r['pattern']) and not any(fnmatch.fnmatchcase(name, x) for x in r['exc']):
                return r
        return None

    calls, touches = {}, {}
    for s, t, tt in db.execute("select SourceName, TargetName, TargetType from refs where RefKind='call' and SourceType in ('MICROFLOW','NANOFLOW','WORKFLOW')"):
        calls.setdefault(s, []).append((t, tt))
    for s, t in db.execute("select SourceName, TargetName from refs where RefKind in ('create','commit','delete') and SourceType in ('MICROFLOW','NANOFLOW') and TargetType='ENTITY'"):
        touches.setdefault(s, set()).add(t)
    created = {}
    for s, t in db.execute("select SourceName, TargetName from refs where RefKind='create' and SourceType in ('MICROFLOW','NANOFLOW') and TargetType='ENTITY'"):
        created.setdefault(s, set()).add(t)
    events = {}
    for s, t in db.execute("select SourceName, TargetName from refs where RefKind='event' and SourceType='ENTITY' and TargetType='MICROFLOW'"):
        events.setdefault(s, []).append(t)
    parent_ent = {}
    for s, t in db.execute("select SourceName, TargetName from refs where RefKind='generalize' and SourceType='ENTITY'"):
        parent_ent[s] = t
    autoattrs = {}
    if auto_rule:
        for e, n in db.execute("select EntityQualifiedName, Name from attributes where DataType=?", (auto_rule['pattern'],)):
            autoattrs.setdefault(e, []).append(n)
    known = set(r[0] for r in db.execute("select QualifiedName from microflows"))
    try:
        known |= set(r[0] for r in db.execute("select QualifiedName from nanoflows"))
    except sqlite3.Error:
        pass
    known |= set(calls)

    acts = {}
    if act_rules:
        ph = ','.join('?' * len(act_rules))
        for mf, at in db.execute("select distinct MicroflowQualifiedName, ActionType from activities_data where ActionType in (%s)" % ph, tuple(act_rules)):
            acts.setdefault(mf, set()).add(at)

    # walk: parent pointers give one shortest path per reached flow
    parent, via, order = {}, {}, []
    q = deque()
    java_known = set(t for v in calls.values() for t, tt in v if tt == 'JAVA_ACTION')
    for r in roots:
        if r in java_known and r not in known:   # `call java action X.Y` as a test root
            parent[r] = None
            order.append(r)
            continue
        if r not in known:
            out['unknownRoots'].append(r)
            continue
        parent[r] = None
        q.append(r)
    stop = set()   # call targets that are themselves the effect: reached, not descended
    while q:
        f = q.popleft()
        order.append(f)
        nxt = []
        for t, tt in calls.get(f, []):
            if call_match(t):
                continue
            nxt.append((t, tt, None))
        for ent in touches.get(f, ()):
            e, guard = ent, set()
            while e and e not in guard:   # handlers on a parent entity fire for its children too
                guard.add(e)
                for h in events.get(e, []):
                    nxt.append((h, 'MICROFLOW', 'event on ' + (e if e == ent else '%s, parent of %s' % (e, ent))))
                e = parent_ent.get(e)
        for t, tt, why in nxt:
            if t in parent or tt not in FLOW_TYPES + ('JAVA_ACTION',):
                continue
            parent[t] = f
            via[t] = why
            if tt in FLOW_TYPES:
                q.append(t)
            else:
                order.append(t)

    def path_of(f):
        p = []
        while f is not None:
            p.append(f + (' (%s)' % via[f] if via.get(f) else ''))
            f = parent[f]
        p.reverse()
        return p

    lines, seen = [], set()
    def add(cls, effect, flow, detail, rule, note=''):
        key = (cls, effect, flow, detail)
        if key in seen:
            return
        seen.add(key)
        lines.append(dict(cls=cls, effect=effect, flow=flow, detail=detail, path=path_of(flow),
                          proof=rule['proof'].split(':')[0] if rule else '', note=note))

    def extends_filedoc(ent):
        guard = 0
        while ent and guard < 20:
            if ent == fd_rule['pattern']:
                return True
            ent = parent_ent.get(ent)
            guard += 1
        return False

    for f in order:
        if parent.get(f, 0) is None and f in java_known and f not in known:
            r = call_match(f)
            if r:
                add(r['cls'], r['effect'], f, f, r, r['note'])
            continue
        if f not in calls and f not in acts and f not in touches:
            continue
        for at in sorted(acts.get(f, ())):
            r = act_rules[at]
            add(r['cls'], r['effect'], f, at, r, r['note'])
        for t, tt in calls.get(f, []):
            r = call_match(t)
            if r:
                add(r['cls'], r['effect'], f, t, r, r['note'])
            for r in type_rules:
                if tt == r['pattern']:
                    add(r['cls'], r['effect'], f, t, r, r['note'])
        if auto_rule:
            for ent in sorted(created.get(f, ())):
                for a in autoattrs.get(ent, []):
                    add(auto_rule['cls'], auto_rule['effect'], f, '%s.%s' % (ent, a), auto_rule, auto_rule['note'])
        if fd_rule:
            for ent in sorted(created.get(f, ())):
                if extends_filedoc(ent) and ent != fd_rule['pattern']:
                    add(fd_rule['cls'], fd_rule['effect'], f, ent, fd_rule, fd_rule['note'])
    # class U: java actions that no row classifies, once each, capped
    listed = set()
    for f in order:
        for t, tt in calls.get(f, []):
            if tt == 'JAVA_ACTION' and not call_match(t) and not t.startswith('System.') and t not in listed and not any(fnmatch.fnmatchcase(t, g) for g in ignore):
                listed.add(t)
                if len(listed) <= U_CAP:
                    lines.append(dict(cls='U', effect='UNLISTED-JAVA', flow=f, detail=t, path=path_of(f), proof='', note='not in rollback-effects.tsv; read its source if it writes, sends or commits'))
    extra = max(0, len(listed) - U_CAP)

    lines.sort(key=lambda d: ('ABU'.index(d['cls']) if d['cls'] in 'ABU' else 9, d['effect'], d['flow'], d['detail']))
    out['reached'] = len(order)
    out['effects'] = lines
    out['seconds'] = round(time.time() - t0, 3)

    if as_json:
        print(json.dumps(out, indent=2))
        return 0
    text = []
    text.append('rollback-scan: %d root flow(s)%s · %d flow(s) reached · %d effect line(s) · %.2fs'
                % (len(roots), (' from %d test file(s)' % len(files)) if files else '', len(order), len(lines), out['seconds']))
    for w in out['warnings']:
        text.append('  warning: ' + w)
    for r in out['unknownRoots']:
        text.append('  not in catalog: %s (no such flow, or the catalog is older than the test)' % r)
    for b in bad:
        text.append('  ignored: %s (not a file and not Module.Flow)' % b)
    for d in lines:
        p = d['path']
        shown = ' > '.join(p if len(p) <= 6 else p[:2] + ['...'] + p[-3:])
        text.append('%s  %-13s %s  [%s]  via %s%s' % (d['cls'], d['effect'], d['flow'], d['detail'], shown,
                                                    ('  -- ' + d['note']) if d['note'] else ''))
    if extra:
        text.append('U  ... and %d more unlisted Java action(s)' % extra)
    if not lines:
        text.append('  no listed effect reached.')
    text.append('Read as: rollback does NOT undo the A lines (and B lines are leftovers, usually ignorable). '
                'A line may be gated by a constant or a decision; read the flow. Not: the test is unsafe.')
    print('\n'.join(text))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
