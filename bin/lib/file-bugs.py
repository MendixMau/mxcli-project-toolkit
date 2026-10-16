"""file-bugs.py: engine behind bin/file-bugs.sh (see that file for the contract).

Reads <project>/docs/bugs.jsonl, redacts, searches the target repo for duplicates, and either
shows (default), prints prefilled new-issue URLs (--links / --json) or files (--file/--all + y/N).
Only two repos are ever addressed; see TARGETS.
"""
import argparse, datetime, json, os, re, subprocess, sys, tempfile, urllib.parse

TARGETS = {"mxcli": "mendixlabs/mxcli", "toolkit": "MendixMau/mxcli-project-toolkit"}
ALLOWED_URL = ("github.com/mendixlabs/", "github.com/mendixmau/mxcli-project-toolkit")
TLDS = "com|net|org|io|dev|cloud|local|lan|internal|corp|intra|de|nl|uk|eu|us|fr|jp|cn|tw|th|kr|app|ai|co|info|biz"
URL_MAX = 6000
STOP_NAMES = {"system", "administration", "atlas_core", "atlas_web_content", "marketplace",
              "mxmodelreflection", "root", "user", "admin", "test", "mendix", "mxcli", "module",
              "entity", "app", "main"}

RE_PRIVKEY = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)", re.S)
RE_TOKENS = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}"
    r"|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b"
    r"|\bBearer\s+[A-Za-z0-9._~+/=-]{8,}")
RE_KV = re.compile(r"(?i)\b((?:[a-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|credential)[a-z0-9_.-]*|authorization))"
                   r"(\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\s,;]+)")
RE_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")
RE_URL = re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s)>\]\"',;]*[^\s)>\]\"',;.]")
RE_BARE = re.compile(r"\b(?:[A-Za-z0-9-]+\.)+(?:%s)\b(?::\d+)?(?:/[^\s)>\]\"',;]*[^\s)>\]\"',;.])?" % TLDS, re.I)
RE_PATH = re.compile(r"(?:/(?:Users|home)/[^/\s\"']+(?:/[^\s\"',;)]*)?|[A-Za-z]:\\+Users\\+[^\\\s]+(?:\\[^\s\"',;)]*)?"
                     r"|(?<![\w.])~/[^\s\"',;)]+|/Volumes/[^\s\"',;)]+)")
RE_IP4 = re.compile(r"(?<![\w.])(?<!v)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\w.])")
RE_IP6 = re.compile(r"(?<![\w:])(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}(?![\w:])")
RE_OPAQUE = re.compile(r"(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/=_-]{32,}(?![A-Za-z0-9+/=_-])")
RE_HEXSHA = re.compile(r"^[0-9a-fA-F]{7,40}$")


def sh(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kw)
    except OSError as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


class Redactor:
    def __init__(self, project, extra_names):
        self.project = project
        self.deny = self._load_deny()
        self.users = self._users()
        self.hosts = self._hosts()
        self.mods, self.ents, self.app = {}, {}, None
        self._names(extra_names)
        self.docs = {}

    # --- identity sources -------------------------------------------------------------
    def _load_deny(self):
        pats = []
        cands = [os.environ.get("LEAKGUARD_DENY"), os.path.join(self.project, ".leakguard-deny")]
        for c in cands:
            if not c or not os.path.isfile(c):
                continue
            for ln in open(c, errors="replace"):
                ln = ln.strip()
                if ln and not ln.startswith("#"):
                    try:
                        pats.append(re.compile(ln, re.I))
                    except re.error:
                        pass
            break
        return pats

    def _users(self):
        out = set()
        for v in (os.environ.get("USER"), os.environ.get("LOGNAME"), sh(["id", "-un"]).stdout.strip(),
                  os.path.basename(os.path.expanduser("~"))):
            if v:
                out.add(v)
        gn = sh(["git", "config", "user.name"]).stdout.strip()
        out.update(w for w in re.split(r"[\s.]+", gn) if w)
        return {u for u in out if len(u) >= 3 and u.lower() not in STOP_NAMES}

    def _hosts(self):
        out = set()
        for c in (["hostname"], ["hostname", "-s"]):
            v = sh(c).stdout.strip()
            if v:
                out.add(v)
                out.add(v.split(".")[0])
        return {h for h in out if len(h) >= 3 and h.lower() not in STOP_NAMES}

    def _names(self, extra):
        p = self.project
        mods, ents = set(), set()
        for f in os.listdir(p) if os.path.isdir(p) else []:
            if f.lower().endswith(".mpr"):
                self.app = f[:-4]
        pm = os.path.join(p, "PROJECT.md")
        if os.path.isfile(pm):
            for ln in open(pm, errors="replace"):
                m = re.match(r"(?i)^[\s*|>-]*(?:app|project)(?:\s+name)?\s*\**\s*[:|]\s*\**\s*([^|\n]+)", ln)
                if m and not self.app:
                    self.app = m.group(1).strip(" *`")
                m = re.match(r"(?i)^[\s*|>-]*modules?\s*\**\s*[:|]\s*\**\s*([^|\n]+)", ln)
                if m:
                    mods.update(x.strip(" *`") for x in re.split(r"[,;]", m.group(1)) if x.strip(" *`"))
        md = os.path.join(p, "mdlsource")
        for root, _d, files in os.walk(md):
            for f in files:
                if not f.lower().endswith((".mdl", ".md", ".txt", ".sql")):
                    continue
                try:
                    txt = open(os.path.join(root, f), errors="replace").read(400000)
                except OSError:
                    continue
                mods.update(re.findall(r"(?i)\bCREATE\s+MODULE\s+(\w+)", txt))
                for m, e in re.findall(r"(?i)\bCREATE\s+(?:OR\s+\w+\s+)?(?:(?:NON-)?PERSISTENT\s+|VIEW\s+|EXTERNAL\s+)?ENTITY\s+(\w+)\.(\w+)", txt):
                    mods.add(m)
                    ents.add(e)
        for x in extra:
            (mods if "." not in x else ents).add(x)
        mods = {m for m in mods if len(m) >= 3 and m.lower() not in STOP_NAMES}
        ents = {e for e in ents if len(e) >= 3 and e.lower() not in STOP_NAMES}
        for i, m in enumerate(sorted(mods), 1):
            self.mods[m] = "Module%d" % i
        for i, e in enumerate(sorted(ents)):
            self.ents[e] = "Entity" + (chr(65 + i) if i < 26 else chr(65 + i // 26 - 1) + chr(65 + i % 26))
        if self.app and (len(self.app) < 3 or self.app.lower() in STOP_NAMES):
            self.app = None

    # --- redaction ----------------------------------------------------------------------
    @staticmethod
    def _url_ok(s):
        s = re.sub(r"^[a-z][a-z0-9+.-]*://", "", s, flags=re.I).lower()
        return s.startswith(ALLOWED_URL)

    def redact(self, text):
        keep = []

        def hold(s):
            keep.append(s)
            return "\x00%d\x00" % (len(keep) - 1)

        t = text or ""
        t = RE_PRIVKEY.sub("<key>", t)
        t = RE_TOKENS.sub("<token>", t)
        t = RE_KV.sub(lambda m: m.group(1) + m.group(2) + "<redacted>", t)
        t = RE_EMAIL.sub("<email>", t)
        t = RE_URL.sub(lambda m: hold(m.group(0)) if self._url_ok(m.group(0)) else "<url>", t)
        t = RE_PATH.sub("<path>", t)
        t = RE_BARE.sub(lambda m: hold(m.group(0)) if self._url_ok(m.group(0)) else "<host>", t)
        t = RE_IP6.sub("<ip>", RE_IP4.sub("<ip>", t))
        for h in sorted(self.hosts, key=len, reverse=True):
            t = re.sub(r"(?i)(?<![\w])%s(?![\w])" % re.escape(h), "<host>", t)
        for u in sorted(self.users, key=len, reverse=True):
            t = re.sub(r"(?i)(?<![\w])%s(?![\w])" % re.escape(u), "<user>", t)
        for rx in self.deny:
            t = rx.sub("<redacted>", t)
        if self.app:
            t = re.sub(r"(?i)(?<![\w])%s(?![\w])" % re.escape(self.app), "App1", t)
        for m in sorted(self.mods, key=len, reverse=True):
            pm = self.mods[m]

            def qual(mm, pm=pm):
                name = mm.group(1)
                if name in self.ents:
                    return pm + "." + self.ents[name]
                self.docs.setdefault(name, "Doc%d" % (len(self.docs) + 1))
                return pm + "." + self.docs[name]
            t = re.sub(r"(?<![\w])%s\.(\w+)" % re.escape(m), qual, t)
            t = re.sub(r"(?<![\w])%s(?![\w])" % re.escape(m), pm, t)
        for e in sorted(self.ents, key=len, reverse=True):
            t = re.sub(r"(?<![\w.])%s(?![\w])" % re.escape(e), self.ents[e], t)
        return re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], t)

    def scan(self, text):
        """Return a list of reasons text still looks unsafe (empty = clean)."""
        bad = []
        probes = [("home path", RE_PATH), ("email", RE_EMAIL), ("IP address", RE_IP4), ("IPv6 address", RE_IP6),
                  ("token", RE_TOKENS), ("private key", RE_PRIVKEY)]
        for label, rx in probes:
            if rx.search(text):
                bad.append(label)
        for m in RE_URL.finditer(text):
            if not self._url_ok(m.group(0)):
                bad.append("URL " + m.group(0)[:40])
        for m in RE_BARE.finditer(text):
            if not self._url_ok(m.group(0)):
                bad.append("hostname " + m.group(0)[:40])
        for m in RE_KV.finditer(text):
            if m.group(3).strip("\"'") != "<redacted>":
                bad.append("secret assignment " + m.group(1))
        for m in RE_OPAQUE.finditer(text):
            s = m.group(0)
            if RE_HEXSHA.match(s) or not (re.search(r"\d", s) and re.search(r"[A-Za-z]", s)):
                continue
            bad.append("opaque string " + s[:12] + "...")
        words = list(self.users) + list(self.hosts) + list(self.mods) + list(self.ents) + ([self.app] if self.app else [])
        for w in words:
            if re.search(r"(?i)(?<![\w])%s(?![\w])" % re.escape(w), text):
                bad.append("name survives")
        for rx in self.deny:
            if rx.search(text):
                bad.append("deny-list match")
        return sorted(set(bad))


# --- bug rows -----------------------------------------------------------------------------
def load(path):
    rows, raw = [], []
    if not os.path.isfile(path):
        return rows, raw
    for n, ln in enumerate(open(path, errors="replace"), 1):
        raw.append(ln.rstrip("\n"))
        s = ln.strip()
        if not s:
            continue
        try:
            d = json.loads(s)
            if isinstance(d, dict):
                rows.append((n - 1, d))
        except ValueError:
            sys.stderr.write("file-bugs: %s line %d is not JSON, left untouched\n" % (path, n))
    return rows, raw


def text_of(v):
    if isinstance(v, list):
        return "\n".join("%d. %s" % (i, x) for i, x in enumerate(v, 1))
    return str(v or "")


def build(r, b):
    """Return (title, body, problems) for one bug, redacted and scanned."""
    vers = b.get("versions") or {}
    if isinstance(vers, dict):
        vtxt = ", ".join("%s %s" % (k, v) for k, v in vers.items() if v) or "not recorded"
    else:
        vtxt = str(vers)
    parts = ["**Versions:** " + vtxt, "### Steps to reproduce\n" + (text_of(b.get("repro")) or "-"),
             "### Expected\n" + (text_of(b.get("expected")) or "-"), "### Actual\n" + (text_of(b.get("actual")) or "-")]
    if b.get("workaround"):
        parts.append("### Workaround\n" + text_of(b["workaround"]))
    title = r.redact(str(b.get("title", "")))
    body = r.redact("\n\n".join(parts))
    return title, body, r.scan(title + "\n" + body)


def new_issue_url(repo, title, body):
    base = "https://github.com/%s/issues/new?title=%s&body=" % (repo, urllib.parse.quote(title, safe=""))
    note = "\n\n(truncated to fit a URL; full text is in the project bug log)"
    if len(base) + len(urllib.parse.quote(body, safe="")) <= URL_MAX:
        return base + urllib.parse.quote(body, safe=""), False
    lo, hi = 0, len(body)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if len(base) + len(urllib.parse.quote(body[:mid] + note, safe="")) <= URL_MAX:
            lo = mid
        else:
            hi = mid - 1
    return base + urllib.parse.quote(body[:lo] + note, safe=""), True


def dupes(repo, title):
    if not sh(["gh", "--version"]).returncode == 0:
        return None
    q = " ".join(re.findall(r"[A-Za-z0-9_]{3,}", title)[:8])
    p = sh(["gh", "issue", "list", "--repo", repo, "--state", "all", "--search", q + " in:title", "--limit", "5",
            "--json", "number,title,state,url"])
    if p.returncode != 0:
        p = sh(["gh", "search", "issues", "--repo", repo, q, "--limit", "5", "--json", "number,title,state,url"])
    if p.returncode != 0:
        return None
    try:
        return json.loads(p.stdout or "[]")
    except ValueError:
        return None


def write_back(path, bid, upd):
    rows, raw = load(path)
    for idx, d in rows:
        if d.get("id") == bid:
            d.update(upd)
            raw[idx] = json.dumps(d, ensure_ascii=False)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".bugs.")
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(raw) + "\n")
    os.replace(tmp, path)


def add(path, a):
    rows, _ = load(path)
    nums = [int(m.group(1)) for _, d in rows for m in [re.match(r"^BUG-(\d+)$", str(d.get("id", "")))] if m]
    bid = "BUG-%02d" % (max(nums, default=0) + 1)
    here = os.path.dirname(os.path.abspath(__file__))
    tk = sh(["git", "-C", os.path.join(here, "..", ".."), "describe", "--tags", "--always"]).stdout.strip()
    mx = a.mxcli or (sh(["mxcli", "--version"]).stdout.strip().splitlines() or [""])[0]
    row = {"id": bid, "date": datetime.date.today().isoformat(), "target": a.target, "title": a.title,
           "repro": a.repro, "expected": a.expected, "actual": a.actual,
           "versions": {"mxcli": mx, "mendix": a.mendix or "", "toolkit": a.toolkit_version or tk},
           "workaround": a.workaround or "", "status": "open", "issue_url": ""}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
    print("file-bugs: added %s to %s (local id; the public number comes from the issue)" % (bid, path))


def main():
    ap = argparse.ArgumentParser(prog="file-bugs.sh", add_help=True)
    ap.add_argument("--project", default=".")
    ap.add_argument("--file", action="append", default=[], metavar="BUG-NN")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--links", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--name", action="append", default=[], help="extra project name to redact")
    ap.add_argument("--add", action="store_true")
    for k in ("target", "title", "repro", "expected", "actual", "workaround", "mxcli", "mendix", "toolkit-version"):
        ap.add_argument("--" + k)
    a = ap.parse_args()
    project = os.path.abspath(a.project)
    path = os.path.join(project, "docs", "bugs.jsonl")
    if a.add:
        if a.target not in TARGETS or not (a.title and a.repro and a.expected and a.actual):
            sys.exit("file-bugs: --add needs --target mxcli|toolkit, --title, --repro, --expected, --actual")
        return add(path, a)
    rows, _ = load(path)
    if not os.path.isfile(path):
        sys.exit("file-bugs: no %s" % path)
    want = set(a.file)
    todo = [(i, d) for i, d in rows if d.get("status", "open") == "open" and (not want or d.get("id") in want)]
    for w in want:
        if not any(d.get("id") == w for _, d in rows):
            sys.exit("file-bugs: %s is not in %s" % (w, path))
        if not any(d.get("id") == w for _, d in todo):
            sys.stderr.write("file-bugs: %s is not open, skipped\n" % w)
    r = Redactor(project, a.name)
    out = []
    posting = bool(want or a.all) and not (a.links or a.json)
    if posting and not (sys.stdin.isatty() or os.environ.get("MXTK_FILE_BUGS_STDIN") == "1"):
        sys.exit("file-bugs: posting needs an interactive terminal (y/N per bug); nothing posted")
    for _, d in todo:
        target = d.get("target")
        repo = TARGETS.get(target)
        if not repo:
            sys.stderr.write("file-bugs: %s has target %r, not one of %s; skipped\n" % (d.get("id"), target, "/".join(TARGETS)))
            continue
        title, body, problems = build(r, d)
        url, trunc = (None, False) if problems else new_issue_url(repo, title, body)
        item = {"id": d.get("id"), "target": target, "repo": repo, "title": title, "body": body,
                "url": url, "truncated": trunc, "refused": problems}
        out.append(item)
        if a.json:
            continue
        if a.links:
            print("%s  %s\n  %s" % (d.get("id"), title, url or "REFUSED (%s)" % ", ".join(problems)))
            continue
        print("=" * 72 + "\n%s -> %s%s" % (d.get("id"), repo, "" if posting else "   [dry run, nothing is posted]"))
        print("TITLE: " + title + "\n--- BODY ---\n" + body + "\n--- END ---")
        dp = dupes(repo, title)
        if dp is None:
            print("Duplicates: search unavailable (gh missing or not authenticated)")
        elif not dp:
            print("Duplicates: none found")
        else:
            print("Likely duplicates:")
            for x in dp:
                print("  #%s [%s] %s  %s" % (x.get("number"), x.get("state"), x.get("title"), x.get("url")))
        if problems:
            print("WARNING: redaction left suspicious content (%s). Refusing to post this bug; fix the log row." % ", ".join(problems))
            continue
        if not posting:
            continue
        if want and d.get("id") not in want:
            continue
        if dp is None:
            print("Not posting: the duplicate search did not run.")
            continue
        sys.stdout.write("Post this to %s? [y/N] " % repo)
        sys.stdout.flush()
        ans = sys.stdin.readline().strip().lower()
        if ans != "y":
            print("skipped.")
            continue
        p = sh(["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body])
        m = re.search(r"https://github\.com/%s/issues/\d+" % re.escape(repo), p.stdout or "")
        if p.returncode != 0 or not m:
            print("gh issue create failed: " + (p.stderr or p.stdout).strip()[:300])
            continue
        write_back(path, d.get("id"), {"status": "filed", "issue_url": m.group(0)})
        print("filed: " + m.group(0))
    if a.json:
        print(json.dumps(out, indent=2, ensure_ascii=False))
    elif not out and not a.links:
        print("file-bugs: no open bugs")


if __name__ == "__main__":
    main()
