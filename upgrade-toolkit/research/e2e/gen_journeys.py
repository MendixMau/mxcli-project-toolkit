#!/usr/bin/env python3
"""Turn an impact map (impact_map.py --out) into journeys in the shared journey-runner format.

    gen_journeys.py <impact.json> --out-dir DIR [--create SPEC.json] [--roles-with-users A,B] [--mfa-probe-role ROLE]

Baseline (before the upgrade exists): map the old project against itself (impact_map.py old old) and run this
on it; you get the always-on set only. On E1 that set was identical to the one generated from the upgrade map.

Writes, in DIR:
  journeys/<role>/<id>.journey.json   one folder per role, because journey-runner.js logs in ONCE per
                                      invocation as TEST_USER; the driver runs each folder with that
                                      role's credentials.
  plan.json                           what was generated, for which role, from which candidate, and the
                                      candidates that are NOT browser journeys (startup log, scheduled
                                      events, services, screenshots) with the check the gate runs instead.

Format: exactly the keys journey-runner.js parses (id, title, persona, requirement, seeds, steps[name,
actions, ui{ready, checks, textPresent, textAbsent}, data{creates, delta, scope, oql}], outcome).
Keys starting with "_" are ignored by the runner; "_run" and "_why" carry the role and the reason.

Always-on set, whatever changed:
  login-<role>     per role with a user: the role home renders (landing guard is a widget the login page
                   and guest home do NOT render), the role's top menu captions are shown and the captions
                   of pages it may not open are not.
  mfa-password-only-refused
                   when an MFA module is present: a user with an MFA type signs in on the model login page
                   with the password only and must NOT get in. Runs logged in as an ordinary role user first
                   (the runner always logs in), then signs out and signs in as the MFA user (_run.mfaUser).
  create-save      one core create-and-save per app. The widget names cannot be guessed safely, so this
                   comes from --create SPEC.json (written once per app at baseline); without it the plan
                   lists it as TODO, never as covered.
"""
import argparse, json, os, re, sys
from pathlib import Path

GENERIC = re.compile(r"^[a-z]+[A-Z]?[a-zA-Z]*\d+$")


def landing_selector(role_facts):
    lw = (role_facts.get("landing") or {}).get("widget")
    return f".mx-name-{lw}" if lw else ".mx-page"


def journey(jid, title, role, why, steps, requirement=None):
    return {"id": jid, "title": title, "persona": role, "requirement": requirement or [],
            "_run": {"role": role}, "_why": why, "steps": steps}


def page_texts(model, qn, depth=4):
    """Every translated text on a page, its layout and their snippets: what body.innerText can contain."""
    if model is None or not qn:
        return []
    seen, frontier, texts = {qn}, [qn], []
    for _ in range(depth):
        nxt = []
        for q in frontier:
            for r in model.refs(q):
                d = model.docs.get(r)
                if d and d.type in ("Forms$Snippet", "Forms$Layout") and r not in seen:
                    seen.add(r)
                    nxt.append(r)
        frontier = nxt

    def walk(x):
        if isinstance(x, dict):
            if x.get("$Type") == "Texts$Translation" and isinstance(x.get("Text"), str):
                texts.append(x["Text"])
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    for q in seen:
        walk(model.docs[q].data)
    return texts


def login_journey(role, f, reasons, model=None):
    ui = {"ready": landing_selector(f)}
    # Menu captions: shown vs hidden for this role. The runner matches substrings of body.innerText, so a
    # hidden caption is dropped when it is a substring of a shown caption or of any text the home page
    # itself renders (E1: hidden "Home" is also the home page title, "Account" is inside "MyAccount").
    shown = list(f.get("menu_visible") or [])
    page_txt = page_texts(model, f.get("home_page"))
    hidden = [h for h in (f.get("menu_hidden") or [])
              if not any(h in s for s in shown) and not any(h in t for t in page_txt)]
    if shown:
        ui["textPresent"] = shown
    if hidden:
        ui["textAbsent"] = hidden
    step = {"name": f"{role} home after login", "actions": [], "ui": ui}
    return journey(f"login-{role}", f"Login as {role} lands on {f.get('home_page') or 'the role home'} with the role menu",
                   role, reasons, [step], [f"role:{role}"])


def mfa_journey(role, f, login, sign_out_path, reasons):
    """Sign out, sign in again as a user who has an MFA type, with the password only. That must NOT let the
    user in: the login page stays and none of the role menu renders. Measured on E1 (MFAmodule 5): with
    EnabledMFA true the password-only login answers 401 and the page stays; with false the user is let in."""
    if not (login.get("id") and login.get("password") and login.get("button")):
        return None, "model login page has no id/password/button widgets; MFA journey not generatable (default login.html: write it by hand)"
    actions = []
    if sign_out_path:
        actions.append({"do": "nav", "group": sign_out_path[0] if len(sign_out_path) > 1 else None,
                        "item": sign_out_path[-1], "settleMs": 5000, "label": "Sign out"})
    actions += [
        {"do": "fill", "widget": login["id"], "value": "${MFA_USER}", "label": "user name"},
        {"do": "fill", "widget": login["password"], "value": "${MFA_PASS}", "label": "password"},
        {"do": "click", "widget": login["button"], "settleMs": 6000, "label": "Sign in"},
    ]
    shown = f.get("menu_visible") or []
    steps = [
        {"name": "signed out: login page shown, role menu gone",
         "actions": actions[:1], "ui": {"ready": f".mx-name-{login['button']}", **({"textAbsent": shown} if shown else {})}},
        {"name": "MFA user with password only is not let in",
         "actions": actions[1:],
         "ui": {"ready": f".mx-name-{login['button']}", **({"textAbsent": shown} if shown else {})}},
    ]
    j = journey("mfa-password-only-refused", "A user with an MFA type is not let in with the password alone",
                role, reasons, steps, ["auth:mfa"])
    # ${MFA_USER} / ${MFA_PASS} are replaced by the driver in its run copy (no credentials in the file).
    # No seed: seeds need the runner's OQL instrument (mxcli oql --direct), which only answers on a runtime
    # booted with the live-preview dev flags; a gate app started by the toolkit has none (measured on E1).
    j["_run"]["mfaUser"] = True
    return j, None


def create_journey(spec):
    """spec: {role, nav:{group,item}, newButton, fields:[{widget,value}], saveButton, entity, ready}."""
    acts = [{"do": "nav", "group": spec["nav"].get("group"), "item": spec["nav"]["item"]},
            {"do": "click", "widget": spec["newButton"], "label": "New"}]
    acts += [{"do": "fill", "widget": f["widget"], "value": f["value"]} for f in spec.get("fields", [])]
    acts += [{"do": "click", "widget": spec["saveButton"], "label": "Save"}]
    step = {"name": f"create and save one {spec['entity']}", "actions": acts,
            "ui": {"ready": spec.get("ready") or ".mx-page"},
            "data": {"creates": spec["entity"], "delta": 1, "scope": {"newRowsBy": "id"}}}
    return journey("create-save", f"Core create-and-save: {spec['entity']}", spec["role"],
                   ["always-on: one core create-and-save per app"], [step], ["core:create-save"])


ERROR_TEXT = ["An error occurred", "You do not have access", "Access denied"]


def page_landing(model, qn):
    """Landing guard for a menu target: a named widget on the target page (or the page a microflow opens)."""
    if model is None or not qn:
        return None
    import impact_map as I
    d = model.docs.get(qn)
    if d is None:
        return None
    if d.type != "Forms$Page":  # microflow target: the first page it shows
        qn = next((r for r in model.refs(qn) if (model.docs.get(r) and model.docs[r].type == "Forms$Page")), None)
        if not qn:
            return None
    lw = I.landing_widget(model, qn)
    return lw["widget"] if lw else None


def menu_journey(cand, role, model):
    item = cand.get("menu")
    if not item:
        return None
    lw = page_landing(model, cand.get("target"))
    ui = {"ready": f".mx-name-{lw}" if lw else ".mx-page", "textAbsent": ERROR_TEXT}
    return journey(re.sub(r"[^A-Za-z0-9_.-]", "_", cand["id"]) + f"-{role}", cand["title"], role, cand.get("reasons", []),
                   [{"name": f"open {' > '.join(item)}", "actions": [
                       {"do": "nav", "group": item[0] if len(item) > 1 else None, "item": item[-1], "settleMs": 3000}],
                     "ui": ui}], [f"impact:{cand['id']}"])


NON_BROWSER = {
    "startup": "start log: the after-startup flow ran with no new ERROR and the module's own 'active' lines match the baseline (log diff, gate step 4)",
    "scheduled": "scheduled event: confirm it exists or is intentionally removed; run it once by its microflow on the new app and diff the log",
    "service": "published service: REST check (status + contract diff) already in the gate; add a call per changed operation",
    "visual": "screenshot every listed page per role on old and new and compare (smoke walk with screenshots)",
    "module-pages": "open each listed vendor page as the role that may open it, screenshot old vs new; empty charts or blank grids are the finding",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("impact")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--create", help="create-and-save spec JSON for this app")
    ap.add_argument("--roles-with-users", help="comma list; journeys only for roles that have a test user")
    ap.add_argument("--mfa-probe-role", help="ordinary role to log in as before the MFA sign-in (default: first non-admin role with users)")
    a = ap.parse_args()

    m = json.load(open(a.impact))
    roles = m["roles"]
    guest = m["user_roles"].get("guest")
    have = [r.strip() for r in a.roles_with_users.split(",")] if a.roles_with_users else [r for r in roles if r != guest]
    out = Path(a.out_dir)
    plan = {"impact": a.impact, "journeys": [], "not_browser": [], "todo": [], "skipped": []}

    def emit(j):
        d = out / "journeys" / j["_run"]["role"]
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{j['id']}.journey.json").write_text(json.dumps(j, indent=2, ensure_ascii=False) + "\n")
        plan["journeys"].append({"id": j["id"], "role": j["_run"]["role"], "why": j.get("_why", [])[:4]})

    cands = {c["id"]: c for c in m["candidates"]}
    model = None
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import mprmodel
        model = mprmodel.Model.load(m["new"])
    except Exception as e:  # journeys still generate; menu guards fall back to .mx-page
        print(f"note: new model not loaded ({e}); menu landing guards fall back to .mx-page", file=sys.stderr)
    login_reasons = (cands.get("login-per-role") or {}).get("reasons", ["always-on: login per role"])
    for r in roles:
        if r == guest:
            continue
        if r not in have:
            plan["skipped"].append({"id": f"login-{r}", "why": "no test user for this role (INVALID in the gate, not PASS)"})
            continue
        emit(login_journey(r, roles[r], login_reasons[:6], model))

    if m.get("auth", {}).get("modules") and any(x in " ".join(m["auth"]["modules"]) for x in ("MFA", "GoogleAuth", "TOTP")):
        probe = a.mfa_probe_role or next((r for r in have if r in roles and not roles[r].get("is_admin")), None)
        if probe:
            j, err = mfa_journey(probe, roles[probe], m.get("login", {}), roles[probe].get("sign_out_item"),
                                 (cands.get("mfa") or {}).get("reasons", ["always-on: MFA module present"])[:6])
            if j:
                emit(j)
            else:
                plan["todo"].append({"id": "mfa-challenge", "why": err})

    if a.create:
        emit(create_journey(json.load(open(a.create))))
    else:
        plan["todo"].append({"id": "create-save", "why": "no --create spec: write one core create-and-save spec per app at baseline (widget names are app-specific)"})

    for c in m["candidates"]:
        k = c["kind"]
        if c["id"] in ("login-per-role", "mfa"):
            continue
        if k == "menu":
            for r in [x for x in c.get("roles", []) if x in have][:1]:
                j = menu_journey(c, r, model)
                if j:
                    emit(j)
            if not [x for x in c.get("roles", []) if x in have]:
                plan["skipped"].append({"id": c["id"], "why": f"no test user for any of {c.get('roles')}"})
        elif k == "home":
            plan["todo"].append({"id": c["id"], "why": "role home: covered by login-<role> for that role (guest home: by mfa-challenge step 1)"})
        elif k in ("page", "client_microflow"):
            plan["todo"].append({"id": c["id"], "why": "no menu item reaches it; needs a hand-written step from the page that opens it"})
        else:
            key = next((n for n in NON_BROWSER if k.startswith(n) or c["id"].startswith(n)), None)
            plan["not_browser"].append({"id": c["id"], "priority": c.get("priority"), "check": NON_BROWSER.get(key, "manual check"),
                                        "targets": c.get("targets", [])[:20]})
    (out / "plan.json").write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(plan['journeys'])} journeys, {len(plan['not_browser'])} non-browser checks, "
          f"{len(plan['todo'])} todo, {len(plan['skipped'])} skipped -> {out}")


if __name__ == "__main__":
    main()
