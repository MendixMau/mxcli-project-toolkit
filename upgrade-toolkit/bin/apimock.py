#!/usr/bin/env python3
"""apimock.py: a local stand-in for the external APIs an app consumes, read from its model (E2E-13, E2E-14, E2E-15).

A gate run must never call a real external system, and a call nobody answers must never pass as "no issues". Before
E2E-13 every journey or smoke step that touched Opcenter, an OData service or an SSO endpoint either called the real
system or failed on a dead host, and the gate could not tell an upgrade defect from a missing server. This script
reads the consumed APIs from the .mpr (mprmodel.py; no Studio Pro, no mxcli), points every endpoint constant at
itself, answers with bodies of the mapped shape, and logs every request. The old and the new app use the SAME
stand-in (pass both models), so their journeys see the same answers.

  apimock.py inventory <model> [<model> ...] [--exclude SYSTEM[=glob,...]] [--classify FILE] [--recorded DIR] [--json FILE]
  apimock.py serve <model> [<model> ...] --state DIR [--port 8790 (env UPG_APIMOCK_PORT)] [--bind ADDR] [--public-host HOST]
             [--exclude ...] [--classify FILE] [--recorded DIR] [--background]
  apimock.py stop --state DIR
  apimock.py check --state DIR [--exclude-systems Teamcenter,...]            the gate's "apis" rung
  apimock.py attribute-smoke <smoke-after.json> --state DIR --exclude-systems Teamcenter   (gate.sh, smoke rung rc 1)
  apimock.py standin --state DIR             the endpoints the stand-in answered for (gate.sh: never a plain PASS)

Inventory (per model; several models are merged by endpoint id):
  rest:<Microflow>[#n]   a Call REST action (Microflows$RestCallAction): method, URL template, the import mapping and
                         its JSON structure. The location's first template parameter is traced: @Module.Constant,
                         $Object/Attribute (data), $Variable (create/change variable in the flow, the argument every
                         caller passes for that parameter, the return value of a called sub-microflow, the constant
                         arguments of a Java action whose result it is; 3 levels), a literal URL.
  send:<Microflow>[#n]   Send REST request / REST operation call / consumed web service / call external action: the
                         location is traced the same way when the action carries a HttpConfiguration; otherwise every
                         constant the service document names. Shapes not yet seen on a real model: UNKNOWN unless a
                         constant routes them.
  odata:<Service>        a consumed OData service (Rest$ConsumedODataService): the stored $metadata is served, entity
                         sets answer two sample rows each, $count answers 2. Location: the service's CustomLocation
                         expression, else the constants its ConfigurationMicroflow (and the flows it calls) reads.
  const:<Module.Const>   a URL constant (value http(s)://..., or a String constant named *Url/*Uri/*Endpoint/
                         *Location/*Host/*Address) that no modelled call above reads: a Java action or a string built
                         at runtime may call it. Overridden like the others, UNKNOWN until classified.
  addon:<Module>         an add-on module (<project>/modules/<Module>.mxmodule, B4T2-6, B4N1-9): its packed model is not
                         a sqlite MPR and its flows are protected, so its calls cannot be read, and a location it builds
                         at runtime from entity data (EXFN_ServiceLayer: ClientConfiguration.OpcenterEXFNUrl + '/...')
                         is invisible. One UNKNOWN endpoint per add-on, so "unknown 0" is never claimed while add-ons
                         exist. The URL-named constants its files name (@EXFN_Authentication.APPBaseUrl) are routed and
                         overridden; the URL-named attributes it names are printed as candidate data locations.

Classification, one per endpoint:
  EXCLUDED <System>  --exclude matched its module, document, constant names or the host of its default URL. Built-in
                     patterns: Teamcenter = TcConnector*, Teamcenter*, *Teamcenter*, Viewer3D_TC*, *_TC, *teamcenter*
                     hosts. --exclude NAME=glob,glob gives your own. Excluded endpoints are still pointed at the
                     stand-in, which answers 503 "EXCLUDED: <System>": the real system is never called either way.
                     Only a system that cannot be stood in may be excluded (steps/gate.md): it is listed by name.
  MOCKED             every location of it is a constant this stand-in overrides, or a --classify line says so (with
                     a reason), or a recorded response exists for a constant-only endpoint. A MOCKED line on an
                     endpoint with no constant and no data location is refused (stays UNKNOWN, B4N1-9): the app could
                     not reach the stand-in, so "mocked" would be a claim nothing can prove.
  UNKNOWN            anything else (a location from data, a hard-coded URL no override reaches, a URL constant no
                     modelled call reads, a shape this reader does not know). UNKNOWN stays INVALID until someone
                     classifies it: --classify FILE lines "<fnmatch on endpoint id> MOCKED # reason" or
                     "<pattern> EXCLUDED <System> # reason" (reason required). A location from data is reachable by
                     setting that attribute to the printed /a/<Entity.Attr> URL in the seed data.
  A location the reader cannot see (an add-on constant, an add-on microflow building the URL from data) is declared:
    "<pattern> LOCATION const:<Module.Constant> # reason"   the constant is overridden (overrides.json, CONST_OVERRIDES
                                                            works for add-on constants too)
    "<pattern> LOCATION data:<Module.Entity.Attribute> # reason"   serve prints `data: set <Entity.Attr> to .../a/...`:
                                                            set that row in the seed data (the add-on appends its own
                                                            segments; an OData endpoint finds its entity set in them)
  It replaces the endpoint's unknown routes; a data location still needs a MOCKED line. An endpoint whose location can
  be neither declared nor redirected is not stood in: it stays UNKNOWN (INVALID), never MOCKED.
  "<pattern> UNEXERCISED # reason": a MOCKED endpoint no journey calls (check names it, waived, instead of INVALID).
Output: one line per endpoint, then `apis E found · mocked M · excluded X (System, ...) · unknown U`.
inventory exit: 0 = no UNKNOWN, 3 = UNKNOWN present (INVALID), 2 = input error.

serve: prints the constant overrides (`Module.Constant=http://HOST:PORT/c/Module.Constant`) and writes
<state>/overrides.json (runapp.py CONST_OVERRIDES), <state>/inventory.json, <state>/coverage.txt and appends every
request to <state>/requests.jsonl ({t, method, path, endpoint, status, system, code, match}). status MOCKED, EXCLUDED,
UNKNOWN (an UNKNOWN endpoint's constant was called) or UNMATCHED (no endpoint for the path, 404). Bodies are
deterministic (no clock, no random). A recorded response <recorded>/<id with non [A-Za-z0-9._-] as _>.json
({"status": 200, "content_type": "...", "body": ...}) overrides any endpoint's answer. --public-host is the host the
APP reaches (the Docker gateway for a runapp container), --bind the address to listen on: 127.0.0.1 by default, and
0.0.0.0 by default when --public-host is given (a runapp container cannot reach the host's 127.0.0.1; B4T2-5).

check (gate.sh rung "apis"): the inventory and the request log; prints `requests seen: N`. Exit 0 = nothing UNKNOWN,
no UNKNOWN or UNMATCHED request, nothing excluded, every MOCKED endpoint answered at least one request; 4 = the same
but endpoints excluded (each listed "NOT CHECKED (excluded: <System>) ..."); 3 = UNKNOWN endpoints or UNKNOWN /
UNMATCHED requests (INVALID); 2 = no state. An endpoint excluded for a system not in --exclude-systems is INVALID too
(the gate names what it excludes). B4N1-11: a MOCKED endpoint with 0 requests is "NOT EXERCISED" and INVALID unless an
UNEXERCISED line waives it with a reason; MOCKED endpoints with 0 requests answered IN TOTAL are INVALID with no
waiver (the stand-in was never shown reachable: Opcenter b4 passed this rung with 2 MOCKED endpoints and 0 requests).

A --classify EXCLUDED line (with its reason) makes its endpoints INFO, not stray: printed "INFO (excluded: <System>) ...:
check at deploy", exit 0 ("verdict: PASS (INFO: ...)"). Only an --exclude pattern without a classify line is "NOT CHECKED" (4).
check --direct DIR (apidirect.py compare's DIR/direct.json): every consumed REST call was run on the old and the new app
against this stand-in and compared (apidirect.py header, steps/apis.md). The endpoints it measured (PASS or FAIL) no
longer need a journey hit, and its verdict joins this one: a FAIL call is exit 1 (FAIL: the old and the new app differ),
an INVALID call exit 3 (could not be measured, with the reason). Requests the direct run sent carry call/side/mode in
the log (apidirect.py split-log moves them out, so the journey hits stay journey evidence).

attribute-smoke / attribute (run_journeys.py --apimock-log): a FAIL step whose time window holds a call into an
EXCLUDED system named in --exclude-systems, and no UNKNOWN or UNMATCHED call, is NOT CHECKED (excluded: <System>);
every other FAIL stays FAIL. attribute-smoke exit: 4 = every FAIL step is NOT CHECKED and nothing else is wrong, 1 =
a FAIL remains, 2 = no log or no step times.

standin (E2E-15; gate.sh, whenever APIMOCK is set): the stand-in is a stopgap, not the standard. A pass against a fake
API must never look like a pass against the real one, so gate.sh turns PASS into "PASS (on stand-in APIs: <systems>)",
exit 4, when this lists anything. One line per MOCKED endpoint, called or not (the app was pointed at the stand-in
either way, so it never talked to the real system): `  STAND-IN (<system>) endpoint <id>: N requests answered`, the
system being the endpoint's module unless a classification named one; then `stand-in systems: A, B` and
`stand-in endpoints E · requests answered R`. Exit 0 (whether or not anything was stood in), 2 = no state.
"""
import argparse, fnmatch, glob, json, os, re, signal, socket, subprocess, sys, threading, time, zipfile
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BUILTIN_EXCLUDE = {
    # needs a real Teamcenter server (SOA login, FMS tickets, the viewer's server-side rendering): no stand-in
    "teamcenter": ["TcConnector*", "Teamcenter*", "*Teamcenter*", "Viewer3D_TC*", "*_TC", "*_TC.*", "host:*teamcenter*",
                   "host:*.tc.*"],
}
URLISH = re.compile(r"^\s*'?(https?|ftp)://", re.I)
URLNAME = re.compile(r"(url|uri|endpoint|location|host|address|baseurl|serveraddress)$", re.I)
CONST_RE = re.compile(r"@([A-Za-z_]\w*\.[A-Za-z_]\w*)")
ATTR_RE = re.compile(r"^\$(\w+)/(\w+)$")
VAR_RE = re.compile(r"^\$(\w+)$")
LIT_RE = re.compile(r"^'((?:https?|ftp)://[^']*)'")
CALL_TYPES = ("Microflows$SendRestRequestAction", "Microflows$RestOperationCallAction",
              "Microflows$WebServiceCallAction", "Microflows$CallExternalAction")
FLOWS = ("Microflows$Microflow", "Microflows$Rule")
EXIT_INVALID, EXIT_EXCEPT = 3, 4


def die(msg):
    print(f"apimock: {msg}", file=sys.stderr)
    sys.exit(2)


def nodes(x, want=None):
    """Every dict under x (depth first), or those whose $Type is in want."""
    if isinstance(x, dict):
        if want is None or x.get("$Type") in want:
            yield x
        for v in x.values():
            yield from nodes(v, want)
    elif isinstance(x, list):
        for v in x:
            yield from nodes(v, want)


def safe(eid):
    return re.sub(r"[^A-Za-z0-9._-]", "_", eid)


# ------------------------------------------------------------------------------------------------ the model reader
class Reader:
    """Consumed APIs of one mprmodel.Model."""

    def __init__(self, m):
        self.m = m
        self.flows = {d.qn: d for d in m.of_type(*FLOWS)}
        self._calls = None

    # -- tracing a location expression to routes: ("const", qn) / ("attr", Entity.Attr) / ("literal", url) / ("unknown", why)
    def callers(self):
        if self._calls is None:
            self._calls = {}
            for qn, d in self.flows.items():
                for c in nodes(d.data, ("Microflows$MicroflowCall",)):
                    self._calls.setdefault(c.get("Microflow"), []).append((qn, c))
        return self._calls

    def var_entity(self, doc, var):
        for n in nodes(doc.data):
            names = (n.get("Name"), n.get("VariableName"), n.get("OutputVariableName"), n.get("ResultVariableName"))
            if var not in names:
                continue
            for k in ("VariableType", "ParameterType", "Type", "ResultType"):
                t = n.get(k)
                if isinstance(t, dict) and isinstance(t.get("Entity"), str) and t["Entity"]:
                    return t["Entity"]
            src = n.get("RetrieveSource")
            if isinstance(src, dict) and isinstance(src.get("Entity"), str) and src["Entity"]:
                return src["Entity"]
            if isinstance(n.get("Entity"), str) and n["Entity"]:
                return n["Entity"]
        return None

    def resolve(self, expr, doc, depth=0, seen=None):
        expr = (expr or "").strip()
        seen = seen or set()
        if not expr:
            return [("unknown", "empty location")]
        consts = [c for c in CONST_RE.findall(expr) if c.split(".")[0] in self.m.modules]
        if consts:
            return [("const", consts[0])]
        m = LIT_RE.match(expr)
        if m:
            return [("literal", m.group(1))]
        m = ATTR_RE.match(expr)
        if m:
            ent = self.var_entity(doc, m.group(1)) if doc else None
            return [("attr", f"{ent}.{m.group(2)}" if ent else f"?${m.group(1)}.{m.group(2)}")]
        m = VAR_RE.match(expr)
        if not m or doc is None:
            return [("unknown", f"location expression {expr[:80]!r} is not a constant, an attribute or a variable")]
        var = m.group(1)
        key = (doc.qn, var)
        if key in seen or depth > 3:
            return [("unknown", f"${var}: traced too deep")]
        seen = seen | {key}
        out = []
        for n in nodes(doc.data):
            t = n.get("$Type", "")
            if t == "Microflows$CreateVariableAction" and n.get("VariableName") == var:
                out += self.resolve(n.get("InitialValue"), doc, depth + 1, seen)
            elif t == "Microflows$ChangeVariableAction" and var in (n.get("ChangeVariableName"), n.get("VariableName")):
                out += self.resolve(n.get("Value"), doc, depth + 1, seen)
            elif t == "Microflows$MicroflowCallAction" and n.get("ResultVariableName") == var:
                callee = (n.get("MicroflowCall") or {}).get("Microflow")
                cd = self.flows.get(callee)
                rets = [e.get("ReturnValue") for e in nodes(cd.data, ("Microflows$EndEvent",))
                        if (e.get("ReturnValue") or "").strip()] if cd else []
                if not rets:
                    out.append(("unknown", f"${var} is returned by {callee}, which returns nothing traceable"))
                for r in rets:
                    out += self.resolve(r, cd, depth + 1, seen)
            elif t == "Microflows$JavaActionCallAction" and n.get("ResultVariableName") == var:
                # a Java action's result: trace the constants passed in (LoadStringValueFromEnvOrDefault(env, @Const)
                # style); with none, the URL is computed at runtime and stays UNKNOWN, naming the action.
                args = [((pm.get("Value") or {}).get("Argument") or "") for pm in n.get("ParameterMappings") or []
                        if isinstance(pm, dict)]
                cs = [c for a in args for c in CONST_RE.findall(a) if c.split(".")[0] in self.m.modules]
                if cs:
                    out.append(("const", cs[0]))
                else:
                    out.append(("unknown", f"${var} is computed by Java action {n.get('JavaAction')} at runtime"))
        is_param = any(n.get("$Type") == "Microflows$MicroflowParameterObject" and n.get("Name") == var
                       for n in nodes(doc.data))
        if is_param:
            calls = self.callers().get(doc.qn, [])
            if not calls:
                out.append(("unknown", f"${var} is a parameter of {doc.qn} and nothing in the model calls it"))
            for cq, c in calls:
                for pm in c.get("ParameterMappings") or []:
                    if isinstance(pm, dict) and pm.get("Parameter") == f"{doc.qn}.{var}":
                        out += self.resolve(pm.get("Argument"), self.flows.get(cq), depth + 1, seen)
        if not out:
            out.append(("unknown", f"${var} in {doc.qn}: no assignment found"))
        return list(dict.fromkeys(out))

    # -- response shapes
    def mapping_body(self, mqn):
        """(body, content type, shape note) of an import mapping: its JSON structure's snippet, else built from the
        mapping's own JsonPath elements."""
        md = self.m.docs.get(mqn)
        if not md:
            return {}, "application/json", f"mapping {mqn} not in the model: answers {{}}"
        js = md.data.get("JsonStructure")
        jd = self.m.docs.get(js) if js else None
        if jd and (jd.data.get("JsonSnippet") or "").strip():
            try:
                return json.loads(jd.data["JsonSnippet"], strict=False), "application/json", f"mapping {mqn}, JSON structure {js}"
            except ValueError:
                pass
        leaves = []
        for n in nodes(md.data.get("Elements") or []):
            p = n.get("JsonPath")
            if isinstance(p, str) and p:
                leaves.append((p, n.get("ElementType"), (n.get("Type") or {}).get("$Type", "") if isinstance(n.get("Type"), dict) else ""))
        if not leaves:
            return {}, "application/json", f"mapping {mqn} has no JSON paths: answers {{}}"
        return build_from_paths(leaves), "application/json", f"mapping {mqn}, built from its element paths"

    # -- the endpoints
    def endpoints(self):
        eps = []
        used_consts = set()
        for qn, d in sorted(self.flows.items()):
            n_rest = [x for x in nodes(d.data, ("Microflows$RestCallAction",))]
            for i, a in enumerate(n_rest):
                eps.append(self.rest_ep(d, a, f"rest:{qn}" + (f"#{i + 1}" if len(n_rest) > 1 else "")))
            n_send = [x for x in nodes(d.data, CALL_TYPES)]
            for i, a in enumerate(n_send):
                eps.append(self.send_ep(d, a, f"send:{qn}" + (f"#{i + 1}" if len(n_send) > 1 else "")))
        for d in sorted(self.m.of_type("Rest$ConsumedODataService"), key=lambda d: d.qn):
            eps.append(self.odata_ep(d))
        for e in eps:
            used_consts |= {r[1] for r in e["routes"] if r[0] == "const"}
        for d in sorted(self.m.of_type("Constants$Constant"), key=lambda d: d.qn):
            if d.qn in used_consts:
                continue
            c = self.m.constant(d.qn)
            dv = str(c.get("default") or "")
            if URLISH.match(dv) or (c.get("type") == "String" and URLNAME.search(d.data.get("Name", ""))):
                eps.append({"id": f"const:{d.qn}", "kind": "const", "module": d.module, "doc": d.qn, "method": "*",
                            "template": "", "routes": [("const", d.qn)], "body": None, "shape": "no modelled call reads it",
                            "why": "URL constant no modelled call reads (a Java action or a string built at runtime may "
                                   "call it): classify it"})
        return eps

    def location(self, d, hc, text_key="CustomLocationTemplate"):
        """(routes, template suffix) of a HttpConfiguration."""
        tpl = hc.get(text_key) if isinstance(hc.get(text_key), dict) else None
        if tpl and (tpl.get("Text") or "").strip():
            text = tpl["Text"]
            params = [p.get("Expression", "") for p in tpl.get("Parameters") or [] if isinstance(p, dict)]
            m = re.match(r"\s*\{(\d+)\}", text)
            if m and int(m.group(1)) <= len(params):
                return self.resolve(params[int(m.group(1)) - 1], d), text[m.end():], params
            m = re.match(r"\s*((?:https?|ftp)://[^{]*)", text)
            if m:
                return [("literal", m.group(1))], text[m.end():], params
            return [("unknown", f"location template {text[:60]!r} does not start with a parameter or a URL")], text, params
        loc = hc.get("CustomLocation") or ""
        if loc:
            return self.resolve(loc, d), "", []
        return [("unknown", "no location in the action")], "", []

    def rest_ep(self, d, a, eid):
        hc = a.get("HttpConfiguration") or {}
        routes, suffix, params = self.location(d, hc)
        rh = a.get("ResultHandling") or {}
        imc = rh.get("ImportMappingCall") if isinstance(rh.get("ImportMappingCall"), dict) else None
        rtype = a.get("ResultHandlingType") or ""
        if imc and imc.get("ReturnValueMapping"):
            body, ct, shape = self.mapping_body(imc["ReturnValueMapping"])
            if (imc.get("ContentType") or "").lower() == "xml":
                shape += " (XML mapping: answered as JSON, record an XML response)"
        else:
            body, ct, shape = {}, "application/json", f"result handling {rtype or '?'}: no mapped shape, answers {{}}"
        rh_tpl = ((a.get("RequestHandling") or {}).get("Template") or {}).get("Text") if isinstance(a.get("RequestHandling"), dict) else None
        return {"id": eid, "kind": "rest", "module": d.module, "doc": d.qn, "method": (hc.get("HttpMethod") or "Get").upper(),
                "template": suffix, "params": params, "routes": routes, "body": body, "content_type": ct, "shape": shape,
                "seg_hints": segment_hints(suffix, params), "req_fixed": fixed_pairs(rh_tpl)}

    def send_ep(self, d, a, eid):
        t = a.get("$Type", "").split("$")[-1]
        hc = a.get("HttpConfiguration") if isinstance(a.get("HttpConfiguration"), dict) else None
        refs = sorted({s for s in mprmodel.strings(a) if re.fullmatch(r"[A-Za-z_]\w*\.[A-Za-z_][\w.]*", s)})
        if hc and hc.get("OverrideLocation"):
            routes, suffix, params = self.location(d, hc)
        else:
            routes, suffix, params = [], "", []
            for r in refs:   # the service document the action names: the constants it reads
                sd = self.m.docs.get(".".join(r.split(".")[:2]))
                if sd and sd.type != "Constants$Constant":
                    for s in mprmodel.strings(sd.data):
                        for c in CONST_RE.findall(s):
                            if self.m.constant(c):
                                routes.append(("const", c))
            routes = list(dict.fromkeys(routes)) or [("unknown", f"{t}: location not read (a shape this reader has not "
                                                                    f"seen on a real model; names {', '.join(refs[:3]) or 'nothing'})")]
        op = a.get("OperationName") or a.get("Operation") or ""
        soap = "WebService" in t
        body = (f'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><{op or "Operation"}Response/>'
                f'</soap:Body></soap:Envelope>') if soap else {}
        return {"id": eid, "kind": "ws" if soap else "send", "module": d.module, "doc": d.qn, "method": "POST" if soap else "*",
                "template": suffix, "params": params, "routes": routes, "body": body,
                "content_type": "text/xml" if soap else "application/json",
                "shape": f"{t}{(' ' + op) if op else ''}: " + ("an empty SOAP response" if soap else "no mapped shape read, answers {}")}

    def odata_ep(self, d):
        hc = d.data.get("HttpConfiguration") or {}
        loc = (hc.get("CustomLocation") or "").strip()
        cfg = d.data.get("ConfigurationMicroflow") or ""
        if loc:
            routes = self.resolve(loc, None)
        elif cfg:
            routes = self.config_consts(cfg)
        else:
            u = d.data.get("ServiceUrl") or d.data.get("MetadataUrl") or ""
            routes = [("unknown", f"hard-coded location {u[:80]} (no constant, no configuration microflow): no override reaches it")]
        md = d.data.get("Metadata") or ""
        sets = odata_sets(md) if isinstance(md, str) and md.strip() else {}
        return {"id": f"odata:{d.qn}", "kind": "odata", "module": d.module, "doc": d.qn, "method": "GET", "template": "",
                "routes": routes, "body": None, "metadata_doc": d.qn, "odata_version": d.data.get("ODataVersion") or "",
                "shape": f"$metadata stored in the model ({len(md)} chars), {len(sets)} entity sets" if md else "no stored $metadata"}

    def config_consts(self, mf):
        d = self.flows.get(mf)
        if not d:
            return [("unknown", f"location set by {mf} (not in the model: an add-on module or protected): classify it")]
        found = []
        todo, seen = [d], set()
        while todo and len(seen) < 6:
            cur = todo.pop(0)
            if cur.qn in seen:
                continue
            seen.add(cur.qn)
            for s in mprmodel.strings(cur.data):
                for c in CONST_RE.findall(s):
                    k = self.m.constant(c)
                    if k and (URLISH.match(str(k.get("default") or "")) or URLNAME.search(c.split(".")[-1])):
                        found.append(("const", c))
            for c in nodes(cur.data, ("Microflows$MicroflowCall",)):
                nd = self.flows.get(c.get("Microflow"))
                if nd:
                    todo.append(nd)
                elif c.get("Microflow"):
                    found.append(("unknown", f"location may be set by {c.get('Microflow')} (not in the model)"))
        consts = [r for r in found if r[0] == "const"]
        if consts:
            return list(dict.fromkeys(consts))
        return list(dict.fromkeys(found)) or [("unknown", f"location set at runtime by {mf} (no URL constant read): classify it")]


import mprmodel  # noqa: E402  (after sys.path)


def sample(name, ptype):
    t = (ptype or "").lower()
    if "integer" in t or "long" in t or "int" in t:
        return 1
    if "decimal" in t or "float" in t or "double" in t or "number" in t:
        return 1.5
    if "boolean" in t:
        return True
    if "date" in t:
        return "2024-01-01T00:00:00Z"
    return f"{name} 1" if name else "value 1"


MARKS = ("(Object)", "(Array)", "(Value)")


def build_from_paths(leaves):
    """Mendix JsonPath strings -> a JSON value of that shape. Convention (as the JSON structures and import mappings of
    the field models write it): the root is "(Object)" or "(Array)"; a key holding an object has its keys directly under
    it ("(Object)|address|street"); a key holding an array has one item marker under it ("(Object)|items|(Object)|id",
    "(Object)|tags|(Value)"); a root array's item is "(Array)|(Object)"."""
    paths = [p.split("|") for p, _, _ in leaves]
    types = {tuple(p.split("|")): ty for p, _, ty in leaves}

    def kids(prefix):
        return list(dict.fromkeys(p[len(prefix)] for p in paths if len(p) > len(prefix) and p[:len(prefix)] == prefix))

    def build(prefix):
        nexts = kids(prefix)
        last = prefix[-1]
        if last == "(Value)" or (not nexts and last not in MARKS):
            return sample(prefix[-2] if last == "(Value)" and len(prefix) > 1 else last, types.get(tuple(prefix)))
        marks = [n for n in nexts if n in MARKS]
        if last == "(Array)" or (marks and last != "(Object)"):
            return [build(prefix + [marks[0]])] if marks else []
        return {n: build(prefix + [n]) for n in nexts if n not in MARKS}

    roots = kids([])
    return build([roots[0]]) if roots else {}


def shape_paths(v):
    """A JSON value -> the set of Mendix-style JsonPaths it holds (the inverse of build_from_paths), to check a body
    against a mapping's element paths."""
    out = set()

    def walk(x, p):
        out.add("|".join(p))
        if isinstance(x, dict):
            for k, val in x.items():
                walk(val, p + [k])
        elif isinstance(x, list):
            for i in x[:1]:
                walk(i, p + ["(Object)" if isinstance(i, dict) else "(Array)" if isinstance(i, list) else "(Value)"])
    walk(v, ["(Array)" if isinstance(v, list) else "(Object)"])
    return out


def odata_sets(xml):
    """$metadata XML -> {entity set: [(property, Edm type, is key)]}."""
    try:
        root = ET.fromstring(xml.encode("utf-8") if isinstance(xml, str) else xml)
    except ET.ParseError:
        return {}
    local = lambda t: t.rsplit("}", 1)[-1]
    types = {}
    for et in root.iter():
        if local(et.tag) == "EntityType":
            keys = {pr.get("Name") for k in et if local(k.tag) == "Key" for pr in k}
            props = [(p.get("Name"), p.get("Type", ""), p.get("Name") in keys) for p in et if local(p.tag) == "Property"]
            types[et.get("Name")] = props
    sets = {}
    for es in root.iter():
        if local(es.tag) == "EntitySet":
            sets[es.get("Name")] = types.get((es.get("EntityType") or "").rsplit(".", 1)[-1], [])
    return sets


def odata_rows(props, n=2):
    rows = []
    for i in range(1, n + 1):
        r = {}
        for name, t, key in props:
            tl = t.lower()
            if "int" in tl or "byte" in tl:
                r[name] = i
            elif "decimal" in tl or "double" in tl or "single" in tl:
                r[name] = i + 0.5
            elif "boolean" in tl:
                r[name] = i % 2 == 1
            elif "datetime" in tl:
                r[name] = f"2024-01-0{i}T00:00:00Z"
            elif "date" in tl:
                r[name] = f"2024-01-0{i}"
            elif "guid" in tl:
                r[name] = f"00000000-0000-0000-0000-00000000000{i}"
            elif tl.startswith("edm."):
                r[name] = f"{name} {i}"
        rows.append(r)
    return rows


# ------------------------------------------------------------------------------------------------ classification
def parse_excludes(specs):
    """--exclude NAME or NAME=glob,glob -> [(system, [patterns], reason)]."""
    out = []
    for s in specs or []:
        for part in [p for p in re.split(r";", s) if p.strip()]:
            name, _, pats = part.partition("=")
            name = name.strip()
            if not name:
                die(f"--exclude {s!r}: no system name")
            plist = [p.strip() for p in pats.split(",") if p.strip()] or BUILTIN_EXCLUDE.get(name.lower()) or [f"*{name}*"]
            reason = ("needs a real Teamcenter server (SOA login, FMS tickets, viewer rendering): no stand-in"
                      if name.lower() in BUILTIN_EXCLUDE and not pats else f"excluded on request (--exclude {part.strip()})")
            out.append((name, plist, reason))
    return out


def read_classify(path):
    rules = []
    if not path:
        return rules
    p = Path(path)
    if not p.is_file():
        die(f"--classify {path}: no such file")
    for i, raw in enumerate(p.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # the reason starts at the first '#' after whitespace: endpoint ids carry '#2' style suffixes (rest:Mod.Mf#2)
        m = re.search(r"\s#", line)
        body, reason = (line[:m.start()], line[m.end():]) if m else (line, "")
        f = body.split()
        if not reason.strip():
            die(f"--classify {path}:{i}: no '# reason': {line}")
        if (len(f) < 2 or f[1] not in ("MOCKED", "EXCLUDED", "LOCATION", "UNEXERCISED")
                or (f[1] in ("EXCLUDED", "LOCATION") and len(f) < 3)):
            die(f"--classify {path}:{i}: want '<pattern> MOCKED # reason', '<pattern> EXCLUDED <System> # reason', "
                f"'<pattern> LOCATION const:<Module.Constant>|data:<Module.Entity.Attribute> # reason' or "
                f"'<pattern> UNEXERCISED # reason': {line}")
        arg = f[2] if f[1] in ("EXCLUDED", "LOCATION") else ""
        if f[1] == "LOCATION" and not (re.fullmatch(r"const:[A-Za-z_]\w*\.[A-Za-z_]\w*", arg)
                                       or re.fullmatch(r"data:[A-Za-z_]\w*\.[A-Za-z_]\w*\.[A-Za-z_]\w*", arg)):
            die(f"--classify {path}:{i}: LOCATION wants const:<Module.Constant> or data:<Module.Entity.Attribute>: {line}")
        rules.append((f[0], f[1], arg, reason.strip()))
    return rules


def apply_locations(ep, rules):
    """B4N1-9: a LOCATION line declares where an endpoint's URL comes from when the reader cannot see it (a protected
    add-on microflow builds it from entity data, or an add-on constant). The declared constant or attribute replaces the
    endpoint's unknown routes, so `serve` overrides that constant or prints the /a/<Entity.Attr> URL to seed."""
    decl = [(("const" if arg.startswith("const:") else "attr"), arg.split(":", 1)[1], pat, reason)
            for pat, verb, arg, reason in rules if verb == "LOCATION" and fnmatch.fnmatch(ep["id"], pat)]
    if not decl:
        return
    ep["routes"] = [r for r in ep["routes"] if r[0] != "unknown"]
    for kind, ref, pat, reason in decl:
        if (kind, ref) not in ep["routes"]:
            ep["routes"].append((kind, ref))
    ep["declared"] = "; ".join(f"location {k == 'const' and 'constant' or 'data'} {ref} declared ({pat}): {reason}"
                               for k, ref, pat, reason in decl)


def host_of(url):
    try:
        return (urlsplit(url.strip("'")).hostname or "").lower()
    except ValueError:
        return ""


def classify(ep, model_consts, excludes, rules, recorded):
    """Sets ep status / system / why."""
    names = {ep["module"] or "", ep["doc"]}
    hosts = set()
    for kind, ref in ep["routes"]:
        if kind == "const":
            names |= {ref, ref.split(".")[0]}
            hosts.add(host_of(str((model_consts.get(ref) or {}).get("default") or "")))
        elif kind == "attr":
            names |= {ref, ref.split(".")[0]}
        elif kind == "literal":
            hosts.add(host_of(ref))
    hosts.discard("")
    for system, pats, reason in excludes:
        for p in pats:
            if p.startswith("host:"):
                hit = next((h for h in hosts if fnmatch.fnmatch(h, p[5:].lower())), None)
            else:
                hit = next((n for n in names if fnmatch.fnmatch(n.lower(), p.lower())), None)
            if hit:
                ep.update(status="EXCLUDED", system=system, why=f"{reason}; matched {p} on {hit}")
                return
    for pat, st, system, reason in rules:
        if st == "UNEXERCISED" and fnmatch.fnmatch(ep["id"], pat) and "unexercised" not in ep:
            ep["unexercised"] = f"{reason} ({pat})"
    kinds = {k for k, _ in ep["routes"]}
    for pat, st, system, reason in rules:
        if st in ("LOCATION", "UNEXERCISED") or not fnmatch.fnmatch(ep["id"], pat):
            continue
        if st == "MOCKED" and not kinds & {"const", "attr"}:
            # B4N1-9: MOCKED says the app talks to this stand-in; with no constant or data location the stand-in has no
            # route the app could reach (Opcenter: the URL is built by a protected add-on microflow), so the claim is
            # unprovable and the endpoint stays UNKNOWN until a LOCATION line names where the URL comes from.
            ep.update(status="UNKNOWN", system="", why=f"classified MOCKED ({pat}) but the stand-in has no route to it: "
                      f"no constant or data location is known ({'; '.join(r for k, r in ep['routes'] if k == 'unknown') or 'no location'}); "
                      f"add '<pattern> LOCATION const:<Module.Constant>|data:<Module.Entity.Attribute> # reason' naming "
                      f"where the URL comes from, or it is not stood in")
            return
        ep.update(status=st, system=system, why=f"classified {st} ({pat}): {reason}")
        if st == "EXCLUDED":   # written down in a --classify line with its reason: documented (INFO, check at deploy), never stray
            ep["classified"] = True
        return
    if ep["kind"] == "const":
        if recorded and (Path(recorded) / f"{safe(ep['id'])}.json").is_file():
            ep.update(status="MOCKED", system="", why="recorded response for this constant")
        else:
            ep.update(status="UNKNOWN", system="", why=ep.get("why", ""))
        return
    if kinds == {"const"}:
        ep.update(status="MOCKED", system="", why="every location is an overridden constant")
        return
    whys = [ref if k == "unknown" else
            f"location from data {ref}: set it to the printed /a/{ref} URL in the seed data, then classify it" if k == "attr" else
            f"hard-coded URL {ref}: no override reaches it" for k, ref in ep["routes"] if k != "const"]
    ep.update(status="UNKNOWN", system="", why="; ".join(whys) or "no location")


def addon_files(model_path):
    """<project dir>/modules/*.mxmodule beside a model (.mpr or its folder): the add-on modules (mxversion.addons)."""
    proj = model_path if os.path.isdir(model_path) else os.path.dirname(os.path.abspath(model_path))
    return sorted(glob.glob(os.path.join(proj, "modules", "*.mxmodule")))


def addon_names(path, names, cap=256 << 20):
    """(URL constants {qualified name: default}, URL-named attributes, why unreadable) of an add-on module. An .mxmodule
    is a zip whose project.mpr is not a sqlite MPR but ONE bson document (mprmodel cannot open it): its
    Constants$Constant nodes (Name, DefaultValue, Type; EXFN_Authentication.APPBaseUrl = 'OCEXFN: {{APPLICATIONBASEURL}}')
    and the Attribute of every member change (EXFN_Authentication.ClientConfiguration.OpcenterEXFNUrl) are read from it.
    A packed model bson cannot decode falls back to qualified names in its bytes (modules of `names` only)."""
    consts, attrs = {}, set()
    try:
        with zipfile.ZipFile(path) as z:
            mprs = sorted((i for i in z.infolist() if i.filename.lower().endswith(".mpr")),
                          key=lambda i: (os.path.basename(i.filename).lower() != "project.mpr", i.filename))
            if not mprs:
                return {}, [], "no .mpr inside"
            if mprs[0].file_size > cap:
                return {}, [], f"{mprs[0].filename} is {mprs[0].file_size} bytes: not read"
            raw = z.read(mprs[0])
            mod = re.search(rb'<module name="([^"]+)"', z.read("package.xml")) if "package.xml" in z.namelist() else None
    except (OSError, zipfile.BadZipFile, KeyError) as e:
        return {}, [], f"not readable as a zip ({e})"
    module = mod.group(1).decode() if mod else os.path.splitext(os.path.basename(path))[0]
    try:
        import bson
        tree = bson.decode(raw)
    except Exception as e:  # noqa: BLE001  any decoder failure: fall back to the byte scan, say so
        tree, err = None, f"packed model not decodable ({type(e).__name__}): names read from its bytes"
    if tree is not None:
        err = ""
        for n in nodes(tree):
            t = n.get("$Type")
            if t == "Constants$Constant" and n.get("Name"):
                dv = str(n.get("DefaultValue") or "")
                is_str = "String" in str((n.get("Type") or {}).get("$Type", "")) if isinstance(n.get("Type"), dict) else True
                if URLISH.match(dv) or (is_str and URLNAME.search(n["Name"])):
                    consts[f"{module}.{n['Name']}"] = dv
            a = n.get("Attribute")
            if isinstance(a, str) and a.count(".") == 2 and URLNAME.search(a.split(".")[-1]):
                attrs.add(a)
        return dict(sorted(consts.items())), sorted(attrs), err
    mods = "|".join(re.escape(x) for x in sorted(set(names) | {module}, key=len, reverse=True))
    rx = re.compile(rb"(?<![\w.])@(" + mods.encode() + rb")\.([A-Za-z_]\w*)(?![\w.])")
    for m in rx.finditer(raw):
        if URLNAME.search(m.group(2).decode()):
            consts[f"{m.group(1).decode()}.{m.group(2).decode()}"] = ""
    return dict(sorted(consts.items())), [], err


def addon_endpoint(path, names):
    """B4T2-6 / B4N1-9: an add-on module's own calls are invisible to this reader (its model is packed and protected; a
    location may be built at runtime from entity data, EXFN_ServiceLayer). It is one UNKNOWN endpoint per add-on, so
    "unknown 0" is never claimed while add-ons exist. The URL-named constants it names are routed (serve overrides them
    and they show in overrides.json); the URL-named attributes are printed as candidate data locations."""
    name = os.path.splitext(os.path.basename(path))[0]
    consts, attrs, err = addon_names(path, names)
    why = (f"add-on module {os.path.basename(path)}: its calls are not readable (packed, protected; a URL it builds at "
           f"runtime from data is invisible)" + (f"; {err}" if err else "")
           + (f"; URL-named attributes it reads: {', '.join(attrs[:6])}" if attrs else "")
           + "; point each location at the stand-in (LOCATION line: const: overrides the constant, data: prints the "
             "/a/ URL to seed) and classify it MOCKED, or it stays UNKNOWN")
    return {"id": f"addon:{name}", "kind": "addon", "module": name, "doc": name, "method": "*", "template": "",
            "routes": [("const", c) for c in consts] + [("unknown", why)], "body": {}, "content_type": "application/json",
            "shape": f"add-on module, {len(consts)} URL constants" + (f" ({', '.join(list(consts)[:4])})" if consts else ""),
            "addon_file": os.path.basename(path), "addon_attrs": attrs,
            "addon_constants": {c: {"default": v, "type": "String", "exposed": True} for c, v in consts.items()}}


def build_inventory(models, excludes, rules, recorded):
    eps, consts, metas, mods = {}, {}, {}, []
    for path in models:
        if not os.path.exists(path):
            die(f"model not found: {path}")
        try:
            m = mprmodel.Model.load(path)
        except SystemExit:
            raise
        except Exception as e:  # noqa: BLE001  an unreadable file is an input error, never "0 APIs"
            die(f"cannot read {path}: {e}")
        if not m.all_docs:
            die(f"{path}: no documents read")
        mods.append(path)
        r = Reader(m)
        for d in m.of_type("Constants$Constant"):
            consts.setdefault(d.qn, m.constant(d.qn))
        for d in m.of_type("Rest$ConsumedODataService"):
            metas.setdefault(d.qn, d.data.get("Metadata") or "")
        adds = addon_files(path)
        found = r.endpoints() + [addon_endpoint(f, {os.path.splitext(os.path.basename(x))[0] for x in adds}) for f in adds]
        for e in found:
            for c, info in (e.get("addon_constants") or {}).items():
                consts.setdefault(c, info)
            if e["id"] in eps:
                old = eps[e["id"]]
                for rt in e["routes"]:
                    if rt not in old["routes"]:
                        old["routes"].append(rt)
                continue
            eps[e["id"]] = e
    for e in eps.values():
        e["routes"] = [tuple(r) for r in e["routes"]]
        apply_locations(e, rules)
        classify(e, consts, excludes, rules, recorded)
        if e.get("declared"):
            e["why"] = f"{e['why']}; {e['declared']}"
    return {"models": mods, "endpoints": [eps[k] for k in sorted(eps)], "constants": consts, "metadata": metas,
            "excludes": [[s, p, r] for s, p, r in excludes]}


def coverage_line(inv):
    eps = inv["endpoints"]
    st = lambda s: [e for e in eps if e["status"] == s]
    systems = sorted({e["system"] for e in st("EXCLUDED")})
    return (f"apis {len(eps)} found · mocked {len(st('MOCKED'))} · excluded {len(st('EXCLUDED'))}"
            + (f" ({', '.join(systems)})" if systems else "") + f" · unknown {len(st('UNKNOWN'))}")


def route_text(e):
    return ", ".join(f"constant {r}" if k == "const" else f"data {r}" if k == "attr" else f"URL {r}" if k == "literal" else "?"
                     for k, r in e["routes"] if k != "unknown") or "no location"


def print_inventory(inv, out=sys.stdout):
    for e in inv["endpoints"]:
        st = e["status"] + (f" ({e['system']})" if e["status"] == "EXCLUDED" else "")
        print(f"{st:22} {e['id']}  {e['method']} {e['template'][:60]}  via {route_text(e)}  [{e['shape']}]"
              + (f"  -- {e['why']}" if e["status"] != "MOCKED" or e["why"].startswith("classified") or e.get("declared") else ""),
              file=out)
    print(coverage_line(inv), file=out)


def overrides(inv, base):
    """{Module.Constant: URL on the stand-in} for every constant an endpoint routes through."""
    o = {}
    for e in inv["endpoints"]:
        for k, r in e["routes"]:
            if k == "const":
                dv = str((inv["constants"].get(r) or {}).get("default") or "")
                o[r] = f"{base}/c/{r}" + ("/" if dv.endswith("/") else "")
    return dict(sorted(o.items()))


# ------------------------------------------------------------------------------------------------ the stand-in
def tpl_regex(t):
    t = t.split("?")[0]
    parts = re.split(r"\{\d+\}", t)
    return re.compile("^" + ".*?".join(re.escape(p) for p in parts) + "/?$"), sum(len(p) for p in parts)


def segment_hints(template, params):
    """{segment index: [literals]} for each path segment of a template that is a lone {N} placeholder whose parameter
    expression holds quoted names (`if $X then 'GetCompletedCo' else 'GetActiveCo'`). Several calls share one generic
    template (/OData/{2}?filter=...); the literal names tell them apart (pick)."""
    out = {}
    for i, seg in enumerate(template.split("?")[0].strip("/").split("/")):
        m = re.fullmatch(r"\{(\d+)\}", seg)
        if m and 0 < int(m.group(1)) <= len(params):
            lits = re.findall(r"'([A-Za-z_][A-Za-z0-9_]*)'", str(params[int(m.group(1)) - 1]))
            if lits:
                out[str(i)] = sorted(set(lits))
    return out


def fixed_pairs(text):
    """{key: value} of the string pairs a request body template fixes ("api_name": "TimeZone"), skipping any value
    that holds a {N} placeholder. Many calls POST to one generic route (/Requests/Execute); these pairs tell them apart."""
    if not text:
        return {}
    return {k: v for k, v in re.findall(r'"([A-Za-z_]\w*)"\s*:\s*"([^"{}]*)"', text)}


def discriminate(e, rest, body, query=""):
    """Tie-break among endpoints that share a route and a template: +1 per fixed request pair or path-segment name the
    request matches, -1 per one it contradicts (a query name only one side has counts too). 0 when the endpoint holds nothing to compare."""
    score = 0
    segs = rest.split("?")[0].strip("/").split("/")
    for i, lits in (e.get("seg_hints") or {}).items():
        i = int(i)
        if i < len(segs):
            score += 1 if segs[i].lower() in {x.lower() for x in lits} else -1
    tkeys = set(re.findall(r"[?&]([$A-Za-z_][\w.]*)=", e.get("template", "")))
    if tkeys and e["method"] == "GET":   # the same path with other query names (a paged call has top and skip)
        rkeys = {k.lstrip("$") for k in parse_qs(query or "")}
        score -= len({k.lstrip("$") for k in tkeys} ^ rkeys)
    fixed = e.get("req_fixed") or {}
    if fixed and body:
        try:
            req = json.loads(body)
        except ValueError:
            req = None
        if isinstance(req, dict):
            for k, v in fixed.items():
                if k in req and isinstance(req[k], str):
                    score += 1 if req[k] == v else -1
    return score


SECRET_HEADER = re.compile(r"authorization|cookie|token|secret|api[-_]?key|password|credential", re.I)
IGNORED_HEADERS = {"host", "user-agent", "content-length", "connection", "accept-encoding", "date", "expect"}
FAULT_MODES = ("ok", "500", "malformed")
BODY_KEEP = 20000


def mask_headers(headers):
    """Request headers for the log (direct API tests): names lower-cased, a secret's value reduced to its scheme
    ("Bearer <redacted>"), so a header that is present or missing still shows and no token is ever written."""
    out = {}
    for k, v in headers:
        k = k.lower()
        if SECRET_HEADER.search(k):
            scheme = (v or "").split(" ", 1)[0] if " " in (v or "") else ""
            v = (scheme + " " if scheme else "") + "<redacted>"
        out[k] = v if k not in out else out[k] + ", " + v
    return out


class Stand:
    def __init__(self, inv, state, recorded):
        self.inv, self.state, self.recorded = inv, Path(state), recorded
        self.lock = threading.Lock()
        self.ctx = None   # direct API test (apidirect.py): {"call", "side", "mode"} while one call runs; None = normal answers
        self.by_route = {}
        for e in inv["endpoints"]:
            for k, r in e["routes"]:
                if k in ("const", "attr"):
                    self.by_route.setdefault(f"/{'c' if k == 'const' else 'a'}/{r}", []).append(e)
        self.sets = {q: odata_sets(md) for q, md in inv["metadata"].items() if md}

    def log(self, rec):
        with self.lock:
            with open(self.state / "requests.jsonl", "a") as f:
                f.write(json.dumps(rec) + "\n")

    def pick(self, method, path, body=None, query=""):
        best = None
        for prefix in sorted(self.by_route, key=len, reverse=True):
            if path == prefix or path.startswith(prefix + "/"):
                rest = path[len(prefix):]
                cands = self.by_route[prefix]
                scored = []
                for e in cands:
                    if e["kind"] == "odata":   # two services behind one declared prefix: the one owning the set wins
                        tail = self.odata_tail(e, rest).split("/")[0]
                        own = tail == "$metadata" or re.match(r"[^(]*", tail).group(0) in self.sets.get(e["metadata_doc"], {})
                        scored.append((1.5 if own else 1, e, "odata"))
                        continue
                    if e["method"] not in ("*", method):
                        continue
                    rx, lit = tpl_regex(e["template"])
                    if rx.match(rest):
                        scored.append((2 + lit + 0.1 * discriminate(e, rest, body, query), e, "template"))
                    elif e["kind"] == "const":
                        scored.append((0, e, "constant"))
                if not scored:
                    same = [e for e in cands if e["method"] in ("*", method) and e["kind"] != "odata"]
                    if len(same) == 1:
                        scored.append((0, same[0], "loose"))
                if scored:
                    scored.sort(key=lambda x: -x[0])
                    return scored[0][1], scored[0][2], rest
                best = (None, "no template matches", rest)
                break
        return best or (None, "no endpoint route", path)

    def answer(self, e, method, rest, query):
        rec = Path(self.recorded) / f"{safe(e['id'])}.json" if self.recorded else None
        if rec and rec.is_file():
            r = json.loads(rec.read_text())
            b = r.get("body", "")
            return int(r.get("status", 200)), r.get("content_type", "application/json"), b if isinstance(b, str) else json.dumps(b)
        if e["kind"] == "odata":
            return self.odata(e, rest, query)
        b = e.get("body")
        return 200, e.get("content_type", "application/json"), b if isinstance(b, str) else json.dumps(b if b is not None else {})

    def odata_tail(self, e, rest):
        """The part of the path from $metadata or an entity set on. A location built at runtime adds segments after the
        routed prefix (Opcenter: <OpcenterEXFNUrl>/<segment>/<plant>/Application/<app>/odata/<Set>, B4N1-9)."""
        segs = rest.strip("/").split("/")
        sets = self.sets.get(e["metadata_doc"], {})
        for i, sg in enumerate(segs):
            if sg == "$metadata" or re.match(r"[^(]*", sg).group(0) in sets:
                return "/".join(segs[i:])
        return rest.strip("/")

    def odata(self, e, rest, query):
        md = self.inv["metadata"].get(e["metadata_doc"], "")
        seg = self.odata_tail(e, rest)
        if seg == "$metadata":
            return (200, "application/xml", md) if md else (404, "application/json", json.dumps({"error": "no stored $metadata"}))
        sets = self.sets.get(e["metadata_doc"], {})
        if not seg:
            return 200, "application/json", json.dumps({"value": [{"name": s, "url": s} for s in sorted(sets)]})
        m = re.match(r"([^/(]+)(\([^)]*\))?(/\$count)?", seg)
        name = m.group(1) if m else seg
        if name not in sets:
            return 404, "application/json", json.dumps({"error": {"code": "404", "message": f"no entity set {name} in $metadata"}})
        rows = odata_rows(sets[name])
        if m.group(3):
            return 200, "text/plain", str(len(rows))
        if m.group(2):
            return 200, "application/json", json.dumps(rows[0])
        body = {"@odata.context": f"$metadata#{name}", "value": rows}
        if "true" in (query.get("$count") or query.get("$inlinecount") or [""])[0].lower() or query.get("$inlinecount"):
            body["@odata.count"] = len(rows)
        return 200, "application/json", json.dumps(body)


def make_handler(stand):
    class H(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def handle_any(self):
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n) if n else b""
            u = urlsplit(self.path)
            q = parse_qs(u.query)
            t = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
            if u.path.startswith("/__ad/"):   # control endpoint of apidirect.py: which call (and fault mode) is running
                return self.control(u.path, raw)
            e, how, rest = stand.pick(self.command, u.path, raw.decode('utf-8', 'replace') if raw else None, u.query)
            rec = {"t": t, "method": self.command, "path": u.path, "query": u.query[:200], "endpoint": e["id"] if e else None,
                   "status": "UNMATCHED", "system": "", "code": 404, "match": how}
            ctx = stand.ctx
            if ctx:   # a direct test is running: keep what was SENT (secrets masked), and tag the request with the call
                rec.update(call=ctx.get("call"), side=ctx.get("side"), mode=ctx.get("mode"), query=u.query[:2000],
                           headers=mask_headers(self.headers.items()),
                           body=raw.decode("utf-8", "replace")[:BODY_KEEP] if raw else "")
            if not e:
                code, ct, body = 404, "application/json", json.dumps({"error": f"apimock: UNMATCHED {self.command} {u.path} ({how})"})
            elif e["status"] == "EXCLUDED":
                rec.update(status="EXCLUDED", system=e["system"])
                code, ct, body = 503, "application/json", json.dumps({"error": f"EXCLUDED: {e['system']} ({e['id']}): not stood in"})
            else:
                rec["status"] = e["status"]   # MOCKED, or UNKNOWN (answered, but the gate stays INVALID)
                code, ct, body = stand.answer(e, self.command, rest, q)
                if ctx and ctx.get("mode") == "500":   # error path of a direct test: a server error for any call
                    code, ct, body = 500, "application/json", json.dumps({"error": "apimock: injected 500"})
                elif ctx and ctx.get("mode") == "malformed":   # ... and a 200 whose body is not JSON
                    code, ct, body = 200, "application/json", '{"value": [ {"broken": '
            rec["code"] = code
            stand.log(rec)
            data = body.encode("utf-8") if isinstance(body, str) else body
            self.send_response(code)
            self.send_header("Content-Type", ct)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def control(self, path, raw):
            try:
                req = json.loads(raw.decode() or "{}")
            except ValueError:
                req = {}
            if path == "/__ad/call":
                mode = req.get("mode") or "ok"
                if mode not in FAULT_MODES:
                    return self.reply(400, {"error": f"mode {mode!r}: want one of {', '.join(FAULT_MODES)}"})
                stand.ctx = {"call": req.get("call"), "side": req.get("side"), "mode": mode}
            elif path == "/__ad/end":
                stand.ctx = None
            else:
                return self.reply(404, {"error": f"no control endpoint {path}"})
            self.reply(200, {"ctx": stand.ctx})

        def reply(self, code, obj):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = handle_any
    return H


# ------------------------------------------------------------------------------------------------ attribution (E2E-14)
def read_log(path):
    recs = []
    p = Path(path)
    if not p.is_file():
        return None
    for line in p.read_text().splitlines():
        try:
            r = json.loads(line)
            r["_t"] = datetime.fromisoformat(r["t"].replace("Z", "+00:00")).timestamp()
            recs.append(r)
        except (ValueError, KeyError):
            continue
    return recs


def ts(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def window_calls(recs, t0, t1, grace=1.0):
    a, b = ts(t0), ts(t1)
    if a is None or b is None:
        return None
    return [r for r in recs if a - grace <= r["_t"] <= b + grace]


def attribute(windows, recs, systems):
    """windows: [{"name", "t0", "t1", "ok"}] of ONE journey or smoke step. Returns (system names, why) when every
    failing window holds a call into an excluded system named in `systems` and no window holds an UNKNOWN or UNMATCHED
    call; else (None, why). The UNKNOWN / UNMATCHED test looks 1 s around each window (a stray call keeps the FAIL);
    the excluded-call test looks strictly inside the failing window (a neighbour's excluded call never excuses it)."""
    want = {s.lower() for s in systems}
    bad = [w for w in windows if not w.get("ok")]
    if not bad:
        return None, "no failing step"
    hit = set()
    for w in windows:
        calls = window_calls(recs, w.get("t0"), w.get("t1"))
        if calls is None:
            return None, f"{w.get('name')}: no step times (rerun with this toolkit's engine patch)"
        odd = [c for c in calls if c.get("status") in ("UNKNOWN", "UNMATCHED")]
        if odd:
            return None, f"{w.get('name')}: {odd[0]['status']} call {odd[0]['method']} {odd[0]['path']}"
        if w.get("ok"):
            continue
        ex = [c for c in window_calls(recs, w.get("t0"), w.get("t1"), grace=0.0)
              if c.get("status") == "EXCLUDED" and c.get("system", "").lower() in want]
        if not ex:
            return None, f"{w.get('name')} fails with no call into an excluded system"
        hit |= {f"{c['system']}" for c in ex}
        w["excluded_calls"] = sorted({f"{c['method']} {c['path']} ({c['endpoint']})" for c in ex})[:3]
    return sorted(hit), "; ".join(f"{w.get('name')}: {', '.join(w.get('excluded_calls', []))}" for w in bad)


def mark_journeys(journeys, log_path, systems):
    """run_journeys.py: FAIL journeys whose only failures are calls into excluded systems -> NOT CHECKED."""
    recs = read_log(log_path)
    lines = []
    if recs is None:
        return [f"apimock: no request log {log_path}: no journey can be NOT CHECKED"]
    for j, s in journeys.items():
        if s.get("verdict") != "FAIL" or not s.get("windows"):
            continue
        sysn, why = attribute([dict(w, name=f"step{w['n']}") for w in s["windows"]], recs, systems)
        if sysn:
            s["verdict"] = "NOT CHECKED"
            s["excluded"] = sysn
            s["why"] = f"excluded: {', '.join(sysn)}: {why}"
            lines.append(f"  NOT CHECKED (excluded: {', '.join(sysn)}) journey {j}: {why}"[:300])
    return lines


# ------------------------------------------------------------------------------------------------ commands
def cmd_inventory(a):
    inv = build_inventory(a.models, parse_excludes(a.exclude), read_classify(a.classify), a.recorded)
    print_inventory(inv)
    if a.json:
        Path(a.json).write_text(json.dumps(inv, indent=1, default=list) + "\n")
    sys.exit(EXIT_INVALID if any(e["status"] == "UNKNOWN" for e in inv["endpoints"]) else 0)


def cmd_serve(a):
    st = Path(a.state)
    st.mkdir(parents=True, exist_ok=True)
    if a.bind is None:
        # B4T2-5: an app in a container reaches the stand-in on the Docker gateway (--public-host 172.18.0.1); a stand-in
        # listening on 127.0.0.1 is unreachable from there. With --public-host the default is every interface.
        a.bind = "0.0.0.0" if a.public_host else "127.0.0.1"
    if a.background:
        args = [sys.executable, os.path.abspath(__file__), "serve", *a.models, "--state", str(st), "--port", str(a.port),
                "--bind", a.bind, "--public-host", a.public_host or a.bind]
        for x in a.exclude or []:
            args += ["--exclude", x]
        for k in ("classify", "recorded"):
            if getattr(a, k):
                args += [f"--{k}", getattr(a, k)]
        (st / "ready").unlink(missing_ok=True)
        with open(st / "serve.out", "w") as out:
            p = subprocess.Popen(args, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
        for _ in range(600):
            if (st / "ready").exists() or p.poll() is not None:
                break
            time.sleep(0.1)
        print((st / "serve.out").read_text(), end="")
        if not (st / "ready").exists():
            die(f"the stand-in did not start (see {st / 'serve.out'})")
        (st / "pid").write_text(str(p.pid))
        sys.exit(0)
    inv = build_inventory(a.models, parse_excludes(a.exclude), read_classify(a.classify), a.recorded)
    try:
        srv = ThreadingHTTPServer((a.bind, a.port), make_handler(Stand(inv, st, a.recorded)))
    except OSError as e:
        die(f"cannot listen on {a.bind}:{a.port}: {e}")
    base = f"http://{a.public_host or ('127.0.0.1' if a.bind == '0.0.0.0' else a.bind)}:{srv.server_address[1]}"
    ov = overrides(inv, base)
    (st / "inventory.json").write_text(json.dumps(inv, indent=1, default=list) + "\n")
    (st / "overrides.json").write_text(json.dumps(ov, indent=1) + "\n")
    (st / "coverage.txt").write_text(coverage_line(inv) + "\n")
    (st / "requests.jsonl").touch()
    print_inventory(inv)
    for k, v in ov.items():
        print(f"{k}={v}")
    for e in inv["endpoints"]:
        for k, r in e["routes"]:
            if k == "attr":
                print(f"data: set {r} to {base}/a/{r} in the seed data ({e['id']})")
    print(f"apimock: listening on {a.bind}:{srv.server_address[1]} as {base}; log {st / 'requests.jsonl'}; "
          f"CONST_OVERRIDES=$(cat {st / 'overrides.json'})", flush=True)
    (st / "ready").write_text(base + "\n")
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))   # stop: the log is line-buffered, nothing to flush
    srv.serve_forever()


def cmd_stop(a):
    p = Path(a.state) / "pid"
    if not p.is_file():
        die(f"no {p}: nothing to stop")
    try:
        os.kill(int(p.read_text()), signal.SIGTERM)
    except ProcessLookupError:
        pass
    p.unlink()
    (Path(a.state) / "ready").unlink(missing_ok=True)
    print("apimock: stopped")


def systems_arg(s):
    return [x.strip() for x in (s or "").split(",") if x.strip()]


def cmd_check(a):
    st = Path(a.state)
    if not (st / "inventory.json").is_file():
        die(f"no {st / 'inventory.json'}: start the stand-in with apimock.py serve --state {st}")
    inv = json.load(open(st / "inventory.json"))
    recs = read_log(st / "requests.jsonl") or []
    systems = {s.lower() for s in systems_arg(a.exclude_systems)}
    print_inventory(inv)
    eps = inv["endpoints"]
    unknown = [e for e in eps if e["status"] == "UNKNOWN"]
    excl = [e for e in eps if e["status"] == "EXCLUDED"]
    # a --classify EXCLUDED line carries its reason: the endpoint is INFO ("check at deploy"), not a stray exclusion
    info = [e for e in excl if e.get("classified")]
    stray = [e for e in excl if e["system"].lower() not in systems and not e.get("classified")]
    direct = None
    if a.direct:
        if not (Path(a.direct) / "direct.json").is_file():
            die(f"no {Path(a.direct) / 'direct.json'}: run apidirect.py compare --state {a.direct}")
        import apidirect
        direct = json.load(open(Path(a.direct) / "direct.json"))
        measured = {k for k, e in direct["endpoints"].items() if e["verdict"] in ("PASS", "FAIL")}
    else:
        measured = set()
    by = lambda s: [r for r in recs if r.get("status") == s]
    mocked = [e for e in eps if e["status"] == "MOCKED"]
    # B4N1-11: a MOCKED endpoint nobody called proves nothing: either no journey reached it, or the app never reached the
    # stand-in at all (Opcenter b4: 2 endpoints MOCKED, 0 requests, the old app failing on every page, verdict PASS).
    hits = {e["id"]: sum(1 for r in recs if r.get("endpoint") == e["id"] and r.get("status") == "MOCKED") for e in mocked}
    idle = [e for e in mocked if not hits[e["id"]] and e["id"] not in measured]
    unwaived = [e for e in idle if not e.get("unexercised")]
    answered = sum(hits.values())
    print(f"requests seen: {len(recs)}")
    print(f"requests {len(recs)} · mocked {len(by('MOCKED'))} · excluded {len(by('EXCLUDED'))} · unknown {len(by('UNKNOWN'))}"
          f" · unmatched {len(by('UNMATCHED'))}")
    for r in (by("UNKNOWN") + by("UNMATCHED"))[:10]:
        print(f"  {r['status']} request {r['method']} {r['path']} ({r.get('endpoint') or r.get('match')}) at {r['t']}")
    for e in excl:
        if e.get("classified"):
            print(f"  INFO (excluded: {e['system']}) endpoint {e['id']}: check at deploy")
        else:
            print(f"  NOT CHECKED (excluded: {e['system']}) endpoint {e['id']}")
    for e in idle:
        print(f"  NOT EXERCISED endpoint {e['id']}: 0 requests answered"
              + (f" (waived: {e['unexercised']})" if e.get("unexercised") else
                 ": no proof the app reaches the stand-in for it (call it in a journey, or waive it with a "
                 "'<pattern> UNEXERCISED # reason' --classify line)"))
    zero = bool(mocked) and answered == 0 and not measured   # a direct run that reached the stand-in shows it reachable
    drc, dlines = (apidirect.verdict(a.direct, info_lines=False) if direct else (0, []))
    for ln in dlines:
        print(ln)
    if unknown or by("UNKNOWN") or by("UNMATCHED") or stray or unwaived or zero:
        why = []
        if unknown:
            why.append(f"{len(unknown)} endpoints UNKNOWN (classify each: --classify, or point its data at the stand-in)")
        if by("UNKNOWN") or by("UNMATCHED"):
            why.append(f"{len(by('UNKNOWN')) + len(by('UNMATCHED'))} requests to UNKNOWN or UNMATCHED endpoints")
        if stray:
            why.append(f"{len(stray)} endpoints excluded for a system not in EXCLUDE_SYSTEMS ({', '.join(sorted({e['system'] for e in stray}))})")
        if zero:   # never waivable: no MOCKED answer at all means the stand-in was not shown reachable
            why.append(f"{len(mocked)} endpoints MOCKED and 0 requests answered: the stand-in was never shown reachable "
                       f"from the app (overrides.json passed as CONST_OVERRIDES? --bind reachable from the container? "
                       f"a location built from data seeded?)")
        elif unwaived:
            why.append(f"{len(unwaived)} MOCKED endpoints NOT EXERCISED (0 requests, no UNEXERCISED waiver)")
        if drc == 1:
            why.append(f"{direct['counts'].get('FAIL', 0)} REST calls differ between the old and the new app (direct API test)")
        print("verdict: " + ("FAIL" if drc == 1 else "INVALID") + ": " + "; ".join(why))
        sys.exit(1 if drc == 1 else EXIT_INVALID)
    if drc:
        print(dlines[-1].replace("verdict: ", "verdict: ", 1))
        sys.exit(drc)
    if len(info) < len(excl):
        rest = [e for e in excl if not e.get("classified")]
        print(f"verdict: PASS except {', '.join(sorted({e['system'] for e in rest}))}: {len(rest)} endpoints NOT CHECKED")
        sys.exit(EXIT_EXCEPT)
    if info:
        print(f"verdict: PASS (INFO: {len(info)} endpoints of {', '.join(sorted({e['system'] for e in info}))} are excluded, check at deploy)")
        sys.exit(0)
    print("verdict: PASS")
    sys.exit(0)


def cmd_standin(a):
    """E2E-15: what the stand-in answered instead of a real system (gate.sh reads these lines)."""
    st = Path(a.state)
    if not (st / "inventory.json").is_file():
        die(f"no {st / 'inventory.json'}: start the stand-in with apimock.py serve --state {st}")
    inv = json.load(open(st / "inventory.json"))
    recs = read_log(st / "requests.jsonl") or []
    mocked = [e for e in inv["endpoints"] if e["status"] == "MOCKED"]
    systems = []
    nreq = 0
    for e in mocked:
        sysn = e.get("system") or e.get("module") or e["doc"].split(".")[0]
        n = sum(1 for r in recs if r.get("endpoint") == e["id"] and r.get("status") == "MOCKED")
        nreq += n
        systems.append(sysn)
        print(f"  STAND-IN ({sysn}) endpoint {e['id']}: {n} requests answered")
    if mocked:
        print(f"stand-in systems: {', '.join(sorted(set(systems)))}")
    print(f"stand-in endpoints {len(mocked)} · requests answered {nreq}")
    sys.exit(0)


def cmd_attribute_smoke(a):
    st = Path(a.state)
    recs = read_log(st / "requests.jsonl")
    if recs is None:
        die(f"no request log {st / 'requests.jsonl'}")
    systems = systems_arg(a.exclude_systems)
    if not systems:
        die("--exclude-systems is empty: nothing can be NOT CHECKED")
    sm = json.load(open(a.smoke))
    left, marked = [], []
    for r in sm.get("roles", []):
        for s in r.get("steps", []):
            if s.get("verdict") in ("PASS", "SKIPPED"):
                continue
            name = f"{r.get('role')}: {s.get('caption')} -> {s.get('target')}"
            if s.get("verdict") != "FAIL":
                left.append(f"{s.get('verdict')} {name}")
                continue
            sysn, why = attribute([{"name": name, "t0": s.get("t0"), "t1": s.get("t1"), "ok": False}], recs, systems)
            if sysn:
                marked.append(f"  NOT CHECKED (excluded: {', '.join(sysn)}) smoke {name}: {why}"[:300])
            else:
                left.append(f"FAIL {name} ({why})")
    for m in marked:
        print(m)
    for l in left:
        print(f"  still {l}")
    if left or not marked:
        print(f"smoke attribution: {len(marked)} NOT CHECKED, {len(left)} other non-PASS steps: the rung keeps its verdict")
        sys.exit(1)
    print(f"smoke attribution: every FAIL step ({len(marked)}) called only an excluded system: NOT CHECKED")
    sys.exit(EXIT_EXCEPT)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("inventory", "serve"):
        p = sub.add_parser(name)
        p.add_argument("models", nargs="+")
        p.add_argument("--exclude", action="append", help="SYSTEM or SYSTEM=glob,glob (module, document, constant; host:glob)")
        p.add_argument("--classify", help="lines '<pattern> MOCKED|EXCLUDED <System> # reason'")
        p.add_argument("--recorded", help="folder of recorded responses <endpoint id>.json")
        if name == "inventory":
            p.add_argument("--json")
        else:
            p.add_argument("--state", required=True)
            p.add_argument("--port", type=int, default=int(os.environ.get("UPG_APIMOCK_PORT", 8790)))
            p.add_argument("--bind", default=None, help="address to listen on (default 127.0.0.1; 0.0.0.0 when "
                           "--public-host is given, so an app container can reach it, B4T2-5)")
            p.add_argument("--public-host", help="host the app reaches the stand-in on (default: --bind)")
            p.add_argument("--background", action="store_true")
    p = sub.add_parser("stop"); p.add_argument("--state", required=True)
    p = sub.add_parser("check"); p.add_argument("--state", required=True); p.add_argument("--exclude-systems", default="")
    p.add_argument("--direct", help="folder with direct.json of apidirect.py compare: measured per call, replaces the journey hits as proof")
    p = sub.add_parser("standin"); p.add_argument("--state", required=True)
    p = sub.add_parser("attribute-smoke"); p.add_argument("smoke"); p.add_argument("--state", required=True)
    p.add_argument("--exclude-systems", default="")
    a = ap.parse_args()
    {"inventory": cmd_inventory, "serve": cmd_serve, "stop": cmd_stop, "check": cmd_check, "standin": cmd_standin,
     "attribute-smoke": cmd_attribute_smoke}[a.cmd](a)


if __name__ == "__main__":
    main()
