#!/usr/bin/env python3
"""impact_map.py: what did a Mendix upgrade change, and which user journeys does that touch, per user role.

    impact_map.py <old project dir|mpr> <new project dir|mpr> [--updates updates.txt]
                  [--out impact.json] [--md impact.md] [--catalog-check SCRATCH_DIR]

Reads both projects straight from their BSON (mprmodel.py; works for 9.x, 10.x and 11.x MPR v1/v2),
so it needs no Studio Pro and no mxbuild. Optional --catalog-check copies both .mpr files into
SCRATCH_DIR and cross-checks constants, scheduled events and published REST operations against
`mxcli catalog` (mxcli writes .mxcli/ next to the .mpr, so it never runs on the projects themselves).

Change kinds it reports
    module        marketplace/own module added, removed, version changed
    constant      default value or type changed, constant added or removed
    startup       after-startup / before-shutdown microflow swapped, or anything in its call tree changed
    scheduled     scheduled event added, removed, enabled flag, interval or microflow changed, or its tree changed
    document      microflow, nanoflow, java action, javascript action, page, snippet, layout, rule changed/removed;
                  domain model entity or attribute added/removed, attribute type, default value, validation or
                  access rules changed (doc = the module's $DomainModel; qn = Module.Entity or Module.Entity.Attribute)
    caller        own-module document that calls a changed or removed marketplace document, or uses a changed or
                  removed domain entity (it references the entity by name)
    security      user role added/removed, module-role mapping changed, project security settings, module security
    service       published REST / OData / web service or operation added, removed or changed
Journey candidates
    Every change is traced up the caller graph to entry points a person (or a client) can reach:
    menu items, role home pages, pages with allowed roles, client-callable microflows, published
    operations, scheduled events, after-startup. Entry points are mapped to user roles through the
    module-role -> user-role mapping of the NEW project. Login, MFA and startup are always candidates
    when an authentication module, the login page, project security or the after-startup tree changed.

The `roles` section carries what the journey generator needs per user role: home page and a
landing widget, the top-level menu captions the role can and cannot see, and the login page widgets.
This is an impact map, not a requirement ledger (coverage-ledger): it says what to look at, not
what the app must do.
"""
import argparse, collections, json, os, re, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mprmodel import Model, SKIP_KEYS, text_of, module_role_to_user_roles  # noqa: E402

AUTH_MODULES = re.compile(r"(MFA|GoogleAuth|TOTP|SAML|SSO|OIDC|LDAP|Administration|UserCommons|ForgotPassword|"
                          r"Login|Authentication|Kerberos|DeepLink)", re.I)
FLOW_TYPES = {"Microflows$Microflow", "Microflows$Nanoflow", "Microflows$Rule", "JavaActions$JavaAction",
              "JavaScriptActions$JavaScriptAction"}
UI_TYPES = {"Forms$Page", "Forms$Snippet", "Forms$Layout"}
DOC_TYPES = FLOW_TYPES | UI_TYPES
SERVICE_TYPES = {"Rest$PublishedRestService", "Rest$PublishedODataService", "Rest$ConsumedODataService",
                 "WebServices$PublishedWebService", "WebServices$ImportedWebService", "Rest$ConsumedRestService"}
GENERIC_NAME = re.compile(r"^[a-z]+[A-Za-z]*\d+$")
EXTRA_SKIP = SKIP_KEYS | {"StableId", "Excluded", "MarkAsUsed", "Line"}  # Line: flow routing geometry (10.x)


# ---------------------------------------------------------------- version-tolerant equality
def _empty(v):
    if v in (None, "", False, 0, [], {}):
        return True
    if isinstance(v, list):
        return all((isinstance(i, int) and not isinstance(i, bool)) or _empty(i) for i in v)
    if isinstance(v, dict):  # e.g. a bare Microflows$NoCase that a newer version writes where the old wrote nothing
        return all(k in ("$Type", "$ID") or _empty(x) for k, x in v.items())
    return False


def same(a, b):
    """Equal in meaning: ignore ids and geometry, and keys that exist on one side only. Within one Studio Pro
    version every key is always written, so a one-sided key is a schema difference between the two versions
    (a new property such as IsRequired, or a rename such as CaseValue -> CaseValues), not an edit. A real
    edit still shows as a different value under a shared key or a different list. Trade-off: a value that
    moved to a renamed key is not compared. A conversion must not mark every document changed."""
    if isinstance(a, dict) and isinstance(b, dict):
        if a.get("$Type") != b.get("$Type"):
            return False
        for k in set(a) | set(b):
            if k in EXTRA_SKIP:
                continue
            if k in a and k in b and not same(a[k], b[k]):
                return False
        return True
    if isinstance(a, list) and isinstance(b, list):
        a2 = [i for i in a if not (isinstance(i, int) and not isinstance(i, bool))]
        b2 = [i for i in b if not (isinstance(i, int) and not isinstance(i, bool))]
        return len(a2) == len(b2) and all(same(x, y) for x, y in zip(a2, b2))
    if hasattr(a, "subtype") or isinstance(a, (bytes, bytearray)):
        return True
    return a == b


def strip_widget_defs(x):
    """Drop pluggable widget definition and property lists: what update-widgets rewrites."""
    if isinstance(x, dict):
        cw = x.get("$Type", "").startswith("CustomWidgets$CustomWidget")
        return {k: strip_widget_defs(v) for k, v in x.items() if not (cw and k in ("Type", "Object"))}
    if isinstance(x, list):
        return [strip_widget_defs(i) for i in x]
    return x


def first_diff(a, b, path=""):
    """Path of the first meaningful difference, for the report."""
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k in EXTRA_SKIP:
                continue
            if k in a and k in b:
                p = first_diff(a[k], b[k], f"{path}.{k}" if path else k)
                if p:
                    return p
        return None
    if isinstance(a, list) and isinstance(b, list):
        a2 = [i for i in a if not (isinstance(i, int) and not isinstance(i, bool))]
        b2 = [i for i in b if not (isinstance(i, int) and not isinstance(i, bool))]
        if len(a2) != len(b2):
            return f"{path}[len {len(a2)}->{len(b2)}]"
        for i, (x, y) in enumerate(zip(a2, b2)):
            p = first_diff(x, y, f"{path}[{i}]")
            if p:
                return p
        return None
    return None if same(a, b) else path


def _cval(c):
    """Constant default as the runtime reads it: Boolean 'True' and 'true' are the same value."""
    v = c.get("default")
    return str(v).lower() if c.get("type") == "Boolean" and v is not None else v


# ---------------------------------------------------------------- role facts (new project)
class Roles:
    def __init__(self, m):
        self.m = m
        self.mr2ur = module_role_to_user_roles(m)
        self.all = sorted(m.user_roles())
        sec = m.singletons.get("Security$ProjectSecurity", {})
        self.admin = sec.get("AdminUserRole")
        self.guest = sec.get("GuestUserRole") if sec.get("EnableGuestAccess") else None

    def of_module_roles(self, mrs):
        out = set()
        for mr in mrs or []:
            out |= self.mr2ur.get(mr, set())
        return out

    def of_doc(self, qn):
        d = self.m.docs.get(qn)
        if not d:
            return set()
        if d.type == "Forms$Page":
            return self.of_module_roles(self.m.page_roles(qn))
        if d.type in ("Microflows$Microflow", "Microflows$Nanoflow"):
            return self.of_module_roles(d.data.get("AllowedModuleRoles"))
        if d.type in SERVICE_TYPES:
            return self.of_module_roles(d.data.get("AllowedRoles"))
        return set()


def layout_closure(m, page_qn, depth=6):
    """The layouts a page renders inside, and the snippets those layouts use (not the page's own snippets)."""
    out, frontier = [], [r for r in m.refs(page_qn) if m.docs.get(r) and m.docs[r].type == "Forms$Layout"]
    out += frontier
    for _ in range(depth):
        nxt = []
        for q in frontier:
            for r in m.refs(q):
                d = m.docs.get(r)
                if d and d.type in ("Forms$Layout", "Forms$Snippet") and r not in out:
                    out.append(r); nxt.append(r)
        frontier = nxt
    return out


NAV_TYPES = re.compile(r"Navigation|MenuBar|SimpleMenuBar|MenuWidget")


def has_navigation(m, page_qn):
    """True when the page's layout renders a menu (navigation tree, menu bar). A popup or bare layout has none,
    so the role menu captions are not on screen (E4 12, E5b 10)."""
    return any(NAV_TYPES.search(w.get("$Type", "")) for q in layout_closure(m, page_qn) for w in m.widgets(q))


def nav_sources(m, page_qn):
    """The menus the page's layouts render, one entry per menu widget: ("profile", name) for a navigation profile
    source, ("menu", qn) for a menu document, ("unknown", None) when the widget names no source (older models).
    T6-14: a Phone/Tablet layout renders the Phone_Menu document, so the Responsive profile captions are not on
    screen. Atlas 3 writes {"$Type": "Forms$NavigationSource", "NavigationProfile": "Responsive"} and
    {"$Type": "Forms$MenuDocumentSource", "Menu": "Atlas_Core.Phone_Menu"} (read from a real 10.x model)."""
    out = []
    for q in layout_closure(m, page_qn):
        for w in m.widgets(q):
            if not NAV_TYPES.search(w.get("$Type", "")):
                continue
            src = w.get("MenuSource") if isinstance(w.get("MenuSource"), dict) else {}
            st = src.get("$Type", "")
            if "MenuDocumentSource" in st:
                out.append(("menu", src.get("Menu") or ""))
            elif "NavigationSource" in st:
                out.append(("profile", src.get("NavigationProfile") or src.get("ProfileType") or None))
            else:
                out.append(("unknown", None))
    return out


def _menu_items(x, path=(), idx=()):
    """(caption path, action $Type, index path, action dict) of every menu item under x (a menu document or an item
    collection). The index path counts menu items in model order per level (int list markers skipped): Mendix renders
    item i of a menu bar as `.mx-name-<menuBar>-<i>`, its sub item j as `.mx-name-<menuBar>-<i>-<j>` (T2R3-4: the hand
    journey clicked menuBar2-0 then menuBar2-0-1 "Sign out" and PASSed on the Opcenter app)."""
    if isinstance(x, dict):
        if x.get("$Type", "").endswith("MenuItem"):
            p = path + (text_of(x.get("Caption")),)
            a = x.get("Action") if isinstance(x.get("Action"), dict) else {}
            yield p, (a.get("$Type") or ""), idx, a
            yield from _menu_items(x.get("Items") or [], p, idx)
            return
        for v in x.values():
            yield from _menu_items(v, path, idx)
    elif isinstance(x, list):
        i = 0
        for v in x:
            if isinstance(v, dict) and v.get("$Type", "").endswith("MenuItem"):
                yield from _menu_items(v, path, idx + (i,))
                i += 1
            elif isinstance(v, (dict, list)):
                yield from _menu_items(v, path, idx)


def _clicks(widget, idx):
    """The click chain that opens a menu bar item by index: menuBar2-0, menuBar2-0-1 (T2R3-4)."""
    return [f"{widget}-" + "-".join(str(i) for i in idx[:n]) for n in range(1, len(idx) + 1)]


SIGN_OUT_TEXT = re.compile(r"^\s*(sign|log)\s*-?\s*(out|off)\s*$", re.I)
SIGN_OUT_NAME = re.compile(r"(sign|log)_?(out|off)", re.I)


def _qns(x):
    """Qualified-name strings (Module.Name) anywhere in x: the flow a menu item or button action calls."""
    if isinstance(x, str):
        return [x] if re.fullmatch(r"[A-Za-z_]\w*\.[A-Za-z_]\w*", x) else []
    if isinstance(x, dict):
        return [q for k, v in x.items() if k not in SKIP_KEYS for q in _qns(v)]
    if isinstance(x, list):
        return [q for v in x for q in _qns(v)]
    return []


def _sign_out_flow(m, action, depth=3):
    """The flow (or JavaScript/Java action) named like sign-out / log-out that the action calls, directly or through
    up to depth levels of called flows, else None. B4T2-4: a sign-out item that calls a logout flow (an add-on OIDC
    logout, NanoflowCommons.SignOut) instead of the platform SignOut action was invisible to the action-type test."""
    frontier, seen = _qns(action), set()
    for _ in range(depth + 1):
        for q in frontier:
            if SIGN_OUT_NAME.search(q.rsplit(".", 1)[-1]):
                return q
        seen |= set(frontier)
        frontier = [r for q in frontier if q in m.docs for r in sorted(m.refs(q))
                    if r not in seen and m.docs.get(r) and m.docs[r].type in FLOW_TYPES]
    return None


def _sign_out_kind(m, caption, action):
    """(by, detail) when a menu item or button signs out, else None. by: "action" (the platform SignOut action),
    "flow" (it calls a flow named like sign-out, B4T2-4), "caption" (its caption reads Sign out / Log out / Logout,
    B4T2-4). flow and caption are inferred: the journey's own check (login page shown, role menu gone) FAILs loudly
    when the inference is wrong, it is never a PASS by itself."""
    t = (action or {}).get("$Type") or ""
    if "SignOut" in t:
        return "action", t
    f = _sign_out_flow(m, action) if action else None
    if f:
        return "flow", f"{t.split('$')[-1] or 'action'} reaches {f}"
    if caption and SIGN_OUT_TEXT.match(caption):
        return "caption", f"caption {caption!r}, {t.split('$')[-1] or 'no action'}"
    return None


def _layout_menus(m, page_qn):
    """(menu widget, items or None, source text) for every menu widget the page's layouts render."""
    nav = None
    for q in layout_closure(m, page_qn):
        for w in m.widgets(q):
            if not NAV_TYPES.search(w.get("$Type", "")):
                continue
            src = w.get("MenuSource") if isinstance(w.get("MenuSource"), dict) else {}
            items, what = None, "no menu source"
            if "MenuDocumentSource" in src.get("$Type", ""):
                d = m.docs.get(src.get("Menu") or "")
                items, what = (d.data if d else None), f"menu {src.get('Menu') or '?'}"
            elif "NavigationSource" in src.get("$Type", ""):  # a menu bar on another profile than the role menu
                name = src.get("NavigationProfile") or src.get("ProfileType") or ""
                nav = nav if nav is not None else (m.singletons.get("Navigation$NavigationDocument") or {})
                pr = next((x for x in nav.get("Profiles") or [] if isinstance(x, dict)
                           and name in (x.get("Name"), x.get("Kind"))), None)
                items, what = ((pr.get("Menu") or pr.get("MenuItemCollection")) if pr else None), f"profile {name or '?'}"
            yield q, w, items, what


def layout_sign_out(m, page_qn):
    """Sign-out the page's layouts offer outside the navigation profile menu (T2-11: a layout menu bar, user icon
    dropdown "My profile | Sign out"). Returns {"path": [captions], "widget": name, "clicks": [...], "by", "detail"}
    for a menu item of a menu document (or of another navigation profile) a layout menu widget renders,
    {"button": name, "by", "detail"} for a layout button that signs out, or None.
    T2R3-4, N1R2: the Opcenter user dropdown is an icon-only item (empty caption), so a caption path cannot name it and
    the old `all(captions)` test dropped the item: sign-out stayed a hand todo. Every menu hit carries "clicks", the
    index chain of the rendered item names; the journey uses it when a caption on the path is empty.
    B4T2-4: the platform SignOut action wins; else an item or button that calls a flow named like sign-out, else one
    captioned Sign out / Log out (by: action, flow, caption). sign_out_why says why nothing was found."""
    best = None
    rank = {"action": 0, "flow": 1, "caption": 2}
    for q, w, items, what in _layout_menus(m, page_qn):
        for p, kind, idx, a in (_menu_items(items) if items else []):
            k = _sign_out_kind(m, p[-1] if p else "", a)
            if k and (best is None or rank[k[0]] < rank[best["by"]]):
                best = {"path": list(p), "widget": w["Name"], "clicks": _clicks(w["Name"], idx), "by": k[0], "detail": k[1]}
    for q in layout_closure(m, page_qn):
        for w in m.widgets(q):
            if NAV_TYPES.search(w.get("$Type", "")) or not isinstance(w.get("Action"), dict):
                continue
            k = _sign_out_kind(m, text_of(w.get("Caption")) if w.get("Caption") else "", w["Action"])
            if k and (best is None or rank[k[0]] < rank[best["by"]]):
                best = {"button": w["Name"], "by": k[0], "detail": k[1]}
    return best


def any_sign_out(m, limit=5):
    """Every place in the whole model that signs out (BT-4): a menu item of a menu document or of a navigation profile,
    and a button / link / card widget with an Action, on any page, layout or snippet. [(where, by, detail)], at most
    `limit`. Empty is the proof run_journeys.py's NO-SIGNOUT evidence needs: the app has no sign-out UI at all."""
    hits = []
    nav = [("navigation", m.singletons[t]) for t in m.singletons if "Navigation" in t]
    for qn, data in nav + [(d.qn, d.data) for d in m.all_docs if d.type.startswith(("Forms$", "Pages$", "Menus$"))]:
        for p, kind, idx, a in _menu_items(data):
            k = _sign_out_kind(m, p[-1] if p else "", a)
            if k:
                hits.append((f"{qn}: menu item {' > '.join(p)}", *k))
    for d in m.all_docs:
        if d.type.startswith(("Forms$", "Pages$")):
            for w in m.widgets(d.qn):
                if isinstance(w.get("Action"), dict) and not NAV_TYPES.search(w.get("$Type", "")):
                    k = _sign_out_kind(m, text_of(w.get("Caption")) if w.get("Caption") else "", w["Action"])
                    if k:
                        hits.append((f"{d.qn}.{w.get('Name')}", *k))
        if len(hits) >= limit:
            break
    return hits[:limit]


def sign_out_why(m, page_qn, limit=6):
    """Why layout_sign_out found nothing on page_qn's layouts, one line per menu widget (B4T2-4: the todo said only
    "no sign-out item", so nobody could tell an unreadable add-on menu from an item that calls a microflow)."""
    out = []
    lays = layout_closure(m, page_qn)
    if not lays:
        return [f"{page_qn}: no layout in the model"]
    for q, w, items, what in _layout_menus(m, page_qn):
        tag = f"{q}.{w.get('Name') or '?'} ({what})"
        if items is None:
            out.append(f"{tag}: " + ("menu document not in the model (unreadable add-on module?)" if what.startswith("menu ")
                                     else "no items read"))
            continue
        its = [(" > ".join(c or "(icon)" for c in p), kind.split("$")[-1] or "no action") for p, kind, idx, a in _menu_items(items)]
        out.append(f"{tag}: {len(its)} items, none signs out: " +
                   ", ".join(f"{c!r} {k}" for c, k in its[:limit]) + (" ..." if len(its) > limit else ""))
    if not out:
        out.append(f"layouts {', '.join(lays)} render no menu widget")
    return out


# Guard candidates (T1-25, T2-10, T4-7): only real widgets of the page's own widget tree that render once per page.
# NOT_A_WIDGET: named model elements that are no widget (page parameters and variables carry a Name too: T4-7 got
# `.mx-name-NotificationFilterHelperNP`, the page parameter) and snippet calls (no element of their own, T2-10).
# REPEATING: content of these renders per row, or not at all on an empty list (T1-25: a button inside a TaskInbox list
# template FAILed 4 healthy logins). Content of a pluggable widget is skipped as well: gallery and data grid 2 rows,
# popovers and collapsed panels render it per item or on demand. Content of a conditionally visible widget too.
NOT_A_WIDGET = re.compile(r"Parameter|Variable|Argument|SnippetCall|\$(Page|Snippet|Layout|BuildingBlock|PageTemplate)$")
# T7: widgets that draw no element of their own (Set URL, timers, listen-to, trigger-only): the field's "setURL1" was
# 0 x 0 and the engine's first match, so every login journey FAILed on a healthy app. Matched by type and, for
# pluggable widgets whose type is generic, by the default name Studio Pro gives them.
NON_RENDERING = re.compile(r"\$(SetURL|SetUrl|Timer|ListenTo|(Microflow|Nanoflow)Trigger)$")
NON_RENDERING_NAME = re.compile(r"^(setURL|setUrl|timer|listenTo|microflowTrigger|nanoflowTrigger|trigger)\d*$")
REPEATING = re.compile(r"\$(ListView|DataGrid|TemplateGrid|Gallery|ReferenceSetSelector|TreeView)$")
TITLE = re.compile(r"\$(Title|PageTitle)$")


def hidden_on_desktop(x):
    """True when the widget's Atlas "Hide on" design property includes Desktop: in the DOM, never visible to the
    desktop browser the journeys run in (G-3 family). Shape read from a real 11.12 model (Atlas_Core.Atlas_TopBar):
    Appearance.DesignProperties [{"Key": "Hide on", "Value": {"$Type": "Forms$CompoundDesignPropertyValue",
    "Properties": [2, {"Key": "Tablet", ...}, {"Key": "Phone", ...}]}}]."""
    ap = x.get("Appearance") if isinstance(x.get("Appearance"), dict) else {}
    for dp in ap.get("DesignProperties") or []:
        if isinstance(dp, dict) and dp.get("Key") == "Hide on":
            v = dp.get("Value") if isinstance(dp.get("Value"), dict) else {}
            if any(isinstance(q, dict) and q.get("Key") == "Desktop" for q in v.get("Properties") or []):
                return True
    return False


def shown_tab_page(tc):
    """The tab page a tab control shows when the page opens: the one DefaultPagePointer names, else the first. None
    when the active tab comes from an attribute or variable (no tab page is certain). G-3: the T8R2 guard dataView2 sat
    on the non-default tab "Forms" of Offline actions, so the healthy OLD app FAILed the menu journey."""
    pages = [p for p in tc.get("TabPages") or [] if isinstance(p, dict)]
    if tc.get("ActivePageAttributeRef") or tc.get("ActivePageSourceVariable") or not pages:
        return None
    ptr = tc.get("DefaultPagePointer")
    return next((p for p in pages if ptr and p.get("$ID") == ptr), pages[0])


def is_popup_menu(w):
    """A Pop-up menu pluggable widget (com.mendix.widget.web.popupmenu.PopupMenu): its items render only once the
    menu is opened (PR-F35). FN-4: the Dropdown container (mendix.dropdowncontainer.DropdownContainer, kebab row
    menus) hides its content the same way until its .dropdown-toggle is clicked: an Edit or Delete button inside a
    closed kebab menu never appeared, and the journey failed on the healthy OLD app."""
    wid = str((w.get("Type") or {}).get("WidgetId") or "").lower()
    return "popupmenu" in wid or "dropdowncontainer" in wid


def popup_key(w, prop):
    """The PropertyKey of custom widget w's property prop (its TypePointer resolved through the widget's type)."""
    for pt in ((w.get("Type") or {}).get("ObjectType") or {}).get("PropertyTypes") or []:
        if isinstance(pt, dict) and pt.get("$ID") == prop.get("TypePointer"):
            return pt.get("PropertyKey")
    return None


def tab_path(m, qn, widget, host=None, depth=3):
    """(tabs, why) for reaching widget on page qn. tabs: [{"tab", "caption", "control"}], outermost first, one per
    tab page above the widget that its tab control does not show when the page opens (shown_tab_page): the journey
    clicks each before it clicks the widget. Snippet calls are followed (FormCall.Form, read from a real 9.x/10.x
    model) up to depth levels; host: the snippet that holds the widget (actions.json "on"), so a page widget of the
    same name does not answer (widget names are unique per document, not per page). why is None, or why the path is
    not certain: the widget is not in qn's tree, or a tab control picks its page from an attribute or variable (its
    tab is clicked anyway, the run then shows whether it was needed). PR-F35: a widget among a Pop-up menu's items
    (any property but menuTrigger) adds {"menu": <popup name>, "caption": "menu", "control": <popup name>} in its
    place in the order: Purchase Request pipe-30, the admin's 7 workflow actions sit in "Possible actions" and all
    FAILed "not visible" on the healthy OLD app. B4T2-11, B4N1-8: action journeys never clicked
    the tab page holding the widget, so 31 of 32 generated journeys FAILed on the healthy OLD app (StarterKit.HowTo,
    actionButton1 on tabPage1, ...)."""
    host = None if host == qn else host

    def find(x, trail, d, inside):
        if isinstance(x, dict):
            t = x.get("$Type", "")
            if inside and x.get("Name") == widget and ("Forms$" in t or "CustomWidgets$" in t or "Pages$" in t):
                return trail
            if "SnippetCall" in t and d > 0:
                s = (x.get("FormCall") or {}).get("Form") if isinstance(x.get("FormCall"), dict) else None
                if s and s in m.docs:
                    r = find(m.docs[s].data, trail, d - 1, host is None or s == host)
                    if r is not None:
                        return r
            for k, v in x.items():
                if k in SKIP_KEYS:
                    continue
                if t == "CustomWidgets$CustomWidget" and k == "Object" and isinstance(v, dict) and is_popup_menu(x):
                    for pr in v.get("Properties") or []:
                        if isinstance(pr, dict):
                            r = find(pr, trail + ([] if popup_key(x, pr) == "menuTrigger" else [(x, None)]), d, inside)
                            if r is not None:
                                return r
                    continue
                if t.endswith("$TabControl") and k == "TabPages":
                    for p in v or []:
                        if isinstance(p, dict):
                            r = find(p, trail + [(x, p)], d, inside)
                            if r is not None:
                                return r
                    continue
                r = find(v, trail, d, inside)
                if r is not None:
                    return r
        elif isinstance(x, list):
            for v in x:
                r = find(v, trail, d, inside)
                if r is not None:
                    return r
        return None

    doc = m.docs.get(qn)
    trail = find(doc.data, [], depth, host is None) if doc else None
    if trail is None:
        return [], (f"{widget} not found on {qn or '?'}" + (f" via snippet {host}" if host else "") +
                    ("" if doc else " (document not in the model)"))
    tabs, why = [], None
    for tc, tp in trail:
        if tp is None:          # PR-F35: a popup menu item, hidden until the menu is opened
            tabs.append({"menu": tc.get("Name") or "?", "caption": "menu", "control": tc.get("Name") or "?"})
            continue
        shown = shown_tab_page(tc)
        if shown is None and not why:
            why = (f"tab control {tc.get('Name') or '?'} picks its tab from an attribute or variable: "
                   f"{tp.get('Name') or '?'} clicked, not proven needed")
        if tp is not shown:
            tabs.append({"tab": tp.get("Name") or "?", "caption": text_of(tp.get("Caption")) or "",
                         "control": tc.get("Name") or "?"})
    return tabs, why


def walk_rendered(data, visit, skip_key=lambda k: False):
    """Walk a document's widget tree, calling visit(node, depth, blocked) on every dict. blocked is True for content
    that may not render or render once: under a conditionally visible or desktop-hidden widget, a REPEATING or
    pluggable widget or snippet call, or a tab page the tab control does not show first (G-3). Keys for which
    skip_key(key) is true are not entered. depth counts widget nesting (1 = top level of the page)."""
    def walk(x, depth, blocked):
        if isinstance(x, dict):
            t = x.get("$Type", "")
            is_w = isinstance(x.get("Name"), str) and ("Forms$" in t or "CustomWidgets$" in t or "Pages$" in t)
            visit(x, depth, blocked)
            hid = is_w and (bool(x.get("ConditionalVisibilitySettings")) or hidden_on_desktop(x))
            nb = blocked or (is_w and (hid or bool(REPEATING.search(t)) or t.startswith("CustomWidgets$")
                                       or "SnippetCall" in t))
            shown = shown_tab_page(x) if t.endswith("$TabControl") else None
            for k, v in x.items():
                if skip_key(k):
                    continue
                if t.endswith("$TabControl") and k == "TabPages":
                    for p in v or []:
                        if isinstance(p, dict):
                            walk(p, depth + 1, nb or p is not shown)
                    continue
                walk(v, depth + (1 if is_w else 0), nb)
        elif isinstance(x, list):
            for v in x:
                walk(v, depth, blocked)
    walk(data, 0, False)


def guard_widgets(m, qn):
    """[(widget dict, depth)] of the document's own widget tree that can serve as a guard: see NOT_A_WIDGET,
    REPEATING and walk_rendered (a widget hidden on desktop or on a tab page not shown first is no guard: G-3).
    depth counts widget nesting (1 = top level of the page)."""
    d = m.docs.get(qn)
    out = []

    def visit(x, depth, blocked):
        t = x.get("$Type", "")
        is_w = isinstance(x.get("Name"), str) and ("Forms$" in t or "CustomWidgets$" in t or "Pages$" in t)
        if is_w and not blocked and not x.get("ConditionalVisibilitySettings") and not hidden_on_desktop(x) \
                and not NOT_A_WIDGET.search(t) and not NON_RENDERING.search(t) \
                and not NON_RENDERING_NAME.match(x["Name"]) and not draws_nothing(x):
            out.append((x, depth))
    if d:
        walk_rendered(d.data, visit)
    return out


def draws_nothing(w):
    """FN-5: an HTML snippet pluggable widget (HTMLSnippet.widget.HTMLSnippet) set to JavaScript draws no element a
    user sees; as a landing guard it never became visible (a tab-focus script taken as the guard FAILed "never
    appeared" on the healthy OLD app)."""
    if w.get("$Type") != "CustomWidgets$CustomWidget" or "htmlsnippet" not in str((w.get("Type") or {}).get("WidgetId") or "").lower():
        return False
    for pr in ((w.get("Object") or {}).get("Properties") or []):
        if isinstance(pr, dict) and popup_key(w, pr) == "contenttype":
            v = (pr.get("Value") or {}).get("PrimitiveValue") if isinstance(pr.get("Value"), dict) else None
            return str(v).lower() in ("js", "jsjquery")
    return False


DATA_SOURCE_DEPENDENT = re.compile(r"\$(MicroflowSource|NanoflowSource|AssociationSource|ListenTargetSource)$")


def data_dependent(m, qn):
    """(inside, around): names of the data views on document qn whose object depends on the data (DATA_SOURCE_DEPENDENT
    data source, or a Forms$DataViewSource over an association path: EntityRef DomainModels$IndirectEntityRef, 18 of the
    93 such data views of the T6R 9.24 model) plus every named widget inside them, and names of the widgets that contain
    such a data view (T6R-3). A data view on a page or snippet parameter itself (DirectEntityRef), or with no data source,
    renders whenever the page opens and is not listed."""
    d = m.docs.get(qn)
    inside, around = set(), set()

    def walk(x, anc, dep):
        if isinstance(x, dict):
            t = x.get("$Type", "")
            name = x.get("Name") if isinstance(x.get("Name"), str) and ("Forms$" in t or "CustomWidgets$" in t) else None
            ds = x.get("DataSource") if isinstance(x.get("DataSource"), dict) else {}
            er = ds.get("EntityRef") if isinstance(ds.get("EntityRef"), dict) else {}
            here = dep or (t == "Forms$DataView" and (bool(DATA_SOURCE_DEPENDENT.search(ds.get("$Type", "")))
                                                      or er.get("$Type") == "DomainModels$IndirectEntityRef"))
            if here and name:
                inside.add(name)
            if here and not dep:
                around.update(anc)
            sub = anc + ((name,) if name else ())
            for v in x.values():
                walk(v, sub, here)
        elif isinstance(x, list):
            for v in x:
                walk(v, anc, dep)
    if d:
        walk(d.data, (), False)
    return inside, around - inside


def landing_widget(m, page_qn, exclude=()):
    """A widget on the page itself (not its layout) to use as the landing guard.
    Only widgets that render once on the page whatever its data (guard_widgets: no page parameter or variable, no
    snippet call, nothing inside a list view, data grid, template grid, gallery or pluggable widget, nothing under a
    conditionally visible or desktop-hidden widget, nothing on a tab page that is not shown first: G-3). Preference:
    the page title, then the outermost data view, then distinctive names, then content widgets, outermost first
    (T1-25, T2-10, T4-7). B2-2: the title comes first because a data view can be in the DOM with zero height (T8R2
    Dashboard.DashboardAll dataView1: boundingBox 256 x 0, content positioned out of flow) and the engine's ready check
    is an instant isVisible: the healthy OLD app FAILed; pageTitle1 on the same page was visible (155 x 41). The model
    holds no layout box, so the widget that renders text of its own wins.
    Names in `exclude` (widgets the login page or the guest home also render) are skipped: a guard that
    the login screen satisfies would let a failed login pass. Names the page's layout also uses are skipped
    too, and so are widgets with conditional visibility: in E5b the page's "container1" shared its name with a
    hidden container in the layout, the runner matched the hidden one and healthy pages FAILed (E5b 9, E5b 23).
    T6R-3: a data view whose object comes from a microflow, nanoflow, association or listen-to source (data_dependent)
    renders only when that source returns an object for the signed-in user. The T6R Inspector home picked dataView3
    (microflow source: the user's departments); the seeded Inspector had none, ".mx-name-dataView3" never appeared and
    the healthy OLD app FAILed. Such a data view and everything inside it is no guard; a widget that contains one
    (layout grid, container) is taken only when nothing else is left, since it may be empty with zero height (B2-2).
    No guard left: None, the journey stays a todo, never a guess."""
    lay = {w["Name"] for q in layout_closure(m, page_qn) for w in m.widgets(q) if isinstance(w.get("Name"), str)}
    inside, around = data_dependent(m, page_qn)
    cands = [(w, dep) for w, dep in guard_widgets(m, page_qn)
             if w["Name"] not in exclude and w["Name"] not in lay and w["Name"] not in inside]
    # stable: outermost first, model order within a depth; a widget around a data-dependent data view last (T6R-3)
    ws = [w for w, _ in sorted(cands, key=lambda c: (c[0]["Name"] in around, c[1]))]
    dv = [w for w in ws if w.get("$Type") == "Forms$DataView"]
    title = [w for w in ws if TITLE.search(w.get("$Type", "")) or re.match(r"^pageTitle\d*$", w["Name"])]
    good = [w for w in ws if not GENERIC_NAME.match(w["Name"])]
    content = [w for w in ws if w.get("$Type") not in ("Forms$DivContainer", "Forms$GroupBox")]
    pick = (title[:1] or dv[:1] or good or content or ws)[:1]
    return {"widget": pick[0]["Name"], "type": pick[0]["$Type"], "generic_name": not good} if pick else None


def guard_names(m, page_qn):
    """Names landing_widget may pick on this page (ignoring the exclude set): to re-check an older impact.json."""
    lay = {w["Name"] for q in layout_closure(m, page_qn) for w in m.widgets(q) if isinstance(w.get("Name"), str)}
    return {w["Name"] for w, _ in guard_widgets(m, page_qn)} - lay


def snippet_closure(m, qn, depth=3):
    out, frontier = [qn], [qn]
    for _ in range(depth):
        nxt = []
        for q in frontier:
            for r in m.refs(q):
                d = m.docs.get(r)
                if d and d.type == "Forms$Snippet" and r not in out:
                    out.append(r)
                    nxt.append(r)
        frontier = nxt
    return out


def login_facts(m, nav):
    prof = next(iter(nav.values()), {}) if nav else {}
    lp = prof.get("login_page") or ""
    found = {"login_page": lp, "id": None, "password": None, "button": None, "other_text_boxes": [], "docs": []}
    docs = snippet_closure(m, lp) if lp else []
    if not docs:  # default login.html: no model page
        return found
    found["docs"] = docs
    for q in docs:
        for w in m.widgets(q):
            t = w["$Type"]
            if t == "Forms$LoginIdTextBox":
                found["id"] = found["id"] or w["Name"]
            elif t == "Forms$PasswordTextBox":
                found["password"] = found["password"] or w["Name"]
            elif t == "Forms$LoginButton":
                found["button"] = found["button"] or w["Name"]
            elif t == "Forms$TextBox":
                found["other_text_boxes"].append({"widget": w["Name"], "in": q})
    return found


def role_facts(m, roles):
    nav = m.navigation()
    web = next((v for v in nav.values() if (v.get("kind") or "").lower().startswith("responsive")),
               next(iter(nav.values()), {}))
    menu = web.get("menu", [])
    tops = collections.OrderedDict()
    for it in menu:
        tops.setdefault(it["path"][0], []).append(it)
    out = {}
    pre_login = set()  # widget names visible before a real login: login page and guest home closures
    guest_home = next((h for h in web.get("homes", []) if h["role"] == roles.guest), None) if roles.guest else None
    for q in [web.get("login_page") or "", (guest_home or {}).get("page") or ""]:
        for d in (snippet_closure(m, q) if q else []):
            pre_login |= {w["Name"] for w in m.widgets(d) if isinstance(w.get("Name"), str)}
    for r in roles.all:
        default = next((h for h in web.get("homes", []) if h["role"] == "*"), {})
        home = next((h for h in web.get("homes", []) if h["role"] == r), None) or default
        visible, hidden = [], []
        for cap, items in tops.items():
            targets = [i for i in items if i["target"]]
            ok = any(r in roles.of_doc(i["target"]) for i in targets)
            if not targets:  # sign-out, url, no target: always shown
                ok = None
            if ok:
                visible.append(cap)
            elif ok is False:
                hidden.append(cap)
        hp = home.get("page") or ""
        out[r] = {"home_page": hp, "home_microflow": home.get("microflow") or "",
                  "home_role_specific": home is not default,
                  "landing": landing_widget(m, hp, () if r == roles.guest else pre_login) if hp else None,
                  "menu_visible": visible, "menu_hidden": hidden,
                  "sign_out_item": next((i["path"] for i in menu if i["kind"] == "SignOutClientAction"), None),
                  "is_admin": r == roles.admin, "is_guest": r == roles.guest}
    return out, web, nav


# ---------------------------------------------------------------- graph helpers
def flow_tree(m, root, limit=3000):
    """Transitive closure of flows/pages called from root (refs restricted to flow and java/js documents)."""
    seen, stack = set(), [root]
    while stack and len(seen) < limit:
        q = stack.pop()
        if q in seen or q not in m.docs:
            continue
        seen.add(q)
        for r in m.refs(q):
            d = m.docs.get(r)
            if d and d.type in FLOW_TYPES and r not in seen:
                stack.append(r)
    return seen


def tree_refs_constants(m, tree):
    out = set()
    for q in tree:
        for r in m.refs(q):
            d = m.docs.get(r)
            if d and d.type == "Constants$Constant":
                out.add(r)
    return out


class EntryFinder:
    """Walk callers upward from a document to the entry points that reach it (new project)."""

    def __init__(self, m, roles, web, startup_tree, sched):
        self.m, self.roles = m, roles
        self.callers = m.callers_index()
        self.menu_by_target = collections.defaultdict(list)
        for it in web.get("menu", []):
            if it["target"]:
                self.menu_by_target[it["target"]].append(it["path"])
        self.home_pages = {h["page"]: h["role"] for h in web.get("homes", []) if h.get("page")}
        self.home_pages.update({h["microflow"]: h["role"] for h in web.get("homes", []) if h.get("microflow")})
        self.startup_tree = startup_tree
        self.sched = sched  # microflow -> event name

    def entries(self, qn, max_nodes=600, max_depth=8):
        out, seen = [], {qn}
        frontier = [(qn, [qn])]
        depth = 0
        while frontier and depth <= max_depth and len(seen) < max_nodes:
            nxt = []
            for q, path in frontier:
                d = self.m.docs.get(q)
                typ = d.type if d else ""
                if q in self.menu_by_target:
                    for mp in self.menu_by_target[q]:
                        out.append({"kind": "menu", "menu": mp, "target": q, "via": path,
                                    "roles": sorted(self.roles.of_doc(q))})
                if q in self.home_pages:
                    out.append({"kind": "home", "target": q, "via": path, "home_role": self.home_pages[q],
                                "roles": sorted(self.roles.of_doc(q))})
                if q in self.startup_tree:
                    out.append({"kind": "startup", "target": q, "via": path, "roles": []})
                if q in self.sched:
                    out.append({"kind": "scheduled", "target": self.sched[q], "via": path, "roles": []})
                if typ in SERVICE_TYPES:
                    out.append({"kind": "service", "target": q, "via": path, "roles": sorted(self.roles.of_doc(q))})
                if typ == "Forms$Page" and self.m.page_roles(q) and q not in self.menu_by_target:
                    out.append({"kind": "page", "target": q, "via": path, "roles": sorted(self.roles.of_doc(q))})
                if typ in ("Microflows$Microflow",) and d.data.get("AllowedModuleRoles"):
                    out.append({"kind": "client_microflow", "target": q, "via": path,
                                "roles": sorted(self.roles.of_doc(q))})
                for c in self.callers.get(q, ()):
                    cd = self.m.docs.get(c)
                    if not cd or c in seen:
                        continue
                    if cd.type in DOC_TYPES or cd.type in SERVICE_TYPES or cd.type == "Constants$Constant":
                        seen.add(c)
                        nxt.append((c, path + [c]))
            frontier = nxt
            depth += 1
        # one entry per (kind, target), shortest path kept
        best = {}
        for e in out:
            k = (e["kind"], e["target"], tuple(e.get("menu") or ()))
            if k not in best or len(e["via"]) < len(best[k]["via"]):
                best[k] = e
        return list(best.values())


# ---------------------------------------------------------------- domain model (entities, attributes, rules)
def _short(t):
    """DomainModels$StringAttributeType -> String, DomainModels$RequiredRuleInfo -> Required."""
    t = (t or "").split("$")[-1]
    for suf in ("AttributeType", "RuleInfo"):
        if t.endswith(suf) and len(t) > len(suf):
            return t[: -len(suf)]
    return t


def _named(xs):
    """The named dict items of a BSON list (its leading int marker skipped), keyed by Name."""
    return {x["Name"]: x for x in xs or [] if isinstance(x, dict) and x.get("Name")}


def _attr_type(a):
    t = a.get("Type") if isinstance(a.get("Type"), dict) else {}
    enum = t.get("Enumeration")
    return _short(t.get("$Type")) + (f"({enum})" if enum else "")


def _attr_default(a):
    """The stored default value, None for a calculated attribute. Boolean defaults compare case-insensitively."""
    v = a.get("Value") if isinstance(a.get("Value"), dict) else {}
    if v.get("$Type", "").endswith("CalculatedValue"):
        return None
    d = str(v.get("DefaultValue") or "")
    t = a.get("Type") if isinstance(a.get("Type"), dict) else {}
    return d.lower() if t.get("$Type", "").endswith("BooleanAttributeType") else d


def _rules_by_attr(e):
    """Validation rules of an entity (they sit on the entity, each names its attribute), keyed by attribute name."""
    out = collections.defaultdict(list)
    for r in e.get("ValidationRules") or []:
        if isinstance(r, dict) and isinstance(r.get("RuleInfo"), dict):
            out[(r.get("Attribute") or "").rsplit(".", 1)[-1]].append(r["RuleInfo"])
    return out


def _access_sig(r):
    """One access rule as a comparable tuple: roles, create, delete, default member rights, member rights, XPath.
    Read field by field, so the rule's $ID and any position never reach the comparison."""
    members = tuple(sorted((m.get("Attribute") or m.get("Association") or "", m.get("AccessRights") or "")
                           for m in r.get("MemberAccesses") or [] if isinstance(m, dict)))
    return (tuple(sorted(x for x in r.get("AllowedModuleRoles") or [] if isinstance(x, str))),
            bool(r.get("AllowCreate")), bool(r.get("AllowDelete")), r.get("DefaultMemberAccessRights") or "None",
            members, r.get("XPathConstraint") or "")


_RIGHTS = {"None": 0, "ReadOnly": 1, "ReadWrite": 2}


def _access_changes(oe, ne):
    """Access rule differences of one entity, compared rule by rule (keyed by the rule's role set) and member by
    member. Severity says what a user can lose: high when a role set's rule is gone, create or delete is taken away,
    or a member both rules list loses rights; medium when the XPath or the default member rights change, or a rule
    for a new role set appears; low when only members appear or disappear (an attribute or association added,
    removed or renamed is already its own record) or rights only grow."""
    def by_roles(e):
        out = {}
        for r in e.get("AccessRules") or []:
            if isinstance(r, dict):
                sig = _access_sig(r)
                out.setdefault(sig[0], []).append(sig)
        return out
    o, n = by_roles(oe), by_roles(ne)
    res = []
    for roles in sorted(set(o) | set(n)):
        label = ", ".join(roles) or "no roles"
        if roles not in n:
            res.append((f"access rule for {label} removed", "high"))
            continue
        if roles not in o:
            res.append((f"access rule for {label} added", "medium"))
            continue
        if sorted(o[roles]) == sorted(n[roles]):
            continue
        if len(o[roles]) != 1 or len(n[roles]) != 1:
            res.append((f"access rules for {label} changed ({len(o[roles])} -> {len(n[roles])} rules)", "high"))
            continue
        (_, oc, od, odm, om, ox), (_, nc, nd, ndm, nm, nx) = o[roles][0], n[roles][0]
        bits, sev = [], "low"
        def up(level):
            nonlocal sev
            if ["low", "medium", "high"].index(level) > ["low", "medium", "high"].index(sev):
                sev = level
        for what, a, b in (("create", oc, nc), ("delete", od, nd)):
            if a != b:
                bits.append(f"{what} {'allowed' if b else 'removed'}")
                up("high" if a and not b else "medium")
        if odm != ndm:
            bits.append(f"default member rights {odm} -> {ndm}")
            up("high" if _RIGHTS.get(ndm, 0) < _RIGHTS.get(odm, 0) else "medium")
        if ox != nx:
            bits.append("xpath changed")
            up("medium")
        om, nm = dict(om), dict(nm)
        lost = sorted(m for m in om.keys() & nm.keys() if _RIGHTS.get(nm[m], 0) < _RIGHTS.get(om[m], 0))
        grew = sorted(m for m in om.keys() & nm.keys() if _RIGHTS.get(nm[m], 0) > _RIGHTS.get(om[m], 0))
        if lost:
            bits.append("rights lost on " + ", ".join(f"{m.rsplit('.', 1)[-1]} {om[m]} -> {nm[m]}" for m in lost))
            up("high")
        if grew:
            bits.append("rights gained on " + ", ".join(f"{m.rsplit('.', 1)[-1]} {om[m]} -> {nm[m]}" for m in grew))
            up("medium")
        added, gone = sorted(nm.keys() - om.keys()), sorted(om.keys() - nm.keys())
        if added or gone:
            bits.append(f"members +{len(added)} -{len(gone)}")
        res.append((f"access rule for {label}: " + "; ".join(bits), sev))
    return res


def domain_changes(old, new):
    """Entity and attribute changes in every module's $DomainModel that both models have. Each hit: qn (the entity or
    the attribute), detail, severity, module, entity, doc, propagate (a flow or page using the entity may break, so the
    caller trace follows it) and gone (the entity itself was removed). Keyed by name, so order, ids, GUIDs and
    positions never show: a model compared to itself gives no hit."""
    out = []

    def hit(qn, detail, sev, mod, ent, **kw):
        out.append(dict(qn=qn, detail=detail, severity=sev, module=mod, entity=ent, doc=f"{mod}.$DomainModel",
                        **{"propagate": False, "gone": False, **kw}))

    dms_old = {d.module: d for d in old.docs.values() if d.type == "DomainModels$DomainModel" and d.module}
    dms_new = {d.module: d for d in new.docs.values() if d.type == "DomainModels$DomainModel" and d.module}
    for mod in sorted(set(dms_old) & set(dms_new)):
        o, n = dms_old[mod].data, dms_new[mod].data
        oe, ne = _named(o.get("Entities")), _named(n.get("Entities"))
        for en in sorted(set(oe) | set(ne)):
            eq = f"{mod}.{en}"
            oen, nen = oe.get(en), ne.get(en)
            if oen is None:
                hit(eq, f"entity added ({len(_named(nen.get('Attributes')))} attributes)", "low", mod, eq)
                continue
            if nen is None:
                hit(eq, "entity removed", "high", mod, eq, propagate=True, gone=True)
                continue
            oa, na = _named(oen.get("Attributes")), _named(nen.get("Attributes"))
            orules, nrules = _rules_by_attr(oen), _rules_by_attr(nen)
            for an in sorted(set(oa) | set(na)):
                aq = f"{eq}.{an}"
                x, y = oa.get(an), na.get(an)
                if x is None:
                    hit(aq, f"attribute added ({_attr_type(y)})", "low", mod, eq)
                    continue
                if y is None:
                    hit(aq, f"attribute removed (was {_attr_type(x)})", "high", mod, eq, propagate=True)
                    continue
                if _attr_type(x) != _attr_type(y):
                    hit(aq, f"type {_attr_type(x)} -> {_attr_type(y)}", "high", mod, eq, propagate=True)
                if _attr_default(x) != _attr_default(y):
                    hit(aq, f"default: {(_attr_default(x) or '')!r} -> {(_attr_default(y) or '')!r}", "medium",
                        mod, eq, propagate=True)
                ol, nl = orules.get(an, []), nrules.get(an, [])
                ol_labels = sorted(_short(r.get("$Type")) for r in ol)
                nl_labels = sorted(_short(r.get("$Type")) for r in nl)
                if ol_labels != nl_labels:
                    hit(aq, f"validation: [{', '.join(ol_labels)}] -> [{', '.join(nl_labels)}]", "medium", mod, eq,
                        propagate=True)
                elif not all(same(p, q) for p, q in zip(sorted(ol, key=lambda r: r.get("$Type", "")),
                                                        sorted(nl, key=lambda r: r.get("$Type", "")))):
                    hit(aq, f"validation rule settings changed ({', '.join(nl_labels)})", "medium", mod, eq,
                        propagate=True)
            for detail, sev in _access_changes(oen, nen):
                hit(eq, detail, sev, mod, eq, propagate=sev != "low")
    return out


# ---------------------------------------------------------------- diff
def diff(old, new, declared_updates=None):
    changes = []

    def add(kind, qn, detail, module=None, severity="medium", **kw):
        changes.append(dict(kind=kind, qn=qn, module=module or (qn.split(".")[0] if "." in qn else qn),
                            detail=detail, severity=severity, **kw))

    # modules
    for name in sorted(set(old.modules) | set(new.modules)):
        o, n = old.modules.get(name), new.modules.get(name)
        if not o:
            add("module", name, f"added ({n['version'] or 'own'})", severity="high" if AUTH_MODULES.search(name) else "medium",
                old=None, new=n["version"])
        elif not n:
            add("module", name, f"removed (was {o['version'] or 'own'})", severity="high", old=o["version"], new=None)
        elif o["version"] != n["version"]:
            add("module", name, f"{o['version']} -> {n['version']}",
                severity="high" if AUTH_MODULES.search(name) else "medium", old=o["version"], new=n["version"])
    if declared_updates:
        found = {c["qn"] for c in changes if c["kind"] == "module"}
        for name in declared_updates:
            if name not in found:
                add("module", name, "declared in the update list but the project shows no version change",
                    severity="info")

    # constants
    for qn in sorted({d.qn for d in old.of_type("Constants$Constant")} | {d.qn for d in new.of_type("Constants$Constant")}):
        o, n = old.constant(qn), new.constant(qn)
        if o and not n:
            add("constant", qn, f"removed (default was {o['default']!r})", severity="high", old=o, new=None)
        elif n and not o:
            add("constant", qn, f"added, default {n['default']!r} ({n['type']})", severity="low", old=None, new=n,
                added=True)
        elif _cval(o) != _cval(n) or o["type"] != n["type"]:
            add("constant", qn, f"default {o['default']!r} -> {n['default']!r}" +
                (f", type {o['type']} -> {n['type']}" if o["type"] != n["type"] else ""),
                severity="high", old=o, new=n)

    # after-startup / before-shutdown
    oa, na = old.after_startup(), new.after_startup()
    for k in ("AfterStartupMicroflow", "BeforeShutdownMicroflow", "HealthCheckMicroflow"):
        if (oa.get(k) or "") != (na.get(k) or ""):
            add("startup", na.get(k) or oa.get(k) or k, f"{k}: {oa.get(k) or '(none)'} -> {na.get(k) or '(none)'}",
                module="(project)", severity="high")
    o_tree = flow_tree(old, oa.get("AfterStartupMicroflow") or "")
    n_tree = flow_tree(new, na.get("AfterStartupMicroflow") or "")
    t_added = sorted(n_tree - o_tree)
    t_removed = sorted(o_tree - n_tree)
    t_changed = sorted(q for q in o_tree & n_tree if not same(old.docs[q].data, new.docs[q].data))
    if t_added or t_removed or t_changed:
        add("startup", na.get("AfterStartupMicroflow") or "(none)",
            f"after-startup call tree: {len(t_added)} added, {len(t_removed)} removed, {len(t_changed)} changed "
            f"(old tree {len(o_tree)}, new tree {len(n_tree)})", module="(project)", severity="high",
            added=t_added, removed=t_removed, changed=t_changed,
            # still in the new model but no longer run at startup: a deprecated or replaced startup flow
            # (E1: MFAmodule 5 left ASU_MFA in place, hollowed out, and the project tree stopped calling it)
            not_called=[q for q in t_removed if q in new.docs])
    for c in [c for c in changes if c["kind"] == "constant"]:
        users_new = [q for q in n_tree if c["qn"] in new.refs(q)]
        users_old = [q for q in o_tree if c["qn"] in old.refs(q)]
        if users_new or users_old:
            c["severity"] = "medium" if c.get("added") else "high"
            c["in_startup_tree"] = sorted(set(users_new) | set(users_old))

    # scheduled events
    def sched(m):
        return {d.qn: d.data for d in m.of_type("ScheduledEvents$ScheduledEvent")}
    os_, ns_ = sched(old), sched(new)
    for qn in sorted(set(os_) | set(ns_)):
        o, n = os_.get(qn), ns_.get(qn)
        if not n:
            add("scheduled", qn, "removed", severity="high")
            continue
        if not o:
            add("scheduled", qn, f"added (enabled={n.get('Enabled')}, {n.get('Microflow')})",
                severity="medium" if n.get("Enabled") else "low")
            continue
        bits = []
        for k in ("Enabled", "Microflow", "Interval", "IntervalType", "StartDateTime", "OnOverlap"):
            if o.get(k) != n.get(k) and not (o.get(k) is None and n.get(k) in ("", None)):
                bits.append(f"{k} {o.get(k)} -> {n.get(k)}")
        ot, nt = flow_tree(old, o.get("Microflow") or ""), flow_tree(new, n.get("Microflow") or "")
        tc = sorted(q for q in ot & nt if not same(old.docs[q].data, new.docs[q].data)) + sorted(nt ^ ot)
        if tc:
            bits.append(f"call tree changed ({len(tc)} documents)")
        if bits:
            add("scheduled", qn, "; ".join(bits), severity="high" if n.get("Enabled") else "low",
                tree_changed=tc[:50])

    # documents (flows, pages)
    changed_docs, removed_docs = [], []
    for qn, od in old.docs.items():
        if od.type not in DOC_TYPES:
            continue
        nd = new.docs.get(qn)
        if not nd:
            removed_docs.append(qn)
        elif not same(od.data, nd.data):
            changed_docs.append(qn)
    added_docs = sorted(q for q, d in new.docs.items() if d.type in DOC_TYPES and q not in old.docs)
    own = {n for n, i in new.modules.items() if not i["from_appstore"]}
    for qn in sorted(removed_docs):
        add("document", qn, f"{old.docs[qn].type.split('$')[1]} removed",
            severity="high" if qn.split(".")[0] in own else "medium", doc_type=old.docs[qn].type)
    widget_only = set()
    for qn in sorted(changed_docs):
        od, nd = old.docs[qn], new.docs[qn]
        if same(strip_widget_defs(od.data), strip_widget_defs(nd.data)):
            widget_only.add(qn)
            add("document", qn, f"{nd.type.split('$')[1]}: only pluggable widget definitions refreshed",
                severity="low", doc_type=nd.type, widget_refresh=True)
            continue
        where = (f"type {od.type} -> {nd.type}" if od.type != nd.type else f"at {first_diff(od.data, nd.data)}")
        add("document", qn, f"{nd.type.split('$')[1]} changed {where}",
            severity="medium" if qn.split(".")[0] in own else "low", doc_type=nd.type)
    for qn in added_docs:
        if qn.split(".")[0] in own:
            add("document", qn, f"{new.docs[qn].type.split('$')[1]} added in own module", severity="low",
                doc_type=new.docs[qn].type)

    # domain model: entities, attributes, validation and access rules, one document record per difference
    dm = domain_changes(old, new)
    for h in dm:
        add("document", h["qn"], h["detail"], module=h["module"],
            severity=h["severity"] if h["module"] in own else "low", doc_type="DomainModels$DomainModel", doc=h["doc"])

    # own-module callers of changed/removed marketplace documents
    vendor_touched = {q for q in changed_docs + removed_docs if q.split(".")[0] not in own and q not in widget_only}
    callers = new.callers_index()
    for q in sorted(q for q in vendor_touched if old.docs[q].type == "Forms$Layout"):
        users = [c for c in callers.get(q, ()) if new.docs.get(c) and new.docs[c].type == "Forms$Page"]
        own_users = [c for c in users if c.split(".")[0] in own]
        if own_users:
            add("caller", q, f"layout changed; used by {len(own_users)} own pages (theme/visual impact: smoke walk "
                f"and screenshots, not one journey per page)", severity="medium", target=q, layout=True,
                pages=sorted(own_users))
    for q in sorted(q for q in vendor_touched if old.docs[q].type != "Forms$Layout"):
        for c in sorted(callers.get(q, ())):
            cd = new.docs.get(c)
            if cd and c.split(".")[0] in own and cd.type in DOC_TYPES | SERVICE_TYPES:
                add("caller", c, f"calls {q} ({'removed' if q in removed_docs else 'changed'})", severity="high"
                    if q in removed_docs else "medium", target=q)
    # removed documents still referenced (dangling)
    for q in sorted(removed_docs):
        for c in sorted(callers.get(q, ())):
            if new.excluded(c):  # an excluded example page is not built and cannot fail (E4 31)
                continue
            add("caller", c, f"still references removed {q}", severity="high", target=q)
    # domain model: the own flows and pages that use a changed entity. They reference it by name, so callers_index
    # finds them, the same trace a changed marketplace document gets. New attributes and entities break no caller.
    by_entity = collections.defaultdict(list)
    for h in dm:
        if h["propagate"]:
            by_entity[h["entity"]].append(h)
    for ent in sorted(by_entity):
        hs = by_entity[ent]
        gone = any(h["gone"] for h in hs)
        # a caller is a place to look, not a proven break: high only for a removed entity, attribute or type change
        sev = "high" if gone or any(h["severity"] == "high" and not h["detail"].startswith("access") for h in hs) \
            else "medium"
        parts = [h["qn"][len(ent) + 1:] + " " + h["detail"].split(":")[0].split(" (")[0] if h["qn"] != ent
                 else h["detail"].split(":")[0] for h in hs]
        why = "; ".join(parts[:3]) + (f"; +{len(parts) - 3} more" if len(parts) > 3 else "")
        for c in sorted(callers.get(ent, ())):
            cd = new.docs.get(c)
            if not cd or c.split(".")[0] not in own or cd.type not in DOC_TYPES | SERVICE_TYPES or new.excluded(c):
                continue
            add("caller", c, f"still references removed entity {ent}" if gone else f"uses {ent} ({why})",
                severity=sev, target=ent)

    # security
    our, nur = old.user_roles(), new.user_roles()
    for r in sorted(set(our) | set(nur)):
        if r not in nur:
            add("security", r, "user role removed", module="(security)", severity="high")
        elif r not in our:
            add("security", r, "user role added", module="(security)", severity="medium")
        elif our[r] != nur[r]:
            plus, minus = sorted(set(nur[r]) - set(our[r])), sorted(set(our[r]) - set(nur[r]))
            add("security", r, f"module roles +{plus} -{minus}", module="(security)", severity="high",
                added=plus, removed=minus)
    os_sum, ns_sum = old.security_summary(), new.security_summary()
    for k in os_sum:
        if not same(os_sum[k], ns_sum.get(k)):
            add("security", k, f"{os_sum[k]} -> {ns_sum.get(k)}", module="(security)", severity="high")
    for qn, od in old.docs.items():
        if od.type == "Security$ModuleSecurity":
            nd = new.docs.get(qn)
            if nd and not same(od.data, nd.data):
                orl = {r.get("Name") for r in od.data.get("ModuleRoles") or [] if isinstance(r, dict)}
                nrl = {r.get("Name") for r in nd.data.get("ModuleRoles") or [] if isinstance(r, dict)}
                add("security", qn, f"module roles +{sorted(nrl - orl)} -{sorted(orl - nrl)}"
                    if orl != nrl else "module security changed (access rules or role details)",
                    severity="high" if orl - nrl else "medium")
    # page access: a page lost or gained roles
    for qn, od in old.docs.items():
        nd = new.docs.get(qn)
        if od.type == "Forms$Page" and nd:
            o, n = set(old.page_roles(qn)), set(new.page_roles(qn))
            if o != n:
                add("security", qn, f"page allowed roles +{sorted(n - o)} -{sorted(o - n)}",
                    severity="high" if o - n else "medium")

    # services
    def services(m):
        out = {}
        for d in m.docs.values():
            if d.type in SERVICE_TYPES:
                out[d.qn] = d
        return out
    osv, nsv = services(old), services(new)
    for qn in sorted(set(osv) | set(nsv)):
        o, n = osv.get(qn), nsv.get(qn)
        if not n:
            add("service", qn, f"{o.type.split('$')[1]} removed", severity="high")
        elif not o:
            add("service", qn, f"{n.type.split('$')[1]} added", severity="low")
        elif not same(o.data, n.data):
            add("service", qn, f"{n.type.split('$')[1]} changed at {first_diff(o.data, n.data)}", severity="high")
        else:
            # operation microflows changed?
            ops = [op for res in n.data.get("Resources") or [] if isinstance(res, dict)
                   for op in res.get("Operations") or [] if isinstance(op, dict)]
            hit = [op.get("Microflow") for op in ops if op.get("Microflow") in set(changed_docs)]
            if hit:
                add("service", qn, f"operation microflows changed: {hit}", severity="medium")

    return changes, {"startup_tree_old": len(o_tree), "startup_tree_new": len(n_tree),
                     "changed_docs": len(changed_docs), "removed_docs": len(removed_docs),
                     "added_docs": len(added_docs), "own_modules": sorted(own)}


# ---------------------------------------------------------------- candidates
SEV = {"high": 3, "medium": 2, "low": 1, "info": 0}


def candidates(old, new, changes, roles, rfacts, web):
    na = new.after_startup()
    startup_tree = flow_tree(new, na.get("AfterStartupMicroflow") or "")
    sched = {d.data.get("Microflow"): d.qn for d in new.of_type("ScheduledEvents$ScheduledEvent")}
    ef = EntryFinder(new, roles, web, startup_tree, sched)
    login = login_facts(new, {k: v for k, v in new.navigation().items() if v is web} or new.navigation())
    login_docs = set(login["docs"])
    cands = {}

    def cand(cid, kind, title, roles_, reason, sev, **kw):
        c = cands.setdefault(cid, dict(id=cid, kind=kind, title=title, roles=set(), reasons=[], score=0, **kw))
        c["roles"] |= set(roles_)
        if reason not in c["reasons"]:
            c["reasons"].append(reason)
        c["score"] = max(c["score"], SEV.get(sev, 1))

    human = [r for r in roles.all if r != roles.guest]
    auth_hit = []
    for ch in changes:
        why = f"{ch['kind']}: {ch['qn']}: {ch['detail']}"
        mod = ch["module"]
        is_auth = bool(AUTH_MODULES.search(mod or "")) or ch["qn"] in login_docs
        if ch["kind"] == "startup" or (ch["kind"] == "constant" and ch.get("in_startup_tree")):
            cand("startup", "startup", "App starts clean and the startup work is done (log + login per role)",
                 human, why, "high")
        if is_auth and ch["severity"] in ("high", "medium") and ch["kind"] != "document":
            auth_hit.append(why)
        if ch["kind"] == "constant" and is_auth:
            auth_hit.append(why)
        if ch["kind"] == "security":
            cand("login-per-role", "login", "Login per role lands on the role home with the role menu",
                 human, why, ch["severity"])
        if ch["kind"] == "scheduled":
            cand(f"sched:{ch['qn']}", "scheduled", f"Scheduled event {ch['qn']} still runs and does its work", [],
                 why, ch["severity"], target=ch["qn"])
        if ch["kind"] == "service":
            cand(f"svc:{ch['qn']}", "service", f"Published service {ch['qn']} answers as before (REST gate)",
                 sorted(roles.of_doc(ch["qn"])), why, ch["severity"], target=ch["qn"])
        if ch.get("layout"):
            cand("visual-smoke", "visual", "Smoke walk with screenshots over pages that use a changed layout",
                 human, why, "medium", pages=len(ch.get("pages", [])))
            continue
        if ch["kind"] in ("caller", "document", "constant") and ch["severity"] != "info":
            if ch["kind"] == "document" and ch["severity"] == "low":
                # vendor-internal edits and widget refreshes: only traced when an own document calls them ('caller')
                continue
            ents = ef.entries(ch["qn"])
            # a person reaches it through a menu or home page: that is the journey. Fall back to the nearest
            # role-gated page or client microflow only when no menu/home path exists (max 2).
            # Fallbacks only when nothing better exists, only if some user role can reach them (max 2).
            if any(e["kind"] in ("menu", "home", "startup", "scheduled", "service") for e in ents):
                ents = [e for e in ents if e["kind"] not in ("page", "client_microflow")]
            else:
                fb = sorted([e for e in ents if e["kind"] in ("page", "client_microflow") and e["roles"]],
                            key=lambda e: len(e["via"]))
                ents = [e for e in ents if e["kind"] not in ("page", "client_microflow")] + fb[:2]
            for e in ents:
                if e["kind"] == "menu":
                    cid = "menu:" + " > ".join(e["menu"])
                    cand(cid, "menu", f"Open {' > '.join(e['menu'])} and use it", e["roles"], why, ch["severity"],
                         menu=e["menu"], target=e["target"], via=e["via"])
                elif e["kind"] == "home":
                    cand(f"home:{e['target']}", "home", f"Role home page {e['target']} works",
                         e["roles"] or ([e["home_role"]] if e["home_role"] != "*" else human), why, ch["severity"],
                         target=e["target"], via=e["via"])
                elif e["kind"] == "startup":
                    cand("startup", "startup", "App starts clean and the startup work is done (log + login per role)",
                         human, why, ch["severity"])
                elif e["kind"] == "scheduled":
                    cand(f"sched:{e['target']}", "scheduled", f"Scheduled event {e['target']} still runs", [], why,
                         ch["severity"], target=e["target"])
                elif e["kind"] == "service":
                    cand(f"svc:{e['target']}", "service", f"Published service {e['target']} answers as before",
                         e["roles"], why, ch["severity"], target=e["target"])
                elif e["kind"] in ("page", "client_microflow"):
                    cand(f"{e['kind']}:{e['target']}", e["kind"],
                         f"Reach {e['target']} (no menu item; opened from another page)", e["roles"], why,
                         max(1, SEV[ch["severity"]] - 1) and ch["severity"], target=e["target"], via=e["via"])
    # Updated marketplace modules: their own role-gated pages that changed (admin dashboards, account pages).
    # No own document calls them, so the caller trace misses them; E5's TaskQueueHelpers dashboard is one.
    updated = {c["qn"] for c in changes if c["kind"] == "module" and c.get("old") and c.get("new")}
    for mod in sorted(updated):
        pages = []
        for c in changes:
            if c["kind"] == "document" and c["module"] == mod and c.get("doc_type") == "Forms$Page":
                rs = roles.of_doc(c["qn"])
                if rs:
                    pages.append((c["qn"], sorted(rs), bool(c.get("widget_refresh"))))
        if pages:
            pages.sort(key=lambda p: (p[2], p[0]))  # real edits before widget-definition refreshes
            cand(f"module-pages:{mod}", "module-pages",
                 f"Open the changed {mod} pages a role can reach and look at them (screenshot old vs new)",
                 sorted({r for p in pages for r in p[1]}), f"module: {mod} updated; {len(pages)} changed role-gated "
                 f"pages: {', '.join(p[0] for p in pages[:6])}", "medium", pages=[p[0] for p in pages])
    if auth_hit:
        for w in auth_hit:
            cand("login-per-role", "login", "Login per role lands on the role home with the role menu", human, w, "high")
        mfa_mods = [n for n in new.modules if re.search(r"MFA|GoogleAuth|TOTP", n, re.I)]
        if mfa_mods:
            for w in auth_hit:
                cand("mfa", "mfa", "A user with a second factor is challenged for the code after the password",
                     human, w, "high", modules=mfa_mods)
    for c in cands.values():
        c["roles"] = sorted(c["roles"])
        c["priority"] = {3: "P1", 2: "P2", 1: "P3", 0: "P3"}[c["score"]]
    return sorted(cands.values(), key=lambda c: (-c["score"], c["kind"], c["id"])), login


# ---------------------------------------------------------------- catalog cross-check
def catalog_check(old_mpr, new_mpr, scratch, mxcli):
    q = {"constants": "SELECT QualifiedName, DefaultValue, DataType FROM CATALOG.CONSTANTS",
         "scheduled": "SELECT Name, Enabled, Microflow FROM CATALOG.SCHEDULED_EVENTS",
         "rest_ops": "SELECT * FROM CATALOG.PUBLISHED_REST_OPERATIONS"}
    res = {}
    for tag, mpr in (("old", old_mpr), ("new", new_mpr)):
        d = os.path.join(scratch, tag)
        os.makedirs(d, exist_ok=True)
        dst = os.path.join(d, os.path.basename(mpr))
        shutil.copy2(mpr, dst)
        res[tag] = {}
        first = True
        for k, sql in q.items():
            pre = "REFRESH CATALOG FULL; " if first else ""
            first = False
            p = subprocess.run([mxcli, "-p", dst, "-c", pre + sql + ";"], capture_output=True, text=True, timeout=1200)
            rows = []
            for line in p.stdout.splitlines():
                if line.startswith("|") and not line.startswith("|--"):
                    rows.append([c.strip() for c in line.strip("|").split("|")])
            res[tag][k] = rows[1:] if rows else []
            res[tag][k + "_header"] = rows[0] if rows else []
    oc = {r[0]: r[1] for r in res["old"]["constants"]}
    nc = {r[0]: r[1] for r in res["new"]["constants"]}
    const_changed = sorted(k for k in set(oc) & set(nc) if oc[k] != nc[k])
    return {"constants_changed": [{"qn": k, "old": oc[k], "new": nc[k]} for k in const_changed],
            "constants_added": sorted(set(nc) - set(oc)), "constants_removed": sorted(set(oc) - set(nc)),
            "scheduled_old": res["old"]["scheduled"], "scheduled_new": res["new"]["scheduled"],
            "rest_ops_old": len(res["old"]["rest_ops"]), "rest_ops_new": len(res["new"]["rest_ops"])}


# ---------------------------------------------------------------- report
def markdown(rep):
    L = [f"# Upgrade impact map", "", f"old: `{rep['old']}`  ", f"new: `{rep['new']}`", "",
         "This maps changes to journeys to look at. It is not a requirement ledger.", ""]
    s = rep["stats"]
    L += [f"After-startup: `{rep['after_startup']['old']}` -> `{rep['after_startup']['new']}` "
          f"(tree {s['startup_tree_old']} -> {s['startup_tree_new']} documents)  ",
          f"Documents: {s['changed_docs']} changed, {s['removed_docs']} removed, {s['added_docs']} added", ""]
    by = collections.defaultdict(list)
    for c in rep["changes"]:
        by[c["kind"]].append(c)
    for kind in ("module", "constant", "startup", "scheduled", "security", "service", "caller", "document"):
        rows = sorted(by.get(kind, []), key=lambda c: (-SEV[c["severity"]], c["qn"]))
        if not rows:
            continue
        L += [f"## {kind} ({len(rows)})", ""]
        cap = 40 if kind == "document" else 200
        for c in rows[:cap]:
            extra = ""
            if c.get("in_startup_tree"):
                extra = f" (read in the startup tree by {', '.join(c['in_startup_tree'][:4])})"
            L.append(f"- [{c['severity']}] `{c['qn']}`: {c['detail']}{extra}")
            if kind == "startup" and (c.get("removed") or c.get("changed")):
                nc = set(c.get("not_called", []))
                if nc:
                    L.append(f"  - no longer called at startup but still in the model (deprecated or replaced?): {', '.join(sorted(nc))}")
                gone = [q for q in c.get("removed", []) if q not in nc]
                if gone:
                    L.append(f"  - removed from the model: {', '.join(gone[:12])}")
                if c.get("changed"):
                    L.append(f"  - changed in the tree: {', '.join(c['changed'][:12])}")
        if len(rows) > cap:
            L.append(f"- ... {len(rows) - cap} more (see the JSON)")
        L.append("")
    L += ["## Journey candidates", ""]
    for c in rep["candidates"]:
        L.append(f"- **{c['priority']} {c['id']}**: {c['title']}  ")
        L.append(f"  roles: {', '.join(c['roles']) or '(system, no role)'}  ")
        for r in c["reasons"][:4]:
            L.append(f"  because {r}  ")
        if len(c["reasons"]) > 4:
            L.append(f"  ... and {len(c['reasons']) - 4} more reasons  ")
    L += ["", "## Per role", ""]
    for r, f in rep["roles"].items():
        cs = [c["id"] for c in rep["candidates"] if r in c["roles"]]
        L.append(f"- **{r}** home `{f['home_page'] or f['home_microflow']}`; candidates: {', '.join(cs) or 'none'}")
    if rep.get("catalog_check"):
        cc = rep["catalog_check"]
        L += ["", "## mxcli catalog cross-check", "",
              f"constants changed (catalog): {[(c['qn'], c['old'], c['new']) for c in cc['constants_changed']]}  ",
              f"agrees with the BSON diff: {cc.get('agrees')}"]
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--updates", help="module update list: one module name per line (extra text ignored)")
    ap.add_argument("--out", help="write the full JSON here")
    ap.add_argument("--md", help="write the markdown report here")
    ap.add_argument("--catalog-check", metavar="SCRATCH", help="cross-check with mxcli catalog on copies in SCRATCH")
    ap.add_argument("--mxcli", default=os.environ.get("MXCLI", os.path.expanduser("~/.local/bin/mxcli")))
    a = ap.parse_args()
    old, new = Model.load(a.old), Model.load(a.new)
    declared = None
    if a.updates:
        declared = [ln.split()[0] for ln in open(a.updates) if ln.strip() and not ln.startswith("#")]
    changes, stats = diff(old, new, declared)
    roles = Roles(new)
    rfacts, web, _ = role_facts(new, roles)
    cands, login = candidates(old, new, changes, roles, rfacts, web)
    mfa_consts = {}
    for d in new.of_type("Constants$Constant"):
        if AUTH_MODULES.search(d.module) and re.search(r"enable", d.qn, re.I):
            mfa_consts[d.qn] = {"old": (old.constant(d.qn) or {}).get("default"), "new": new.constant(d.qn)["default"]}
    rep = {"old": os.path.abspath(old.path), "new": os.path.abspath(new.path),  # absolute: gen_journeys may run elsewhere (E5b 24)
           "after_startup": {"old": old.after_startup().get("AfterStartupMicroflow"),
                             "new": new.after_startup().get("AfterStartupMicroflow")},
           "stats": stats, "changes": changes, "candidates": cands, "roles": rfacts, "login": login,
           "auth": {"modules": sorted(n for n in new.modules if AUTH_MODULES.search(n)),
                    "enable_constants": mfa_consts},
           "user_roles": {"admin": roles.admin, "guest": roles.guest, "all": roles.all}}
    if a.catalog_check:
        cc = catalog_check(old.path, new.path, a.catalog_check, a.mxcli)
        bson_c = {c["qn"] for c in changes if c["kind"] == "constant" and c.get("old") and c.get("new")}
        cc["agrees"] = bson_c == {c["qn"] for c in cc["constants_changed"]}
        rep["catalog_check"] = cc
    if a.out:
        with open(a.out, "w") as f:
            json.dump(rep, f, indent=1, default=str)
    md = markdown(rep)
    if a.md:
        open(a.md, "w").write(md)
    if not a.out and not a.md:
        print(md)
    else:
        hi = [c for c in changes if c["severity"] == "high"]
        print(f"{len(changes)} changes ({len(hi)} high), {len(cands)} journey candidates; "
              f"after-startup {rep['after_startup']['old']} -> {rep['after_startup']['new']}")


if __name__ == "__main__":
    main()
