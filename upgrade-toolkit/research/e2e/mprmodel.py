#!/usr/bin/env python3
"""mprmodel.py: read a Mendix project (MPR v1 or v2) straight from its BSON, no Studio Pro, no mxbuild.

Works for 9.x, 10.x and 11.x project files because it only relies on the unit table and on the
$Type / Name / qualified-name-string conventions, which have been stable across those versions.
Same approach as idcheck.py's reader, extended to every unit type.

Library use:
    m = Model.load("<dir or .mpr>")
    m.docs["Module.Name"]  -> Doc(qn, type, module, data, hash)
    m.modules              -> {name: {"version": ..., "from_appstore": bool}}
    m.refs(qn)             -> set of qualified names referenced by that document (microflows, pages,
                              constants, java actions, entities ...), read from its BSON strings
CLI (quick look):
    mprmodel.py <dir|mpr> [--type Constants$Constant] [--doc Module.Name]
"""
import glob, hashlib, json, os, re, sqlite3, sys, uuid

try:
    import bson  # pymongo's bson
except ImportError:
    sys.exit("mprmodel: needs the 'bson' module (pip install pymongo)")

SKIP_KEYS = {"$ID", "GUID", "Location", "RelativeMiddlePoint", "Size", "OriginPointer", "DestinationPointer",
             "OriginControlVector", "DestinationControlVector", "OriginBezierVector", "DestinationBezierVector",
             "LineType", "ContentsHash", "NewSortIndex", "SortIndex", "ExportLevel", "Documentation"}

QN = re.compile(r"@?([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)")


def norm(x):
    """Version-neutral projection: drop ids, geometry and binary, keep meaning."""
    if isinstance(x, dict):
        return {k: norm(v) for k, v in sorted(x.items()) if k not in SKIP_KEYS}
    if isinstance(x, list):
        return [norm(i) for i in x if not isinstance(i, int) or isinstance(i, bool)]
    if isinstance(x, (bytes, bytearray)) or hasattr(x, "subtype"):
        return "B"
    return x


def strings(x):
    if isinstance(x, dict):
        for k, v in x.items():
            if k in ("$ID", "GUID"):
                continue
            yield from strings(v)
    elif isinstance(x, list):
        for v in x:
            yield from strings(v)
    elif isinstance(x, str):
        yield x


def text_of(t):
    """Texts$Text -> first translation (en_US preferred)."""
    if not isinstance(t, dict):
        return ""
    items = [i for i in (t.get("Items") or []) if isinstance(i, dict)]
    for i in items:
        if i.get("LanguageCode", "").startswith("en"):
            return i.get("Text", "")
    return items[0].get("Text", "") if items else ""


class Doc:
    __slots__ = ("qn", "type", "module", "data", "hash", "folder")

    def __init__(self, qn, typ, module, data, folder):
        self.qn, self.type, self.module, self.data, self.folder = qn, typ, module, data, folder
        self.hash = hashlib.sha1(json.dumps(norm(data), sort_keys=True, default=str).encode()).hexdigest()


class Model:
    def __init__(self, path):
        self.path = path
        self.units = {}      # uid -> (container uid, containment, dict)
        self.docs = {}       # qn -> Doc
        self.modules = {}    # name -> info
        self.singletons = {}  # $Type -> dict (ProjectSettings, ProjectSecurity, Navigation ...)
        self._refs = {}

    @classmethod
    def load(cls, path):
        p = path
        if os.path.isdir(p):
            mprs = glob.glob(os.path.join(p, "*.mpr"))
            if len(mprs) != 1:
                sys.exit(f"mprmodel: {p}: expected exactly one .mpr, found {len(mprs)}")
            p = mprs[0]
        m = cls(p)
        m._read(p)
        m._index()
        return m

    def _read(self, path):
        proj_dir = os.path.dirname(os.path.abspath(path))
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
        blob_col = "Contents" if "Contents" in cols else "NULL"
        rows = con.execute(f"select UnitID, ContainerID, ContainmentName, {blob_col} from Unit").fetchall()
        v2files = {}
        if os.path.isdir(os.path.join(proj_dir, "mprcontents")):
            for f in glob.glob(os.path.join(proj_dir, "mprcontents", "**", "*.mxunit"), recursive=True):
                v2files[os.path.basename(f)[:-7].lower()] = f
        for uid, cid, cname, blob in rows:
            if blob is None and v2files:
                f = (v2files.get(str(uuid.UUID(bytes_le=bytes(uid))).lower())
                     or v2files.get(str(uuid.UUID(bytes=bytes(uid))).lower()))
                if f:
                    blob = open(f, "rb").read()
            if not blob:
                continue
            try:
                self.units[bytes(uid)] = (bytes(cid) if cid else None, cname, bson.decode(blob))
            except Exception:
                continue

    def _module_of(self, uid):
        """Walk containers up to the Projects$Module(Impl); return (module name, folder path)."""
        folders = []
        cur = self.units.get(uid)
        seen = 0
        while cur and seen < 50:
            seen += 1
            cid = cur[0]
            parent = self.units.get(cid)
            if not parent:
                return None, "/".join(reversed(folders))
            t = parent[2].get("$Type", "")
            if t in ("Projects$ModuleImpl", "Projects$Module"):
                return parent[2].get("Name"), "/".join(reversed(folders))
            if t == "Projects$Folder":
                folders.append(parent[2].get("Name", ""))
            cur = parent
        return None, ""

    def _index(self):
        for uid, (cid, cname, d) in self.units.items():
            t = d.get("$Type", "")
            if t in ("Projects$ModuleImpl", "Projects$Module"):
                self.modules[d.get("Name")] = {
                    "version": d.get("AppStoreVersion") or "",
                    "from_appstore": bool(d.get("FromAppStore")),
                    "package_id": d.get("AppStorePackageId") or 0,
                }
                continue
            if t in ("Settings$ProjectSettings", "Security$ProjectSecurity", "Navigation$NavigationDocument",
                     "Projects$Project"):
                self.singletons[t] = d
                continue
            if t == "DomainModels$DomainModel":
                mod, _ = self._module_of(uid)
                self.docs[f"{mod}.$DomainModel"] = Doc(f"{mod}.$DomainModel", t, mod, d, "")
                continue
            if t == "Security$ModuleSecurity":
                mod, _ = self._module_of(uid)
                self.docs[f"{mod}.$ModuleSecurity"] = Doc(f"{mod}.$ModuleSecurity", t, mod, d, "")
                continue
            name = d.get("Name")
            if not name or t in ("Projects$Folder", "Projects$ModuleSettings"):
                continue
            mod, folder = self._module_of(uid)
            if not mod:
                continue
            qn = f"{mod}.{name}"
            self.docs[qn] = Doc(qn, t, mod, d, folder)

    # ------------------------------------------------------------ queries
    def of_type(self, *types):
        return [d for d in self.docs.values() if d.type in types]

    def refs(self, qn):
        """Qualified names (documents, constants, entities/attributes as Module.X) referenced by a document."""
        if qn in self._refs:
            return self._refs[qn]
        d = self.docs.get(qn)
        out = set()
        if d:
            for s in strings(d.data):
                for mod, name in QN.findall(s):
                    if mod in self.modules:
                        out.add(f"{mod}.{name}")
        out.discard(qn)
        self._refs[qn] = out
        return out

    def callers_index(self):
        """qn -> set of documents that reference it (reverse of refs, documents only)."""
        idx = {}
        for qn in self.docs:
            for r in self.refs(qn):
                idx.setdefault(r, set()).add(qn)
        return idx

    def after_startup(self):
        ps = self.singletons.get("Settings$ProjectSettings", {})
        for part in ps.get("Settings") or []:
            if isinstance(part, dict) and "AfterStartupMicroflow" in part:
                return {k: part.get(k, "") for k in ("AfterStartupMicroflow", "BeforeShutdownMicroflow",
                                                      "HealthCheckMicroflow")}
        return {}

    def user_roles(self):
        """name -> sorted module roles."""
        sec = self.singletons.get("Security$ProjectSecurity", {})
        out = {}
        for r in sec.get("UserRoles") or []:
            if isinstance(r, dict):
                out[r.get("Name")] = sorted(m for m in (r.get("ModuleRoles") or []) if isinstance(m, str))
        return out

    def security_summary(self):
        sec = self.singletons.get("Security$ProjectSecurity", {})
        pp = sec.get("PasswordPolicySettings") or {}
        return {"SecurityLevel": sec.get("SecurityLevel"), "CheckSecurity": sec.get("CheckSecurity"),
                "EnableGuestAccess": sec.get("EnableGuestAccess"), "GuestUserRole": sec.get("GuestUserRole"),
                "AdminUserRole": sec.get("AdminUserRole"), "StrictMode": sec.get("StrictMode"),
                "PasswordPolicy": {k: v for k, v in pp.items() if not k.startswith("$")}}

    def navigation(self):
        """Per profile: home page(s), login page, menu items [(path captions, action kind, target)]."""
        nav = self.singletons.get("Navigation$NavigationDocument", {})
        out = {}
        for pr in nav.get("Profiles") or []:
            if not isinstance(pr, dict):
                continue
            hp = pr.get("HomePage") or {}
            homes = [{"role": "*", "page": hp.get("Page") or "", "microflow": hp.get("Microflow") or ""}]
            for h in pr.get("HomeItems") or []:
                if isinstance(h, dict):
                    homes.append({"role": h.get("UserRole"), "page": h.get("Page") or "",
                                  "microflow": h.get("Microflow") or ""})
            menu = []

            def walk(items, path):
                for it in items or []:
                    if not isinstance(it, dict):
                        continue
                    cap = text_of(it.get("Caption"))
                    a = it.get("Action") or {}
                    target, kind = "", a.get("$Type", "")
                    if a.get("FormSettings"):
                        target = a["FormSettings"].get("Form") or ""
                    elif a.get("MicroflowSettings"):
                        target = a["MicroflowSettings"].get("Microflow") or ""
                    menu.append({"path": path + [cap], "kind": kind.split("$")[-1], "target": target})
                    walk(it.get("Items"), path + [cap])

            mc = pr.get("Menu") or pr.get("MenuItemCollection") or {}
            walk(mc.get("Items") if isinstance(mc, dict) else [], [])
            lp = (pr.get("LoginPageSettings") or {}).get("Form") or ""
            out[pr.get("Name") or pr.get("Kind")] = {"kind": pr.get("Kind"), "homes": homes, "login_page": lp,
                                                     "menu": menu}
        return out

    def page_roles(self, qn):
        d = self.docs.get(qn)
        if not d:
            return []
        roles = d.data.get("AllowedRoles") or d.data.get("AllowedModuleRoles") or []  # key differs per version
        return sorted(r for r in roles if isinstance(r, str))

    def constant(self, qn):
        d = self.docs.get(qn)
        if not d or d.type != "Constants$Constant":
            return None
        t = (d.data.get("Type") or {}).get("$Type", "").split("$")[-1].replace("Type", "")
        return {"default": d.data.get("DefaultValue"), "type": t,
                "exposed": bool(d.data.get("ExposedToClient"))}

    def widgets(self, qn):
        """Flat list of widgets on a page/snippet/layout: dicts with $Type, Name and the raw node."""
        d = self.docs.get(qn)
        out = []

        def walk(x):
            if isinstance(x, dict):
                t = x.get("$Type", "")
                if x.get("Name") and ("Forms$" in t or "CustomWidgets$" in t or "Pages$" in t):
                    out.append(x)
                for v in x.values():
                    walk(v)
            elif isinstance(x, list):
                for v in x:
                    walk(v)
        if d:
            walk(d.data)
        return out


def module_role_to_user_roles(model):
    idx = {}
    for ur, mrs in model.user_roles().items():
        for mr in mrs:
            idx.setdefault(mr, set()).add(ur)
    return idx


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--type")
    ap.add_argument("--doc")
    ap.add_argument("--refs", action="store_true")
    a = ap.parse_args()
    m = Model.load(a.project)
    if a.doc:
        d = m.docs[a.doc]
        print(json.dumps(norm(d.data), indent=1, default=str)[:20000])
        if a.refs:
            print("REFS", sorted(m.refs(a.doc)))
    elif a.type:
        for d in sorted(m.of_type(a.type), key=lambda d: d.qn):
            print(d.qn)
    else:
        print(json.dumps({"modules": len(m.modules), "docs": len(m.docs), "after_startup": m.after_startup(),
                          "user_roles": list(m.user_roles())}, indent=1))
