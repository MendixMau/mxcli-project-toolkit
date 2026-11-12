#!/usr/bin/env python3
"""decisions.py: the single decision ledger of an upgrade run, <work>/decisions.json (a list of rows, history kept).

  decisions.py add     --work W --item ID --choice KEY --by NAME --source chat|page [--reason TEXT]
  decisions.py import  --work W --json FILE [--names FILE]
  decisions.py apply   --work W
  decisions.py pending --work W [--json]

Row: {item, choice, by, at, source: page|chat, reason?, plan_hash? (sign-off only)}. The last row per item wins; older rows stay.
Two paths write the same ledger: the cockpit page buttons (the orchestrating session exports the artifact db and runs `import`;
rows are source page) and the chat ("approve batch 1": the session runs `add --source chat`). Item ids and options come from
cockpitpage.build_model(), the same list the page shows (`pending` prints it).

apply turns the ledger into what the pipeline already reads, every line ending in "by NAME via page|chat: reason" and tagged
[item:ID] so a rerun replaces it instead of adding it again (idempotent):
  - an option's "writes": {file, line} lines into approved.txt, allow.txt, log-allow.txt, shot-accept.txt, regression-decisions.txt,
    rejected-changes.txt, ... in W;  {decisions_md: ...} replaces the P-n line of DECISIONS.md (the module plan answers);
  - the sign-off: PROPOSAL.md section 6 gets `Signed-off: NAME date`.

SIGN-OFF RULE. Nobody but the person writes the Signed-off line. `add --item signoff` always refuses (exit 2: "sign the plan with
the page button"). Only `import` carries a sign-off, from the page's signoffs collection, and apply writes the line only from a
row with source page whose plan_hash equals the current PROPOSAL.md hash (a changed plan clears it), using that row's name. A row
whose name is still an opaque viewer id (u_...) is not written: give import --names FILE ({"u_...": "Name"}).

STEPS. A row whose item is a step id (S-n), or the P-n alias of a step in <work>/steps.jsonl, also writes that step's approval
through steps.py (the same person, the same source): choice approve or reject for a step id, any option key of the item for a
P-n (approved). The ledger row wins over an older approval and never over a newer one; running import again adds nothing.
A sign-off is never a step approval here: proposal.py approves the steps that nobody answered on its own.

Exit: 0 ok, 2 usage or refused input.
"""
import argparse, datetime, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cockpitpage  # noqa: E402
import steps  # noqa: E402  step records: a ledger row for a step writes that step's approval

LEDGER = "decisions.json"


def die(msg, code=2):
    print(f"decisions: {msg}", file=sys.stderr)
    sys.exit(code)


def load(work):
    p = os.path.join(work, LEDGER)
    try:
        d = json.load(open(p, encoding="utf-8"))
    except FileNotFoundError:
        return []
    except ValueError:
        die(f"{p} is not valid JSON", 2)
    if not isinstance(d, list):
        die(f"{p} must be a list", 2)
    return d


def save(work, rows):
    p = os.path.join(work, LEDGER)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, p)


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def lastmap(rows):
    out = {}
    for r in rows:
        if r.get("item") and r["item"] != "signoff":
            out[r["item"]] = r
    return out


def clean(s):
    return " ".join(str(s).split())


STEP_CHOICES = ("approve", "reject")


def sid_of(w, ref):
    """The S-n id of a step id or P-n alias in this run's steps.jsonl, else None."""
    return steps.resolve(w, ref) if os.path.exists(steps.path_of(w)) else None


def step_item(w, item, choice):
    """The S-n id when `item` is a step id (or alias) and `choice` is approve or reject, else None."""
    sid = sid_of(w, item)
    return sid if sid and choice in STEP_CHOICES else None


def sync_steps(w, rows):
    """Write the approval of every step that the last ledger row of an item names; skip what is already written."""
    n = 0
    for item, r in sorted(lastmap(rows).items()):
        sid = sid_of(w, item)
        if not sid:
            continue
        state = "rejected" if r.get("choice") == "reject" else "approved"
        cur = steps.approval_of(w, sid)
        if cur and cur.get("ledger_at") == r["at"] and cur["state"] == state:
            continue
        if cur and cur["state"] != "assumed" and r["at"] < (cur.get("ledger_at") or cur["at"]):
            continue   # a newer answer from another route stays; an assumption never does
        steps.set_approval(w, sid, state, r["by"], r["source"], ledger_at=r["at"], item=item, **({"reason": r["reason"]} if r.get("reason") else {}))
        n += 1
    return n


def cmd_add(a):
    w = a.work
    if a.item == "signoff":
        die("sign the plan with the page button: a sign-off is only valid from the cockpit page (source page, through import), "
            "never typed in chat and never added here", 2)
    model = cockpitpage.build_model(w)
    it = next((i for i in model["items"] if i["id"] == a.item), None)
    if not it and step_item(w, a.item, a.choice):
        it = {"options": [{"key": c} for c in STEP_CHOICES]}
    if not it:
        if sid_of(w, a.item):
            die(f"'{a.item}' is a step: the choice is approve or reject, not '{a.choice}'")
        die(f"unknown item '{a.item}' (decisions.py pending lists the ids)")
    keys = [o["key"] for o in it["options"]]
    if a.choice not in keys:
        die(f"'{a.choice}' is not an option of {a.item}: {', '.join(keys)}")
    by = clean(a.by)
    if not by:
        die("--by NAME is required")
    rows = load(w)
    row = {"item": a.item, "choice": a.choice, "by": by, "at": now(), "source": a.source}
    if a.reason:
        row["reason"] = clean(a.reason)
    rows.append(row)
    save(w, rows)
    sync_steps(w, rows)
    print(f"decisions: {a.item} = {a.choice} by {by} via {a.source}")
    return 0


def cmd_import(a):
    w = a.work
    try:
        data = json.load(open(a.json, encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"cannot read {a.json}: {e}")
    names = {}
    if a.names:
        try:
            names = json.load(open(a.names, encoding="utf-8"))
        except (OSError, ValueError) as e:
            die(f"cannot read {a.names}: {e}")
    if isinstance(data, list):
        decs, sigs = data, []
    else:
        decs, sigs = data.get("decisions", []), data.get("signoffs", [])
    model = cockpitpage.build_model(w)
    known = {i["id"]: i for i in model["items"]}
    rows = load(w)
    seen = {(r.get("item"), r.get("choice"), r.get("by"), r.get("at")) for r in rows}
    added = skipped = 0
    for d in decs:
        item = d.get("item") or d.get("id")
        if item == "signoff":
            sigs = list(sigs) + [d]
            continue
        by = names.get(d.get("by"), d.get("by"))
        keys = [o["key"] for o in known[item]["options"]] if item in known else list(STEP_CHOICES) if step_item(w, item, d.get("choice")) else []
        if d.get("choice") not in keys or not by:
            print(f"decisions: skipped row for '{item}': unknown item, option or name", file=sys.stderr)
            skipped += 1
            continue
        row = {"item": item, "choice": d["choice"], "by": clean(by), "at": d.get("at") or now(), "source": "page"}
        if d.get("reason"):
            row["reason"] = clean(str(d["reason"]))[:200]
        k = (row["item"], row["choice"], row["by"], row["at"])
        if k in seen:
            continue
        seen.add(k)
        rows.append(row)
        added += 1
    for s in sigs:
        if s.get("source", "page") != "page":
            print("decisions: skipped a sign-off row that is not source page", file=sys.stderr)
            skipped += 1
            continue
        uid = s.get("id") or s.get("by") or ""
        by = names.get(s.get("by") or uid, s.get("by") or uid)
        plan = s.get("plan") or s.get("plan_hash") or ""
        if not by or not plan:
            print("decisions: skipped a sign-off row without name or plan hash", file=sys.stderr)
            skipped += 1
            continue
        row = {"item": "signoff", "choice": "sign", "by": clean(by), "at": s.get("at") or now(), "source": "page", "plan_hash": plan}
        k = ("signoff", "sign", row["by"], row["at"])
        if k in seen:
            continue
        seen.add(k)
        rows.append(row)
        added += 1
    save(w, rows)
    sync_steps(w, rows)
    print(f"decisions: imported {added} row(s), skipped {skipped}")
    return 0


# ---- apply ----
def read_lines(p):
    try:
        return open(p, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return None


def write_lines(p, lines):
    with open(p, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))


def set_tagged(path, tag, line):
    """Remove every line carrying tag, then append `line` (None = only remove). Rewrites the file only when it changes."""
    old = read_lines(path)
    base = [x for x in (old or []) if tag not in x]
    new = base + ([line] if line else [])
    if old is None and not new:
        return False
    if old == new:
        return False
    write_lines(path, new)
    return True


def apply_signoff(w, rows, model):
    sigs = [r for r in rows if r.get("item") == "signoff"]
    if not sigs:
        return "no sign-off row"
    pp = os.path.join(w, "PROPOSAL.md")
    lines = read_lines(pp)
    if lines is None:
        return "no PROPOSAL.md"
    cur = model["planHash"]
    ok = [r for r in sigs if r.get("source") == "page" and r.get("plan_hash") == cur and cur]
    if not ok:
        return "sign-off ignored: not from the page, or the plan changed since (sign again on the page)"
    r = ok[-1]
    if re.match(r"^u_\S+$", r["by"]):
        return f"sign-off not written: '{r['by']}' is a viewer id, not a name (import --names FILE maps it)"
    i = next((n for n, x in enumerate(lines) if x.startswith("## 6.")), None)
    if i is None:
        return "PROPOSAL.md has no section 6"
    sec = lines[i:]
    if any(cockpitpage.SIGNED.match(x) for x in sec):
        return "already signed"
    if any(x.startswith("Status: PAUSED") for x in sec):
        return "PAUSED by the owner: sign-off not written (remove the Status line first)"
    line = f"Signed-off: {r['by']} {r['at'][:10]}"
    j = next((n for n in range(i, len(lines)) if lines[n].strip() == "Status: open"), None)
    if j is None:
        lines.append(line)
    else:
        lines[j] = line
    write_lines(pp, lines)
    return f"Signed-off line written for {r['by']} (page sign-off, plan {cur[:8]})"


def apply_decisions_md(w, op, tag_by):
    p = os.path.join(w, "DECISIONS.md")
    lines = read_lines(p) or []
    pid = op["id"]
    k = next((n for n, x in enumerate(lines) if re.match(rf"^{re.escape(pid)}\s*\|", x)), None)
    closes = "closes by: the rung that measures it passes (steps/decide.md)"
    if k is not None:
        m = re.search(r"\| (closes by: .*)$", lines[k])
        closes = m.group(1) if m else closes
    new = f"{pid} | {op['name']} | {op['kind']} | {op['option']} | {tag_by} | {tag_by.split(' via ')[0].replace('by ', '', 1)} | DECIDED | {closes}"
    if k is not None and lines[k] == new:
        return False
    if k is None:
        lines.append(new)
    else:
        lines[k] = new
    write_lines(p, lines)
    return True


def cmd_apply(a):
    w = a.work
    rows = load(w)
    model = cockpitpage.build_model(w)
    items = {i["id"]: i for i in model["items"]}
    changed, notes = 0, []
    for item, r in sorted(lastmap(rows).items()):
        it = items.get(item)
        if not it and sid_of(w, item):
            notes.append(f"{item}: a step, its approval is in steps.jsonl; nothing to write for the pipeline")
            continue
        if not it:
            notes.append(f"{item}: not an open item of this run, skipped")
            continue
        opt = next((o for o in it["options"] if o["key"] == r.get("choice")), None)
        if not opt:
            notes.append(f"{item}: option '{r.get('choice')}' no longer exists, skipped")
            continue
        tag = f"[item:{item}]"
        reason = r.get("reason") or opt["label"]
        by = f"by {r['by']} via {r['source']}: {reason}"
        wrote = set()
        for wr in opt.get("writes", []):
            if "decisions_md" in wr:
                changed += apply_decisions_md(w, wr["decisions_md"], by)
            else:
                path = os.path.join(w, wr["file"])
                changed += set_tagged(path, tag, f"{wr['line']} # {tag} {by}")
                wrote.add(wr["file"])
        for o in it["options"]:   # a changed answer removes what the earlier answer wrote
            for wr in o.get("writes", []):
                if "file" in wr and wr["file"] not in wrote:
                    changed += set_tagged(os.path.join(w, wr["file"]), tag, None)
        if not opt.get("writes"):
            notes.append(f"{item}: recorded ({opt['label']}), nothing to write for the pipeline")
    s = apply_signoff(w, rows, model)
    if s != "no sign-off row":
        notes.append(f"sign-off: {s}")
        changed += s.startswith("Signed-off line written")
    for n in notes:
        print(f"decisions: {n}")
    print(f"decisions: apply done, {changed} file change(s)")
    return 0


def cmd_pending(a):
    w = a.work
    model = cockpitpage.build_model(w)
    last = lastmap(load(w))
    open_items = [i for i in model["items"] if not (i["id"] in last) and i["kind"] != "confirmgroup"]   # the group row is only a page heading; its changes are the items
    if a.json:
        print(json.dumps([{k: i[k] for k in ("id", "kind", "title", "meta", "rec", "options")} for i in open_items], indent=1))
        return 0
    print(f"open items ({len(open_items)}):")
    for i in open_items:
        print(f"\n{i['id']}  {i['title']}")
        print(f"    {i['meta']}")
        if i["kind"] == "signoff":
            print("    sign the plan with the page button (a sign-off is never taken from chat)")
            continue
        for o in i["options"]:
            print(f"    {o['key']}{' (recommended)' if o['key'] == i['rec'] else ''}: {o['label']}")
        print(f"    chat: decisions.py add --work {w} --item {i['id']} --choice {i['rec']} --by NAME --source chat")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for n in ("add", "import", "apply", "pending"):
        s = sub.add_parser(n)
        s.add_argument("--work", required=True)
        if n == "add":
            s.add_argument("--item", required=True)
            s.add_argument("--choice", required=True)
            s.add_argument("--by", required=True)
            s.add_argument("--source", required=True, choices=["chat", "page"])
            s.add_argument("--reason")
        if n == "import":
            s.add_argument("--json", required=True)
            s.add_argument("--names")
        if n == "pending":
            s.add_argument("--json", action="store_true")
    a = ap.parse_args()
    a.work = os.path.abspath(a.work)
    if not os.path.isdir(a.work):
        die(f"no work folder {a.work}")
    return {"add": cmd_add, "import": cmd_import, "apply": cmd_apply, "pending": cmd_pending}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
