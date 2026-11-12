#!/usr/bin/env python3
"""Draft user processes (processes.md) from the model, the user manual and a key-user interview (E2E-16).

    draft_processes.py --actions actions.json --out processes.md [--manual FILE ...] [--interview FILE ...] [--max N]

E2E-16: per-action journeys (E2E-10) prove buttons, not jobs. A process is a job a user does end to end, defined
cheaply: this tool writes the drafts, a consultant runs a 15-minute key-user interview (templates/process-interview.md)
and the key user confirms. Every process written here is "status: draft"; this tool never writes "confirmed" and
bin/process_journeys.py compiles confirmed processes only. Format: templates/processes.example.md.

Three inputs, each cited in the process's "source:" line:
  model      actions.json (bin/action_inventory.py on the OLD model). Drafts, ranked:
               lifecycle   the actions of one entity that change its status, run a workflow or a task outcome
                           (kind/effects status-change, workflow-call, task-outcome, workflow-op), in click-path order;
                           the entity's enumeration values are listed under notes;
               create      a create button and the save on the page it opens: fill the first String attribute with
                           "<Attr> ${RUN_ID}", expect that row (COUNT = 1 through the data rung, E2E-9);
               write       any other action without a todo that commits, on its recorded click path.
             Only actions without a todo and with a click path are drafted from the model (the rest would compile
             INVALID); their steps are pinned (=> <action id>), so a confirmed model draft compiles as it stands.
  --manual   md / txt / html, or pdf through pdftotext. A section (heading) with two or more list items is a process
             in the users' own words; so is each row of a table that has a name / process / task / flow column (with
             an actor / role column for its roles and a step / command / action column, split on ";" or "->", for its
             steps), under a heading or in a column that says process / task / flow / procedure / use case / scenario.
             Each step is matched to the actions (caption, widget name, or the page it opens): one match pins it, more
             or none write "=> ?" and a "candidates:" line, so the draft cannot compile until a human picks. A step
             naming alternatives ("Submit/Approve/Release/Retire") is never pinned on the one word that matched.
             A manual process that pins the final action of a model draft replaces it (the users' words win); the
             model's expected outcome is kept under notes as a suggestion.
  --interview notes written on templates/process-interview.md: "Top 5 daily tasks" (a task with indented sub-steps,
             or a single step), "Most critical process" (its numbered steps; "What breaking looks like" goes to its
             notes), roles from "[Role]" / "Roles". "expect:" lines in the notes are carried as written.

Existing processes in --out are kept byte for byte (human edits win): a draft whose name is already there is not
written again, and new ids continue after the highest Pnn. Prints "drafted N (model M, manual K, interview I) · kept E
existing · not written X (--max)". Exit 0, or 2 on unreadable input.
"""
import argparse
import html
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_journeys import FILL_KINDS  # noqa: E402
from gen_journeys import task_list_hosts  # noqa: E402
from process_journeys import Compiler, assign_to_me_dead, has_phrase, parse_processes, quoted, words  # noqa: E402

LIFECYCLE = {"status-change", "workflow-call", "task-outcome", "workflow-op"}
PROCESSY = r"process|task|flow|procedure|use ?case|scenario"
LIST = re.compile(r"^(?P<ind>\s*)(?:\d+[.)]|[-*+])\s+(?P<t>.+?)\s*$")


# ------------------------------------------------------------------------------------------------ model
def short(qn):
    return (qn or "?").rsplit(".", 1)[-1]


def click_text(x):
    if x.get("caption"):
        return f'Click "{x["caption"]}"'
    return f"Click the {x['widget']} ({x.get('widget_type') or 'widget'}) on {short(x['host'])}"


def string_field(x):
    """The first String field a run can type "<Attr> ${RUN_ID}" into, or None."""
    for f in x.get("fields") or []:
        at = f.get("attr_type") or {}
        if (f.get("input") == "text" and at.get("type") == "String" and not f.get("hidden") and not f.get("password")
                and f.get("editable") in (None, "Always") and f.get("attribute") and not f.get("association")):
            a = short(f["attribute"])
            if not at.get("length") or at["length"] >= len(a) + 12:
                return f
    return None


def entity_of(x):
    if x.get("entity"):
        return x["entity"]
    if x.get("context"):
        return x["context"]
    f = string_field(x) or next((g for g in x.get("fields") or [] if g.get("attribute")), None)
    return f["attribute"].rsplit(".", 1)[0] if f else None


def fill_expect(x):
    f = string_field(x)
    if not f:
        return [], None
    v = f"{short(f['attribute'])} ${{RUN_ID}}"
    return ([f'Fill "{short(f["attribute"])}" with "{v}"'],
            f'{f["attribute"].rsplit(".", 1)[0]} where {short(f["attribute"])} = "{v}"')


def model_drafts(doc, comp, users=None, left_out=None):
    left_out = [] if left_out is None else left_out
    ok = [x for x in doc.get("actions", []) if not x.get("todo") and x.get("path") and x.get("path_role")]
    hosts = task_list_hosts(doc)   # PRF-2: only a participant's task list gives tasks that arrive assigned
    # QW-2: "Assign to me" shows only for an unassigned task; a role with one user gets its tasks assigned, so the
    # button never renders and a process step on it can only fail (Purchase Request: 4 steps, cost 13). Left out, said.
    dead = {x["id"]: f"left out '{x.get('caption') or x['widget']}' ({x['id']}): shown only for unassigned tasks and role "
                     f"{x['path_role']} has 1 user, its tasks arrive assigned"
            for x in ok if assign_to_me_dead(x, x["path_role"], users, hosts)}
    left_out.extend(dead.values())
    blocking = lambda x: [t for t in x.get("todo") or [] if not t.startswith("no-click-path")]
    used, out = set(), []
    eff = lambda x: set(x.get("effects") or []) | {x.get("kind"), x["action"]}
    # lifecycle: per entity, the status / workflow / task actions, shortest click path first
    groups = {}
    for x in ok:
        if eff(x) & LIFECYCLE and entity_of(x):
            groups.setdefault(entity_of(x), []).append(x)
    for ent, xs in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        xs.sort(key=lambda x: (len(x["path"]), x["id"]))
        steps, notes = [], [dead[x["id"]] for x in xs if x["id"] in dead]
        xs = [x for x in xs if x["id"] not in dead]
        if not xs:
            continue
        for x in xs:
            fl, _ = fill_expect(x) if x is xs[0] else ([], None)
            steps += [(x["path_role"], s, None, None) for s in fl] + [(x["path_role"], click_text(x), x["id"], None)]
            used.add(x["id"])
            for f in x.get("fields") or []:
                at = f.get("attr_type") or {}
                if at.get("type") == "Enumeration" and at.get("enum"):
                    notes.append(f"{short(f['attribute'])} values: {', '.join(map(str, at['enum']))}")
        _, exp = fill_expect(xs[0])
        out.append({"rank": 0, "name": f"Move a {short(ent)} through its statuses", "steps": steps, "expect": exp,
                    "source": f"model: actions.json, {len(xs)} status / workflow / task actions of {ent}",
                    "notes": "; ".join(dict.fromkeys(notes)), "finals": {x["id"] for x in xs}})
    # create + save on the page the create opens
    for x in ok:
        if x["action"] != "create" or not x.get("target") or x["id"] in used or x["id"] in dead:
            continue
        saves = [s for s in doc.get("actions", []) if s["action"] == "save" and comp.page_of(s) == x["target"]
                 and not blocking(s) and comp.may_run(s, x["path_role"])]
        if len(saves) != 1:
            continue
        s = saves[0]
        fl, exp = fill_expect(s)
        used |= {x["id"], s["id"]}
        out.append({"rank": 1, "name": f"Create a {short(x.get('entity') or entity_of(s) or x['target'])}",
                    "steps": [(x["path_role"], click_text(x), x["id"], None)] + [(x["path_role"], t, None, None) for t in fl]
                    + [(x["path_role"], click_text(s), s["id"], None)], "expect": exp,
                    "source": f"model: actions.json, create {x['id']} + save {s['id']}", "notes": "", "finals": {s["id"]}})
    # any other action that writes
    for x in ok:
        if x["id"] in used or x["id"] in dead or not (x["action"] == "save" or eff(x) & FILL_KINDS):
            continue
        fl, exp = fill_expect(x)
        out.append({"rank": 2, "name": f"{x.get('caption') or x['widget']} on {short(x['host'])}",
                    "steps": [(x["path_role"], t, None, None) for t in fl] + [(x["path_role"], click_text(x), x["id"], None)],
                    "expect": exp, "source": f"model: actions.json, {x['id']} ({x.get('kind')})", "notes": "",
                    "finals": {x["id"]}})
    return out


# ------------------------------------------------------------------------------------------------ text inputs
def read_text(path):
    p = Path(path)
    if p.suffix.lower() == ".pdf":
        if not shutil.which("pdftotext"):
            raise OSError(f"{path}: a pdf needs pdftotext (poppler) on PATH, or give its text as .txt")
        return subprocess.run(["pdftotext", "-layout", str(p), "-"], capture_output=True, text=True, check=True).stdout
    t = p.read_text(encoding="utf-8", errors="replace")
    if p.suffix.lower() in (".html", ".htm"):
        t = re.sub(r"(?is)<(script|style)\b.*?</\1>", "", t)
        t = re.sub(r"(?is)<h([1-6])[^>]*>(.*?)</h\1>", lambda m: "\n" + "#" * int(m[1]) + " " + re.sub(r"<[^>]+>", "", m[2]) + "\n", t)
        t = re.sub(r"(?is)<li[^>]*>", "\n- ", t)
        t = re.sub(r"(?is)<(br|p|div|tr|ol|ul)[^>]*>", "\n", t)
        t = html.unescape(re.sub(r"<[^>]+>", "", t))
    return t


def sections(text):
    """[(heading, first line number, [lines])]. Markdown headings, or numbered / short title lines in plain text."""
    out, cur = [], ("(top)", 1, [])
    md = any(re.match(r"^#{1,6}\s", l) for l in text.splitlines())
    for i, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line) if md else re.match(r"^(\d+(?:\.\d+)*\.?\s+[A-Z][^.:;]{2,70})\s*$", line)
        if m:
            out.append(cur)
            cur = (m[1].strip(), i, [])
        else:
            cur[2].append(line)
    out.append(cur)
    return [s for s in out if s[2]]


def clean(t):
    t = re.sub(r"\*\*(.+?)\*\*|__(.+?)__|`(.+?)`", lambda m: '"' + (m[1] or m[2] or m[3]) + '"', t)
    return re.sub(r"\s+", " ", t).strip()


def heading_name(h):
    return re.sub(r"^\d+(\.\d+)*\.?\s+", "", h).strip()


def table_rows(lines):
    """Markdown table rows as dicts keyed by lower-case header; "_i" is the row's index in lines (its source line)."""
    rows, head = [], None
    for i, l in enumerate(lines):
        if not l.strip().startswith("|"):
            if head and rows:
                break
            continue
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if head is None:
            head = [c.lower() for c in cells]
        elif all(re.match(r"^:?-{2,}:?$", c) for c in cells if c):
            continue
        else:
            rows.append(dict(zip(head, cells), _i=i))
    return head or [], rows


def col(head, pat):
    return next((h for h in head if re.search(pat, h)), None)


class Matcher:
    def __init__(self, doc, comp):
        self.doc, self.comp = doc, comp
        self.roles = sorted({r for x in doc.get("actions", []) for r in (x.get("roles") or []) + [x.get("path_role")] if r})
        self.menus = comp.menus

    def match(self, text):
        """Candidate action ids for a step in user words (caption, widget, page opened), best tier only."""
        t, qs = text.lower(), [q.strip().lower() for q in quoted(text)]
        for tier in (1, 2):
            c = [x["id"] for x in self.doc.get("actions", [])
                 if any(lt == tier and lab and ((qs and lab in qs) or (not qs and len(lab) > 2 and has_phrase(t, lab)))
                        for lt, lab in self.comp.labels(x))]
            if c:
                return c
        return []

    def roles_in(self, text):
        return [r for r in self.roles if has_phrase(text.lower(), r.lower()) or has_phrase(text.lower(), words(r))]

    def step(self, role, text):
        """(role, text, pin or '?', candidates line or None)."""
        if re.match(r"^(fill|enter|type|select|choose|pick)\s+" + r"[\"“']", text, re.I) or re.match(r"^(start on|sign in|log ?in|confirm)\b", text, re.I):
            return (role, text, None, None)
        m = re.match(r"^(open|go to|navigate to)\s+(.+?)(\s+in the (main )?menu)?\s*\.?$", text, re.I)
        if m:
            q = quoted(m[2])
            if (q[0] if q else m[2]).strip().lower() in self.menus:
                return (role, text, None, None)
        c = self.match(text)
        if len(c) == 1 and not quoted(text) and re.search(r"\w\s*/\s*\w", text):
            # "Submit/Approve/Release/Retire": one word of several matched; several actions in one step, never a pin
            return (role, text, "?", f"candidates: {c[0]} (the step names alternatives: one action per step)")
        if len(c) == 1:
            return (role, text, c[0], None)
        return (role, text, "?", "candidates: " + (" | ".join(c[:6]) + (" | ..." if len(c) > 6 else "") if c else "none in the model"))


def manual_drafts(path, m):
    out = []
    text = read_text(path)
    for h, line, lines in sections(text):
        name = heading_name(h)
        head, rows = table_rows(lines)
        ncol = col(head, r"name|process|task|procedure|use ?case")
        if rows and ncol and re.search(PROCESSY, h + " " + ncol, re.I):
            rcol, icol = col(head, r"actor|role|persona|user"), col(head, r"\bid\b|flowid|^id$|id$")
            scol = col(head, r"step") or col(head, r"command|action")
            for k, r in enumerate(rows, 1):
                roles = [x.strip() for x in re.split(r"[/,;]| and ", r.get(rcol, "")) if x.strip()] if rcol else []
                steps_t = [clean(s) for s in re.split(r";|→|->", r.get(scol, "")) if clean(s) and clean(s) not in ("-", "...")] if scol else []
                steps_t = [s for s in steps_t if not s.endswith("...")] or steps_t
                role = roles[0] if len(roles) == 1 else None
                st = [m.step(role, s) for s in (steps_t or [clean(r[ncol])])]
                ref = r.get(icol) if icol and r.get(icol) else f"row {k}"
                out.append({"name": clean(r[ncol]), "roles": roles, "steps": st,
                            "source": f"manual: {Path(path).name} §{name} {ref} (line {line + r['_i'] + 1})", "expect": None,
                            "notes": ""})
            continue
        items = [clean(LIST.match(l)["t"]) for l in lines if LIST.match(l) and not l.strip().startswith("|")]
        if len(items) < 2:
            continue
        roles = m.roles_in(" ".join(lines) + " " + h)
        role = roles[0] if len(roles) == 1 else None
        out.append({"name": name, "roles": roles, "steps": [m.step(role, s) for s in items],
                    "source": f"manual: {Path(path).name} §{name} (line {line})", "expect": None, "notes": ""})
    return out


def interview_drafts(path, m):
    out, text = [], read_text(path)
    roles_all = []
    secs = sections(text)
    breaking = ""
    for h, line, lines in secs:
        if re.search(r"\broles?\b", h, re.I):
            for l in lines:
                lm = LIST.match(l)
                if lm:
                    roles_all.append(re.split(r"[:—–(-]", lm["t"])[0].strip())
        if re.search(r"break", h, re.I):
            breaking = clean(" ".join(l for l in lines if l.strip() and not l.strip().startswith(">")))
    for h, line, lines in secs:
        name = heading_name(h)
        if not re.search(r"task|process|critical", h, re.I) or re.search(r"break|sample|data", h, re.I):
            continue
        expect = next((l.split(":", 1)[1].strip() for l in lines if re.match(r"^\s*expect\s*:", l, re.I)), None)
        critical = bool(re.search(r"critical", h, re.I))
        items = [(len(LIST.match(l)["ind"]), clean(LIST.match(l)["t"]), line + i + 1) for i, l in enumerate(lines) if LIST.match(l)]
        if critical:
            nm = next((l.split(":", 1)[1].strip() for l in lines if re.match(r"^\s*(name|process)\s*:", l, re.I)), name)
            out.append(one_interview(m, nm, [t for _, t, _ in items], f"interview: {Path(path).name} §{name} (line {line})",
                                     expect, ("breaking: " + breaking) if breaking else "", roles_all))
            continue
        top = min((i for i, _, _ in items), default=0)
        k = 0
        for j, (ind, t, at) in enumerate(items):
            if ind != top:
                continue
            k += 1
            subs = []
            for ind2, t2, _ in items[j + 1:]:
                if ind2 == top:
                    break
                subs.append(t2)
            out.append(one_interview(m, re.sub(r"^\[[^\]]+\]\s*", "", t), subs or [t],
                                     f"interview: {Path(path).name} §{name} item {k} (line {at})", None, "", roles_all, t))
    return out


def one_interview(m, name, steps, source, expect, notes, roles_all, head=""):
    lead = re.match(r"^\[([^\]]+)\]", head or name)
    role = lead[1].strip() if lead else None
    st = []
    for s in steps:
        r = re.match(r"^\[([^\]]+)\]\s*(.*)$", s)
        rr, txt = (r[1].strip(), r[2]) if r else (role, s)
        st.append(m.step(rr, txt))
    roles = list(dict.fromkeys([s[0] for s in st if s[0]] or m.roles_in(" ".join(steps + [name])) or []))
    if not roles and len(roles_all) == 1:
        roles = roles_all
    return {"name": name, "roles": roles, "steps": st, "source": source, "expect": expect, "notes": notes}


# ------------------------------------------------------------------------------------------------ writing
def render(pid, d):
    roles = d.get("roles") or sorted({s[0] for s in d["steps"] if s[0]})
    lines = [f"## {pid}: {d['name']}", "status: draft", f"roles: {', '.join(roles) if roles else '?'}", f"source: {d['source']}", "steps:"]
    for i, (role, text, pin, cand) in enumerate(d["steps"], 1):
        lines.append(f"{i}. " + (f"[{role}] " if role else "") + text + (f"  => {pin}" if pin else ""))
        if cand:
            lines.append(f"   {cand}")
    lines.append(f"expect: {d['expect'] or '?'}")
    if d.get("notes"):
        lines.append(f"notes: {d['notes']}")
    return "\n".join(lines) + "\n"


HEADER = """# Processes

Drafted by bin/draft_processes.py (E2E-16). Every process is `status: draft` until a key user confirms it: check the
steps read as they work, pick a candidate for each `=> ?`, write the expected outcome, then set `status: confirmed`.
Only confirmed processes are compiled (bin/process_journeys.py). Format: templates/processes.example.md.

"""


def main():
    ap = argparse.ArgumentParser(description="E2E-16: draft user processes (status: draft) from model, manual, interview")
    ap.add_argument("--actions", required=True, help="actions.json of the OLD model (bin/action_inventory.py --out)")
    ap.add_argument("--out", required=True, help="processes.md: created, or extended (existing processes are kept)")
    ap.add_argument("--manual", nargs="*", default=[], help="user manual text: md, txt, html, or pdf (pdftotext)")
    ap.add_argument("--interview", nargs="*", default=[], help="key-user interview notes (templates/process-interview.md)")
    ap.add_argument("--max", type=int, default=12, help="write at most N new drafts, best ranked first (default 12)")
    ap.add_argument("--users", help="users.json (run_journeys.py): an \"Assign to me\" step is left out of a model draft "
                    "for a role with exactly one user (QW-2)")
    ap.add_argument("--no-model", action="store_true", help="no model drafts (manual / interview only)")
    a = ap.parse_args()
    try:
        doc = json.load(open(a.actions))
        if not isinstance(doc.get("actions"), list):
            raise ValueError('no "actions" list (not an action_inventory.py --out file)')
        comp = Compiler(doc)
        m = Matcher(doc, comp)
        users = json.load(open(Path(a.users).expanduser())) if a.users else None
        left_out = []
        model = [] if a.no_model else model_drafts(doc, comp, users, left_out)
        manual = [d for f in a.manual for d in manual_drafts(f, m)]
        inter = [d for f in a.interview for d in interview_drafts(f, m)]
    except (OSError, ValueError, subprocess.CalledProcessError) as e:
        print(f"cannot read input: {e}", file=sys.stderr)
        sys.exit(2)
    # a manual / interview process that pins a model draft's final action replaces it: the users' words win
    for d in manual + inter:
        pins = {s[2] for s in d["steps"] if s[2] and s[2] != "?"}
        for md in [x for x in model if x["finals"] & pins]:
            model.remove(md)
            d["notes"] = "; ".join(x for x in (d["notes"], f"replaces model draft '{md['name']}'"
                                               + (f", which suggests expect: {md['expect']}" if md["expect"] else "")) if x)
    for d in manual + inter:   # no role in the text: the role the model walks every pinned action as, when that is one
        pr = {comp.by_id[s[2]].get("path_role") for s in d["steps"] if s[2] not in (None, "?")}
        if not d["roles"] and len(pr) == 1 and None not in pr:
            d["roles"] = sorted(pr)
            d["notes"] = "; ".join(x for x in (d["notes"], f"role {d['roles'][0]} from the model (the text names none): check it") if x)
    for d in manual:   # rank: more pinned steps first, file order otherwise
        d["rank"] = 3 + (0 if any(s[2] not in (None, "?") for s in d["steps"]) else 1)
    for d in inter:
        d["rank"] = -1   # what the key user said comes first
    for d in model:
        d["roles"] = sorted({s[0] for s in d["steps"]})
    for t in left_out:
        print(f"NOTE {t}")
    allp = sorted(inter + model + manual, key=lambda d: d["rank"])
    out = Path(a.out)
    old = out.read_text(encoding="utf-8") if out.is_file() else ""
    have = parse_processes(old)
    names = {p["name"].strip().lower() for p in have}
    nums = [int(x[1]) for x in (re.match(r"^P(\d+)$", p["id"]) for p in have) if x]
    nxt = max(nums, default=0) + 1
    new, cut, dup = [], 0, 0
    for d in allp:
        if d["name"].strip().lower() in names:
            dup += 1
            continue
        if len(new) >= a.max:
            cut += 1
            continue
        names.add(d["name"].strip().lower())
        new.append(render(f"P{nxt:02d}", d))
        print(f"DRAFT P{nxt:02d} {d['name'][:60]:60} {d['source'][:60]}  steps {len(d['steps'])}, pinned "
              f"{sum(1 for s in d['steps'] if s[2] not in (None, '?'))}, open {sum(1 for s in d['steps'] if s[2] == '?')}")
        nxt += 1
    body = (old.rstrip("\n") + "\n\n" if old else HEADER) + "\n".join(new)
    out.write_text(body if body.endswith("\n") else body + "\n", encoding="utf-8")
    src = lambda k: sum(1 for b in new if f"source: {k}:" in b)
    print(f"drafted {len(new)} (model {src('model')}, manual {src('manual')}, interview {src('interview')}) · kept {len(have)} existing"
          + (f" · {dup} already there by name" if dup else "") + f" · not written {cut} (--max {a.max})")
    print("all drafts are status: draft: a key user confirms them (status: confirmed) before process_journeys.py compiles any")


if __name__ == "__main__":
    main()
