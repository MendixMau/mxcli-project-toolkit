"""contract-check.py — the engine behind bin/contract-check.sh. Read that file's header first;
this one documents only the internals.

Two mxcli calls per app, both read-only on the model (mxcli refreshes its own catalog cache,
.mxcli/catalog.db beside the .mpr — nothing else is written):

  1. one `-c` string of SELECTs over the catalog tables listed in QUERIES, with --json. mxcli
     prints one JSON array per statement on stdout (counts and warnings go to stderr), so the
     output is parsed as a sequence of JSON values and must hold exactly len(QUERIES) of them.
     A statement error makes mxcli exit non-zero and stop: that is exit 2 here, never a partial
     snapshot.
  2. `describe odata service X;` per published OData service, with --json — one object per
     service whose "mdl" field holds the service text. The catalog has no table of published
     OData members, so the exposed members are parsed from that text and then RESOLVED against
     catalog.attributes / catalog.associations of the published entity (and its
     generalizations). A member the service still names but the entity no longer has is
     "resolved": false — mxcli's `impact` and `refs` do not see OData exposure, and `check` and
     `exec` stay green when an exposed attribute is dropped (measured 2026-11-05, mxcli v0.28.0),
     so resolution is the only thing that catches it.

Replay: MXTK_CONTRACT_MXCLI may name any executable that answers like mxcli; the fixture uses a
shim that replays captured mxcli output (tests/wave2/fixtures/contract-check/).
"""
import json
import os
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse

SCHEMA = "mxtk-contracts/1"

QUERIES = [
    ("odata_pub", "select QualifiedName, Path, Version, ODataVersion from catalog.published_odata_services"),
    ("rest_pub", "select QualifiedName, Path, Version from catalog.published_rest_services"),
    ("rest_pub_ops", "select ServiceQualifiedName, ResourceName, HttpMethod, Path, Microflow, Deprecated from catalog.published_rest_operations"),
    ("rest_con", "select QualifiedName, BaseUrl from catalog.consumed_rest_services"),
    ("rest_con_ops", "select ServiceQualifiedName, Name, HttpMethod, Path from catalog.consumed_rest_operations"),
    ("odata_con", "select QualifiedName, MetadataUrl, Version from catalog.consumed_odata_services"),
    ("ext_entities", "select QualifiedName, ServiceName, EntitySet, RemoteName from catalog.external_entities"),
    ("be_services", "select QualifiedName, ServiceName, EventNamePrefix from catalog.business_event_services"),
    ("be_messages", "select ServiceQualifiedName, MessageName, Entity, CanPublish, CanSubscribe from catalog.business_events"),
    ("entities", "select QualifiedName, Generalization from catalog.entities"),
    ("attributes", "select EntityQualifiedName, Name, DataType, EnumerationQualifiedName from catalog.attributes"),
    ("associations", "select QualifiedName, Name, FromEntity, ToEntity from catalog.associations"),
    ("constants", "select QualifiedName, DefaultValue from catalog.constants"),
]


def die(msg, code=2):
    sys.stderr.write("contract-check: " + msg + "\n")
    sys.exit(code)


# --- registry -------------------------------------------------------------------------------

def read_registry(path):
    if not os.path.isfile(path):
        die("no system registry at %s (pass --registry FILE or set MXTK_SYSTEM_REGISTRY)" % path)
    base = os.path.dirname(os.path.abspath(path))
    apps, seen = [], set()
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 3:
                die("%s:%d: need at least 3 TAB-separated columns (name, path, role), got %d" % (path, n, len(cols)))
            name, p, role = cols[0].strip(), cols[1].strip(), cols[2].strip()
            url = cols[3].strip() if len(cols) > 3 else ""
            if not re.match(r"^[A-Za-z0-9_-]+$", name):
                die("%s:%d: app name %r must be letters, digits, _ or - (it names the snapshot file)" % (path, n, name))
            if name in seen:
                die("%s:%d: app %r listed twice" % (path, n, name))
            if role not in ("publisher", "consumer", "both"):
                die("%s:%d: role %r is not publisher|consumer|both" % (path, n, role))
            seen.add(name)
            full = p if os.path.isabs(p) else os.path.normpath(os.path.join(base, p))
            apps.append({"name": name, "path": full, "role": role, "url": url})
    if not apps:
        die("registry %s lists no apps" % path)
    return apps


def resolve_mpr(p):
    """A registry path is the .mpr itself or a project root (single-tree: *.mpr at the root;
    two-tree: the app under app/). Exactly one .mpr, or the caller is told which ones."""
    if os.path.isfile(p) and p.lower().endswith(".mpr"):
        return p
    if not os.path.isdir(p):
        return None
    for d in (p, os.path.join(p, "app")):
        if os.path.isdir(d):
            found = sorted(x for x in os.listdir(d) if x.lower().endswith(".mpr"))
            if len(found) == 1:
                return os.path.join(d, found[0])
            if len(found) > 1:
                die("%s holds %d .mpr files (%s); name the one you mean in the registry" % (d, len(found), ", ".join(found)))
    return None


def find_mxcli(mpr):
    env = os.environ.get("MXTK_CONTRACT_MXCLI") or os.environ.get("MXCLI")
    if env:
        return env
    root = os.path.dirname(mpr)
    cands = [root, os.path.dirname(root)]
    for d in cands:
        # Windows first: a Linux ELF `mxcli` left by a container must not shadow mxcli.exe.
        for n in (("mxcli.exe", "mxcli") if os.name == "nt" else ("mxcli",)):
            c = os.path.join(d, n)
            if os.path.isfile(c) and os.access(c, os.X_OK):
                return c
    return shutil.which("mxcli")


# --- extraction -----------------------------------------------------------------------------

def json_values(text):
    dec, i, out = json.JSONDecoder(), 0, []
    while True:
        while i < len(text) and text[i] not in "[{":
            i += 1
        if i >= len(text):
            return out
        v, i = dec.raw_decode(text, i)
        out.append(v)


def run_mxcli(mx, mpr, stmts):
    try:
        # a .sh stand-in (the fixture's replay shim) runs through bash: Windows cannot exec it
        argv = (["bash", mx] if mx.endswith(".sh") else [mx])
        r = subprocess.run(argv + ["-p", mpr, "--json", "-c", stmts], capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=600)
    except (OSError, subprocess.TimeoutExpired) as e:
        die("could not run %s on %s: %s" % (mx, mpr, e))
    if r.returncode != 0:
        die("mxcli exited %d on %s:\n%s" % (r.returncode, mpr, r.stderr.strip()[-2000:]))
    return r.stdout, r.stderr


def norm_path(*parts):
    segs = []
    for p in parts:
        for s in (p or "").split("/"):
            if s:
                segs.append(s)
    return "/" + "/".join(segs)


def template(path):
    # /orders/{id} and /orders/{orderId} are the same route
    return re.sub(r"\{[^}]*\}", "{}", path.rstrip("/") or "/").lower()


def major(v):
    m = re.match(r"\s*v?(\d+)", v or "")
    return m.group(1) if m else (v or "")


def type_of(a):
    t = a.get("DataType", "")
    if a.get("EnumerationQualifiedName"):
        t += "(" + a["EnumerationQualifiedName"] + ")"
    return t


def parse_odata_mdl(mdl):
    """-> [(entity, set_name, [(source, exposed, key)])], unparsed_lines"""
    sets, cur, in_expose, unparsed = [], None, False, []
    for raw in mdl.splitlines():
        line = raw.strip()
        m = re.match(r"publish entity\s+(\S+)\s+as\s+'([^']*)'", line, re.I)
        if m:
            cur = (m.group(1), m.group(2), [])
            sets.append(cur)
            in_expose = False
            continue
        if re.match(r"expose\s*\(", line, re.I):
            in_expose = True
            continue
        if in_expose:
            if line.startswith(")"):
                in_expose = False
                continue
            m = re.match(r"(\S+)\s+as\s+'([^']*)'\s*(\(([^)]*)\))?", line)
            if m and cur:
                opts = [o.strip().upper() for o in (m.group(4) or "").split(",")]
                cur[2].append((m.group(1), m.group(2), "KEY" in opts))
            elif line:
                unparsed.append(line)
        elif re.match(r"publish\s+", line, re.I):
            unparsed.append(line)   # a publish kind this parser does not know: named, never dropped
    return sets, unparsed


def extract(app):
    mpr = resolve_mpr(app["path"])
    if not mpr:
        die("app %s: no .mpr at %s (registry path is the .mpr or a project root holding one at the root or under app/)" % (app["name"], app["path"]))
    mx = find_mxcli(mpr)
    if not mx:
        die("no mxcli found (set MXCLI, put ./mxcli beside the app, or put mxcli on PATH)")
    out, err = run_mxcli(mx, mpr, " ".join(q + ";" for _, q in QUERIES))
    vals = json_values(out)
    if len(vals) != len(QUERIES):
        die("app %s: expected %d result sets from mxcli, got %d — this mxcli's catalog differs from the one this was written against (v0.28.0)" % (app["name"], len(QUERIES), len(vals)))
    T = {k: v for (k, _), v in zip(QUERIES, vals)}

    gen = {e["QualifiedName"]: e.get("Generalization", "") for e in T["entities"]}
    attrs = {}
    for a in T["attributes"]:
        attrs.setdefault(a["EntityQualifiedName"], {})[a["Name"]] = type_of(a)
    assocs = {}
    for a in T["associations"]:
        for side in ("FromEntity", "ToEntity"):
            assocs.setdefault(a[side], {})[a["Name"]] = "Association(%s)" % a["ToEntity" if side == "FromEntity" else "FromEntity"]
            assocs[a[side]][a["QualifiedName"]] = assocs[a[side]][a["Name"]]

    def member_type(entity, name):
        seen = set()
        e = entity
        while e and e not in seen:
            seen.add(e)
            if name in attrs.get(e, {}):
                return attrs[e][name]
            if name in assocs.get(e, {}):
                return assocs[e][name]
            e = gen.get(e, "")
        return None

    unparsed_all = []
    odata = []
    names = sorted(s["QualifiedName"] for s in T["odata_pub"])
    described = {}
    if names:
        dout, _ = run_mxcli(mx, mpr, " ".join("describe odata service %s;" % n for n in names))
        for v in json_values(dout):
            if isinstance(v, dict) and "mdl" in v:
                described[v.get("name")] = v["mdl"]
    for s in sorted(T["odata_pub"], key=lambda s: s["QualifiedName"]):
        qn = s["QualifiedName"]
        if qn not in described:
            die("app %s: describe odata service %s returned nothing" % (app["name"], qn))
        sets, unparsed = parse_odata_mdl(described[qn])
        unparsed_all += ["%s: %s" % (qn, u) for u in unparsed]
        es = []
        for ent, sname, mem in sets:
            members = []
            for src, exp, key in mem:
                t = member_type(ent, src)
                members.append({"name": exp, "source": src, "key": key, "type": t or "", "resolved": t is not None})
            es.append({"name": sname, "entity": ent, "members": sorted(members, key=lambda m: m["name"])})
        odata.append({"service": qn, "path": norm_path(s["Path"]), "version": s["Version"],
                      "odata_version": s.get("ODataVersion", ""), "entity_sets": sorted(es, key=lambda e: e["name"])})

    rest = []
    for s in sorted(T["rest_pub"], key=lambda s: s["QualifiedName"]):
        ops = []
        for o in T["rest_pub_ops"]:
            if o["ServiceQualifiedName"] != s["QualifiedName"]:
                continue
            ops.append({"method": o["HttpMethod"].upper(), "path": norm_path(s["Path"], o["ResourceName"], o["Path"]),
                        "resource": o["ResourceName"], "microflow": o.get("Microflow", ""),
                        "deprecated": o.get("Deprecated", "0") not in ("0", "", "false")})
        rest.append({"service": s["QualifiedName"], "path": norm_path(s["Path"]), "version": s["Version"],
                     "operations": sorted(ops, key=lambda o: (o["path"], o["method"]))})

    bes = []
    for s in sorted(T["be_services"], key=lambda s: s["QualifiedName"]):
        msgs = []
        for m in T["be_messages"]:
            if m["ServiceQualifiedName"] != s["QualifiedName"]:
                continue
            at = [{"name": n, "type": t} for n, t in sorted(attrs.get(m["Entity"], {}).items())]
            msgs.append({"name": m["MessageName"], "entity": m["Entity"], "attributes": at,
                         "can_publish": m.get("CanPublish") == "1", "can_subscribe": m.get("CanSubscribe") == "1"})
        bes.append({"service": s["QualifiedName"], "service_name": s.get("ServiceName", ""),
                    "prefix": s.get("EventNamePrefix", ""), "messages": sorted(msgs, key=lambda m: m["name"])})

    consts = {c["QualifiedName"]: c.get("DefaultValue", "") for c in T["constants"]}

    def url_of(v):
        if v and "://" not in v and v in consts:
            return consts[v], "constant " + v
        return v or "", "literal"

    crest = []
    for s in sorted(T["rest_con"], key=lambda s: s["QualifiedName"]):
        base, src = url_of(s.get("BaseUrl", ""))
        bpath = urlparse(base).path if "://" in base else ""
        ops = [{"name": o["Name"], "method": o["HttpMethod"].upper(), "op_path": o["Path"],
                "path": norm_path(bpath, o["Path"])}
               for o in T["rest_con_ops"] if o["ServiceQualifiedName"] == s["QualifiedName"]]
        crest.append({"service": s["QualifiedName"], "base_url": base, "base_url_source": src,
                      "operations": sorted(ops, key=lambda o: o["name"])})

    codata = []
    for s in sorted(T["odata_con"], key=lambda s: s["QualifiedName"]):
        meta, src = url_of(s.get("MetadataUrl", ""))
        ees = []
        for e in T["ext_entities"]:
            if e["ServiceName"] != s["QualifiedName"]:
                continue
            at = [{"name": n, "type": t} for n, t in sorted(attrs.get(e["QualifiedName"], {}).items())]
            ees.append({"entity": e["QualifiedName"], "entity_set": e.get("EntitySet", ""),
                        "remote_name": e.get("RemoteName", ""), "attributes": at})
        codata.append({"service": s["QualifiedName"], "metadata_url": meta, "metadata_url_source": src,
                       "version": s.get("Version", ""), "external_entities": sorted(ees, key=lambda e: e["entity"])})

    return {"schema": SCHEMA, "app": app["name"],
            "published": {"odata": odata, "rest": rest, "business_events": bes},
            "consumed": {"rest": crest, "odata": codata},
            "unparsed": sorted(unparsed_all)}


def dump(snap):
    return json.dumps(snap, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def counts(s):
    p, c = s["published"], s["consumed"]
    return ("published: %d OData service(s) / %d entity set(s) / %d member(s), %d REST service(s) / %d operation(s), "
            "%d business event service(s) / %d message(s); consumed: %d REST client(s) / %d operation(s), "
            "%d OData client(s) / %d external entit(y/ies)") % (
        len(p["odata"]), sum(len(o["entity_sets"]) for o in p["odata"]),
        sum(len(e["members"]) for o in p["odata"] for e in o["entity_sets"]),
        len(p["rest"]), sum(len(r["operations"]) for r in p["rest"]),
        len(p["business_events"]), sum(len(b["messages"]) for b in p["business_events"]),
        len(c["rest"]), sum(len(r["operations"]) for r in c["rest"]),
        len(c["odata"]), sum(len(o["external_entities"]) for o in c["odata"]))


# --- diff: publisher side -------------------------------------------------------------------

def diff_app(name, base, cur, out):
    """Appends (kind, text) rows; returns the number of VIOLATIONs."""
    viol = 0

    def svc_map(s, k):
        return {x["service"]: x for x in s["published"][k]}

    for kind, label in (("rest", "REST"), ("odata", "OData")):
        b, c = svc_map(base, kind), svc_map(cur, kind)
        for qn in sorted(set(b) | set(c)):
            if qn not in c:
                out.append(("BREAKING", "%s:%s %s service removed (was %s, version %s)" % (name, qn, label, b[qn]["path"], b[qn]["version"])))
                continue
            if qn not in b:
                out.append(("ADDITIVE", "%s:%s new %s service %s" % (name, qn, label, c[qn]["path"])))
                continue
            bs, cs, brk = b[qn], c[qn], []
            if bs["path"] != cs["path"]:
                brk.append("path %s -> %s" % (bs["path"], cs["path"]))
            if kind == "rest":
                bo = {(o["method"], o["path"]): o for o in bs["operations"]}
                co = {(o["method"], o["path"]): o for o in cs["operations"]}
                gone, new = sorted(set(bo) - set(co)), sorted(set(co) - set(bo))
                for k in gone:
                    ren = [n for n in new if co[n]["microflow"] and co[n]["microflow"] == bo[k]["microflow"]]
                    brk.append("operation %s %s removed%s" % (k[0], k[1], (" (renamed to %s %s? same microflow)" % ren[0]) if ren else ""))
                for k in new:
                    out.append(("ADDITIVE", "%s:%s operation %s %s added" % (name, qn, k[0], k[1])))
            else:
                bset = {e["name"]: e for e in bs["entity_sets"]}
                cset = {e["name"]: e for e in cs["entity_sets"]}
                for sn in sorted(set(bset) - set(cset)):
                    ren = [n for n in set(cset) - set(bset) if cset[n]["entity"] == bset[sn]["entity"]]
                    brk.append("entity set '%s' removed%s" % (sn, (" (renamed to '%s'? same entity)" % ren[0]) if ren else ""))
                for sn in sorted(set(cset) - set(bset)):
                    out.append(("ADDITIVE", "%s:%s entity set '%s' added" % (name, qn, sn)))
                for sn in sorted(set(bset) & set(cset)):
                    bm = {m["name"]: m for m in bset[sn]["members"]}
                    cm = {m["name"]: m for m in cset[sn]["members"]}
                    for mn in sorted(set(bm) - set(cm)):
                        brk.append("'%s'.%s no longer exposed" % (sn, mn))
                    for mn in sorted(set(cm) - set(bm)):
                        out.append(("ADDITIVE", "%s:%s '%s'.%s exposed" % (name, qn, sn, mn)))
                    for mn in sorted(set(bm) & set(cm)):
                        x, y = bm[mn], cm[mn]
                        if x["resolved"] and not y["resolved"]:
                            brk.append("'%s'.%s still exposed but %s.%s no longer exists (attribute dropped from the entity)" % (sn, mn, cset[sn]["entity"], y["source"]))
                        elif x["resolved"] and y["resolved"] and x["type"] != y["type"]:
                            brk.append("'%s'.%s type %s -> %s" % (sn, mn, x["type"], y["type"]))
                        if x["key"] != y["key"]:
                            brk.append("'%s'.%s KEY %s -> %s" % (sn, mn, x["key"], y["key"]))
            for t in brk:
                out.append(("BREAKING", "%s:%s %s" % (name, qn, t)))
            if brk and major(bs["version"]) == major(cs["version"]):
                viol += 1
                out.append(("VIOLATION", "%s:%s %d breaking change(s) with major version unchanged (%s -> %s); bump the major version and publish on a new path, keeping the old one until every consumer moved" % (name, qn, len(brk), bs["version"], cs["version"])))
            elif bs["version"] != cs["version"]:
                out.append(("VERSION", "%s:%s version %s -> %s" % (name, qn, bs["version"], cs["version"])))

    b = {x["service"]: x for x in base["published"]["business_events"]}
    c = {x["service"]: x for x in cur["published"]["business_events"]}
    for qn in sorted(set(b) | set(c)):
        if qn not in c:
            out.append(("BREAKING", "%s:%s business event service removed (no version field in the model: no bump check)" % (name, qn)))
            continue
        if qn not in b:
            out.append(("ADDITIVE", "%s:%s new business event service" % (name, qn)))
            continue
        bm = {m["name"]: m for m in b[qn]["messages"]}
        cm = {m["name"]: m for m in c[qn]["messages"]}
        for mn in sorted(set(bm) - set(cm)):
            out.append(("BREAKING", "%s:%s message %s removed (no version field in the model: no bump check)" % (name, qn, mn)))
        for mn in sorted(set(cm) - set(bm)):
            out.append(("ADDITIVE", "%s:%s message %s added" % (name, qn, mn)))
        for mn in sorted(set(bm) & set(cm)):
            ba = {a["name"]: a["type"] for a in bm[mn]["attributes"]}
            ca = {a["name"]: a["type"] for a in cm[mn]["attributes"]}
            for an in sorted(set(ba) - set(ca)):
                out.append(("BREAKING", "%s:%s message %s attribute %s removed" % (name, qn, mn, an)))
            for an in sorted(set(ba) & set(ca)):
                if ba[an] != ca[an]:
                    out.append(("BREAKING", "%s:%s message %s attribute %s type %s -> %s" % (name, qn, mn, an, ba[an], ca[an])))
    return viol


def dangling(name, snap, out):
    n = 0
    for o in snap["published"]["odata"]:
        for e in o["entity_sets"]:
            for m in e["members"]:
                if not m["resolved"]:
                    n += 1
                    out.append(("DANGLING", "%s:%s '%s'.%s exposes %s.%s, which the entity does not have" % (name, o["service"], e["name"], m["name"], e["entity"], m["source"])))
    return n


# --- cross-app join -------------------------------------------------------------------------

def host_of(url):
    return urlparse(url).netloc.lower() if "://" in (url or "") else ""


def join(apps, snaps):
    """Every consumed REST operation and external entity, resolved against every OTHER app's
    published services. Returns rows [(status, consumer_app, consumer_elem, publisher_app,
    publisher_service, publisher_elem, detail)]."""
    url = {a["name"]: host_of(a["url"]) for a in apps}
    rows = []
    for a in apps:
        cn = a["name"]
        for cs in snaps[cn]["consumed"]["rest"]:
            chost = host_of(cs["base_url"])
            for op in cs["operations"]:
                elem = "%s.%s" % (cs["service"], op["name"])
                if not cs["base_url"]:
                    rows.append(("UNRESOLVED", cn, elem, "", "", "", "base URL is empty or an unresolved constant"))
                    continue
                svc_hits = []
                for p in apps:
                    if p["name"] == cn or (url[p["name"]] and chost and url[p["name"]] != chost):
                        continue
                    for ps in snaps[p["name"]]["published"]["rest"]:
                        if template(op["path"]).startswith(template(ps["path"]) + "/") or template(op["path"]) == template(ps["path"]):
                            svc_hits.append((p["name"], ps))
                if not svc_hits:
                    rows.append(("EXTERNAL", cn, elem, "", "", "", "%s %s: no app in the registry publishes this path" % (op["method"], op["path"])))
                    continue
                if len({h[0] for h in svc_hits}) > 1:
                    rows.append(("AMBIGUOUS", cn, elem, ",".join(sorted({h[0] for h in svc_hits})), "", "", "%s %s matches services in several apps; add the url column to the registry" % (op["method"], op["path"])))
                    continue
                hit = [(pn, ps, po) for pn, ps in svc_hits for po in ps["operations"]
                       if po["method"] == op["method"] and template(po["path"]) == template(op["path"])]
                if hit:
                    pn, ps, po = hit[0]
                    rows.append(("EDGE", cn, elem, pn, ps["service"], "%s %s" % (po["method"], po["path"]), "microflow " + po["microflow"]))
                else:
                    pn, ps = svc_hits[0]
                    rows.append(("BROKEN", cn, elem, pn, ps["service"], "", "%s %s: %s:%s serves %s but no such operation" % (op["method"], op["path"], pn, ps["service"], ps["path"])))
        for cs in snaps[cn]["consumed"]["odata"]:
            meta = cs["metadata_url"]
            mpath = template(re.sub(r"/?\$metadata$", "", urlparse(meta).path if "://" in meta else ""))
            mhost = host_of(meta)
            svc_hits = []
            for p in apps:
                if p["name"] == cn or (url[p["name"]] and mhost and url[p["name"]] != mhost):
                    continue
                for ps in snaps[p["name"]]["published"]["odata"]:
                    if mpath and template(ps["path"]) == mpath:
                        svc_hits.append((p["name"], ps))
            ees = cs["external_entities"] or [None]
            for ee in ees:
                elem = ee["entity"] if ee else cs["service"]
                if not mpath:
                    rows.append(("UNRESOLVED", cn, elem, "", "", "", "metadata URL is empty or an unresolved constant"))
                    continue
                if not svc_hits:
                    rows.append(("EXTERNAL", cn, elem, "", "", "", "%s: no app in the registry publishes this OData path" % mpath))
                    continue
                if len({h[0] for h in svc_hits}) > 1:
                    rows.append(("AMBIGUOUS", cn, elem, ",".join(sorted({h[0] for h in svc_hits})), "", "", "%s published by several apps; add the url column to the registry" % mpath))
                    continue
                pn, ps = svc_hits[0]
                if major(cs["version"]) != major(ps["version"]):
                    rows.append(("STALE", cn, cs["service"], pn, ps["service"], "", "consumer contract version %s, publisher now %s" % (cs["version"], ps["version"])))
                if not ee:
                    rows.append(("EDGE", cn, elem, pn, ps["service"], "", "no external entities"))
                    continue
                sets = {e["name"]: e for e in ps["entity_sets"]}
                es = sets.get(ee["entity_set"])
                if not es:
                    rows.append(("BROKEN", cn, elem, pn, ps["service"], "'%s'" % ee["entity_set"], "entity set '%s' not published by %s:%s" % (ee["entity_set"], pn, ps["service"])))
                    continue
                mem = {m["name"]: m for m in es["members"]}
                bad = []
                for at in ee["attributes"]:
                    m = mem.get(at["name"])
                    if not m:
                        bad.append("%s not exposed" % at["name"])
                    elif not m["resolved"]:
                        bad.append("%s exposed but dangling on the publisher (%s.%s does not exist)" % (at["name"], es["entity"], m["source"]))
                    elif m["type"].split("(")[0] != at["type"].split("(")[0]:
                        bad.append("%s type %s on the publisher, %s here" % (at["name"], m["type"], at["type"]))
                if bad:
                    rows.append(("BROKEN", cn, elem, pn, ps["service"], "'%s'" % es["name"], "; ".join(bad)))
                else:
                    rows.append(("EDGE", cn, elem, pn, ps["service"], "'%s'" % es["name"], "%d attribute(s) matched" % len(ee["attributes"])))
    return rows


def print_join(rows):
    for r in rows:
        st, cn, ce, pn, psvc, pe, det = r
        tgt = ("%s:%s %s" % (pn, psvc, pe)).strip() if psvc else (pn or "-")
        print("%-10s %s:%s -> %s  (%s)" % (st, cn, ce, tgt, det))
    tot = len([r for r in rows if r[0] != "STALE"])
    k = lambda s: len([r for r in rows if r[0] == s])
    print("denominator: %d/%d consumed REST operations and external entities resolved to a publisher in the registry "
          "(broken %d, external %d, ambiguous %d, unresolved %d, stale contract versions %d)" % (
              k("EDGE"), tot, k("BROKEN"), k("EXTERNAL"), k("AMBIGUOUS"), k("UNRESOLVED"), k("STALE")))


# --- baseline -------------------------------------------------------------------------------

def load_baseline(path, mode):
    d, f = os.path.dirname(path), os.path.basename(path)
    if mode in ("git", "auto"):
        try:
            tracked = subprocess.run(["git", "-C", d, "ls-files", "--error-unmatch", f], capture_output=True, text=True).returncode == 0
        except OSError:
            tracked = False
        if tracked:
            r = subprocess.run(["git", "-C", d, "show", "HEAD:./" + f], capture_output=True, text=True, encoding="utf-8")
            if r.returncode == 0:
                return json.loads(r.stdout), "git HEAD"
        if mode == "git":
            return None, "not committed"
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh), "file (not in git)"
    return None, "missing"


# --- impact ---------------------------------------------------------------------------------

def touchpoints(snap, elem):
    """Published contract members of one app that expose `elem` (Module.Entity,
    Module.Entity.Attribute, Module.Microflow, or a service's qualified name)."""
    tp = []
    parts = elem.split(".")
    ent = ".".join(parts[:2])
    attr = parts[2] if len(parts) > 2 else None
    for o in snap["published"]["odata"]:
        for e in o["entity_sets"]:
            if o["service"] == elem:
                tp.append(("odata", o["service"], e["name"], None))
            elif e["entity"] == ent:
                if attr is None:
                    tp.append(("odata", o["service"], e["name"], None))
                else:
                    for m in e["members"]:
                        if m["source"] == attr:
                            tp.append(("odata", o["service"], e["name"], m["name"]))
    for r in snap["published"]["rest"]:
        for op in r["operations"]:
            if r["service"] == elem or op["microflow"] == elem:
                tp.append(("rest", r["service"], "%s %s" % (op["method"], op["path"]), None))
    for b in snap["published"]["business_events"]:
        for m in b["messages"]:
            if b["service"] == elem or m["entity"] == ent:
                tp.append(("be", b["service"], m["name"], attr))
    return tp


# --- commands -------------------------------------------------------------------------------

def main():
    import argparse
    ap = argparse.ArgumentParser(prog="contract-check")
    ap.add_argument("cmd", nargs="?", choices=["snapshot", "check"])
    ap.add_argument("--registry", default=os.environ.get("MXTK_SYSTEM_REGISTRY") or "system.tsv")
    ap.add_argument("--contracts")
    ap.add_argument("--app")
    ap.add_argument("--baseline", choices=["auto", "git", "file"], default="auto")
    ap.add_argument("--impact")
    a = ap.parse_args()
    if not a.cmd and not a.impact:
        die("say snapshot, check or --impact <app>:<element> (see --help)")
    apps = read_registry(a.registry)
    cdir = a.contracts or os.path.join(os.path.dirname(os.path.abspath(a.registry)), "contracts")
    names = [x["name"] for x in apps]
    if a.app and a.app not in names:
        die("app %r is not in the registry (%s)" % (a.app, ", ".join(names)))

    snaps = {}
    for app in apps:
        snaps[app["name"]] = extract(app)

    if a.impact:
        if ":" not in a.impact:
            die("--impact takes <app>:<Module.Element>")
        an, elem = a.impact.split(":", 1)
        if an not in snaps:
            die("app %r is not in the registry (%s)" % (an, ", ".join(names)))
        tps = touchpoints(snaps[an], elem)
        rows = [r for r in join(apps, snaps) if r[3] == an and r[0] in ("EDGE", "BROKEN", "STALE")]
        if not tps:
            print("NOT-EXPOSED %s:%s is in no published OData, REST or business event contract of %s" % (an, elem, an))
            print("denominator: 0 contract members; 0 consumer apps")
            return 0
        consumers = set()
        for kind, svc, member, sub in tps:
            print("EXPOSED    %s:%s via %s %s%s" % (an, elem, svc, member, ("." + sub) if sub else ""))
            for r in rows:
                if r[4] != svc:
                    continue
                if kind == "odata" and r[5] and r[5] != "'%s'" % member:
                    continue
                if kind == "rest" and r[5] and r[5] != member:
                    continue
                if kind == "odata" and sub:
                    ee = [e for c in snaps[r[1]]["consumed"]["odata"] for e in c["external_entities"] if e["entity"] == r[2]]
                    if ee and sub not in [x["name"] for x in ee[0]["attributes"]]:
                        continue
                consumers.add(r[1])
                print("CONSUMER   %s:%s (%s)" % (r[1], r[2], r[0]))
        if [t for t in tps if t[0] == "be"]:
            print("NOTE       business event subscribers are not joined across apps (not implemented: no subscriber fixture)")
        print("denominator: %d contract member(s); %d consumer app(s) in a registry of %d: %s" % (
            len(tps), len(consumers), len(apps), ", ".join(sorted(consumers)) or "none"))
        print("note: `mxcli impact` / `refs` do not report OData exposure (measured on v0.28.0); this list is the cross-app answer")
        return 0

    if a.cmd == "snapshot":
        os.makedirs(cdir, exist_ok=True)
        for app in apps:
            if a.app and app["name"] != a.app:
                continue
            s = snaps[app["name"]]
            p = os.path.join(cdir, app["name"] + ".json")
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(dump(s))
            print("SNAPSHOT   %s -> %s" % (app["name"], p))
            print("           %s" % counts(s))
            for u in s["unparsed"]:
                print("UNPARSED   %s:%s" % (app["name"], u))
        print("next: commit %s — `check` compares against the committed copy" % cdir)
        return 0

    # check
    out, viol, missing = [], 0, []
    for app in apps:
        n = app["name"]
        base, src = load_baseline(os.path.join(cdir, n + ".json"), a.baseline)
        if base is None:
            missing.append("%s (%s)" % (n, src))
            continue
        out.append(("BASELINE", "%s: %s" % (n, src)))
        viol += diff_app(n, base, snaps[n], out)
    dang = sum(dangling(n, snaps[n], out) for n in names)
    for k, t in out:
        print("%-10s %s" % (k, t))
    for app in apps:
        for u in snaps[app["name"]]["unparsed"]:
            print("UNPARSED   %s:%s" % (app["name"], u))
    rows = join(apps, snaps)
    print_join(rows)
    broken = len([r for r in rows if r[0] == "BROKEN"])
    members = sum(len(e["members"]) for s in snaps.values() for o in s["published"]["odata"] for e in o["entity_sets"])
    brk = len([o for o in out if o[0] == "BREAKING"])
    print("summary: %d app(s); %d published OData member(s) resolved against their entity, %d dangling; "
          "%d BREAKING, %d VIOLATION, %d BROKEN consumer link(s)" % (len(apps), members, dang, brk, viol, broken))
    if missing:
        print("NOT RUN    no committed baseline for: %s — run `snapshot` and commit the contracts dir" % ", ".join(missing))
        return 2
    return 1 if (viol or broken or dang) else 0


if __name__ == "__main__":
    sys.exit(main())
