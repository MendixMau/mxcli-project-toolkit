#!/usr/bin/env python3
r"""runapp.py: start a built Mendix app (.mda) on Postgres in Docker through the M2EE admin API.

  runapp.py start <name> <mda> <runtime-version> <db> [--login-override auto|off|<file>] [--harness-file auto|off|<list>]
                                                          unpack, start runtime container, run DDL, start; exit 0 = started
  runapp.py quick <name> <mda> <runtime-version> <db> [--login-override ...] [--harness-file ...]
                                                          start, save the log, stop: the mandatory quick start of the new app
  runapp.py logs  <name>                                  save the container log to logs/runtime-<name>.log (an earlier
                                                          log of that name is kept as runtime-<name>-<n>.log) AND to
                                                          logs/runtime-<name>.<db>.log, named by the start's database
                                                          (B4N1-16: gate.sh OLD_LOG=logs/runtime-old.<baseline db>.log is
                                                          one stable file; the numbered copies moved with every save)
  runapp.py stop  <name>                                  save the log, remove the runtime container, prune run/<name>/ (BT-9: the
                                                          unpacked app and the runtime's files, 200 to 400 MB per start; the
                                                          small evidence files and data/files stay; UPG_KEEP_RUN=1 keeps all)
                                                          (FM-9: with UPG_NAME unset
                                                          and another run's container <x>-<name> present, refused: it names
                                                          which containers exist; UPG_NAME=<x>, or UPG_ALLOW_DEFAULT_PREFIX=1)

Env:
  WORKDIR          run folder (default: current folder). Holds run/<name>/ (unpacked app) and logs/. A relative <mda> is
                   read from here.
  UPG_TOOLS        folder with runtime-<version>/ (default: $WORKDIR/tools). The runtime is a SEPARATE download from
                   mxbuild (mxbuild has no launcher): https://cdn.mendix.com/runtime/mendix-<full version>.tar.gz.
                   Both layouts are found: runtime-<ver>/runtime/launcher/runtimelauncher.jar, and the tarball as it
                   unpacks, runtime-<ver>/<full version>/runtime/launcher/... (E5b-2). <runtime-version> may be the short
                   (10.24.16) or the full form (10.24.16.96987, as mxversion.py prints it) (E5b-31).
  RT_IMAGE         Java image (default: by Mendix major, 9 -> eclipse-temurin:11-jdk, 10/11 -> eclipse-temurin:21-jdk)
  XMX              runtime heap (default 1g)
  PORT_OFF         admin port 8090+PORT_OFF, app port 8080+PORT_OFF (default 0; controls use 800 -> 8890/8880)
  CONST_OVERRIDES  JSON {"Module.Constant": "value"}, or the path of a file holding it: give old and new runs the SAME
                   overrides (the environment's values). A path is what gate.sh's CONST_OVERRIDES key holds and exports to
                   PRE commands (B4T2-12: runapp read the path as JSON, "Expecting value", every PRE rung rc 1). Empty =
                   none. When the app has MendixSSOClient.PushAppDeploymentEnabled and CONST_OVERRIDES does not name it, runapp sets
                   it to false for every start (T9: the LaMa push backs off 525 s) and prints a HARNESS CONDITION. Anything else (bad JSON, a missing file, not an object) stops the start before anything runs.
  (MC-20: with work/const-overrides.json present and CONST_OVERRIDES unset, start prints a WARN naming the file and the prefix)
  UPG_NAME         container name prefix (default mig): container <prefix>-<name>, so you can tell your own apart
  UPG_DB_PREFIX    when set, refuse any database name that does not start with it (controls: fx_)
  UPG_SESSION_TIMEOUT  SessionTimeout in ms (also sets ClusterManagerActionInterval to half of it). Journeys need 30000:
                   a trial runtime allows 6 sessions, guest sessions count, and with the 10 minute default every later
                   role login is refused ("login form did not render").

Login override (T2-7, N1-4): an app whose web/login.html redirects to an external IdP (meta refresh, window.location, a form
posting to an /auth/ path) cannot be signed into by smoke walks and journeys. --login-override (or UPG_LOGIN_OVERRIDE):
  auto (default)  replace login.html only when it redirects off-app, with web/login.old, web/login-stock.html or a
                  web/*login*without*sso*.html (the app's own stock page; Academy ships login-without-sso.html, T4); a normal Mendix login page (also one with an SSO button) is never touched.
                  No stock page: login.html stays, a HARNESS CONDITION says so, and sign-in journeys are INVALID
  off             never touch login.html
  <file>          always replace login.html with that file
After ANY login override the stock login.js sends the client on to index.html; an SSO app's index.html redirects to
/openid/login (registered only on Mendix Cloud: 404 here). So when the override was used and index.html redirects
off-app, the app's own non-SSO index (web/index3.html, or web/index-without-sso*.html / index-nosso*.html) is served as
web/index.html (original kept as index.html.orig, run/<name>/harness-index-override.txt, HARNESS CONDITION line). No
such page: index.html stays and a HARNESS CONDITION says the client may land on a 404 (T4).
Same value and same result for old and new. Every replacement prints a HARNESS CONDITION line and writes
run/<name>/harness-login-override.txt (original kept as login.html.orig) for the gate and scorecard to show.

Harness files (T2R3-5, B4T2-13): an add-on that builds a Windows path at runtime (EXFN_Authentication reads
`/w/run/<name>\model\metadata.json`) fails with FileNotFoundException on Linux (also on Mendix Cloud); workers copied
the file by hand for old AND new, and forgetting it for new gave a convincing create-save FAIL that was no regression.
--harness-file (or UPG_HARNESS_FILE):
  auto (default)  create run/<name>\model\metadata.json, a copy of the unpacked app's own model/metadata.json
  off             create nothing
  <list>          comma list of app-relative paths (model\metadata.json,web\x.json): each copied from the app's own file;
                  a path the app does not have stops the start
Every start removes the previous start's files of that name first (they belong to the old .mda), prints a HARNESS FILE
line and writes run/<name>/harness-files.txt. An app that never reads such a path is not affected. Quote the line in
the scorecard when the add-on needs it (report the add-on defect to its publisher).

Postgres: one container mig-pg (port 5439, user/pass mendix) serves every app. If it exists it is used as it is (started
when stopped, NEVER recreated). If it is absent it is created with the named volume mig-pg-data and without --rm, so a
Docker Desktop restart no longer deletes every database (E1 8). Restore after a loss: recreate by running any start, then
`docker exec -i mig-pg psql -U mendix -c 'create database <db>'` and `docker exec -i mig-pg pg_restore -U mendix -d <db>
< <db>.dump` (take dumps with `docker exec mig-pg pg_dump -U mendix -Fc <db> > <db>.dump`).
"""
import base64, gzip, json, os, re, shutil, subprocess, sys, time, urllib.request, zipfile
from pathlib import Path

WORK = Path(os.environ.get("WORKDIR", ".")).resolve()
TOOLS = Path(os.environ.get("UPG_TOOLS", WORK / "tools")).resolve()
XMX = os.environ.get("XMX", "1g")
PREFIX = os.environ.get("UPG_NAME", "mig")
NET, PG, PGVOL = "mig-net", "mig-pg", "mig-pg-data"
PASS = "m2ee-local-only"


def sh(*a, check=True):
    return subprocess.run(a, capture_output=True, text=True, check=check).stdout.strip()


def image_for(rtv):
    if os.environ.get("RT_IMAGE"):
        return os.environ["RT_IMAGE"]
    return "eclipse-temurin:11-jdk" if rtv.split(".")[0] in ("7", "8", "9") else "eclipse-temurin:21-jdk"


def ensure_pg():
    names = sh("docker", "ps", "-a", "--format", "{{.Names}} {{.State}}").splitlines()
    state = dict(n.split(" ", 1) for n in names if " " in n).get(PG)
    sh("docker", "network", "create", NET, check=False)
    if state == "running":
        return
    if state:  # exists but stopped: start it, never recreate (it may hold every run's databases)
        sh("docker", "start", PG)
    else:
        sh("docker", "volume", "create", PGVOL)
        sh("docker", "run", "-d", "--name", PG, "--network", NET, "--restart", "unless-stopped",
           "-v", f"{PGVOL}:/var/lib/postgresql/data", "-e", "POSTGRES_PASSWORD=mendix", "-e", "POSTGRES_USER=mendix",
           "-p", "5439:5432", "postgres:16")
    for _ in range(60):
        if subprocess.run(["docker", "exec", PG, "pg_isready", "-U", "mendix"], capture_output=True).returncode == 0:
            break
        time.sleep(1)
    time.sleep(2)


def admin(port, action, params=None):
    req = urllib.request.Request(f"http://localhost:{port}/", data=json.dumps({"action": action, "params": params or {}}).encode(),
                                 headers={"Content-Type": "application/json",
                                          "X-M2EE-Authentication": base64.b64encode(PASS.encode()).decode()})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read())


def save_log(name):
    (WORK / "logs").mkdir(parents=True, exist_ok=True)
    p = subprocess.run(["docker", "logs", f"{PREFIX}-{name}"], capture_output=True, text=True)
    dbf = WORK / "run" / name / "runapp-db.txt"
    if dbf.is_file():  # B4N1-16: one file per start, named by its database (the container log is cumulative: the last save wins)
        (WORK / "logs" / f"runtime-{name}.{dbf.read_text().strip()}.log").write_text(p.stdout + p.stderr)
    out = WORK / "logs" / f"runtime-{name}.log"
    if out.exists():
        # keep the earlier log: a quick start, a false-build start and the final stop of one name each write it (E7-13)
        n = 1
        while (WORK / "logs" / f"runtime-{name}-{n}.log").exists():
            n += 1
        out.rename(WORK / "logs" / f"runtime-{name}-{n}.log")
        print(f"runapp: kept the earlier log as runtime-{name}-{n}.log")
    out.write_text(p.stdout + p.stderr)
    return out


def find_runtime(rtv, tools=None):
    """The folder to mount as /rt (it holds runtime/launcher/runtimelauncher.jar), or None. Accepts 10.24.16 and
    10.24.16.96987, folders runtime-<short> or runtime-<full>, flat or with the tarball's <full version>/ level."""
    tools = Path(tools or TOOLS)
    short = ".".join(rtv.split(".")[:3])
    names = [f"runtime-{rtv}", f"runtime-{short}"] + sorted(p.name for p in tools.glob(f"runtime-{short}.*"))
    for n in dict.fromkeys(names):
        d = tools / n
        if (d / "runtime" / "launcher" / "runtimelauncher.jar").exists():
            return d
        for sub in sorted(d.glob(f"{short}*")) if d.is_dir() else []:
            if (sub / "runtime" / "launcher" / "runtimelauncher.jar").exists():
                return sub
    return None


LOGIN_REDIRECT = [re.compile(p, re.I) for p in (
    r"<meta[^>]+http-equiv\s*=\s*[\"']?refresh[^>]+url\s*=",
    r"(window|document|top|self)\.location(\.href)?\s*(=|\.(replace|assign)\s*\()",
    r"<form[^>]+action\s*=\s*[\"'][^\"']*(/auth/|/oauth|/saml|/sso|/openid|/oidc)",
    r"\blocation\.(replace|assign)\s*\(")]


SAME_APP_HTML = re.compile(r"^(?!\w+:|//)[\w./~-]*\.html?(\?[^\"']*)?$", re.I)


def same_app_html_target(tail):
    """BT-3: the statement after a redirect match names only literal same-app .html pages (appUrl + "unsupported-browser.html":
    the stock browser check, not an IdP). tail = the text after the matched redirect up to the end of the statement."""
    stmt = re.split(r"[;\n>]", tail, 1)[0]
    lits = re.findall(r"[\"']([^\"']*)[\"']", stmt)
    if not lits:
        m = re.match(r"\s*([^\s\"'<>)]+)", stmt)  # <meta ... url=target>: the target is not quoted
        lits = [m.group(1)] if m else []
    return bool(lits) and all(SAME_APP_HTML.match(x) for x in lits)


def login_redirects_off_app(text):
    """True when the login page sends the browser away (IdP / SSO) instead of showing a login form. A redirect whose
    target is a literal page of the same app (unsupported-browser.html) is a browser check, not an IdP (BT-3)."""
    return any(not same_app_html_target(text[m.end():m.end() + 200]) for p in LOGIN_REDIRECT for m in p.finditer(text))


def has_login_form(text):
    """A username and a password input (the stock page's ids, or any input of type password)."""
    return bool(re.search(r"usernameInput|name\s*=\s*[\"']username", text, re.I)
                and re.search(r"passwordInput|type\s*=\s*[\"']password", text, re.I))


def apply_login_override(base, mode="auto", name="app"):
    """Replace base/web/login.html per mode. Returns a one-line HARNESS CONDITION text, or None when untouched."""
    web = Path(base) / "web"
    cur = web / "login.html"
    if mode == "off" or not cur.exists() and mode == "auto":
        return None
    text = cur.read_text(errors="replace") if cur.exists() else ""
    if mode == "auto":
        if not login_redirects_off_app(text):
            return None
        trusted = [web / "login.old", web / "login-stock.html"] + sorted(
            f for f in web.glob("*.html") if re.search(r"login.*without.*sso", f.name, re.I))  # T4: Academy login-without-sso.html
        # BT-3 (APPR): a backup of the stock page under another name (login_backup_2022-12-12_10-33.html) and the other
        # login*.html pages; accepted only when the page shows a username and a password field and does not redirect
        others = sorted((f for f in web.glob("login*.html") if f.name != "login.html" and f not in trusted),
                        key=lambda f: (not re.search(r"backup|stock|orig|default|plain|local|basic", f.name, re.I), f.name))

        def usable(c, need_form):
            if not c.exists():
                return False
            t = c.read_text(errors="replace")
            return not login_redirects_off_app(t) and (not need_form or has_login_form(t))
        src = next((c for c in trusted if usable(c, False)), None) or next((c for c in others if usable(c, True)), None)
        why = "login.html redirects off-app"
        if src is None:  # never invent a login form: an unverified page would turn a real sign-in failure into noise
            msg = (f"HARNESS CONDITION: {name}: web/login.html redirects off-app and the app ships no stock login page "
                   f"(login.old, login-stock.html, login-without-sso.html, a login*backup*.html with a form); left as it is: sign-in journeys are INVALID")
            (Path(base) / "harness-login-override.txt").write_text(msg + "\n")
            return msg
    else:
        src, why = Path(mode), "explicit --login-override"
        if not src.exists():
            sys.exit(f"runapp: --login-override file {src} not found")
    if cur.exists():
        shutil.copyfile(cur, web / "login.html.orig")
    shutil.copyfile(src, cur)
    gz = web / "login.html.gz"
    with gzip.open(gz, "wb") as g:  # the runtime serves the .gz when present
        g.write(cur.read_bytes())
    msg = (f"HARNESS CONDITION: {name}: web/login.html replaced by {src.name} ({why}); original kept as login.html.orig; "
           f"the app's own sign-in (SSO) is NOT exercised")
    (Path(base) / "harness-login-override.txt").write_text(msg + "\n")
    return msg


INDEX_ALT = (r"^index3\.html$", r"^index.*(without|no).?sso.*\.html$")


def apply_index_override(base, name="app"):
    """T4: after a login override the stock login.js continues to index.html; an SSO app's index.html redirects to
    /openid/login (Mendix Cloud only: 404 here). Serve the app's own non-SSO index instead. Only when the login override
    was applied, index.html redirects off-app and an alternate index (INDEX_ALT) does not. Returns a HARNESS CONDITION
    text or None (nothing to do)."""
    base = Path(base); web = base / "web"
    marker = base / "harness-login-override.txt"
    if not marker.is_file() or "replaced by" not in marker.read_text():
        return None
    cur = web / "index.html"
    if not cur.is_file() or not login_redirects_off_app(cur.read_text(errors="replace")):
        return None
    alts = [f for pat in INDEX_ALT for f in sorted(web.glob("index*.html")) if re.search(pat, f.name, re.I)]
    alt = next((f for f in alts if not login_redirects_off_app(f.read_text(errors="replace"))), None)
    if alt is None:
        msg = (f"HARNESS CONDITION: {name}: web/index.html redirects off-app and the app ships no non-SSO index "
               f"(index3.html, index-without-sso*.html); left as it is: after sign-in the client may land on a 404 "
               f"(/openid/login); the app's own SSO sign-in is NOT exercised")
    else:
        shutil.copyfile(cur, web / "index.html.orig")
        shutil.copyfile(alt, cur)
        gz = web / "index.html.gz"
        if gz.exists():
            gz.unlink()
        msg = (f"HARNESS CONDITION: {name}: web/index.html replaced by {alt.name} (the login override sends the client to "
               f"index.html, which redirects to the SSO IdP); original kept as index.html.orig; the app's own SSO sign-in "
               f"is NOT exercised")
    (base / "harness-index-override.txt").write_text(msg + "\n")
    return msg


SSO_PUSH = "MendixSSOClient.PushAppDeploymentEnabled"


def sso_push_override(consts, overrides, name="app"):
    """T9 (E5b-13): MendixSSOClient pushes the deployment to LaMa at start with a backoff (525 s per start). When the
    module's constant exists and the caller gave no value, return ({constant: 'false'}, HARNESS CONDITION text); else
    ({}, None). The caller's own CONST_OVERRIDES value always wins."""
    if SSO_PUSH not in consts or SSO_PUSH in overrides:
        return {}, None
    return {SSO_PUSH: "false"}, (f"HARNESS CONDITION: {name}: {SSO_PUSH}=false (MendixSSOClient is present; its push to LaMa "
                                 f"at start backs off for minutes); same for old and new; set the constant in CONST_OVERRIDES to override")


def const_overrides():
    """CONST_OVERRIDES as a dict: JSON text, or a path to a JSON file (B4T2-12), empty = {}. Exits on anything else."""
    raw = os.environ.get("CONST_OVERRIDES", "").strip()
    if not raw:
        f = WORK / "const-overrides.json"
        if f.is_file():  # MC-20: a hand start without the key got an empty Encryption key ("Key should not be empty" at first login)
            print(f"runapp: WARN {f} exists but CONST_OVERRIDES is not set: this start gets NO constant overrides "
                  f"(export CONST_OVERRIDES={f}); container prefix is {PREFIX!r}"
                  + ("" if os.environ.get("UPG_NAME") else " (UPG_NAME not set, the default; gate.conf may name another)"),
                  file=sys.stderr)
        return {}
    src = "CONST_OVERRIDES"
    if not raw.startswith("{"):
        p = Path(raw)
        if not p.is_file():
            sys.exit(f"runapp: CONST_OVERRIDES={raw!r} is neither a JSON object nor an existing file; refused (nothing started)")
        src, raw = str(p), p.read_text()
    try:
        v = json.loads(raw)
    except ValueError as e:
        sys.exit(f"runapp: CONST_OVERRIDES ({src}) is not valid JSON: {e}; refused (nothing started)")
    if not isinstance(v, dict):
        sys.exit(f"runapp: CONST_OVERRIDES ({src}) must be a JSON object {{\"Module.Constant\": \"value\"}}; refused")
    return v


HARNESS_AUTO = ["model\\metadata.json"]


def harness_files(base, name, mode):
    """Create run/<name>\\<rel> copies of the app's own files (T2R3-5, B4T2-13). Returns the HARNESS FILE line or None."""
    run = Path(base).parent
    for old in run.iterdir():  # the previous start's files of this name belong to the previous .mda
        if old.name.startswith(name + "\\") and old.is_file():
            old.unlink()
    if mode == "off" or os.sep == "\\":  # on Windows the Windows path is the real file already
        return None
    rels = HARNESS_AUTO if mode == "auto" else [r.strip() for r in mode.split(",") if r.strip()]
    made = []
    for rel in rels:
        rel = rel.replace("/", "\\").strip("\\")
        parts = rel.split("\\")
        if not rel or ".." in parts:
            sys.exit(f"runapp: --harness-file {rel!r}: an app-relative path without '..'")
        src = Path(base).joinpath(*parts)
        if not src.is_file():
            if mode == "auto":
                continue
            sys.exit(f"runapp: --harness-file {rel}: the app has no {src.relative_to(run)} to copy; refused")
        shutil.copyfile(src, run / f"{name}\\{rel}")
        made.append(f"run/{name}\\{rel}")
    if not made:
        return None
    msg = (f"HARNESS FILE: {name}: {', '.join(made)} (copy of the app's own file under the Windows path an add-on builds "
           f"at runtime, T2R3-5; same for old and new; --harness-file off leaves it out)")
    (Path(base) / "harness-files.txt").write_text(msg + "\n")
    return msg


def port_busy(port):
    """F21 (Purchase Request 10.24, real run): a debug app held 8080, `docker run` failed with exit 125 and the pipeline
    filed it as "needs judgment". A taken port is an environment fault: name the holder, the caller exits 3 (infra)."""
    import socket
    with socket.socket() as s:
        s.settimeout(1)
        if s.connect_ex(("127.0.0.1", port)) != 0:
            return None
    who = subprocess.run(["docker", "ps", "--filter", f"publish={port}", "--format", "{{.Names}}"],
                         capture_output=True, text=True).stdout.split()
    return ", ".join(who) or "a non-container process"


def start(name, mda, rtv, db, port_off=0, login_override=None, harness=None):
    overrides = const_overrides()  # B4T2-12: refuse a bad value before a database or container is touched
    pre = os.environ.get("UPG_DB_PREFIX")
    if pre and not db.startswith(pre):
        sys.exit(f"runapp: database {db!r} does not start with UPG_DB_PREFIX={pre!r}; refused")
    if not re.match(r"^[a-z0-9_]+$", db):
        sys.exit(f"runapp: database name {db!r}: use lower case letters, digits, underscore")
    rt = find_runtime(rtv)
    if rt is None:
        sys.exit(f"runapp: no runtime {rtv} under {TOOLS} (looked for runtime-{rtv}, runtime-{'.'.join(rtv.split('.')[:3])}, "
                 f"flat or with a <full version>/ level; see the docstring: the runtime is a separate download)")
    rtv = ".".join(rtv.split(".")[:3])
    (WORK / "logs").mkdir(parents=True, exist_ok=True)
    ensure_pg()
    if not sh("docker", "exec", PG, "psql", "-U", "mendix", "-tAc", f"SELECT 1 FROM pg_database WHERE datname='{db}'"):
        sh("docker", "exec", PG, "createdb", "-U", "mendix", db)
    base = WORK / "run" / name
    if base.exists():
        sh("rm", "-rf", str(base))
    base.mkdir(parents=True)
    (base / "runapp-db.txt").write_text(db + "\n")  # B4N1-16: save_log names a second copy of the log by it
    mdap = Path(mda) if os.path.isabs(mda) else WORK / mda
    zipfile.ZipFile(mdap).extractall(base)
    for d in ("data/files", "data/tmp", "data/model-upload", "data/database"):
        (base / d).mkdir(parents=True, exist_ok=True)
    note = apply_login_override(base, login_override or os.environ.get("UPG_LOGIN_OVERRIDE", "auto"), name)
    if note:
        print("runapp: " + note)
    ix = apply_index_override(base, name)
    if ix:
        print("runapp: " + ix)
    hf = harness_files(base, name, harness or os.environ.get("UPG_HARNESS_FILE", "auto"))
    if hf:
        print("runapp: " + hf)
    meta = json.loads((base / "model/metadata.json").read_text())
    consts = {c["Name"]: c.get("DefaultValue", "") for c in meta.get("Constants", [])}
    consts.update(overrides)
    extra, pnote = sso_push_override({c["Name"] for c in meta.get("Constants", [])}, overrides, name)
    if pnote:
        print("runapp: " + pnote)
        consts.update(extra)
    aport, rport = 8090 + port_off, 8080 + port_off
    cname = f"{PREFIX}-{name}"
    sh("docker", "rm", "-f", cname, check=False)  # only our own name: <prefix>-<name>
    for p in (rport, aport):
        who = port_busy(p)
        if who:
            print(f"runapp: INFRA port {p} in use by {who}; stop it (or set PORT_OFF) and rerun")
            return 3
    img = image_for(rtv)
    print(f"runapp: {cname} image {img}, runtime {rtv}, db {db}, ports {rport}/{aport}")
    sh("docker", "run", "-d", "--name", cname, "--network", NET, "-v", f"{WORK}:/w", "-v", f"{rt}:/rt:ro",
       "-p", f"{aport}:8090", "-p", f"{rport}:8080", "-e", "M2EE_ADMIN_PORT=8090", "-e", "M2EE_ADMIN_LISTEN_ADDRESSES=*",
       "-e", f"M2EE_ADMIN_PASS={PASS}", "-e", "MX_INSTALL_PATH=/rt",
       img, "java", "-Dfile.encoding=UTF-8", f"-Xmx{XMX}", "-jar", "/rt/runtime/launcher/runtimelauncher.jar", f"/w/run/{name}")
    for _ in range(180):
        try:
            admin(aport, "echo", {"echo": "ping"}); break
        except Exception:
            time.sleep(2)
    else:
        print(f"runapp: admin API did not come up; {save_log(name)}"); return 1
    admin(aport, "create_log_subscriber", {"type": "console", "name": "stdout", "autosubscribe": "INFO"})  # 10.24+ logs nothing without one
    admin(aport, "start_logging")
    admin(aport, "update_appcontainer_configuration", {"runtime_port": 8080, "runtime_listen_addresses": "*", "runtime_jetty_options": {}})
    cfg = {"DatabaseType": "PostgreSQL", "DatabaseHost": f"{PG}:5432", "DatabaseName": db, "DatabaseUserName": "mendix",
           "DatabasePassword": "mendix", "DTAPMode": "D", "ScheduledEventExecution": "NONE", "BasePath": f"/w/run/{name}",
           "RuntimePath": "/rt/runtime", "MxClientSystemPath": "/rt/runtime/mxclientsystem",
           "MicroflowConstants": consts, "ApplicationRootUrl": f"http://localhost:{rport}"}
    if os.environ.get("UPG_SESSION_TIMEOUT"):
        st = int(os.environ["UPG_SESSION_TIMEOUT"])
        cfg.update(SessionTimeout=st, ClusterManagerActionInterval=max(st // 2, 1000))
    print("update_configuration:", admin(aport, "update_configuration", cfg).get("result"))
    t0 = time.time()
    r = admin(aport, "start", {"autocreatedb": True})
    for i in range(5):  # 10.24 syncs in phases: each start can ask for a new DDL batch
        if r.get("result") != 3:
            break
        fb = admin(aport, "get_ddl_commands").get("feedback", {})
        ddl = fb.get("ddl_commands", [])  # 10.12 returns the list; 10.24 returns only {"count": n}
        (WORK / "logs" / f"ddl-{name}-{i}.sql").write_text("\n".join(ddl))
        print(f"DDL commands: {len(ddl) or fb.get('count')} (logs/ddl-{name}-{i}.sql; empty when the runtime only gives a count)")
        admin(aport, "execute_ddl_commands")
        r = admin(aport, "start", {"autocreatedb": True})
    print(f"start: result {r.get('result')} {r.get('message', '')[:300]} ({time.time() - t0:.0f}s)")
    if r.get("result") == 0:
        admin(aport, "create_admin_user", {"password": "Local-only-1!"})
        return 0
    print(f"runapp: NOT started; {save_log(name)}")
    return 1


def foreign_containers(name):
    """FM-9: containers <x>-<name> (x not the prefix in use) that a stop of <prefix>-<name> could be confused with."""
    out = subprocess.run(["docker", "ps", "-a", "--format", "{{.Names}}"], capture_output=True, text=True).stdout.split()
    return sorted(n for n in out if n.endswith(f"-{name}") and n != f"{PREFIX}-{name}" and n != PG)


# BT-9: what stays of run/<name>/ after a stop. Everything else is the unpacked package and what the runtime wrote beside it
# (a 26-module app left 950 MB after 5 starts). start wipes and unpacks the folder again, and nothing reads it after a stop.
KEEP_TOP = re.compile(r"^(harness-.*\.txt|runapp-db\.txt)$")


def prune_run(name):
    """Remove the bulk of run/<name>/ once its container is gone. Keeps harness-*.txt (HARNESS CONDITION evidence),
    runapp-db.txt and data/files (file contents the journeys and the snapshot refer to). UPG_KEEP_RUN=1 prunes nothing.
    Returns the number of bytes freed, or None when nothing was pruned."""
    base = WORK / "run" / name
    if os.environ.get("UPG_KEEP_RUN") or not base.is_dir():
        return None
    if f"{PREFIX}-{name}" in sh("docker", "ps", "-a", "--format", "{{.Names}}", check=False).split():
        return None  # the container is still there: its files are in use

    def size(d):
        return sum(f.stat().st_size for f in d.rglob("*") if f.is_file() and not f.is_symlink()) if d.is_dir() else d.stat().st_size

    freed = 0
    for e in sorted(base.iterdir()):
        if e.name == "data" and e.is_dir():
            for d in sorted(e.iterdir()):
                if d.name != "files":
                    freed += size(d)
                    shutil.rmtree(d, ignore_errors=True) if d.is_dir() else d.unlink()
            continue
        if KEEP_TOP.match(e.name):
            continue
        freed += size(e) if not e.is_symlink() else 0
        if e.is_dir() and not e.is_symlink():
            shutil.rmtree(e, ignore_errors=True)
            if e.exists():
                sh("rm", "-rf", str(e), check=False)  # files the container wrote as root
        else:
            e.unlink()
    print(f"runapp: pruned run/{name}: {freed / 1048576:.0f} MB freed; kept harness-*.txt, runapp-db.txt, data/files (UPG_KEEP_RUN=1 keeps all)")
    return freed


def stop(name, guard=True):
    if guard and not os.environ.get("UPG_NAME") and not os.environ.get("UPG_ALLOW_DEFAULT_PREFIX"):
        others = foreign_containers(name)
        if others:  # same class as MC-20: env.sh not sourced, the default prefix names another run's app
            print(f"runapp: REFUSED to stop {PREFIX}-{name}: UPG_NAME is not set (default prefix {PREFIX!r}) and other containers "
                  f"named like it exist: {', '.join(others)}. Source the run's env.sh (or set UPG_NAME=<prefix>) and repeat; "
                  "UPG_ALLOW_DEFAULT_PREFIX=1 stops the default one anyway.", file=sys.stderr)
            sys.exit(2)
    print(f"runapp: stopping container {PREFIX}-{name}")
    p = save_log(name)
    sh("docker", "rm", "-f", f"{PREFIX}-{name}", check=False)
    print(f"runapp: stopped {PREFIX}-{name}; log {p}")
    prune_run(name)


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("start", "quick", "logs", "stop"):
        sys.exit(__doc__)
    cmd, off = sys.argv[1], int(os.environ.get("PORT_OFF", 0))
    opts = {}
    for flag in ("--login-override", "--harness-file"):
        if flag in sys.argv:
            i = sys.argv.index(flag)
            if i + 1 >= len(sys.argv):
                sys.exit(__doc__)
            opts[flag] = sys.argv[i + 1]
            del sys.argv[i:i + 2]
    lo = opts.get("--login-override")
    if cmd in ("start", "quick"):
        if len(sys.argv) != 6:
            sys.exit(__doc__)
        rc = start(*sys.argv[2:6], port_off=off, login_override=lo, harness=opts.get("--harness-file"))
        if cmd == "quick" and rc != 3:
            time.sleep(3)
            stop(sys.argv[2], guard=False)
            print("QUICK START " + ("PASS: the new app starts" if rc == 0 else
                                    "FAIL: fix this before the gate (after-startup, constants, missing jars)"))
        sys.exit(rc)
    elif cmd == "logs":
        print(save_log(sys.argv[2]))
    else:
        stop(sys.argv[2])
