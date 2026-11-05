"""file-bugs.py: engine behind bin/file-bugs.sh (see that file for the contract).

Reads <project>/docs/bugs.jsonl, redacts, searches the target repo for duplicates, and either
shows (default), prints prefilled new-issue URLs (--links / --json), files (--file/--all + y/N
read from /dev/tty) or, in a project whose PROJECT.md says `Bug filing: auto`, files every open row
that passes the scan without a y/N (--auto). Only two repos are ever addressed; see TARGETS.
"""
import argparse, datetime, ipaddress, json, os, re, shutil, subprocess, sys, tempfile, unicodedata, urllib.parse

TARGETS = {"mxcli": "mendixlabs/mxcli", "toolkit": "MendixMau/mxcli-project-toolkit"}
TOOLKIT_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ALLOWED_REPOS = tuple(v.lower() for v in TARGETS.values())
URL_MAX = 6000
TITLE_URL_MAX = 1200
LOCAL_PREFIX = "PBUG"
AUTO_LABEL = "auto-filed"
LOG_LINES = 40
LOG_CHARS = 8000
FENCE = "`" * 3
# The opt-in: a PROJECT.md line that says exactly `Bug filing: auto`, bold/backtick/list-bullet
# variants allowed, nothing else on the line, outside an HTML comment (the template ships one
# commented out). "auto (maybe)" or "auto?" is NOT an opt-in: an annotated line never posts.
RE_OPTIN = re.compile(r"(?im)^[ \t]*(?:[-*+][ \t]+)?bug filing[ \t]*:[ \t]*auto[ \t]*$")
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
# Names that are ordinary words, short, or mxcli/MDL/Mendix words: matched as whole words or identifier
# segments only, never inside other words. KW_NAMES are verbs/keywords: matched only in their exact
# spelling, so `mxcli create` or `check` in prose survive an entity called Create or Check.
KW_NAMES = set("""create check describe build show list edit view new test run init add drop alter select insert update delete
exec execute lint format validate search install uninstall marketplace catalog open save close start stop import export diff
apply rename move set get use help version doctor sync serve tunnel domain page microflow nanoflow entity module enumeration
association attribute workflow snippet layout widget security project report input output index status error warning""".split())
COMMON_NAMES = set("""order orders home admin account accounts user users customer customers product products item items sales
shop store invoice invoices payment payments person people employee employees task tasks ticket tickets message messages
document documents request requests setting settings person address data file files group groups role roles event events
booking bookings contact contacts company department project projects client clients supplier vendor article articles
category categories price offer offers cart basket delivery shipment""".split())
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
RE_AUTH = re.compile(r"(?i)\b((?:proxy-)?authorization)(\s*[:=]\s*)[\"']?(?:basic|bearer|digest|token|negotiate|ntlm|aws4-hmac-sha256|apikey)\s+[^\s\"',;]+")
RE_HDR = re.compile(r"(?im)^([ \t]*(?:set-cookie|cookie|www-authenticate|x-[\w-]*(?:auth|token|key|secret)[\w-]*)[ \t]*:(?![ \t]*<redacted>[ \t]*$)[ \t]*)(.+)$")
RE_KV = re.compile(r"(?i)([\"']?)\b((?:[a-z0-9_.-]*" + KEYW + r"[a-z0-9_.-]*|authorization))\1(\s*[:=]\s*)(\"[^\"]*\"|'[^']*'|[^\s,;}\]]+)")
RE_FLAG = re.compile(r"(?i)(--?[a-z0-9_-]*" + KEYW + r"[a-z0-9_-]*)([ \t]+|=)(\"[^\"]*\"|'[^']*'|[^\s,;]+)")
RE_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+")
RE_URL = re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s)>\]\"',;]*[^\s)>\]\"',;.]")
# any dotted name whose last label is lowercase letters and not a file extension (all TLDs, no fixed list)
RE_BARE = re.compile(r"(?<![\w.@/\\-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+(?P<tld>[a-z]{2,24}|[A-Z]{2,24})\b(?::\d+)?"
                     r"(?:/[^\s)>\]\"',;]*[^\s)>\]\"',;.])?")
# Dotted names that are code, not hosts (#646). Only these shapes, each kept only when no deny
# pattern matches it (deny and name matching still run over the kept text afterwards):
#   obj.method( / os.path.join(  2-3 identifier labels directly followed by "(", last label not a
#                                common TLD (zonkco.com( and intranet.zonkco.org( stay hosts)
#   org.<org>.common.service.lib a reversed-domain package of 3+ lowercase identifier labels: the
#                                organisation label (2nd) is replaced, the rest of the shape kept
#   java.util.concurrent         a JDK/platform package root: kept whole
RE_CALL = re.compile(r"^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*){1,2}$")
RE_PKG = re.compile(r"^[a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*){2,}$")
PKG_ORG_ROOTS = set("com org net io nl de be fr uk ch at dk se no fi es it eu edu gov".split())
PKG_PLATFORM_ROOTS = set("java javax jakarta android androidx kotlin kotlinx scala jdk sun".split())
CALL_TLD_NOT = set("com org net io dev app co uk de nl be fr eu ch at us info biz cloud local lan corp internal intra "
                   "int edu gov mil".split())
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


_ALLOWED = re.compile(r"(?i)^((?:https?://)?github\.com/(?:" + "|".join(re.escape(r) for r in ALLOWED_REPOS) +
                      r"))((?:/(?:issues|pull)/\d+)?)(?![\w.-])(.*)$", re.S)


def split_allowed(s):
    """(kept, rest) for a URL under one of the two target repos, else None. Kept is the repo prefix
    plus /issues/N or /pull/N; rest (any other path, query, fragment) is never kept."""
    m = _ALLOWED.match(s)
    return (m.group(1) + m.group(2), m.group(3)) if m else None


def url_ok(s):
    """Exactly the repo prefix, optionally /issues/N or /pull/N; nothing after it."""
    a = split_allowed(s)
    return bool(a) and a[1] == ""


SCHEMES = ("http", "https", "jdbc", "postgres", "postgresql", "mysql", "mongodb", "redis", "amqp", "ftp", "file", "ssh", "git")


def url_clean(s):
    """What a URL becomes: the allowed prefix, a non-web scheme with its host redacted, or <url>."""
    a = split_allowed(s)
    if a:
        return a[0]
    m = re.match(r"(?i)^([a-z][a-z0-9+.-]*)://", s)
    if m and m.group(1).lower() not in ("http", "https", "ftp") and m.group(1).lower() in SCHEMES:
        return m.group(1) + "://<host>"
    return "<url>"


def url_safe(s):
    m = re.match(r"(?i)^([a-z][a-z0-9+.-]*)://<host>?$", s)
    return url_ok(s) or bool(m and m.group(1).lower() in SCHEMES)


def mask_ok(t):
    """Replace allowed repo URLs with a marker so name checks do not see them."""
    t = RE_URL.sub(lambda m: "\x01" if url_safe(m.group(0)) else m.group(0), t)
    return RE_BARE.sub(lambda m: "\x01" if url_ok(m.group(0)) else m.group(0), t)


def is_weak(n):
    ln = n.lower()
    return len(n) < 5 or ln in COMMON_NAMES or ln in KW_NAMES


def name_pat(name, sub=None):
    """Case-insensitive pattern for a name, line-break tolerant. Distinctive names (5+ chars, not an
    English, MDL or Mendix word) match anywhere, also inside identifiers. Weak names match only as a
    whole word or identifier segment (ACT_Order_Save, OrderOverview, myOrder; not ordering). Keyword
    names (Create, Check) match only in their exact spelling."""
    n = norm(name)
    core = LB.join(re.escape(c) for c in n)
    if sub is None:
        sub = not is_weak(n)
    if sub:
        return "(?i:" + core + ")"
    if n.lower() in KW_NAMES:
        return r"(?<![A-Za-z0-9])" + core + r"(?![a-z0-9])"
    cap = LB.join(re.escape(c) for c in n[:1].upper() + n[1:])
    return r"(?:(?<![A-Za-z0-9])(?i:" + core + r")|(?<=[a-z0-9])" + cap + r")(?![a-z0-9])"


def _toolkit_names():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, "..", ".."))
    names = set()
    for d in ("bin", "bin/lib", "project-bin", "skills", "agents"):
        try:
            for f in os.listdir(os.path.join(root, d)):
                if os.path.isfile(os.path.join(root, d, f)):
                    names.add(f)
                    stem = f.rsplit(".", 1)[0]
                    if "-" in stem and len(stem) >= 6:
                        names.add(stem)
        except OSError:
            pass
    # the toolkit's and a scaffolded project's own top-level files: public names, never a client's
    # (a fixed list, not a directory listing: an untracked scratch file in the clone root is not public)
    names.update("CLAUDE.md CLAUDE.local.md AGENTS.md README.md CONTRIBUTING.md CHANGELOG.md CONVERSION-RUNBOOK.md "
                 "ROUTING.md PROJECT.md intake.md toolkit-guide.html".split())
    return names


_TK = _toolkit_names()
RE_TKFILE = re.compile(r"(?<![\w.-])(?:" + "|".join(re.escape(x) for x in sorted(_TK, key=lambda x: -len(x))) + r")(?![\w-])") if _TK else None
RE_MXCLI = re.compile(r"(?i)\bmxcli(?:\.exe)?(?:[ \t]+--?[\w-]+)*[ \t]+[a-z][a-z-]*(?:[ \t]+[a-z][a-z-]*)?")


def protect(t, hold):
    """Keep toolkit file names (anything in bin/, project-bin/, skills/) and mxcli verbs out of name matching."""
    if RE_TKFILE:
        t = RE_TKFILE.sub(lambda m: hold(m.group(0)), t)

    def verbs(m):
        return re.sub(r"(?<=[ \t])[a-z][a-z-]*", lambda w: hold(w.group(0)) if w.group(0) in KW_NAMES else w.group(0),
                      m.group(0))
    return RE_MXCLI.sub(verbs, t)


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


def code_form(m, deny):
    """What a RE_BARE match that is code becomes (see RE_CALL / RE_PKG), or None when it is a host."""
    s, txt = m.group(0), m.string
    if any(rx.search(s) for rx in deny):
        return None
    labels = s.split(".")
    if RE_CALL.match(s) and txt[m.end():m.end() + 1] == "(" and labels[-1].lower() not in CALL_TLD_NOT:
        return s
    if RE_PKG.match(s):
        if labels[0] in PKG_PLATFORM_ROOTS:
            return s
        if labels[0] in PKG_ORG_ROOTS:
            return ".".join([labels[0], "<org>"] + labels[2:])
    return None


def hex_ok(t, m):
    s = m.group(0)
    return len(s) in (40, 64) and bool(RE_COMMITCTX.search(t[max(0, m.start() - 12):m.start()]))


class Redactor:
    def __init__(self, project, extra_names):
        self.project = project
        self.warnings = []
        self.bad_deny = []
        self.own_deny = 0
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
        .leakguard-deny is read as well, and so is the toolkit clone's own .leakguard-deny
        ($MXTK_LEAKGUARD_DENYFILE overrides it, as in init-project.sh), where init-project.sh registers
        every scaffolded project's name (#645). That list redacts but does not count as this project's
        deny list (own_deny): it holds other projects' names, not this client's. An invalid pattern is
        recorded in bad_deny."""
        pats = []

        def add(pat, src):
            try:
                pats.append(re.compile(pat, re.I))
                return
            except re.error:
                pass
            # invalid as a whole: nothing is kept, posting/--links/--json are refused until it is fixed
            self.bad_deny.append("%s: %r" % (src, pat[:60]))

        env = os.environ.get("LEAKGUARD_DENY", "")
        files = [os.path.join(self.project, ".leakguard-deny")]
        if env and os.path.isfile(env):
            files.insert(0, env)
        elif env:
            add(env, "$LEAKGUARD_DENY")
        tk = os.environ.get("MXTK_LEAKGUARD_DENYFILE") or os.path.join(TOOLKIT_ROOT, ".leakguard-deny")
        for f in files + [None, tk]:
            if f is None:
                self.own_deny = len(pats)
                continue
            if not os.path.isfile(f):
                continue
            for ln in open(f, errors="replace"):
                ln = ln.strip()
                if ln and not ln.startswith("#"):
                    add(norm(ln), f)
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
        out.update(w for w in re.split(r"[\s._-]+", gn) if w)
        for u in list(out):
            out.update(w for w in re.split(r"[._-]+", u) if w)   # first.last: the whole and each part
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
                    v = re.sub(r"^(?:[a-z][a-z0-9+.-]*:)+//", "", v, flags=re.I)
                    v = re.sub(r"^[^/@]*@", "", v).split("/")[0].split(":")[0].strip("[]")
                    if re.match(r"(?i)^(?:jdbc|postgres(?:ql)?|mysql|mariadb|sqlserver|oracle|mongodb|redis|amqp|https?|ftp|ldaps?)$", v):
                        continue
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
        self.matchers = []
        if self.app:
            self.matchers.append((self.app, "App1", name_pat(self.app)))
        for table in (self.mods, self.ents, self.docs, self.attrs):
            for n, tok in table.items():
                self.matchers.append((n, tok, name_pat(n)))
        for u in self.users:
            self.matchers.append((u, "<user>", name_pat(u)))
        for h in self.hosts:
            self.matchers.append((h, "<host>", name_pat(h)))
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
        t = RE_AUTH.sub(lambda m: m.group(1) + m.group(2) + "<redacted>", t)
        t = RE_HDR.sub(lambda m: m.group(1) + "<redacted>", t)
        t = RE_KV.sub(lambda m: m.group(1) + m.group(2) + m.group(1) + m.group(3) + "<redacted>", t)
        t = RE_FLAG.sub(lambda m: m.group(1) + m.group(2) + "<redacted>", t)
        t = RE_HEXTOK.sub(lambda m: hold(m.group(0)) if hex_ok(t, m) else "<token>", t)
        t = RE_EMAIL.sub("<email>", t)
        t = RE_URL.sub(lambda m: hold(url_clean(m.group(0))) if url_clean(m.group(0)) != "<url>" else "<url>", t)
        t = RE_PATH.sub("<path>", t)
        def bare(m):
            if split_allowed(m.group(0)):
                return hold(split_allowed(m.group(0))[0])
            if m.group("tld").lower() in FILE_EXT:
                return m.group(0)
            c = code_form(m, self.deny)
            return "<host>" if c is None else c
        t = RE_BARE.sub(bare, t)
        t = RE_IP6.sub(lambda m: "<ip>" if ip6_ok(m.group(0)) else m.group(0), t)
        t = RE_IP4.sub(lambda m: m.group(0) if RE_VERCTX.search(t[max(0, m.start() - 24):m.start()]) else "<ip>", t)
        for rx in self.deny:
            t = rx.sub("<redacted>", t)
        t = protect(t, hold)
        for m, pm in sorted(self.mods.items(), key=lambda x: -len(x[0])):
            def qual(mm, pm=pm):
                low = mm.group(1).lower()
                for tbl in (self.ents, self.docs):
                    for k, v in tbl.items():
                        if k.lower() == low:
                            return pm + "." + v
                self.docs[mm.group(1)] = "Doc%d" % (len(self.docs) + 1)
                return pm + "." + self.docs[mm.group(1)]
            t = re.sub(r"(?<![A-Za-z0-9])" + name_pat(m) + r"\.(\w+)", qual, t)
        for rx, tok in self.mrx:
            t = rx.sub(tok, t)
        return re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], t)

    def scan(self, text):
        """Return a list of reasons text still looks unsafe (empty = clean)."""
        t0 = norm(text)
        bad = []
        for m in RE_URL.finditer(t0):
            if not url_safe(m.group(0)):
                bad.append("URL " + m.group(0)[:40])
        tm = mask_ok(t0)
        t = tm
        for m in RE_AUTH.finditer(t):
            bad.append("authorization header")
        for m in RE_HDR.finditer(t):
            bad.append("secret header " + m.group(1).strip()[:20])
        for label, rx in (("home path", RE_PATH), ("email", RE_EMAIL), ("token", RE_TOKENS), ("private key", RE_PRIVKEY)):
            if rx.search(t):
                bad.append(label)
        if ip4_hits(t):
            bad.append("IP address")
        if any(ip6_ok(m.group(0)) for m in RE_IP6.finditer(t)):
            bad.append("IPv6 address")
        for m in RE_BARE.finditer(t):
            if m.group("tld").lower() not in FILE_EXT and not url_ok(m.group(0)) and code_form(m, self.deny) is None:
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
            t = protect(t, lambda s: "\x01")
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


RE_DESCRIBE = re.compile(r"\bv?\d+(?:\.\d+){1,3}-\d+-g[0-9a-f]{7,12}\b")
RE_SHA = re.compile(r"(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])")


def toolkit_version(project):
    """The toolkit a bug was seen on, when the row has none (#646): PROJECT.md's `Toolkit commit:`
    line (the session-start ritual keeps it fresh), else git describe of this toolkit clone, marked
    (at filing). A sha is cut to 12 characters: a full 40-hex one reads as an opaque token to the scan."""
    pm = os.path.join(project, "PROJECT.md")
    if os.path.isfile(pm):
        for ln in open(pm, errors="replace"):
            m = re.match(r"(?i)^[\s*>-]*toolkit commit\s*\**\s*:\s*\**\s*`?([0-9a-f]{7,40})\b", ln)
            if m:
                return m.group(1)[:12]
    d = sh(["git", "-C", TOOLKIT_ROOT, "describe", "--tags", "--always"]).stdout.strip()
    return (d + " (at filing)") if d else ""


def versions_line(vers, project=None):
    """Only version-shaped strings, taken from the row and never run through redact(). A toolkit
    value may also be git-describe output or a commit sha; a row without one gets toolkit_version()."""
    vers = dict(vers) if isinstance(vers, dict) else ({"version": vers} if vers else {})
    out, has_tk = [], False
    for k, v in vers.items():
        v = str(v or "")
        m = RE_DESCRIBE.search(v) or RE_VER.search(v)
        if not m and str(k) == "toolkit":
            m = RE_SHA.search(v)
        k = re.sub(r"[^A-Za-z0-9 _-]", "", str(k))[:16]
        if m and k:
            val = m.group(0)[:12] if RE_SHA.fullmatch(m.group(0)) else m.group(0)
            out.append("%s %s" % (k, val))
            has_tk = has_tk or k == "toolkit"
    if not has_tk and project is not None:
        tv = toolkit_version(project)
        m = tv and (RE_DESCRIBE.match(tv) or RE_VER.match(tv) or RE_SHA.match(tv))
        if m:
            val = m.group(0)[:12] if RE_SHA.fullmatch(m.group(0)) else m.group(0)
            out.append("toolkit " + val + (" (at filing)" if tv.endswith("(at filing)") else ""))
    return ", ".join(out) or "not recorded"


def build(r, b):
    """Return (title, body, problems) for one bug, redacted and scanned."""
    parts = ["### Steps to reproduce\n" + (text_of(b.get("repro")) or "-"),
             "### Expected\n" + (text_of(b.get("expected")) or "-"), "### Actual\n" + (text_of(b.get("actual")) or "-")]
    if b.get("workaround"):
        parts.append("### Workaround\n" + text_of(b["workaround"]))
    title = re.sub(r"\s+", " ", r.redact(str(b.get("title", ""))))
    body = "**Versions:** " + versions_line(b.get("versions"), r.project) + "\n\n" + r.redact("\n\n".join(parts))
    if b.get("log"):
        # redacted and scanned on its own: a log that fails is left out, never posted, and never
        # sinks the rest of the report
        lg = r.redact(str(b["log"]))[-LOG_CHARS:]
        if r.scan(lg):
            body += "\n\n### Log\n(left out: it did not pass the redaction scan)"
        else:
            body += "\n\n### Log (last lines, redacted)\n" + FENCE + "\n" + lg.replace(FENCE, "'" * 3) + "\n" + FENCE
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


def gh_bin():
    """The gh to run: $MXTK_GH, else gh, else gh.exe (Git Bash/Windows: Python does not map a bare
    name to .exe the way MSYS does). None when there is no gh at all."""
    env = os.environ.get("MXTK_GH")
    if env:
        return shutil.which(env) or (env if os.path.isfile(env) else None)
    return shutil.which("gh") or shutil.which("gh.exe")


def dupes(repo, title):
    """Called only with a redacted title that passed the final scan."""
    gh = gh_bin()
    if not gh or sh([gh, "--version"]).returncode != 0:
        return None
    q = " ".join(re.findall(r"[A-Za-z0-9_]{3,}", title)[:8])
    p = sh([gh, "issue", "list", "--repo", repo, "--state", "all", "--search", q + " in:title", "--limit", "5",
            "--json", "number,title,state,url"])
    if p.returncode != 0:
        p = sh([gh, "search", "issues", "--repo", repo, q, "--limit", "5", "--json", "number,title,state,url"])
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
    if a.log:
        lg, why = log_tail(Redactor(os.path.dirname(os.path.dirname(path)), a.name), a.log, a.log_lines)
        if lg is None:
            print("file-bugs: the log was NOT attached: %s. Describe what it showed in --actual instead." % why)
        else:
            row["log"] = lg
            print("file-bugs: attached the last %d line(s) of the log, redacted" % len(lg.splitlines()))
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


def gh_create(repo, title, body, label=None):
    fd, bf = tempfile.mkstemp(prefix="file-bugs-body.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(body)
        cmd = [gh_bin() or "gh", "issue", "create", "--repo=" + repo, "--title=" + title, "--body-file=" + bf]
        return sh(cmd + (["--label=" + label] if label else []))
    finally:
        try:
            os.unlink(bf)
        except OSError:
            pass


def optin_in(txt):
    """RE_OPTIN outside HTML comments and fenced code blocks (``` or ~~~): a quoted example or the
    commented template line is not the person's decision."""
    txt = re.sub(r"(?s)<!--.*?(?:-->|$)", "", txt)
    txt = re.sub(r"(?ms)^[ \t]*(`{3,}|~{3,}).*?(?:^[ \t]*\1[ \t]*$|\Z)", "", txt)
    return bool(RE_OPTIN.search(txt.replace("*", "").replace("`", "")))


def opted_in(project):
    """(True, "<sha> <date>") when PROJECT.md carries `Bug filing: auto` in the working copy AND in
    the committed HEAD (git show HEAD:./PROJECT.md), with the commit that last changed that line.
    An uncommitted line, or no git repo, is (False, why): an agent can edit a file, a commit is a
    visible, attributable record."""
    try:
        txt = open(os.path.join(project, "PROJECT.md"), errors="replace").read()
    except OSError:
        return False, "there is no PROJECT.md"
    if not optin_in(txt):
        return False, "PROJECT.md has no line `Bug filing: auto`"
    head = sh(["git", "-C", project, "show", "HEAD:./PROJECT.md"])
    if head.returncode != 0:
        return False, "PROJECT.md is not in a git commit here (no repo, or never committed)"
    if not optin_in(head.stdout):
        return False, "the `Bug filing: auto` line is not committed yet (commit PROJECT.md to opt in)"
    lg = sh(["git", "-C", project, "log", "-1", "-i", "-G", "bug filing", "--format=%h %ad", "--date=short", "--", "PROJECT.md"])
    return True, (lg.stdout.strip() or "unknown commit")


def gh_ready():
    """(gh path, None) when gh is installed and signed in, else (None, why)."""
    gh = gh_bin()
    if not gh:
        return None, "gh is not installed"
    if sh([gh, "auth", "status"]).returncode != 0:
        return None, "gh is installed but not signed in (`gh auth login`)"
    return gh, None


def auto_label(gh, repo, cache):
    """The auto-filed label when the repo has it, or when this user may create it (WRITE or more);
    otherwise None and the issue is filed without a label."""
    if repo in cache:
        return cache[repo]
    have = False
    p = sh([gh, "label", "list", "--repo", repo, "--search", AUTO_LABEL, "--limit", "50", "--json", "name"])
    if p.returncode == 0:
        try:
            have = any(str(x.get("name", "")).lower() == AUTO_LABEL for x in json.loads(p.stdout or "[]"))
        except (ValueError, AttributeError):
            have = False
    if not have:
        v = sh([gh, "repo", "view", repo, "--json", "viewerPermission", "--jq", ".viewerPermission"])
        if v.returncode == 0 and v.stdout.strip().upper() in ("ADMIN", "MAINTAIN", "WRITE"):
            have = sh([gh, "label", "create", AUTO_LABEL, "--repo", repo, "--color", "BFD4F2",
                       "--description", "Filed by an agent with bin/file-bugs.sh --auto"]).returncode == 0
    cache[repo] = AUTO_LABEL if have else None
    return cache[repo]


def log_tail(r, path, n):
    """The last n lines of a log, redacted: (text, None), or (None, why it was dropped)."""
    try:
        lines = open(path, errors="replace").read().splitlines()[-max(1, n):]
    except OSError as e:
        return None, "cannot read it (%s)" % e.strerror
    red = r.redact("\n".join(lines))[-LOG_CHARS:]
    bad = r.scan(red)
    return (None, "after redaction it still looks unsafe (%s)" % ", ".join(bad)) if bad else (red, None)


NODENY_MSG = ("no deny list, so client names outside the project files cannot be caught. Add one: one regex per line "
              "in <project>/.leakguard-deny (the names this project must never publish), or set LEAKGUARD_DENY='Foo|Bar'. "
              "Client names of 4 characters or fewer match as whole words only, so list them there too.")
REFUSED_NOTE = "refused: run the dry run to see why"


def main():
    ap = argparse.ArgumentParser(prog="file-bugs.sh", add_help=True, allow_abbrev=False, formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Per-project bug log (docs/bugs.jsonl) and a redacted way to file it to mendixlabs/mxcli or the toolkit repo.",
        epilog="Posting (--file, --all) is for a human: run it yourself with `!bin/file-bugs.sh --file PBUG-NN`. "
               "No script can tell a person from an agent driving a pty, so the shipped Claude Code permissions "
               "deny `file-bugs.sh --file` and `--all`. Dry run, --links and --json post nothing; all three, and "
               "posting, need a deny list (<project>/.leakguard-deny or $LEAKGUARD_DENY). --auto is the one way an "
               "agent posts: only in a project whose PROJECT.md has the line `Bug filing: auto` (the person's "
               "decision), every open row that passes the scan, with the person's own gh login, no y/N; without "
               "that line it is a dry run. No gh or not signed in: it prints the --links instead and exits 0.")
    ap.add_argument("--project", default=".")
    ap.add_argument("--file", action="append", default=[], metavar="PBUG-NN")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--auto", action="store_true", help="post every open row that passes the scan, no y/N; only when "
                    "PROJECT.md says `Bug filing: auto`, otherwise a dry run")
    ap.add_argument("--links", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--name", action="append", default=[], help="extra project name to redact")
    ap.add_argument("--to", choices=sorted(TARGETS), help="file to this repo instead of the row's target: a finding that is "
                    "really both is two submissions (skills/upstream-feedback.md). The row keeps its target and status; "
                    "the issue URL is recorded under also.<repo>")
    ap.add_argument("--add", action="store_true")
    ap.add_argument("--log", metavar="FILE", help="with --add: attach the last --log-lines lines of FILE, redacted; "
                    "a log that still looks unsafe after redaction is dropped, never stored or posted")
    ap.add_argument("--log-lines", type=int, default=LOG_LINES, metavar="N")
    for k in ("target", "title", "repro", "expected", "actual", "workaround", "mxcli", "mendix", "toolkit-version"):
        ap.add_argument("--" + k)
    a = ap.parse_args()
    if a.log and not a.add:
        sys.exit("file-bugs: --log goes with --add")
    if a.auto and (a.all or a.links or a.json or a.add or a.to):
        sys.exit("file-bugs: --auto cannot be combined with --all, --links, --json, --add or --to "
                 "(a second submission to the other repo is a human's call)")
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
    also = lambda d: bool(a.to) and a.to != d.get("target")   # a second submission, to the other repo
    todo = [(i, d) for i, d in rows if (d.get("status", "open") == "open" or (also(d) and d.get("status") == "filed"))
            and not (also(d) and (d.get("also") or {}).get(a.to)) and (not want or sid(d) in want)]
    for w in want:
        if not any(sid(d) == w for _, d in rows):
            sys.exit("file-bugs: %s is not in %s" % (w, path))
        if not any(sid(d) == w for _, d in todo):
            sys.stderr.write("file-bugs: %s is not open, skipped\n" % w)
    auto_off = False
    if a.auto:
        ok, info = opted_in(project)
        auto_off = not ok
        if ok:
            print("Bug filing: auto -- opted in by commit %s (PROJECT.md)\n" % info)
            # --to is refused above; never re-post a row that is not open
            todo = [(i, d) for i, d in todo if d.get("status", "open") == "open"]
        else:
            print("NOTE: --auto is off for this project: %s, so this is a dry run and nothing is posted. Only the "
                  "person decides that line, in a commit; until then a human files with "
                  "`!bin/file-bugs.sh --file PBUG-NN`.\n" % info)
            a.auto = False
    posting = bool(want or a.all or a.auto) and not (a.links or a.json or auto_off)
    tty = None
    r = Redactor(project, a.name)
    for w in r.warnings:
        sys.stderr.write("file-bugs: warning: %s\n" % w)
    if r.bad_deny:
        msg = ("invalid deny pattern (%s): fix it in the deny list. Posting, --links and --json are refused "
               "until then; nothing posted." % "; ".join(r.bad_deny))
        if posting or a.links or a.json:
            sys.exit("file-bugs: " + msg)
        print("NOTE: " + msg + "\n")
    nodeny = not r.own_deny and not r.bad_deny
    if nodeny:
        if posting or a.links or a.json:
            sys.exit("file-bugs: " + NODENY_MSG + " Posting, --links and --json are refused until then; nothing posted.")
        print("NOTE: " + NODENY_MSG + " Posting, --links and --json are refused until then.\n")
    gh, labels, tally = None, {}, {"filed": 0, "refused": 0, "held": 0}
    if a.auto:
        gh, why = gh_ready()
        if not gh:
            # never a failure: the rows stay open with their workarounds; links let anyone file them
            print("NOTE: --auto cannot post: %s. Nothing posted; here are the pre-filled links instead "
                  "(anyone with a GitHub account can open one):\n" % why)
            a.auto, a.links, posting = False, True, False
    elif posting:
        tty = tty_open()
        if tty is None:
            sys.exit("file-bugs: posting needs an interactive terminal (/dev/tty, y/N per bug); nothing posted")
    out = []
    for _, d in todo:
        target = d.get("target")
        repo = TARGETS.get(target) if isinstance(target, str) else None
        if repo and a.to: repo = TARGETS[a.to]
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
            tally["refused"] += 1
            continue
        dp = dupes(repo, title)
        if dp is None:
            print("Duplicates: search unavailable (gh missing or not authenticated)")
            if posting:
                print("Nothing breaks: the bug stays open in docs/bugs.jsonl with its workaround. To file it later, install gh and run "
                      "`gh auth login`, or print a pre-filled link for someone with a GitHub account: file-bugs.sh --links " + sid(d))
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
            tally["held"] += 1
            continue
        label = None
        if a.auto:
            same = [x for x in dp if re.sub(r"\s+", " ", str(x.get("title", ""))).strip().lower() == title.strip().lower()]
            if same and re.match(r"https://github\.com/%s/issues/\d+$" % re.escape(repo), str(same[0].get("url", ""))):
                # the same title is already there: record it instead of opening a second issue
                if also(d): write_back(path, sid(d), {"also": dict(d.get("also") or {}, **{a.to: same[0]["url"]})})
                else: write_back(path, sid(d), {"status": "filed", "issue_url": same[0]["url"], "duplicate": True})
                print("Not posting: #%s has the same title; recorded it as this bug's issue." % same[0].get("number"))
                tally["held"] += 1
                continue
            rel = [x.get("number") for x in dp if str(x.get("number", "")).isdigit()]
            body += "\n\n---\nFiled by the reporter's agent with `bin/file-bugs.sh --auto` (redacted before posting)."
            if rel:
                body += " Possibly related: " + ", ".join("#%s" % n for n in rel) + "."
            again = r.scan(title + "\n" + body)
            if again:
                print("WARNING: the filing footer failed the scan (%s); not posting." % ", ".join(again))
                tally["refused"] += 1
                continue
            label = auto_label(gh, repo, labels)
        elif not confirm(tty, repo):
            print("skipped.")
            continue
        p = gh_create(repo, title, body, label)
        if label and p.returncode != 0:
            p = gh_create(repo, title, body)   # a label this user may not apply never blocks the report
        m = re.search(r"https://github\.com/%s/issues/\d+" % re.escape(repo), p.stdout or "")
        if p.returncode != 0 or not m:
            print("gh issue create failed: " + (p.stderr or p.stdout).strip()[:300])
            tally["held"] += 1
            continue
        tally["filed"] += 1
        if also(d): write_back(path, sid(d), {"also": dict(d.get("also") or {}, **{a.to: m.group(0)})})
        else: write_back(path, sid(d), {"status": "filed", "issue_url": m.group(0)})
        print("filed: " + m.group(0))
    if a.json:
        print(json.dumps(out, indent=2, ensure_ascii=False))
    elif not out and not a.links:
        print("file-bugs: no open bugs")
    if a.auto and out:
        print("\nfile-bugs --auto: %d filed, %d refused by the redaction scan (never posted: run the dry run, fix the row), "
              "%d not posted (duplicate recorded, search unavailable or gh failed)" % (tally["filed"], tally["refused"], tally["held"]))


if __name__ == "__main__":
    main()
