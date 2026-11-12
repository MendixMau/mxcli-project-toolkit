#!/usr/bin/env python3
"""smokewalk_gen.py: write a smoke-walk plan from the app model: per user role, every page one click away.

Reads the project (.mpr v1, or v2 with mprcontents/) and, per user role of the Responsive navigation profile:
  - the role's home page (role-based home item, else the default home page)
  - every menu item (nested items too), with its index path in the menu, so the runner can click it
    (the Dojo client names menu links mx-name-<menuWidget>-<i>-<j>, the model order)
  - every button on the home page that opens a page without parameters (clicked by .mx-name-<widget>)
Steps the role cannot open (page or microflow not allowed for any of its module roles) are left out.
Microflow steps are written with kind "microflow"; the runner skips them unless --microflows (side effects). PV-6: a
role whose home is a microflow, or more than half of whose menu items are, gets a WARN line: without --microflows the walk
of that role proves nothing.

Never walked (FM-6): a step whose page, microflow, widget or menu caption matches DemoData*, *Reset*, *Delete* (fnmatch,
case-insensitive; the demo-data and reset buttons of a Teamcenter-style app open a confirmation that rewrites data and
the walk can never accept it). Such a step is written to "skipped" with the pattern; --exclude PATTERN adds more,
--no-default-excludes drops the defaults.

Usage:
  smokewalk_gen.py <project.mpr|dir> -o plan.json [--role NAME ...] [--exclude PATTERN ...] [--no-default-excludes]
The plan contains user role names: keep it next to the app data, not in a shared repo.
Run it with smokewalk.js.
"""
import argparse, fnmatch, glob, json, os, sqlite3, sys, uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import bson
except ImportError:
    sys.exit("smokewalk_gen: needs the 'bson' module (pip install pymongo)")


DEFAULT_EXCLUDES = ["DemoData*", "*Reset*", "*Delete*"]
EXCLUDES = list(DEFAULT_EXCLUDES)


def excluded(*names):
    """FM-6: the first exclude pattern that matches any of the names (qualified page or microflow name, its part after the
    module, widget name, menu caption), or ''."""
    for n in names:
        if not n:
            continue
        for cand in {n, n.split(".")[-1]}:
            for pat in EXCLUDES:
                if fnmatch.fnmatch(cand.lower(), pat.lower()):
                    return pat
    return ""


def microflow_warning(role_plan):
    """PV-6: the runner skips microflow steps unless --microflows, so a role whose home page or most of whose menu items
    are microflows proves nothing without it. Returns the warning text or ''."""
    st = role_plan["steps"]
    menu = [x for x in st if x.get("via") == "menu"]
    home_mf = any(x["kind"] == "microflow" and x.get("via") == "home" for x in st)
    mf_menu = [x for x in menu if x["kind"] == "microflow"]
    why = []
    if home_mf:
        why.append("its home is a microflow")
    if menu and len(mf_menu) * 2 > len(menu):
        why.append(f"{len(mf_menu)} of {len(menu)} menu items are microflows")
    if not why:
        return ""
    return ("; ".join(why) + ": smokewalk.js SKIPS microflow steps unless run with --microflows, so without it this role's walk "
            "proves nothing (microflows have side effects: run it on the X_smoke copy only)")


def items(x):
    return [i for i in (x or []) if isinstance(i, dict)]


def text(t):
    if not isinstance(t, dict):
        return ""
    tr = items(t.get("Items"))
    for i in tr:
        if i.get("LanguageCode", "").startswith("en"):
            return i.get("Text", "")
    return tr[0].get("Text", "") if tr else ""


def load_units(mpr):
    from mprunits import unit_rows  # NR2-10: MPR v2 has no Contents column
    units = {}
    for uid, cid, blob in unit_rows(mpr):
        if not blob:
            continue
        try:
            units[uid] = (cid, bson.decode(blob))
        except Exception:
            pass
    return units


def module_of(uid, units):
    seen = 0
    while uid in units and seen < 50:
        cid, d = units[uid]
        if d.get("$Type") == "Projects$ModuleImpl":
            return d.get("Name")
        uid, seen = cid, seen + 1
    return None


def walk_actions(node, widget=None, out=None):
    """Yield (widget name, action dict) for every FormAction / MicroflowAction under node."""
    out = [] if out is None else out
    if isinstance(node, dict):
        t = node.get("$Type", "")
        if t in ("Forms$FormAction", "Forms$MicroflowAction") and widget:
            out.append((widget, node))
        name = node.get("Name") if isinstance(node.get("Name"), str) and t.startswith(("Forms$", "Pages$", "CustomWidgets$")) else None
        for k, v in node.items():
            if k in ("$ID",):
                continue
            walk_actions(v, name or widget, out)
    elif isinstance(node, list):
        for v in node:
            walk_actions(v, widget, out)
    return out


def build(mpr):
    units = load_units(mpr)
    pages, microflows, nav, sec = {}, {}, None, None
    for uid, (cid, d) in units.items():
        t = d.get("$Type")
        if t == "Forms$Page":
            m = module_of(uid, units)
            pages[f"{m}.{d['Name']}"] = d | {"_module": m}
        elif t == "Microflows$Microflow":
            microflows[f"{module_of(uid, units)}.{d['Name']}"] = d
        elif t == "Navigation$NavigationDocument":
            nav = d
        elif t == "Security$ProjectSecurity":
            sec = d
    if not nav or not sec:
        sys.exit("smokewalk_gen: no navigation document or project security in this project")
    prof = next((p for p in items(nav.get("Profiles")) if p.get("Kind") == "Responsive"), None)
    if not prof:
        sys.exit("smokewalk_gen: no Responsive navigation profile")
    roles = {r["Name"]: set(m for m in (r.get("ModuleRoles") or []) if isinstance(m, str)) for r in items(sec.get("UserRoles"))}
    return pages, microflows, prof, sec, roles


def allowed(doc, mroles):
    if doc is None:
        return False
    return bool(mroles & set(m for m in (doc.get("AllowedModuleRoles") or []) if isinstance(m, str)))


def has_params(page):
    return bool(items(page.get("Parameters")))


def page_path(qn):
    m, n = qn.split(".", 1)
    return f"{m}/{n}.page.xml"


def menu_steps(menu_items, path, pages, microflows, mroles, out, parent_caption="", skipped=None):
    for i, it in enumerate(items(menu_items)):
        p = path + [i]
        cap = text(it.get("Caption"))
        a = it.get("Action") or {}
        t = a.get("$Type")
        label = f"{parent_caption} > {cap}" if parent_caption else cap
        if t == "Forms$FormAction":
            pg = (a.get("FormSettings") or {}).get("Form")
            hit = excluded(pg, cap) if pg else ""
            if hit and allowed(pages.get(pg), mroles):
                if skipped is not None:
                    skipped.append({"caption": label, "page": pg, "via": "menu", "why": f"excluded by pattern {hit} (writes data)"})
            elif pg and allowed(pages.get(pg), mroles):
                out.append({"kind": "page", "via": "menu", "menu_path": p, "caption": label, "page": pg,
                            "page_path": page_path(pg), "url": pages[pg].get("Url") or ""})
        elif t == "Forms$MicroflowAction":
            mf = (a.get("MicroflowSettings") or {}).get("Microflow")
            hit = excluded(mf, cap) if mf else ""
            if hit and allowed(microflows.get(mf), mroles):
                if skipped is not None:
                    skipped.append({"caption": label, "microflow": mf, "via": "menu", "why": f"excluded by pattern {hit} (writes data)"})
            elif mf and allowed(microflows.get(mf), mroles):
                out.append({"kind": "microflow", "via": "menu", "menu_path": p, "caption": label, "microflow": mf})
        menu_steps(it.get("Items"), p, pages, microflows, mroles, out, label, skipped)


def plan_for_role(role, pages, microflows, prof, roles, home_buttons=True):
    mroles = roles[role]
    home = next((h for h in items(prof.get("HomeItems")) if h.get("UserRole") == role), None) or prof.get("HomePage") or {}
    home_page = home.get("Page") or ""
    steps, skipped = [], []
    if home_page:
        steps.append({"kind": "page", "via": "home", "caption": "home page", "page": home_page,
                      "page_path": page_path(home_page), "allowed": allowed(pages.get(home_page), mroles)})
    elif home.get("Microflow"):
        steps.append({"kind": "microflow", "via": "home", "caption": "home microflow", "microflow": home["Microflow"]})
    menu_steps((prof.get("Menu") or {}).get("Items"), [], pages, microflows, mroles, steps, skipped=skipped)
    if home_buttons and home_page in pages:
        seen = set()
        for widget, a in walk_actions(pages[home_page].get("FormCall")):
            if a.get("$Type") != "Forms$FormAction":
                continue
            pg = (a.get("FormSettings") or {}).get("Form")
            if not pg or (widget, pg) in seen:
                continue
            seen.add((widget, pg))
            if pg not in pages:
                skipped.append({"widget": widget, "page": pg, "why": "page not found"})
            elif has_params(pages[pg]):
                skipped.append({"widget": widget, "page": pg, "why": "page needs an object (parameter)"})
            elif not allowed(pages[pg], mroles):
                skipped.append({"widget": widget, "page": pg, "why": "not allowed for role"})
            elif excluded(pg, widget):
                skipped.append({"widget": widget, "page": pg, "why": f"excluded by pattern {excluded(pg, widget)} (writes data)"})
            else:
                steps.append({"kind": "page", "via": "button", "widget": widget, "caption": f"button {widget}",
                              "page": pg, "page_path": page_path(pg)})
    return {"role": role, "home": home_page, "steps": steps, "skipped": skipped}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--role", action="append", help="limit to these user roles (default: all but the guest role)")
    ap.add_argument("--exclude", action="append", default=[], metavar="PATTERN", help="also skip steps matching this fnmatch pattern")
    ap.add_argument("--no-default-excludes", action="store_true", help="do not skip DemoData*, *Reset*, *Delete*")
    args = ap.parse_args()
    EXCLUDES[:] = ([] if args.no_default_excludes else DEFAULT_EXCLUDES) + args.exclude
    p = args.project
    if os.path.isdir(p):
        mprs = glob.glob(os.path.join(p, "*.mpr"))
        if len(mprs) != 1:
            sys.exit(f"smokewalk_gen: {p}: expected one .mpr, found {len(mprs)}")
        p = mprs[0]
    pages, microflows, prof, sec, roles = build(p)
    guest = sec.get("GuestUserRole") if sec.get("EnableGuestAccess") else None
    names = args.role or [r for r in roles if r != sec.get("GuestUserRole")]
    plan = {"project": os.path.abspath(p), "login_page": ((prof.get("LoginPageSettings") or {}).get("Form") or ""),
            "admin_role": sec.get("AdminUserRole"), "guest_role": guest, "roles": []}
    for r in names:
        if r not in roles:
            sys.exit(f"smokewalk_gen: unknown user role {r}")
        plan["roles"].append(plan_for_role(r, pages, microflows, prof, roles))
    json.dump(plan, open(args.out, "w"), indent=1)
    for r in plan["roles"]:
        k = [s["kind"] for s in r["steps"]]
        print(f"{r['role']}: {k.count('page')} page steps, {k.count('microflow')} microflow steps, "
              f"{len(r['skipped'])} steps skipped (need an object, not allowed, or excluded)")
        w = microflow_warning(r)
        if w:
            print(f"WARN {r['role']}: {w}")
    print(f"plan: {args.out}")


if __name__ == "__main__":
    main()
