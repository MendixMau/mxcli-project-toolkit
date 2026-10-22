"""render.py - turn extract.py graphs into ONE self-contained HTML page.

usage: python3 -I render.py OUT.html --model NAME=graph.json [--model ...] [--diff NAME=before.json,after.json]
Inline SVG for everything that has stored positions (domain models, microflows, diff overlays);
Mermaid (one pinned script from jsdelivr) only for the auto-laid-out call/wiring graph and the
fidelity comparison. Without network the SVG sections still render; the Mermaid blocks show source.
"""
import sys, json, html, time

MERMAID = 'https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs'
esc = lambda s: html.escape(str(s if s is not None else ''), quote=True)

# ---------------------------------------------------------------- domain model
def ent_box(e):
    rows = [f"{a['name']}: {a['type']}" + (f"({a['len']})" if a['type'] == 'String' and a.get('len') else '') for a in e['attrs']]
    w = max(150, 7.2 * max([len(e['name']) + 2] + [len(r) for r in rows]) + 20)
    h = 26 + 17 * max(1, len(rows)) + 6
    return w, h, rows

def domain_svg(mod, diff=None):
    ents = mod['entities']
    if not ents: return ''
    boxes = {e['id']: (e, *ent_box(e)) for e in ents}
    ghosts = []
    if diff:  # removed entities + old positions of moved ones
        for e in diff.get('ent_removed', []): ghosts.append((e, *ent_box(e), 'g-removed'))
        for e in diff.get('ent_old', []): ghosts.append((e, *ent_box(e), 'g-old'))
    allb = list(boxes.values()) + [(g[0], g[1], g[2], g[3]) for g in ghosts]
    xs = [b[0]['loc'][0] for b in allb] + [b[0]['loc'][0] + b[1] for b in allb]
    ys = [b[0]['loc'][1] for b in allb] + [b[0]['loc'][1] + b[2] for b in allb]
    x0, y0, x1, y1 = min(xs) - 40, min(ys) - 40, max(xs) + 40, max(ys) + 40
    out = [f'<svg class="dm" viewBox="{x0} {y0} {x1 - x0} {y1 - y0}" width="{x1 - x0}" role="img"><title>domain model</title>']
    for e, w, h, rows, cls in ghosts:
        x, y = e['loc']
        out.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="4"/><text class="gl" x="{x + 8}" y="{y - 6}">{"removed" if cls == "g-removed" else "was here"}: {esc(e["name"])}</text>')
    for a in mod['associations']:
        p = boxes.get(a['parent']); c = boxes.get(a['child'])
        if not p: continue
        px, py = p[0]['loc'][0] + p[1] * a['pc'][0] / 100, p[0]['loc'][1] + p[2] * a['pc'][1] / 100
        if c:
            cx, cy = c[0]['loc'][0] + c[1] * a['cc'][0] / 100, c[0]['loc'][1] + c[2] * a['cc'][1] / 100
        else:  # cross-module: stub line + label
            cx, cy = px + 120, py
            out.append(f'<text class="xm" x="{cx + 4}" y="{cy + 4}">{esc(a["child_qn"])}</text>')
        many_child = a['type'] == 'ReferenceSet'
        out.append(f'<line class="as" x1="{px}" y1="{py}" x2="{cx}" y2="{cy}"/>')
        out.append(f'<text class="mult" x="{px + (8 if cx > px else -14)}" y="{py - 5}">*</text>'
                   f'<text class="mult" x="{cx + (-14 if cx > px else 8)}" y="{cy - 5}">{"*" if many_child else "1"}</text>')
        out.append(f'<text class="al" x="{(px + cx) / 2}" y="{(py + cy) / 2 - 6}" text-anchor="middle">{esc(a["name"])}</text>')
    byname = {e['name']: b for b in boxes.values() for e in [b[0]]}
    for e, w, h, rows in boxes.values():
        g = e.get('generalization')
        if g and g.split('.')[-1] in byname and g.split('.')[0] == g.split('.')[0]:
            pe, pw, ph, _ = byname[g.split('.')[-1]]
            out.append(f'<line class="gen" x1="{e["loc"][0] + w / 2}" y1="{e["loc"][1]}" x2="{pe["loc"][0] + pw / 2}" y2="{pe["loc"][1] + ph}" marker-end="url(#tri)"/>')
    for e, w, h, rows in boxes.values():
        x, y = e['loc']
        st = (diff or {}).get('ent_state', {}).get(e['id'], '')
        out.append(f'<g class="ent {e["kind"]} {st}"><rect class="body" x="{x}" y="{y}" width="{w}" height="{h}" rx="4"/>'
                   f'<path class="hdr" d="M{x} {y + 24}V{y + 4}a4 4 0 0 1 4-4H{x + w - 4}a4 4 0 0 1 4 4V{y + 24}Z"/>'
                   f'<text class="en" x="{x + 8}" y="{y + 16}">{esc(e["name"])}</text>')
        if e.get('generalization'):
            out.append(f'<text class="gn" x="{x + w - 6}" y="{y + 16}" text-anchor="end">▲ {esc(e["generalization"])}</text>')
        changed_attrs = (diff or {}).get('attr_state', {})
        for i, r in enumerate(rows):
            a = e['attrs'][i]
            out.append(f'<text class="at {changed_attrs.get(a["id"], "")}" x="{x + 10}" y="{y + 40 + 17 * i}">{esc(r)}</text>')
        out.append('</g>')
    for n in mod.get('annotations', []):
        x, y = n['loc']
        out.append(f'<foreignObject x="{x}" y="{y}" width="{n["w"]}" height="60"><div class="note">{esc(n["text"])}</div></foreignObject>')
    out.append('</svg>')
    return ''.join(out)

# ---------------------------------------------------------------- microflow
SIDE = {0: (0, -0.5), 1: (0.5, 0), 2: (0, 0.5), 3: (-0.5, 0)}

def anchor(o, idx):
    dx, dy = SIDE.get(idx, (0.5, 0))
    return o['x'] + dx * o['w'], o['y'] + dy * o['h']

def wrap(s, n=17, lines=3):
    words, out, cur = str(s).split(), [], ''
    for w in words:
        w = w if len(w) <= n else w[:n - 1] + '…'
        if len(cur) + len(w) + 1 > n and cur: out.append(cur); cur = w
        else: cur = (cur + ' ' + w).strip()
    if cur: out.append(cur)
    return out[:lines] if len(out) <= lines else out[:lines - 1] + [out[lines - 1][:n - 1] + '…']

def flow_svg(f, diff=None):
    objs = {o['id']: o for o in f['objects']}
    if not objs: return ''
    st = (diff or {}).get('obj_state', {})
    old = (diff or {}).get('obj_old', [])
    pool = list(objs.values()) + old
    x0 = min(o['x'] - o['w'] / 2 for o in pool) - 70; x1 = max(o['x'] + o['w'] / 2 for o in pool) + 40
    y0 = min(o['y'] - o['h'] / 2 for o in pool) - 40; y1 = max(o['y'] + o['h'] / 2 for o in pool) + 40
    out = [f'<svg class="mf" viewBox="{x0} {y0} {x1 - x0} {y1 - y0}" width="{x1 - x0}" role="img"><title>{esc(f["qn"])}</title>']
    for o in [o for o in f['objects'] if o['type'] == 'LoopedActivity']:
        x, y = o['x'] - o['w'] / 2, o['y'] - o['h'] / 2
        out.append(f'<rect class="loop" x="{x}" y="{y}" width="{o["w"]}" height="{o["h"]}" rx="6"/><text class="ll" x="{x + 8}" y="{y + 14}">⟳ {esc(o["label"])}</text>')
    for o in old:
        out.append(f'<rect class="g-old" x="{o["x"] - o["w"] / 2}" y="{o["y"] - o["h"] / 2}" width="{o["w"]}" height="{o["h"]}" rx="6"/>')
    for fl in f['flows']:
        a, b = objs.get(fl['from']), objs.get(fl['to'])
        if not a or not b: continue
        (ax, ay), (bx, by) = anchor(a, fl['oi']), anchor(b, fl['di'])
        if fl.get('ann'):
            out.append(f'<line class="annf" x1="{a["x"]}" y1="{a["y"]}" x2="{b["x"]}" y2="{b["y"]}"/>'); continue
        c1 = (ax + fl['ocv'][0], ay + fl['ocv'][1]); c2 = (bx + fl['dcv'][0], by + fl['dcv'][1])
        cls = 'fl err' if fl.get('err') else 'fl'
        out.append(f'<path class="{cls}" d="M{ax} {ay}C{c1[0]} {c1[1]} {c2[0]} {c2[1]} {bx} {by}" marker-end="url(#arr)"/>')
        if fl.get('label'):  # place on the curve at t=0.25, like Studio Pro puts case labels near the split
            t = 0.25; u = 1 - t
            lx = u**3*ax + 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t**3*bx; ly = u**3*ay + 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t**3*by
            out.append(f'<text class="cl" x="{lx + 4}" y="{ly - 5}">{esc(fl["label"])}</text>')
    for o in f['objects']:
        t, x, y, w, h = o['type'], o['x'], o['y'], o['w'], o['h']
        s = st.get(o['id'], '')
        if t == 'StartEvent':
            out.append(f'<circle class="start {s}" cx="{x}" cy="{y}" r="{w / 2}"/>')
        elif t in ('EndEvent', 'ErrorEvent'):
            out.append(f'<circle class="end {s}" cx="{x}" cy="{y}" r="{w / 2}"/>')
            if o.get('label'): out.append(f'<text class="sm" x="{x}" y="{y + h / 2 + 12}" text-anchor="middle">{esc(o["label"][:24])}</text>')
        elif t in ('ExclusiveSplit', 'InheritanceSplit', 'ExclusiveMerge'):
            cls = 'merge' if t == 'ExclusiveMerge' else 'split'
            out.append(f'<path class="{cls} {s}" d="M{x} {y - h / 2}L{x + w / 2} {y}L{x} {y + h / 2}L{x - w / 2} {y}Z"/>')
            for i, line in enumerate(wrap(o.get('label', ''), 16, 2)):
                out.append(f'<text class="tx" x="{x}" y="{y + 4 + (i - 0.5) * 12}" text-anchor="middle">{esc(line)}</text>')
        elif t == 'Parameter':
            out.append(f'<path class="param {s}" d="M{x - 15} {y - 10}H{x + 15}L{x + 10} {y + 10}H{x - 20}Z"/><text class="sm" x="{x}" y="{y + 24}" text-anchor="middle">{esc(o["label"])}</text>')
        elif t == 'Annotation':
            out.append(f'<foreignObject x="{x - w / 2}" y="{y - h / 2}" width="{w}" height="{h}"><div class="note">{esc(o["label"])}</div></foreignObject>')
        elif t == 'LoopedActivity':
            pass
        else:
            cls = 'act' + (' dis' if o.get('disabled') else '') + f' k-{(o.get("kind") or "x").replace(" ", "")}'
            out.append(f'<g class="{cls} {s}"><rect x="{x - w / 2}" y="{y - h / 2}" width="{w}" height="{h}" rx="6"/>')
            lines = wrap(o.get('label') or t, 17, 3)
            for i, line in enumerate(lines):
                out.append(f'<text class="tx" x="{x}" y="{y + 4 + (i - (len(lines) - 1) / 2) * 13}" text-anchor="middle">{esc(line)}</text>')
            out.append('</g>')
    out.append('</svg>')
    return ''.join(out)

# ---------------------------------------------------------------- mermaid
mid = lambda s: 'n_' + ''.join(ch if ch.isalnum() else '_' for ch in s)

def callgraph_mermaid(g):
    lines = ['flowchart LR']
    nodes = {}
    for f in g['flows']: nodes[f['qn']] = 'nf' if f['kind'] == 'Nanoflow' else 'mf'
    for p in g['pages']: nodes[p['qn']] = 'pg'
    used = {a for e in g['edges'] for a in e[:2]}
    for qn, k in nodes.items():
        if qn not in used: continue
        sh = {'mf': f'{mid(qn)}["{qn}"]', 'nf': f'{mid(qn)}(["{qn}"])', 'pg': f'{mid(qn)}[/"{qn}"/]'}[k]
        lines.append(f'  {sh}:::{k}')
    for a, b, kind in g['edges']:
        if b not in nodes: lines.append(f'  {mid(b)}["{b}"]:::ext'); nodes[b] = 'ext'
        lines.append(f'  {mid(a)} -->|{kind}| {mid(b)}')
    lines += ['  classDef mf fill:#e8f1fc,stroke:#4a7cc2', '  classDef nf fill:#efe7fb,stroke:#7c5cc4',
              '  classDef pg fill:#e7f6ec,stroke:#3c9a5f', '  classDef ext fill:#f2f2f2,stroke:#999,stroke-dasharray:3 3']
    return '\n'.join(lines)

def er_mermaid(mod_name, mod):
    L = ['erDiagram']
    ids = {e['id']: e['name'] for e in mod['entities']}
    for e in mod['entities']:
        L.append(f'  {e["name"]} {{'); L += [f'    {a["type"]} {a["name"]}' for a in e['attrs']]; L.append('  }')
    for a in mod['associations']:
        c = ids.get(a['child']) or (a['child_qn'] or 'Ext').replace('.', '_')
        L.append(f'  {ids.get(a["parent"], "Ext")} {"}o--o{" if a["type"] == "ReferenceSet" else "}o--||"} {c} : "{a["name"]}"')
    return '\n'.join(L)

def flow_mermaid(f):
    L = ['flowchart LR']
    for o in f['objects']:
        lbl = (o.get('label') or o['type']).replace('"', "'")[:40]
        t = o['type']
        shape = f'(("{t[:5]}"))' if t in ('StartEvent', 'EndEvent') else f'{{"{lbl}"}}' if 'Split' in t or 'Merge' in t else f'["{lbl}"]'
        L.append(f'  {mid(o["id"])}{shape}')
    for fl in f['flows']:
        if fl.get('ann'): continue
        L.append(f'  {mid(fl["from"])} -->{"|" + fl["label"] + "|" if fl.get("label") else ""} {mid(fl["to"])}')
    return '\n'.join(L)

# ---------------------------------------------------------------- diff
def diff_graphs(A, B):
    res = {'dm': {}, 'mf': {}, 'summary': []}
    for m, mb in B['modules'].items():
        ma = A['modules'].get(m, {'entities': []})
        ea = {e['id']: e for e in ma['entities']}; eb = {e['id']: e for e in mb['entities']}
        d = {'ent_state': {}, 'attr_state': {}, 'ent_old': [], 'ent_removed': [ea[i] for i in ea if i not in eb]}
        for i, e in eb.items():
            if i not in ea: d['ent_state'][i] = 'd-added'; res['summary'].append(f'+ entity {m}.{e["name"]}'); continue
            o = ea[i]
            if o['loc'] != e['loc']: d['ent_state'][i] = 'd-moved'; d['ent_old'].append(o); res['summary'].append(f'~ entity {m}.{e["name"]} moved {o["loc"]} → {e["loc"]}')
            aa = {a['id']: a for a in o['attrs']}
            for a in e['attrs']:
                if a['id'] not in aa: d['attr_state'][a['id']] = 'd-added'; res['summary'].append(f'+ attribute {m}.{e["name"]}.{a["name"]}')
                elif aa[a['id']] != a:
                    d['attr_state'][a['id']] = 'd-changed'; d['ent_state'].setdefault(i, 'd-changed')
                    res['summary'].append(f'~ attribute {m}.{e["name"]}.{aa[a["id"]]["name"]} → {a["name"]} ({a["type"]})')
            for x in set(aa) - {a['id'] for a in e['attrs']}: res['summary'].append(f'- attribute {m}.{e["name"]}.{aa[x]["name"]}')
        for e in d['ent_removed']: res['summary'].append(f'- entity {m}.{e["name"]}')
        if d['ent_state'] or d['ent_removed']: res['dm'][m] = d
    fa = {f['qn']: f for f in A['flows']}
    for f in B['flows']:
        o = fa.get(f['qn'])
        if not o: res['summary'].append(f'+ {f["kind"].lower()} {f["qn"]}'); continue
        oa = {x['id']: x for x in o['objects']}; ob = {x['id']: x for x in f['objects']}
        d = {'obj_state': {}, 'obj_old': []}
        for i, x in ob.items():
            if i not in oa: d['obj_state'][i] = 'd-added'; res['summary'].append(f'+ {f["qn"]}: {x["type"]} "{x.get("label", "")}"')
            else:
                y = oa[i]
                if (y['x'], y['y']) != (x['x'], x['y']): d['obj_state'][i] = 'd-moved'; d['obj_old'].append(y); res['summary'].append(f'~ {f["qn"]}: "{x.get("label") or x["type"]}" moved ({y["x"]:.0f},{y["y"]:.0f}) → ({x["x"]:.0f},{x["y"]:.0f})')
                if y.get('label') != x.get('label'): d['obj_state'][i] = 'd-changed'; res['summary'].append(f'~ {f["qn"]}: caption "{y.get("label")}" → "{x.get("label")}"')
        for i in set(oa) - set(ob): d['obj_old'].append(oa[i]); res['summary'].append(f'- {f["qn"]}: {oa[i]["type"]} "{oa[i].get("label", "")}"')
        if d['obj_state'] or d['obj_old']: res['mf'][f['qn']] = d
    for q in set(fa) - {f['qn'] for f in B['flows']}: res['summary'].append(f'- flow {q}')
    return res

# ---------------------------------------------------------------- page
CSS = r'''
:root{--bg:#f7f8fa;--panel:#fff;--ink:#1d2433;--mute:#5d6676;--line:#d6dbe3;--acc:#2f6fd0;
--ent-p:#2f6fd0;--ent-n:#e07b16;--ent-v:#2e9b5b;--ent-x:#7c4dc4;--act:#eaf2fd;--act-s:#5b8fd6;--split:#fff3cf;--split-s:#d6a200;
--start:#43a047;--end:#e53935;--loop:#8a94a6;--note:#fff9db;--add:#1f9d55;--chg:#d08a00;--rem:#d33;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#14171c;--panel:#1c2027;--ink:#e6e9ef;--mute:#9aa3b2;--line:#323844;
--act:#1f2b3d;--act-s:#6f9be0;--split:#3a3218;--note:#3a3519}}
:root[data-theme="dark"]{--bg:#14171c;--panel:#1c2027;--ink:#e6e9ef;--mute:#9aa3b2;--line:#323844;--act:#1f2b3d;--act-s:#6f9be0;--split:#3a3218;--note:#3a3519}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
main{max-width:1200px;margin:0 auto;padding:24px 16px 64px}h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:32px 0 8px;border-bottom:1px solid var(--line);padding-bottom:6px}
h3{font-size:14px;margin:18px 0 6px;font-family:ui-monospace,Menlo,monospace}.mute{color:var(--mute)}
.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px;overflow:auto;margin-bottom:10px}
.card svg{max-width:100%;height:auto;display:block}details>summary{cursor:pointer;color:var(--mute);margin:6px 0}
pre{white-space:pre-wrap;font-size:12px;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:8px;overflow:auto}
table{border-collapse:collapse;font-size:13px}td,th{border:1px solid var(--line);padding:4px 8px;text-align:left}
nav a{color:var(--acc);margin-right:12px}ul.chg{font-family:ui-monospace,Menlo,monospace;font-size:12.5px}
svg text{font-family:system-ui,-apple-system,Segoe UI,sans-serif;fill:var(--ink)}
.ent .body{fill:var(--panel);stroke:var(--line);stroke-width:1.2}.ent .hdr{fill:var(--ent-p)}.ent.nonpersistent .hdr{fill:var(--ent-n)}
.ent.view .hdr{fill:var(--ent-v)}.ent.external .hdr{fill:var(--ent-x)}.ent .en{fill:#fff;font-weight:600;font-size:12.5px}.ent .gn{fill:#fff;font-size:10px;opacity:.85}
.ent .at{font-size:11.5px}.as{stroke:var(--mute);stroke-width:1.4}.gen{stroke:var(--mute);stroke-width:1.4}.mult,.al,.xm,.gl{font-size:10.5px;fill:var(--mute)}
.mf .act rect{fill:var(--act);stroke:var(--act-s);stroke-width:1.3}.mf .act.dis rect{stroke-dasharray:4 3;opacity:.6}
.mf .act.k-Call rect{stroke:#7c4dc4}.mf .act.k-Showpage rect,.mf .act.k-Closepage rect{stroke:#2e9b5b}
.split,.merge{fill:var(--split);stroke:var(--split-s);stroke-width:1.3}.start{fill:var(--start)}.end{fill:var(--end)}
.param{fill:var(--split);stroke:var(--split-s)}.loop{fill:none;stroke:var(--loop);stroke-dasharray:5 4;stroke-width:1.3}
.tx{font-size:11px}.sm,.cl,.ll{font-size:10.5px;fill:var(--mute)}.fl{fill:none;stroke:var(--mute);stroke-width:1.3}.fl.err{stroke:var(--rem);stroke-dasharray:5 3}
.annf{stroke:var(--mute);stroke-dasharray:2 3}.note{background:var(--note);border:1px solid var(--split-s);font-size:11px;padding:4px;border-radius:3px;height:100%;overflow:hidden}
.d-added rect,.d-added .body,rect.d-added{stroke:var(--add)!important;stroke-width:3!important}.d-moved rect,.d-moved .body,path.d-moved,circle.d-moved{stroke:var(--chg)!important;stroke-width:3!important}
.d-changed rect,.d-changed .body{stroke:var(--chg)!important;stroke-width:3!important}text.d-changed{fill:var(--chg);font-weight:700}text.d-added{fill:var(--add);font-weight:700}
.g-old{fill:none;stroke:var(--chg);stroke-dasharray:4 4;stroke-width:1.5}.g-removed{fill:none;stroke:var(--rem);stroke-dasharray:4 4;stroke-width:1.5}
.legend span{display:inline-block;margin-right:14px;font-size:12px}.sw{display:inline-block;width:12px;height:12px;border-radius:2px;vertical-align:-1px;margin-right:4px}
'''

DEFS = '''<svg width="0" height="0" style="position:absolute"><defs>
<marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#8a94a6"/></marker>
<marker id="tri" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="10" markerHeight="10" orient="auto"><path d="M0 0L12 6L0 12z" fill="none" stroke="#8a94a6"/></marker>
</defs></svg>'''

def main():
    args = sys.argv[1:]; out = args[0]; models = []; diffs = []
    i = 1
    while i < len(args):
        if args[i] == '--model': n, p = args[i + 1].split('='); models.append((n, json.load(open(p))))
        if args[i] == '--diff': n, p = args[i + 1].split('='); a, b = p.split(','); diffs.append((n, json.load(open(a)), json.load(open(b))))
        i += 2
    t0 = time.time(); body = []
    body.append('<h1>Mendix model viewer — prototype</h1><p class="mute">Public test models from mendixlabs/mxcli testdata only. Domain models and microflows are drawn at the positions Studio Pro stored; the call graph is auto-laid-out by Mermaid.</p>')
    body.append('<nav>' + ''.join(f'<a href="#m-{n}">{esc(n)}</a>' for n, _ in models) + ''.join(f'<a href="#d-{n}">diff: {esc(n)}</a>' for n, _, _ in diffs) + '</nav>')
    body.append('<p class="legend"><span><i class="sw" style="background:var(--ent-p)"></i>persistent</span><span><i class="sw" style="background:var(--ent-n)"></i>non-persistent</span><span><i class="sw" style="background:var(--ent-v)"></i>view</span><span><i class="sw" style="background:var(--ent-x)"></i>external</span><span><i class="sw" style="border:2px solid var(--add)"></i>added</span><span><i class="sw" style="border:2px solid var(--chg)"></i>moved/changed</span><span><i class="sw" style="border:2px dashed var(--rem)"></i>removed</span></p>')
    for name, g in models:
        body.append(f'<h2 id="m-{esc(name)}">{esc(name)}</h2>')
        nE = sum(len(m['entities']) for m in g['modules'].values())
        body.append(f'<p class="mute">{len(g["modules"])} modules · {nE} entities · {len(g["flows"])} microflows/nanoflows · {len(g["pages"])} pages/snippets · {len(g["edges"])} wiring edges</p>')
        body.append('<h3>Domain models (stored positions)</h3>')
        for m, mod in sorted(g['modules'].items()):
            svg = domain_svg(mod)
            if svg: body.append(f'<h3>{esc(m)}</h3><div class="card">{svg}</div>')
        body.append('<h3>Call graph and page → microflow wiring (Mermaid, auto layout)</h3>')
        body.append(f'<div class="card"><pre class="mermaid">{esc(callgraph_mermaid(g))}</pre></div>')
        body.append('<h3>Microflows and nanoflows (stored positions)</h3>')
        for f in sorted(g['flows'], key=lambda f: -len(f['objects'])):
            body.append(f'<details {"open" if len(f["objects"]) >= 12 else ""}><summary>{esc(f["qn"])} — {f["kind"].lower()}, {len(f["objects"])} objects</summary><div class="card">{flow_svg(f)}</div></details>')
        big = max(g['flows'], key=lambda f: len(f['objects']))
        mods = [m for m in g['modules'] if g['modules'][m]['entities']]
        body.append(f'<h3>Fidelity comparison: the same content through Mermaid</h3><p class="mute">{esc(big["qn"])} as a Mermaid flowchart (positions discarded), and the {esc(mods[0])} domain model as a Mermaid erDiagram.</p>')
        body.append(f'<div class="card"><pre class="mermaid">{esc(flow_mermaid(big))}</pre></div><div class="card"><pre class="mermaid">{esc(er_mermaid(mods[0], g["modules"][mods[0]]))}</pre></div>')
    for name, A, B in diffs:
        d = diff_graphs(A, B)
        body.append(f'<h2 id="d-{esc(name)}">Model diff: {esc(name)}</h2><p class="mute">Computed by element $ID from two git revisions. `git diff` itself only says "Bin 10663 → 10663 bytes" for these files.</p>')
        body.append('<ul class="chg">' + ''.join(f'<li>{esc(s)}</li>' for s in d['summary']) + '</ul>')
        for m, dd in d['dm'].items():
            body.append(f'<h3>{esc(m)} domain model (after, with before ghosts)</h3><div class="card">{domain_svg(B["modules"][m], dd)}</div>')
        fb = {f['qn']: f for f in B['flows']}
        for q, dd in d['mf'].items():
            body.append(f'<h3>{esc(q)} (after, with before ghosts)</h3><div class="card">{flow_svg(fb[q], dd)}</div>')
    render_ms = (time.time() - t0) * 1000
    body.append(f'<p class="mute">Rendered in {render_ms:.0f} ms.</p>')
    page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mendix Model Viewer</title><style>{CSS}</style></head><body>{DEFS}<main>{"".join(body)}</main>
<script type="module">
try {{ const m = (await import('{MERMAID}')).default;
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  m.initialize({{startOnLoad:false, theme: dark ? 'dark' : 'default', securityLevel:'strict', maxTextSize:200000}});
  await m.run({{querySelector:'pre.mermaid'}}); }} catch (e) {{ console.warn('mermaid unavailable, source left visible', e); }}
</script></body></html>'''
    open(out, 'w').write(page)
    print(f'wrote {out} ({len(page) / 1024:.0f} KB, render {render_ms:.0f} ms)')

if __name__ == '__main__':
    main()
