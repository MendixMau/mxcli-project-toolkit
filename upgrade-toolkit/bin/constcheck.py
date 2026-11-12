#!/usr/bin/env python3
"""constcheck.py: compare the constants of two app versions, so a module update cannot silently change app behaviour.

Why: a module update replaces the module's constants with the package defaults. In run E1, MFAmodule 1.5.0 -> 5.0.0
reset MFAmodule.EnabledMFA from True (the app's value) to False. mx check, idcheck, the data diff, REST, the ERROR log
and the smoke walk all passed with MFA switched off.

Inputs (old and new, any mix):
  app.mda           model/metadata.json "Constants" (Name, Type, DefaultValue): what the runtime gets by default
  app.mpr / <dir>   Constants$Constant documents plus the project's run configurations (Settings, ConstantValues)

  constcheck.py OLD NEW [--config NAME] [--overrides env.json] [--allow allow.txt] [--md out.md] [--json out.json]
                [--restore-to restore.mdl] [--module-versions versions.json]

Effective value per constant = the configuration value when the app has one (MPR input, --config, default: the
active or only configuration), else the default. --overrides is a JSON object {"Module.Constant": "value"} of values
the target environment sets (cloud portal, runapp CONST_OVERRIDES); a changed default that the environment overrides
is INFO, because the environment wins.

Verdicts per constant:
  CHANGED   effective value differs (booleans compared case-insensitively)            FAIL unless allow-listed
  REMOVED   constant gone in NEW                                                       INFO (callers fail mx check)
  ADDED     new constant (new module version), value printed:
              behaviour switch (Boolean type, a true/false default, or a name such as Show*, Hide*, Enable*,
              Disable*, Allow*, Use*, Is*, Skip*, Force*, *Enabled)                    REVIEW unless allow-listed or
                                                                                       set by --overrides
              anything else                                                            INFO
            Why REVIEW: in runs E4 and E5b TaskQueueHelpers 3.1.0 added ShowSystemQueuesInCharts (default False); the
            dashboard charts went empty while every rung passed and this line said INFO. A new switch changes what
            the app does with its default value; somebody has to decide that default is right for this app.
  CHANGED version label (FM-8): a String constant whose name ends in Version, old and new both look like a version
            (1.5.0, 2.0.1.3) and the new one is higher: a publisher label that moves with the module (OIDC 5.0.0
            in an app with no OIDC rows)                                             INFO, with the reason. With
            --module-versions F (JSON {"Module": "5.0.0"}) the new value must also equal that module's installed
            version, else it stays a FAIL.
Secret-looking names (password, secret, key, token) never print a value, only "set (n chars)" or "empty".
allow.txt: one fnmatch pattern per line on the constant name, then " # reason".
The effective value printed for ADDED and CHANGED rows is the --overrides value when the environment sets one.
--restore-to FILE writes an MDL script that sets every open CHANGED constant back to its OLD value, created with mode
0600 and never printed (a reset secret such as a keystore password is restored without showing it; E4-25):
"CREATE OR MODIFY CONSTANT M.N TYPE t DEFAULT v;" for a default, "ALTER SETTINGS CONSTANT ... IN CONFIGURATION" for a
configuration value. Run it with mxcli exec, then delete it.
Exit: 0 = no open CHANGED or REVIEW, 1 = open CHANGED or REVIEW, 2 = input error.
"""
import argparse, fnmatch, glob, json, os, re, sqlite3, sys, uuid, zipfile

SECRET = re.compile(r"(?i)pass|secret|key|token|pwd|credential")
SWITCH = re.compile(r"^(Show|Hide|Enable|Disable|Allow|Deny|Use|Is|Has|Skip|Force|Auto|Include|Exclude|Display|Block)"
                    r"(?=[A-Z_0-9])|Enabled$|Disabled$|Active$")


def is_switch(name, c):
    short = name.split(".")[-1]
    return ((c.get("type") or "").lower().startswith("bool") or str(c.get("default")).lower() in ("true", "false")
            or bool(SWITCH.search(short)))


VERSION_LABEL = re.compile(r"^\d+(\.\d+){1,3}$")


def version_label(name, ov, nv, module_versions):
    """FM-8: why a changed '*Version' constant is only a publisher label that moved with the module, or ''."""
    mod, _, short = name.rpartition(".")
    if not short.endswith("Version") or not VERSION_LABEL.match(str(ov).strip()) or not VERSION_LABEL.match(str(nv).strip()):
        return ""
    key = lambda v: [int(x) for x in str(v).strip().split(".")]
    if key(nv) <= key(ov):
        return ""
    if module_versions is not None:
        have = module_versions.get(mod)
        if have is None or str(have).strip() != str(nv).strip():
            return ""
        return f"version label: {short} {nv} is the installed {mod} version"
    return f"version label: {short} went up to {nv} with the module update"


def mpr_units(path):
    try:
        import bson
    except ImportError:
        sys.exit("constcheck: needs the 'bson' module (pip install pymongo)")
    proj = os.path.dirname(os.path.abspath(path))
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    cols = {r[1] for r in con.execute("pragma table_info(Unit)")}
    blob_col = "Contents" if "Contents" in cols else "NULL"
    v2 = {os.path.basename(f)[:-7].lower(): f
          for f in glob.glob(os.path.join(proj, "mprcontents", "**", "*.mxunit"), recursive=True)}
    units = {}
    for uid, cid, blob in con.execute(f"select UnitID, ContainerID, {blob_col} from Unit"):
        if blob is None and v2:
            f = v2.get(str(uuid.UUID(bytes_le=bytes(uid))).lower())
            blob = open(f, "rb").read() if f else None
        if not blob:
            continue
        try:
            units[bytes(uid)] = (bytes(cid) if cid else None, bson.decode(blob))
        except Exception:
            continue
    return units


def module_of(units, cid):
    for _ in range(50):
        if cid not in units:
            return None
        parent, d = units[cid]
        if d.get("$Type") == "Projects$ModuleImpl" or d.get("$Type") == "Projects$Module":
            return d.get("Name")
        cid = parent
    return None


def read_mpr(path, config):
    units = mpr_units(path)
    consts, cfgs = {}, {}
    for uid, (cid, d) in units.items():
        t = d.get("$Type")
        if t == "Constants$Constant":
            mod = module_of(units, cid) or "?"
            consts[f"{mod}.{d.get('Name')}"] = {"type": (d.get("Type") or {}).get("$Type", "").split("$")[-1].replace("Type", ""),
                                               "default": d.get("DefaultValue")}
        elif t == "Settings$ProjectSettings":
            for part in d.get("Settings") or []:
                if not isinstance(part, dict) or "Configuration" not in part.get("$Type", ""):
                    continue
                for c in part.get("Configurations") or []:
                    if not isinstance(c, dict):
                        continue
                    vals = {}
                    for cv in c.get("ConstantValues") or []:
                        if not isinstance(cv, dict):
                            continue
                        v = cv.get("Value")
                        sv = cv.get("SharedOrPrivateValue")
                        if isinstance(sv, dict):
                            v = sv.get("Value", v)
                        vals[cv.get("Constant")] = v
                    cfgs[c.get("Name")] = vals
    chosen = None
    if config:
        if config not in cfgs:
            sys.exit(f"constcheck: {path}: no configuration {config!r} (have {sorted(cfgs)})")
        chosen = config
    elif len(cfgs) == 1:
        chosen = next(iter(cfgs))
    elif "Default" in cfgs:
        chosen = "Default"
    over = cfgs.get(chosen, {}) if chosen else {}
    for name, c in consts.items():
        c["config"] = over.get(name)
    return consts, chosen


def read_mda(path):
    with zipfile.ZipFile(path) as z:
        meta = json.loads(z.read("model/metadata.json"))
    return {c["Name"]: {"type": c.get("Type"), "default": c.get("DefaultValue"), "config": None}
            for c in meta.get("Constants", [])}, None


def load(path, config):
    p = path
    if os.path.isdir(p):
        mprs = glob.glob(os.path.join(p, "*.mpr"))
        if len(mprs) != 1:
            sys.exit(f"constcheck: {p}: expected one .mpr, found {len(mprs)}")
        p = mprs[0]
    if p.endswith(".mda"):
        return read_mda(p)
    if p.endswith(".mpr"):
        return read_mpr(p, config)
    sys.exit(f"constcheck: unknown input {path}")


def norm(v, typ):
    if v is None:
        return None
    s = str(v)
    return s.lower() if (typ or "").lower().startswith("bool") else s


def show(name, v):
    if v is None:
        return "(none)"
    if SECRET.search(name.split(".")[-1]):
        return f"set ({len(str(v))} chars)" if str(v) else "empty"
    return repr(str(v))[:80]


def mdl_value(v, typ):
    t = (typ or "String").lower()
    if t.startswith("bool"):
        return str(v).lower()
    if t in ("integer", "long", "decimal") and re.match(r"^-?\d+(\.\d+)?$", str(v)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def write_restore(path, restore, cfg):
    """MDL for the open CHANGED constants, written 0600; returns the report line (no values)."""
    out = ["-- constcheck --restore-to: OLD values of reset constants. Contains secrets: run with mxcli exec, then delete."]
    for name, typ, o, ov in restore:
        if o["config"] is not None and cfg:
            out.append(f"ALTER SETTINGS CONSTANT '{name}' VALUE {mdl_value(ov, 'String')} IN CONFIGURATION '{cfg}';")
        else:
            out.append(f"CREATE OR MODIFY CONSTANT {name} TYPE {typ or 'String'} DEFAULT {mdl_value(ov, typ)};")
    old = os.umask(0o077)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.chmod(path, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(out) + "\n")
    finally:
        os.umask(old)
    return (f"restore: {len(restore)} statement(s) for {', '.join(n for n, *_ in restore) or 'nothing'} written to {path} "
            f"(mode 0600, values not shown): mxcli exec it, then delete it")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old"); ap.add_argument("new")
    ap.add_argument("--config", help="run configuration name to read from MPR inputs")
    ap.add_argument("--overrides", help="JSON {name: value} the target environment sets")
    ap.add_argument("--module-versions", help="JSON {Module: installed version}: a changed *Version label must equal it (FM-8)")
    ap.add_argument("--allow"); ap.add_argument("--md"); ap.add_argument("--json")
    ap.add_argument("--restore-to", help="write MDL that restores the OLD value of every open CHANGED constant (mode 0600)")
    a = ap.parse_args()
    restore = []
    (old, ocfg), (new, ncfg) = load(a.old, a.config), load(a.new, a.config)
    if not old and not new:
        print("constcheck: INVALID, no constants on either side", file=sys.stderr); sys.exit(2)
    env = json.load(open(a.overrides)) if a.overrides else {}
    modver = json.load(open(a.module_versions)) if a.module_versions else None
    allow = []
    if a.allow:
        for line in open(a.allow):
            if line.strip() and not line.lstrip().startswith("#"):
                pat, _, why = line.partition("#"); allow.append((pat.strip(), why.strip() or "allowed"))
    rows = []
    for name in sorted(set(old) | set(new)):
        o, n = old.get(name), new.get(name)
        if o and not n:
            rows.append(("INFO", "REMOVED", name, f"was {show(name, o['config'] if o['config'] is not None else o['default'])}"))
            continue
        if n and not o:
            nv = n["config"] if n["config"] is not None else n["default"]
            detail = f"default {show(name, n['default'])}"
            if n["config"] is not None:
                detail += f", configuration {show(name, n['config'])}"
            if name in env:
                rows.append(("INFO", "ADDED", name, detail + f"; the environment sets {show(name, env[name])}"))
                continue
            if not is_switch(name, n):
                rows.append(("INFO", "ADDED", name, detail))
                continue
            detail += f"; behaviour switch, the app runs with {show(name, nv)}"
            for pat, why in allow:
                if fnmatch.fnmatch(name, pat):
                    rows.append(("PASS*", "ADDED", name, detail + f" (accepted: {why})")); break
            else:
                rows.append(("REVIEW", "ADDED", name, detail + "; decide the value (allow.txt or --overrides)"))
            continue
        ov = o["config"] if o["config"] is not None else o["default"]
        nv = n["config"] if n["config"] is not None else n["default"]
        typ = n.get("type") or o.get("type")
        if norm(ov, typ) == norm(nv, typ):
            rows.append(("PASS", "SAME", name, ""))
            continue
        detail = f"{show(name, ov)} -> {show(name, nv)}"
        if o["default"] != n["default"] and o["config"] is None and n["config"] is None:
            detail += " (package default changed)"
        if name in env:
            rows.append(("INFO", "CHANGED", name, detail + f"; the environment overrides it ({show(name, env[name])})"))
            continue
        for pat, why in allow:
            if fnmatch.fnmatch(name, pat):
                rows.append(("PASS*", "CHANGED", name, detail + f" (accepted: {why})")); break
        else:
            vl = version_label(name, ov, nv, modver)
            if vl:
                rows.append(("INFO", "CHANGED", name, detail + f"; {vl}"))
                continue
            rows.append(("FAIL", "CHANGED", name, detail))
            restore.append((name, typ, o, ov))
    order = {"FAIL": 0, "REVIEW": 1, "PASS*": 2, "INFO": 3, "PASS": 4}
    rows.sort(key=lambda r: (order[r[0]], r[2]))
    counts = {k: sum(1 for r in rows if r[0] == k) for k in order}
    lines = [f"# constcheck {a.old} -> {a.new}", "",
             f"constants old {len(old)}, new {len(new)}; configuration old {ocfg or '-'}, new {ncfg or '-'}; "
             f"environment overrides {len(env)}", " | ".join(f"{k} {v}" for k, v in counts.items()), ""]
    lines += [f"{v:6} {kind:8} {name}  {d}" for v, kind, name, d in rows if v != "PASS"]
    if a.restore_to:
        lines += ["", write_restore(a.restore_to, restore, ncfg)]
    out = "\n".join(lines)
    print(out)
    if a.md:
        open(a.md, "w").write(out + "\n")
    if a.json:
        json.dump([dict(zip(("verdict", "kind", "name", "detail"), r)) for r in rows], open(a.json, "w"), indent=1)
    sys.exit(1 if counts["FAIL"] or counts["REVIEW"] else 0)


if __name__ == "__main__":
    main()
