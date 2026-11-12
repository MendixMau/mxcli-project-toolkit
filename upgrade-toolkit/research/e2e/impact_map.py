#!/usr/bin/env python3
"""impact_map.py: what did a Mendix upgrade change, and which user journeys does that touch, per user role.

    impact_map.py <old project dir|mpr> <new project dir|mpr> [--updates updates.txt]
                  [--out impact.json] [--md impact.md] [--catalog-check SCRATCH_DIR]

Reads both projects straight from their BSON (mprmodel.py; works for 9.x, 10.x and 11.x MPR v1/v2),
so it needs no Studio Pro and no mxbuild. Optional --catalog-check copies both .mpr files into
SCRATCH_DIR and cross-checks constants, scheduled events and published REST operations against
`mxcli catalog` (mxcli writes .mxcli/ next to the .mpr, so it never runs on the projects themselves).

Change kinds it reports
    module        marketplace/own module added, removed, version changed
    constant      default value or type changed, constant added or removed
    startup       after-startup / before-shutdown microflow swapped, or anything in its call tree changed
    scheduled     scheduled event added, removed, enabled flag, interval or microflow changed, or its tree changed
    document      microflow, nanoflow, java action, javascript action, page, snippet, layout, rule changed/removed
    caller        own-module document that calls a changed or removed marketplace document
    security      user role added/removed, module-role mapping changed, project security settings, module security
    service       published REST / OData / web service or operation added, removed or changed
Journey candidates
    Every change is traced up the caller graph to entry points a person (or a client) can reach:
    menu items, role home pages, pages with allowed roles, client-callable microflows, published
    operations, scheduled events, after-startup. Entry points are mapped to user roles through the
    module-role -> user-role mapping of the NEW project. Login, MFA and startup are always candidates
    when an authentication module, the login page, project security or the after-startup tree changed.

The `roles` section carries what the journey generator needs per user role: home page and a
landing widget, the top-level menu captions the role can and cannot see, and the login page widgets.
This is an impact map, not a requirement ledger (coverage-ledger): it says what to look at, not
what the app must do.
"""
import argparse, collections, json, os, re, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mprmodel import Model, SKIP_KEYS, text_of, module_role_to_user_roles  # noqa: E402

AUTH_MODULES = re.compile(r"(MFA|GoogleAuth|TOTP|SAML|SSO|OIDC|LDAP|Administration|UserCommons|ForgotPassword|"
                          r"Login|Authentication|Kerberos|DeepLink)", re.I)
FLOW_TYPES = {"Microflows$Microflow", "Microflows$Nanoflow", "Microflows$Rule", "JavaActions$JavaAction",
              "JavaScriptActions$JavaScriptAction"}
UI_TYPES = {"Forms$Page", "Forms$Snippet", "Forms$Layout"}
DOC_TYPES = FLOW_TYPES | UI_TYPES
SERVICE_TYPES = {"Rest$PublishedRestService", "Rest$PublishedODataService", "Rest$ConsumedODataService",
                 "WebServices$PublishedWebService", "WebServices$ImportedWebService", "Rest$ConsumedRestService"}
GENERIC_NAME = re.compile(r"^[a-z]+[A-Za-z]*\d+$")
EXTRA_SKIP = SKIP_KEYS | {"StableId", "Excluded", "MarkAsUsed", "Line"}  # Line: flow routing geometry (10.x)


# ---------------------------------------------------------------- version-tolerant equality
def _empty(v):
    if v in (None, "", False, 0, [], {}):
        return True
    if isinstance(v, list):
        return all((isinstance(i, int) and not isinstance(i, bool)) or _empty(i) for i in v)
    if isinstance(v, dict):  # e.g. a bare Microflows$NoCase that a newer version writes where the old wrote nothing
        return all(k in ("$Type", "$ID") or _empty(x) for k, x in v.items())
    return False


def same(a, b):
    """Equal in meaning: ignore ids and geometry, and keys that exist on one side only. Within one Studio Pro
    version every key is always written, so a one-sided key is a schema difference between the two versions
    (a new property such as IsRequired, or a rename such as CaseValue -> CaseValues), not an edit. A real
    edit still shows as a different value under a shared key or a different list. Trade-off: a value that
    moved to a renamed key is not compared. A conversion must not mark every document changed."""
    if isinstance(a, dict) and isinstance(b, dict):
        if a.get("$Type") != b.get("$Type"):
            return False
        for k in set(a) | set(b):
            if k in EXTRA_SKIP:
                continue
            if k in a and k in b and not same(a[k], b[k]):
                return False
        return True
    if isinstance(a, list) and isinstance(b, list):
        a2 = [i for i in a if not (isinstance(i, int) and not isinstance(i, bool))]
        b2 = [i for i in b if not (isinstance(i, int) and not isinstance(i, bool))]
        return len(a2) == len(b2) and all(same(x, y) for x, y in zip(a2, b2))
    if hasattr(a, "subtype") or isinstance(a, (bytes, bytearray)):
        return True
    return a == b


def strip_widget_defs(x):
    """Drop pluggable widget definition and property lists: what update-widgets rewrites."""
    if isinstance(x, dict):
        cw = x.get("$Type", "").startswith("CustomWidgets$CustomWidget")
        return {k: strip_widget_defs(v) for k, v in x.items() if not (cw and k in ("Type", "Object"))}
    if isinstance(x, list):
        return [strip_widget_defs(i) for i in x]
    return x


def first_diff(a, b, path=""):
    """Path of the first meaningful difference, for the report."""
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k in EXTRA_SKIP:
                continue
            if k in a and k in b:
                p = first_diff(a[k], b[k], f"{path}.{k}" if path else k)
                if p:
                    return p
        return None
    if isinstance(a, list) and isinstance(b, list):
        a2 = [i for i in a if not (isinstance(i, int) and not isinstance(i, bool))]
        b2 = [i for i in b if not (isinstance(i, int) and not isinstance(i, bool))]
        if len(a2) != len(b2):
            return f"{path}[len {len(a2)}->{len(b2)}]"
        for i, (x, y) in enumerate(zip(a2, b2)):
            p = first_diff(x, y, f"{path}[{i}]")
            if p:
                return p
        return None
    return None if same(a, b) else path


def _cval(c):
    """Constant default as the runtime reads it: Boolean 'True' and 'true' are the same value."""
    v = c.get("default")
    return str(v).lower() if c.get("type") == "Boolean" and v is not None else v


# ---------------------------------------------------------------- role facts (new project)
class Roles:
    def __init__(self, m):
        self.m = m
        self.mr2ur = module_role_to_user_roles(m)
        self.all = sorted(m.user_roles())
        sec = m.singletons.get("Security$ProjectSecurity", {})
        self.admin = sec.get("AdminUserRole")
        self.guest = sec.get("GuestUserRole") if sec.get("EnableGuestAccess") else None

    def of_module_roles(self, mrs):
        out = set()
        for mr in mrs or []:
            out |= self.mr2ur.get(mr, set())
        return out

    def of_doc(self, qn):
        d = self.m.docs.get(qn)
        if not d:
            return set()
        if d.type == "Forms$Page":
            return self.of_module_roles(self.m.page_roles(qn))
        if d.type in ("Microflows$Microflow", "Microflows$Nanoflow"):
            return self.of_module_roles(d.data.get("AllowedModuleRoles"))
        if d.type in SERVICE_TYPES:
            return self.of_module_roles(d.data.get("AllowedRoles"))
        return set()


def landing_widget(m, page_qn, exclude=()):
    """A widget on the page itself (not its layout) to use as the landing guard; distinctive names first.
    Names in `exclude` (widgets the login page or the guest home also render) are skipped: a guard that
    the login screen satisfies would let a failed login pass."""
    ws = [w for w in m.widgets(page_qn) if isinstance(w.get("Name"), str) and w["Name"] not in exclude
          and w.get("$Type") not in ("Forms$Page", "Forms$Snippet", "Forms$Layout")]
    good = [w for w in ws if not GENERIC_NAME.match(w["Name"])]
    pick = (good or ws)[:1]
    return {"widget": pick[0]["Name"], "type": pick[0]["$Type"], "generic_name": not good} if pick else None


def snippet_closure(m, qn, depth=3):
    out, frontier = [qn], [qn]
    for _ in range(depth):
        nxt = []
        for q in frontier:
            for r in m.refs(q):
                d = m.docs.get(r)
                if d and d.type == "Forms$Snippet" and r not in out:
                    out.append(r)
                    nxt.append(r)
        frontier = nxt
    return out


def login_facts(m, nav):
    prof = next(iter(nav.values()), {}) if nav else {}
    lp = prof.get("login_page") or ""
    found = {"login_page": lp, "id": None, "password": None, "button": None, "other_text_boxes": [], "docs": []}
    docs = snippet_closure(m, lp) if lp else []
    if not docs:  # default login.html: no model page
        return found
    found["docs"] = docs
    for q in docs:
        for w in m.widgets(q):
            t = w["$Type"]
            if t == "Forms$LoginIdTextBox":
                found["id"] = found["id"] or w["Name"]
            elif t == "Forms$PasswordTextBox":
                found["password"] = found["password"] or w["Name"]
            elif t == "Forms$LoginButton":
                found["button"] = found["button"] or w["Name"]
            elif t == "Forms$TextBox":
                found["other_text_boxes"].append({"widget": w["Name"], "in": q})
    return found


def role_facts(m, roles):
    nav = m.navigation()
    web = next((v for v in nav.values() if (v.get("kind") or "").lower().startswith("responsive")),
               next(iter(nav.values()), {}))
    menu = web.get("menu", [])
    tops = collections.OrderedDict()
    for it in menu:
        tops.setdefault(it["path"][0], []).append(it)
    out = {}
    pre_login = set()  # widget names visible before a real login: login page and guest home closures
    guest_home = next((h for h in web.get("homes", []) if h["role"] == roles.guest), None) if roles.guest else None
    for q in [web.get("login_page") or "", (guest_home or {}).get("page") or ""]:
        for d in (snippet_closure(m, q) if q else []):
            pre_login |= {w["Name"] for w in m.widgets(d) if isinstance(w.get("Name"), str)}
    for r in roles.all:
        default = next((h for h in web.get("homes", []) if h["role"] == "*"), {})
        home = next((h for h in web.get("homes", []) if h["role"] == r), None) or default
        visible, hidden = [], []
        for cap, items in tops.items():
            targets = [i for i in items if i["target"]]
            ok = any(r in roles.of_doc(i["target"]) for i in targets)
            if not targets:  # sign-out, url, no target: always shown
                ok = None
            if ok:
                visible.append(cap)
            elif ok is False:
                hidden.append(cap)
        hp = home.get("page") or ""
        out[r] = {"home_page": hp, "home_microflow": home.get("microflow") or "",
                  "home_role_specific": home is not default,
                  "landing": landing_widget(m, hp, () if r == roles.guest else pre_login) if hp else None,
                  "menu_visible": visible, "menu_hidden": hidden,
                  "sign_out_item": next((i["path"] for i in menu if i["kind"] == "SignOutClientAction"), None),
                  "is_admin": r == roles.admin, "is_guest": r == roles.guest}
    return out, web, nav


# ---------------------------------------------------------------- graph helpers
def flow_tree(m, root, limit=3000):
    """Transitive closure of flows/pages called from root (refs restricted to flow and java/js documents)."""
    seen, stack = set(), [root]
    while stack and len(seen) < limit:
        q = stack.pop()
        if q in seen or q not in m.docs:
            continue
        seen.add(q)
        for r in m.refs(q):
            d = m.docs.get(r)
            if d and d.type in FLOW_TYPES and r not in seen:
                stack.append(r)
    return seen


def tree_refs_constants(m, tree):
    out = set()
    for q in tree:
        for r in m.refs(q):
            d = m.docs.get(r)
            if d and d.type == "Constants$Constant":
                out.add(r)
    return out


class EntryFinder:
    """Walk callers upward from a document to the entry points that reach it (new project)."""

    def __init__(self, m, roles, web, startup_tree, sched):
        self.m, self.roles = m, roles
        self.callers = m.callers_index()
        self.menu_by_target = collections.defaultdict(list)
        for it in web.get("menu", []):
            if it["target"]:
                self.menu_by_target[it["target"]].append(it["path"])
        self.home_pages = {h["page"]: h["role"] for h in web.get("homes", []) if h.get("page")}
        self.home_pages.update({h["microflow"]: h["role"] for h in web.get("homes", []) if h.get("microflow")})
        self.startup_tree = startup_tree
        self.sched = sched  # microflow -> event name

    def entries(self, qn, max_nodes=600, max_depth=8):
        out, seen = [], {qn}
        frontier = [(qn, [qn])]
        depth = 0
        while frontier and depth <= max_depth and len(seen) < max_nodes:
            nxt = []
            for q, path in frontier:
                d = self.m.docs.get(q)
                typ = d.type if d else ""
                if q in self.menu_by_target:
                    for mp in self.menu_by_target[q]:
                        out.append({"kind": "menu", "menu": mp, "target": q, "via": path,
                                    "roles": sorted(self.roles.of_doc(q))})
                if q in self.home_pages:
                    out.append({"kind": "home", "target": q, "via": path, "home_role": self.home_pages[q],
                                "roles": sorted(self.roles.of_doc(q))})
                if q in self.startup_tree:
                    out.append({"kind": "startup", "target": q, "via": path, "roles": []})
                if q in self.sched:
                    out.append({"kind": "scheduled", "target": self.sched[q], "via": path, "roles": []})
                if typ in SERVICE_TYPES:
                    out.append({"kind": "service", "target": q, "via": path, "roles": sorted(self.roles.of_doc(q))})
                if typ == "Forms$Page" and self.m.page_roles(q) and q not in self.menu_by_target:
                    out.append({"kind": "page", "target": q, "via": path, "roles": sorted(self.roles.of_doc(q))})
                if typ in ("Microflows$Microflow",) and d.data.get("AllowedModuleRoles"):
                    out.append({"kind": "client_microflow", "target": q, "via": path,
                                "roles": sorted(self.roles.of_doc(q))})
                for c in self.callers.get(q, ()):
                    cd = self.m.docs.get(c)
                    if not cd or c in seen:
                        continue
                    if cd.type in DOC_TYPES or cd.type in SERVICE_TYPES or cd.type == "Constants$Constant":
                        seen.add(c)
                        nxt.append((c, path + [c]))
            frontier = nxt
            depth += 1
        # one entry per (kind, target), shortest path kept
        best = {}
        for e in out:
            k = (e["kind"], e["target"], tuple(e.get("menu") or ()))
            if k not in best or len(e["via"]) < len(best[k]["via"]):
                best[k] = e
        return list(best.values())


# ---------------------------------------------------------------- diff
def diff(old, new, declared_updates=None):
    changes = []

    def add(kind, qn, detail, module=None, severity="medium", **kw):
        changes.append(dict(kind=kind, qn=qn, module=module or (qn.split(".")[0] if "." in qn else qn),
                            detail=detail, severity=severity, **kw))

    # modules
    for name in sorted(set(old.modules) | set(new.modules)):
        o, n = old.modules.get(name), new.modules.get(name)
        if not o:
            add("module", name, f"added ({n['version'] or 'own'})", severity="high" if AUTH_MODULES.search(name) else "medium",
                old=None, new=n["version"])
        elif not n:
            add("module", name, f"removed (was {o['version'] or 'own'})", severity="high", old=o["version"], new=None)
        elif o["version"] != n["version"]:
            add("module", name, f"{o['version']} -> {n['version']}",
                severity="high" if AUTH_MODULES.search(name) else "medium", old=o["version"], new=n["version"])
    if declared_updates:
        found = {c["qn"] for c in changes if c["kind"] == "module"}
        for name in declared_updates:
            if name not in found:
                add("module", name, "declared in the update list but the project shows no version change",
                    severity="info")

    # constants
    for qn in sorted({d.qn for d in old.of_type("Constants$Constant")} | {d.qn for d in new.of_type("Constants$Constant")}):
        o, n = old.constant(qn), new.constant(qn)
        if o and not n:
            add("constant", qn, f"removed (default was {o['default']!r})", severity="high", old=o, new=None)
        elif n and not o:
            add("constant", qn, f"added, default {n['default']!r} ({n['type']})", severity="low", old=None, new=n,
                added=True)
        elif _cval(o) != _cval(n) or o["type"] != n["type"]:
            add("constant", qn, f"default {o['default']!r} -> {n['default']!r}" +
                (f", type {o['type']} -> {n['type']}" if o["type"] != n["type"] else ""),
                severity="high", old=o, new=n)

    # after-startup / before-shutdown
    oa, na = old.after_startup(), new.after_startup()
    for k in ("AfterStartupMicroflow", "BeforeShutdownMicroflow", "HealthCheckMicroflow"):
        if (oa.get(k) or "") != (na.get(k) or ""):
            add("startup", na.get(k) or oa.get(k) or k, f"{k}: {oa.get(k) or '(none)'} -> {na.get(k) or '(none)'}",
                module="(project)", severity="high")
    o_tree = flow_tree(old, oa.get("AfterStartupMicroflow") or "")
    n_tree = flow_tree(new, na.get("AfterStartupMicroflow") or "")
    t_added = sorted(n_tree - o_tree)
    t_removed = sorted(o_tree - n_tree)
    t_changed = sorted(q for q in o_tree & n_tree if not same(old.docs[q].data, new.docs[q].data))
    if t_added or t_removed or t_changed:
        add("startup", na.get("AfterStartupMicroflow") or "(none)",
            f"after-startup call tree: {len(t_added)} added, {len(t_removed)} removed, {len(t_changed)} changed "
            f"(old tree {len(o_tree)}, new tree {len(n_tree)})", module="(project)", severity="high",
            added=t_added, removed=t_removed, changed=t_changed,
            # still in the new model but no longer run at startup: a deprecated or replaced startup flow
            # (E1: MFAmodule 5 left ASU_MFA in place, hollowed out, and the project tree stopped calling it)
            not_called=[q for q in t_removed if q in new.docs])
    for c in [c for c in changes if c["kind"] == "constant"]:
        users_new = [q for q in n_tree if c["qn"] in new.refs(q)]
        users_old = [q for q in o_tree if c["qn"] in old.refs(q)]
        if users_new or users_old:
            c["severity"] = "medium" if c.get("added") else "high"
            c["in_startup_tree"] = sorted(set(users_new) | set(users_old))

    # scheduled events
    def sched(m):
        return {d.qn: d.data for d in m.of_type("ScheduledEvents$ScheduledEvent")}
    os_, ns_ = sched(old), sched(new)
    for qn in sorted(set(os_) | set(ns_)):
        o, n = os_.get(qn), ns_.get(qn)
        if not n:
            add("scheduled", qn, "removed", severity="high")
            continue
        if not o:
            add("scheduled", qn, f"added (enabled={n.get('Enabled')}, {n.get('Microflow')})",
                severity="medium" if n.get("Enabled") else "low")
            continue
        bits = []
        for k in ("Enabled", "Microflow", "Interval", "IntervalType", "StartDateTime", "OnOverlap"):
            if o.get(k) != n.get(k) and not (o.get(k) is None and n.get(k) in ("", None)):
                bits.append(f"{k} {o.get(k)} -> {n.get(k)}")
        ot, nt = flow_tree(old, o.get("Microflow") or ""), flow_tree(new, n.get("Microflow") or "")
        tc = sorted(q for q in ot & nt if not same(old.docs[q].data, new.docs[q].data)) + sorted(nt ^ ot)
        if tc:
            bits.append(f"call tree changed ({len(tc)} documents)")
        if bits:
            add("scheduled", qn, "; ".join(bits), severity="high" if n.get("Enabled") else "low",
                tree_changed=tc[:50])

    # documents (flows, pages)
    changed_docs, removed_docs = [], []
    for qn, od in old.docs.items():
        if od.type not in DOC_TYPES:
            continue
        nd = new.docs.get(qn)
        if not nd:
            removed_docs.append(qn)
        elif not same(od.data, nd.data):
            changed_docs.append(qn)
    added_docs = sorted(q for q, d in new.docs.items() if d.type in DOC_TYPES and q not in old.docs)
    own = {n for n, i in new.modules.items() if not i["from_appstore"]}
    for qn in sorted(removed_docs):
        add("document", qn, f"{old.docs[qn].type.split('$')[1]} removed",
            severity="high" if qn.split(".")[0] in own else "medium", doc_type=old.docs[qn].type)
    widget_only = set()
    for qn in sorted(changed_docs):
        od, nd = old.docs[qn], new.docs[qn]
        if same(strip_widget_defs(od.data), strip_widget_defs(nd.data)):
            widget_only.add(qn)
            add("document", qn, f"{nd.type.split('$')[1]}: only pluggable widget definitions refreshed",
                severity="low", doc_type=nd.type, widget_refresh=True)
            continue
        where = (f"type {od.type} -> {nd.type}" if od.type != nd.type else f"at {first_diff(od.data, nd.data)}")
        add("document", qn, f"{nd.type.split('$')[1]} changed {where}",
            severity="medium" if qn.split(".")[0] in own else "low", doc_type=nd.type)
    for qn in added_docs:
        if qn.split(".")[0] in own:
            add("document", qn, f"{new.docs[qn].type.split('$')[1]} added in own module", severity="low",
                doc_type=new.docs[qn].type)

    # own-module callers of changed/removed marketplace documents
    vendor_touched = {q for q in changed_docs + removed_docs if q.split(".")[0] not in own and q not in widget_only}
    callers = new.callers_index()
    for q in sorted(q for q in vendor_touched if old.docs[q].type == "Forms$Layout"):
        users = [c for c in callers.get(q, ()) if new.docs.get(c) and new.docs[c].type == "Forms$Page"]
        own_users = [c for c in users if c.split(".")[0] in own]
        if own_users:
            add("caller", q, f"layout changed; used by {len(own_users)} own pages (theme/visual impact: smoke walk "
                f"and screenshots, not one journey per page)", severity="medium", target=q, layout=True,
                pages=sorted(own_users))
    for q in sorted(q for q in vendor_touched if old.docs[q].type != "Forms$Layout"):
        for c in sorted(callers.get(q, ())):
            cd = new.docs.get(c)
            if cd and c.split(".")[0] in own and cd.type in DOC_TYPES | SERVICE_TYPES:
                add("caller", c, f"calls {q} ({'removed' if q in removed_docs else 'changed'})", severity="high"
                    if q in removed_docs else "medium", target=q)
    # removed documents still referenced (dangling)
    for q in sorted(removed_docs):
        for c in sorted(callers.get(q, ())):
            add("caller", c, f"still references removed {q}", severity="high", target=q)

    # security
    our, nur = old.user_roles(), new.user_roles()
    for r in sorted(set(our) | set(nur)):
        if r not in nur:
            add("security", r, "user role removed", module="(security)", severity="high")
        elif r not in our:
            add("security", r, "user role added", module="(security)", severity="medium")
        elif our[r] != nur[r]:
            plus, minus = sorted(set(nur[r]) - set(our[r])), sorted(set(our[r]) - set(nur[r]))
            add("security", r, f"module roles +{plus} -{minus}", module="(security)", severity="high",
                added=plus, removed=minus)
    os_sum, ns_sum = old.security_summary(), new.security_summary()
    for k in os_sum:
        if not same(os_sum[k], ns_sum.get(k)):
            add("security", k, f"{os_sum[k]} -> {ns_sum.get(k)}", module="(security)", severity="high")
    for qn, od in old.docs.items():
        if od.type == "Security$ModuleSecurity":
            nd = new.docs.get(qn)
            if nd and not same(od.data, nd.data):
                orl = {r.get("Name") for r in od.data.get("ModuleRoles") or [] if isinstance(r, dict)}
                nrl = {r.get("Name") for r in nd.data.get("ModuleRoles") or [] if isinstance(r, dict)}
                add("security", qn, f"module roles +{sorted(nrl - orl)} -{sorted(orl - nrl)}"
                    if orl != nrl else "module security changed (access rules or role details)",
                    severity="high" if orl - nrl else "medium")
    # page access: a page lost or gained roles
    for qn, od in old.docs.items():
        nd = new.docs.get(qn)
        if od.type == "Forms$Page" and nd:
            o, n = set(old.page_roles(qn)), set(new.page_roles(qn))
            if o != n:
                add("security", qn, f"page allowed roles +{sorted(n - o)} -{sorted(o - n)}",
                    severity="high" if o - n else "medium")

    # services
    def services(m):
        out = {}
        for d in m.docs.values():
            if d.type in SERVICE_TYPES:
                out[d.qn] = d
        return out
    osv, nsv = services(old), services(new)
    for qn in sorted(set(osv) | set(nsv)):
        o, n = osv.get(qn), nsv.get(qn)
        if not n:
            add("service", qn, f"{o.type.split('$')[1]} removed", severity="high")
        elif not o:
            add("service", qn, f"{n.type.split('$')[1]} added", severity="low")
        elif not same(o.data, n.data):
            add("service", qn, f"{n.type.split('$')[1]} changed at {first_diff(o.data, n.data)}", severity="high")
        else:
            # operation microflows changed?
            ops = [op for res in n.data.get("Resources") or [] if isinstance(res, dict)
                   for op in res.get("Operations") or [] if isinstance(op, dict)]
            hit = [op.get("Microflow") for op in ops if op.get("Microflow") in set(changed_docs)]
            if hit:
                add("service", qn, f"operation microflows changed: {hit}", severity="medium")

    return changes, {"startup_tree_old": len(o_tree), "startup_tree_new": len(n_tree),
                     "changed_docs": len(changed_docs), "removed_docs": len(removed_docs),
                     "added_docs": len(added_docs), "own_modules": sorted(own)}


# ---------------------------------------------------------------- candidates
SEV = {"high": 3, "medium": 2, "low": 1, "info": 0}


def candidates(old, new, changes, roles, rfacts, web):
    na = new.after_startup()
    startup_tree = flow_tree(new, na.get("AfterStartupMicroflow") or "")
    sched = {d.data.get("Microflow"): d.qn for d in new.of_type("ScheduledEvents$ScheduledEvent")}
    ef = EntryFinder(new, roles, web, startup_tree, sched)
    login = login_facts(new, {k: v for k, v in new.navigation().items() if v is web} or new.navigation())
    login_docs = set(login["docs"])
    cands = {}

    def cand(cid, kind, title, roles_, reason, sev, **kw):
        c = cands.setdefault(cid, dict(id=cid, kind=kind, title=title, roles=set(), reasons=[], score=0, **kw))
        c["roles"] |= set(roles_)
        if reason not in c["reasons"]:
            c["reasons"].append(reason)
        c["score"] = max(c["score"], SEV.get(sev, 1))

    human = [r for r in roles.all if r != roles.guest]
    auth_hit = []
    for ch in changes:
        why = f"{ch['kind']}: {ch['qn']}: {ch['detail']}"
        mod = ch["module"]
        is_auth = bool(AUTH_MODULES.search(mod or "")) or ch["qn"] in login_docs
        if ch["kind"] == "startup" or (ch["kind"] == "constant" and ch.get("in_startup_tree")):
            cand("startup", "startup", "App starts clean and the startup work is done (log + login per role)",
                 human, why, "high")
        if is_auth and ch["severity"] in ("high", "medium") and ch["kind"] != "document":
            auth_hit.append(why)
        if ch["kind"] == "constant" and is_auth:
            auth_hit.append(why)
        if ch["kind"] == "security":
            cand("login-per-role", "login", "Login per role lands on the role home with the role menu",
                 human, why, ch["severity"])
        if ch["kind"] == "scheduled":
            cand(f"sched:{ch['qn']}", "scheduled", f"Scheduled event {ch['qn']} still runs and does its work", [],
                 why, ch["severity"], target=ch["qn"])
        if ch["kind"] == "service":
            cand(f"svc:{ch['qn']}", "service", f"Published service {ch['qn']} answers as before (REST gate)",
                 sorted(roles.of_doc(ch["qn"])), why, ch["severity"], target=ch["qn"])
        if ch.get("layout"):
            cand("visual-smoke", "visual", "Smoke walk with screenshots over pages that use a changed layout",
                 human, why, "medium", pages=len(ch.get("pages", [])))
            continue
        if ch["kind"] in ("caller", "document", "constant") and ch["severity"] != "info":
            if ch["kind"] == "document" and ch["severity"] == "low":
                # vendor-internal edits and widget refreshes: only traced when an own document calls them ('caller')
                continue
            ents = ef.entries(ch["qn"])
            # a person reaches it through a menu or home page: that is the journey. Fall back to the nearest
            # role-gated page or client microflow only when no menu/home path exists (max 2).
            # Fallbacks only when nothing better exists, only if some user role can reach them (max 2).
            if any(e["kind"] in ("menu", "home", "startup", "scheduled", "service") for e in ents):
                ents = [e for e in ents if e["kind"] not in ("page", "client_microflow")]
            else:
                fb = sorted([e for e in ents if e["kind"] in ("page", "client_microflow") and e["roles"]],
                            key=lambda e: len(e["via"]))
                ents = [e for e in ents if e["kind"] not in ("page", "client_microflow")] + fb[:2]
            for e in ents:
                if e["kind"] == "menu":
                    cid = "menu:" + " > ".join(e["menu"])
                    cand(cid, "menu", f"Open {' > '.join(e['menu'])} and use it", e["roles"], why, ch["severity"],
                         menu=e["menu"], target=e["target"], via=e["via"])
                elif e["kind"] == "home":
                    cand(f"home:{e['target']}", "home", f"Role home page {e['target']} works",
                         e["roles"] or ([e["home_role"]] if e["home_role"] != "*" else human), why, ch["severity"],
                         target=e["target"], via=e["via"])
                elif e["kind"] == "startup":
                    cand("startup", "startup", "App starts clean and the startup work is done (log + login per role)",
                         human, why, ch["severity"])
                elif e["kind"] == "scheduled":
                    cand(f"sched:{e['target']}", "scheduled", f"Scheduled event {e['target']} still runs", [], why,
                         ch["severity"], target=e["target"])
                elif e["kind"] == "service":
                    cand(f"svc:{e['target']}", "service", f"Published service {e['target']} answers as before",
                         e["roles"], why, ch["severity"], target=e["target"])
                elif e["kind"] in ("page", "client_microflow"):
                    cand(f"{e['kind']}:{e['target']}", e["kind"],
                         f"Reach {e['target']} (no menu item; opened from another page)", e["roles"], why,
                         max(1, SEV[ch["severity"]] - 1) and ch["severity"], target=e["target"], via=e["via"])
    # Updated marketplace modules: their own role-gated pages that changed (admin dashboards, account pages).
    # No own document calls them, so the caller trace misses them; E5's TaskQueueHelpers dashboard is one.
    updated = {c["qn"] for c in changes if c["kind"] == "module" and c.get("old") and c.get("new")}
    for mod in sorted(updated):
        pages = []
        for c in changes:
            if c["kind"] == "document" and c["module"] == mod and c.get("doc_type") == "Forms$Page":
                rs = roles.of_doc(c["qn"])
                if rs:
                    pages.append((c["qn"], sorted(rs), bool(c.get("widget_refresh"))))
        if pages:
            pages.sort(key=lambda p: (p[2], p[0]))  # real edits before widget-definition refreshes
            cand(f"module-pages:{mod}", "module-pages",
                 f"Open the changed {mod} pages a role can reach and look at them (screenshot old vs new)",
                 sorted({r for p in pages for r in p[1]}), f"module: {mod} updated; {len(pages)} changed role-gated "
                 f"pages: {', '.join(p[0] for p in pages[:6])}", "medium", pages=[p[0] for p in pages])
    if auth_hit:
        for w in auth_hit:
            cand("login-per-role", "login", "Login per role lands on the role home with the role menu", human, w, "high")
        mfa_mods = [n for n in new.modules if re.search(r"MFA|GoogleAuth|TOTP", n, re.I)]
        if mfa_mods:
            for w in auth_hit:
                cand("mfa", "mfa", "A user with a second factor is challenged for the code after the password",
                     human, w, "high", modules=mfa_mods)
    for c in cands.values():
        c["roles"] = sorted(c["roles"])
        c["priority"] = {3: "P1", 2: "P2", 1: "P3", 0: "P3"}[c["score"]]
    return sorted(cands.values(), key=lambda c: (-c["score"], c["kind"], c["id"])), login


# ---------------------------------------------------------------- catalog cross-check
def catalog_check(old_mpr, new_mpr, scratch, mxcli):
    q = {"constants": "SELECT QualifiedName, DefaultValue, DataType FROM CATALOG.CONSTANTS",
         "scheduled": "SELECT Name, Enabled, Microflow FROM CATALOG.SCHEDULED_EVENTS",
         "rest_ops": "SELECT * FROM CATALOG.PUBLISHED_REST_OPERATIONS"}
    res = {}
    for tag, mpr in (("old", old_mpr), ("new", new_mpr)):
        d = os.path.join(scratch, tag)
        os.makedirs(d, exist_ok=True)
        dst = os.path.join(d, os.path.basename(mpr))
        shutil.copy2(mpr, dst)
        res[tag] = {}
        first = True
        for k, sql in q.items():
            pre = "REFRESH CATALOG FULL; " if first else ""
            first = False
            p = subprocess.run([mxcli, "-p", dst, "-c", pre + sql + ";"], capture_output=True, text=True, timeout=1200)
            rows = []
            for line in p.stdout.splitlines():
                if line.startswith("|") and not line.startswith("|--"):
                    rows.append([c.strip() for c in line.strip("|").split("|")])
            res[tag][k] = rows[1:] if rows else []
            res[tag][k + "_header"] = rows[0] if rows else []
    oc = {r[0]: r[1] for r in res["old"]["constants"]}
    nc = {r[0]: r[1] for r in res["new"]["constants"]}
    const_changed = sorted(k for k in set(oc) & set(nc) if oc[k] != nc[k])
    return {"constants_changed": [{"qn": k, "old": oc[k], "new": nc[k]} for k in const_changed],
            "constants_added": sorted(set(nc) - set(oc)), "constants_removed": sorted(set(oc) - set(nc)),
            "scheduled_old": res["old"]["scheduled"], "scheduled_new": res["new"]["scheduled"],
            "rest_ops_old": len(res["old"]["rest_ops"]), "rest_ops_new": len(res["new"]["rest_ops"])}


# ---------------------------------------------------------------- report
def markdown(rep):
    L = [f"# Upgrade impact map", "", f"old: `{rep['old']}`  ", f"new: `{rep['new']}`", "",
         "This maps changes to journeys to look at. It is not a requirement ledger.", ""]
    s = rep["stats"]
    L += [f"After-startup: `{rep['after_startup']['old']}` -> `{rep['after_startup']['new']}` "
          f"(tree {s['startup_tree_old']} -> {s['startup_tree_new']} documents)  ",
          f"Documents: {s['changed_docs']} changed, {s['removed_docs']} removed, {s['added_docs']} added", ""]
    by = collections.defaultdict(list)
    for c in rep["changes"]:
        by[c["kind"]].append(c)
    for kind in ("module", "constant", "startup", "scheduled", "security", "service", "caller", "document"):
        rows = sorted(by.get(kind, []), key=lambda c: (-SEV[c["severity"]], c["qn"]))
        if not rows:
            continue
        L += [f"## {kind} ({len(rows)})", ""]
        cap = 40 if kind == "document" else 200
        for c in rows[:cap]:
            extra = ""
            if c.get("in_startup_tree"):
                extra = f" (read in the startup tree by {', '.join(c['in_startup_tree'][:4])})"
            L.append(f"- [{c['severity']}] `{c['qn']}`: {c['detail']}{extra}")
            if kind == "startup" and (c.get("removed") or c.get("changed")):
                nc = set(c.get("not_called", []))
                if nc:
                    L.append(f"  - no longer called at startup but still in the model (deprecated or replaced?): {', '.join(sorted(nc))}")
                gone = [q for q in c.get("removed", []) if q not in nc]
                if gone:
                    L.append(f"  - removed from the model: {', '.join(gone[:12])}")
                if c.get("changed"):
                    L.append(f"  - changed in the tree: {', '.join(c['changed'][:12])}")
        if len(rows) > cap:
            L.append(f"- ... {len(rows) - cap} more (see the JSON)")
        L.append("")
    L += ["## Journey candidates", ""]
    for c in rep["candidates"]:
        L.append(f"- **{c['priority']} {c['id']}**: {c['title']}  ")
        L.append(f"  roles: {', '.join(c['roles']) or '(system, no role)'}  ")
        for r in c["reasons"][:4]:
            L.append(f"  because {r}  ")
        if len(c["reasons"]) > 4:
            L.append(f"  ... and {len(c['reasons']) - 4} more reasons  ")
    L += ["", "## Per role", ""]
    for r, f in rep["roles"].items():
        cs = [c["id"] for c in rep["candidates"] if r in c["roles"]]
        L.append(f"- **{r}** home `{f['home_page'] or f['home_microflow']}`; candidates: {', '.join(cs) or 'none'}")
    if rep.get("catalog_check"):
        cc = rep["catalog_check"]
        L += ["", "## mxcli catalog cross-check", "",
              f"constants changed (catalog): {[(c['qn'], c['old'], c['new']) for c in cc['constants_changed']]}  ",
              f"agrees with the BSON diff: {cc.get('agrees')}"]
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--updates", help="module update list: one module name per line (extra text ignored)")
    ap.add_argument("--out", help="write the full JSON here")
    ap.add_argument("--md", help="write the markdown report here")
    ap.add_argument("--catalog-check", metavar="SCRATCH", help="cross-check with mxcli catalog on copies in SCRATCH")
    ap.add_argument("--mxcli", default=os.environ.get("MXCLI", os.path.expanduser("~/.local/bin/mxcli")))
    a = ap.parse_args()
    old, new = Model.load(a.old), Model.load(a.new)
    declared = None
    if a.updates:
        declared = [ln.split()[0] for ln in open(a.updates) if ln.strip() and not ln.startswith("#")]
    changes, stats = diff(old, new, declared)
    roles = Roles(new)
    rfacts, web, _ = role_facts(new, roles)
    cands, login = candidates(old, new, changes, roles, rfacts, web)
    mfa_consts = {}
    for d in new.of_type("Constants$Constant"):
        if AUTH_MODULES.search(d.module) and re.search(r"enable", d.qn, re.I):
            mfa_consts[d.qn] = {"old": (old.constant(d.qn) or {}).get("default"), "new": new.constant(d.qn)["default"]}
    rep = {"old": old.path, "new": new.path,
           "after_startup": {"old": old.after_startup().get("AfterStartupMicroflow"),
                             "new": new.after_startup().get("AfterStartupMicroflow")},
           "stats": stats, "changes": changes, "candidates": cands, "roles": rfacts, "login": login,
           "auth": {"modules": sorted(n for n in new.modules if AUTH_MODULES.search(n)),
                    "enable_constants": mfa_consts},
           "user_roles": {"admin": roles.admin, "guest": roles.guest, "all": roles.all}}
    if a.catalog_check:
        cc = catalog_check(old.path, new.path, a.catalog_check, a.mxcli)
        bson_c = {c["qn"] for c in changes if c["kind"] == "constant" and c.get("old") and c.get("new")}
        cc["agrees"] = bson_c == {c["qn"] for c in cc["constants_changed"]}
        rep["catalog_check"] = cc
    if a.out:
        with open(a.out, "w") as f:
            json.dump(rep, f, indent=1, default=str)
    md = markdown(rep)
    if a.md:
        open(a.md, "w").write(md)
    if not a.out and not a.md:
        print(md)
    else:
        hi = [c for c in changes if c["severity"] == "high"]
        print(f"{len(changes)} changes ({len(hi)} high), {len(cands)} journey candidates; "
              f"after-startup {rep['after_startup']['old']} -> {rep['after_startup']['new']}")


if __name__ == "__main__":
    main()
