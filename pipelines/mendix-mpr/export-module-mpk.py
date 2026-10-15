#!/usr/bin/env python3
"""export-module-mpk.py — headless "export module to .mpk" for an MPR v1 (single SQLite) app.

usage: export-module-mpk.py <source.mpr> <Module> <out.mpk> [--no-widgets] [--scrub-constant-defaults] [--json]

WHAT IT DOES
  Writes a Mendix *module package* in the shape Studio Pro / Marketplace module packages have
  (studied on Marketplace "Encryption" 9.0.3, built with 9.18.0): a zip holding `package.xml`
  (<modelerProject><module name=…/><projectFile path="project.mpr"/><files>…</files>) and a
  `project.mpr` that is a new SQLite database with
    - the source's own CREATE TABLE statements, verbatim (same schema, no translation),
    - the source's `_MetaData` row, verbatim (ProductVersion stays the source's version),
    - the `Projects$Project` root unit, the `Projects$ProjectConversion` unit and the four
      project documents (mx module-import refuses a package without them) — SystemTexts
      verbatim; ProjectSecurity, ProjectSettings and Navigation *scrubbed*: demo users and their
      passwords, user roles, admin password, guest role, configuration constant values / custom
      settings / database credentials, certificates, the after-startup / before-shutdown /
      health-check microflow names and the navigation profiles are emptied, and those units'
      ContentsHash recomputed (sha256 of Contents, base64 — verified on all 4783 units of the field-service template),
    - the module unit (`ContainmentName='Modules'`, BSON Name == <Module>) and every unit below
      it by ContainerID, every column copied byte for byte (UnitID, ContentsHash, Contents …).
      That includes the module's own constants (`Constants$Constant`) WITH their DefaultValue: a
      key or password kept as a constant default travels in the package. `--scrub-constant-defaults`
      empties every DefaultValue, recomputes the ContentsHash and prints the count — UNVERIFIED in
      Studio Pro: no package built with it has yet been installed and checked (`mx check`). An
      emptied non-String default (Integer, Boolean …) needs a value set in the target,
  plus the module's files, matched on the lower-cased module name the way Mendix lays them out:
  `javasource/<m>/` (minus `proxies/`, which the build regenerates), `javascriptsource/<m>/`,
  `themesource/<m>/`, `resources/<m>/`, every `userlib/<jar>` that has a
  `<jar>.<Module>.RequiredLib` marker (with the marker — the same rule as `mx
  create-module-package --filter-required-libs`), and (unless --no-widgets) every
  `widgets/*.mpk` whose widget id is referenced by a unit of the module.

WHY THE SCRUB
  Reference module packages carry *blank* project documents. The monolith's own carry demo-user
  passwords, constant values and database settings, which must not travel inside a module
  package. A first version omitted the four documents; `mx module-import` (10.24) then failed
  with "Sequence contains no elements" (exit 117) on every package, and succeeded with all four
  present (each one alone, or any three, still failed). The scrub keeps the documents and
  empties the secrets. It refuses to rewrite a document whose BSON does not round-trip
  byte-identically.

WHAT IT CANNOT KNOW
  - Whether the target has the modules this module references (the cut's crossing edges). It
    counts them and prints them; the target's `mx check` is what proves them.
  - Whether the target's Mendix version accepts the package. It does not convert BSON: the
    package is exactly as old as the source. (Field result, 2026-10-12: `mx module-import`
    11.13 refuses packages older than 10.21; 9.24's mx has no module-import at all.)
  - Managed (Gradle) Java dependencies, jars without a RequiredLib marker, and JavaScript
    action npm dependencies outside `javascriptsource/<m>/`.

WHEN TO USE SOMETHING ELSE
  On Mendix 10.x/11.x `mx create-module-package <mpr> <Module>` is Mendix's own headless
  export (MxBuild toolset). Prefer it. This script exists for MPR v1 sources whose mx has no such
  verb (Mendix 9.x). It refuses — rather than guessing — an MPR v2 source (mprcontents/), a
  schema that is not the reference schema, a module name that is missing or ambiguous.

Python stdlib only. Read-only on the source (opened with mode=ro).
Field run 2026-10-12: a public field-service template app (Mendix 9.24.2, MPR v1, 64 MB); three
modules exported and installed into Mendix 10.24 and 11.13 (results in this pipeline's README.md).
"""
import base64
import hashlib
import json
import os
import re
import sqlite3
import struct
import sys
import zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

REF_UNIT_COLS = ["UnitID", "ContainerID", "ContainmentName", "TreeConflict",
                 "ContentsHash", "ContentsConflicts", "Contents"]
REF_META_COLS = {"_ProductVersion", "_BuildVersion", "_SchemaHash", "_DisableAutoMprV2Upgrade"}
SHELL_TYPES = {"Projects$Project", "Projects$ProjectConversion"}
# mx module-import refuses a package without all four ("Sequence contains no elements", exit 117,
# Mendix 10.24 — field run 2026-10-12). SystemTexts is copied verbatim; the three that carry
# secrets or monolith-wide references are scrubbed (see scrub_*).
PROJECT_DOC_TYPES = {"Security$ProjectSecurity", "Settings$ProjectSettings",
                     "Navigation$NavigationDocument", "Texts$SystemTextCollection"}


class Refuse(Exception):
    pass


class SamePath(Refuse):
    """Source and output are the same file: a usage error (exit 2), never a write."""


# --- minimal BSON reading: top-level fields only, enough for $Type / Name / WidgetId ---------
def _bson_top(b):
    """Return the top-level string fields of a BSON document (others skipped)."""
    out = {}
    size = struct.unpack_from("<i", b, 0)[0]
    i, end = 4, size - 1
    while i < end:
        t = b[i]; i += 1
        j = b.index(b"\x00", i); key = b[i:j].decode("utf-8", "replace"); i = j + 1
        if t == 2:
            n = struct.unpack_from("<i", b, i)[0]
            out[key] = b[i + 4:i + 3 + n].decode("utf-8", "replace"); i += 4 + n
        elif t in (3, 4):
            i += struct.unpack_from("<i", b, i)[0]
        elif t == 5:
            i += 5 + struct.unpack_from("<i", b, i)[0]
        elif t in (1, 9, 17, 18):
            i += 8
        elif t == 16:
            i += 4
        elif t == 8:
            i += 1
        elif t in (6, 10, 127, 255):
            pass
        else:
            raise Refuse(f"unexpected BSON element type {t} in a unit header — not the reference format")
    return out


def _bson_strings(b, key):
    """Every string value stored under `key` anywhere in the document (raw scan, no full parse)."""
    found, needle, i = set(), b"\x02" + key.encode() + b"\x00", 0
    while True:
        i = b.find(needle, i)
        if i < 0:
            return found
        i += len(needle)
        n = struct.unpack_from("<i", b, i)[0]
        if 0 < n < 4096:
            found.add(b[i + 4:i + 3 + n].decode("utf-8", "replace"))
        i += 4


# --- type-preserving BSON (list of (type, key, value)), used only to scrub project docs and constants ---
def bson_load(b, i=0):
    size = struct.unpack_from("<i", b, i)[0]
    end, i, items = i + size - 1, i + 4, []
    while i < end:
        t = b[i]; i += 1
        j = b.index(b"\x00", i); key = b[i:j]; i = j + 1
        if t == 2:
            n = struct.unpack_from("<i", b, i)[0]; v = b[i + 4:i + 4 + n]; i += 4 + n
        elif t in (3, 4):
            n = struct.unpack_from("<i", b, i)[0]; v = bson_load(b, i); i += n
        elif t == 5:
            n = struct.unpack_from("<i", b, i)[0]; v = b[i:i + 5 + n]; i += 5 + n
        elif t in (1, 9, 17, 18):
            v = b[i:i + 8]; i += 8
        elif t == 16:
            v = b[i:i + 4]; i += 4
        elif t == 8:
            v = b[i:i + 1]; i += 1
        elif t in (6, 10, 127, 255):
            v = b""
        else:
            raise Refuse(f"unexpected BSON element type {t} in a project document")
        items.append((t, key, v))
    return items


def bson_dump(items):
    body = b""
    for t, key, v in items:
        if t == 2:
            body += bytes([t]) + key + b"\x00" + struct.pack("<i", len(v)) + v
        elif t in (3, 4):
            body += bytes([t]) + key + b"\x00" + bson_dump(v)
        else:
            body += bytes([t]) + key + b"\x00" + v
    return struct.pack("<i", len(body) + 5) + body + b"\x00"


def _str(v):
    s = v.encode() + b"\x00"
    return s


def _set(items, key, t, v):
    kb = key.encode()
    return [(t, k, v) if k == kb else (tt, k, vv) for tt, k, vv in items]


def _empty_list(items, key):
    """Keep a Mendix list's leading storage marker (element "0", an int32), drop its elements."""
    kb = key.encode()
    return [(t, k, [x for x in v if x[1] == b"0"]) if (k == kb and t == 4) else (t, k, v)
            for t, k, v in items]


def _get(items, key, default=None):
    kb = key.encode()
    for t, k, v in items:
        if k == kb:
            return v
    return default


def scrub_security(items):
    for key in ("DemoUsers", "UserRoles"):
        items = _empty_list(items, key)
    for key in ("AdminPassword", "AdminUserRole", "GuestUserRole"):
        if _get(items, key) is not None:
            items = _set(items, key, 2, _str(""))
    for key in ("EnableDemoUsers", "EnableGuestAccess"):
        if _get(items, key) is not None:
            items = _set(items, key, 8, b"\x00")
    if _get(items, "SecurityLevel") is not None:
        items = _set(items, "SecurityLevel", 2, _str("CheckNothing"))
    return items


def scrub_constant(items):
    """Empty a module constant's DefaultValue (top-level string): API keys and passwords live there."""
    if _get(items, "DefaultValue") is not None:
        items = _set(items, "DefaultValue", 2, _str(""))
    return items


def scrub_settings(items):
    def walk(node):
        out = []
        for t, k, v in node:
            if t in (3, 4):
                v = walk(v)
                if t == 3:
                    typ = _get(v, "$Type", b"").rstrip(b"\x00")
                    if typ == b"Settings$ServerConfiguration":
                        for key in ("ConstantValues", "CustomSettings"):
                            v = _empty_list(v, key)
                        for key in ("DatabasePassword", "DatabaseUserName", "DatabaseUrl"):
                            if _get(v, key) is not None:
                                v = _set(v, key, 2, _str(""))
                    elif typ == b"Settings$CertificateSettings":
                        v = _empty_list(v, "Certificates")
                    elif typ == b"Settings$ModelSettings":
                        for key in ("AfterStartupMicroflow", "BeforeShutdownMicroflow", "HealthCheckMicroflow"):
                            if _get(v, key) is not None:
                                v = _set(v, key, 2, _str(""))
            out.append((t, k, v))
        return out
    return walk(items)


def scrub_navigation(items):
    """Drop the monolith's navigation profiles: their menus, home pages and offline configs name
    pages, entities and user roles of every other module, and no installer reads them."""
    return _empty_list(items, "Profiles")


def scrubbed_row(row, scrub_constant_defaults=False):
    """Return the Unit row with a scrubbed Contents and a recomputed ContentsHash."""
    uid, cid, cname, tconf, _h, cconf, contents = row
    top = _bson_top(contents)
    typ = top.get("$Type")
    scrubbers = {"Security$ProjectSecurity": scrub_security,
                 "Settings$ProjectSettings": scrub_settings,
                 "Navigation$NavigationDocument": scrub_navigation}
    if scrub_constant_defaults:
        scrubbers["Constants$Constant"] = scrub_constant
    if typ not in scrubbers:
        return row, False
    if typ == "Constants$Constant" and not top.get("DefaultValue"):
        return row, False                      # already empty: copy byte for byte
    if bson_dump(bson_load(contents)) != contents:
        raise Refuse(f"{typ}: BSON round trip is not byte-identical — will not rewrite it")
    items = bson_load(contents)
    items = scrubbers[typ](items)
    new = bson_dump(items)
    h = base64.b64encode(hashlib.sha256(new).digest()).decode()
    return (uid, cid, cname, tconf, h, cconf, new), True


# --- source checks ------------------------------------------------------------------------
def open_source(path):
    if not os.path.isfile(path):
        raise Refuse(f"source not found: {path}")
    if os.path.isdir(os.path.join(os.path.dirname(os.path.abspath(path)), "mprcontents")):
        raise Refuse("source is MPR v2 (mprcontents/ beside the .mpr): unit contents live in files, "
                     "not in the Unit table. On Mendix 10+/11 use `mx create-module-package` instead.")
    db = sqlite3.connect(f"file:{os.path.abspath(path)}?mode=ro", uri=True)
    tables = {r[0]: r[1] for r in db.execute("select name, sql from sqlite_master where type='table'")}
    if set(tables) != {"_MetaData", "Unit"}:
        raise Refuse(f"tables are {sorted(tables)}, reference is ['Unit', '_MetaData']")
    ucols = [r[1] for r in db.execute("pragma table_info('Unit')")]
    if ucols != REF_UNIT_COLS:
        raise Refuse(f"Unit columns {ucols} differ from reference {REF_UNIT_COLS}")
    mcols = {r[1] for r in db.execute("pragma table_info('_MetaData')")}
    if not mcols <= REF_META_COLS or "_ProductVersion" not in mcols:
        raise Refuse(f"_MetaData columns {sorted(mcols)} are not a subset of {sorted(REF_META_COLS)}")
    if db.execute("select count(*) from _MetaData").fetchone()[0] != 1:
        raise Refuse("_MetaData must hold exactly one row")
    if db.execute("select count(*) from Unit where Contents is null").fetchone()[0]:
        raise Refuse("Unit rows without Contents — MPR v2 or a damaged file")
    return db, tables


def collect(db, module):
    rows = db.execute("select UnitID, ContainerID, ContainmentName, Contents from Unit").fetchall()
    children, by_id, shell, modules = {}, {}, [], []
    for uid, cid, cname, contents in rows:
        by_id[uid] = (cid, cname, contents)
        if cid is not None and cid != uid:
            children.setdefault(cid, []).append(uid)
        top = _bson_top(contents)
        if top.get("$Type") in SHELL_TYPES or (cname == "ProjectDocuments"
                                               and top.get("$Type") in PROJECT_DOC_TYPES):
            shell.append(uid)
        if cname == "Modules":
            modules.append((top.get("Name"), uid, top))
    match = [m for m in modules if m[0] == module]
    if not match:
        raise Refuse(f"module {module!r} not found; modules: {', '.join(sorted(str(m[0]) for m in modules))}")
    if len(match) > 1:
        raise Refuse(f"module name {module!r} is ambiguous ({len(match)} units)")
    if len([u for u in shell if _bson_top(by_id[u][2]).get("$Type") == "Projects$Project"]) != 1:
        raise Refuse("expected exactly one Projects$Project root unit")
    _, mod_uid, mod_top = match[0]
    subtree, stack = [], [mod_uid]
    while stack:
        u = stack.pop()
        subtree.append(u)
        stack.extend(children.get(u, []))
    return shell, subtree, mod_top, {m[0] for m in modules}, by_id


def crossing_refs(by_id, subtree, module, all_modules):
    """Qualified names Module.X in the subtree's string fields pointing at another module.

    The match must start at a name boundary: a plain substring test counted `NativeNote.X` as a
    reference to module `Note` (field-service template run 2026-10-12, increment 3: "Note x54", 0 real). In BSON
    the byte before a string's first character is the high byte of its int32 length (0x00), and
    inside an XPath or expression it is `[`, `/`, `(`, a space or a quote — never [A-Za-z0-9_]."""
    refs = {}
    others = sorted((m for m in all_modules if m and m != module), key=len, reverse=True)
    for u in subtree:
        c = by_id[u][2]
        for m in others:
            if re.search(rb"(?<![A-Za-z0-9_])" + re.escape(m.encode()) + rb"\.", c):
                refs[m] = refs.get(m, 0) + 1
    return refs


# --- files --------------------------------------------------------------------------------
def module_files(app_dir, module):
    low, picked = module.lower(), []
    for top in ("javasource", "javascriptsource", "themesource", "resources"):
        base = os.path.join(app_dir, top)
        if not os.path.isdir(base):
            continue
        for entry in os.listdir(base):
            if entry.lower() != low:
                continue
            for root, dirs, files in os.walk(os.path.join(base, entry)):
                rel_root = os.path.relpath(root, app_dir).replace(os.sep, "/")
                if top == "javasource" and rel_root.split("/")[2:3] == ["proxies"]:
                    dirs[:] = []
                    continue
                dirs.sort()
                for f in sorted(files):
                    picked.append(f"{rel_root}/{f}")
    ul = os.path.join(app_dir, "userlib")
    if os.path.isdir(ul):
        names = set(os.listdir(ul))
        suffix = f".{module}.RequiredLib"
        for n in sorted(names):
            if n.endswith(suffix):
                jar = n[: -len(suffix)]
                if jar in names:
                    picked.append(f"userlib/{jar}")
                picked.append(f"userlib/{n}")
    return picked


def widget_index(app_dir):
    """widget id -> widgets/<file>.mpk, read from each widget package's own XML."""
    idx, wdir = {}, os.path.join(app_dir, "widgets")
    if not os.path.isdir(wdir):
        return idx
    for f in sorted(os.listdir(wdir)):
        if not f.endswith(".mpk"):
            continue
        try:
            with zipfile.ZipFile(os.path.join(wdir, f)) as z:
                for n in z.namelist():
                    if n.endswith(".xml") and n != "package.xml":
                        try:
                            root = ET.fromstring(z.read(n))
                        except ET.ParseError:
                            continue
                        if root.tag.endswith("widget") and root.get("id"):
                            idx.setdefault(root.get("id"), f"widgets/{f}")
        except zipfile.BadZipFile:
            continue
    return idx


def package_xml(module, files):
    lines = ['<?xml version="1.0" encoding="utf-8"?>',
             '<package xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
             'xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="http://www.mendix.com/package/1.0/">',
             '  <modelerProject xmlns="http://www.mendix.com/modelerProject/1.0/">',
             f'    <module name={quoteattr(module)} />',
             '    <projectFile path="project.mpr" />',
             '    <files>']
    lines += [f'      <file path={quoteattr(f)} />' for f in files]
    lines += ['    </files>', '  </modelerProject>', '</package>']
    return "\n".join(lines) + "\n"


# --- main ---------------------------------------------------------------------------------
def export(src, module, out, with_widgets=True, scrub_constant_defaults=False):
    # refuse before anything is removed or written: `out` == `src` would delete the source app
    if os.path.exists(out) and os.path.realpath(out) == os.path.realpath(src):
        raise SamePath(f"output {out} is the source .mpr itself — refusing before any write")
    tmp_mpr = out + ".project.mpr.tmp"
    if os.path.realpath(tmp_mpr) == os.path.realpath(src):
        raise SamePath(f"temporary file {tmp_mpr} would be the source .mpr — refusing")
    try:
        return _export(src, module, out, with_widgets, tmp_mpr, scrub_constant_defaults)
    finally:
        if os.path.exists(tmp_mpr):
            os.remove(tmp_mpr)


def _export(src, module, out, with_widgets, tmp_mpr, scrub_constant_defaults=False):
    db, tables = open_source(src)
    shell, subtree, mod_top, all_modules, by_id = collect(db, module)
    app_dir = os.path.dirname(os.path.abspath(src))
    if os.path.exists(tmp_mpr):
        os.remove(tmp_mpr)
    dst = sqlite3.connect(tmp_mpr)
    for name in ("_MetaData", "Unit"):
        dst.execute(tables[name])
    meta_cols = [r[1] for r in db.execute("pragma table_info('_MetaData')")]
    meta = db.execute(f"select {', '.join(meta_cols)} from _MetaData").fetchone()
    dst.execute(f"insert into _MetaData ({', '.join(meta_cols)}) values ({', '.join('?' * len(meta_cols))})", meta)
    keep = shell + subtree
    q = f"select {', '.join(REF_UNIT_COLS)} from Unit where UnitID = ?"
    scrubbed, constants_emptied = [], []
    for uid in keep:
        row, changed = scrubbed_row(db.execute(q, (uid,)).fetchone(), scrub_constant_defaults)
        if changed:
            top = _bson_top(row[6])
            if top.get("$Type") == "Constants$Constant":
                constants_emptied.append(f"{module}.{top.get('Name', '?')}")
            else:
                scrubbed.append(top.get("$Type"))
        dst.execute(f"insert into Unit values ({', '.join('?' * 7)})", row)
    dst.commit(); dst.close()

    files = module_files(app_dir, module)
    widgets_used, widgets_shipped, widgets_missing = set(), [], []
    for u in subtree:
        widgets_used |= _bson_strings(by_id[u][2], "WidgetId")
    if with_widgets and widgets_used:
        idx = widget_index(app_dir)
        for w in sorted(widgets_used):
            if w in idx:
                if idx[w] not in widgets_shipped:
                    widgets_shipped.append(idx[w])
            else:
                widgets_missing.append(w)
        files += widgets_shipped

    if os.path.exists(out):
        os.remove(out)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("package.xml", package_xml(module, files))
        z.write(tmp_mpr, "project.mpr")
        for f in files:
            z.write(os.path.join(app_dir, f), f)

    types = {}
    for u in subtree:
        t = _bson_top(by_id[u][2]).get("$Type", "?")
        types[t] = types.get(t, 0) + 1
    return {
        "module": module,
        "product_version": meta[0],
        "units_module_subtree": len(subtree),
        "units_shell": len(shell),
        "project_docs_scrubbed": scrubbed,
        "constant_defaults_emptied": constants_emptied,
        "constant_defaults_scrubbed": scrub_constant_defaults,
        "unit_types": dict(sorted(types.items())),
        "from_app_store": mod_top.get("AppStoreVersion") or None,
        "files": len(files),
        "java_files": sum(1 for f in files if f.startswith("javasource/") and f.endswith(".java")),
        "js_files": sum(1 for f in files if f.startswith("javascriptsource/")),
        "widgets_referenced": sorted(widgets_used),
        "widgets_shipped": widgets_shipped,
        "widgets_unresolved": widgets_missing,
        "crossing_refs_by_module": dict(sorted(crossing_refs(by_id, subtree, module, all_modules).items())),
        "out": out,
    }


KNOWN_FLAGS = {"--no-widgets", "--scrub-constant-defaults", "--json"}


def main(argv):
    # an unknown flag is refused, never ignored: a typo such as `--scrub-constants` would otherwise
    # export with every constant default in plain text while the caller believes it scrubbed them
    unknown = [a for a in argv if a.startswith("--") and a not in KNOWN_FLAGS]
    if unknown:
        print(f"unknown option(s): {' '.join(unknown)} (known: {' '.join(sorted(KNOWN_FLAGS))})",
              file=sys.stderr)
        print(__doc__.split("\n\n")[0] + "\n" + __doc__.split("\n")[2], file=sys.stderr)
        return 2
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 3:
        print(__doc__.split("\n\n")[0] + "\n" + __doc__.split("\n")[2], file=sys.stderr)
        return 2
    try:
        r = export(args[0], args[1], args[2], with_widgets="--no-widgets" not in argv,
                   scrub_constant_defaults="--scrub-constant-defaults" in argv)
    except SamePath as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 2
    except Refuse as e:
        print(f"REFUSED: {e}", file=sys.stderr)
        return 3
    if "--json" in argv:
        print(json.dumps(r, indent=2))
        print("constant defaults " + (f"emptied: {len(r['constant_defaults_emptied'])} (--scrub-constant-defaults)"
              if r["constant_defaults_scrubbed"] else "copied unchanged"), file=sys.stderr)
    else:
        print(f"wrote {r['out']}: module {r['module']} ({r['product_version']}), "
              f"{r['units_module_subtree']} units + {r['units_shell']} shell, {r['files']} files "
              f"({r['java_files']} .java, {r['js_files']} js), widgets shipped {len(r['widgets_shipped'])}"
              f"/{len(r['widgets_referenced'])} referenced")
        if r["constant_defaults_scrubbed"]:
            print(f"  constant defaults emptied (--scrub-constant-defaults): {len(r['constant_defaults_emptied'])}"
                  + (" (" + ", ".join(r["constant_defaults_emptied"]) + ")" if r["constant_defaults_emptied"] else ""))
        else:
            print("  constant defaults copied unchanged (module constants travel in the package; "
                  "--scrub-constant-defaults empties them)")
        if r["widgets_unresolved"]:
            print("  widget ids with no .mpk in widgets/ (core or platform widgets): "
                  + ", ".join(r["widgets_unresolved"]))
        if r["crossing_refs_by_module"]:
            print("  units naming other modules (crossing edges the target must satisfy): "
                  + ", ".join(f"{m}×{n}" for m, n in r["crossing_refs_by_module"].items()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
