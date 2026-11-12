#!/usr/bin/env python3
"""domain_map.py: the data structure of a Mendix app, read offline from the .mpr (no Studio Pro, no mxbuild).

    python3 -I domain_map.py <app dir|.mpr> [--module M ...] [--all]

Per module (own modules by default; --all adds Marketplace modules): entities with generalization,
attributes (type, enumeration, default), validation rules (required / unique / range / regex), associations
(parent -> child, owner, type, delete behaviour), and the module roles with access rules per entity.
Then enumerations with their values. Marketplace modules are skipped unless named: their entities are seeded by
the app itself or by smoke_users.py, never by hand.

Why: seeding without this is guessing. The three questions a seed must answer come out of this table:
  1. which attributes MUST have a value (required rule, no default) and which must be unique,
  2. which association has to be filled for a child to appear on a page (parent -> child),
  3. which enumeration values exist (every value a page filters or colours on needs at least one row).
Built on mprmodel.py (../../bin). Read-only.
"""
import argparse, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "bin"))
import mprmodel  # noqa: E402


def items(x):
    """Mendix BSON arrays start with a storage-version integer."""
    return [i for i in (x or []) if isinstance(i, dict)]


def tname(t):
    ty = t.get("$Type", "").split("$")[-1].replace("AttributeType", "")
    if ty == "Enumeration":
        return "Enum(" + str(t.get("EnumerationName") or t.get("Enumeration") or "?") + ")"
    if ty == "String":
        return "String(%s)" % t.get("Length", "?")
    return ty


def rule_kind(r):
    info = r.get("RuleInfo") or {}
    return info.get("$Type", "").split("$")[-1].replace("RuleInfo", "").lower() or "rule"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--module", action="append")
    ap.add_argument("--all", action="store_true", help="include Marketplace modules")
    a = ap.parse_args()
    m = mprmodel.Model.load(a.project)
    mods = set(a.module or [])
    if not mods:
        mods = {n for n, v in m.modules.items() if a.all or not v.get("from_appstore")}
    mods -= {"System"}
    for d in sorted(m.docs.values(), key=lambda x: x.qn):
        if d.type != "DomainModels$DomainModel" or d.module not in mods:
            continue
        dm = d.data
        ents = {e["$ID"]: e for e in items(dm.get("Entities"))}
        print("\n## Module %s" % d.module)
        for e in items(dm.get("Entities")):
            gen = e.get("MaybeGeneralization") or {}
            parent = gen.get("Generalization") or ""
            tags = []
            if gen.get("Persistable") is False:
                tags.append("NON-PERSISTENT: never seed")
            for k, label in (("HasOwnerAttr", "System.owner"), ("HasChangedDateAttr", "changedDate"), ("HasCreatedDateAttr", "createdDate"), ("HasChangedByAttr", "changedBy")):
                if gen.get(k):
                    tags.append(label)
            print("\n### %s.%s%s%s" % (d.module, e["Name"], ("  extends " + str(parent)) if parent else "", ("  [" + ", ".join(tags) + "]") if tags else ""))
            rules = {}
            for r in items(e.get("ValidationRules")):
                rules.setdefault(str(r.get("Attribute", "")).split(".")[-1], []).append(rule_kind(r))
            for at in items(e.get("Attributes")):
                v = at.get("Value") or {}
                dflt = v.get("DefaultValue", "") if v.get("$Type", "").endswith("StoredValue") else "(calculated)"
                rs = ",".join(rules.get(at["Name"], []))
                print("- %s : %s%s%s" % (at["Name"], tname(at.get("NewType") or {}), (" default=" + str(dflt)) if dflt not in ("", None) else "", ("  RULE:" + rs) if rs else ""))
            for ar in items(e.get("AccessRules")):
                rl = ",".join(x.split(".")[-1] for x in (ar.get("AllowedModuleRoles") or []) if isinstance(x, str))
                print("  access[%s] create=%s delete=%s default=%s xpath=%s" % (rl, ar.get("AllowCreate"), ar.get("AllowDelete"), ar.get("DefaultMemberAccessRights"), (ar.get("XPathConstraint") or "")[:90]))
        for key in ("Associations", "CrossAssociations"):
            for s in items(dm.get(key)):
                p = ents.get(s.get("ParentPointer"))
                c = ents.get(s.get("ChildPointer"))
                pn = p["Name"] if p else str(s.get("Parent") or "?")
                cn = c["Name"] if c else str(s.get("Child") or "?")
                pn = pn if p else str(s.get("Parent") or s.get("ParentPointer") or "?")
                db = s.get("DeleteBehavior") or {}
                print("assoc %s: %s -> %s  type=%s owner=%s del(parent/child)=%s/%s" % (
                    s.get("Name"), pn, cn, s.get("Type") or "Reference", s.get("Owner"),
                    db.get("ParentDeleteBehavior"), db.get("ChildDeleteBehavior")))
    print("\n## Enumerations")
    for d in sorted(m.docs.values(), key=lambda x: x.qn):
        if d.type == "Enumerations$Enumeration" and d.module in mods:
            vals = []
            for v in items(d.data.get("Values")):
                cap = [t.get("Text") for t in items((v.get("Caption") or {}).get("Items"))]
                vals.append("%s(%s)" % (v.get("Name"), cap[0] if cap else ""))
            print("- %s.%s: %s" % (d.module, d.data.get("Name"), ", ".join(vals)))


if __name__ == "__main__":
    main()
