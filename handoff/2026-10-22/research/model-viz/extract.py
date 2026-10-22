"""extract.py - read an MPR v2 project (.mpr index + mprcontents/*.mxunit) into a small JSON graph.

Prototype for the model-visualization research. Read-only. No dependencies beyond the stdlib.
Sources:   a working tree  (path to the folder holding the .mpr)
           or a git revision (repo dir + rev), read with `git show` / `git cat-file --batch`.
Output:    {modules:{name:{entities,associations,annotations}}, flows:[...], pages:[...], edges:[...]}
Positions are kept exactly as stored (entity Location, activity RelativeMiddlePoint + Size,
flow connection indexes + Bezier control vectors), so a renderer can reproduce Studio Pro's layout.
"""
import sys, os, json, glob, sqlite3, uuid, subprocess, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bsonlite

def pt(s, default=(0, 0)):
    if not s or ';' not in str(s): return list(default)
    a, b = str(s).split(';')[:2]; return [float(a), float(b)]

def items(lst):  # Mendix BSON arrays carry a leading int "kind" marker
    return [x for x in (lst or []) if isinstance(x, dict)]

class WorkTree:
    def __init__(self, root):
        self.root = root
        self.mpr = glob.glob(os.path.join(root, '*.mpr'))[0]
    def mpr_path(self): return self.mpr
    def units(self):
        for f in glob.glob(os.path.join(self.root, 'mprcontents', '**', '*.mxunit'), recursive=True):
            yield os.path.basename(f)[:-7], open(f, 'rb').read()

class GitRev:
    def __init__(self, repo, rev):
        self.repo, self.rev = repo, rev
    def _git(self, *a, inp=None):
        return subprocess.run(['git', '-C', self.repo, *a], input=inp, capture_output=True, check=True).stdout
    def mpr_path(self):
        name = [p for p in self._git('ls-tree', '--name-only', self.rev).decode().split('\n') if p.endswith('.mpr')][0]
        fd, tmp = tempfile.mkstemp(suffix='.mpr'); os.write(fd, self._git('show', f'{self.rev}:{name}')); os.close(fd)
        return tmp
    def units(self):
        paths = [p for p in self._git('ls-tree', '-r', '--name-only', self.rev, 'mprcontents').decode().split('\n') if p.endswith('.mxunit')]
        out = self._git('cat-file', '--batch', inp=''.join(f'{self.rev}:{p}\n' for p in paths).encode())
        i = 0
        for p in paths:  # parse "<sha> blob <size>\n<content>\n"
            nl = out.index(b'\n', i); size = int(out[i:nl].split()[2]); body = out[nl + 1: nl + 1 + size]; i = nl + 1 + size + 1
            yield os.path.basename(p)[:-7], body

ACTION_KEYS = ['Microflow', 'Nanoflow', 'Form', 'Page', 'JavaAction', 'JavaScriptAction', 'Entity',
               'AssociationId', 'ChangeVariableName', 'CommitVariableName', 'DeleteVariableName', 'VariableName', 'RefreshVariableName']

def find_key(o, keys, depth=0):
    if depth > 4 or not isinstance(o, dict): return None
    for k in keys:
        v = o.get(k)
        if isinstance(v, str) and v: return v
    for v in o.values():
        if isinstance(v, dict):
            r = find_key(v, keys, depth + 1)
            if r: return r
    return None

def action_label(o):
    a = o.get('Action') or {}
    t = a.get('$Type', '').split('$')[-1]; t = t[:-6] if t.endswith('Action') else t
    t = {'ShowForm': 'Show page', 'CloseForm': 'Close page', 'CreateChange': 'Create', 'MicroflowCall': 'Call',
         'NanoflowCall': 'Call', 'JavaActionCall': 'Java', 'JavaScriptActionCall': 'JS', 'Retrieve': 'Retrieve', 'ValidationFeedback': 'Validation',
         'ShowMessage': 'Message', 'LogMessage': 'Log', 'RestCall': 'REST call'}.get(t, t)
    target = find_key(a, ACTION_KEYS) or ''
    if o.get('Caption') and not o.get('AutoGenerateCaption', True): return o['Caption'], t, target
    short = target.split('.')[-1] if '.' in target else (('$' + target) if target and t in ('Change', 'Commit', 'Delete', 'CreateVariable', 'ChangeVariable') else target)
    return (f'{t} {short}'.strip()), t, target

def collect_refs(o, out, keys=('Microflow', 'Nanoflow', 'Form', 'Page')):
    if isinstance(o, dict):
        for k in keys:
            v = o.get(k)
            if isinstance(v, str) and '.' in v: out.add((k, v))
        for v in o.values(): collect_refs(v, out, keys)
    elif isinstance(o, list):
        for v in o: collect_refs(v, out, keys)

def flow_objects(coll, offset=(0, 0), parent=None):
    objs = []
    for o in items((coll or {}).get('Objects')):
        t = o['$Type'].split('$')[-1]
        c = pt(o.get('RelativeMiddlePoint')); s = pt(o.get('Size'), (20, 20))
        c = [c[0] + offset[0], c[1] + offset[1]]
        n = {'id': o['$ID'], 'type': t, 'x': c[0], 'y': c[1], 'w': s[0], 'h': s[1], 'parent': parent}
        if t == 'ActionActivity':
            n['label'], n['kind'], n['target'] = action_label(o)
            n['disabled'] = o.get('Disabled', False)
        elif t in ('ExclusiveSplit', 'InheritanceSplit'):
            n['label'] = o.get('Caption') or find_key(o.get('SplitCondition') or {}, ['Expression']) or ''
        elif t == 'Annotation':
            n['label'] = o.get('Caption', '')
        elif t in ('MicroflowParameterObject', 'MicroflowParameter'):
            n['label'] = o.get('Name', ''); n['type'] = 'Parameter'
        elif t == 'LoopedActivity':
            ls = o.get('LoopSource') or {}
            n['label'] = f"{ls.get('VariableName', '')} in ${ls.get('ListVariableName', '')}" if ls.get('ListVariableName') else 'while'
            objs.append(n)
            objs += flow_objects(o.get('ObjectCollection'), (c[0] - s[0] / 2, c[1] - s[1] / 2), o['$ID'])
            continue
        elif t == 'EndEvent':
            n['label'] = o.get('ReturnValue', '')
        objs.append(n)
    return objs

def extract(src):
    con = sqlite3.connect(f'file:{src.mpr_path()}?mode=ro', uri=True)
    container = {str(uuid.UUID(bytes_le=u)): (str(uuid.UUID(bytes_le=c)) if c else None)
                 for u, c in con.execute('select UnitID, ContainerID from Unit')}
    docs = {uid: bsonlite.loads(b) for uid, b in src.units()}
    names = {uid: d.get('Name') for uid, d in docs.items()}
    def module_of(uid):
        seen = 0
        while uid and seen < 50:
            d = docs.get(uid)
            if d and d['$Type'] == 'Projects$ModuleImpl': return d['Name']
            uid = container.get(uid); seen += 1
        return None
    g = {'modules': {}, 'flows': [], 'pages': [], 'edges': []}
    ent_qn = {}
    for uid, d in docs.items():
        if d['$Type'] != 'DomainModels$DomainModel': continue
        m = module_of(uid)
        for e in items(d.get('Entities')): ent_qn[e['$ID']] = f'{m}.{e["Name"]}'
    for uid, d in docs.items():
        t = d['$Type']; m = module_of(uid)
        if t == 'DomainModels$DomainModel':
            mod = g['modules'].setdefault(m, {})
            ents = []
            for e in items(d.get('Entities')):
                gen = e.get('MaybeGeneralization') or {}
                src_t = (e.get('Source') or {}).get('$Type', '') if isinstance(e.get('Source'), dict) else ''
                kind = 'view' if 'OqlView' in src_t else 'external' if src_t else (
                    'persistent' if gen.get('$Type') == 'DomainModels$Generalization' or gen.get('Persistable', True) else 'nonpersistent')
                ents.append({'id': e['$ID'], 'name': e['Name'], 'loc': pt(e.get('Location')), 'kind': kind,
                             'generalization': gen.get('Generalization') if gen.get('$Type') == 'DomainModels$Generalization' else None,
                             'attrs': [{'id': a['$ID'], 'name': a['Name'], 'type': a['NewType']['$Type'].split('$')[-1].replace('AttributeType', ''),
                                        'len': a['NewType'].get('Length')} for a in items(e.get('Attributes'))]})
            assocs = []
            for a in items(d.get('Associations')) + items(d.get('CrossAssociations')):
                assocs.append({'id': a['$ID'], 'name': a['Name'], 'type': a.get('Type'), 'owner': a.get('Owner'),
                               'parent': a.get('ParentPointer'), 'child': a.get('ChildPointer') or a.get('Child'),
                               'pc': pt(a.get('ParentConnection'), (50, 50)), 'cc': pt(a.get('ChildConnection'), (50, 50)),
                               'cross': 'Child' in a and 'ChildPointer' not in a})
            anns = [{'id': a['$ID'], 'text': a.get('Caption', ''), 'loc': pt(a.get('Location')), 'w': a.get('Width', 200)}
                    for a in items(d.get('Annotations'))]
            mod.update(entities=ents, associations=assocs, annotations=anns)
        elif t in ('Microflows$Microflow', 'Microflows$Nanoflow', 'Microflows$Rule'):
            qn = f'{m}.{d["Name"]}'
            objs = flow_objects(d.get('ObjectCollection'))
            flows = []
            for f in items(d.get('Flows')):
                line = f.get('Line') or {}
                cases = [c.get('Value') for c in items(f.get('CaseValues')) if c.get('Value') is not None]
                flows.append({'id': f['$ID'], 'from': f.get('OriginPointer'), 'to': f.get('DestinationPointer'),
                              'oi': f.get('OriginConnectionIndex', 1), 'di': f.get('DestinationConnectionIndex', 3),
                              'ocv': pt(line.get('OriginControlVector')), 'dcv': pt(line.get('DestinationControlVector')),
                              'err': f.get('IsErrorHandler', False), 'label': ','.join(cases)})
            for f in items(d.get('AnnotationFlows')):
                flows.append({'id': f['$ID'], 'from': f.get('OriginPointer'), 'to': f.get('DestinationPointer'), 'ann': True,
                              'oi': f.get('OriginConnectionIndex', 1), 'di': f.get('DestinationConnectionIndex', 3), 'ocv': [0, 0], 'dcv': [0, 0]})
            g['flows'].append({'qn': qn, 'module': m, 'kind': t.split('$')[1], 'objects': objs, 'flows': flows})
            for o in objs:
                if o.get('kind') == 'Call' and o.get('target'): g['edges'].append([qn, o['target'], 'calls'])
                if o.get('kind') == 'Show page' and o.get('target'): g['edges'].append([qn, o['target'], 'opens'])
        elif t in ('Forms$Page', 'Forms$Snippet'):
            qn = f'{m}.{d["Name"]}'; refs = set(); collect_refs(d, refs, ('Microflow', 'Nanoflow'))
            g['pages'].append({'qn': qn, 'module': m, 'kind': t.split('$')[1]})
            for k, v in sorted(refs): g['edges'].append([qn, v, 'uses'])
    for m in g['modules'].values():  # resolve association endpoints to qualified names
        for a in m['associations']:
            a['parent_qn'] = ent_qn.get(a['parent']); a['child_qn'] = ent_qn.get(a['child'], a['child'])
    return g

if __name__ == '__main__':
    src = GitRev(sys.argv[2], sys.argv[3]) if sys.argv[1] == '--git' else WorkTree(sys.argv[1])
    json.dump(extract(src), sys.stdout, indent=1)
