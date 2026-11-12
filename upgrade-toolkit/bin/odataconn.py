#!/usr/bin/env python3
"""OData / REST connector modules: the one place that knows their names (T3F-11).

An app can consume OData with no consumed-OData document at all: the Marketplace connector SAPODataConnector (Java
actions GetList/Create, entities generalizing SAPODataConnector.OdataObject) and ODataQueryBuilder carry it. T3 (PFEP)
recorded "0 OData consumed" from the built-in client count alone, and `release_impact.py --auto` with that fact would
have closed every consumed-OData row as not relevant. The count of REFERENCES into such a module is its own fact,
odata_consumed_connector; a non-zero value keeps the OData rows open, a value that could not be counted is no fact.

A module is a connector when its name (letters only, lowercase) holds "odata" or is a known REST connector. The name
test is generous on purpose: a false hit only keeps a row open, a miss closes a row wrongly. Presence alone counts for
nothing: the module must be REFERENCED from outside the connector modules (entity generalization, microflow or Java
action call, a constant or type of it), so an installed-but-unused connector stays 0.

Producers: test_inventory.py (catalog refs, key odata_consumed_connector) and release_impact.py --facts-from-mpr (model
strings). Consumer: release_impact.py auto_rule, feature "consumed OData" and "OData".
"""
import re

KNOWN = {"restservices", "restclient"}


def is_connector(name):
    n = re.sub(r"[^a-z]", "", (name or "").lower())
    return "odata" in n or n in KNOWN


def count_model_refs(model):
    """{connector module: references} from outside the connector modules, over every string of every unit of an
    mprmodel.Model. A string 'Module.Name' counts when Module is an installed connector module."""
    import mprmodel
    present = {n for n in model.modules if n and is_connector(n)}
    out = {}
    if not present:
        return out
    for uid, (_, _, d) in model.units.items():
        own, _ = model._module_of(uid)
        if own in present:
            continue
        for s in mprmodel.strings(d):
            head, dot, _ = s.partition(".")
            if dot and head in present and len(s) < 300:
                out[head] = out.get(head, 0) + 1
    return out


def catalog_refs(rows_refs, rows_ents, modules):
    """The reference rows of a catalog into installed connector modules: [{source, kind, target}], or a one-row list
    {"_error": ...} when it cannot be told (refs table missing or empty: not a full catalog rebuild). Generalizations
    come from entities_data too, so the entity case holds even when refs is lost."""
    present = {m for m in modules if is_connector(m)}
    hits, seen = [], set()

    def add(src, kind, tgt):
        head = (tgt or "").partition(".")[0]
        if head in present and (src or "").partition(".")[0] not in present and (src, kind, tgt) not in seen:
            seen.add((src, kind, tgt)); hits.append({"source": src, "kind": kind, "target": tgt})
    for e in rows_ents:
        if "_error" not in e:
            add(e.get("QualifiedName"), "generalize", e.get("Generalization"))
    refs_ok = bool(rows_refs) and not any("_error" in r for r in rows_refs)
    for r in rows_refs if refs_ok else []:
        add(r.get("SourceName"), r.get("RefKind"), r.get("TargetName"))
    if not hits and not refs_ok:
        why = rows_refs[0].get("_error") if rows_refs else "refs is empty: full catalog rebuild needed"
        return [{"_error": f"connector references unknown: {why}"}]
    return hits
