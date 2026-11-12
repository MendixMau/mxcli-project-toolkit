#!/usr/bin/env python3
"""access_matrix.py: which user role may do what in an app, and what an upgrade changed in it (quality plan L1b).

    access_matrix.py matrix <project dir|mpr> [--out matrix.json]
    access_matrix.py diff <OLD model|matrix.json> <NEW model|matrix.json> [--out diff.json]

Inputs: the OLD and NEW project models, which the upgrade already has (the source project and the upgraded project,
the same two impact_map.py reads). This script produces neither; it reads both straight from BSON through mprmodel.py
(needs the bson module, no Studio Pro, no mxbuild). A matrix written by `matrix --out` may stand in for a model on
either side of `diff`, so two matrices compare without the bson module.

What a matrix holds, per user role (its module roles resolved through Security$ProjectSecurity):
    entity   create, delete, and read / write per member (attribute or association). Every access rule whose module
             roles the user role holds counts; a member a rule does not list takes that rule's default right; the best
             right over the rules wins. Tokens: "create Mod.Entity", "delete Mod.Entity", "read Mod.Entity.Attr",
             "write Mod.Entity.Attr" (an association member is "Mod.Assoc").
    xpath    the XPath constraints of the rules that grant something on an entity, whitespace-normalised (runs of
             whitespace collapse to one space; nothing else changes). Kept per entity, as a sorted list.
    page     "page Mod.Page" for each page not Excluded whose allowed module roles the user role holds.
    flow     "flow Mod.Flow" for each microflow and nanoflow not Excluded whose allowed module roles it holds.
    guest    "guest access" for the guest role, when guest access is on.

diff compares two matrices, user roles by name and module roles by Module.Name, and prints one line per change:
    REVIEW <role>: gained <token>            the NEW app gives a right the OLD app did not
    REVIEW <role>: lost <token>              the OLD app gave a right the NEW app does not
    REVIEW <role>: xpath <entity>: <old> -> <new>
    REVIEW <role>: gained|lost module role <Mod.Role>
    REVIEW <role>: gained|lost role (exists only in NEW|OLD, N rights)
    REVIEW <Mod.Role>: gained|lost module role (exists only in NEW|OLD)
    note: platform module <System> (...)      a Mendix platform module the MPR does not hold (not partial)
    not compared: <module> (<reason>)        a module with no readable domain model, or a module role whose module is
                                             missing: its entity rights are not compared, and it is never silent
Summary: "access diff: N objects × R roles compared, G gained, L lost, X xpath changed". N counts the guarded objects
(entities, pages, flows) of both models; R counts the user roles present on both sides.

Exit: 0 no difference; 1 any REVIEW line; 2 usage; 3 a model that could not be read, or a comparison that was partial
(a module not compared) with no REVIEW line. A partial comparison is never reported as "no difference".
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

RANK = {"None": 0, "ReadOnly": 1, "ReadWrite": 2}
MATRIX_KEY = "access_matrix"
# Platform modules: the Mendix runtime defines them, so a project's MPR does not hold them. Their roles are compared by
# name; their entity rules are not in the model, and a note says so. They do not make a comparison partial.
PLATFORM_MODULES = {"System"}


class Unreadable(Exception):
    """A model or matrix that cannot be read, or a matrix that is not one."""


def ws(s):
    """XPath text with whitespace runs collapsed: the only normalisation a comparison applies."""
    return " ".join(str(s or "").split())


def dicts(xs):
    return [x for x in (xs or []) if isinstance(x, dict)]


def strs(xs):
    return [x for x in (xs or []) if isinstance(x, str)]


def load_model(path):
    """mprmodel.Model for a project dir or .mpr. Every failure is Unreadable, never a partial model."""
    if not os.path.exists(path):
        raise Unreadable(f"{path}: no such file or directory")
    try:
        import mprmodel
        m = mprmodel.Model.load(path)
    except SystemExit as e:  # mprmodel exits on: no bson module, not exactly one .mpr
        raise Unreadable(f"{path}: {e.code}")
    except Exception as e:  # sqlite: not a database, no Unit table, locked
        raise Unreadable(f"{path}: {type(e).__name__}: {e}")
    if not m.modules:
        raise Unreadable(f"{path}: no module units could be read")
    return m


def entity_rights(mrs, qn, ent):
    """Tokens and XPath constraints one user role (module roles mrs) holds on one entity."""
    toks, xps = set(), set()
    for r in ent["rules"]:
        if not set(r["roles"]) & mrs:
            continue
        grants = (r["create"] or r["delete"] or r["default"] != "None"
                  or any(v != "None" for v in r["members"].values()))
        if not grants:
            continue
        xps.add(r["xpath"])
        if r["create"]:
            toks.add(f"create {qn}")
        if r["delete"]:
            toks.add(f"delete {qn}")
    for mem in ent["members"]:
        best = 0
        for r in ent["rules"]:
            if set(r["roles"]) & mrs:
                best = max(best, RANK[r["members"].get(mem, r["default"])])
        if best >= 1:
            toks.add(f"read {mem}")
        if best >= 2:
            toks.add(f"write {mem}")
    return toks, sorted(xps)


def build(m, source):
    """The matrix of one model (a dict that is also the matrix JSON)."""
    sec = m.singletons.get("Security$ProjectSecurity", {})
    mr_of = {name: set(mrs) for name, mrs in m.user_roles().items()}
    guest = sec.get("GuestUserRole") if sec.get("EnableGuestAccess") else None
    admin = sec.get("AdminUserRole") or None
    readable = sorted(mod for mod in m.modules if f"{mod}.$DomainModel" in m.docs)
    not_compared = {mod: "no readable domain model" for mod in sorted(m.modules) if mod not in readable}
    platform = set()
    for ur in sorted(mr_of):
        for mr in sorted(mr_of[ur]):
            mod = mr.split(".")[0]
            if mod in m.modules:
                continue
            if mod in PLATFORM_MODULES:
                platform.add(mod)
            else:
                not_compared.setdefault(mod, f"module role {mr} of user role {ur} is not in the model")

    # Association members: an association is a member of both its ends (the pointers are entity $IDs).
    assoc_of = {}
    for mod in readable:
        dm = m.docs[f"{mod}.$DomainModel"].data
        for a in dicts(dm.get("Associations")):
            for p in ("ParentPointer", "ChildPointer"):
                if a.get(p):
                    assoc_of.setdefault(bytes(a[p]), set()).add(f"{mod}.{a['Name']}")
        for a in dicts(dm.get("CrossAssociations")):
            if a.get("ParentPointer"):
                assoc_of.setdefault(bytes(a["ParentPointer"]), set()).add(f"{mod}.{a['Name']}")

    entities = {}
    for mod in readable:
        for e in dicts(m.docs[f"{mod}.$DomainModel"].data.get("Entities")):
            qn = f"{mod}.{e['Name']}"
            members = {f"{qn}.{a['Name']}" for a in dicts(e.get("Attributes"))}
            members |= assoc_of.get(bytes(e["$ID"]), set())
            rules = []
            for r in dicts(e.get("AccessRules")):
                if "AllowedModuleRoles" not in r:  # a key this reader does not know: refuse, never read as "no roles"
                    raise Unreadable(f"{qn}: access rule without AllowedModuleRoles")
                mem = {}
                for ma in dicts(r.get("MemberAccesses")):
                    name = ma.get("Attribute") or ma.get("Association") or ""
                    if not name:
                        continue
                    rights = ma.get("AccessRights") or "None"
                    if rights not in RANK:
                        raise Unreadable(f"{qn}: access right {rights!r} is not one this reader knows")
                    mem[name] = rights
                    members.add(name)
                default = r.get("DefaultMemberAccessRights") or "None"
                if default not in RANK:
                    raise Unreadable(f"{qn}: default access right {default!r} is not one this reader knows")
                rules.append({"roles": sorted(set(strs(r.get("AllowedModuleRoles")))),
                              "create": bool(r.get("AllowCreate")), "delete": bool(r.get("AllowDelete")),
                              "default": default, "members": mem, "xpath": ws(r.get("XPathConstraint"))})
            entities[qn] = {"members": members, "rules": rules}

    pages = {d.qn: set(strs(d.data.get("AllowedModuleRoles"))) for d in m.of_type("Forms$Page")
             if not d.data.get("Excluded")}
    flows = {d.qn: set(strs(d.data.get("AllowedModuleRoles")))
             for d in m.of_type("Microflows$Microflow", "Microflows$Nanoflow") if not d.data.get("Excluded")}

    roles = {}
    for ur in sorted(mr_of):
        mrs = mr_of[ur]
        rights, xp = set(), {}
        for qn in sorted(entities):
            toks, xps = entity_rights(mrs, qn, entities[qn])
            rights |= toks
            if xps:
                xp[qn] = xps
        for qn, allowed in pages.items():
            if allowed & mrs:
                rights.add(f"page {qn}")
        for qn, allowed in flows.items():
            if allowed & mrs:
                rights.add(f"flow {qn}")
        if ur == guest:
            rights.add("guest access")
        roles[ur] = {"module_roles": sorted(mrs), "admin": ur == admin, "guest": ur == guest,
                     "rights": sorted(rights), "xpath": xp}

    defined = []
    for mod in readable:
        sd = m.docs.get(f"{mod}.$ModuleSecurity")
        if sd:
            defined += [f"{mod}.{r['Name']}" for r in dicts(sd.data.get("ModuleRoles")) if r.get("Name")]
    return {MATRIX_KEY: 1, "model": source,
            "counts": {"user_roles": len(roles), "entities": len(entities), "pages": len(pages), "flows": len(flows)},
            "user_roles": roles, "module_roles": sorted(set(defined)), "entities": sorted(entities),
            "pages": sorted(pages), "flows": sorted(flows), "modules": sorted(m.modules),
            "members": sorted(set().union(*(e["members"] for e in entities.values())) if entities else set()),
            "not_compared": not_compared, "platform_modules": sorted(platform)}


def as_matrix(path):
    """A matrix from a matrix JSON file (checked) or from a model (built)."""
    if path.lower().endswith(".json") and os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
        except (OSError, ValueError) as e:
            raise Unreadable(f"{path}: not JSON ({e})")
        if not isinstance(d, dict) or d.get(MATRIX_KEY) != 1 or not isinstance(d.get("user_roles"), dict):
            raise Unreadable(f"{path}: JSON, but not an access matrix written by access_matrix.py matrix")
        return d
    return build(load_model(path), path)


def show(xs):
    text = " | ".join(x if x else "(no constraint)" for x in xs) or "(none)"
    return text if len(text) <= 200 else text[:197] + "..."


def gone(token, new):
    """A lost token whose object the NEW model does not hold at all (a removed or renamed module, entity, page or flow):
    the reviewer should read it as "removed", not as "access taken away from a kept object"."""
    kind, _, qn = token.partition(" ")
    if kind == "page":
        return qn not in new["pages"]
    if kind == "flow":
        return qn not in new["flows"]
    if kind in ("create", "delete"):
        return qn not in new["entities"]
    if kind in ("read", "write"):
        return qn not in new["members"]  # an attribute or an association the NEW model no longer has
    return False  # guest access and anything else: no object to be gone


def diff(old, new):
    lines, G, L, X = [], 0, 0, 0
    o_roles, n_roles = old["user_roles"], new["user_roles"]
    both = sorted(set(o_roles) & set(n_roles))
    for name in sorted(set(o_roles) ^ set(n_roles)):
        if name in o_roles:
            cnt = len(o_roles[name]["rights"])
            lines.append(f"REVIEW {name}: lost role (exists only in OLD, {cnt} rights)")
            L += cnt
        else:
            cnt = len(n_roles[name]["rights"])
            lines.append(f"REVIEW {name}: gained role (exists only in NEW, {cnt} rights)")
            G += cnt
    for name in both:
        o, n = o_roles[name], n_roles[name]
        for mr in sorted(set(n["module_roles"]) - set(o["module_roles"])):
            lines.append(f"REVIEW {name}: gained module role {mr}")
            G += 1
        for mr in sorted(set(o["module_roles"]) - set(n["module_roles"])):
            lines.append(f"REVIEW {name}: lost module role {mr}")
            L += 1
        for t in sorted(set(n["rights"]) - set(o["rights"])):
            lines.append(f"REVIEW {name}: gained {t}")
            G += 1
        for t in sorted(set(o["rights"]) - set(n["rights"])):
            lines.append(f"REVIEW {name}: lost {t}" + (" (object not in NEW)" if gone(t, new) else ""))
            L += 1
        for qn in sorted(set(o["xpath"]) | set(n["xpath"])):
            a, b = o["xpath"].get(qn, []), n["xpath"].get(qn, [])
            if a != b:
                lines.append(f"REVIEW {name}: xpath {qn}: {show(a)} -> {show(b)}")
                X += 1
    om, nm = set(old["module_roles"]), set(new["module_roles"])
    for mr in sorted(nm - om):
        lines.append(f"REVIEW {mr}: gained module role (exists only in NEW)")
        G += 1
    for mr in sorted(om - nm):
        lines.append(f"REVIEW {mr}: lost module role (exists only in OLD)")
        L += 1
    for mod in sorted(set(old.get("platform_modules", [])) | set(new.get("platform_modules", []))):
        lines.append(f"note: platform module {mod} (not in the model: its roles compare by name, its entity rules "
                     f"are not read)")
    not_compared = {}
    for side, mx in (("OLD", old), ("NEW", new)):
        for mod, why in sorted(mx["not_compared"].items()):
            not_compared.setdefault(mod, []).append(f"{side}: {why}")
    for mod in sorted(not_compared):
        lines.append(f"not compared: {mod} ({'; '.join(not_compared[mod])})")
    objects = set(old["entities"]) | set(new["entities"]) | set(old["pages"]) | set(new["pages"]) \
        | set(old["flows"]) | set(new["flows"])
    summary = (f"access diff: {len(objects)} objects × {len(both)} roles compared, "
               f"{G} gained, {L} lost, {X} xpath changed")
    return lines, summary, bool(not_compared), G, L, X


def main(argv=None):
    ap = argparse.ArgumentParser(description="Access matrix per user role, and its diff between two models (L1b).")
    sub = ap.add_subparsers(dest="cmd", required=True)
    mx = sub.add_parser("matrix", help="the access matrix of one model")
    mx.add_argument("model", help="project dir or .mpr")
    mx.add_argument("--out", help="write the matrix as JSON")
    df = sub.add_parser("diff", help="what changed in access between OLD and NEW")
    df.add_argument("old", help="OLD model (dir or .mpr) or matrix JSON")
    df.add_argument("new", help="NEW model (dir or .mpr) or matrix JSON")
    df.add_argument("--out", help="write the diff as JSON")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "matrix":
            mat = build(load_model(a.model), a.model)
            c = mat["counts"]
            print(f"access matrix: {c['user_roles']} user roles × {c['entities']} entities, {c['pages']} pages, "
                  f"{c['flows']} flows")
            for mod in mat["platform_modules"]:
                print(f"note: platform module {mod} (not in the model: its roles compare by name, its entity rules "
                      f"are not read)")
            for mod, why in sorted(mat["not_compared"].items()):
                print(f"not compared: {mod} ({why})")
            if a.out:
                write_json(a.out, mat)
            return 0
        old, new = as_matrix(a.old), as_matrix(a.new)
        try:
            lines, summary, partial, G, L, X = diff(old, new)
        except (KeyError, TypeError, AttributeError) as e:
            raise Unreadable(f"a matrix is malformed ({type(e).__name__}: {e})")
        for ln in lines:
            print(ln)
        print(summary)
        if a.out:
            write_json(a.out, {"summary": summary, "lines": lines, "gained": G, "lost": L, "xpath_changed": X})
        if any(ln.startswith("REVIEW ") for ln in lines):
            return 1
        if partial:
            print("access_matrix: the comparison is partial (a module was not compared): not reported as no difference")
            return 3
        return 0
    except Unreadable as e:
        print(f"access_matrix: cannot read: {e}", file=sys.stderr)
        return 3


def write_json(path, obj):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=1, sort_keys=True)
    except OSError as e:
        print(f"access_matrix: cannot write {path}: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    sys.exit(main())
