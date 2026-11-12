#!/usr/bin/env python3
"""Turn an impact map (impact_map.py --out) into journeys in the shared journey-runner format.

    gen_journeys.py <impact.json> --out-dir DIR [--create SPEC.json] [--roles-with-users A,B] [--mfa-probe-role ROLE]
    gen_journeys.py [<impact.json>] --actions actions.json --out-dir DIR [--create SPEC.json] [--data-rung] ...

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
                   and guest home do NOT render, that renders once on the page: never a page parameter, a
                   snippet call or anything inside a list view, grid, gallery or pluggable widget; T1-25,
                   T2-10, T4-7), the role's top menu captions are shown (only when the home layout renders
                   the profile menu, T6-14) and the captions of pages it may not open are not (only when the
                   model proves they cannot occur on the role's home page, else omitted: T2-10, T4-6). A
                   role home that is a microflow is closed by this journey ("closes", T4-8, T6-14) when every page
                   it shows has a landing widget (then that widget is the guard, error texts asserted absent).
                   The pages it shows are found through its sub-microflow calls too (3 levels, T6R-3b).
  mfa-password-only-refused
                   when an MFA module is present: a user with an MFA type signs in on the model login page
                   with the password only and must NOT get in. Runs logged in as an ordinary role user first
                   (the runner always logs in), then signs out and signs in as the MFA user (_run.mfaUser).
  sign-out         per app, as the first role with a user and a sign-out menu item: sign out, the login
                   page renders and the role menu is gone (E5b 6). Without one in the profile menu, the home
                   layouts are scanned: a menu bar item (menu document or another profile) or a button whose
                   action is sign-out (T2-11).
  create-save      one core create-and-save per app. The widget names cannot be guessed safely, so this
                   comes from --create SPEC.json (written once per app at baseline; "path" lists the clicks between the
                   menu item and the New button when no menu item opens the list page); without it the plan
                   lists it as TODO, never as covered. The spec may carry textPresent (the saved value; use
                   ${RUN_ID} in a field value and in textPresent so a reused DB cannot satisfy it, E5b 25) and
                   textAbsent (validation messages), because a ready selector alone passed a refused save in
                   E5b (the grid behind the popup matched). The data rung (row count +1) is left out unless
                   --data-rung: it is asked through the app's Postgres (run_journeys.py --psql / UPG_PSQL,
                   E2E-9), because mxcli oql --direct is not answered by a runapp runtime (E5b 11). A field may
                   name the attribute it writes ("attr"); with --data-rung each such field adds an own-row
                   check, COUNT(*) WHERE <attr> = '<value>' = 1, so the run's own ${RUN_ID} row is what is
                   judged, not any row a previous run left (E2E-9).

Generated actions (--actions actions.json, from action_inventory.py on the OLD model; E2E-10). N3-21: 7 journeys for
a 31-page, 6-role app, because only the always-on set was generated and every action needed a hand-written journey.
  act-<action id>  one per action without a todo, as the role the inventory walked its path as (path_role), in that
                   role's folder. One step per page on the way: the entry (the role home, or the menu item by caption),
                   then each click of the path, each step guarded by the widget the next click needs, so a broken hop
                   fails where it breaks. Inside a list the click follows the inventory's click plan: "row" clicks the
                   first row (a row on-click, or a classic grid's selection before its control-bar button). The last
                   step fills the form when the action writes (save, or a flow that commits, changes a status, runs a
                   workflow or task outcome, or the page edits an object an earlier click created: a wizard, PR-F27):
                   text of a String attribute U-${RUN_ID}-n (n counts per run, so every
                   value is unique), Integer/Long n, Decimal n.5, a date picker 15 January next year in its format (en_US
                   order for Date/DateTime: stated in "_assumes"), an enumeration drop-down its first value's caption,
                   a reference drop-down its first option ("select" with "first": an empty list is a fixture gap, an
                   error, never a pass). Not filled, listed in "_unfilled" with the reason: hidden fields (conditional
                   visibility, a later tab page), read-only or conditionally editable ones, check boxes (no value is
                   safe: PR's Account_Edit has System.User.Blocked), radio buttons, reference sets, file uploads,
                   comboboxes, Form-mode reference selectors, a type the model does not tell. Then the click, and the
                   confirmation dialog when the action asks for one. Guard: the target page's landing widget for
                   open-page and create; for save the widget that opened the form; else .mx-page, and "_guard" says
                   it is weak. With --data-rung each filled String field with a known attribute (no association, not a
                   password, a value that fits) adds the E2E-9 own-row check when the action commits, the way a
                   --create spec field with "attr" does: COUNT(*) FROM <its entity> WHERE <attr> = '<value>' = 1.
                   "_destructive" marks a delete (it removes the first row it is given) or a workflow operation
                   (PR-F35); run_journeys.py walks those needing data last. PR-P4: a delete the inventory scopes as
                   identity, delete-all or reimport (it wipes or reseeds shared data) also carries "_scope" and
                   "resetsData": true, the tag journey-proof.md reads; run_journeys.py runs it after the main set, counted
                   apart. The k-th workflow operation of a role (Abort, Pause, ...) opens row k of the workflow list
                   ("nth" on its row step), so each takes its own instance instead of the first for all.
  skipped          every action with a todo (combobox, page-parameter, external-call, no-click-path, no-role,
                   unknown-action), or whose role has no test user, or whose path starts at the login page, in another
                   navigation profile or at an icon-only menu item: one entry each with the reason ("reasons", "why"),
                   INVALID in the gate. Never dropped: journeys + skipped + override = actions found (asserted).
  --create         wins per action: the spec's create-save journey covers the actions it walks (its "action"/"actions"
                   ids, else the newButton's create and the saveButton on the page it opens): they are "covered" with
                   closed_by create-save, and the journey "closes" them, so they take its verdict. A spec that matches
                   no action is kept, with a warning. With --actions a missing --create is no longer a todo.
  plan "actions"   found, generated, override, not_generated_by_reason and the line
                   "actions A found · G generated · O by --create override · S not generated by reason r n, ..."
Without an impact map only the action journeys are made (no login, menu or sign-out journeys); without
--roles-with-users every path role is assumed to have a test user (a role without one fails at login, loudly).

plan.json keys:
  journeys      generated
  skipped       INVALID in the gate: a role without a test user, an anonymous role (needs an anonymous
                journey, E4 11), a menu item no tested role can open
  todo          INVALID in the gate: needs a hand-written journey (a page reached from another page)
  covered       listed only: a role home that login-<role> already walks; a microflow home carries
                "closed_by" and takes that login journey's verdict in the run (T4-8); a microflow
                home whose pages have no landing widget stays a todo. The pages of a microflow home or menu
                target include those of the microflows it calls, 3 levels deep (T6R-3b); a home whose page is
                still not resolved stays a todo whose "why" says so (never "no login journey" when it has one)
  unreachable   listed only: a changed page or client microflow that no menu item, home page or login page
                reaches through any chain of callers (E5b 22); report it, it cannot block the gate
  not_browser   checks the gate runs instead (log, REST, scheduled events, screenshots); an API-only role, whose
                home page is a login form, is listed here as login-<role> instead of a login journey (T8R B2-3)
  anonymous_role the guest role when guest access is on, else null. The gate needs one anonymous process for it (S):
                run_journeys.py prints "anonymous process: P of 1 required" and blocks at 0
"""
import argparse, json, os, re, sys, time
from pathlib import Path

STANDIN = False   # --standin (set in main): an external-call todo alone does not skip an action

GENERIC = re.compile(r"^[a-z]+[A-Z]?[a-zA-Z]*\d+$")


def landing_selector(role_facts):
    lw = (role_facts.get("landing") or {}).get("widget")
    return f".mx-name-{lw}" if lw else ".mx-page"


def journey(jid, title, role, why, steps, requirement=None):
    return {"id": jid, "title": title, "persona": role, "requirement": requirement or [],
            "_run": {"role": role}, "_why": why, "steps": steps}


def translations(x):
    """Every Texts$Translation text under x."""
    out = []
    if isinstance(x, dict):
        if x.get("$Type") == "Texts$Translation" and isinstance(x.get("Text"), str):
            out.append(x["Text"])
        for v in x.values():
            out += translations(v)
    elif isinstance(x, list):
        for v in x:
            out += translations(v)
    return out


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


# N1R2-3: texts a page model holds that body.innerText does not show when the page opens: a placeholder is an input
# attribute ("Type search text here..."), a tooltip shows on hover, an action's texts (show message, validation
# feedback, confirmation) only after a click, and the page Title only through a page title widget.
NOT_ON_SCREEN_KEY = re.compile(r"Placeholder|Tooltip|Action$|^Title$")


def _pick_text(x, lang):
    items = x.get("Items") if isinstance(x.get("Items"), list) else []
    tr = [t for t in items if isinstance(t, dict) and isinstance(t.get("Text"), str) and t["Text"].strip()]
    pick = next((t for t in tr if t.get("LanguageCode") == lang), tr[0] if tr else None)
    return pick["Text"].strip() if pick else ""


def home_texts(model, qn, limit=2, lang="en_US"):
    """Distinctive texts on the home page itself (not its layout): what a role home with no menu shows (E4 12).
    One translation per text (lang, else the first), longest first: a sentence is a better guard than a button.
    Only texts that render when the page opens (impact_map.walk_rendered: nothing under a conditional, desktop-hidden,
    repeating or pluggable widget, nothing on a tab page not shown first) and only keys whose text is on screen
    (NOT_ON_SCREEN_KEY). The page Title counts only when a page title widget (on the page or its layout) or a popup
    layout's dialog header renders it.
    N1R2-3: "Type search text here..." (a text box placeholder) and "Home" (the page Title, no title widget on the
    page) were asserted and both login journeys FAILed on the unchanged OLD Opcenter app."""
    if model is None or not qn or qn not in model.docs:
        return []
    import impact_map as I
    out = []

    def add(t):
        if 3 <= len(t) <= 120 and "{" not in t and "%" not in t and "\n" not in t and t not in out:
            out.append(t)

    def visit(x, depth, blocked):
        if not blocked and x.get("$Type") == "Texts$Text":
            add(_pick_text(x, lang))
    I.walk_rendered(model.docs[qn].data, visit, lambda k: bool(NOT_ON_SCREEN_KEY.search(k)))
    page = model.docs[qn].data
    tw = [w for w, _ in I.guard_widgets(model, qn) if I.TITLE.search(w.get("$Type", ""))]
    tw += [w for q in I.layout_closure(model, qn) for w, _ in I.guard_widgets(model, q) if I.TITLE.search(w.get("$Type", ""))]
    # a popup layout shows the page Title in the dialog header (11.12 Atlas_Core.PopupLayout: Content.LayoutType "ModalPopup")
    popup = any("Popup" in str((model.docs[q].data.get("Content") or {}).get("LayoutType") or model.docs[q].data.get("LayoutType") or "")
                for q in I.layout_closure(model, qn))
    if (tw or popup) and isinstance(page.get("Title"), dict):
        add(_pick_text(page["Title"], lang))
    return sorted(out, key=len, reverse=True)[:limit]


def fix_landing(model, f, login):
    """An impact.json written before the fix may carry a landing widget the guard rules now refuse: a name the layout
    also uses (E5b: the page's "container1" and a hidden layout container), a page parameter (T4-7), a snippet call
    (T2-10), a widget inside a list view or grid row (T1-25), on a tab page not shown first or hidden on desktop (G-3),
    or a data view where the page has a title widget (B2-2: a data view can be in the DOM with zero height). Pick again
    on the loaded model."""
    import impact_map as I
    home, lw = f.get("home_page"), (f.get("landing") or {}).get("widget")
    if model is None or home not in model.docs:
        return f
    pre = {login.get(k) for k in ("id", "password", "button") if login.get(k)}
    pre |= {x.get("widget") for x in login.get("other_text_boxes") or []}
    new = I.landing_widget(model, home, pre)
    dv_over_title = ((f.get("landing") or {}).get("type") == "Forms$DataView" and bool(new)
                     and bool(I.TITLE.search(new.get("type") or "")))
    if lw and lw in I.guard_names(model, home) and not dv_over_title:
        return f
    if not new and lw and (I.NON_RENDERING_NAME.match(lw) or I.NON_RENDERING.search((f.get("landing") or {}).get("type") or "")):
        # T7: the only landing the impact.json knew is a widget that draws nothing (Set URL, timer, listen-to): no guard
        return dict(f, landing=None, _landing_was=lw, _landing_why="draws no element of its own (T7); the guard falls back to .mx-page")
    if new and new.get("widget") != lw:
        lay = {w["Name"] for q in I.layout_closure(model, home) for w in model.widgets(q) if isinstance(w.get("Name"), str)}
        why = ("is also a layout widget name" if lw in lay else
               "is a data view and the page has a title widget: a data view can be in the DOM with zero height and "
               "fail the visibility check on a healthy app (B2-2)" if dv_over_title else
               "is not a widget that renders once on the page (a page parameter or variable, a snippet call, inside "
               "a list view, grid, gallery or pluggable widget, on a tab page not shown first, or hidden on desktop: "
               "T1-25, T2-10, T4-7, G-3)")
        f = dict(f, landing=new, _landing_was=lw, _landing_why=why)
    return f


def role_home_pages(model, f):
    """The pages a role lands on: its home page, or every page its home microflow shows (T4-8, T6-14)."""
    if f.get("home_page"):
        return [f["home_page"]]
    return shown_pages(model, f.get("home_microflow")) if f.get("home_microflow") else []


def menu_profile(model):
    """Name of the navigation profile the role menu captions come from (impact_map.role_facts: the Responsive one)."""
    nav = model.navigation() if model is not None else {}
    return next((k for k, v in nav.items() if (v.get("kind") or "").lower().startswith("responsive")), next(iter(nav), None))


def unknown_role_captions(model, profile):
    """Top-level captions with a target whose user roles the model cannot tell (a page or microflow of a protected
    add-on module that is not in the model: T2-10 asserted the Administrator's own "Client Configuration" absent)."""
    import impact_map as I
    roles, out = I.Roles(model), set()
    for it in model.navigation().get(profile, {}).get("menu", []):
        t = it.get("target")
        if t and (t not in model.docs or not roles.of_doc(t)):
            out.add(it["path"][0])
    return out


def login_form_home(model, f, login):
    """T8R B2-3: the role's home page is a login page (the navigation login page, or a page whose snippet closure holds
    a password box): a user of the role signs in and lands on a login form again, so no browser journey can show a
    signed-in home (an API-only role such as FSM's FSMAPIConsumer). Returns the reason, else None."""
    home = f.get("home_page")
    if not home:
        return None
    if home == (login or {}).get("login_page"):
        return f"its home page {home} is the login page"
    if model is None or home not in model.docs:
        return None
    import impact_map as I
    for d in I.snippet_closure(model, home):
        if any(w.get("$Type") == "Forms$PasswordTextBox" for w in model.widgets(d)):
            return f"its home page {home} holds a login form (password box{'' if d == home else ' in snippet ' + d})"
    return None


def login_journey(role, f, reasons, model=None, old=None):
    ui = {"ready": landing_selector(f)}
    home = f.get("home_page")
    profile = menu_profile(model)
    if model is not None and home in model.docs:
        import impact_map as I
        src = I.nav_sources(model, home)
        other = bool(src) and not any(k == "profile" and n in (None, profile) for k, n in src) \
            and not any(k == "unknown" for k, _ in src)
        if not I.has_navigation(model, home) or other:
            # the home layout renders no menu (popup or bare layout), or another menu than the role's navigation
            # profile (T6-14: a Phone/Tablet layout renders the Phone_Menu document): the profile captions cannot be
            # on screen, so assert the page's own texts instead (E4 12, E5b 10)
            txt = home_texts(model, home)
            why = "layout has no menu" if not src else "layout renders another menu than the " + str(profile) + " profile"
            step = {"name": f"{role} home after login ({why})", "actions": [],
                    "ui": dict(ui, **({"textPresent": txt} if txt else {}), textAbsent=ERROR_TEXT)}
            j = journey(f"login-{role}", f"Login as {role} lands on {home} ({why}: page texts asserted)",
                        role, reasons, [step], [f"role:{role}"])
            j["_home_without_menu"] = True
            return j
    # Menu captions: shown vs hidden for this role. The runner matches substrings of body.innerText, so a
    # hidden caption is dropped when it is a substring of a shown caption or of any text the role's own home page
    # renders (the page, its layouts, snippets and the menu documents its layout menu bars show), compared without
    # case (E1: hidden "Home" is also the home page title, "Account" is inside "MyAccount"; T4-6: "Buffer" is another
    # role's menu caption AND a label on every Kanban card of this role's home).
    # textAbsent is asserted only when the model proves it: every home page renders the role's profile menu, and
    # every target of the caption has known roles. When unsure it is omitted: a false FAIL on a healthy app costs
    # more than a missing absent-check (T2-10, T4-6, T6-14).
    # A microflow home is never proven: the page it ends on may come from a sub-microflow (T4-6 was such a home).
    shown = list(f.get("menu_visible") or [])
    hidden = []
    pages = [home] if home else []
    if model is not None and pages and all(p in model.docs for p in pages):
        import impact_map as I
        srcs = [I.nav_sources(model, p) for p in pages]
        proven = all(any(k == "profile" and n == profile for k, n in s) for s in srcs)
        if proven:
            txt = [t.lower() for p in pages for t in page_texts(model, p)]
            # a menu document a layout menu bar renders is on screen too (its captions are texts of this home)
            txt += [t.lower() for s in srcs for k, q in s if k == "menu" and q in model.docs for t in translations(model.docs[q].data)]
            unknown = unknown_role_captions(model, profile)
            hidden = [h for h in (f.get("menu_hidden") or []) if h not in unknown
                      and not any(h.lower() in s.lower() for s in shown) and not any(h.lower() in t for t in txt)]
    # N1-3: a caption is asserted only when the page actually reached after login is PROVEN to render this profile's
    # menu (every home page's layout has a menu widget on the profile source). A layout whose menu source is unknown,
    # another menu document, or a home the model cannot show: no textPresent; the READY selector decides.
    menu_proven = False
    if model is not None:
        import impact_map as I
        hp = role_home_pages(model, f)
        menu_proven = bool(hp) and all(p in model.docs and any(k == "profile" and n in (None, profile)
                                                               for k, n in I.nav_sources(model, p)) for p in hp)
    if shown and not menu_proven:
        notproven = list(shown)
    else:
        notproven = []
    if shown and menu_proven:
        ui["textPresent"] = shown
    if hidden:
        ui["textAbsent"] = hidden
    step = {"name": f"{role} home after login", "actions": [], "ui": ui}
    j = journey(f"login-{role}", f"Login as {role} lands on {f.get('home_page') or f.get('home_microflow') or 'the role home'} with the role menu",
                role, reasons, [step], [f"role:{role}"])
    if notproven:
        j["_textPresent_omitted"] = (f"{notproven[:8]}: not asserted present, the model does not prove the page reached "
                                     "after login renders this menu; the ready selector decides (N1-3)")
    dropped = [h for h in (f.get("menu_hidden") or []) if h not in hidden]
    if dropped:
        j["_textAbsent_omitted"] = (f"{dropped[:8]}: not asserted absent, the model does not prove they cannot occur on "
                                    "this role's home (T2-10, T4-6, T6-14)")
    mf = f.get("home_microflow") if not f.get("home_page") else None
    if mf and model is not None and mf in model.docs:
        # T4-8, T6-14: the login journey walks the role home microflow (it runs at sign-in) and closes that home
        # candidate, but only with a guard that proves the microflow's page opened: the landing widget of every page
        # it shows (page_landing, on both models), never the bare ".mx-page" + menu captions, which the layout of an
        # error or fallback page also satisfies. No such guard: no "closes", the home stays a todo.
        ready, branches, note = page_landing(model, mf, old)
        if ready and ready != ".mx-page":
            ui["ready"] = ready
            ui["textAbsent"] = hidden + ERROR_TEXT
            j["closes"] = [f"home:{mf}"]
            if branches:
                j["_branches"] = branches
            if note:
                j["_landing_note"] = note
        else:
            # T6R-3b: say exactly why the home cannot be closed, the todo carries this text
            pages, why = resolve_shown(model, mf)
            if not pages:
                j["_closes_not"] = f"home:{mf}: {why}; the home stays a todo"
            else:
                bare = [b["page"] for b in branches if not b.get("widget")] if branches else pages
                j["_closes_not"] = (f"home:{mf}: no landing widget on every page the microflow shows ({', '.join(pages)}; "
                                    f"none on {', '.join(bare)}); the home stays a todo")
    elif mf:
        j["_closes_not"] = (f"home:{mf}: " + ("the model was not loaded" if model is None else f"{mf} is not in the model")
                            + ", so the page it shows cannot be resolved; the home stays a todo")
    return j


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


def signout_journey(role, f, login):
    """Sign out from the role menu: the login page renders and the role menu is gone (E5b 6). A layout menu item with
    an empty caption on its path (T2R3-4: the Opcenter icon-only user dropdown) is opened by clicking the rendered
    item names in turn (sign_out_clicks: menuBar2-0, menuBar2-0-1), as the T2R3 hand journey did."""
    path, button, clicks = f.get("sign_out_item"), f.get("sign_out_button"), f.get("sign_out_clicks")
    if not path and not button and not clicks:
        return None
    ready = f".mx-name-{login['button']}" if login.get("button") else "#loginButton,.mx-name-loginButton,input[type=password]"
    shown = f.get("menu_visible") or []
    if path:
        acts = [{"do": "nav", "group": path[0] if len(path) > 1 else None, "item": path[-1], "settleMs": 5000, "label": "Sign out"}]
    elif clicks:
        acts = [{"do": "click", "widget": w} for w in clicks[:-1]]
        acts.append({"do": "click", "widget": clicks[-1], "settleMs": 5000, "label": "Sign out"})
    else:
        acts = [{"do": "click", "widget": button, "settleMs": 5000, "label": "Sign out"}]
    step = {"name": "sign out: login page shown, role menu gone", "actions": acts,
            "ui": {"ready": ready, **({"textAbsent": shown} if shown else {})}}
    j = journey("sign-out", f"Sign out as {role} returns to the login page", role, ["always-on: sign out"], [step],
                ["auth:sign-out"])
    if f.get("_sign_out_from"):
        j["_sign_out_from"] = f["_sign_out_from"]   # T2-11: found in a layout, not in the profile menu
    if f.get("_sign_out_by"):
        j["_sign_out_by"] = f["_sign_out_by"]       # B4T2-4: not the platform SignOut action, inferred
    return j


def create_journey(spec, data_rung=False):
    """spec: {role, nav:{group,item}, path?:[{widget,label?}], newButton, fields:[{widget,value,attr?}], saveButton,
    entity, ready, textPresent?, textAbsent?}. attr: the attribute of `entity` the field writes, for the own-row check
    (E2E-9). path: clicks between the menu item and the New button, for a list page that no menu item opens (R1,
    Purchase Request: Vendors overview is a link on the admin home page)."""
    acts = [{"do": "nav", "group": spec["nav"].get("group"), "item": spec["nav"]["item"]}]
    acts += [{"do": "click", "widget": c["widget"], "label": c.get("label") or c["widget"]} for c in spec.get("path", [])]
    acts += [{"do": "click", "widget": spec["newButton"], "label": "New"}]
    acts += [{"do": "fill", "widget": f["widget"], "value": f["value"]} for f in spec.get("fields", [])]
    acts += [{"do": "click", "widget": spec["saveButton"], "label": "Save"}]
    ui = {"ready": spec.get("ready") or ".mx-page"}
    for k in ("textPresent", "textAbsent"):
        if spec.get(k):
            ui[k] = spec[k]
    step = {"name": f"create and save one {spec['entity']}", "actions": acts, "ui": ui}
    if data_rung:
        step["data"] = {"creates": spec["entity"], "delta": 1, "scope": {"newRowsBy": "id"}}
        # E2E-9: +1 says some row arrived; the own-row check says it is THIS run's row with the typed value
        own = [{"label": f"the run's own row: {f['attr']} = {f['value']}", "expect": 1,
                "sql": f"SELECT COUNT(*) AS n FROM {spec['entity']} WHERE {f['attr']} = '{f['value']}'"}
               for f in spec.get("fields", []) if f.get("attr")]
        if own:
            step["data"]["oql"] = own
    j = journey("create-save", f"Core create-and-save: {spec['entity']}", spec["role"],
                ["always-on: one core create-and-save per app"], [step], ["core:create-save"])
    warn = []
    if not spec.get("textPresent"):
        warn.append("spec has no textPresent: the ready selector alone can pass a refused save (E5b 12); "
                    "add the saved value (with ${RUN_ID}) as textPresent")
    if data_rung and not any(f.get("attr") for f in spec.get("fields", [])):
        warn.append("no field names its attribute (\"attr\"): the data rung checks +1 only, not the run's own "
                    "${RUN_ID} row (E2E-9)")
    if warn:
        j["_warning"] = "; ".join(warn)
    return j


def entry_reach(model, excluded=()):
    """Documents reachable from the app's entry points (menu targets, home pages, login page) through refs.
    A caller that is not a page, snippet, layout, microflow or nanoflow (a service, scheduled event, workflow,
    project setting) also counts as an entry point."""
    nav = model.navigation()
    entries = set()
    for pr in nav.values():
        for h in pr.get("homes", []):
            entries.update(x for x in (h.get("page"), h.get("microflow")) if x)
        entries.update(x["target"] for x in pr.get("menu", []) if x.get("target"))
        if pr.get("login_page"):
            entries.add(pr["login_page"])
    flow = ("Forms$Page", "Forms$Snippet", "Forms$Layout", "Microflows$Microflow", "Microflows$Nanoflow")
    entries.update(q for q, d in model.docs.items() if d.type not in flow and d.module not in excluded)
    # F24: a page with a URL opens from the address bar or a bookmark, so it is never dead in the UI
    entries.update(q for q, d in model.docs.items() if d.type == "Forms$Page" and str((d.data or {}).get("Url") or "").strip())
    seen, frontier = set(entries), list(entries)
    while frontier:
        nxt = []
        for q in frontier:
            for r in model.refs(q):
                if r not in seen and r in model.docs:
                    seen.add(r); nxt.append(r)
        frontier = nxt
    return seen


def todo_closers(todo, actions, models, every=None):
    """F23 (Purchase Request 10.24, real run): with --actions, 17 impact todos ("no menu item reaches it") stayed INVALID
    while generated action journeys walked every one of them: the task pages on their click paths, the microflows as
    their click targets. Map each page:/client_microflow: todo to the first generatable action that walks it, as
    {action id: [todo ids]}; the journey then "closes" them and the todo takes that journey's verdict (never a PASS of
    its own). Walked: a page on the action's click path or its host page; a microflow the click runs (target); a
    microflow that a walked page or one of its snippets references but no click on them runs (a data source, which
    runs when the page renders: DS_GetWorkflowView_FromUserTask on the four task pages). `every` is the whole inventory:
    a click that runs a microflow is never a data source, whether or not its own journey could be generated."""
    want = {}
    for e in todo:
        kind, _, q = e["id"].partition(":")
        if kind in ("page", "client_microflow") and q:
            want.setdefault(q, e["id"])
    if not want:
        return {}
    clicked = {}
    for x in (every if every is not None else actions):
        if x.get("target"):
            clicked.setdefault(x.get("host"), set()).add(x["target"])

    def shown(page):  # the page and the snippets it shows (transitively), from any loaded model
        out, front = {page}, [page]
        while front:
            nxt = []
            for q in front:
                for mo in models:
                    for r in (mo.refs(q) if q in mo.docs else []):
                        d = mo.docs.get(r)
                        if d is not None and d.type == "Forms$Snippet" and r not in out:
                            out.add(r); nxt.append(r)
            front = nxt
        return out

    def data_sources(page):
        hosts = shown(page)
        runs = set().union(*(clicked.get(h, set()) for h in hosts))
        refs = set()
        for h in hosts:
            for mo in models:
                refs.update(mo.refs(h) if h in mo.docs else [])
        return refs - runs

    closes, done, ds_cache = {}, set(), {}
    for x in actions:
        pages = [s["page"] for s in (x.get("path") or []) if s.get("page")]
        if x.get("host_type") == "Page" and x.get("host"):
            pages.append(x["host"])
        walked = set(pages) | ({x["target"]} if x.get("target") else set())
        for pg in pages:
            if pg not in ds_cache:
                ds_cache[pg] = data_sources(pg)
            walked |= ds_cache[pg]
        hit = [want[q] for q in sorted(walked) if q in want and want[q] not in done]
        if hit:
            closes[x["id"]] = hit
            done.update(hit)
    return closes


ERROR_TEXT = ["An error occurred", "You do not have access", "Access denied"]

ASSIGNEES_EMPTY = re.compile(r"Assignees\s*=\s*empty", re.I)


def unassigned_only(x):
    """QW-2 (PR-F44 baseline, "Assign to me" cost 13): the action is the button that takes an unassigned task: its
    shown_if (own or on the recorded path) says `WorkflowUserTask_Assignees = empty`, or it calls an AssignToMe_* flow."""
    conds = list(x.get("shown_if") or []) + [c for h in x.get("path") or [] if h.get("id") == x.get("id")
                                             for c in h.get("shown_if") or []]
    return any(ASSIGNEES_EMPTY.search(c) for c in conds) or bool(re.search(r"AssignToMe", x.get("target") or ""))
def role_users(users, role):
    """How many users users.json lists for a role: an object is one, a list is its length, a missing role is None
    (unknown: the guard stays silent, it only speaks when it knows)."""
    v = (users or {}).get(role)
    if isinstance(v, list):
        return len(v)
    return 1 if isinstance(v, dict) and v else None


def task_list_hosts(doc):
    """Pages that list tasks for their participants: the hosts of an open-task action (Purchase Request: TaskInbox)."""
    return {x.get("host") for x in doc.get("actions", []) if x.get("action") == "open-task"}


def assign_to_me_dead(x, role, users, hosts=None):
    """True when x only renders for an unassigned task and the role has exactly one user: its tasks arrive assigned.
    hosts (task_list_hosts): when given, only a button reached through a participant's task list counts. PRF-2, Purchase
    Request: the Administrator's "Assign to user" (Snip_UserTaskView_Details.actionButton10) sits on the workflow admin
    pages, which list every task, assigned or not; it PASSED on the old app and must not be called dead."""
    if not (bool(users) and unassigned_only(x) and role_users(users, role) == 1):
        return False
    return hosts is None or x.get("host") in hosts or any(
        h.get("page") in hosts or h.get("on") in hosts for h in x.get("path") or [])


# PR-P4: action_inventory.py "scope": the first three wipe or reseed shared data (run_journeys.py DESTRUCTIVE_SCOPES)
DESTRUCTIVE_SCOPES = ("identity", "delete-all", "reimport")
SCOPE_WHY = {"identity": "deletes accounts or what cascades to them: later logins may fail",
             "delete-all": "deletes every row of an entity it retrieves without a constraint",
             "reimport": "deletes and writes the same data again (a reset or import): the seed is not what it was"}


def both_landing(model, old, qn):
    """Landing widget of page qn that the OLD page also has (E6-18: SAML20 4.x redesigned its page; the new page's
    snippetCallWidget1 did not exist on the old app, so before-picked FAILed on a healthy page). Returns (widget or
    None, note). A page new in this upgrade, or no old model, keeps the new-model pick."""
    import impact_map as I
    if old is None or qn not in old.docs:
        lw = I.landing_widget(model, qn)
        return (lw["widget"] if lw else None), None
    # same name AND type on both pages; never a snippet call: its own element is not rendered the same way across
    # versions (E6: snippetCallWidget1 is on both SAMLConfigOverview pages, the old app rendered no element for it)
    on_old = {(w["Name"], w.get("$Type")) for w in old.widgets(qn) if isinstance(w.get("Name"), str)}
    only_new = {w["Name"] for w in model.widgets(qn) if isinstance(w.get("Name"), str)
                and ((w["Name"], w.get("$Type")) not in on_old or w.get("$Type") == "Forms$SnippetCallWidget")}
    lw = I.landing_widget(model, qn, only_new)
    if lw:
        return lw["widget"], None
    # inside the snippets the page calls, when the snippet is on both models (the E6 SAML page is one snippet call)
    lay = {w["Name"] for q in I.layout_closure(model, qn) for w in model.widgets(q) if isinstance(w.get("Name"), str)}
    for sn in I.snippet_closure(model, qn)[1:]:
        if sn not in old.docs:
            continue
        so = {(w["Name"], w.get("$Type")) for w in old.widgets(sn) if isinstance(w.get("Name"), str)}
        skip = lay | {w["Name"] for w in model.widgets(sn) if isinstance(w.get("Name"), str)
                      and ((w["Name"], w.get("$Type")) not in so or w.get("$Type") == "Forms$SnippetCallWidget")}
        lw = I.landing_widget(model, sn, skip)
        if lw:
            return lw["widget"], f"{qn}: landing guard {lw['widget']} is inside snippet {sn} (on both models)"
    first = I.landing_widget(model, qn)
    return None, (f"{qn}: no landing widget on both the old and the new page (new only: {first['widget']}); "
                  f"guard falls back to .mx-page" if first else None)


SUBFLOW_DEPTH = 3   # levels of sub-microflow calls followed to find the page a microflow shows (T6R-3b)


def resolve_shown(model, qn, depth=SUBFLOW_DEPTH):
    """(pages, why): the pages a menu target or role home opens, and why none could be resolved (None when found).
    A page is itself. A microflow shows every page it references and every page a microflow it calls references, up
    to `depth` levels of calls (T6R-3b: the T6R Admin, DepartmentManager and WebserviceUser homes called DeepLink and
    a sub-microflow before the page; reading only the home microflow found no page, and the todo then said "role home
    of a role with no login journey" although each role had one). Calls deeper than `depth` are not followed and the
    why says so: an unresolved home stays a todo, never a pass."""
    d = model.docs.get(qn) if model is not None and qn else None
    if d is None:
        return [], (f"{qn} is not in the model" if model is not None else "the model was not loaded")
    if d.type == "Forms$Page":
        return [qn], None
    pages, seen, frontier, cut = set(), {qn}, [qn], []
    for level in range(depth + 1):
        nxt = []
        for f in frontier:
            for r in sorted(model.refs(f)):
                rd = model.docs.get(r)
                if rd is None:
                    continue
                if rd.type == "Forms$Page":
                    pages.add(r)
                elif rd.type == "Microflows$Microflow" and r not in seen:
                    seen.add(r)
                    nxt.append(r)
        if level == depth:
            cut = nxt
        frontier = nxt
    if pages:
        return sorted(pages), None
    walked = len(seen) - 1 - len(cut)
    why = (f"microflow {qn} shows no page we can resolve: no show-page action in it"
           + (f" or in the {walked} microflow(s) it calls up to {depth} levels deep" if walked else " and it calls no microflow"))
    if cut:
        why += f"; calls deeper than {depth} levels not followed ({', '.join(cut[:4])})"
    return [], why


def shown_pages(model, qn):
    """Pages a menu target opens: the page itself, or every page a microflow target shows, sub-microflows included
    (sorted; resolve_shown, T6R-3b)."""
    return resolve_shown(model, qn)[0]


def page_landing(model, qn, old=None):
    """Landing guard for a menu target: (ready selector, branches, note).
    A microflow target that shows more than one page (E7-2: ACT_ProducerHomePage opens the team detail page with a
    team and the overview without one) gets a union selector of every branch's landing widget, so either branch
    passes and an error page still fails. A branch page without a usable widget makes it None: a todo, never a guess."""
    pages = shown_pages(model, qn)
    if not pages:
        return ".mx-page", [], None
    picks, notes = [], []
    for p in pages:
        w, note = both_landing(model, old, p)
        picks.append(w)
        if note:
            notes.append(note)
    if len(pages) == 1:
        return (f".mx-name-{picks[0]}" if picks[0] else ".mx-page"), [], (notes[0] if notes else None)
    branches = [{"page": p, "widget": w} for p, w in zip(pages, picks)]
    if not all(picks):
        return None, branches, "; ".join(notes) or None
    return ", ".join(f".mx-name-{w}" for w in picks), branches, "; ".join(notes) or None


def menu_journey(cand, role, model, old=None):
    """(journey or None, todo or None)."""
    item = cand.get("menu")
    if not item:
        return None, None
    ready, branches, note = page_landing(model, cand.get("target"), old)
    if ready is None:
        bare = [b["page"] for b in branches if not b["widget"]]
        return None, {"id": cand["id"], "role": role, "_branches": branches,
                      "why": f"menu target {cand.get('target')} shows {len(branches)} pages depending on its data "
                             f"({', '.join(b['page'] for b in branches)}) and {', '.join(bare)} has no landing widget "
                             f"on both models: write the journey by hand with the branch its test data takes"}
    ui = {"ready": ready, "textAbsent": ERROR_TEXT}
    j = journey(re.sub(r"[^A-Za-z0-9_.-]", "_", cand["id"]) + f"-{role}", cand["title"], role, cand.get("reasons", []),
                [{"name": f"open {' > '.join(item)}", "actions": [
                    {"do": "nav", "group": item[0] if len(item) > 1 else None, "item": item[-1], "settleMs": 3000}],
                  "ui": ui}], [f"impact:{cand['id']}"])
    if branches:
        j["_branches"] = branches
        j["_why"] = j.get("_why", []) + [f"{cand.get('target')} shows one of {len(branches)} pages; ready accepts any of them"]
    if note:
        j["_landing_note"] = note
    return j, None


# ---------------------------------------------------------------------------------------------- E2E-10: --actions
FILL_KINDS = {"commit", "status-change", "task-outcome", "workflow-call", "workflow-op"}
# PR-F25: dates go one year past generation, so a "must be in the future" rule holds (pipe-18 typed 1/15/2026 on
# 12 Oct 2026 and the wizard refused it). JOURNEY_YEAR pins it for reproducible output.
YEAR = int(os.environ.get("JOURNEY_YEAR") or time.localtime().tm_year + 1)
MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December"]


def act_id(action_id):
    return "act-" + re.sub(r"[^A-Za-z0-9_.-]", "_", action_id)


def date_value(fmt):
    """(value, None) or (None, why) for a date picker: 15 January of YEAR, 12:00, in the picker's format. The en_US
    defaults (M/d/yyyy, h:mm a) are an assumption about the test user's language, stated in the journey."""
    kind, custom = (fmt or {}).get("DateFormat") or "Date", (fmt or {}).get("Custom") or ""
    if kind == "Date":
        return f"1/15/{YEAR}", None
    if kind == "DateTime":
        return f"1/15/{YEAR} 12:00 PM", None
    if kind == "Time":
        return "12:00 PM", None
    if kind != "Custom" or not custom:
        return None, f"date format {kind} not known"
    tok = {"yyyy": str(YEAR), "yy": str(YEAR)[-2:], "y": str(YEAR), "MMMM": "January", "MMM": "Jan", "MM": "01", "M": "1",
           "dd": "15", "d": "15", "HH": "12", "H": "12", "hh": "12", "h": "12", "mm": "00", "m": "0", "ss": "00",
           "s": "0", "a": "PM"}
    out, bad = [], []
    for run in re.finditer(r"'[^']*'|([A-Za-z])\1*|[^A-Za-z']+", custom):
        t = run.group(0)
        if t.startswith("'"):
            out.append(t.strip("'"))
        elif t[0].isalpha():
            if t in tok:
                out.append(tok[t])
            else:
                bad.append(t)
        else:
            out.append(t)
    if bad:
        return None, f"custom date format {custom!r}: token(s) {', '.join(bad)} not generated"
    return "".join(out), None


def fill_field(f, n, password):
    """FN-7: a field inside a Gallery / Data grid 2 (action_inventory "in_list") is drawn once per
    item, so an empty list shows none: its fill is optional (the engine skips it when no such input is shown) and it gives
    no own-row check (the row exists only when the list had an item)."""
    acts, own, why = _fill_field(f, n, password)
    if f.get("in_list") and acts:
        acts = [dict(a, optional=True) if a.get("do") == "fill" else a for a in acts]
        own = None
    return acts, own, why


URL_NAME = re.compile(r"(url|uri)$", re.I)   # FN-11: ImageURL, ThumbnailURL, CallbackURL


def _fill_field(f, n, password):
    """One form field -> (actions, own-row attr or None, unfilled reason or None). n: this field's number in the run
    (U-${RUN_ID}-n). Never a guess: a field whose value cannot be chosen from the model is listed as unfilled."""
    w, inp, at = f.get("widget"), f.get("input"), f.get("attr_type") or {}
    typ = at.get("type")
    if not w:
        return [], None, "widget has no name"
    if f.get("hidden"):
        return [], None, f["hidden"]
    if f.get("editable") == "Never":
        return [], None, "read-only (Editable: Never)"
    if f.get("editable") == "Conditionally":
        return [], None, "editable only under a condition the model states in an expression: not generated"
    if inp == "text":
        if f.get("password") or typ == "HashString":
            return [{"do": "fill", "widget": w, "value": password}], None, None
        if typ == "String":
            v = f"U-${{RUN_ID}}-{n}"
            if URL_NAME.search((f.get("attribute") or "").rsplit(".", 1)[-1]):
                # FN-11: an attribute named *URL is often validated as a URL by the app's own save flow; a bare
                # U-<run>-n failed the save on the healthy OLD app. Same run-unique value, written as a URL.
                v = f"https://example.com/U-${{RUN_ID}}-{n}"
            if at.get("length") and at["length"] < len(v.replace("${RUN_ID}", "0000000000")):
                v = f"U{n}"[:at["length"]]
                return [{"do": "fill", "widget": w, "value": v}], None, None   # too short for the run id: no own row
            own = f["attribute"] if f.get("attribute") and not f.get("association") else None
            if at.get("persistable") is False:
                # PR-P5: a non-persistable entity has no table: "SELECT .. FROM WorkflowCommons.WorkflowCommentHelper" is
                # rejected ("OQL returned nothing"). Check the persistent attribute the flow copies it to, else nothing
                own = f.get("persisted_as")
            return [{"do": "fill", "widget": w, "value": v}], own, None
        if typ in ("Integer", "Long"):
            return [{"do": "fill", "widget": w, "value": str(n)}], None, None
        if typ == "Decimal":
            return [{"do": "fill", "widget": w, "value": f"{n}.5"}], None, None
        if typ == "AutoNumber":
            return [], None, "autonumber: the runtime sets it"
        return [], None, f"text box on a {typ or 'unknown'} attribute" + (f" ({at['why']})" if at.get("why") else "")
    if inp == "date":
        v, why = date_value(f.get("date_format"))
        return ([{"do": "fill", "widget": w, "value": v}], None, None) if v else ([], None, why)
    if inp == "toggle":
        # left as it is: a generated true can lock the run out (PR Account_Edit: checkBox1 is System.User.Blocked)
        return [], None, "check box left as it is: no value is safe to assume (Blocked, Active)"
    if inp == "select":
        if typ == "Enumeration" and at.get("enum_first_caption"):
            return [{"do": "select", "widget": w, "match": at["enum_first_caption"]}], None, None
        return [], None, f"drop-down on a {typ or 'unknown'} attribute: its option texts are not in the model"
    if inp == "reference":
        if (f.get("render") or "DropDown") == "DropDown":
            return [{"do": "select", "widget": w, "first": True}], None, None
        return [], None, f"reference selector rendered as {f.get('render')}: opens a select page, not generated"
    if inp == "combobox":   # PR-F25: journey-verbs.js "combo"; an enumeration by its first caption, else the first row
        if typ == "Enumeration" and at.get("enum_first_caption"):
            return [{"do": "combo", "widget": w, "match": at["enum_first_caption"]}], None, None
        return [{"do": "combo", "widget": w, "first": True}], None, None
    if inp == "file":   # PR-F44: journey-verbs.js upload, a generated .jpeg (no file from disk)
        return [{"do": "upload", "widget": w, "file": os.environ.get("UPG_UPLOAD_FILE") or "upg-seed.jpeg"}], None, None
    return [], None, {"radio": "radio buttons: no verb", "reference-set": "reference set selector: no verb"}.get(inp, f"input {inp}: no verb")


def click_acts(h):
    """A click hop or the action itself -> engine actions (action_inventory click_plan: row, row_only, within)."""
    if "menu_item" in h:   # a menu document item of a layout or snippet: journey-verbs.js menuitem
        return [{"do": "menuitem", "widget": h["click"], "nth": h["menu_item"], "label": h.get("caption") or h["click"]}]
    if h.get("row_only"):
        # PR-P3: a Data grid 2 whose row fires on a double click (onClickTrigger = double in the model)
        return [dict({"do": "row", "widget": h["row"]}, **({"dblclick": True} if h.get("trigger") == "double" else {}))]
    acts = [{"do": "row", "widget": h["row"]}] if h.get("row") else []
    # PR-F26: a navigation list item is clicked by its position in the list (journey-verbs.js item)
    return acts + [{"do": "item", "widget": h["click"], "nth": h["item"], "of": h.get("items")} if "item" in h else {"do": "click", "widget": h["click"]}]


def shown(step, *hops):
    """PR-F38: step + "shown_if", the visibility conditions (action_inventory hop "shown_if") of the widgets the step
    clicks or waits for, so run_journeys can say a baseline FAIL there met a widget its condition hid."""
    c = list(dict.fromkeys(t for h in hops if h for t in h.get("shown_if") or []))
    if c:
        step["shown_if"] = c
    return step


def name_hops(x, cause, rules, by_id):
    """D94: an action reached only through a flow that is run BY NAME (a task type row holds "Module.ShowTaskPage", click_causes.py
    cause dynamic-name) has no click path in the model. UPG_NAME_HOPS=file.json {"rules": [{"flow", "pages", "entry_of", "hops"}]}
    names the clicks a person makes that make the app run it (Task List: the mission card, then Open). A rule applies to an action
    with no path whose cause names `flow` and whose pages are all in `pages`; `entry_of` is an action whose path starts at the same
    role home (its first two hops are the entry). Returns x with path, path_role and the no-click-path todo replaced, or x."""
    if x.get("path") or not cause or cause.get("cause") != "dynamic-name":
        return x
    for r in rules:
        if r.get("flow") not in cause.get("detail", "") or not set(x.get("via_pages") or []) <= set(r.get("pages") or []):
            continue
        base = (by_id.get(r.get("entry_of") or "") or {}).get("path") or []
        if len(base) < 2 or not x.get("roles"):
            return x
        path = [dict(base[0]), dict(base[1])]
        page = base[1].get("page")
        for h in r.get("hops") or []:
            path += [dict(h), {"page": h.get("page") or page}]
        path.append({"click": x["widget"], "on": x["host"], "action": x["action"], "id": x["id"],
                     **({"shown_if": x["shown_if"]} if x.get("shown_if") else {})})
        y = dict(x, path=path, path_role=x["roles"][0], todo=[t for t in x.get("todo") or [] if not t.startswith("no-click-path")])
        y["path_text"] = f"as {y['path_role']}: " + " -> ".join(f"click {h['click']}" if "click" in h else h.get("page") or h.get("entry", "") for h in path)
        return y
    return x


def click_target(h):
    """The selector that proves a click hop is on screen: the widget, or the list for a row on-click."""
    return f".mx-name-{h['row'] if h.get('row_only') else h['click']}"


class ActionGen:
    """actions.json (action_inventory.py, E2E-8) -> one journey per action without a todo (E2E-10)."""

    def __init__(self, doc, have, data_rung, model=None, users=None):
        self.doc, self.have, self.data_rung, self.model = doc, have, data_rung, model
        self.users = users   # PRF-2 (D6): users.json, to know which roles have exactly one user; None = no such judgement
        self.task_hosts = task_list_hosts(doc)
        self.by_id = {x["id"]: x for x in doc.get("actions", [])}
        # PR-F25: the editable form of each page (data-view fields of any action hosted there), for wizard hops
        self.page_form = {}
        for x in doc.get("actions", []):
            f = [g for g in x.get("fields") or [] if g.get("editable") not in ("Never",)]
            if f and len(f) > len(self.page_form.get(x.get("host"), [])):
                self.page_form[x.get("host")] = f
        self.n = 0
        self._landing = {}
        # UPG_LANDING_OVERRIDE=file.json {"Module.Page": "widgetName"}: a page whose every widget is conditionally visible has
        # no guard the model can vouch for (a field app Homepage: the generated grid is empty for a role and never "appears").
        # The override names the widget a person saw render; it replaces the pick, `away` skipping included.
        try:
            self._landing_override = json.load(open(os.environ["UPG_LANDING_OVERRIDE"])) if os.environ.get("UPG_LANDING_OVERRIDE") else {}
        except (OSError, ValueError):
            self._landing_override = {}
        # UPG_PAGE_COMBOS=file.json {"Module.Page": "comboBoxName"}: a master-detail page that shows its content only after a pick
        # ("Select a Work Order to see Annex details"). The combo is the page's landing guard (the detail widgets are not
        # there yet) and the journey picks its first option before the next click on that page (journey-verbs.js combo).
        try:
            self._page_combos = json.load(open(os.environ["UPG_PAGE_COMBOS"])) if os.environ.get("UPG_PAGE_COMBOS") else {}
        except (OSError, ValueError):
            self._page_combos = {}
        self._landing_override = {**self._landing_override, **self._page_combos}
        # UPG_PAGE_PREPS=file.json {"Module.Page": [{"do": "upload"|"fill"|..., "widget": ..., ...}]}: what a person does on a page
        # before its buttons can be pressed (an upload that enables Sign, the password typed into a snippet the model cannot
        # see). The actions run before the next click that leaves the page, and before the action's own click (D96).
        try:
            self._page_preps = json.load(open(os.environ["UPG_PAGE_PREPS"])) if os.environ.get("UPG_PAGE_PREPS") else {}
        except (OSError, ValueError):
            self._page_preps = {}
        self.tabs = {"journeys": 0, "steps": 0, "uncertain": 0}

    def tab_acts(self, h, page):
        """(engine actions, tab notes) that bring hop h's widget on screen: a click on every tab page above it that
        the page does not show first (impact_map.tab_path). B4T2-11, B4N1-8: actions.json carries no tab, so 31 of 32
        generated journeys FAILed on the healthy OLD app until a hand script added the tab clicks. A plain click on
        the tab page name is what that hand fix ran and PASSed with (`.mx-name-tabPage1`, settleMs 800); the `tab`
        verb in journey-verbs.js checks the tab became active, once the runner dispatches it. PR-F35: an item of a
        Pop-up menu gets {"do": "menu"} on that menu first."""
        if self.model is None or "menu_item" in h:
            return [], []
        import impact_map as I
        w = h["row"] if h.get("row") else h["click"]
        tabs, why = I.tab_path(self.model, page, w, host=h.get("on"))
        notes = [dict(t, widget=w) for t in tabs]
        if why and (tabs or "not found" not in why):
            notes.append({"widget": w, "why": why})
        elif why:
            notes.append({"widget": w, "why": why + ": no tab step, the step guard fails if a tab hides it"})
        # PR-F35: a Pop-up menu item is reached by opening its menu (journey-verbs.js "menu"), in tab order
        return [{"do": "menu", "widget": t["menu"]} if "menu" in t else {"do": "click", "widget": t["tab"], "settleMs": 800}
                for t in tabs], notes

    def landing(self, qn, away=None):
        """Landing widget of page qn. away: the page the click leaves; its own and its layouts' widget names are
        skipped (PR-F26), so the guard cannot pass while the click left the screen on that page."""
        if self.model is None or not qn or qn not in self.model.docs:
            return None
        if qn in self._landing_override:
            return self._landing_override[qn]
        key = (qn, away)
        if key not in self._landing:
            import impact_map as I
            lw = I.landing_widget(self.model, qn, self.names(away))
            self._landing[key] = lw["widget"] if lw else None
        return self._landing[key]

    def page_pick(self, qn, widget=None):
        """What a page needs before its next click: the combo pick of a master-detail page (UPG_PAGE_COMBOS) and the preparation
        a person does (UPG_PAGE_PREPS), as fresh action dicts. A preparation given as {"actions": [...],
        "not_for": [widget], "only_for": [widget]} is skipped when the click is on a not_for widget (the click that is itself
        the preparation) or not on an only_for one."""
        if not qn:
            return []
        c = self._page_combos.get(qn)
        prep = self._page_preps.get(qn) or []
        if isinstance(prep, dict):
            skip = widget in (prep.get("not_for") or []) or (prep.get("only_for") is not None and widget not in prep["only_for"])
            extra = (prep.get("per_widget") or {}).get(widget) or []
            prep = [] if skip else (prep.get("actions") or []) + extra
        return ([{"do": "combo", "widget": c, "first": True}] if c else []) + [dict(a) for a in prep]

    def names(self, qn):
        """Widget names page qn renders (the page and its layouts); empty when unknown."""
        if self.model is None or not qn or qn not in self.model.docs:
            return set()
        import impact_map as I
        return {w["Name"] for q in [qn] + list(I.layout_closure(self.model, qn)) for w in self.model.widgets(q)
                if isinstance(w.get("Name"), str)}

    def distinct_ready(self, sel, page, away):
        """(selector, note) for a step that lands on `page` from `away`. PR-F26, Purchase Request pipe-19: the click to
        Step 3 left the screen on Step 2, and the guard .mx-name-actionButton1 (Step 3's Submit) PASSed on Step 2's
        actionButton1 (Discard); the Submit click then discarded the request and ended the session. A guard whose
        name the page left also renders proves nothing: take a landing widget only `page` has, else keep it and say."""
        w = sel[len(".mx-name-"):] if sel.startswith(".mx-name-") else None
        if not w or not away or away == page or w not in self.names(away):
            return sel, None
        lw = self.landing(page, away)
        if lw:
            return f".mx-name-{lw}", {"page": page, "guard": lw, "was": w, "why": f"{w} is also on {away}"}
        return sel, {"page": page, "guard": w, "why": f"{w} is also on {away} and {page} has no widget of its own: weak guard"}

    def name_collision(self, x):
        """PRC-6 (Purchase Request run 4): (["name-collision"], why) when a LAYOUT widget has the name of the widget x clicks,
        else None. A step waits for `.mx-name-<widget>`; the layout's widget answers it on every page, so the guard cannot tell
        the page's widget from the layout's: MyRequests.container6 (the attachment tile) shared its name with the top bar's
        container6 ("Purchase Request"), the old app PASSED on the top bar while the page showed "No items found", and the
        rebuilt top bar of the new app made the same journey a REGRESSION. Not generated, never dropped (the todo list names it)."""
        w = x.get("widget")
        if not w or x.get("host_type") == "Layout":
            return None
        lay = sorted({a["host"] for a in self.doc.get("actions", [])
                      if a.get("widget") == w and a.get("host_type") == "Layout" and a.get("host") != x.get("host")})
        if not lay:
            return None
        return ["name-collision"], (f".mx-name-{w} is also a widget of layout {', '.join(lay)}: a guard on that name is satisfied by the "
                                    "layout on any page, so the journey cannot show the page's widget (write it by hand, scoped to the page)")

    def why_not(self, x):
        """None when a journey can be generated, else (reasons, why) for its skipped plan entry (never dropped).
        reasons: the todo reasons of action_inventory.py, or no-user, login-entry, profile, icon-menu, old-inventory."""
        todo = [t for t in x.get("todo") or [] if not (STANDIN and t.startswith("external-call"))]
        if todo:   # --standin: an external call alone is no todo, the stand-in answers it (heal.py outside-call)
            return [t.split(":")[0].split(" (")[0] for t in todo], "action todo: " + "; ".join(todo)
        path, role = x.get("path") or [], x.get("path_role")
        if not path or not role:
            return ["no-click-path"], "no click path recorded"
        if role not in self.have:
            return ["no-user"], f"no test user for role {role}, the role the click path is walked as"
        if assign_to_me_dead(x, role, self.users, self.task_hosts):
            return ["assign-to-me-dead"], (f"PRF-2: shown only if Assignees = empty, and role {role} has 1 user, so its tasks arrive "
                                           "assigned and the button never renders (WorkflowCommons assigns a task with one target user "
                                           "at creation): not a defect of the app, no route in this fixture; a 2nd user for the role makes it reachable")
        e = path[0]
        if e.get("via") == "login":
            return ["login-entry"], "the path starts at the login page: needs an anonymous journey, write it by hand"
        if e.get("via") not in ("home", "menu"):
            return ["old-inventory"], "actions.json has no structured entry hop (written before E2E-10): rerun action_inventory.py"
        if not (e.get("profile_kind") or "").lower().startswith("responsive"):
            return ["profile"], f"the path enters through navigation profile {e.get('profile') or '?'}: the engine runs the Responsive profile"
        if e.get("via") == "menu" and not all(e.get("menu") or [None]):
            return ["icon-menu"], "the path starts at a menu item without a caption (icon only): the nav verb finds items by caption"
        return None

    def ready_after(self, x, hops):
        """(selector, weak note or None) the action step lands on."""
        if x["action"] in ("open-page", "create") and x.get("target"):
            w = self.landing(x["target"], x.get("host") if x.get("host") != x["target"] else None)
            if w:
                return f".mx-name-{w}", None
            return ".mx-page", f"{x['target']}: no landing widget (or model not loaded): guard is .mx-page"
        if x["action"] == "save" and len(hops) >= 2:
            # FN-6: the opener button can sit in a closed Pop-up menu or Dropdown container;
            # after the save the menu is closed again, so the button is hidden and the step FAILed with the row saved.
            # Land on the menu widget itself, which is on screen without opening it.
            sel = click_target(hops[-2])
            _, tn = self.tab_acts(hops[-2], hops[-2].get("on"))
            menus = [n["menu"] for n in tn if n.get("menu")]
            if menus:
                sel = f".mx-name-{menus[0]}"
            return sel, ("save: lands back on the page that opened the form; a popup form leaves "
                         "that page visible, so the own-row check (--data-rung) is the strong check")
        return ".mx-page", f"{x['action']} -> {x.get('kind')}: no page the model proves it lands on; guard is .mx-page"

    def unassigned_route(self, x):
        """(path, note) PR-C1: x is a button shown only for an UNASSIGNED task (Assignees = empty, "Assign to me"). A
        path that opens the task from a list of the tasks ASSIGNED to the user (action_inventory hop
        "assigned_to_me": Purchase Request TaskInbox "My Tasks", XPath Assignees = '[%CurrentUser%]') can never show
        it, whatever row is clicked: the first open-task action of the same page whose list is not so filtered
        ("Open tasks") replaces that hop. None found: the path stays and the note says the button has no route."""
        path = x["path"]
        if not unassigned_only(x) or x.get("action") == "open-task":
            return path, None
        if path and path[-1].get("assigned_to_me"):   # the button itself sits in a list of the user's own tasks
            return path, {"route": f"{path[-1].get('click')} sits in {path[-1].get('within') or 'a list'}, which holds only the "
                                   "tasks assigned to the user (XPath Assignees = current user): shown only if Assignees = "
                                   "empty, so it can never render there"}
        for i, h in enumerate(path):
            if h.get("action") != "open-task" or not h.get("assigned_to_me"):
                continue
            role = x.get("path_role")
            for sib in self.doc.get("actions", []):
                last = (sib.get("path") or [{}])[-1]
                if (sib.get("action") == "open-task" and sib.get("host") == h.get("on") and sib["id"] != h.get("id")
                        and not sib.get("todo") and last.get("click") and last.get("id") == sib["id"]
                        and not last.get("assigned_to_me") and (role in (sib.get("roles") or []) or role == sib.get("path_role"))):
                    return path[:i] + [dict(last)] + path[i + 1:], {
                        "route": f"{h.get('click')} lists only the tasks assigned to the user (XPath Assignees = current user); "
                                 f"{last['click']} ({last.get('within') or 'list'}) can hold an unassigned one: took it"}
            return path, {"route": f"{h.get('click')} lists only the tasks assigned to the user and no other open-task action "
                                   f"on {h.get('on')} lists unassigned ones: the button has no route (shown only if Assignees = empty)"}
        return path, None

    def journey(self, x):
        path, route = self.unassigned_route(x)
        unas = unassigned_only(x)
        e, clicks = path[0], [h for h in path if "click" in h]
        steps = []
        first = []
        if e.get("via") == "menu":
            m = e["menu"]
            first = [{"do": "nav", "group": m[0] if len(m) > 1 else None, "item": m[-1], "settleMs": 3000}]
        pages = [h["page"] for h in path if "page" in h]
        # one step per page on the way: the step's guard is the widget the next click needs (fails where it breaks)
        pending, tab_notes, guard_notes = first, [], []
        for i, h in enumerate(clicks):
            label = f"open {pages[i] if i < len(pages) else '?'}" + (f" via {' > '.join(e['menu'])}" if i == 0 and e.get("via") == "menu" else "")
            if i == 0 and e.get("via") == "home":
                label = f"role home {pages[0] if pages else '?'}"
            tacts, tnotes = self.tab_acts(h, pages[i] if i < len(pages) else h.get("on"))
            if tacts:
                label += " > " + " > ".join(f"menu {n['menu']}" if n.get("menu") else f"tab {n.get('caption') or n['tab']!r}"
                                            for n in tnotes if n.get("tab") or n.get("menu"))
            tab_notes += tnotes
            ready_i, dn = self.distinct_ready(click_target(h), pages[i] if i < len(pages) else None,
                                              pages[i - 1] if 0 < i <= len(pages) else None)
            if dn:
                guard_notes.append(dn)
            if i < len(pages) and pages[i] in self._page_combos:
                # the next click's widget shows only after the pick; on the LAST hop too (the action step picks, then
                # clicks), or the page step waits for a widget that cannot be there yet (SNIP_AnnexReview_VerticalBar x6)
                ready_i = f".mx-name-{self._page_combos[pages[i]]}"
            if tacts and ready_i != click_target(h):
                # PR-F37, Purchase Request pipe-30: the landing guard of a swapped step sits on the tab the page shows
                # first, so after the tab click it was hidden and all 14 comments/attachments journeys FAILed on the
                # healthy OLD app (the tab and its Submit were on screen). Land first, then open the tab: the second
                # step waits for the widget itself, which the first step proved is on this page and not the one left
                steps.append(shown({"name": label.split(" > ")[0], "actions": pending, "ui": {"ready": ready_i, "textAbsent": ERROR_TEXT}},
                                   clicks[i - 1] if i else None))
                pending, ready_i = [], click_target(h)
                dn["then"] = f"{ready_i} after the tab step"
                steps.append(shown({"name": label, "actions": tacts, "ui": {"ready": ready_i, "textAbsent": ERROR_TEXT}}, h))
            else:
                steps.append(shown({"name": label, "actions": pending + tacts, "ui": {"ready": ready_i, "textAbsent": ERROR_TEXT}},
                                   clicks[i - 1] if i else None, h))
            if h is clicks[-1]:
                break
            ref = self.by_id.get(h.get("id") or "")
            # PR-F25: a wizard. When an earlier hop created the object, the page this hop leaves edits that new object,
            # and a later step validates it (Purchase Request pipe-18: Step 1 left empty, Submit refused). Fill the
            # page's form before leaving it, whichever widget leaves (a step list skips the Next button's checks)
            pending = self.page_pick(pages[i] if i < len(pages) else None, h.get("click"))
            made = any((self.by_id.get(c.get("id") or "") or {}).get("kind") == "create" for c in clicks[:i])
            if made and (ref or {}).get("kind") != "create":
                for f in self.page_form.get(h.get("on") or (pages[i] if i < len(pages) else None), []):
                    self.n += 1
                    pending += fill_field(f, self.n, f"Pw-${{RUN_ID}}-a!{i}")[0]
            acts_h = click_acts(h)
            if unas and h.get("action") == "open-task":
                # PR-C1: the list item that states no assignee (journey-verbs.js topmost `unassigned`), not the first
                for a in acts_h:
                    if a["do"] == "click":
                        a["unassigned"] = True
                        if x.get("caption"):
                            a["has"] = x["caption"]
            pending += acts_h
            if ref and ref.get("confirm"):
                pending.append({"do": "confirm", **({"label": ref["confirm"]["proceed"]} if ref["confirm"].get("proceed") else {})})
        if steps and not steps[0]["actions"]:
            steps[0]["actions"] = [{"do": "wait", "ms": 500}]   # the role home is where resetToStart leaves the journey
        # the action: fill the form when the action writes, click, confirm
        acts, own, unfilled, fields = [], [], [], []
        eff = set(x.get("effects") or []) | {x.get("kind")}
        writes = x["action"] == "save" or bool(eff & FILL_KINDS)
        pw = f"Pw-${{RUN_ID}}-a!{len(clicks)}"
        # PR-F27: the wizard rule of the hops (PR-F25) holds for the action too: on a page that edits the object an
        # earlier click created, a Next that only opens a page still validates the form (Purchase Request pipe-19:
        # Step1 Next left the form empty and Step 2 never opened)
        made = any((self.by_id.get(c.get("id") or "") or {}).get("kind") == "create" for c in clicks[:-1])
        if writes or (made and x.get("kind") != "create"):
            for f in x.get("fields") or self.page_form.get(x.get("host"), []):
                self.n += 1
                fa, attr, why = fill_field(f, self.n, pw)
                acts += fa
                if why:
                    unfilled.append({"widget": f.get("widget"), "attribute": f.get("attribute"), "why": why})
                elif fa and fa[0]["do"] == "fill":
                    fields.append({"widget": f["widget"], "value": fa[0]["value"], **({"attr": attr} if attr else {})})
                if attr:
                    own.append((attr, fa[0]["value"]))
        acts = self.page_pick(pages[len(clicks) - 1] if len(clicks) - 1 < len(pages) else x.get("host"), clicks[-1].get("click")) + acts
        acts += click_acts(clicks[-1])
        if x.get("confirm"):
            acts.append({"do": "confirm", **({"label": x["confirm"]["proceed"]} if x["confirm"].get("proceed") else {})})
        ready, weak = self.ready_after(x, clicks)
        cap = x.get("caption") or x["widget"]
        step = shown({"name": f"{x['action']} {cap!r} on {x['host']} ({x.get('kind')})", "actions": acts,
                      "ui": {"ready": ready, "textAbsent": ERROR_TEXT}}, clicks[-1], x)
        commits = x["action"] == "save" or bool(eff & {"commit", "status-change"})
        if self.data_rung and own and commits:
            # E2E-9 own-row check, create-spec style: the row this run typed, in the attribute's own entity
            step["data"] = {"oql": [{"label": f"the run's own row: {a.rsplit('.', 1)[1]} = {v}", "expect": 1,
                                     "sql": f"SELECT COUNT(*) AS n FROM {a.rsplit('.', 1)[0]} WHERE {a.rsplit('.', 1)[1]} = '{v}'"}
                                    for a, v in own]}
        steps.append(step)
        j = journey(act_id(x["id"]), f"{x['action']} {cap} ({x['id']})", x["path_role"],
                    [f"action {x['id']}: {x['action']} -> {x.get('kind')}", x.get("path_text") or ""], steps,
                    [f"action:{x['id']}"])
        j["_action"] = x["id"]
        j["action"] = x["id"]   # the link run_journeys counts coverage by (E2E-11); "_action" kept for readers of E2E-10
        if fields:
            j["_fields"] = [dict(f, attr=f["attr"].rsplit(".", 1)[1]) if f.get("attr") else f for f in fields]
        if unfilled:
            j["_unfilled"] = unfilled
        if weak:
            j["_guard"] = weak
        if any(a["do"] == "fill" and re.match(r"^\d+/15/\d{4}", str(a.get("value"))) for a in acts):
            j["_assumes"] = "dates typed in en_US order (M/d/yyyy): the test user's language must be English (US)"
        if route:
            j["_route"] = route["route"]   # PR-C1
        if x.get("needs"):
            j["_needs"] = x["needs"]
        # PR-F25: the data every hop of the path needs, not only the action's own (Purchase Request pipe-18: 51 of 106
        # baseline defects clicked a per-row button on the way, in a list no earlier journey had filled yet).
        # run_journeys.py walks journeys with path needs in a second pass, after every role's first pass has created rows
        pn = list(dict.fromkeys(n for h in clicks for n in (self.by_id.get(h.get("id") or "") or {}).get("needs") or []))
        pn += [n for n in x.get("needs") or [] if n not in pn]
        if pn:
            j["_path_needs"] = pn
        if guard_notes:
            j["_guards"] = guard_notes   # PR-F26: a step guard swapped for one the page left does not render
        if self.model is None:
            j["_tabs_unchecked"] = "model not loaded: a widget on a tab page not shown first gets no tab step (B4T2-11)"
        elif tab_notes:
            j["_tabs"] = tab_notes
            n = sum(1 for t in tab_notes if t.get("tab"))
            self.tabs["journeys"] += bool(n)
            self.tabs["steps"] += n
            self.tabs["uncertain"] += any(t.get("why") for t in tab_notes)
        return j

    def spec_actions(self, spec):
        """Action ids a --create spec covers: its explicit "action"/"actions", else the newButton's create action
        and the saveButton on the page that create opens."""
        if not spec:
            return []
        ids = [i for i in ([spec["action"]] if spec.get("action") else []) + list(spec.get("actions") or []) if i in self.by_id]
        if ids:
            return ids
        acts = self.doc.get("actions", [])
        news = [x for x in acts if x["widget"] == spec.get("newButton") and x["action"] == "create"]
        pages = {x.get("target") for x in news if x.get("target")}
        saves = [x for x in acts if x["widget"] == spec.get("saveButton") and x["host"] in pages]
        return [x["id"] for x in news if x.get("target") in {s["host"] for s in saves}] + [x["id"] for x in saves]


def action_summary(found, gen, skipped, override, oos=()):
    by = {}
    for s in skipped:
        for r in s["reasons"]:
            by[r] = by.get(r, 0) + 1
    line = (f"actions {found} found · {gen} generated · {len(override)} by --create override · "
            f"{len(skipped)} not generated by reason " + (", ".join(f"{k} {n}" for k, n in sorted(by.items())) or "none"))
    if oos:   # journey_scope.py: listed, INFO in the gate, never INVALID
        bc = {}
        for e in oos:
            bc[e["class"]] = bc.get(e["class"], 0) + 1
        line += f" · {len(oos)} out of scope (" + ", ".join(f"{k} {n}" for k, n in sorted(bc.items())) + ")"
    return by, line


NON_BROWSER = {
    "startup": "start log: the after-startup flow ran with no new ERROR and the module's own 'active' lines match the baseline (log diff, gate step 4)",
    "scheduled": "scheduled event: confirm it exists or is intentionally removed; run it once by its microflow on the new app and diff the log",
    "service": "published service: REST check (status + contract diff) already in the gate; add a call per changed operation",
    "visual": "screenshot every listed page per role on old and new and compare (smoke walk with screenshots)",
    "module-pages": "open each listed vendor page as the role that may open it, screenshot old vs new; empty charts or blank grids are the finding",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("impact", nargs="?", help="impact_map.py --out JSON (optional with --actions)")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--actions", help="actions.json (action_inventory.py --out, E2E-8): one journey per action without a todo (E2E-10)")
    ap.add_argument("--actions-model", help="the .mpr actions.json was read from, when its \"model\" path is not on this "
                    "machine: landing guards and tab steps (B4T2-11) come from it")
    ap.add_argument("--create", help="create-and-save spec JSON for this app")
    ap.add_argument("--scope", help="scope.json (journey_scope.py): an action classed unreachable, marketplace-module, no-role or "
                    "unused gets no journey and is listed in plan.json out_of_scope (INFO in the gate, never INVALID)")
    ap.add_argument("--causes", help="causes.json (click_causes.py): the cause of each reachable action without a click path is "
                    "added to its skipped row's why (INVALID with a precise reason, not just \"no click path\")")
    ap.add_argument("--roles-with-users", help="comma list; journeys only for roles that have a test user")
    ap.add_argument("--mfa-probe-role", help="ordinary role to log in as before the MFA sign-in (default: first non-admin role with users)")
    ap.add_argument("--users", help="users.json (role -> one user object, or a list): an action shown only for an UNASSIGNED task "
                    "(\"Assign to me\") of a role with exactly one user can never render; it is listed as todo assign-to-me-dead (PRF-2)")
    ap.add_argument("--standin", action="store_true", help="an action whose only todo is external-call gets a journey: the run serves apimock.py "
                    "for the old and the new app (same answers), so the call is not a gap. Used by the heal step; the gate still never PASSes on a stand-in")
    ap.add_argument("--data-rung", action="store_true", help="keep the create-save data rung (+1 and own-row checks; run_journeys needs --psql / UPG_PSQL, E2E-9)")
    a = ap.parse_args()
    global STANDIN
    STANDIN = a.standin
    if not a.impact and not a.actions:
        ap.error("give an impact map, --actions actions.json, or both")
    adoc = json.load(open(a.actions)) if a.actions else None
    users = json.load(open(a.users)) if a.users else None
    scope = json.load(open(a.scope))["classes"] if a.scope else {}
    causes = json.load(open(a.causes))["actions"] if a.causes else {}
    name_rules = json.load(open(os.environ["UPG_NAME_HOPS"])).get("rules", []) if os.environ.get("UPG_NAME_HOPS") else []
    if scope and adoc is None:
        ap.error("--scope needs --actions (the scope names actions)")
    if adoc is not None and not isinstance(adoc.get("actions"), list):
        ap.error(f"{a.actions}: no \"actions\" list (not an action_inventory.py --out file)")

    # without an impact map (--actions alone) there are no login/menu/sign-out journeys to make: only the actions
    m = json.load(open(a.impact)) if a.impact else {"roles": {}, "user_roles": {}, "candidates": []}
    base = os.path.dirname(os.path.abspath(a.impact)) if a.impact else "."
    for k in ("old", "new"):  # older impact.json files hold paths relative to where impact_map ran (E5b 24)
        p = m.get(k)
        if p and not os.path.isabs(p) and not os.path.exists(p):
            for cand in (os.path.join(base, p), os.path.join(os.path.dirname(base), p)):
                if os.path.exists(cand):
                    m[k] = cand
                    break
    roles = m["roles"]
    guest = m["user_roles"].get("guest")
    have = [r.strip() for r in a.roles_with_users.split(",")] if a.roles_with_users else [r for r in roles if r != guest]
    if not a.roles_with_users and not a.impact and adoc is not None:
        # no role list at all: every role a click path is walked as (a role without a user then fails at login, loudly)
        have = sorted({x["path_role"] for x in adoc["actions"] if x.get("path_role")})
    out = Path(a.out_dir)
    # S: the anonymous role, read as impact_map.Roles reads it (EnableGuestAccess + GuestUserRole); null when guests are off.
    # run_journeys.py needs it to demand one anonymous process (the gate's anonymous denominator)
    plan = {"impact": os.path.abspath(a.impact) if a.impact else None, "journeys": [], "not_browser": [], "todo": [], "skipped": [],
            "covered": [], "unreachable": [], "out_of_scope": [], "anonymous_role": guest}

    # PRC-7 (Purchase Request run 4): a journey an earlier run generated for an action that is now skipped stayed in the folder and
    # ran again (MyRequests.container6, skipped as a name collision, still produced the one REGRESSION). The generator owns the
    # files it writes: its own earlier journeys (a "_why" key, id not proc-*, which process_journeys.py owns) go before the
    # new ones are written; hand-written journeys have no "_why" and stay.
    stale = 0
    for f in sorted((out / "journeys").glob("*/*.journey.json")):
        try:
            old = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(old, dict) and "_why" in old and not str(old.get("id", f.name)).startswith("proc-"):
            f.unlink()
            stale += 1
    if stale:
        print(f"note: removed {stale} journey file(s) of an earlier generation (rewritten below where still generated)")

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
        model = mprmodel.Model.load(m["new"]) if m.get("new") else None
    except Exception as e:  # journeys still generate; menu guards fall back to .mx-page
        print(f"note: new model not loaded ({e}); menu landing guards fall back to .mx-page", file=sys.stderr)
    old = None
    if model is not None and m.get("old") and m.get("old") != m.get("new"):
        try:  # before-picked runs on the OLD app: a guard must exist on both (E6-18)
            old = mprmodel.Model.load(m["old"])
        except Exception as e:
            print(f"note: old model not loaded ({e}); menu guards are checked against the new model only", file=sys.stderr)
    emitted_login = set()
    reach = None
    if model is not None:
        try:
            reach = entry_reach(model)
        except Exception as e:
            print(f"note: reachability not computed ({e}); unlinked pages stay todo", file=sys.stderr)
    login_reasons = (cands.get("login-per-role") or {}).get("reasons", ["always-on: login per role"])
    # B2-3: a role whose home page IS the login page is an API-only role (T8R2 FSMAPIConsumer, home General.Login_Web):
    # its user signs in and gets the login page again, so no browser journey can prove its login; the engine then
    # reported the trial-licence session cap as the cause, which was wrong (the runtime log had no session limit). Listed
    # as not_browser with the real reason, like the login-form home below, and left out of every other browser journey.
    # Not skipped: since QJ-5 an INVALID login-<role> blocks, and nothing a browser can do would ever clear it; its
    # services are what the gate's other rungs check.
    lp = (m.get("login") or {}).get("login_page")
    api_only = {r for r in roles if r != guest and lp and roles[r].get("home_page") == lp}
    for r in roles:
        if r in api_only:
            plan["not_browser"].append({"id": f"login-{r}", "role": r, "check": "API-only role: no browser home",
                                        "targets": [lp],
                                        "why": f"API-only role: its home page is the login page {lp}, so a signed-in user sees "
                                               "the login page again and no browser journey can prove its login (not a licence "
                                               "or session-cap failure, B2-3); test it through the services it calls"})
            continue
        if r == guest:
            # anonymous: no login journey can cover it; listed so the gate prints INVALID instead of nothing (E4 11)
            plan["skipped"].append({"id": f"anonymous-{r}", "role": r,
                                    "why": "anonymous role: needs an anonymous journey (open the app without signing in, "
                                           "check the guest home renders); write it by hand"})
            continue
        api = login_form_home(model, roles[r], m.get("login", {}))
        if api:
            # T8R B2-3: an API-only role; its services are what the gate's other rungs check, not a browser home
            plan["not_browser"].append({"id": f"login-{r}", "role": r, "check": "API-only role: no browser home",
                                        "targets": [roles[r]["home_page"]],
                                        "why": f"API-only role: {api}; a signed-in user sees a login form again"})
            print(f"note: login-{r}: no login journey: API-only role, {api}", file=sys.stderr)
            continue
        if r not in have:
            plan["skipped"].append({"id": f"login-{r}", "why": "no test user for this role (INVALID in the gate, not PASS)"})
            continue
        roles[r] = fix_landing(model, roles[r], m.get("login", {}))
        if roles[r].get("_landing_was"):
            print(f"note: login-{r}: landing guard {roles[r]['_landing_was']} {roles[r].get('_landing_why', 'is also a layout widget name')}; "
                  f"using {(roles[r]['landing'] or {}).get('widget', '.mx-page')}", file=sys.stderr)
        lj = login_journey(r, roles[r], login_reasons[:6], model, old)
        emit(lj)
        emitted_login.add(r)
        roles[r]["_closes"] = list(lj.get("closes") or [])   # a microflow home it proves (T4-8)
        roles[r]["_closes_not"] = lj.get("_closes_not")      # why it cannot, for the home todo (T6R-3b)

    have = [r for r in have if r not in api_only]   # B2-3: no MFA probe, sign-out or menu journey as an API-only role
    if m.get("auth", {}).get("modules") and any(x in " ".join(m["auth"]["modules"]) for x in ("MFA", "GoogleAuth", "TOTP")):
        probe = a.mfa_probe_role or next((r for r in have if r in roles and not roles[r].get("is_admin")), None)
        if probe:
            j, err = mfa_journey(probe, roles[probe], m.get("login", {}), roles[probe].get("sign_out_item"),
                                 (cands.get("mfa") or {}).get("reasons", ["always-on: MFA module present"])[:6])
            if j:
                emit(j)
            else:
                plan["todo"].append({"id": "mfa-challenge", "why": err})

    so = next((r for r in have if r in roles and roles[r].get("sign_out_item")), None)
    so_why = []   # B4T2-4: why no layout sign-out was found, per home page looked at
    if not so and model is not None:
        # T2-11: sign-out in a layout menu bar (a menu document or another profile) or a layout sign-out button
        import impact_map as I
        for r in [x for x in have if x in emitted_login]:
            pages = role_home_pages(model, roles[r])
            if not pages:
                so_why.append(f"{r}: no home page the model shows (home microflow {roles[r].get('home_microflow') or '?'})")
            for p in pages:
                lso = I.layout_sign_out(model, p) if p in model.docs else None
                if lso:
                    # T2R3-4: a caption path with an empty caption (icon-only item) cannot be navigated by caption
                    named = lso.get("path") if lso.get("path") and all(lso["path"]) else None
                    roles[r] = dict(roles[r], sign_out_item=named, sign_out_button=lso.get("button"),
                                    sign_out_clicks=None if named else lso.get("clicks"),
                                    _sign_out_from=f"layout of {p}" + (f", menu widget {lso['widget']}" if lso.get("widget") else ""),
                                    _sign_out_by=None if lso.get("by") == "action" else
                                    f"inferred from the {lso['by']}: {lso['detail']} (B4T2-4); the login-page check proves it")
                    so = r
                    break
                so_why += [f"{r} home {p}: {w}" for w in (I.sign_out_why(model, p) if p in model.docs else [f"{p} not in the model"])]
            if so:
                break
    if so:
        emit(signout_journey(so, roles[so], m.get("login", {})))
    elif a.impact:
        why = "no tested role has a sign-out item in its menu or home layout: write the sign-out journey by hand"
        if model is None:
            why += " (layouts not searched: model not loaded)"
        elif so_why:
            why += ". Layout menus looked at: " + "; ".join(dict.fromkeys(so_why))
        plan["todo"].append({"id": "sign-out", "why": why})

    gen = None
    if adoc is not None:
        apath = a.actions_model or adoc.get("model")
        amodel = model if model is not None and m.get("new") and os.path.abspath(m["new"]) == apath else None
        if amodel is None and apath and os.path.exists(apath):
            try:   # the model actions.json was read from (the OLD app): landing guards and tab steps come from it
                import mprmodel
                amodel = mprmodel.Model.load(apath)
            except Exception as e:
                print(f"note: actions model not loaded ({e}); action guards fall back to .mx-page", file=sys.stderr)
        if amodel is None:   # B4T2-11: say it, a journey without its tab step FAILs on a healthy app
            print(f"note: actions model {apath or '(none named)'} not loaded: tab steps NOT checked (a widget on a tab "
                  "page not shown first gets none) and action guards fall back to .mx-page; pass --actions-model", file=sys.stderr)
        gen = ActionGen(adoc, set(have), a.data_rung, amodel, users)
    spec_ids = []
    if a.create:
        spec = json.load(open(a.create))
        cj = create_journey(spec, a.data_rung)
        if gen is not None:
            # E2E-10: the hand-written spec wins over the generated journey for the actions it walks
            spec_ids = gen.spec_actions(spec)
            if spec_ids:
                cj["closes"] = [act_id(i) for i in spec_ids]
                cj["covers"] = list(spec_ids)   # E2E-11: raw action ids, so coverage counts the actions this spec walks
            else:
                print("warning: create-save: the --create spec matches no action in --actions (set \"action\": "
                      "\"<action id>\" in the spec); both are kept", file=sys.stderr)
        emit(cj)
        if cj.get("_warning"):
            print(f"warning: create-save: {cj['_warning']}", file=sys.stderr)
    elif adoc is None:
        plan["todo"].append({"id": "create-save", "why": "no --create spec: write one core create-and-save spec per app at baseline (widget names are app-specific)"})

    for c in m["candidates"]:
        k = c["kind"]
        if c["id"] in ("login-per-role", "mfa"):
            continue
        if k == "menu":
            for r in [x for x in c.get("roles", []) if x in have][:1]:
                j, todo = menu_journey(c, r, model, old)
                if j:
                    emit(j)
                    if j.get("_landing_note"):
                        print(f"note: {j['id']}: {j['_landing_note']}", file=sys.stderr)
                if todo:
                    plan["todo"].append(todo)
            if not [x for x in c.get("roles", []) if x in have]:
                plan["skipped"].append({"id": c["id"], "why": f"no test user for any of {c.get('roles')}"})
        elif k == "home":
            page = c.get("target") or c["id"].split(":", 1)[-1]
            by = [r for r in c.get("roles", []) if r in emitted_login and roles[r].get("home_page") == page]
            # T4-8, T6-14: a role home MICROFLOW is walked by login-<role> too (it runs at sign-in); that journey
            # carries "closes": ["home:<microflow>"], so the item takes its verdict instead of a todo nobody walks
            by_mf = sorted((r for r in emitted_login if roles[r].get("home_microflow") == page and not roles[r].get("home_page")
                            and f"home:{page}" in (roles[r].get("_closes") or [])),
                           key=lambda r: (r not in c.get("roles", []), r))
            if by:
                plan["covered"].append({"id": c["id"], "role": by[0], "why": f"role home walked by login-{by[0]}"})
            elif by_mf:
                plan["covered"].append({"id": c["id"], "role": by_mf[0], "closed_by": f"login-{by_mf[0]}",
                                        "why": f"role home microflow {page} runs at sign-in: walked by login-{by_mf[0]} (closes it)"})
            else:
                # T6R-3b: the todo says the real reason. "role home of a role with no login journey" was printed for
                # three T6R homes whose roles all had one; the reason was a microflow home whose page was not resolved.
                walkers = sorted(r for r in emitted_login if roles[r].get("home_microflow") == page and not roles[r].get("home_page"))
                if walkers:
                    why = (f"login-{walkers[0]} walks this role home but cannot close it: "
                           + (roles[walkers[0]].get("_closes_not") or f"home:{page}: no guard proves its page opened")
                           + "; write the guard by hand, or a hand-checked journey that \"closes\" it")
                else:
                    cr = list(c.get("roles") or [])
                    other = [r for r in cr if r in emitted_login]
                    why = (f"role home of {', '.join(cr) or 'no known role'}: "
                           + (f"login-{other[0]} lands on that role's own home ({roles[other[0]].get('home_page') or roles[other[0]].get('home_microflow')}), "
                              "not this one (another navigation profile)" if other else
                              "none of these roles has a login journey (no test user, API-only or anonymous)")
                           + ": walk it by hand")
                plan["todo"].append({"id": c["id"], "why": why})
        elif k in ("page", "client_microflow"):
            tgt = c.get("target") or c["id"].split(":", 1)[-1]
            if reach is not None and tgt in model.docs and tgt not in reach:
                plan["unreachable"].append({"id": c["id"], "why": "no menu item, home page or login page reaches it through any "
                                                                   "chain of callers: dead in the UI, report it"})
            else:
                plan["todo"].append({"id": c["id"], "why": "no menu item reaches it; needs a hand-written step from the page that opens it"})
        else:
            key = next((n for n in NON_BROWSER if k.startswith(n) or c["id"].startswith(n)), None)
            tg = [x for x in (c.get("targets") or c.get("pages") or []) if isinstance(x, str)] if isinstance(c.get("targets") or c.get("pages"), list) else []  # module-pages candidates list "pages" (E6-20)
            row = {"id": c["id"], "priority": c.get("priority"), "check": NON_BROWSER.get(key, "manual check"), "targets": tg[:20]}
            if k == "module-pages" and reach is not None:
                # F24 (Purchase Request 10.24, real run, user decision): a vendor page that no menu item, home page, login
                # page, page URL, service, scheduled event, workflow or caller chain reaches is dead in the UI, before and
                # after: listed as unreachable (INFO), the same rule as a single page, instead of a NOT PROVED module row.
                # It still has to pass mx check; the module row keeps proving every page a user can reach.
                dead = [p for p in tg if p in model.docs and p not in reach]
                for p in dead:
                    plan["unreachable"].append({"id": f"page:{p}", "module_pages": c["id"],
                                                "why": f"vendor page of {c['id']}: no menu item, home page, login page, page "
                                                       "URL or caller chain reaches it: dead in the UI, report it"})
                row["targets"] = [p for p in tg if p not in dead]
                if dead:
                    row["dead"] = dead
                    print(f"note: {c['id']}: {len(dead)} of {len(tg)} pages dead in the UI, listed as unreachable")
            plan["not_browser"].append(row)
    if gen is not None:
        # E2E-10: every action is a journey, a create-save override or a skipped entry (INVALID in the gate): never dropped
        ngen, skipped, override, oos = 0, [], [], []
        oos_of = lambda x: scope.get(x["id"], {}).get("class") in ("marketplace-module", "unreachable", "no-role", "unused")
        walkable = [x for x in adoc["actions"] if x["id"] not in spec_ids and not oos_of(x) and not gen.why_not(x)]
        closers = todo_closers(plan["todo"], walkable, [mo for mo in (model, amodel) if mo is not None],
                               adoc["actions"])
        # PR-P4: the k-th workflow-op journey of a role (by journey id, the order its wave runs) takes row k of the list
        wf_rows, by_role = {}, {}
        for x in adoc["actions"]:
            if x["id"] not in spec_ids and not oos_of(x) and not gen.why_not(x) and (x.get("kind") == "workflow-op" or "workflow-op" in (x.get("effects") or [])):
                by_role.setdefault(x.get("path_role") or "", []).append(act_id(x["id"]))
        for ids in by_role.values():
            wf_rows.update({i: k for k, i in enumerate(sorted(ids))})
        for x in adoc["actions"]:
            if x["id"] in spec_ids:
                override.append({"id": act_id(x["id"]), "action": x["id"], "role": spec.get("role", ""), "closed_by": "create-save",
                                 "why": "the --create spec walks this action (hand-written, wins over the generated journey)"})
                continue
            if oos_of(x):
                sc = scope[x["id"]]
                oos.append({"id": act_id(x["id"]), "action": x["id"], "role": x.get("path_role") or "", "class": sc["class"],
                            "why": sc["reason"]})
                continue
            if name_rules:
                x = name_hops(x, causes.get(x["id"]), name_rules, gen.by_id)
            no = gen.why_not(x) or gen.name_collision(x)
            if no:
                why = no[1]
                cz = causes.get(x["id"])   # click_causes.py: WHY a reachable action has no click path
                if cz and "no-click-path" in no[0]:
                    why += f"; cause {cz['cause']}: {cz['detail']}"
                skipped.append({"id": act_id(x["id"]), "action": x["id"], "role": x.get("path_role") or "",
                                "reasons": no[0], "why": why})
                continue
            j = gen.journey(x)
            if closers.get(x["id"]):
                j["closes"] = list(j.get("closes") or []) + closers[x["id"]]
            sc = x.get("scope")
            if sc in DESTRUCTIVE_SCOPES:
                # PR-P4: it wipes or reseeds shared data. "resetsData" is the tag journey-proof.md item 2 already reads
                # by hand (--protect-state refuses it); run_journeys.py runs it after the main set, counted apart
                j["_scope"], j["resetsData"] = sc, True
                j["_destructive"] = f"DESTRUCTIVE({sc}): {SCOPE_WHY[sc]}"
            elif x.get("kind") == "delete" or "delete" in (x.get("effects") or []):
                j["_destructive"] = "deletes the first row it is given: later journeys of this role may miss it"
                if sc:
                    j["_scope"] = sc
            elif x.get("kind") == "workflow-op" or "workflow-op" in (x.get("effects") or []):
                # PR-F35: abort, pause, retry, jump-to change the workflow it is given, and with it its waiting task
                j["_destructive"] = "changes the state of the first workflow it is given: a task waiting in it may go"
                # PR-P4 (pr-baseline 8): and each one its own workflow, not the first listed for all of them
                k = wf_rows.get(act_id(x["id"]), 0)
                if k:
                    for st in j["steps"]:
                        ra = next((q for q in st.get("actions", []) if q.get("do") == "row"), None)
                        if ra:
                            ra["nth"] = k
                            j["_row"] = f"workflow {k + 1} of the list: the destructive workflow journeys of this role each take their own"
                            break
            emit(j)
            ngen += 1
        for aid, ids in closers.items():
            for e in plan["todo"]:
                if e["id"] in ids:
                    e["closed_by"] = act_id(aid)
        if closers:
            print(f"todo: {sum(len(v) for v in closers.values())} of {len(plan['todo'])} closed by generated action journeys")
        plan["skipped"] += skipped
        plan["covered"] += override
        plan["out_of_scope"] += oos
        by, line = action_summary(len(adoc["actions"]), ngen, skipped, override, oos)
        assert ngen + len(skipped) + len(override) + len(oos) == len(adoc["actions"]), "an action fell out of the plan"
        plan["actions"] = {"source": os.path.abspath(a.actions), "found": len(adoc["actions"]), "generated": ngen,
                           "override": len(override), "not_generated": len(skipped), "not_generated_by_reason": by,
                           "out_of_scope": len(oos), "scope_file": os.path.abspath(a.scope) if a.scope else None,
                           "inventory_line": adoc.get("summary_line"), "line": line}
        t = gen.tabs
        tline = ("tabs: NOT checked, actions model not loaded" if gen.model is None else
                 f"tabs: {t['journeys']} journeys with tab steps · {t['steps']} tab clicks · {t['uncertain']} uncertain")
        plan["actions"]["tabs"] = dict(t, checked=gen.model is not None, line=tline)
        print(line)
        print(tline)
    (out / "plan.json").write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(plan['journeys'])} journeys, {len(plan['not_browser'])} non-browser checks, "
          f"{len(plan['todo'])} todo, {len(plan['skipped'])} skipped, {len(plan['covered'])} covered, "
          f"{len(plan['unreachable'])} unreachable, {len(plan['out_of_scope'])} out of scope -> {out}")


if __name__ == "__main__":
    main()
