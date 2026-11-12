#!/usr/bin/env python3
"""mkmodel.py: build a tiny synthetic Mendix project (MPR v1) from a JSON spec, for the controls.

Synthetic on purpose: controls are committed, so fixtures hold Marketplace and System names only, never an app's own
modules, values or secrets. The units have the fields the toolkit reads (same $Type names and shapes as a real MPR,
captured from the E1/E5 projects), nothing more. A real-evidence control reads ~/upgrade-lab instead.

  mkmodel.py spec.json <out dir>          writes <out dir>/App.mpr (+ widgets/*.mpk, javasource/... when specified)

Spec (all keys optional except modules):
  {"version": "10.24.16.96987", "languages": ["en_US"],
   "modules": [{"name": "Administration", "appstore": [23513, "4.1.0"],
                "entities": [{"name": "Account", "persistent": true, "generalization": "System.User", "guid": "...",
                              "validation": [["Email", "Required"]],
                              "attributes": [{"name": "FullName", "type": "String", "calculated": false, "guid": "..."},
                                             {"name": "Kind", "type": "Enumeration", "enum": "M.ENUM_Kind"}]}],
                "associations": [{"name": "A_B", "parent": "A", "child": "B", "guid": "..."}],
                "cross": [{"name": "A_User", "parent": "A", "child": "System.User", "guid": "..."}],
                "module_roles": ["User", "Administrator"],
                "constants": [{"name": "Enabled", "type": "Boolean", "default": "true"}],
                "pages": [{"name": "Home", "excluded": false, "layout": "Atlas_Core.Atlas_Default", "widgets": ["com.mendix.widget.web.markdown.Markdown"],
                           "refs": {"Microflow": "UserCommons.ACT_Save"},
                           "named": [["DataGrid", "grid1"], {"type": "Label", "name": "label1", "text": "Hello", "conditional": false}]}],
                "docs": [{"type": "ScheduledEvents$ScheduledEvent", "name": "SE_Clean", "data": {"Enabled": true}}],
                "layouts": [{"name": "Layout_App", "type": "Responsive", "named": [["NavigationTree", "navigationTree1"]]}]}],
   (entities also take "access": [...] = DomainModels$AccessRule list, see access_rule(); microflows and nanoflows
    with allowed roles go through "docs" with data {"AllowedModuleRoles": [3, "M.Role"]};
    named widgets also take "children": [...], "source": {"profile": "Responsive"} | {"menu": "M.Menu"},
    "action": "signout"; pages take "allowed": ["M.ModuleRole"], "title": TEXT; modules take
    "menus": [{"name": "Menu", "items": [{"caption": "Sign out", "signout": true, "items": [...]}]}])
   "security": {"user_roles": {"Clerk": ["M.Clerk"]}, "admin": "Admin", "guest": "Guest"},
   "navigation": {"homes": [{"role": "*", "page": "M.Home"}, {"role": "Clerk", "page": "M.Other"},
                            {"role": "Planner", "microflow": "M.NAV_Home"}],
                  "menu": [{"caption": "Home", "page": "M.Home"}, {"caption": "Sign out", "signout": true}], "login_page": "",
                  "profiles": [{"name": "Phone_web", "kind": "Phone"}, {"type": "Navigation$NativeNavigationProfile"}]},
   "configurations": [{"name": "Default", "constants": {"Module.Constant": "value"}}],
   "widget_packages": {"Markdown.mpk": ["com.mendix.widget.web.markdown.Markdown"],
                       "Broken.mpk": {"ids": ["x.Y"], "defect": "crc" | "descriptor"},
                       "Old.mpk": {"ids": ["Old.widget.Old"], "dojo": true, "version": "1.2.0"}},
   "files": {"javasource/x/actions/A.java": "...", "userlib/a-1.0.jar": ""}}
GUIDs default to uuid5(name), so two specs that share an element share its GUID unless one overrides "guid".

A variant names its base and the differences, so a control shows exactly what it changes:
  (attributes also take "default": TEXT, written as Value/DefaultValue only when given: the F10 shape)
  {"from": "base.json", "ops": [["set", "modules/1/entities/0/attributes/1/guid", "1111..."],
                                ["append", "modules/0/pages/0/widgets", "x.Y"], ["delete", "configurations/0/constants/M.C"]]}
Paths are "/"-separated dict keys or list indexes; "from" is relative to the variant file.
"""
import json, os, sqlite3, sys, uuid, zipfile

import bson

NS = uuid.UUID("6f1c6c1e-0000-4000-8000-00000000c0de")


def gid(name, override=None):
    return (uuid.UUID(override) if override else uuid.uuid5(NS, name)).bytes_le


def lst(xs):
    return [3] + list(xs)  # Mendix BSON lists carry a leading type marker


def mtext(key, value):
    return {"$ID": gid("tx:" + key), "$Type": "Texts$Text",
            "Items": lst([{"$ID": gid("tr:" + key), "$Type": "Texts$Translation", "LanguageCode": "en_US", "Text": value}])}


def named(owner, ws):
    """Named Forms widgets: ["DataGrid", "grid1"] or {"type", "name", "text", "conditional", "children", "source",
    "action"}. children: nested named widgets (list view content, ...); source: {"profile": NAME} or {"menu": QN} for a
    navigation widget (MenuSource as a 10.x model writes it); action: "signout" for a sign-out button.
    hide_on: ["Desktop", ...] writes the Atlas "Hide on" design property (shape of a real 11.12 Atlas_TopBar);
    placeholder: TEXT a PlaceholderTemplate (text box); a TabControl takes "tabs": [{"name", "text", "children"}] and
    "default": index of the tab page DefaultPagePointer names (G-3)."""
    out = []
    for i, w in enumerate(ws):
        w = {"type": w[0], "name": w[1]} if isinstance(w, list) else w
        x = {"$ID": gid(f"nw:{owner}.{i}"), "$Type": "Forms$" + w["type"], "Name": w["name"]}
        if w.get("text"):
            x["Caption"] = mtext(f"{owner}.{i}", w["text"])
        if w.get("conditional"):
            x["ConditionalVisibilitySettings"] = {"$ID": gid(f"cv:{owner}.{i}"), "$Type": "Forms$ConditionalVisibilitySettings"}
        if w.get("children"):
            x["Widgets"] = lst(named(f"{owner}.{i}", w["children"]))
        if w.get("hide_on"):
            x["Appearance"] = {"$ID": gid(f"ap:{owner}.{i}"), "$Type": "Forms$Appearance", "Class": "", "Style": "",
                               "DesignProperties": lst([{"$ID": gid(f"dp:{owner}.{i}"), "$Type": "Forms$DesignPropertyValue",
                                                         "Key": "Hide on", "Value": {"$ID": gid(f"dv:{owner}.{i}"),
                                                         "$Type": "Forms$CompoundDesignPropertyValue",
                                                         "Properties": [2] + [{"$ID": gid(f"dq:{owner}.{i}.{k}"),
                                                                               "$Type": "Forms$DesignPropertyValue", "Key": k,
                                                                               "Value": {"$ID": gid(f"dt:{owner}.{i}.{k}"),
                                                                                         "$Type": "Forms$ToggleDesignPropertyValue"}}
                                                                              for k in w["hide_on"]]}}])}
        if w.get("placeholder"):
            x["PlaceholderTemplate"] = {"$ID": gid(f"ph:{owner}.{i}"), "$Type": "Forms$ClientTemplate",
                                        "Template": mtext(f"ph:{owner}.{i}", w["placeholder"])}
        if w.get("tabs"):
            tps = [{"$ID": gid(f"tp:{owner}.{i}.{j}"), "$Type": "Forms$TabPage", "Name": t["name"],
                    "Caption": mtext(f"tp:{owner}.{i}.{j}", t.get("text", t["name"])), "ConditionalVisibilitySettings": None,
                    "Widgets": lst(named(f"{owner}.{i}.{j}", t.get("children", [])))} for j, t in enumerate(w["tabs"])]
            x["TabPages"] = lst(tps)
            x["DefaultPagePointer"] = tps[w.get("default", 0)]["$ID"]
            x["ActivePageAttributeRef"] = None
        src = w.get("source") or {}
        if src.get("profile"):
            x["MenuSource"] = {"$ID": gid(f"ms:{owner}.{i}"), "$Type": "Forms$NavigationSource", "NavigationProfile": src["profile"]}
        elif src.get("menu"):
            x["MenuSource"] = {"$ID": gid(f"ms:{owner}.{i}"), "$Type": "Forms$MenuDocumentSource", "Menu": src["menu"]}
        if w.get("action") == "signout":
            x["Action"] = {"$ID": gid(f"ac:{owner}.{i}"), "$Type": "Forms$SignOutClientAction"}
        elif isinstance(w.get("action"), dict):  # a flow call: {"microflow": QN, "mappings": [[param, {"page"|"widget": NAME} | {"expr": E}]]}
            x["Action"] = {"$ID": gid(f"ac:{owner}.{i}"), "$Type": "Forms$MicroflowClientAction",
                           "MicroflowSettings": flow_call(f"{owner}.{i}.a", w["action"], "Microflow")}
        if w.get("datasource"):  # {"kind": microflow|nanoflow|association|page, "microflow"/"param", "mappings"}
            x["DataSource"] = datasource(f"{owner}.{i}", w["datasource"])
        out.append(x)
    return out


def flow_call(key, c, field):
    """Forms$MicroflowSettings as a 9.x or 10.x page stores it: a flow name and its ParameterMappings (empty = implicit)."""
    pms = []
    for j, (param, v) in enumerate(c.get("mappings", [])):
        pm = {"$ID": gid(f"pm:{key}.{j}"), "$Type": "Forms$PageParameterMapping", "Parameter": param}
        if "page" in v or "widget" in v:
            pm["Variable"] = {"$ID": gid(f"pv:{key}.{j}"), "$Type": "Forms$PageVariable",
                              "PageParameter": v.get("page", ""), "Widget": v.get("widget", "")}
        elif "arg" in v:  # the 10.x shape seen in real units: an Argument expression and an empty PageVariable
            pm["Argument"] = v["arg"]
            pm["Variable"] = {"$ID": gid(f"pv:{key}.{j}"), "$Type": "Forms$PageVariable", "LocalVariable": "",
                              "PageParameter": "", "SnippetParameter": "", "SubKey": "", "UseAllPages": False, "Widget": ""}
        else:
            pm["Expression"] = v.get("expr", "")
        pms.append(pm)
    return {"$ID": gid(f"fs:{key}"), "$Type": "Forms$MicroflowSettings", field: c.get(field.lower(), ""),
            "ParameterMappings": lst(pms)}


def datasource(key, d):
    k = d.get("kind", "page")
    if k == "microflow":
        return {"$ID": gid(f"ds:{key}"), "$Type": "Forms$MicroflowSource", "MicroflowSettings": flow_call(f"{key}.ds", d, "Microflow")}
    if k == "nanoflow":
        return {"$ID": gid(f"ds:{key}"), "$Type": "Forms$NanoflowSource", "NanoflowSettings": flow_call(f"{key}.ds", d, "Nanoflow")}
    if k == "association":
        return {"$ID": gid(f"ds:{key}"), "$Type": "Forms$AssociationSource", "EntityRef": {"$ID": gid(f"er:{key}"), "$Type": "DomainModels$IndirectEntityRef"}}
    if k == "path":  # 9.x association path (T6R-3: 18 of 93 Forms$DataViewSource data views of a real 9.24 model)
        return {"$ID": gid(f"ds:{key}"), "$Type": "Forms$DataViewSource", "PageParameter": d.get("param", ""), "SnippetParameter": "",
                "EntityRef": {"$ID": gid(f"er:{key}"), "$Type": "DomainModels$IndirectEntityRef"}}
    return {"$ID": gid(f"ds:{key}"), "$Type": "Forms$DataViewSource",
            "SourceVariable": {"$ID": gid(f"sv:{key}"), "$Type": "Forms$PageVariable", "PageParameter": d.get("param", ""), "Widget": d.get("widget", "")}}


def menu_items(key, items):
    """Menu document items: [{"caption", "signout"?, "page"?, "microflow"?, "items"?}]. microflow: QN, a menu item
    that calls a flow (B4T2-4: a logout flow instead of the platform SignOut action)."""
    out = []
    for i, it in enumerate(items):
        k = f"{key}.{i}"
        act = ({"$ID": gid(f"ma:{k}"), "$Type": "Forms$SignOutClientAction"} if it.get("signout") else
               {"$ID": gid(f"ma:{k}"), "$Type": "Forms$MicroflowAction",
                "MicroflowSettings": flow_call(f"ma:{k}", {"microflow": it["microflow"]}, "Microflow")} if it.get("microflow") else
               {"$ID": gid(f"ma:{k}"), "$Type": "Forms$FormAction",
                "FormSettings": {"$ID": gid(f"mf:{k}"), "$Type": "Forms$FormSettings", "Form": it.get("page", "")}})
        out.append({"$ID": gid(f"mi:{k}"), "$Type": "Menus$MenuItem", "Caption": mtext(f"mc:{k}", it["caption"]),
                    "Action": act, "Items": lst(menu_items(k, it.get("items", [])))})
    return out


def access_rule(qn, i, a):
    """DomainModels$AccessRule as a 9.x-11.x model writes it (access_matrix.py's field names, captured from the
    field project MendixSSO entities): roles, create / delete, the default member right, the per-member rights and the
    XPath constraint. Entity spec key "access": [{"roles": [M.Role], "create", "delete", "default": None|ReadOnly|
    ReadWrite, "members": [[qn, rights]] (3 parts = attribute, 2 parts = association), "xpath": TEXT}]."""
    members = []
    for j, (mq, rights) in enumerate(a.get("members", [])):
        attr = mq.count(".") == 2
        members.append({"$ID": gid(f"ma:{qn}.{i}.{j}"), "$Type": "DomainModels$MemberAccess", "AccessRights": rights,
                        "Association": "" if attr else mq, "Attribute": mq if attr else ""})
    return {"$ID": gid(f"ar:{qn}.{i}"), "$Type": "DomainModels$AccessRule", "AllowedModuleRoles": lst(a.get("roles", [])),
            "AllowCreate": bool(a.get("create")), "AllowDelete": bool(a.get("delete")),
            "DefaultMemberAccessRights": a.get("default", "None"), "MemberAccesses": lst(members),
            "XPathConstraint": a.get("xpath", "")}


def build(spec, out):
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "App.mpr")
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.execute("create table Unit (UnitID blob primary key, ContainerID blob, ContainmentName text, TreeConflict int,"
                " ContentsHash text, ContentsConflicts text, Contents blob)")
    con.execute("create table _MetaData (_ProductVersion text, _BuildVersion text, _SchemaHash text)")
    con.execute("insert into _MetaData values (?, ?, '')", (spec.get("version", "10.24.16.96987"),) * 2)
    units = []
    root = gid("project")
    units.append((root, None, {"$ID": root, "$Type": "Projects$Project"}))
    for m in spec["modules"]:
        mn = m["name"]
        mid = gid("module:" + mn)
        mod = {"$ID": mid, "$Type": "Projects$ModuleImpl", "Name": mn, "FromAppStore": bool(m.get("appstore"))}
        if m.get("appstore"):
            mod["AppStorePackageId"], mod["AppStoreVersion"] = m["appstore"][0], m["appstore"][1]
        units.append((mid, root, mod))
        if m.get("module_roles"):   # PLM-26: "module_roles": ["User", "Administrator"] = Security$ModuleSecurity of the module
            msid = gid(f"modsec:{mn}")
            units.append((msid, mid, {"$ID": msid, "$Type": "Security$ModuleSecurity",
                                      "ModuleRoles": lst([{"$ID": gid(f"mr:{mn}.{r}"), "$Type": "Security$ModuleRole", "Name": r}
                                                          for r in m["module_roles"]])}))
        ents, eid = [], {}
        for e in m.get("entities", []):
            qn = f"{mn}.{e['name']}"
            eid[e["name"]] = gid("id:" + qn)
            gen = ({"$ID": gid("gen:" + qn), "$Type": "DomainModels$Generalization", "Generalization": e["generalization"]}
                   if e.get("generalization") else
                   {"$ID": gid("gen:" + qn), "$Type": "DomainModels$NoGeneralization", "Persistable": e.get("persistent", True)})
            attrs = [{"$ID": gid("id:" + qn + "." + a["name"]), "$Type": "DomainModels$Attribute", "Name": a["name"],
                      "GUID": gid(qn + "." + a["name"], a.get("guid")),
                      "Type": {"$ID": gid("t:" + qn + a["name"]), "$Type": f"DomainModels${a.get('type', 'String')}AttributeType",
                               **({"Enumeration": a["enum"]} if a.get("enum") else {})},
                      "Value": {"$ID": gid("v:" + qn + a["name"]),
                                "$Type": "DomainModels$CalculatedValue" if a.get("calculated") else "DomainModels$StoredValue",
                                **({"DefaultValue": a["default"]} if "default" in a else {})}}
                     for a in e.get("attributes", [])]
            ents.append({"$ID": eid[e["name"]], "$Type": "DomainModels$EntityImpl", "Name": e["name"], "GUID": gid(qn, e.get("guid")),
                         "MaybeGeneralization": gen, "Attributes": lst(attrs),
                         "AccessRules": lst([access_rule(qn, i, a) for i, a in enumerate(e.get("access", []))]),
                         "ValidationRules": lst([{"$ID": gid(f"vr:{qn}.{a}.{r}"), "$Type": "DomainModels$ValidationRule",
                                                  "Attribute": f"{qn}.{a}", "RuleInfo": {"$ID": gid(f"ri:{qn}.{a}.{r}"),
                                                  "$Type": f"DomainModels${r}RuleInfo"}} for a, r in e.get("validation", [])])})
        assocs = [{"$ID": gid("id:" + mn + "." + a["name"]), "$Type": "DomainModels$Association", "Name": a["name"],
                   "GUID": gid(f"{mn}.{a['name']}", a.get("guid")), "ParentPointer": eid[a["parent"]],
                   "ChildPointer": eid[a["child"]], "Type": a.get("type", "Reference")} for a in m.get("associations", [])]
        cross = [{"$ID": gid("id:" + mn + "." + a["name"]), "$Type": "DomainModels$CrossAssociation", "Name": a["name"],
                  "GUID": gid(f"{mn}.{a['name']}", a.get("guid")), "ParentPointer": eid[a["parent"]], "Child": a["child"],
                  "Type": a.get("type", "Reference")} for a in m.get("cross", [])]
        dm = gid("dm:" + mn)
        units.append((dm, mid, {"$ID": dm, "$Type": "DomainModels$DomainModel", "Entities": lst(ents),
                                "Associations": lst(assocs), "CrossAssociations": lst(cross), "Annotations": lst([])}))
        for c in m.get("constants", []):
            cid = gid(f"const:{mn}.{c['name']}")
            units.append((cid, mid, {"$ID": cid, "$Type": "Constants$Constant", "Name": c["name"], "DefaultValue": c.get("default", ""),
                                     "Type": {"$ID": gid("ct:" + mn + c["name"]), "$Type": f"DataTypes${c.get('type', 'String')}Type"},
                                     "Excluded": False}))
        for p in m.get("pages", []):
            pid = gid(f"page:{mn}.{p['name']}")
            widgets = [{"$ID": gid(f"w:{mn}.{p['name']}.{i}"), "$Type": "CustomWidgets$CustomWidget", "Name": f"w{i}",
                        "Type": {"$ID": gid(f"wt:{mn}.{p['name']}.{i}"), "$Type": "CustomWidgets$CustomWidgetType", "WidgetId": w}}
                       for i, w in enumerate(p.get("widgets", []))]
            refs = [{"$ID": gid(f"r:{mn}.{p['name']}.{k}" + (f".{i}" if i else "")), "$Type": "Forms$ActionButton", k: v}
                    for k, vs in p.get("refs", {}).items() for i, v in enumerate(vs if isinstance(vs, list) else [vs])]
            page = {"$ID": pid, "$Type": "Forms$Page", "Name": p["name"], "Excluded": p.get("excluded", False),
                    "Widgets": lst(widgets + refs + named(f"{mn}.{p['name']}", p.get("named", [])))}
            if p.get("layout"):
                page["FormCall"] = {"$ID": gid(f"fc:{mn}.{p['name']}"), "$Type": "Forms$LayoutCall", "Form": p["layout"]}
            if p.get("allowed"):
                page["AllowedModuleRoles"] = lst(p["allowed"])
            if p.get("title"):
                page["Title"] = mtext(f"pt:{mn}.{p['name']}", p["title"])
            units.append((pid, mid, page))
        for mdoc in m.get("menus", []):  # menu documents: {"name", "items": [{"caption", "signout"?, "page"?, "items"?}]}
            uid = gid(f"menu:{mn}.{mdoc['name']}")
            units.append((uid, mid, {"$ID": uid, "$Type": "Menus$MenuDocument", "Name": mdoc["name"], "Excluded": False,
                                     "ItemCollection": {"$ID": gid(f"mic:{mn}.{mdoc['name']}"), "$Type": "Menus$MenuItemCollection",
                                                        "Items": lst(menu_items(f"{mn}.{mdoc['name']}", mdoc.get("items", [])))}}))
        for i, x in enumerate(m.get("docs", [])):  # any other document: {"type", "name", "excluded", "data", "refs"}
            did = gid(f"doc:{mn}.{x['name']}.{x['type']}")
            d = {"$ID": did, "$Type": x["type"], "Name": x["name"], "Excluded": x.get("excluded", False), **x.get("data", {})}
            if x.get("refs"):
                d["Refs"] = lst([{"$ID": gid(f"dr:{mn}.{x['name']}.{k}" + (f".{i}" if i else "")), "$Type": "Forms$ActionButton", k: v}
                                 for k, vs in x["refs"].items() for i, v in enumerate(vs if isinstance(vs, list) else [vs])])
            units.append((did, mid, d))
        for l in m.get("layouts", []):
            lid = gid(f"layout:{mn}.{l['name']}")
            lay = {"$ID": lid, "$Type": "Forms$Layout", "Name": l["name"], "Excluded": False,
                   "Widgets": lst(named(f"{mn}.{l['name']}", l.get("named", [])))}
            if l.get("type"):  # "ModalPopup" | "Popup" | "Responsive": where an 11.12 model keeps it (Atlas_Core.PopupLayout)
                lay["Content"] = {"$ID": gid(f"lc:{mn}.{l['name']}"), "$Type": "Forms$WebLayoutContent", "LayoutType": l["type"]}
            units.append((lid, mid, lay))
    if spec.get("configurations") or spec.get("languages") or "model_settings" in spec:
        sid = gid("settings")
        cfgs = [{"$ID": gid("cfg:" + c["name"]), "$Type": "Settings$ServerConfiguration", "Name": c["name"],
                 "ConstantValues": lst([{"$ID": gid(f"cv:{c['name']}.{k}"), "$Type": "Settings$ConstantValue", "Constant": k,
                                         "SharedOrPrivateValue": {"$ID": gid(f"sv:{c['name']}.{k}"), "$Type": "Settings$SharedValue", "Value": v}}
                                        for k, v in c.get("constants", {}).items()])} for c in spec.get("configurations", [])]
        parts = [{"$ID": gid("cs"), "$Type": "Settings$ConfigurationSettings", "Configurations": lst(cfgs)}]
        if spec.get("languages"):  # "languages": ["en_US", ...], the shape of a real Settings$LanguageSettings (B1-RI / N1-9)
            parts.append({"$ID": gid("ls"), "$Type": "Settings$LanguageSettings", "DefaultLanguageCode": spec["languages"][0],
                          "Languages": lst([{"$ID": gid("lang:" + c), "$Type": "Texts$Language", "Code": c} for c in spec["languages"]])})
        if "model_settings" in spec:  # NS-9: {"UseOQLVersion2": false, "SslCertificateAlgorithm": "SunX509"}, a real Settings$ModelSettings part
            parts.append({"$ID": gid("ms"), "$Type": "Settings$ModelSettings", **spec["model_settings"]})
        units.append((sid, root, {"$ID": sid, "$Type": "Settings$ProjectSettings", "Settings": lst(parts)}))
    nav = spec.get("navigation")
    if nav:
        def item(i, it):
            act = ({"$ID": gid(f"na:{i}"), "$Type": "Navigation$SignOutClientAction"} if it.get("signout") else
                   {"$ID": gid(f"na:{i}"), "$Type": "Forms$FormAction",
                    "FormSettings": {"$ID": gid(f"nf:{i}"), "$Type": "Forms$FormSettings", "Form": it["page"]}})
            return {"$ID": gid(f"ni:{i}"), "$Type": "Menus$MenuItem", "Caption": mtext(f"nc:{i}", it["caption"]),
                    "Action": act, "Items": lst([])}
        homes = nav.get("homes", [])
        default = next((h for h in homes if h.get("role", "*") == "*"), {})
        prof = {"$ID": gid("navprof"), "$Type": "Navigation$NavigationProfile", "Name": "Responsive", "Kind": "Responsive",
                "HomePage": {"$ID": gid("navhome"), "$Type": "Navigation$HomePage", "Page": default.get("page", ""),
                             "Microflow": default.get("microflow", "")},
                "HomeItems": lst([{"$ID": gid(f"nh:{h['role']}"), "$Type": "Navigation$RoleBasedHomePage",
                                   "UserRole": h["role"], "Page": h.get("page", ""), "Microflow": h.get("microflow", "")}
                                  for h in homes if h.get("role", "*") != "*"]),
                "Menu": {"$ID": gid("navmenu"), "$Type": "Menus$MenuItemCollection",
                         "Items": lst([item(i, it) for i, it in enumerate(nav.get("menu", []))])},
                "LoginPageSettings": {"$ID": gid("navlogin"), "$Type": "Forms$FormSettings", "Form": nav.get("login_page", "")}}
        nid = gid("navdoc")
        # more profiles: "profiles": [{"name": "Phone_web", "kind": "Phone"}, {"type": "Navigation$NativeNavigationProfile", "name": "Native_phone"}]
        more = [{"$ID": gid(f"navprof:{i}"), "$Type": x.get("type", "Navigation$NavigationProfile"), "Name": x.get("name", f"P{i}"),
                 **({"Kind": x["kind"]} if "kind" in x else {})} for i, x in enumerate(nav.get("profiles", []))]
        units.append((nid, root, {"$ID": nid, "$Type": "Navigation$NavigationDocument", "Profiles": lst([prof] + more)}))
    sec = spec.get("security")
    if sec:  # {"user_roles": {"Role": ["Module.ModuleRole", ...]}, "admin": ROLE, "guest": ROLE}
        sid = gid("security")
        units.append((sid, root, {"$ID": sid, "$Type": "Security$ProjectSecurity", "AdminUserRole": sec.get("admin", ""),
                                  "GuestUserRole": sec.get("guest", ""), "EnableGuestAccess": bool(sec.get("guest")),
                                  **({"StrictPageUrlCheck": sec["strict_page_url"]} if "strict_page_url" in sec else {}),  # NS-9
                                  "UserRoles": lst([{"$ID": gid(f"ur:{n}"), "$Type": "Security$UserRole", "Name": n,
                                                     "ModuleRoles": lst(mrs)} for n, mrs in sec.get("user_roles", {}).items()])}))
    for uid, cid, d in units:
        con.execute("insert into Unit (UnitID, ContainerID, Contents) values (?, ?, ?)", (uid, cid, bson.encode(d)))
    con.commit(); con.close()
    for name, ids in (spec.get("widget_packages") or {}).items():
        defect, dojo, ver, js = None, False, None, None
        if isinstance(ids, dict):  # {"ids": [...], "defect": "crc" | "descriptor", "dojo": true, "version": "1.0", "js": "source"}
            ids, defect, dojo, ver, js = ids["ids"], ids.get("defect"), ids.get("dojo"), ids.get("version"), ids.get("js")
        os.makedirs(os.path.join(out, "widgets"), exist_ok=True)
        wp = os.path.join(out, "widgets", name)
        with zipfile.ZipFile(wp, "w") as z:
            if ver:
                z.writestr("package.xml", f'<?xml version="1.0"?>\n<package><clientModule name="p" version="{ver}"/></package>\n')
            for i, w in enumerate(ids):
                plug = "" if dojo else ' pluginWidget="true"'  # a Dojo widget declares no pluginWidget
                z.writestr(f"w{i}.xml", f'<?xml version="1.0"?>\n<widget id="{w}"{plug}></widget>\n')
            if js is not None:  # the widget's JavaScript bundle (NR2-24: replacement row R35 reads it)
                z.writestr("widget.js", js)
        raw = bytearray(open(wp, "rb").read())
        if defect == "crc":  # flip one stored data byte
            raw[raw.find(b"pluginWidget")] ^= 0x20
        elif defect == "descriptor":  # set "data descriptor follows" without writing one (the ListViewControls.mpk shape)
            for sig, off in ((b"PK\x03\x04", 6), (b"PK\x01\x02", 8)):
                j = raw.find(sig)
                while j >= 0:
                    raw[j + off] |= 8
                    j = raw.find(sig, j + 4)
        open(wp, "wb").write(bytes(raw))
    for rel, text in (spec.get("files") or {}).items():
        p = os.path.join(out, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(text)
    return path


def load_spec(path):
    spec = json.load(open(path))
    if "from" not in spec:
        return spec
    base = load_spec(os.path.join(os.path.dirname(os.path.abspath(path)), spec["from"]))
    for op, dotted, *val in spec.get("ops", []):
        keys = [int(k) if k.isdigit() else k for k in dotted.split("/")]
        node = base
        for k in keys[:-1]:
            node = node[k]
        if op == "set":
            node[keys[-1]] = val[0]
        elif op == "append":
            node[keys[-1]].append(val[0])
        elif op == "delete":
            del node[keys[-1]]
        else:
            sys.exit(f"mkmodel: unknown op {op}")
    return base


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    print(build(load_spec(sys.argv[1]), sys.argv[2]))
