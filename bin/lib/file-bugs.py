"""file-bugs.py: engine behind bin/file-bugs.sh (see that file for the contract).

Reads <project>/docs/bugs.jsonl, redacts, searches the target repo for duplicates, and either
shows (default), prints prefilled new-issue URLs (--links / --json) or files (--file/--all + y/N
read from /dev/tty). Only two repos are ever addressed; see TARGETS.
"""
import argparse, datetime, ipaddress, json, os, re, subprocess, sys, tempfile, unicodedata, urllib.parse

TARGETS = {"mxcli": "mendixlabs/mxcli", "toolkit": "MendixMau/mxcli-project-toolkit"}
ALLOWED_REPOS = tuple(v.lower() for v in TARGETS.values())
URL_MAX = 6000
TITLE_URL_MAX = 1200
LOCAL_PREFIX = "PBUG"
STOP_NAMES = {"system", "administration", "atlas_core", "atlas_web_content", "marketplace",
              "mxmodelreflection", "root", "user", "admin", "test", "mendix", "mxcli", "module",
              "entity", "app", "main"}
TOKEN_WORDS = "module entity doc attr app host user path ip url email token key redacted commit"
GENERIC_ATTRS = {"name", "description", "title", "status", "type", "value", "date", "code", "email", "amount",
                 "number", "count", "active", "created", "changed", "owner", "text", "comment", "notes", "price",
                 "quantity", "address", "phone", "state", "category", "label", "order", "result", "message"}
FILE_EXT = set("mpr mdl md json jsonl sh py js ts tsx jsx css scss html htm xml yaml yml txt log sql zip mpk jar java "
               "exe dll png jpg jpeg gif svg pdf csv toml ini cfg conf lock tsv properties tmp bak swp map gz tar "
               "mjs cjs rb go rs c h cpp class so dylib bat ps1 cmd env pem key crt".split())
CONF_SKIP = {"package.json", "package-lock.json", "bugs.jsonl", "tsconfig.json"}

_CONF = {"\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c", "\u0445": "x", "\u0443": "y",
         "\u0456": "i", "\u0458": "j", "\u0455": "s", "\u0501": "d", "\u04bb": "h", "\u0410": "A", "\u0412": "B",
         "\u0415": "E", "\u041a": "K", "\u041c": "M", "\u041d": "H", "\u041e": "O", "\u0420": "P", "\u0421": "C",
         "\u0422": "T", "\u0425": "X", "\u0405": "S", "\u0406": "I", "\u0408": "J", "\u0391": "A", "\u0392": "B",
         "\u0395": "E", "\u0396": "Z", "\u0397": "H", "\u0399": "I", "\u039a": "K", "\u039c": "M", "\u039d": "N",
         "\u039f": "O", "\u03a1": "P", "\u03a4": "T", "\u03a5": "Y", "\u03a7": "X", "\u03bf": "o", "\u03bd": "v",
         "\u03b1": "a", "\u03b9": "i", "\u0131": "i"}
_CONF = {ord(k): v for k, v in _CONF.items()}
LB = r"(?:-?[ \t]*\r?\n[ \t]*)?"          # a name may be split by a line break (optionally hyphenated)

KEYW = r"(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|credential|private[_-]?key)"
RE_PRIVKEY = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)", re.S)
RE_TOKENS = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA)[0-9A-Z]{16}"
    r"|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b"
    r"|\bBearer\s+[A-Za-z0-9._~+/=-]{8,}")
RE_KV = re.compile(r"(?i)([\"']?)\b((?:[a-z0-9_.-]*" + KEYW + r"[a-z0-9_.-]*|authorization))\1(\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\s,;}\]]+)")
RE_FLAG = re.compile(r"(?i)(--?[a-z0-9_-]*" + KEYW + r"[a-z0-9_-]*)([ \t]+|=)(\"[^\"]*\"|'[^']*'|[^\s,;]+)")
RE_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")
RE_URL = re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s)>\]\"',;]*[^\s)>\]\"',;.]")
# any dotted name whose last label is lowercase letters and not a file extension (all TLDs, no fixed list)
RE_BARE = re.compile(r"(?<![\w.@/\\-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+(?P<tld>[a-z]{2,24}|[A-Z]{2,24})\b(?::\d+)?"
                     r"(?:/[^\s)>\]\"',;]*[^\s)>\]\"',;.])?")
_SEG = r"[^\\/\s\"',;)]+(?: [\w.-]+){0,2}"
RE_PATH = re.compile(r"(?i:/(?:users|home)/)(?:" + _SEG + r"[\\/]+)*[^\s\"',;)]*"
                     r"|(?i:[a-z]:\\+users\\+)(?:" + _SEG + r"\\+)*[^\s\"',;)]*"
                     r"|(?<![\w.])~/[^\s\"',;)]+|/Volumes/[^\s\"',;)]+")
RE_IP4 = re.compile(r"(?<![\w.])(?<!v)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\w.])")
RE_IP6 = re.compile(r"(?<![\w:])(?:(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}|[0-9A-Fa-f:]*::[0-9A-Fa-f:]*)(?:%\w+)?(?![\w:])")
RE_OPAQUE = re.compile(r"(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/=_-]{32,}(?![A-Za-z0-9+/=_-])")
RE_HEXTOK = re.compile(r"(?<![A-Za-z0-9])[0-9a-fA-F]{32,}(?![A-Za-z0-9])")
RE_VERCTX = re.compile(r"(?i)\b(?:mendix|studio\s*pro|mxbuild|mxcli|toolkit|runtime|version|v)\W{0,3}$")
RE_COMMITCTX = re.compile(r"(?i)\b(?:commit|sha)\W{0,3}$")
RE_VER = re.compile(r"\bv?\d+(?:\.\d+){1,3}(?:[-+][A-Za-z0-9.]+)?")


def sh(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, **kw)
    except OSError as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


def norm(t):
    """NFKC, drop format/zero-width characters, fold common Cyrillic/Greek lookalikes."""
    t = unicodedata.normalize("NFKC", t or "")
    t = "".join(c for c in t if unicodedata.category(c) != "Cf")
    return t.translate(_CONF)


def join_lb(t):
    return re.sub(r"-?[ \t]*\r?\n[ \t]*", "", t)


def url_ok(s):
    """Exactly one of the two target repos (case-insensitive), then end, / ? or #."""
    s = re.sub(r"^[a-z][a-z0-9+.-]*://", "", s, flags=re.I).lower()
    for repo in ALLOWED_REPOS:
        pre = "github.com/" + repo
        if s.startswith(pre) and (len(s) == len(pre) or s[len(pre)] in "/?#"):
            return True
    return False


def mask_ok(t):
    """Replace allowed repo URLs with a marker so name checks do not see them."""
    t = RE_URL.sub(lambda m: "\x01" if url_ok(m.group(0)) else m.group(0), t)
    return RE_BARE.sub(lambda m: "\x01" if url_ok(m.group(0)) else m.group(0), t)


def name_pat(name, sub):
    """Case-insensitive pattern for a name. sub=True: also inside identifiers (substring);
    sub=False: identifier-aware boundaries (not inside a longer letter/digit run, camelCase ok)."""
    n = norm(name)
    core = LB.join(re.escape(c) for c in n)
    if sub:
        return "(?i:" + core + ")"
    return r"(?<![A-Za-z0-9])(?i:" + core + r")(?![a-z0-9])"


def ip4_hits(t):
    out = []
    for m in RE_IP4.finditer(t):
        if not RE_VERCTX.search(t[max(0, m.start() - 24):m.start()]):
            out.append(m)
    return out


def ip6_ok(s):
    try:
        ipaddress.IPv6Address(s.split("%")[0])
        return bool(re.search(r"[0-9A-Fa-f]", s))
    except ValueError:
        return False


def host_hit(m):
    tld = m.group("tld")
    return tld.lower() not in FILE_EXT and not url_ok(m.group(0))


def hex_ok(t, m):
    s = m.group(0)
    return len(s) in (40, 64) and bool(RE_COMMITCTX.search(t[max(0, m.start() - 12):m.start()]))


class Redactor:
    def __init__(self, project, extra_names):
        self.project = project
        self.warnings = []
        self.deny = self._load_deny()
        self.users = self._users()
        self.hosts = self._hosts() | self._config_hosts()
        self.hosts = {h for h in self.hosts if not self._generic(h)}
        self.mods, self.ents, self.attrs, self.docs, self.app = {}, {}, {}, {}, None
        self._names(extra_names)
        self._compile()

    # --- identity sources -------------------------------------------------------------
    def _load_deny(self):
        """$LEAKGUARD_DENY is a regex value like check-no-client-data.sh reads it ('Foo|Bar'); a value
        that names an existing file is read as a file of one pattern per line. The project's
        .leakguard-deny is read as well. Bad patterns are escaped (never dropped) and warned about."""
        pats = []

        def add(pat, src):
            try:
                pats.append(re.compile(pat, re.I))
            except re.error:
                self.warnings.append("deny list %s: invalid regex %r, matching it literally" % (src, pat[:40]))
                pats.append(re.compile(re.escape(pat), re.I))

        env = os.environ.get("LEAKGUARD_DENY", "")
        files = [os.path.join(self.project, ".leakguard-deny")]
        if env and os.path.isfile(env):
            files.insert(0, env)
        elif env:
            add(env, "$LEAKGUARD_DENY")
        for f in files:
            if not os.path.isfile(f):
                continue
            for ln in open(f, errors="replace"):
                ln = ln.strip()
                if ln and not ln.startswith("#"):
                    add(norm(ln), f)
        if not pats:
            self.warnings.append("no deny list ($LEAKGUARD_DENY unset, no <project>/.leakguard-deny): "
                                 "client names outside the project files cannot be caught")
        return pats

    def _generic(self, w):
        lw = w.lower()
        return len(w) < 3 or lw in STOP_NAMES or lw in ("localhost", "true", "false", "none", "null", "example") \
            or lw in TOKEN_WORDS.split()

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

    def _config_hosts(self):
        """Server names from the project's config files (host/server/url/endpoint values, ://host)."""
        out, seen = set(), 0
        p = self.project
        dirs = [p] + [os.path.join(p, d) for d in ("config", "configs", "deployment", "settings", "docker", "env", "conf")]
        kv = re.compile(r"(?i)\b[\w.-]*(?:host|server|endpoint|address|domain|url|uri)[\w.-]*[\"']?\s*[:=]\s*[\"']?([^\s\"',;#}]+)")
        for d in dirs:
            if not os.path.isdir(d):
                continue
            for f in sorted(os.listdir(d)):
                fp = os.path.join(d, f)
                if (not os.path.isfile(fp) or f in CONF_SKIP or seen > 60 or
                        not re.search(r"(?i)(\.(ya?ml|properties|conf|cfg|ini|env|json|toml|xml)$|^dockerfile|docker-compose|^\.env)", f)):
                    continue
                seen += 1
                try:
                    txt = norm(open(fp, errors="replace").read(200000))
                except OSError:
                    continue
                vals = kv.findall(txt) + re.findall(r"://(?:[^/\s@\"']*@)?([^/\s:\"'?#]+)", txt)
                for v in vals:
                    v = re.sub(r"^[a-z][a-z0-9+.-]*://", "", v, flags=re.I)
                    v = re.sub(r"^[^/@]*@", "", v).split("/")[0].split(":")[0].strip("[]")
                    if (re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]{2,}$", v) and not re.match(r"^[\d.]+$", v)):
                        out.add(v)
                        if "." in v and len(v.split(".")[0]) >= 4:
                            out.add(v.split(".")[0])
        return out

    def _names(self, extra):
        p = self.project
        mods, ents, attrs, docs = set(), set(), set(), set()
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
                for body in re.findall(r"(?is)\bENTITY\s+\w+\.\w+\s*\((.*?)\)\s*(?:;|/|$)", txt):
                    attrs.update(re.findall(r"(?m)(?:^|[(,])\s*(\w+)\s*:\s*[A-Za-z]", body))
                attrs.update(re.findall(r"(?i)\bADD\s+ATTRIBUTE\s+(\w+)", txt))
                for m, n in re.findall(r"(?i)\bCREATE\s+(?:OR\s+(?:MODIFY|REPLACE)\s+)?(?!MODULE\b)(?:[A-Za-z-]+\s+){0,3}?(\w+)\.(\w+)", txt):
                    mods.add(m)
                    docs.add(n)
        for x in extra:
            (mods if "." not in x else ents).add(x.split(".")[-1] if "." in x else x)
        ok = lambda s: not self._generic(s)
        mods, ents, docs = {m for m in mods if ok(m)}, {e for e in ents if ok(e)}, {d for d in docs if ok(d)}
        attrs = {a for a in attrs if len(a) >= 4 and a.lower() not in GENERIC_ATTRS and ok(a)}
        docs -= ents | mods
        for i, m in enumerate(sorted(mods), 1):
            self.mods[m] = "Module%d" % i
        for i, e in enumerate(sorted(ents)):
            self.ents[e] = "Entity" + (chr(65 + i) if i < 26 else chr(65 + i // 26 - 1) + chr(65 + i % 26))
        for i, a in enumerate(sorted(attrs), 1):
            self.attrs[a] = "Attr%d" % i
        for i, d in enumerate(sorted(docs), 1):
            self.docs[d] = "Doc%d" % i
        if self.app and (len(self.app) < 3 or self.app.lower() in STOP_NAMES):
            self.app = None

    def _compile(self):
        """One matcher list shared by redact() and scan(): (token, regex, kind)."""
        subs = [(self.mods, "mod"), (self.ents, "ent"), (self.docs, "doc")]
        self.matchers = []
        if self.app:
            self.matchers.append((self.app, "App1", name_pat(self.app, True)))
        for table, _k in subs:
            for n, tok in table.items():
                self.matchers.append((n, tok, name_pat(n, True)))
        for n, tok in self.attrs.items():
            self.matchers.append((n, tok, name_pat(n, False)))
        for u in self.users:
            self.matchers.append((u, "<user>", name_pat(u, False)))
        for h in self.hosts:
            self.matchers.append((h, "<host>", name_pat(h, False)))
        self.matchers.sort(key=lambda x: -len(x[0]))
        self.mrx = [(re.compile(rx), tok) for _n, tok, rx in self.matchers]

    # --- redaction ----------------------------------------------------------------------
    def redact(self, text):
        keep = []

        def hold(s):
            keep.append(s)
            return "\x00%d\x00" % (len(keep) - 1)

        t = norm(text)
        t = RE_PRIVKEY.sub("<key>", t)
        t = RE_TOKENS.sub("<token>", t)
        t = RE_KV.sub(lambda m: m.group(1) + m.group(2) + m.group(1) + m.group(3) + "<redacted>", t)
        t = RE_FLAG.sub(lambda m: m.group(1) + m.group(2) + "<redacted>", t)
        t = RE_HEXTOK.sub(lambda m: hold(m.group(0)) if hex_ok(t, m) else "<token>", t)
        t = RE_EMAIL.sub("<email>", t)
        t = RE_URL.sub(lambda m: hold(m.group(0)) if url_ok(m.group(0)) else "<url>", t)
        t = RE_PATH.sub("<path>", t)
        t = RE_BARE.sub(lambda m: "<host>" if host_hit(m) else (hold(m.group(0)) if url_ok(m.group(0)) else m.group(0)), t)
        t = RE_IP6.sub(lambda m: "<ip>" if ip6_ok(m.group(0)) else m.group(0), t)
        t = RE_IP4.sub(lambda m: m.group(0) if RE_VERCTX.search(t[max(0, m.start() - 24):m.start()]) else "<ip>", t)
        for rx in self.deny:
            t = rx.sub("<redacted>", t)
        for m, pm in sorted(self.mods.items(), key=lambda x: -len(x[0])):
            def qual(mm, pm=pm):
                low = mm.group(1).lower()
                for tbl in (self.ents, self.docs):
                    for k, v in tbl.items():
                        if k.lower() == low:
                            return pm + "." + v
                self.docs[mm.group(1)] = "Doc%d" % (len(self.docs) + 1)
                return pm + "." + self.docs[mm.group(1)]
            t = re.sub(r"(?<![A-Za-z0-9])" + name_pat(m, True) + r"\.(\w+)", qual, t)
        for rx, tok in self.mrx:
            t = rx.sub(tok, t)
        return re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], t)

    def scan(self, text):
        """Return a list of reasons text still looks unsafe (empty = clean)."""
        t0 = norm(text)
        bad = []
        for m in RE_URL.finditer(t0):
            if not url_ok(m.group(0)):
                bad.append("URL " + m.group(0)[:40])
        tm = mask_ok(t0)
        t = tm
        for label, rx in (("home path", RE_PATH), ("email", RE_EMAIL), ("token", RE_TOKENS), ("private key", RE_PRIVKEY)):
            if rx.search(t):
                bad.append(label)
        if ip4_hits(t):
            bad.append("IP address")
        if any(ip6_ok(m.group(0)) for m in RE_IP6.finditer(t)):
            bad.append("IPv6 address")
        for m in RE_BARE.finditer(t):
            if host_hit(m):
                bad.append("hostname " + m.group(0)[:40])
        for m in RE_KV.finditer(t):
            if m.group(4).strip("\"'") != "<redacted>":
                bad.append("secret assignment " + m.group(2))
        for m in RE_FLAG.finditer(t):
            if m.group(3).strip("\"'") != "<redacted>":
                bad.append("secret flag " + m.group(1))
        for m in RE_OPAQUE.finditer(t):
            s = m.group(0)
            if RE_HEXTOK.fullmatch(s):
                if not hex_ok(t, m):
                    bad.append("opaque string " + s[:12] + "...")
            elif re.search(r"\d", s) and re.search(r"[A-Za-z]", s):
                bad.append("opaque string " + s[:12] + "...")
        for t in (tm, join_lb(tm)):
            for rx, tok in self.mrx:
                if rx.search(t):
                    bad.append("name survives")
            for rx in self.deny:
                if rx.search(t):
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


def versions_line(vers):
    """Only version-shaped strings, taken from the row and never run through redact()."""
    items = vers.items() if isinstance(vers, dict) else [("version", vers)]
    out = []
    for k, v in items:
        m = RE_VER.search(str(v or ""))
        k = re.sub(r"[^A-Za-z0-9 _-]", "", str(k))[:16]
        if m and k:
            out.append("%s %s" % (k, m.group(0)))
    return ", ".join(out) or "not recorded"


def build(r, b):
    """Return (title, body, problems) for one bug, redacted and scanned."""
    parts = ["### Steps to reproduce\n" + (text_of(b.get("repro")) or "-"),
             "### Expected\n" + (text_of(b.get("expected")) or "-"), "### Actual\n" + (text_of(b.get("actual")) or "-")]
    if b.get("workaround"):
        parts.append("### Workaround\n" + text_of(b["workaround"]))
    title = re.sub(r"\s+", " ", r.redact(str(b.get("title", ""))))
    body = "**Versions:** " + versions_line(b.get("versions")) + "\n\n" + r.redact("\n\n".join(parts))
    return title, body, r.scan(title + "\n" + body)


def new_issue_url(repo, title, body):
    q = lambda s: urllib.parse.quote(s, safe="")
    trunc = False
    if len(q(title)) > TITLE_URL_MAX:
        lo, hi = 0, len(title)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if len(q(title[:mid] + "...")) <= TITLE_URL_MAX:
                lo = mid
            else:
                hi = mid - 1
        title, trunc = title[:lo] + "...", True
    base = "https://github.com/%s/issues/new?title=%s&body=" % (repo, q(title))
    note = "\n\n(truncated to fit a URL; full text is in the project bug log)"
    if len(base) + len(q(body)) <= URL_MAX:
        return base + q(body), trunc
    lo, hi = 0, len(body)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if len(base) + len(q(body[:mid] + note)) <= URL_MAX:
            lo = mid
        else:
            hi = mid - 1
    return base + q(body[:lo] + note), True


def dupes(repo, title):
    """Called only with a redacted title that passed the final scan."""
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
        if str(d.get("id")) == bid:
            d.update(upd)
            raw[idx] = json.dumps(d, ensure_ascii=False)
    mode = os.stat(path).st_mode & 0o7777
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".bugs.")
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(raw) + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def add(path, a):
    rows, _ = load(path)
    nums = [int(m.group(1)) for _, d in rows for m in [re.match(r"^%s-(\d+)$" % LOCAL_PREFIX, str(d.get("id", "")))] if m]
    bid = "%s-%02d" % (LOCAL_PREFIX, max(nums, default=0) + 1)
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
    print("file-bugs: added %s to %s (local id, not a toolkit BUG-n; the public number comes from the issue)" % (bid, path))


def tty_open():
    """The only place a posting answer is read from: the controlling terminal."""
    try:
        fd = os.open("/dev/tty", os.O_RDWR)
    except OSError:
        return None
    return os.fdopen(os.dup(fd), "w"), os.fdopen(fd, "r")


def confirm(tty, repo):
    out, inp = tty
    out.write("Post this to %s? [y/N] " % repo)
    out.flush()
    return inp.readline().strip().lower() == "y"


def gh_create(repo, title, body):
    fd, bf = tempfile.mkstemp(prefix="file-bugs-body.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(body)
        return sh(["gh", "issue", "create", "--repo=" + repo, "--title=" + title, "--body-file=" + bf])
    finally:
        try:
            os.unlink(bf)
        except OSError:
            pass


REFUSED_NOTE = "refused: run the dry run to see why"


def main():
    ap = argparse.ArgumentParser(prog="file-bugs.sh", add_help=True)
    ap.add_argument("--project", default=".")
    ap.add_argument("--file", action="append", default=[], metavar="PBUG-NN")
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
    sid = lambda d: str(d.get("id"))
    todo = [(i, d) for i, d in rows if d.get("status", "open") == "open" and (not want or sid(d) in want)]
    for w in want:
        if not any(sid(d) == w for _, d in rows):
            sys.exit("file-bugs: %s is not in %s" % (w, path))
        if not any(sid(d) == w for _, d in todo):
            sys.stderr.write("file-bugs: %s is not open, skipped\n" % w)
    posting = bool(want or a.all) and not (a.links or a.json)
    tty = None
    if posting:
        tty = tty_open()
        if tty is None:
            sys.exit("file-bugs: posting needs an interactive terminal (/dev/tty, y/N per bug); nothing posted")
    r = Redactor(project, a.name)
    for w in r.warnings:
        sys.stderr.write("file-bugs: warning: %s\n" % w)
    out = []
    for _, d in todo:
        target = d.get("target")
        repo = TARGETS.get(target) if isinstance(target, str) else None
        if not repo:
            sys.stderr.write("file-bugs: %s has target %s, not one of %s; skipped\n" %
                             (sid(d), json.dumps(target)[:40], "/".join(TARGETS)))
            continue
        title, body, problems = build(r, d)
        if problems:
            item = {"id": sid(d), "target": target, "repo": repo, "refused": True, "note": REFUSED_NOTE}
        else:
            url, trunc = new_issue_url(repo, title, body)
            item = {"id": sid(d), "target": target, "repo": repo, "title": title, "body": body,
                    "url": url, "truncated": trunc, "refused": False}
        out.append(item)
        if a.json:
            continue
        if a.links:
            print("%s  %s" % (sid(d), REFUSED_NOTE if problems else title + "\n  " + item["url"]))
            continue
        print("=" * 72 + "\n%s -> %s%s" % (sid(d), repo, "" if posting else "   [dry run, nothing is posted]"))
        print("TITLE: " + title + "\n--- BODY ---\n" + body + "\n--- END ---")
        if problems:
            print("WARNING: redaction left suspicious content (%s). Refusing to post this bug; no duplicate search was run; "
                  "fix the log row." % ", ".join(problems))
            continue
        dp = dupes(repo, title)
        if dp is None:
            print("Duplicates: search unavailable (gh missing or not authenticated)")
        elif not dp:
            print("Duplicates: none found")
        else:
            print("Likely duplicates:")
            for x in dp:
                print("  #%s [%s] %s  %s" % (x.get("number"), x.get("state"), x.get("title"), x.get("url")))
        if not posting:
            continue
        if want and sid(d) not in want:
            continue
        if dp is None:
            print("Not posting: the duplicate search did not run.")
            continue
        if not confirm(tty, repo):
            print("skipped.")
            continue
        p = gh_create(repo, title, body)
        m = re.search(r"https://github\.com/%s/issues/\d+" % re.escape(repo), p.stdout or "")
        if p.returncode != 0 or not m:
            print("gh issue create failed: " + (p.stderr or p.stdout).strip()[:300])
            continue
        write_back(path, sid(d), {"status": "filed", "issue_url": m.group(0)})
        print("filed: " + m.group(0))
    if a.json:
        print(json.dumps(out, indent=2, ensure_ascii=False))
    elif not out and not a.links:
        print("file-bugs: no open bugs")


if __name__ == "__main__":
    main()
