#!/usr/bin/env python3
"""action_inventory.py: every clickable action of an app model, the denominator of the generated journeys (E2E-8).

    action_inventory.py <old.mpr|project dir> [--out actions.json]

Why: the journeys covered what someone thought of, never what the app has. T2R3 HANDWORK 14: the four Home page cards
are containers with an on-click action, not buttons, so smokewalk_gen and gen_journeys skipped them and someone wrote
four journeys by hand. N3-21: 7 journeys for 31 pages. A journey count means nothing without the count of actions it
is out of; this script gives that count from the model, before any journey exists.

What counts as an action: every widget with an on-click action (button, grid button, container, image, list view row,
navigation list item, a pluggable widget's action property, the Mendix 9 data grid "New" button) on a page, snippet or
layout that is not excluded, whose action is one of: create object, save, delete, call microflow, call nanoflow, open page, set task outcome, call
workflow, open user task / workflow. Cancel, close page, open link, sign out and "no action" are not actions here
(counted on the summary line as "not actions"); an action type this script does not know is listed with kind
"unknown" and todo "unknown-action", never dropped. On-change / on-enter / on-leave events of classic inputs are not
clicks and are not listed; a pluggable widget's action property is listed whatever its event (the Combo box's on-change
is one, and carries the combobox todo).

Per action (actions.json "actions"):
  id        <host>.<widget>  (host = the page, snippet or layout that holds the widget; "#n" when a host has two
            actions under one widget name, e.g. a pluggable widget with several action properties)
  action    the client action (create, save, delete, microflow, nanoflow, open-page, task-outcome, workflow-call,
            open-task, open-workflow, unknown)
  kind      what it does, from the flow body for microflow/nanoflow, transitively through sub-flows: task-outcome,
            workflow-call, workflow-op, delete, status-change (an enumeration attribute changed and committed), commit,
            external (REST/web service/external call only), create (object created, not committed), open-page,
            open-task, no-db-effect; "unknown" when the body is not readable (a protected add-on module)
  effects   every effect found (kind is the first by that order); "unreadable:<qn>" for a sub-flow or page the model
            does not hold
  path      the click path that reaches it: entry (menu item or home page, per navigation profile) -> page -> click
            -> page ... -> the widget; shortest path through hops that supply every page parameter, walked AS one user
            role: that role's home, and only pages and flows that role may open (path_role; path_roles = every role
            with such a path). T1R2: a role-blind walk sent the InvoiceProcessor task through the Approver's home.
  roles     user roles that may open the page and run the flow (module roles mapped through project security); a
            page a microflow shows is open to every role that may run that microflow, whatever its page access (B5-1)
  targets   for open-task / open-workflow: the workflow task pages / admin pages it can open
  fields    the inputs of the enclosing data view: widget, input type, attribute, attribute type (enumeration with its
            first value), association for reference selectors, editable
  row_fields  PR-F43: the inputs of a list nested in that data view, one per row, each with "list" (its name); only a
            process step fills them (every shown row). Purchase Request's PurchaseOrder_Edit keeps PromiseDate in
            listView1 under the Save's data view: no step could name it, so every PO leg stopped at Save (pipe-34)
  needs     data the journey needs (a row in a list, an open user task)
  todo      why a journey cannot be generated: combobox (the action fires on a change of a Combo box: no click to
            drive it; a Combo box among the fields is filled by journey-verbs.js "combo", PR-F25), page-parameter (a page on every path takes an object no hop
            supplies), external-call (the flow calls out: REST, web service, external action), no-click-path (no chain
            of clicks from a menu item or home page reaches it; "entry_reach" says whether a non-click caller does,
            gen_journeys' rule), no-role (no user role may both open the page and run the flow), unknown-action
  click     how a journey clicks it inside a list (E2E-10): {} outside one; {"row": list, "row_only": true} when the
            widget is the list (row on-click; PR-P3: plus "trigger": "double" when the Data grid 2 fires it on a
            double click, onClickTrigger = double: the `row` verb then double-clicks); {"row": list, "row_only": false} for a control-bar button of a classic
            grid (select the first row first); {"within": list} for a button repeated in each row. Path click hops
            carry the same keys plus "id"; the entry hop carries "via" (home, menu, login), "profile", "profile_kind"
            and, for a menu item, "menu" (its caption path)
  scope     PR-P4, a delete only: how far it reaches. identity (the delete, or an association it cascades through, reaches
            System.User / Administration.Account), delete-all (a database retrieve with no constraint, deleted whole),
            reimport (deletes and writes the same entities, or the flow chain is named *DemoData*, *Reset*, *Import*:
            a name only raises it), row (any other delete, the one object it is given). The first three wipe or
            reseed shared data: gen_journeys tags them "resetsData" and run_journeys runs them after the main set,
            counted apart ("destructive: P/F of N"). Top level "scopes" counts them
  confirm   {"proceed": caption} when the action asks for confirmation first (E2E-10)
  fields    PR-P5 adds per field: persistable false (the attribute is on a non-persistable entity: no table), and
            persisted_as (the persistent attribute the action's flow copies it to, "$Helper/Content" -> Entity.Content);
            E2E-10 adds per field: password, render (reference selector DropDown/Form), date_format, hidden (under a
            conditionally visible widget or on a tab page not shown first), and per attribute: length (String),
            enum_first_caption (what the drop-down shows)
  unknown   what the model could not tell (add-on bodies, missing documents; with a protected add-on present, an action
            whose readable callers run out at a document nothing readable references: the add-on may open it, so
            its path is unknown, not absent -- T2's Client Configuration overview is opened only from the add-on)

  reach     every document the action reaches, transitively, sorted: the host it sits in, the flow or page its click
            runs or opens, the sub-flows, pages (with their snippets and layouts), Java actions, workflows and constants
            those reference, and the modules those documents live in (a module is its bare name, a document its
            Module.Name; System.* targets are listed, not expanded). Reached through the same flow() walk and page
            closures as kind and path, one hop at a time, so a page's own widgets and their targets count when the
            page is reached. A reference the model does not hold (a protected add-on) is in reach_unknown, never dropped;
            unknown, and its module, is also in reach. impact_actions.py selects touched actions from it.
  reach_unknown  the references in reach the model does not hold, or the action has no target (no flow selected,
            an action type not known); [] when every reached document was read.

Summary line (also actions.json "summary"), the denominator stated:
  actions A found · by kind k n, ... · todo T by reason r n, ... · unknown U · not actions N · excluded docs E
A comes from the model, never from the journeys that survived. Unreadable modules (protected add-ons referenced by the
model but not in it) are listed: paths through them cannot be followed, the actions behind them are still counted.

Exit 0 when the inventory was written (todo and unknown are findings, not errors); 1 when the model cannot be read.
Read-only. Works on MPR v1 and v2 (mprmodel.py), Mendix 9, 10 and 11.
"""
import argparse, collections, json, os, re, sys

# PR-C1: a list view XPath that keeps only the tasks of the current user
MINE_XPATH = re.compile(r"Assignee\w*\s*=\s*'\[%CurrentUser%\]'", re.I)
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mprmodel import Model, text_of  # noqa: E402
from gen_journeys import entry_reach  # noqa: E402  same reachability rule as the generated journeys' "unreachable"
import impact_map as I  # noqa: E402  Roles, snippet_closure, layout_closure, FLOW_TYPES, UI_TYPES

# reach: the keys under which a document names another document (Form, Microflow, ...), as the model stores them
REF_KEYS = ("Form", "Page", "Microflow", "Nanoflow", "JavaAction", "Snippet", "Layout", "Workflow", "Rule")

CLIENT = {
    "Forms$CreateObjectClientAction": "create",
    "Forms$SaveChangesClientAction": "save",
    "Forms$DeleteClientAction": "delete",
    "Forms$MicroflowAction": "microflow",
    "Forms$CallNanoflowClientAction": "nanoflow",
    "Forms$FormAction": "open-page",
    "Forms$SetTaskOutcomeClientAction": "task-outcome",
    "Forms$CompleteTaskClientAction": "task-outcome",
    "Forms$CallWorkflowClientAction": "workflow-call",
    "Forms$OpenUserTaskClientAction": "open-task",
    "Forms$OpenWorkflowClientAction": "open-workflow",
}
NOT_ACTIONS = {"Forms$CancelChangesClientAction": "cancel", "Forms$ClosePageClientAction": "close",
               "Forms$OpenLinkClientAction": "link", "Forms$SignOutClientAction": "sign-out",
               "Forms$SyncClientAction": "sync", "Forms$ToggleDesignModeClientAction": "design-mode"}
ACTION_KEYS = ("Action", "OnClickAction", "ClickAction")
HOSTS = ("Forms$Page", "Forms$Snippet", "Forms$Layout")
FLOWS = ("Microflows$Microflow", "Microflows$Nanoflow")
EXTERNAL = {"Microflows$RestCallAction", "Microflows$WebServiceCallAction", "Microflows$CallExternalAction",
            "Microflows$SendRestRequestAction", "Microflows$RestOperationCallAction"}
KIND_ORDER = ["task-outcome", "workflow-call", "workflow-op", "delete", "status-change", "commit", "external", "create",
              "open-page", "open-task", "open-workflow"]
INPUTS = {"Forms$TextBox": "text", "Forms$TextArea": "text", "Forms$DatePicker": "date", "Forms$CheckBox": "toggle",
          "Forms$RadioButtonGroup": "radio", "Forms$DropDown": "select", "Forms$ReferenceSelector": "reference",
          "Forms$ReferenceSetSelector": "reference-set", "Forms$InputReferenceSetSelector": "reference-set",
          "Forms$FileManager": "file", "Forms$ImageUploader": "file"}
LISTS = ("Forms$ListView", "Forms$DataGrid", "Forms$TemplateGrid", "Forms$ReferenceSetSelector")
LIST_WIDGETS = ("datagrid.Datagrid", "gallery.Gallery", "treenode", "listview")


def lst(x):
    return [i for i in (x or []) if isinstance(i, dict)]


def shown_if(name, cv):
    """PR-F38: one conditional visibility setting -> {"widget", "text", "roles"}. text is what must hold for the widget
    to be on screen: the expression, the attribute and its values, and/or the module roles; roles: those module roles
    (empty when the setting does not limit by role)."""
    parts = []
    if (cv.get("Expression") or "").strip():
        parts.append(cv["Expression"].strip())
    attr = first(cv.get("AttributeRef"), "Attribute") if isinstance(cv.get("AttributeRef"), dict) else cv.get("Attribute")
    if attr:
        vals = [c.get("AttributeValue") for c in lst(cv.get("Conditions")) if c.get("EditableVisible")]
        parts.append(f"{attr} in {vals}" if vals else f"{attr} set")
    roles = [r for r in (cv.get("ModuleRoles") or []) if isinstance(r, str)]
    if roles:
        parts.append("module roles " + ", ".join(roles))
    return {"widget": name, "text": f"{name}: " + ("; ".join(parts) or "conditional"), "roles": roles}


def wid(node):
    """Pluggable widget id (CustomWidgets$CustomWidget), else ''."""
    t = node.get("Type") if isinstance(node, dict) else None
    return (t or {}).get("WidgetId", "") if isinstance(t, dict) else ""


def first(x, key):
    """First string value of key anywhere under x."""
    if isinstance(x, dict):
        if isinstance(x.get(key), str) and x[key]:
            return x[key]
        for v in x.values():
            r = first(v, key)
            if r:
                return r
    elif isinstance(x, list):
        for v in x:
            r = first(v, key)
            if r:
                return r
    return ""


def all_values(x, key, out):
    if isinstance(x, dict):
        if isinstance(x.get(key), str) and x[key]:
            out.append(x[key])
        for v in x.values():
            all_values(v, key, out)
    elif isinstance(x, list):
        for v in x:
            all_values(v, key, out)
    return out


def all_nodes(x, typ, out=None):
    """Every dict of $Type typ anywhere under x."""
    out = [] if out is None else out
    if isinstance(x, dict):
        if x.get("$Type") == typ:
            out.append(x)
        for v in x.values():
            all_nodes(v, typ, out)
    elif isinstance(x, list):
        for v in x:
            all_nodes(v, typ, out)
    return out


SCOPES = ("identity", "delete-all", "reimport", "row")   # PR-P4, most severe first; the first three are "destructive"
RESET_NAME = re.compile(r"demodata|reset|import", re.I)


ROW_PROPS = {"columns", "content"}  # PR-F35: the Data grid 2 / Gallery properties rendered once per row


def prop_key(w, prop):
    """The PropertyKey of pluggable widget w's property prop (its TypePointer resolved through the widget's type)."""
    for pt in lst(((w.get("Type") or {}).get("ObjectType") or {}).get("PropertyTypes")):
        if pt.get("$ID") == prop.get("TypePointer"):
            return pt.get("PropertyKey")
    return None


def holds(x, target):
    """True when target (an object) sits anywhere under x, by identity."""
    if x is target:
        return True
    if isinstance(x, dict):
        return any(holds(v, target) for v in x.values())
    if isinstance(x, list):
        return any(holds(v, target) for v in x)
    return False


def list_area(w, target):
    """(property key that holds target, selection) for pluggable list widget w: selection is its itemSelection
    ("None", "Single", "Multi"; "" when the widget has none). PR-F35."""
    props = lst((w.get("Object") or {}).get("Properties"))
    key = next((prop_key(w, pr) for pr in props if holds(pr.get("Value"), target)), None)
    v = next((pr.get("Value") or {} for pr in props if prop_key(w, pr) == "itemSelection"), {})
    sel = v.get("Selection") or v.get("PrimitiveValue") or ""     # the mode is in Selection (10.24 model)
    return key, sel


def row_trigger(w):
    """PR-P3: how a Data grid 2 row fires its on-click action: "double" when its onClickTrigger property says so, else
    "" (single click, the default; also a widget that has no such property). A model fact, not a retry: Purchase
    Request's Product_Overview / Vendor_Overview / MendixSSOUserOverview grid1 carry onClickTrigger = double, and a
    single click on a row only focuses the cell (pipe-30 screenshots: nothing opened, 3 baseline defects)."""
    for pr in lst((w.get("Object") or {}).get("Properties")):
        if prop_key(w, pr) == "onClickTrigger":
            return "double" if (pr.get("Value") or {}).get("PrimitiveValue") == "double" else ""
    return ""


def containers_grid(cont):
    """The innermost list container (the data grid a GridNewButton sits in), else None."""
    return cont[-1]["node"] if cont and cont[-1]["list"] else None


def caption(node):
    for k in ("CaptionTemplate", "Caption"):
        c = node.get(k)
        if isinstance(c, dict):
            t = text_of(c.get("Template") if c.get("$Type") == "Forms$ClientTemplate" else c)
            if t:
                return t
    return ""


class Inventory:
    def __init__(self, m):
        self.m = m
        self.roles = I.Roles(m)
        self.opened_by = {}   # filled by build() (B5-1)
        self.attr = self._attributes()
        self.enums = {d.qn: [v.get("Name") for v in lst(d.data.get("Values"))]
                      for d in m.of_type("Enumerations$Enumeration")}
        # E2E-10: a drop-down shows the value's caption, not its name; the generated journey selects by caption
        self.enum_caps = {d.qn: [text_of(v.get("Caption")) or v.get("Name") for v in lst(d.data.get("Values"))]
                          for d in m.of_type("Enumerations$Enumeration")}
        # the task's OWN TaskPage: first(t, "Page") would find a nested task's page under Outcomes[].Flow first
        self.task_pages = sorted({first(t.get("TaskPage"), "Page") for d in m.of_type("Workflows$Workflow")
                                  for t in self._user_tasks(d.data) if first(t.get("TaskPage"), "Page")})
        self.admin_pages = sorted({first(d.data.get("AdminPage"), "Page") for d in m.of_type("Workflows$Workflow")
                                   if first(d.data.get("AdminPage"), "Page")})
        self.unreadable_modules = set()
        self._flow = {}
        self.points = {}        # host qn -> [point]
        self.menu_hops = {}     # host qn -> [menu document item hop points] (hops only, not actions)
        self.on = {}            # page qn -> hosts it renders (closures(); reach)
        self._expanded = {}     # reach: qn -> (docs, unknown), one hop, memoised
        self.not_actions = collections.Counter()
        self.excluded = 0

    # ------------------------------------------------------------------ model facts
    def _attributes(self):
        out = {}
        for d in self.m.of_type("DomainModels$DomainModel") + [x for x in self.m.docs.values()
                                                               if x.type == "DomainModels$DomainModel"]:
            for e in lst(d.data.get("Entities")):
                npe = (e.get("MaybeGeneralization") or {}).get("Persistable") is False   # a non-persistable entity
                for a in lst(e.get("Attributes")):
                    t = a.get("NewType") or a.get("Type") or {}
                    short = (t.get("$Type", "") if isinstance(t, dict) else "").split("$")[-1].replace("AttributeType", "")
                    rec = {"type": short or "unknown"}
                    if npe:
                        rec["persistable"] = False   # PR-P5: no table: a query on it is rejected
                    if short == "Enumeration":
                        rec["enum"] = t.get("Enumeration", "")
                    if short == "String" and isinstance(t.get("Length"), int) and t["Length"] > 0:
                        rec["length"] = t["Length"]   # E2E-10: a generated value must fit
                    out[f"{d.module}.{e.get('Name')}.{a.get('Name')}"] = rec
        return out

    def identity_entities(self):
        """PR-P4: System.User, Administration.Account and every entity that specialises System.User or such an entity."""
        if getattr(self, "_identity", None) is None:
            gen = {}
            for d in self.m.docs.values():
                if d.type == "DomainModels$DomainModel":
                    for e in lst(d.data.get("Entities")):
                        g = (e.get("MaybeGeneralization") or {}).get("Generalization")
                        if g:
                            gen[f"{d.module}.{e.get('Name')}"] = g
            out = {"System.User", "Administration.Account"}
            while True:
                more = {e for e, g in gen.items() if g in out and e not in out}
                if not more:
                    break
                out |= more
            self._identity = out
        return self._identity

    def cascade(self, ents):
        """PR-P4: ents plus every entity a delete of one of them removes through an association whose delete behaviour
        is "delete me and references": the child when the parent is deleted, the parent when the child is (Mendix:
        DeleteMeAndReferences), to a fixed point."""
        if getattr(self, "_cascade", None) is None:
            edges = collections.defaultdict(set)
            dms = [d for d in self.m.docs.values() if d.type == "DomainModels$DomainModel"]
            # an association is stored in its owner's module and may point at an entity of another one (Request ->
            # MendixSSOUser): the pointers resolve over every domain model
            ids = {e.get("$ID"): f"{d.module}.{e.get('Name')}" for d in dms for e in lst(d.data.get("Entities"))}
            for d in dms:
                for a in lst(d.data.get("Associations")):
                    par, chi, b = ids.get(a.get("ParentPointer")), ids.get(a.get("ChildPointer")), a.get("DeleteBehavior") or {}
                    if par and chi and b.get("ParentDeleteBehavior") == "DeleteMeAndReferences":
                        edges[par].add(chi)
                    if par and chi and b.get("ChildDeleteBehavior") == "DeleteMeAndReferences":
                        edges[chi].add(par)
            self._cascade = edges
        out, todo = set(ents), list(ents)
        while todo:
            for n in self._cascade.get(todo.pop(), ()):
                if n not in out:
                    out.add(n)
                    todo.append(n)
        return out

    def scope_of(self, deletes, written, names, ent=None):
        """PR-P4: how far a delete reaches, or None when it deletes nothing. identity: the delete closure reaches
        System.User / Administration.Account (directly or by cascade); delete-all: a database retrieve with no
        constraint is deleted whole; reimport: it deletes and writes the same entities, or the flow chain is named
        *DemoData* / *Reset* / *Import* (a name only ever raises the scope, never clears it); row: any other delete
        (the one object it is given). Seeding report 1: 47 of 98 runnable actions carry the bare "delete" effect, so
        the effect alone cannot say which one wipes the data."""
        ents = {d["entity"] for d in deletes if d["entity"]} | ({ent} if ent else set())
        if not deletes and not ent:
            return None
        if self.cascade(ents) & self.identity_entities():
            return "identity"
        if any(d["all"] for d in deletes):
            return "delete-all"
        listed = {d["entity"] for d in deletes if d["entity"] and not d.get("param")}   # a given object is a row delete
        if listed & set(written) or any(RESET_NAME.search(n.rsplit(".", 1)[-1]) or RESET_NAME.search(n.split(".")[0]) for n in names):
            return "reimport"
        return "row"

    def _user_tasks(self, x, out=None):
        out = [] if out is None else out
        if isinstance(x, dict):
            if "UserTask" in x.get("$Type", "") and "Outcome" not in x.get("$Type", ""):
                out.append(x)
            for v in x.values():
                self._user_tasks(v, out)
        elif isinstance(x, list):
            for v in x:
                self._user_tasks(v, out)
        return out

    def readable(self, qn):
        """True when the model holds the document; records the module of a missing one as unreadable."""
        if qn in self.m.docs:
            return True
        mod = qn.split(".", 1)[0] if qn else ""
        if mod and mod not in self.m.modules and mod != "System":
            self.unreadable_modules.add(mod)
        return False

    def attr_type(self, attr):
        if not attr:
            return {"type": "none"}
        rec = dict(self.attr.get(attr) or {})
        if not rec:
            mod = attr.split(".", 1)[0]
            if mod not in self.m.modules and mod != "System":
                self.unreadable_modules.add(mod)
                return {"type": "unknown", "why": f"entity in module {mod}, not in the model (protected add-on)"}
            if mod == "System":
                return {"type": "unknown", "why": "System module: the runtime defines it, the .mpr does not store its attributes"}
            return {"type": "unknown", "why": "attribute not found in the domain model"}
        if rec.get("enum"):
            vals = self.enums.get(rec["enum"])
            rec["enum_first"] = vals[0] if vals else None
            caps = self.enum_caps.get(rec["enum"])
            rec["enum_first_caption"] = caps[0] if caps else None
        return rec

    # ------------------------------------------------------------------ flow bodies
    def flow(self, qn, stack=()):
        """{effects, shows, unreadable, outcomes, external} of a microflow/nanoflow, through its sub-flows."""
        if qn in self._flow:
            return self._flow[qn]
        res = {"effects": set(), "shows": set(), "unreadable": set(), "outcomes": [], "external": set(),
               "workflows": set(), "java": set(), "docs": {qn},   # docs: this flow and every sub-flow (reach)
               "deletes": [], "written": set(), "copies": []}   # PR-P4: what it deletes ({entity, all}) and creates / commits (entities)
        if qn in stack:
            return res
        d = self.m.docs.get(qn)
        if d is None or d.type not in FLOWS:
            if not self.readable(qn) or d is None:
                res["unreadable"].add(qn)
            self._flow[qn] = res
            return res
        enum_changed = False
        vt = {}   # PR-P4: variable -> (entity, retrieved without a constraint), for the delete scope
        for pa in all_nodes(d.data, "Microflows$MicroflowParameter"):
            vt[pa.get("Name")] = ((pa.get("VariableType") or {}).get("Entity"), False, True)
        for a in self._actions(d.data):
            t = a.get("$Type", "")
            if t == "Microflows$RetrieveAction":
                src = a.get("RetrieveSource") or {}
                if src.get("$Type") == "Microflows$DatabaseRetrieveSource":
                    rng = src.get("Range") or {}
                    one = rng.get("$Type") != "Microflows$ConstantRange" or bool(rng.get("SingleObject"))
                    vt[a.get("ResultVariableName")] = (src.get("Entity"), not (src.get("XpathConstraint") or "").strip() and not one, False)
            if t in ("Microflows$CreateObjectAction", "Microflows$CreateChangeAction") and a.get("Entity"):
                res["written"].add(a["Entity"])
                vt[a.get("OutputVariableName") or a.get("ResultVariableName") or a.get("VariableName")] = (a["Entity"], False, False)
            if t == "Microflows$CommitAction" and vt.get(a.get("CommitVariableName"), (None,))[0]:
                res["written"].add(vt[a["CommitVariableName"]][0])
            if t == "Microflows$DeleteAction":
                ent, whole, prm = vt.get(a.get("DeleteVariableName"), (None, False, False))
                res["deletes"].append({"entity": ent, "all": whole, "param": prm})
            if t == "Microflows$CommitAction":
                res["effects"].add("commit")
            elif t in ("Microflows$ChangeAction", "Microflows$CreateChangeAction", "Microflows$ChangeObjectAction",
                       "Microflows$CreateObjectAction"):
                if str(a.get("Commit", "No")) not in ("No", "False", ""):
                    res["effects"].add("commit")
                if "Create" in t:
                    res["effects"].add("create")
                for it in lst(a.get("Items")):
                    if self.attr.get(it.get("Attribute") or "", {}).get("type") == "Enumeration":
                        enum_changed = True
                    m = re.fullmatch(r"\$\w+/(\w+)", str(it.get("Value") or "").strip())
                    if m and it.get("Attribute"):   # PR-P5: target attribute <- $Object/Member, a plain copy
                        res["copies"].append((it["Attribute"], m.group(1)))
            elif t == "Microflows$DeleteAction":
                res["effects"].add("delete")
            elif t == "Microflows$WorkflowCallAction":
                res["effects"].add("workflow-call"); res["workflows"].add(a.get("Workflow") or "")
            elif t in ("Microflows$SetTaskOutcomeAction", "Microflows$CompleteUserTaskAction"):
                res["effects"].add("task-outcome"); res["outcomes"].append(a.get("OutcomeValue") or a.get("Outcome") or "")
            elif t == "Microflows$WorkflowOperationAction":
                res["effects"].add("workflow-op")
            elif t in EXTERNAL:
                res["effects"].add("external"); res["external"].add(t.split("$")[-1])
            elif t == "Microflows$JavaActionCallAction":
                res["java"].add(a.get("JavaAction") or "")
            elif t == "Microflows$ShowFormAction" or t == "Microflows$ShowPageAction":
                p = first(a.get("FormSettings") or a.get("PageSettings"), "Form") or first(a, "Page")
                if p:
                    res["shows"].add(p)
            elif t == "Microflows$OpenUserTaskAction":
                res["effects"].add("open-task"); res["shows"].update(self.task_pages)
            elif t == "Microflows$OpenWorkflowAction":
                res["effects"].add("open-workflow"); res["shows"].update(self.admin_pages)
            elif t in ("Microflows$MicroflowCallAction", "Microflows$NanoflowCallAction"):
                sub = first(a.get("MicroflowCall") or a.get("NanoflowCall"), "Microflow") or \
                      first(a.get("NanoflowCall"), "Nanoflow")
                if sub:
                    r = self.flow(sub, stack + (qn,))
                    for k in ("effects", "shows", "unreadable", "external", "workflows", "java", "docs", "written"):
                        res[k] |= r[k]
                    res["outcomes"] += r["outcomes"]
                    res["deletes"] += r["deletes"]
                    res["copies"] += r["copies"]
        if enum_changed and "commit" in res["effects"]:
            res["effects"].add("status-change")
        for p in list(res["shows"]):
            if not self.readable(p):
                res["unreadable"].add(p)
        self._flow[qn] = res
        return res

    def _actions(self, x, out=None):
        out = [] if out is None else out
        if isinstance(x, dict):
            if x.get("$Type") == "Microflows$ActionActivity" and isinstance(x.get("Action"), dict):
                out.append(x["Action"])
            for v in x.values():
                self._actions(v, out)
        elif isinstance(x, list):
            for v in x:
                self._actions(v, out)
        return out

    # ------------------------------------------------------------------ widgets
    def collect(self):
        for d in self.m.all_docs:
            if d.type not in HOSTS:
                continue
            if d.data.get("Excluded"):
                self.excluded += 1
                continue
            pts = []
            self._walk(d.data, d.qn, None, [], [], pts)
            names = collections.Counter()
            for p in pts:
                names[p["widget"]] += 1
                p["id"] = f"{d.qn}.{p['widget']}" + (f"#{names[p['widget']]}" if names[p["widget"]] > 1 else "")
            self.points[d.qn] = pts
            self.menu_hops[d.qn] = self._menu_hops(d)

    def _menu_hops(self, host):
        """Click points of the menu documents a host shows (a layout's side bar, a snippet's menu bar). Not actions of
        their own (a menu item is no widget of a page): hops only, so the BFS can climb through them. Each is a point:
        widget = the menu bar widget, "menu_item" = the item's position in the menu document (journey-verbs.js
        menuitem), "caption" = its caption. Only top-level items; a nested item needs its parent opened first."""
        out = []

        def bars(x, own, acc):
            if isinstance(x, dict):
                if isinstance(x.get("Name"), str) and x["Name"] and str(x.get("$Type", "")).startswith("Forms$"):
                    own = x
                v = x.get("Menu")
                if isinstance(v, str) and v in self.m.docs and self.m.docs[v].type == "Menus$MenuDocument" and own:
                    acc.append((v, own["Name"]))
                for v in x.values():
                    bars(v, own, acc)
            elif isinstance(x, list):
                for v in x:
                    bars(v, own, acc)
        found = []
        bars(host.data, None, found)
        for mq, bar in dict.fromkeys(found):
            for i, it in enumerate(i for i in lst((self.m.docs[mq].data.get("ItemCollection") or {}).get("Items")) if isinstance(i, dict)):
                a = it.get("Action")
                if not isinstance(a, dict) or not a.get("$Type") or a["$Type"] == "Forms$NoAction" \
                        or a["$Type"] in NOT_ACTIONS:
                    continue
                out.append({"host": host.qn, "widget": bar, "widget_type": "MenuBar", "caption": caption(it),
                            "raw_type": a["$Type"], "action": CLIENT.get(a["$Type"], "unknown"), "node": a,
                            "containers": [], "conditional": [], "menu_item": i, "menu_doc": mq,
                            "id": f"{mq}.item{i + 1}"})
        return out

    def _walk(self, x, host, owner, containers, conditional, pts):
        if isinstance(x, list):
            for v in x:
                self._walk(v, host, owner, containers, conditional, pts)
            return
        if not isinstance(x, dict):
            return
        t = x.get("$Type", "")
        if isinstance(x.get("Name"), str) and x.get("Name") and t.startswith(("Forms$", "CustomWidgets$", "Pages$")):
            owner = x
        if isinstance(x.get("ConditionalVisibilitySettings"), dict):
            conditional = conditional + [shown_if(x.get("Name") or t.split("$")[-1], x["ConditionalVisibilitySettings"])]
        cont = containers
        if t == "Forms$DataView" or t in LISTS or (t == "CustomWidgets$CustomWidget" and any(s in wid(x) for s in LIST_WIDGETS)):
            ent = first(x.get("DataSource"), "Entity")
            cont = containers + [{"node": x, "type": t.split("$")[-1] if t != "CustomWidgets$CustomWidget" else wid(x),
                                  "name": x.get("Name"), "entity": ent, "list": t != "Forms$DataView",
                                  # PR-P4: a pluggable list keeps its data source in a property; "entity" stays as it was
                                  "ds_entity": ent or (first(x.get("Object"), "Entity") if t == "CustomWidgets$CustomWidget" else None),
                                  "param": (x.get("DataSource") or {}).get("PageParameter") if isinstance(x.get("DataSource"), dict) else None,
                                  # PR-C1: a classic list view / template grid keeps its XPath on the data source
                                  "xpath": (x.get("DataSource") or {}).get("XPathConstraint") or "" if isinstance(x.get("DataSource"), dict) else ""}]
        if t == "Forms$GridNewButton":
            # E2E-8: the Mendix 9 data grid "New" button carries no Action -- Entity + FormSettings sit on the widget
            # itself. It is T2R3's newButton1 (create-spec.json); it needs no selected row, so the grid is not a need.
            pts.append({"host": host, "widget": x.get("Name") or "?", "widget_type": "GridNewButton",
                        "caption": caption(x), "raw_type": t, "action": "create", "node": x,
                        "containers": [c for c in cont if c["node"] is not containers_grid(cont)],
                        "conditional": conditional})
        for k in ACTION_KEYS:
            a = x.get(k)
            if not isinstance(a, dict) or not a.get("$Type"):
                continue
            at = a["$Type"]
            if at == "Forms$NoAction":
                continue
            if at in NOT_ACTIONS:
                self.not_actions[NOT_ACTIONS[at]] += 1
                continue
            o = owner or {}
            pts.append({"host": host, "widget": o.get("Name") or "?", "widget_type": (o.get("$Type", "").split("$")[-1]
                        if o.get("$Type") != "CustomWidgets$CustomWidget" else wid(o)) or "?",
                        "caption": caption(x) or caption(o), "raw_type": at, "action": CLIENT.get(at, "unknown"),
                        "node": a, "containers": cont, "conditional": conditional,
                        **({"item": x["_item"], "items": x["_items"]} if t == "Forms$NavigationListItem" and "_item" in x else {})})
        if t == "Forms$NavigationList":
            # PR-F26: a navigation list item has no name of its own; its action belongs to the list widget, so the
            # click needs the item's position (Purchase Request pipe-19: a click on the whole navigationList2 hit
            # its middle item, "Step 2", on the way to Step 3). Index among the items, model order.
            items = [it for it in lst(x.get("Items")) if isinstance(it, dict)]
            for i, it in enumerate(items):
                self._walk(dict(it, _item=i, _items=len(items)), host, owner, cont, conditional, pts)
            x = {k: v for k, v in x.items() if k != "Items"}
        for k, v in x.items():
            if k in ACTION_KEYS:
                continue
            self._walk(v, host, owner, cont, conditional, pts)

    def fields(self, dv):
        """Inputs inside data view dv, not inside a nested list or data view. E2E-10 (what gen_journeys needs to fill
        one): password (a password box), render (a reference selector's DropDown or Form), date_format, and hidden (the
        input is under a conditionally visible widget or on a tab page not shown first: not on screen when the page
        opens, so a generated fill would fail on a healthy app)."""
        out = []

        def walk(x, top, hidden=None, in_list=None):
            if isinstance(x, list):
                for v in x:
                    walk(v, top, hidden, in_list)
                return
            if not isinstance(x, dict):
                return
            t = x.get("$Type", "")
            if not top and (t == "Forms$DataView" or t in LISTS):
                return
            if not top and not in_list and t == "CustomWidgets$CustomWidget" and any(s in wid(x) for s in LIST_WIDGETS):
                # FN-7: a Gallery / Data grid 2 is a list; its inputs repeat per item and an empty list renders none, so a
                # fill generated for one failed "input not visible" on a healthy app; a list with rows does show them, so
                # dropping the field loses a fill that works. Keep the field, marked in_list: gen_journeys makes its fill
                # optional.
                for k, v in x.items():
                    if k not in ACTION_KEYS:
                        walk(v, False, hidden, x.get("Name") or "list")
                return
            if not hidden and x.get("ConditionalVisibilitySettings"):
                hidden = f"conditionally visible ({x.get('Name') or t.split('$')[-1]})"
            if t == "Forms$TabControl":
                for i, tp in enumerate(lst(x.get("TabPages"))):
                    walk(tp, False, hidden or (f"on tab page {tp.get('Name') or i + 1}, not shown first" if i else None), in_list)
                return
            w = wid(x) if t == "CustomWidgets$CustomWidget" else ""
            kind = INPUTS.get(t) or ("combobox" if "combobox" in w.lower() else None)
            if kind:
                ar = x.get("AttributeRef") if isinstance(x.get("AttributeRef"), dict) else {}
                attr = ar.get("Attribute") or (first(x, "Attribute") if w else "")
                assoc = all_values(ar.get("EntityRef"), "Association", []) or (all_values(x, "Association", [])[:1] if w else [])
                f = {"widget": x.get("Name"), "input": kind, "attribute": attr or None, "attr_type": self.attr_type(attr)}
                if assoc:
                    f["association"] = assoc[-1]
                ed = x.get("Editable")
                if ed is not None:
                    f["editable"] = ed
                if x.get("IsPasswordBox"):
                    f["password"] = True
                if isinstance(x.get("RenderMode"), str):
                    f["render"] = x["RenderMode"]
                fi = x.get("FormattingInfo") if isinstance(x.get("FormattingInfo"), dict) else {}
                if t == "Forms$DatePicker":
                    f["date_format"] = {"DateFormat": fi.get("DateFormat") or "Date", "Custom": fi.get("CustomDateFormat") or ""}
                if hidden:
                    f["hidden"] = hidden
                if in_list:
                    f["in_list"] = in_list   # FN-7
                out.append(f)
                return
            for k, v in x.items():
                if k not in ACTION_KEYS:
                    walk(v, False, hidden, in_list)
        walk(dv, True)
        return out

    def row_fields(self, dv):
        """PR-F43: the inputs of each list directly inside data view dv (not inside a nested data view), as fields()
        lists them for the list, each tagged "list": the list's name. A user fills them row by row before the data
        view's Save (Purchase Request PurchaseOrder_Edit: PODate / PromiseDate / GeneralLedgerNumber per PO)."""
        out = []

        def find(x, top):
            if isinstance(x, list):
                for v in x:
                    find(v, top)
                return
            if not isinstance(x, dict):
                return
            t = x.get("$Type", "")
            if not top and t == "Forms$DataView":
                return
            if t in LISTS:
                out.extend(dict(f, list=x.get("Name")) for f in self.fields(x))
                return
            for k, v in x.items():
                if k not in ACTION_KEYS:
                    find(v, False)
        find(dv, True)
        return out

    # ------------------------------------------------------------------ targets and paths
    def targets(self, p):
        """Pages a click opens, and whether the hop supplies the target's parameter."""
        a, act = p["node"], p["action"]
        if act in ("open-page", "create"):
            pg = first(a.get("FormSettings") or a.get("PageSettings"), "Form")
            return [pg] if pg else []
        if act in ("microflow", "nanoflow"):
            f = self._flow_of(p)
            return sorted(self.flow(f)["shows"]) if f else []
        if act == "open-task":
            return list(self.task_pages)
        if act == "open-workflow":
            return list(self.admin_pages)
        return []

    def _flow_of(self, p):
        a = p["node"]
        return first(a.get("MicroflowSettings"), "Microflow") or a.get("Nanoflow") or first(a, "Nanoflow") or ""

    def supplies(self, p, page):
        """Does clicking p give page its parameters? A flow, a create or a task open supplies its own object; an
        open-page supplies one when it maps parameters or sits inside a data container."""
        d = self.m.docs.get(page)
        if d is None or not lst(d.data.get("Parameters")):
            return True
        if p["action"] in ("microflow", "nanoflow", "create", "open-task", "open-workflow"):
            return True
        a = p["node"]
        maps = lst((a.get("FormSettings") or a.get("PageSettings") or {}).get("ParameterMappings"))
        return bool(maps or p["containers"])

    def closures(self):
        """page -> hosts it renders (itself, its snippets, its layouts and their snippets); host -> pages."""
        on, via = {}, collections.defaultdict(set)
        for d in self.m.all_docs:
            if d.type != "Forms$Page" or d.data.get("Excluded"):
                continue
            hs = list(dict.fromkeys(I.snippet_closure(self.m, d.qn, depth=6) + I.layout_closure(self.m, d.qn)))
            for h in list(hs):
                if self.m.docs.get(h) and self.m.docs[h].type == "Forms$Layout":
                    hs += [s for s in I.snippet_closure(self.m, h, depth=6) if s not in hs]
            on[d.qn] = hs
            for h in hs:
                via[h].add(d.qn)
        return on, via

    def entries(self, role=None):
        """(label, target, how) per navigation entry. With a role: only that role's home (the role-specific home wins
        over the default one, as in the runtime) and only targets the role may open. how (E2E-10, what gen_journeys
        walks): {"via": home|menu|login, "profile", "profile_kind", "menu": [captions]}."""
        out = []
        for prof, pr in self.m.navigation().items():
            base = {"profile": prof, "profile_kind": pr.get("kind")}
            homes = pr.get("homes", [])
            if role is not None:
                own = [h for h in homes if h.get("role") == role]
                homes = own or [h for h in homes if h.get("role") in ("*", None)]
            for h in homes:
                label = f"home {prof}" + ("" if h.get("role") in ("*", None) else f" ({h['role']})")
                for t in (h.get("page"), h.get("microflow")):
                    if t:
                        out.append((label, t, dict(base, via="home")))
            for it in pr.get("menu", []):
                if it.get("target"):
                    out.append((f"menu {prof}: " + " > ".join(c or "?" for c in it["path"]), it["target"],
                                dict(base, via="menu", menu=list(it["path"]))))
            if pr.get("login_page"):
                out.append((f"login page {prof}", pr["login_page"], dict(base, via="login")))
        if role is not None:
            out = [e for e in out if e[1] not in self.m.docs or role in self.roles.of_doc(e[1])]
        return out

    def may(self, role, p, tgt):
        """May role click p and land on tgt? Unknown (unreadable) flows do not block: the page check still applies.
        B5-1: a page a MICROFLOW shows needs no page access of its own -- the runtime opens it for whoever may run the
        microflow (Kanban with Opcenter: KanbanBoard_Overview has no allowed roles; NAV_KanbanBoard_Overview, the
        WarehouseWorker home, opens it). A nanoflow's show page is a client request and keeps the page check."""
        if role is None:
            return True
        # PR-F38: a widget shown only to some module roles is not there for a role outside them, whatever the flow
        # and page allow
        for c in p.get("conditional") or []:
            if c["roles"] and role not in self.roles.of_module_roles(c["roles"]):
                return False
        f = self._flow_of(p) if p["action"] in ("microflow", "nanoflow") else ""
        if f and f in self.m.docs and role not in self.roles.of_doc(f):
            return False
        if p["action"] == "microflow" and f in self.m.docs and self.m.docs[f].type == "Microflows$Microflow":
            return True
        return role in self.roles.of_doc(tgt)

    def page_roles(self, pg):
        """Roles that may land on page pg: its own page access, plus (B5-1) the roles of every microflow that shows it."""
        return self.roles.of_doc(pg) | self.opened_by.get(pg, set())

    def bfs(self, on, strict, role=None):
        """parent[page] = (prev page or None, entry label or point, depth). strict: only hops that supply params.
        role: only entries and hops that user role is allowed (E2E-8: a path must be walkable by the role it names)."""
        parent, frontier, deferred = {}, [], []
        for label, t, how in self.entries(role):
            d = self.m.docs.get(t)
            if d is None:
                self.readable(t)
                continue
            pages = [t] if d.type == "Forms$Page" else sorted(self.flow(t)["shows"]) if d.type in FLOWS else []
            if d.type in FLOWS and len(pages) > 1:
                # FN-3: a microflow entry that shows several pages picks one by its data (a detail page when the user
                # belongs to a team, an overview when not). Landing on a page that needs an object is a guess about the
                # test user's data: on the field run a third of the journeys of the healthy OLD app walked the entry
                # expecting the detail page and met the overview. Land on the branch pages without parameters only, and
                # let the BFS reach the others by clicks from there.
                plain = [pg for pg in pages if pg in self.m.docs and not lst(self.m.docs[pg].data.get("Parameters"))]
                if plain:
                    deferred.extend((label, t, how, pg) for pg in pages if pg not in plain)
                    pages = plain
            for pg in pages:
                if pg in parent or pg not in self.m.docs:
                    continue
                if role is not None and role not in self.roles.of_doc(pg) and d.type != "Microflows$Microflow":
                    continue   # B5-1: a microflow entry (NAV_ menu item / home) opens its page whatever the page access
                if strict and d.type == "Forms$Page" and lst(self.m.docs[pg].data.get("Parameters")):
                    continue
                parent[pg] = (None, {"entry": label, "target": t, **how}, 0)
                frontier.append(pg)
        depth = 0
        while frontier:
            depth += 1
            nxt = []
            # PR-F38: within a layer, a page any always-shown widget opens is reached through it, not through one
            # that a condition hides (Purchase Request pipe-30: 62 of 91 baseline FAILs clicked a conditionally
            # visible hop; the audit trail path went through "Open parent workflow", shown only for a sub-workflow
            # in an app that has none)
            for p, pg in [(p, pg) for want in (False, True) for pg in frontier for h in on.get(pg, [pg])
                          for p in self.points.get(h, []) + getattr(self, "menu_hops", {}).get(h, []) if bool(p.get("conditional")) == want]:
                for tgt in self.targets(p):
                    if tgt in parent or tgt not in on:
                        continue
                    if strict and not self.supplies(p, tgt):
                        continue
                    if not self.may(role, p, tgt):
                        continue
                    parent[tgt] = (pg, p, depth)
                    nxt.append(tgt)
            frontier = nxt
            if not frontier and deferred:
                # FN-3: a data-dependent branch page no click reached keeps its microflow entry (as before), marked
                for label, t, how, pg in deferred:
                    if pg not in parent:
                        parent[pg] = (None, {"entry": label, "target": t, **how, "branch": "data-dependent"}, 0)
                        frontier.append(pg)
                deferred = []
        return parent

    def chain(self, parent, pg):
        hops, seen = [], set()
        while pg is not None and pg not in seen:
            seen.add(pg)
            prev, how, _ = parent[pg]
            hops.append({"page": pg})
            if prev is None:
                hops.append(dict(how))
            else:
                hops.append(self.click_hop(how))
            pg = prev
        return list(reversed(hops))

    def click_hop(self, p):
        """A click hop of the path. E2E-10: "id" (the action it is, so gen_journeys can find its record) and how to
        click it inside a list ("row", "row_only", see click_plan)."""
        h = {"click": p["widget"], "on": p["host"], "action": p["action"], "id": p["id"]}
        if p.get("conditional"):
            h["shown_if"] = [c["text"] for c in p["conditional"]]   # PR-F38
        if "menu_item" in p:
            h["menu_item"], h["menu_doc"], h["caption"] = p["menu_item"], p["menu_doc"], p.get("caption") or ""
        if "item" in p:
            h["item"], h["items"] = p["item"], p["items"]   # PR-F26: which navigation list item, of how many
        h.update(self.click_plan(p))
        return h

    @classmethod
    def click_plan(cls, p):
        """The click plan of p (_click_plan) plus, PR-C1, "assigned_to_me": the list p sits in holds only the tasks
        assigned to the current user (XPath `Assignees = '[%CurrentUser%]'`), so a button shown only for an UNASSIGNED
        task is never behind a row of it. Purchase Request TaskInbox: "My Tasks" (listView5) vs "Open tasks" (listView4);
        gen_journeys takes the other list for such a button (unassigned_route)."""
        plan = cls._click_plan(p)
        lists = [c for c in p["containers"] if c["list"]]
        if lists and MINE_XPATH.search(lists[-1].get("xpath") or ""):
            plan = dict(plan, assigned_to_me=True)
        return plan

    @staticmethod
    def _click_plan(p):
        """How a journey clicks p when it sits in a list (E2E-10). The innermost list decides:
          the widget IS the list (a list view or data grid 2 / gallery row on-click): click its first row, row_only;
          a classic data grid, template grid or reference set selector (buttons on a control bar act on the selected
          row): select the first row, then click the button -- except a create, which needs no selection;
          a list view / data grid 2 / gallery whose rows hold the widget: click the first instance (the first row's);
          a data grid 2 / gallery header widget (PR-F35): select the first row first when the list selects, else {}.
        Each case needs a row in the list: the record's "needs" says so, and an empty list is a fixture gap."""
        lists = [c for c in p["containers"] if c["list"]]
        if not lists:
            return {}
        inner = lists[-1]
        if inner["name"] and inner["name"] == p["widget"]:
            trig = row_trigger(inner["node"]) if inner["node"].get("$Type") == "CustomWidgets$CustomWidget" else ""
            return {"row": inner["name"], "row_only": True, **({"trigger": trig} if trig else {})}
        if inner["type"] in ("DataGrid", "TemplateGrid", "ReferenceSetSelector") and p["action"] != "create":
            return {"row": inner["name"], "row_only": False}
        if inner["node"].get("$Type") == "CustomWidgets$CustomWidget":
            # PR-F35: a Data grid 2 / Gallery widget outside its per-row properties (the header, filtersPlaceholder)
            # renders once and acts on the selection: select the first row first when the list selects, else click
            # it as it is. Purchase Request pipe-30: "Select Vendor" sits in grid1's header; the "within" click ran
            # with nothing selected, Vendor_Select never opened and 5 journeys FAILed on the healthy OLD app.
            key, sel = list_area(inner["node"], p["node"])
            if key and key not in ROW_PROPS:
                return {"row": inner["name"], "row_only": False} if sel in ("Single", "Multi") else {}
        return {"within": inner["name"]}

    # ------------------------------------------------------------------ reach
    def expand(self, qn):
        """(docs, unknown) one hop from document qn, memoised. docs: the flows, pages, snippets, layouts, Java actions,
        workflows and constants it refers to (flow() for a flow: every sub-flow, page and Java action it reaches);
        unknown: the names it refers to that the model does not hold. Refers = a key the model uses for a document
        (REF_KEYS) or, for a constant, a qualified name in its strings that is a constant of the model."""
        if qn in self._expanded:
            return self._expanded[qn]
        docs, unknown = set(), set()
        d = self.m.docs.get(qn)
        if d is None:
            return docs, unknown
        if d.type in FLOWS:
            r = self.flow(qn)
            docs |= r["docs"] | r["shows"] | (set(r["java"]) | set(r["workflows"])) - {""}
            unknown |= r["unreadable"]
        if qn in self.on:                       # a page: the snippets and layouts it renders
            docs |= set(self.on[qn]) - {qn}
        for k in REF_KEYS:
            for v in all_values(d.data, k, []):
                docs.add(v)
        for c in self.m.refs(qn):               # constants (named in expressions, the only place they appear)
            cd = self.m.docs.get(c)
            if cd is not None and cd.type == "Constants$Constant":
                docs.add(c)
        docs.discard(qn)
        self._expanded[qn] = (docs, unknown)
        return docs, unknown

    def reach_of(self, p):
        """reach and reach_unknown of action p (see the header). The host is in reach; its other widgets are not: a
        click reaches its own target and what that target reaches. System.* names are listed, not expanded and not
        unknown: the runtime defines them, the model cannot show a change in them (L1 rules do)."""
        a, act = p["node"], p["action"]
        docs, unknown, seen, todo = {p["host"]}, set(), set(), []

        def note(q):      # a name the model does not hold: System is the runtime's, anything else is unknown
            if q.split(".", 1)[0] == "System":
                docs.add(q)
            else:
                unknown.add(q)

        def take(q):
            if not q or q in seen:
                return
            if q not in self.m.docs:
                note(q)
                return
            seen.add(q); docs.add(q); todo.append(q)

        if act in ("microflow", "nanoflow"):
            flow_qn = self._flow_of(p)
            if flow_qn:
                take(flow_qn)
            else:
                unknown.add("no flow selected on the action")
        elif act == "workflow-call":
            take(a.get("Workflow") or first(a, "Workflow"))
        elif act == "unknown":
            unknown.add(f"action type {p['raw_type']} is not known to action_inventory.py")
        else:
            for q in self.targets(p):
                take(q)
        while todo:
            q = todo.pop()
            ds, unk = self.expand(q)
            for x in ds:
                take(x)
            for u in unk:
                note(u)
        mods = {q.split(".", 1)[0] for q in docs if "." in q} | {u.split(".", 1)[0] for u in unknown if "." in u}
        return {"reach": sorted(docs | mods), "reach_unknown": sorted(unknown)}

    # ------------------------------------------------------------------ the inventory
    def build(self):
        self.collect()
        on, via = self.closures()
        self.on = on
        self.opened_by = collections.defaultdict(set)   # B5-1: page -> roles of the microflows that show it
        for d in self.m.all_docs:
            if d.type == "Microflows$Microflow" and not d.data.get("Excluded"):
                for pg in self.flow(d.qn)["shows"]:
                    self.opened_by[pg] |= self.roles.of_doc(d.qn)
        trees = {r: (self.bfs(on, True, r), self.bfs(on, False, r)) for r in self.roles.all}
        trees[None] = (self.bfs(on, True), self.bfs(on, False))
        reach = entry_reach(self.m)
        acts = []
        for host in sorted(self.points):
            for p in self.points[host]:
                r = self.record(p, via, trees, reach)
                r.update(self.reach_of(p))   # additive: reach, reach_unknown
                acts.append(r)
        if self.unreadable_modules:
            self.orphans(acts)
        return acts

    def orphans(self, acts):
        """E2E-8: with a protected add-on in the app, "no click path" is not proof of absence -- the add-on's own
        pages (T2: the Client Configuration overview) may open a readable page. Walk the readable callers back;
        a chain that ends at a document nothing readable references is reported as UNKNOWN, never as dead."""
        callers = self.m.callers_index()
        mods = ", ".join(sorted(self.unreadable_modules))
        for r in acts:
            if r["path"] is not None:
                continue
            seen, todo, roots = set(), list(r.get("via_pages") or [r["host"]]), set()
            while todo and len(seen) < 2000:
                q = todo.pop()
                if q in seen:
                    continue
                seen.add(q)
                ups = {c for c in callers.get(q, ()) if not self.m.excluded(c) and c != q}
                if not ups:
                    roots.add(q)
                todo.extend(ups)
            if roots:
                r["unknown"].append(f"no readable document references {', '.join(sorted(roots)[:3])}"
                                    f"{' ...' if len(roots) > 3 else ''}; unreadable module(s) {mods} may open it, "
                                    "so the click path is unknown, not absent")

    def record(self, p, via, trees, reach):
        r = {"id": p["id"], "host": p["host"], "host_type": self.m.docs[p["host"]].type.split("$")[-1],
             "widget": p["widget"], "widget_type": p["widget_type"], "caption": p["caption"], "action": p["action"],
             "target": None, "kind": None, "effects": [], "path": None, "path_text": None, "roles": [], "fields": [],
             "needs": [], "todo": [], "unknown": []}
        if p["conditional"]:
            r["conditional"] = True
            r["shown_if"] = [c["text"] for c in p["conditional"]]   # PR-F38: what must hold for it to be on screen
        a = p["node"]
        r["click"] = self.click_plan(p)          # E2E-10: how gen_journeys clicks it inside a list
        ci = (a.get("MicroflowSettings") or {}).get("ConfirmationInfo") if isinstance(a.get("MicroflowSettings"), dict) \
            else a.get("ConfirmationInfo")
        if isinstance(ci, dict):                 # E2E-10: a confirmation dialog opens before the flow runs
            r["confirm"] = {"proceed": text_of(ci.get("ProceedButtonCaption")) or None}
        if p["action"] == "unknown":
            r["kind"] = "unknown"
            r["todo"].append(f"unknown-action: {p['raw_type']}")
            r["unknown"].append(f"action type {p['raw_type']} is not known to action_inventory.py")
        flow_qn = self._flow_of(p) if p["action"] in ("microflow", "nanoflow") else ""
        copies = []
        if p["action"] in ("microflow", "nanoflow"):
            r["target"] = flow_qn or None
            if not flow_qn:
                r["kind"] = "unknown"; r["unknown"].append("no flow selected on the action")
            else:
                f = self.flow(flow_qn)
                copies = f["copies"]
                eff = set(f["effects"])
                sc = self.scope_of(f["deletes"], f["written"], f["docs"]) if "delete" in eff else None
                if sc:
                    r["scope"] = sc   # PR-P4
                if f["shows"]:
                    eff.add("open-page")
                r["effects"] = [k for k in KIND_ORDER if k in eff] + [f"unreadable:{u}" for u in sorted(f["unreadable"])]
                if f["outcomes"]:
                    r["outcomes"] = sorted(set(f["outcomes"]))
                if f["workflows"]:
                    r["workflows"] = sorted(f["workflows"])
                if f["java"]:
                    r["java"] = sorted(f["java"])
                known = [k for k in KIND_ORDER if k in eff]
                if flow_qn in f["unreadable"]:
                    r["kind"] = "unknown"
                    mod = flow_qn.split(".")[0]
                    r["unknown"].append(f"flow {flow_qn} is not in the model"
                                        + (" (System: built into the runtime)" if mod == "System"
                                           else f" (module {mod} unreadable: protected add-on)"
                                           if mod not in self.m.modules else ""))
                else:
                    r["kind"] = known[0] if known else ("unknown" if f["unreadable"] else "no-db-effect")
                    if f["unreadable"]:
                        r["unknown"].append("part of the flow is not in the model: " + ", ".join(sorted(f["unreadable"]))
                                            + " (kind is a lower bound)")
                if f["external"]:
                    r["todo"].append("external-call: " + ", ".join(sorted(f["external"])))
        elif p["action"] in ("open-page", "create"):
            tg = self.targets(p)
            r["target"] = tg[0] if tg else None
            r["kind"] = "create" if p["action"] == "create" else "open-page"
            if p["action"] == "create":
                r["entity"] = first(a.get("EntityRef"), "Entity") or (a.get("Entity") if isinstance(a.get("Entity"), str) else "") or None
            if r["target"] and not self.readable(r["target"]):
                r["unknown"].append(f"page {r['target']} is not in the model")
        elif p["action"] == "save":
            r["kind"] = "commit"
        elif p["action"] == "delete":
            r["kind"] = "delete"
            r["scope"] = self.scope_of([], set(), [], next((c.get("ds_entity") for c in reversed(p["containers"]) if c.get("ds_entity")), None)) or "row"
        elif p["action"] == "task-outcome":
            r["kind"] = "task-outcome"
            r["outcomes"] = [x for x in [a.get("OutcomeValue") or a.get("Outcome") or first(a, "Outcome")] if x]
            r["needs"].append("an open user task")
        elif p["action"] == "workflow-call":
            r["kind"] = "workflow-call"; r["target"] = a.get("Workflow") or first(a, "Workflow") or None
        elif p["action"] in ("open-task", "open-workflow"):
            r["kind"] = p["action"]
            r["targets"] = self.targets(p)
            r["needs"].append("an open user task" if p["action"] == "open-task" else "a workflow instance")
        # data context: fields of the enclosing data view, rows of an enclosing list
        dvs = [c for c in p["containers"] if not c["list"]]
        if dvs and p["action"] in ("save", "microflow", "nanoflow", "task-outcome", "workflow-call", "delete", "open-page"):
            r["fields"] = self.fields(dvs[-1]["node"])
            if copies:
                for fl in r["fields"]:   # PR-P5: a field on a non-persistable entity is stored where the flow copies it to
                    at = fl.get("attr_type") or {}
                    short = (fl.get("attribute") or "").rsplit(".", 1)[-1]
                    to = next((t for t, src in copies if src == short and self.attr.get(t, {}).get("persistable") is not False), None)
                    if at.get("persistable") is False and to:
                        fl["persisted_as"] = to
            rf = self.row_fields(dvs[-1]["node"])
            if rf:
                r["row_fields"] = rf
            r["context"] = dvs[-1]["entity"] or None
        for c in p["containers"]:
            if c["list"]:
                r["needs"].append(f"a row in {c['type']} {c['name']}" + (f" ({c['entity']})" if c["entity"] else ""))
        # E2E-8: an action fired by a combo box change has no click to drive it. PR-F25: a Combo box among the fields
        # is no longer a todo; gen_journeys fills it with journey-verbs.js "combo" (Purchase Request: 21 actions, among
        # them the Submit that starts the workflow every admin and approver page lists)
        if "combobox" in p["widget_type"].lower():
            r["todo"].append(f"combobox: the action fires on a change of combobox {p['widget']}")
        # roles first (page access, and the flow's access when the button runs one), then a path walkable by one of them
        pages = [p["host"]] if r["host_type"] == "Page" else sorted(via.get(p["host"], []))
        rs = set().union(*[self.page_roles(pg) for pg in pages]) if pages else set()
        if flow_qn and flow_qn in self.m.docs:
            rs &= self.roles.of_doc(flow_qn)
        r["roles"] = sorted(rs)
        best = None
        for strict in (True, False):
            cand = []
            for role in sorted(rs):
                parent = trees[role][0 if strict else 1]
                cand += [(parent[pg][2], role, pg) for pg in pages if pg in parent and role in self.page_roles(pg)]
            if cand:
                d, role, pg = min(cand)
                best = (role, pg, trees[role][0 if strict else 1], strict)
                r["path_roles"] = sorted({c[1] for c in cand})
                break
        if best:
            role, pg, parent, strict = best
            hops = self.chain(parent, pg)
            hops.append(self.click_hop(p))
            r["path"] = hops
            r["path_role"] = role
            r["path_text"] = f"as {role}: " + " -> ".join(h.get("entry") or h.get("page") or f"click {h['click']}"
                                                       for h in hops)
            if not strict:
                bad = [h["page"] for h in hops if "page" in h and self.m.docs.get(h["page"])
                       and lst(self.m.docs[h["page"]].data.get("Parameters"))]
                r["todo"].append("page-parameter: no click path supplies the parameter of " + ", ".join(bad))
        else:
            anyrole = any(pg in trees[None][1] for pg in pages)
            reached = any(pg in reach for pg in pages) or p["host"] in reach
            r["todo"].append("no-click-path" + (" (clicks reach the page, but not as a role allowed to run it)" if anyrole and rs
                                                else " (a non-click caller reaches it: entry_reach)" if reached
                                                else " (no entry point reaches it: entry_reach)"))
            r["via_pages"] = pages
        if not rs:
            r["todo"].append("no-role: no user role may open the page and run the action")
        return r


def summary(acts, inv):
    kinds = collections.Counter(a["kind"] for a in acts)
    todo = collections.Counter(t.split(":")[0].split(" (")[0] for a in acts for t in a["todo"])
    ntodo = sum(1 for a in acts if a["todo"])
    unk = sum(1 for a in acts if a["unknown"])
    s = {"actions": len(acts), "by_kind": dict(sorted(kinds.items())), "todo": ntodo, "todo_by_reason": dict(sorted(todo.items())),
         "unknown": unk, "not_actions": dict(sorted(inv.not_actions.items())), "excluded_docs": inv.excluded,
         "unreadable_modules": sorted(inv.unreadable_modules)}
    sc = collections.Counter(a["scope"] for a in acts if a.get("scope"))
    if sc:
        s["scopes"] = {k: sc[k] for k in SCOPES if sc[k]}   # PR-P4
    line = (f"actions {len(acts)} found · by kind " + (", ".join(f"{k} {n}" for k, n in sorted(kinds.items())) or "none")
            + f" · todo {ntodo} by reason " + (", ".join(f"{k} {n}" for k, n in sorted(todo.items())) or "none")
            + f" · unknown {unk} · not actions {sum(inv.not_actions.values())}"
            + (" (" + ", ".join(f"{k} {n}" for k, n in sorted(inv.not_actions.items())) + ")" if inv.not_actions else "")
            + f" · excluded docs {inv.excluded}")
    return s, line


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("project", help=".mpr file or the folder holding exactly one")
    ap.add_argument("--out", help="write actions.json here")
    a = ap.parse_args()
    if not os.path.exists(a.project):
        print(f"action_inventory: {a.project}: not found", file=sys.stderr)
        return 1
    try:
        m = Model.load(a.project)
    except Exception as e:  # noqa: BLE001  an unreadable model is an error, never an empty inventory
        print(f"action_inventory: cannot read {a.project}: {e}", file=sys.stderr)
        return 1
    if not m.docs:
        print(f"action_inventory: {a.project}: no documents read (not a Mendix project?)", file=sys.stderr)
        return 1
    inv = Inventory(m)
    acts = inv.build()
    s, line = summary(acts, inv)
    for x in acts:
        flag = ("TODO " + "; ".join(x["todo"])) if x["todo"] else ""
        unk = ("UNKNOWN " + "; ".join(x["unknown"])) if x["unknown"] else ""
        print(f"{x['id']} [{x['widget_type']}] {x['action']} -> {x['kind']}"
              f"{' ' + x['target'] if x['target'] else ''} | roles {','.join(x['roles']) or '-'}"
              f" | {x['path_text'] or 'no path'}{' | ' + flag if flag else ''}{' | ' + unk if unk else ''}")
    if s["unreadable_modules"]:
        print("unreadable modules (referenced, not in the model): " + ", ".join(s["unreadable_modules"]))
    print(line)
    if a.out:
        Path(a.out).write_text(json.dumps({"tool": "action_inventory.py", "model": os.path.abspath(a.project),
                                           "summary": s, "summary_line": line, "actions": acts}, indent=1, default=str))
        print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
