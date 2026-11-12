#!/usr/bin/env python3
"""generator_fn_control.py: FN-3, FN-4, FN-5, FN-6, FN-7 and FN-11, the journey generator fixes of the field finish pass,
on fake models (no mpr). Prints one line per case: "ok   <name>: <detail>" or "FAIL <name>: <detail>"; exit 1 on any FAIL.
Catch cases show the defect the fix removed (the OLD behaviour would print FAIL for the pass cases beside them)."""
import os
import sys
import types

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin"))
import action_inventory as A  # noqa: E402
import gen_journeys as G  # noqa: E402
import impact_map as I  # noqa: E402

fails = 0


def check(name, ok, detail):
    global fails
    fails += 0 if ok else 1
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {detail}")


# FN-7: a text box inside a Gallery is kept as a field marked in_list; outside a list it is unmarked
def tb(name, attr="Shop.Item.Name"):
    return {"$Type": "Forms$TextBox", "Name": name, "AttributeRef": {"Attribute": attr}}


gallery = {"$Type": "CustomWidgets$CustomWidget", "Name": "gallery1", "Type": {"WidgetId": "com.mendix.widget.web.gallery.Gallery"},
           "Object": {"Properties": [{"Value": {"Widgets": [tb("inList")]}}]}}
dv = {"$Type": "Forms$DataView", "Widgets": [tb("plain"), gallery]}
inv = types.SimpleNamespace(attr_type=lambda a: {"type": "String"})
fields = {f["widget"]: f for f in A.Inventory.fields(inv, dv)}
check("fields keep a list input, marked", fields.get("inList", {}).get("in_list") == "gallery1", str(fields.get("inList", {}).get("in_list")))
check("fields leave a plain input unmarked", "plain" in fields and "in_list" not in fields["plain"], str(sorted(fields["plain"])))

# FN-7: fill_field makes the fill of an in_list field optional with no own-row check
f = {"widget": "inList", "input": "text", "attribute": "Shop.Item.Name", "attr_type": {"type": "String"}, "in_list": "gallery1"}
acts, own, why = G.fill_field(f, 1, "pw")
check("in_list fill is optional", acts and all(a.get("optional") for a in acts), str(acts))
check("in_list fill has no own-row check", own is None, str(own))
acts, own, why = G.fill_field(dict(f, in_list=None), 1, "pw")
check("plain fill is not optional", acts and not any(a.get("optional") for a in acts), str(acts))
check("plain fill keeps its own-row check", own == "Shop.Item.Name", str(own))

# FN-11: an attribute named *URL or *URI gets an https value (run-unique); a short column keeps the short value
for attr in ("Shop.Item.ImageURL", "Shop.Item.callback_uri"):
    acts, own, why = G.fill_field(dict(f, attribute=attr, in_list=None), 3, "pw")
    check(f"{attr.split('.')[-1]} is filled as a URL", acts[0]["value"] == "https://example.com/U-${RUN_ID}-3", acts[0]["value"])
acts, own, why = G.fill_field(dict(f, attribute="Shop.Item.Surname", in_list=None), 3, "pw")
check("Surname is not taken for a URL", acts[0]["value"] == "U-${RUN_ID}-3", acts[0]["value"])
acts, own, why = G.fill_field(dict(f, attribute="Shop.Item.ImageURL", attr_type={"type": "String", "length": 20}, in_list=None), 3, "pw")
check("URL value too long for the column falls back to the short value", acts[0]["value"] == "U3" and own is None, f"{acts[0]['value']} {own}")


# FN-3: a microflow entry that shows several pages lands on the ones without parameters
class Doc:
    def __init__(self, type_, params=()):
        self.type, self.data = type_, {"Parameters": list(params)}


def bfs(shows, pages, click=None):
    docs = {"Shop.Flow": Doc("Microflows$Microflow")}
    docs.update({p: Doc("Forms$Page", [{"Name": "obj"}] if need else []) for p, need in pages.items()})
    pt = {"action": "page", "conditional": []}
    inv = types.SimpleNamespace(
        m=types.SimpleNamespace(docs=docs), roles=None, points={click[0]: [pt]} if click else {},
        entries=lambda role: [("home", "Shop.Flow", {"via": "home"})], readable=lambda qn: None,
        flow=lambda qn: {"shows": set(shows)}, targets=lambda p: [click[1]], supplies=lambda p, t: True, may=lambda r, p, t: True)
    return A.Inventory.bfs(inv, {p: [p] for p in pages}, False)


two = {"Shop.Detail": True, "Shop.Overview": False}
par = bfs(two, two)
check("branch entry lands on the parameter-free page", par.get("Shop.Overview", (0, {}, 9))[2] == 0 and "branch" not in par["Shop.Overview"][1], str(par.get("Shop.Overview")))
check("branch page no click reaches keeps the entry, marked", par.get("Shop.Detail", (0, {}))[1].get("branch") == "data-dependent", str(par.get("Shop.Detail")))
par = bfs(two, two, click=("Shop.Overview", "Shop.Detail"))
check("branch page a click reaches is reached by the click", par["Shop.Detail"][0] == "Shop.Overview" and "branch" not in par["Shop.Detail"][1], str(par["Shop.Detail"]))
both = {"Shop.A": True, "Shop.B": True}
par = bfs(both, both)
check("every branch page needs an object: all kept as before", sorted(par) == ["Shop.A", "Shop.B"] and not any("branch" in v[1] for v in par.values()), str(sorted(par)))
one = {"Shop.Detail": True}
par = bfs(one, one)
check("an entry that shows one page is untouched", list(par) == ["Shop.Detail"] and "branch" not in par["Shop.Detail"][1], str(par))


# FN-4, FN-5: widgets that draw nothing or hide their content
def cw(widget_id, name="w1"):
    return {"$Type": "CustomWidgets$CustomWidget", "Name": name, "Type": {"WidgetId": widget_id}}


check("Pop-up menu is a popup menu", I.is_popup_menu(cw("com.mendix.widget.web.popupmenu.PopupMenu")), "true")
check("Dropdown container is a popup menu", I.is_popup_menu(cw("mendix.dropdowncontainer.DropdownContainer")), "true")
check("Gallery is no popup menu", not I.is_popup_menu(cw("com.mendix.widget.web.gallery.Gallery")), "false")


def snippet(content_type):
    w = cw("HTMLSnippet.widget.HTMLSnippet", "snip1")
    w["Type"]["ObjectType"] = {"PropertyTypes": [{"$ID": "p1", "PropertyKey": "contenttype"}]}
    w["Object"] = {"Properties": [{"TypePointer": "p1", "Value": {"PrimitiveValue": content_type}}]}
    return w


check("JavaScript HTML snippet draws nothing", I.draws_nothing(snippet("js")) and I.draws_nothing(snippet("jsjquery")), "true")
check("HTML content snippet draws something", not I.draws_nothing(snippet("html")), "false")
check("another widget draws something", not I.draws_nothing(cw("com.mendix.widget.web.gallery.Gallery")), "false")


# FN-6: the landing guard of a save is the menu widget when the opener sits in a closed menu, else the opener
class Gen(G.ActionGen):
    def __init__(self, notes):
        self.notes = notes

    def tab_acts(self, h, page):
        return [], self.notes


hops = [{"page": "Shop.List"}, {"page": "Shop.List", "click": "editButton1"}, {"page": "Shop.Edit"}]
x = {"action": "save"}
sel, _ = Gen([{"menu": "kebab1", "widget": "editButton1"}]).ready_after(x, hops)
check("save lands on the menu that holds the opener", sel == ".mx-name-kebab1", sel)
sel, _ = Gen([]).ready_after(x, hops)
check("save lands on the opener when no menu holds it", sel == ".mx-name-editButton1", sel)
sys.exit(1 if fails else 0)
