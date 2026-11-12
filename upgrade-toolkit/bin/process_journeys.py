#!/usr/bin/env python3
"""Compile CONFIRMED user processes (processes.md) into journeys for run_journeys.py (E2E-16).

    process_journeys.py processes.md --actions actions.json --out-dir GEN_DIR

E2E-16: one generated journey per action (E2E-10) proves every button works, not that a user can still do their job.
A process is what a key user does end to end ("raise a purchase request, the manager approves it"): named in the users'
words, drafted by bin/draft_processes.py from the model, the user manual and a key-user interview, and CONFIRMED by a
human (status: confirmed). Only confirmed processes are compiled; a draft is listed, never walked.

processes.md (templates/processes.example.md), one block per process:

    ## P01: Share feedback
    status: confirmed                      draft | confirmed | dropped. Only a human writes confirmed.
    roles: User
    source: interview: notes.md §Top 5 daily tasks
    steps:
    1. [User] Click "Feedback"  => Atlas_Core.FeedbackWidget.feedback1
    2. [User] Fill "Subject" with "Printer jam ${RUN_ID}"
    3. [User] Click "Take Screenshot"
    expect: FeedbackModule.Feedback where Subject = "Printer jam ${RUN_ID}"

Steps, in the users' words, each resolved to a concrete page and widget through actions.json (action_inventory.py on
the OLD model):
  Fill "<attribute or widget>" with "<value>"     typed into the form of the next action (its "fields")
                                                  or of a list in that form ("row_fields", PR-F43): every shown row
  Select "<value>" in "<attribute or widget>"     a drop-down / reference selector / combo box of the next action
  Select the first in "<attribute or widget>"     a combo box: its first option, whatever the fixture holds
  Open "<menu item>" / Go to "<menu item>"        the navigation menu, when a recorded path enters by that caption
  Start on the home page / Sign in                no click: where every leg starts
  Confirm                                         the confirmation dialog of the step before
  anything else                                   a click: "=> <action id>" pins it; otherwise the quoted text (or the
                                                  words) must match ONE action the role may run: its caption, widget
                                                  name, or the page it opens. Several on the current page or none:
                                                  the process is INVALID with the candidates, never a guess.
An action on the page the previous step left the user on is clicked in place; any other action is reached by walking its
recorded click path (as a role that path is valid for). An action whose inventory todo is a combobox trigger, an
external call, no role or an unknown action type makes the process INVALID with that reason (the same todo a generated
journey is skipped for); "no click path" only blocks an action that is not on the current page.

expect: <Module.Entity> where <Attr> = "<value>" [and ...]   the outcome: the data rung, COUNT(*) = 1 through the
        app's Postgres (run_journeys.py --psql, E2E-9). A value must carry ${RUN_ID} and be typed by a step, so a row
        an earlier run left cannot pass it. expect text: "<text>" adds a textPresent on the last step.

park: <n> after leg <k>[, ...]   PR-F33: a fixture, not a check. Before the second-pass journeys (run_journeys.py
        "~data" waves) the runner walks legs 1..k of this process n more times, each with its own ${RUN_ID}, so n
        workflow instances wait at the step after leg k for the roles that act there; then it assigns every waiting
        user task with exactly one target user to that user, except the newest M of each user (run_journeys.py
        --park-unassigned, default 1: "Assign to me" renders only for a task nobody holds, PR-P1). Purchase Request pipe-28: 44 of 97 baseline defects were
        task pages nobody could open, because no task waited for the role (one per Approve / Reject / Unassign
        journey is consumed). n is 1..20; k must be a leg of the process. k may be the last leg (PR-F34): the
        workflow then waits at a step the process does not model, which is exactly what the later roles' journeys need.

A step that clicks a task outcome (Received, Approve, Complete: the inventory's kind "task-outcome") also asserts that no
dialog is open after the click ("noDialog", PR-P2): the old app answers "Received" before the product line is completed
with a Warning box ("Please complete the tasks first than click on Received"), and the `.mx-page` guard passed it.

Roles: a step's [Role] is the user doing it; a change of role starts a new leg, i.e. a journey proc-<id>-<nn> in that
role's folder (the runner logs in once per role folder). run_journeys.py runs role folders in plan.json "role_order",
so the requester's leg runs before the approver's. A role that acts again after another one (A, B, A), or an order
that contradicts another process, cannot be honoured by one pass over the role folders: that process is INVALID.

Never dropped: every confirmed process is either compiled (legs in plan.json "processes.legs") or INVALID with its
reason, written to plan.json "skipped" as process:<id>, which run_journeys.py reports as INVALID. Re-running replaces
the earlier proc-* journeys and process:* plan rows; everything else in GEN_DIR (gen_journeys.py output) is kept.

PR-B1 (owner-approved): an action a compiled leg clicks ("covers") is walked in its process context, so the
generated one-click journey act-<id> for it is superseded: its file is renamed to act-<id>.journey.json.superseded
(the runner ignores it), its plan row moves to plan.json "covered" (closed_by the leg), and the action's coverage unit
is the leg alone. The unit still FAILs when the leg fails; the journey-set hash changes, so the baseline is re-walked.
Purchase Request: Task_POCreator.10/5/9 passed in proc-p02-03 but their one-click journey opened the first task in the
wrong state, and a unit needs EVERY linked journey to pass. Precedent: the create-save override of gen_journeys.py
(E2E-10). A process that is INVALID supersedes nothing; a rerun restores what the last run superseded before it decides.

Exit: 0 every confirmed process compiled; 3 some INVALID or none confirmed (nothing compiled is not a pass);
2 usage / unreadable input.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_journeys import ERROR_TEXT, ActionGen, act_id, assign_to_me_dead, click_acts, click_target, role_users, task_list_hosts, unassigned_only  # noqa: E402

STATUSES = ("draft", "confirmed", "dropped")
BLOCKING = ("combobox", "external-call", "no-role", "unknown-action", "page-parameter")
HEAD = re.compile(r"^##\s+(?P<id>[A-Za-z][\w-]*)\s*[:.-]\s*(?P<name>.+?)\s*$")
STEP = re.compile(r"^\s*(?P<n>\d+)[.)]\s+(?:\[(?P<role>[^\]]+)\]\s*)?(?P<text>.*?)(?:\s*=>\s*(?P<pin>\S+))?\s*$")
KEY = re.compile(r"^(?P<k>status|roles|source|priority|expect text|expect|notes|park|steps)\s*:\s*(?P<v>.*)$", re.I)
Q = r"[\"“”']"


# ------------------------------------------------------------------------------------------------ processes.md
def parse_processes(text):
    """processes.md -> [process dict]. Keys: id, name, status, roles, source, priority, steps[{n, role, text, pin,
    extra}], expect, expect_text, notes, line, raw (the block's lines, so draft_processes.py keeps it byte for byte)."""
    procs, cur, in_steps = [], None, False
    for i, line in enumerate(text.splitlines(), 1):
        m = HEAD.match(line)
        if m:
            cur = {"id": m["id"], "name": m["name"], "status": None, "roles": [], "source": "", "priority": None,
                   "steps": [], "expect": None, "expect_text": None, "notes": "", "park": None, "line": i, "raw": [line], "bad": []}
            procs.append(cur)
            in_steps = False
            continue
        if cur is None:
            continue
        if line.startswith("# ") or line.startswith("---"):
            cur, in_steps = None, False
            continue
        cur["raw"].append(line)
        k = KEY.match(line.strip())
        if k and not STEP.match(line):
            key, v = k["k"].lower(), k["v"].strip()
            in_steps = key == "steps"
            if key == "status":
                cur["status"] = v.split()[0].lower() if v else ""
            elif key == "roles":
                cur["roles"] = [r.strip() for r in re.split(r"[,;]", v) if r.strip()]
            elif key == "expect":
                cur["expect"] = v
            elif key == "expect text":
                cur["expect_text"] = v
            elif key == "park":
                cur["park"] = v
            elif key in ("source", "priority", "notes"):
                cur[key] = v
            continue
        s = STEP.match(line)
        if in_steps and s:
            cur["steps"].append({"n": int(s["n"]), "role": (s["role"] or "").strip() or None, "text": s["text"].strip(),
                                 "pin": s["pin"], "extra": []})
        elif in_steps and line.strip() and cur["steps"]:
            cur["steps"][-1]["extra"].append(line.strip())
    return procs


def quoted(text):
    return re.findall(Q + r"(.+?)" + Q, text)


def words(s):
    """camelCase / Under_score / dotted name -> lower-case words."""
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", s or "")
    return re.sub(r"[^A-Za-z0-9]+", " ", s).strip().lower()


def has_phrase(text, phrase):
    return bool(phrase) and re.search(r"(?<![a-z0-9])" + re.escape(phrase) + r"(?![a-z0-9])", text) is not None


def parse_expect(v):
    """'Mod.Entity where A = "x" and B = "y"' -> (entity, [(attr, value)]) or (None, why)."""
    m = re.match(r"^(?P<e>[A-Za-z_]\w*\.[A-Za-z_]\w*)\s+where\s+(?P<c>.+)$", v.strip(), re.I)
    if not m:
        return None, f"expect {v!r} is not '<Module.Entity> where <Attr> = \"<value>\"'"
    conds = []
    for part in re.split(r"\s+and\s+", m["c"], flags=re.I):
        c = re.match(r"^([A-Za-z_]\w*)\s*=\s*" + Q + r"(.*)" + Q + r"$", part.strip())
        if not c:
            return None, f"expect condition {part!r} is not '<Attr> = \"<value>\"'"
        conds.append((c[1], c[2]))
    return m["e"], conds


# ------------------------------------------------------------------------------------------------ resolving
class Invalid(Exception):
    pass


class Everyone:
    def __contains__(self, role):
        return True


class Compiler:
    def __init__(self, doc, model=None, users=None):
        self.doc = doc
        self.users = users   # QW-2: users.json, for the "Assign to me" guard; None = no guard
        self.task_hosts = task_list_hosts(doc)   # PRF-2: the guard applies to a participant's task list only
        self.acts = doc.get("actions", [])
        self.by_id = {x["id"]: x for x in self.acts}
        # role users are run_journeys' business, not the compiler's. model: the OLD .mpr, for tab steps (PR-F30)
        self.gen = ActionGen(doc, Everyone(), False, model)
        self.after = {}   # action id -> the page a recorded path shows after that click
        self.menus = {}   # menu caption (lower) -> entry hop
        for x in self.acts:
            path = x.get("path") or []
            for i, h in enumerate(path):
                if h.get("click") and h.get("id") and i + 1 < len(path) and path[i + 1].get("page"):
                    self.after.setdefault(h["id"], path[i + 1]["page"])
            if path and path[0].get("via") == "menu" and path[0].get("menu"):
                for c in (path[0]["menu"][-1], " > ".join(path[0]["menu"])):
                    self.menus.setdefault(c.lower(), path[0])

    @staticmethod
    def page_of(x):
        pages = [h["page"] for h in (x.get("path") or []) if h.get("page")]
        if pages:
            return pages[-1]
        return x["host"] if x.get("host_type") == "Page" else None

    def labels(self, x):
        """(tier, label): 1 caption or widget name, 2 the page an open-page / create action opens."""
        out = []
        if x.get("caption"):
            out.append((1, x["caption"].strip().lower()))
        out.append((1, x["widget"].lower()))
        if x["action"] in ("open-page", "create") and x.get("target"):
            out.append((2, words(x["target"].rsplit(".", 1)[1])))
        elif x.get("target") and "open-page" in (x.get("effects") or []):
            out.append((2, words(re.sub(r"^(ACT|Nav|NAV|SUB|MF|NF|DS)_", "", x["target"].rsplit(".", 1)[1]))
                        .replace("open ", "", 1)))
        if x["id"] in self.after:
            out.append((2, words(self.after[x["id"]].rsplit(".", 1)[1])))
        return out

    def may_run(self, x, role):
        return role in (x.get("roles") or []) or role == x.get("path_role") or role in (x.get("path_roles") or [])

    def resolve(self, step, role, page):
        """The action a click step means, or Invalid with the candidates."""
        if step["pin"]:
            if step["pin"] == "?":
                raise Invalid("not pinned (=> ?): pick one of the candidates and write its action id")
            x = self.by_id.get(step["pin"])
            if not x:
                raise Invalid(f"=> {step['pin']} is not an action in actions.json")
            return x
        t = step["text"].lower()
        qs = [q.strip().lower() for q in quoted(step["text"])]
        best = None
        for tier in (1, 2):
            c = []
            for x in self.acts:
                for lt, lab in self.labels(x):
                    if lt != tier or not lab:
                        continue
                    if (qs and lab in qs) or (not qs and len(lab) > 2 and has_phrase(t, lab)):
                        c.append(x)
                        break
            if c:
                best = c
                break
        if not best:
            raise Invalid("no action matches it (caption, widget name or the page it opens): pin it with => <action id>"
                          " or reword it")
        mine = [x for x in best if self.may_run(x, role)]
        if not mine:
            raise Invalid(f"role {role} may run none of the matching actions: {', '.join(x['id'] for x in best[:5])}")
        here = [x for x in mine if page and self.page_of(x) == page]
        pick = here or mine
        if len(pick) > 1:
            raise Invalid(f"{len(pick)} actions match" + (" on the current page" if here else "") + ": "
                          + ", ".join(x["id"] for x in pick[:6]) + ("" if len(pick) <= 6 else ", ...")
                          + " (pin one with => <action id>)")
        return pick[0]

    def field_acts(self, x, fills, reached=False):
        """Pending Fill / Select steps -> engine actions on the fields of action x. reached: an earlier step of the
        process opened a task (PRF-1, owner decision D5): a field that is only "conditionally visible" (Purchase Request:
        the comment box under State = InProgress) may then be filled, because opening the task is what puts it there.
        A field on a tab page that is not shown first, or any hidden field with no such earlier step, is still refused."""
        out = []
        fields = (x.get("fields") or []) + (x.get("row_fields") or [])   # PR-F43: a nested list's inputs, every row
        for f in fills:
            name = f["field"].strip().lower()
            hit = [g for g in fields if name in {(g.get("widget") or "").lower(), (g.get("attribute") or "").lower(),
                                                (g.get("attribute") or "").rsplit(".", 1)[-1].lower(),
                                                words((g.get("attribute") or "").rsplit(".", 1)[-1])}]
            if len(hit) != 1:
                have = ", ".join(sorted({(g.get("attribute") or g.get("widget") or "?").rsplit(".", 1)[-1] for g in fields})) or "none"
                raise Invalid(f"step {f['n']}: {'no' if not hit else len(hit)} field(s) of the form of {x['id']} match "
                              f"{f['field']!r} (fields: {have})")
            g = hit[0]
            if g.get("hidden"):
                cond = str(g["hidden"]).startswith("conditionally visible")
                if not (cond and reached):
                    raise Invalid(f"step {f['n']}: field {g['widget']} is {g['hidden']}"
                                  + (": no earlier step of this process opens the task that shows it" if cond else ""))
            if g.get("editable") == "Never":
                raise Invalid(f"step {f['n']}: field {g['widget']} is read-only (Editable: Never)")
            inp = g.get("input")
            if f["verb"] == "fill" and inp in ("text", "date"):
                out.append({"do": "fill", "widget": g["widget"], "value": f["value"], **({"rows": True} if g.get("list") else {})})
            elif f["verb"] == "fill" and inp == "file":   # PR-F44: journey-verbs.js upload, a generated file of that name
                out.append({"do": "upload", "widget": g["widget"], "file": f["value"]})
            elif f["value"] is None and inp != "combobox":
                raise Invalid(f"step {f['n']}: \"the first\" works on a combo box only; field {g['widget']} is input {inp}")
            elif inp == "select" or (inp == "reference" and (g.get("render") or "DropDown") == "DropDown"):
                out.append({"do": "select", "widget": g["widget"], "match": f["value"]})
            elif inp == "combobox" and f["verb"] == "select":   # PR-F25: journey-verbs.js "combo"
                out.append({"do": "combo", "widget": g["widget"], **({"match": f["value"]} if f["value"] is not None else {"first": True})})
            else:
                raise Invalid(f"step {f['n']}: field {g['widget']} is input {inp}"
                              + (f" rendered as {g.get('render')}" if g.get("render") else "") + f": no {f['verb']} verb for it")
        return out

    # -------------------------------------------------------------------------------------------- one process
    def compile(self, p):
        """-> (legs, typed values) or raise Invalid. legs: [{role, ops, covers}]."""
        if not p["steps"]:
            raise Invalid("no steps")
        legs, fills, page, stack, typed = [], [], None, [], []
        dead = []   # QW-2: every pinned "Assign to me" the role can never see, named at once
        for st in p["steps"]:
            r = st["role"] or (p["roles"][0] if len(p["roles"]) == 1 else None)
            x = self.by_id.get(st["pin"])
            if x and assign_to_me_dead(x, r, self.users, self.task_hosts):
                dead.append(f"step {st['n']} '{x.get('caption') or st['text']}' [{r}]")
        if dead:
            raise Invalid(f"{'; '.join(dead)}: shown only if Assignees = empty; the role has 1 user, its tasks arrive "
                          f"assigned: remove the step or add a 2nd user")
        reached = False  # PRF-1 (D5): an earlier step of this process opened a task, the state a conditional field needs
        opened = None  # PR-F31: the page a written open-task click (no target page) left, for the step after it

        def leg(role, fresh=False):
            if fresh or not legs or legs[-1]["role"] != role:
                legs.append({"role": role, "ops": [], "covers": []})
            return legs[-1]

        for st in p["steps"]:
            n, text = st["n"], st["text"]
            role = st["role"] or (p["roles"][0] if len(p["roles"]) == 1 else None)
            label = f'step {n} "{text}"'
            if not role:
                raise Invalid(f"{label}: names no [Role] and the process has {len(p['roles'])} roles")
            if p["roles"] and role not in p["roles"]:
                raise Invalid(f"{label}: role {role} is not in roles: {', '.join(p['roles'])}")
            if re.search(r"(^|\s)\?(\s|$)|" + Q + r"\?" + Q, text):
                raise Invalid(f"{label}: has a ? placeholder")
            if legs and legs[-1]["role"] != role:
                if fills:
                    raise Invalid(f"step {fills[0]['n']}: fill with no action after it before the role changes")
                page, stack, opened = None, [], None
            cur = leg(role)
            low = text.lower()
            try:
                m = re.match(r"^(fill|enter|type)\s+(?:in\s+)?" + Q + r"(.+?)" + Q + r"\s+(?:with|as|to)\s+" + Q + r"(.*)" + Q + r"\s*\.?$", text, re.I)
                if m:
                    fills.append({"n": n, "text": text, "verb": "fill", "field": m[2], "value": m[3]})
                    typed.append(m[3])
                    continue
                # PR-F25: "Select the first in "Product"": a combo box option the fixture holds, whatever its name
                m = re.match(r"^(select|choose|pick)\s+the\s+first(?:\s+option)?\s+(?:in|for|from)\s+" + Q + r"(.+?)" + Q + r"\s*\.?$", text, re.I)
                if m:
                    fills.append({"n": n, "text": text, "verb": "select", "field": m[2], "value": None})
                    continue
                m = re.match(r"^(select|choose|pick)\s+" + Q + r"(.+?)" + Q + r"\s+(?:in|for|from|as)\s+" + Q + r"(.+?)" + Q + r"\s*\.?$", text, re.I)
                if m:
                    fills.append({"n": n, "text": text, "verb": "select", "field": m[3], "value": m[2]})
                    typed.append(m[2])
                    continue
                if re.match(r"^(start on the home ?page|start at home|sign in|log ?in)\b", low):
                    if cur["ops"]:
                        raise Invalid("the role is already signed in and away from its home page: start a new process")
                    continue
                if re.match(r"^confirm\b", low):
                    if not cur["ops"]:
                        raise Invalid("Confirm with no step before it")
                    cur["ops"][-1]["actions"].append({"do": "confirm"})
                    continue
                m = re.match(r"^(open|go to|navigate to)\s+(.+?)(\s+in the (main )?menu)?\s*\.?$", text, re.I)
                if m and not st["pin"]:
                    q = quoted(m[2])
                    cap = (q[0] if q else m[2]).strip().lower()
                    e = self.menus.get(cap)
                    if e:
                        if fills:
                            raise Invalid(f"step {fills[0]['n']}: fill with no action after it")
                        mm = e["menu"]
                        cur["ops"].append({"name": f"{n}. {text}", "actions": [{"do": "nav", "group": mm[0] if len(mm) > 1 else None,
                                                                                    "item": mm[-1], "settleMs": 3000}], "need": None})
                        page, stack, opened = e.get("target"), [], None
                        continue
                x = self.resolve(st, role, page)
                bad = [t for t in x.get("todo") or [] if t.split(":")[0].split(" (")[0] in BLOCKING]
                if bad:
                    raise Invalid(f"{x['id']}: action todo: {'; '.join(bad)}")
                if not self.may_run(x, role):
                    raise Invalid(f"role {role} may not run {x['id']} (roles: {', '.join(x.get('roles') or []) or 'none'})")
                if assign_to_me_dead(x, role, self.users, self.task_hosts):
                    raise Invalid(f"'{x.get('caption') or text}': shown only if Assignees = empty; role {role} has 1 user, its tasks "
                                  f"arrive assigned: remove the step or add a 2nd user")
                fa = self.field_acts(x, fills, reached) if fills else []
                name = "; ".join([f"{f['n']}. {f['text']}" for f in fills] + [f"{n}. {text}"])
                fills = []
                in_place = page is not None and self.page_of(x) == page
                if not in_place and opened:
                    task = self.task_page(x, opened)
                    if task:
                        page, in_place = task, True
                after_open, opened = opened, None
                if not in_place and self.page_of(x) in stack:
                    # PR-F25: back on a page the user came from: a popup's microflow closed it (Purchase Request: Save
                    # on ProductLine_NewEdit, then Next on the wizard). Walking from home would start a new request;
                    # the step's guard (the widget it clicks) fails loudly if the popup did not close
                    while stack and stack[-1] != self.page_of(x):
                        stack.pop()
                    page, in_place = stack.pop(), True
                if not in_place and page is None and cur["ops"] and st["pin"] and self.page_of(x) and not after_open:
                    # PR-B7 (Purchase Request run 3, P05): the step before opened a page the inventory cannot name (a
                    # microflow shows it: New Attachment -> Attachment_NewEdit), so the pinned "Add" of that popup was
                    # walked from the role home through the Task page, splitting the wizard into five legs. A pinned
                    # action of a page, right after a click that left the page unknown, is the author's word that
                    # the page is on screen; its guard (the widget it clicks) fails loudly when it is not. Not after an
                    # open-task click: that opens a task page from another page, and PR-F31 walks from home then.
                    page, in_place = self.page_of(x), True
                if in_place:
                    hop = next((h for h in reversed(x.get("path") or []) if h.get("id") == x["id"]),
                               dict(x.get("click") or {}, click=x["widget"]))
                    cur["ops"].append(self.tabbed(hop, page, {"name": name, "actions": fa + self.clicks(x, hop),
                                       "need": f".mx-name-{fa[0]['widget']}" if fa else click_target(hop)}))
                else:
                    where = (f" ({page})" if page else " (the leg starts at the role home)" if not cur["ops"]
                             else " (the step before left it unknown)")
                    if not x.get("path"):
                        raise Invalid(f"{x['id']} is not on the current page{where} and has no recorded click path")
                    if role != x.get("path_role") and role not in (x.get("path_roles") or []):
                        raise Invalid(f"{x['id']} is not on the current page{where} and its click path is recorded for "
                                      f"{', '.join(x.get('path_roles') or [x.get('path_role') or '?'])}, not {role}")
                    why = self.gen.why_not(dict(x, todo=[t for t in x.get("todo") or [] if not t.startswith("no-click-path")]))
                    if why:
                        raise Invalid(f"{x['id']} is not on the current page{where} and cannot be walked to: {why[1]}")
                    e = x["path"][0]
                    if e.get("via") == "home" and cur["ops"]:
                        cur = leg(role, fresh=True)
                    clicks = [h for h in x["path"] if "click" in h]
                    pages = [h["page"] for h in x["path"] if "page" in h]
                    if e.get("via") == "menu":
                        mm = e["menu"]
                        cur["ops"].append({"name": f"{n}. open {' > '.join(mm)}", "actions": [{"do": "nav", "group": mm[0] if len(mm) > 1 else None,
                                                                                               "item": mm[-1], "settleMs": 3000}], "need": None})
                    for i, h in enumerate(clicks[:-1]):
                        ref = self.by_id.get(h.get("id") or "")
                        cur["ops"].append(self.tabbed(h, pages[i] if i < len(pages) else h.get("on"), {
                            "name": f"{n}. open {pages[i + 1] if i + 1 < len(pages) else '?'} ({h['click']})",
                            "actions": self.clicks(ref, h) if ref else own(click_acts(h), h), "need": click_target(h)}))
                        if ref:
                            cur["covers"].append(ref["id"])
                    last = len(clicks) - 1
                    cur["ops"].append(self.tabbed(clicks[-1], pages[last] if last < len(pages) else clicks[-1].get("on"), {
                        "name": name, "actions": fa + self.clicks(x, clicks[-1]),
                        "need": f".mx-name-{fa[0]['widget']}" if fa else click_target(clicks[-1])}))
                    page, stack = (pages[-1] if pages else None), pages[:-1]
                cur["covers"].append(x["id"])
                if x.get("action") == "open-task":
                    reached = True
                if x.get("kind") == "task-outcome" and cur["ops"]:
                    cur["ops"][-1]["outcome"] = x["id"]   # PR-P2: the step must leave no dialog open
                # where the click leaves the user
                prev = page
                if x["action"] in ("open-page", "create") and x.get("target"):
                    page = x["target"]
                elif x["id"] in self.after:
                    page = self.after[x["id"]]
                elif x["action"] in ("save", "cancel", "close"):
                    page = stack.pop() if stack else None
                elif x["action"] == "open-task":
                    page, opened = None, prev
                elif "open-page" in (x.get("effects") or []) or x.get("kind") == "unknown" or any(
                        str(e).startswith("unreadable") for e in x.get("effects") or []):
                    page = None
                if page != prev and x["action"] not in ("save", "cancel", "close") and prev:
                    stack.append(prev)
            except Invalid as e:
                raise Invalid(f"{label}: {e}") from None
        if fills:
            raise Invalid(f"step {fills[0]['n']}: fill with no action after it")
        return legs, typed

    def task_page(self, x, opened):
        """PR-F31: the task page x sits on when x's recorded path opens it with an open-task click on `opened` -- the
        page a written open-task click just left -- else None. The task page an open-task button opens is the row's
        user task, known only at run time, so the button carries no target page and the step after it was walked from
        home in a fresh leg: Purchase Request P02, "View" on the Task Inbox's "Open tasks" then "Assign to me" on the
        task page, reopened the task from "My Tasks", where nobody had put it."""
        seq = x.get("path") or []
        k = next((i for i, h in enumerate(seq) if h.get("action") == "open-task" and h.get("on") == opened), None)
        nxt = next((h["page"] for h in seq[k + 1:] if "page" in h), None) if k is not None else None
        return nxt if nxt and nxt == self.page_of(x) else None

    def tabbed(self, hop, page, op):
        """PR-F30: op with a click on every tab page that hides hop's widget on page first (gen_journeys tab_acts,
        impact_map.tab_path). Purchase Request pipe-22: the Approver's "Assign to me" sits on the Task Inbox's "Open
        tasks" tab, the first tab ("My Tasks") was empty, and the leg FAILed at the role home on the healthy OLD app.
        The step before then waits for the tab, not for the hidden widget."""
        tacts, _ = self.gen.tab_acts(hop, page)
        if not tacts:
            return op
        # PR-B8: a closed Pop-up menu has no element named after it (journey-verbs.js "menu", PR-F40), so the step BEFORE a
        # menu item cannot wait for it: Purchase Request P10, "Delete comment" then "Pause Workflow" FAILed "pop_upMenu5
        # never appeared" on the healthy OLD app. need None = the step's own .mx-page guard.
        need = None if tacts[0].get("do") == "menu" else f".mx-name-{tacts[0]['widget']}"
        return dict(op, actions=tacts + op["actions"], need=need)

    def clicks(self, x, hop):
        acts = own(click_acts(hop), x, hop)
        if x and x.get("confirm"):
            acts.append({"do": "confirm", **({"label": x["confirm"]["proceed"]} if x["confirm"].get("proceed") else {})})
        return acts


def own(acts, *hops):
    """PR-F42: an open-task click takes the list item that names this walk's ${RUN_ID} (journey-verbs.js topmost
    `near`), not the first: the oldest task in Purchase Request's inbox was an earlier walk's, stuck later in P02, and
    every park walk of leg 3 FAILed on its page (pipe-33). An item that names no ${RUN_ID} keeps the first."""
    if any((h or {}).get("action") == "open-task" for h in hops):
        for a in acts:
            if a["do"] == "click":
                a["near"] = "${RUN_ID}"
    return acts


PARK = re.compile(r"^(\d+)\s+after\s+leg\s+(\d+)$", re.I)


def parse_park(v, legs):
    """PR-F33: "8 after leg 1, 6 after leg 2" -> [{"n": 8, "legs": [leg ids 1..k]}]; Invalid on anything else."""
    out = []
    for part in [x.strip() for x in v.split(",")]:
        m = PARK.match(part)
        if not m:
            raise Invalid(f"park {part!r}: write it as '<n> after leg <k>'")
        n, k = int(m[1]), int(m[2])
        if not 1 <= n <= 20:
            raise Invalid(f"park {part!r}: n must be 1..20")
        if not 1 <= k <= len(legs):
            raise Invalid(f"park {part!r}: leg {k} is not a leg of this process ({len(legs)} legs)")
        out.append({"n": n, "after": k, "legs": legs[:k]})
    return out


def leg_journey(p, li, lg, nlegs, outcome, text):
    ops = list(lg["ops"])
    if not ops:
        raise Invalid(f"leg {li} ({lg['role']}) has no step that acts")
    if ops[0]["need"]:
        ops.insert(0, {"name": "role home", "actions": [{"do": "wait", "ms": 500}], "need": None})
    steps = []
    for i, op in enumerate(ops):
        nxt = ops[i + 1]["need"] if i + 1 < len(ops) else None
        ui = {"ready": nxt or ".mx-page", "textAbsent": ERROR_TEXT}
        if op.get("outcome"):
            ui["noDialog"] = True   # PR-P2: a task outcome that answers with a message box did not complete the task
        if i + 1 == len(ops) and li == nlegs and text:
            ui["textPresent"] = [text]
        steps.append({"name": op["name"], "actions": op["actions"] or [{"do": "wait", "ms": 500}], "ui": ui})
    jid = f"proc-{re.sub(r'[^a-z0-9_-]', '-', p['id'].lower())}-{li:02d}"
    j = {"id": jid, "title": f"{p['id']} {p['name']} (leg {li}/{nlegs}, {lg['role']})", "persona": lg["role"],
         "requirement": [f"process:{p['id']}"], "_run": {"role": lg["role"]},
         "_why": [f"process {p['id']}: {p['name']}", f"source: {p['source'] or '?'}"],
         "process": p["id"], "leg": li, "legs": nlegs, "covers": sorted(set(lg["covers"])), "steps": steps}
    if li == nlegs and outcome:
        j["outcome"] = outcome
    if any(s["ui"]["ready"] == ".mx-page" for s in steps):
        j["_guard"] = "a step whose landing the inventory does not prove is guarded by .mx-page; the outcome is the strong check"
    if li > 1:
        j["_handoff"] = ("this leg starts from the role home after leg 1 ran as another role: an open-task click takes "
                         "the list item naming ${RUN_ID} (PR-F42); other list clicks take the first row, which may be "
                         "another record; the outcome (own ${RUN_ID} row) catches that")
    return j


def supersede_restore(jroot, plan):
    """PR-B1: undo the last run's supersessions (rename back, plan rows back), so a rerun decides from scratch."""
    for r in ((plan.get("processes") or {}).get("superseded") or []):
        f = jroot / r["file"]
        g = f.with_name(f.name + ".superseded")
        if g.is_file() and not f.exists():
            g.rename(f)
        if r.get("closes"):
            for e in plan.get("todo", []):
                if e.get("closed_by") == r["by"] and e.get("id") in r["closes"]:
                    e["closed_by"] = r["id"]
        if r.get("entry") and not any(e.get("id") == r["id"] for e in plan.get("journeys", [])):
            plan.setdefault("journeys", []).append(r["entry"])
    plan["covered"] = [e for e in plan.get("covered", []) if not e.get("superseded_by")]


def supersede(jroot, plan, written):
    """PR-B1: the generated act-<id> journey of every action a written leg covers is set aside. Returns the records."""
    recs, owner = [], {}
    for j in sorted(written, key=lambda j: j["id"]):
        for aid in j.get("covers") or []:
            owner.setdefault(aid, j)
    for aid, j in sorted(owner.items()):
        jid = act_id(aid)
        f = next(iter(sorted(jroot.glob(f"*/{jid}.journey.json"))), None)
        if f is None:
            continue
        entry = next((e for e in plan.get("journeys", []) if e.get("id") == jid), None)
        try:   # a todo row the act journey closed ("closes") is closed by the leg now, so it keeps its verdict
            closes = [c for c in json.load(open(f)).get("closes") or [] if isinstance(c, str)]
        except (OSError, ValueError):
            closes = []
        if closes:
            j["closes"] = list(dict.fromkeys(list(j.get("closes") or []) + closes))
            for e in plan.get("todo", []):
                if e.get("closed_by") == jid:
                    e["closed_by"] = j["id"]
        f.rename(f.with_name(f.name + ".superseded"))
        plan["journeys"] = [e for e in plan.get("journeys", []) if e.get("id") != jid]
        plan.setdefault("covered", []).append({"id": jid, "action": aid, "role": j["persona"], "closed_by": j["id"],
                                               "superseded_by": j["id"],
                                               "why": f"walked in process {j['process']} ({j['id']}): the process walk replaces the one-click journey (PR-B1)"})
        recs.append({"id": jid, "action": aid, "by": j["id"], "file": str(f.relative_to(jroot)), "entry": entry,
                     "closes": closes})
    return recs


def role_order(seqs):
    """Topological order of role edges (a before b), name tie-break; None on a cycle."""
    nodes = sorted({r for s in seqs for r in s})
    edges = {(a, b) for s in seqs for a, b in zip(s, s[1:])}
    order, left = [], set(nodes)
    while left:
        free = sorted(r for r in left if not any(b == r and a in left for a, b in edges))
        if not free:
            return None
        order.append(free[0])
        left.remove(free[0])
    return order


def process_line(c):
    return (f"processes {c['confirmed']} confirmed · {c['compiled']} compiled · {len(c['invalid'])} invalid · "
            f"{c['draft']} draft (not compiled)" + (f" · {c['dropped']} dropped" if c["dropped"] else ""))


def main():
    ap = argparse.ArgumentParser(description="E2E-16: confirmed processes -> journeys (legs per role)")
    ap.add_argument("processes")
    ap.add_argument("--actions", required=True, help="actions.json of the OLD model (bin/action_inventory.py --out)")
    ap.add_argument("--out-dir", required=True, help="the gen dir run_journeys.py runs (gen_journeys.py output is kept)")
    ap.add_argument("--users", help="users.json (run_journeys.py): a step whose button shows only for an unassigned task "
                    "(\"Assign to me\") is INVALID for a role with exactly one user, QW-2")
    ap.add_argument("--actions-model", help="the .mpr actions.json was read from, when its \"model\" path is not on "
                    "this machine (tab steps, PR-F30)")
    a = ap.parse_args()
    try:
        text = Path(a.processes).read_text(encoding="utf-8")
        doc = json.load(open(a.actions))
    except (OSError, ValueError) as e:
        print(f"cannot read input: {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(doc.get("actions"), list):
        print(f'{a.actions}: no "actions" list (not an action_inventory.py --out file)', file=sys.stderr)
        sys.exit(2)
    procs = parse_processes(text)
    model, apath = None, a.actions_model or doc.get("model")
    if apath and os.path.exists(apath):
        try:
            import mprmodel
            model = mprmodel.Model.load(apath)
        except Exception as e:
            print(f"note: actions model not loaded ({e})", file=sys.stderr)
    if model is None:   # PR-F30: say it, a step on a tab page not shown first FAILs on a healthy app
        print(f"note: actions model {apath or '(none named)'} not loaded: tab steps NOT added (a widget on a tab page "
              "not shown first gets none); pass --actions-model", file=sys.stderr)
    users = None
    if a.users:
        try:
            users = json.load(open(Path(a.users).expanduser()))
        except (OSError, ValueError) as e:
            print(f"cannot read --users: {e}", file=sys.stderr)
            sys.exit(2)
    comp = Compiler(doc, model, users)
    out = Path(a.out_dir)
    jroot = out / "journeys"
    for f in (jroot.glob("*/proc-*.journey.json") if jroot.is_dir() else []):
        f.unlink()
    plan_p = out / "plan.json"
    plan = json.load(open(plan_p)) if plan_p.is_file() else {"journeys": [], "skipped": [], "todo": []}
    supersede_restore(jroot, plan)
    plan["journeys"] = [e for e in plan.get("journeys", []) if not str(e.get("id", "")).startswith("proc-")]
    plan["skipped"] = [e for e in plan.get("skipped", []) if not str(e.get("id", "")).startswith("process:")]

    seen, invalid, legs_of, seqs, written, park_of = set(), [], {}, [], [], {}
    counts = {s: 0 for s in STATUSES}
    for p in procs:
        st = p["status"]
        if p["id"] in seen:
            invalid.append({"id": p["id"], "why": f"line {p['line']}: process id {p['id']} used twice"})
            continue
        seen.add(p["id"])
        if st not in STATUSES:
            invalid.append({"id": p["id"], "why": f"status {st or '(none)'} is not draft, confirmed or dropped"})
            continue
        counts[st] += 1
        if st != "confirmed":
            continue
        try:
            outcome, etext = None, None
            if not p["expect"] and not p["expect_text"]:
                raise Invalid("no expect: a process without an expected outcome proves nothing")
            if p["expect"]:
                if "?" in p["expect"].split("#")[0] and re.search(r"(^|[\s\"'])\?", p["expect"]):
                    try:  # name the first open step too, so one pass over the list shows everything left to pick
                        comp.compile(p)
                        raise Invalid("expect has a ? placeholder")
                    except Invalid as e:
                        raise Invalid("expect has a ? placeholder" + ("" if str(e).startswith("expect") else f"; {e}"))
                ent, conds = parse_expect(p["expect"])
                if ent is None:
                    raise Invalid(conds)
                if not any("${RUN_ID}" in v for _, v in conds):
                    raise Invalid("expect is not scoped to this run: put ${RUN_ID} in a typed value and in the expect, "
                                  "or a row an earlier run left passes it (E2E-9)")
                legs, typed = comp.compile(p)
                for at, v in conds:
                    if "${RUN_ID}" in v and v not in typed:
                        raise Invalid(f"expect {at} = {v!r}: no step types that value")
                where = " AND ".join(f"{at} = '{v.replace(chr(39), chr(39) * 2)}'" for at, v in conds)
                outcome = {"sql": f"SELECT COUNT(*) AS n FROM {ent} WHERE {where}", "expect": 1,
                           "label": f"process {p['id']} outcome: {p['expect']}"}
            else:
                legs, typed = comp.compile(p)
            if p["expect_text"]:
                q = quoted(p["expect_text"])
                etext = q[0] if q else p["expect_text"].strip()
                if etext == "?":
                    raise Invalid("expect text has a ? placeholder")
            seq = [lg["role"] for lg in legs]
            seq = [r for i, r in enumerate(seq) if i == 0 or seq[i - 1] != r]
            if len(seq) != len(set(seq)):
                raise Invalid(f"roles {' -> '.join(seq)}: a role acts again after another one; the runner runs each role "
                              "folder once, so split it into two processes")
            if len(seq) > 1 and role_order(seqs + [seq]) is None:
                raise Invalid(f"roles {' -> '.join(seq)} contradict the order another confirmed process needs")
            js = [leg_journey(p, i, lg, len(legs), outcome, etext) for i, lg in enumerate(legs, 1)]
        except Invalid as e:
            invalid.append({"id": p["id"], "why": str(e)})
            continue
        if p["park"]:
            try:
                park_of[p["id"]] = parse_park(p["park"], [j["id"] for j in js])
            except Invalid as e:
                invalid.append({"id": p["id"], "why": str(e)})
                continue
        if len(seq) > 1:
            seqs.append(seq)
        legs_of[p["id"]] = [j["id"] for j in js]
        written += js
    for j in written:
        d = jroot / j["persona"]
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{j['id']}.journey.json").write_text(json.dumps(j, indent=2) + "\n")
        plan["journeys"].append({"id": j["id"], "role": j["persona"], "why": j["_why"]})
    sup = supersede(jroot, plan, written)
    for j in written:
        if j.get("closes"):
            (jroot / j["persona"] / f"{j['id']}.journey.json").write_text(json.dumps(j, indent=2) + "\n")
    for e in invalid:
        plan["skipped"].append({"id": f"process:{e['id']}", "reasons": ["process"], "why": f"process INVALID: {e['why']}"})
    c = {"source": Path(a.processes).name, "confirmed": counts["confirmed"], "draft": counts["draft"],
         "dropped": counts["dropped"], "compiled": len(legs_of), "invalid": invalid, "legs": legs_of,
         "role_order": role_order(seqs) or [], "drafts": [p["id"] for p in procs if p["status"] == "draft"],
         "park": [dict(s, process=pid) for pid in legs_of for s in park_of.get(pid, [])], "superseded": sup}
    c["line"] = process_line(c)
    plan["processes"] = c
    if c["role_order"]:
        plan["role_order"] = c["role_order"]
    else:
        plan.pop("role_order", None)
    out.mkdir(parents=True, exist_ok=True)
    plan_p.write_text(json.dumps(plan, indent=2) + "\n")
    for p in procs:
        if p["id"] in legs_of:
            print(f"COMPILED {p['id']:10} {p['name'][:50]:50} legs {', '.join(legs_of[p['id']])}")
            for s in park_of.get(p["id"], []):
                print(f"PARK     {p['id']:10} {s['n']} after leg {s['after']} ({', '.join(s['legs'])})")
    for e in invalid:
        print(f"INVALID  {e['id']:10} {e['why']}")
    for p in procs:
        if p["status"] == "draft":
            print(f"DRAFT    {p['id']:10} {p['name'][:50]} (not compiled: a human sets status: confirmed)")
    for r in sup:
        print(f"SUPERSEDE {r['id']} by {r['by']} (the process walk replaces the one-click journey of {r['action']})")
    if c["role_order"]:
        print(f"role order: {' -> '.join(c['role_order'])}")
    print(c["line"])
    if not c["confirmed"]:
        print("no confirmed process: nothing compiled (only a human confirms a draft)")
    sys.exit(3 if invalid or not c["confirmed"] else 0)


if __name__ == "__main__":
    main()
