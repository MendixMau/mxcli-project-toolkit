"""Shared helpers for the brain-kit pipeline: config, model calls with cost tracking and a budget cap, note parsing.

Every script reads one config file (brain.yaml, path in BRAINKIT_CONFIG or --config). Paths in it are relative to the config file.
Model calls run through headless Claude Code (`claude -p`, default) or the Anthropic SDK (backend: api; ANTHROPIC_API_KEY and ANTHROPIC_BASE_URL work as usual).
JSON answers are prompted and parsed, never forced through tool_choice: several gateways reject forced tools or structured outputs.
"""
import json, os, re, shutil, subprocess, threading, time
from pathlib import Path
import yaml

KINDS = {"practice", "procedure", "pitfall", "decision", "reference"}
PRICE = {"haiku": (1, 5), "sonnet": (3, 15), "opus": (5, 25)}  # USD per million tokens, in / out; matched on the model id


# ---------- config ----------

class Config:
    def __init__(self, path):
        self.path = Path(path).resolve()
        self.root = self.path.parent
        self.d = yaml.safe_load(self.path.read_text()) or {}

    def p(self, key, default):
        return (self.root / self.d.get("paths", {}).get(key, default)).resolve()

    @property
    def brain(self): return self.p("brain", "brain")
    @property
    def work(self): return self.p("work", "work")  # ingest, classified, shortlists: raw material, never committed to the brain
    @property
    def topics(self): return self.d.get("topics", {})
    @property
    def applies_to(self): return self.d.get("applies_to", ["general", "company-standard"])
    @property
    def models(self):
        m = {"cheap": "claude-haiku-4-5", "judge": "claude-sonnet-5-5", "writer": "claude-opus-5-5"}
        m.update(self.d.get("models", {}))
        return m
    @property
    def deny(self):
        """Regex of names that must never appear in a note (customers, people, hosts). Empty = no name check."""
        names = self.d.get("deny_names", [])
        return re.compile(r"\b(" + "|".join(map(re.escape, names)) + r")\b", re.I) if names else None
    @property
    def deny_terms(self):
        terms = self.d.get("deny_terms", [])
        return re.compile(r"\b(" + "|".join(map(re.escape, terms)) + r")\b", re.I) if terms else None
    @property
    def audience(self): return self.d.get("audience", "developers and coding agents")
    @property
    def novelty(self):
        return self.d.get("novelty_rule", "Keep only what a strong LLM would not already know from public documentation: internal "
                                          "procedures, measured results, pitfalls, local rules, version-bound gotchas.")
    @property
    def thresholds(self):
        t = {"faith": 0.90, "find": 0.80}; t.update(self.d.get("thresholds", {})); return t
    @property
    def budget(self): return float(os.environ.get("BRAINKIT_BUDGET", self.d.get("budget_usd", 10)))


def load_config(arg=None, brain=None):
    """--config wins; else BRAINKIT_CONFIG; else brain.yaml in the brain (or current) folder; else defaults around --brain.
    A hand-built brain needs no config at all: `gate.py --brain ~/my-brain --checks lint,find`."""
    for c in (arg, os.environ.get("BRAINKIT_CONFIG"), str(Path(brain or ".") / "brain.yaml")):
        if c and Path(c).exists():
            cfg = Config(c)
            if brain: cfg.d.setdefault("paths", {})["brain"] = str(Path(brain).resolve())
            return cfg
    if arg: raise SystemExit(f"config not found: {arg}")
    if not brain: raise SystemExit("no brain.yaml here: pass --config <brain.yaml> or --brain <brain folder>")
    b = Path(brain).resolve()
    cfg = Config.__new__(Config)
    cfg.path, cfg.root = b / "brain.yaml", b
    cfg.d = {"paths": {"brain": str(b), "work": str(b / "_work")},
             "topics": {p.name: p.name for p in sorted((b / "internal").glob("*")) if p.is_dir() and not p.name.startswith("_")}}
    return cfg


# ---------- model calls ----------

class Budget(Exception): pass


class Msg:
    """The two fields callers read from a response, for the claude-code backend."""
    def __init__(self, stop_reason, usage): self.stop_reason, self.usage = stop_reason, usage


class LLM:
    """Thin wrapper: retries, cost tracking per run, and a hard stop when the run's spend passes the budget.

    Two backends (brain.yaml `backend:` or BRAINKIT_BACKEND):
      claude-code (default)  runs `claude -p` headless, so it uses whatever login Claude Code has: no API key needed.
      api                    the Anthropic SDK with ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL (a company gateway).
    """
    def __init__(self, cfg):
        self.cfg, self.lock, self.usage, self.usd = cfg, threading.Lock(), {}, 0.0
        self.backend = os.environ.get("BRAINKIT_BACKEND") or cfg.d.get("backend", "claude-code")
        if self.backend == "api":
            import anthropic
            self.client = anthropic.Anthropic(max_retries=6, timeout=1800)
        elif not shutil.which("claude"):
            raise SystemExit("backend claude-code needs the `claude` CLI on PATH (or set backend: api)")

    def model(self, role):
        """brain.yaml models: wins; otherwise the claude-code backend uses the CLI's aliases (haiku / sonnet / opus = latest)."""
        if self.backend == "claude-code" and role not in self.cfg.d.get("models", {}):
            return {"cheap": "haiku", "judge": "sonnet", "writer": "opus"}[role]
        return self.cfg.models[role]

    def track(self, model, u, usd=None):
        with self.lock:
            t = self.usage.setdefault(model, [0, 0]); t[0] += u.input_tokens; t[1] += u.output_tokens
            if usd is None:
                pin, pout = next((v for k, v in PRICE.items() if k in model.lower()), PRICE["sonnet"])
                usd = u.input_tokens / 1e6 * pin + u.output_tokens / 1e6 * pout
            self.usd += usd
            if self.usd > self.cfg.budget: raise Budget(f"budget ${self.cfg.budget} passed (${self.usd:.2f})")

    def cost(self): return self.usd

    def claude(self, model, system, user, tools="", cwd=None, max_turns=None, timeout=1800, schema=None):
        """One headless Claude Code run. Returns (result text, the parsed JSON envelope). Tracks the cost it reports.
        schema: a JSON Schema; the envelope's structured_output then holds the validated answer."""
        cmd = ["claude", "-p", "--model", model, "--output-format", "json", "--system-prompt", system, "--tools", tools,
               "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config"]
        if schema: cmd += ["--json-schema", json.dumps(schema)]
        if tools: cmd += ["--allowedTools", tools]
        if max_turns: cmd += ["--max-turns", str(max_turns)]
        r = subprocess.run(cmd, input=user, capture_output=True, text=True, cwd=cwd, timeout=timeout)
        try: env = json.loads(r.stdout)
        except json.JSONDecodeError: raise RuntimeError(f"claude -p failed ({r.returncode}): {(r.stderr or r.stdout)[:300]}")
        u = env.get("usage") or {}
        tok = type("U", (), {"input_tokens": u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0),
                             "output_tokens": u.get("output_tokens", 0)})
        self.track(model, tok, env.get("total_cost_usd", 0.0))
        if env.get("is_error") and env.get("subtype") != "error_max_turns": raise RuntimeError(f"claude -p error: {str(env.get('result'))[:300]}")
        return env.get("result") or "", env

    def text(self, role, system, user, max_tokens=4000, tries=3):
        """One call, text answer. Long outputs stream (a gateway may drop a long non-streamed response)."""
        model = self.model(role)
        if self.backend == "claude-code":
            for k in range(tries):
                try:
                    t, env = self.claude(model, system, user)
                    return t, Msg(env.get("stop_reason"), None)
                except Budget: raise
                except Exception as e:
                    if k == tries - 1: raise
                    print(f"  call failed ({str(e)[:160]}), retry {k + 1}", flush=True); time.sleep(10 * (k + 1))
        for k in range(tries):
            try:
                with self.client.messages.stream(model=model, max_tokens=max_tokens, system=system,
                                                 messages=[{"role": "user", "content": user}]) as s:
                    msg = s.get_final_message()
                self.track(model, msg.usage)
                return "".join(b.text for b in msg.content if b.type == "text"), msg
            except Budget: raise
            except Exception as e:
                if k == tries - 1: raise
                print(f"  call failed ({type(e).__name__}: {str(e)[:120]}), retry {k + 1}", flush=True); time.sleep(10 * (k + 1))

    def json(self, role, system, user, max_tokens=4000):
        """Ask for one JSON object; parse it out of the answer. Retries once with the parse error."""
        sys2 = system + "\n\nAnswer with ONE JSON object only. No prose before or after it, no code fence."
        t, _ = self.text(role, sys2, user, max_tokens)
        try: return parse_json(t)
        except ValueError as e:
            t, _ = self.text(role, sys2, user + f"\n\nYour previous answer did not parse ({e}). Answer with one JSON object only.", max_tokens)
            return parse_json(t)


def parse_json(t):
    t = t.strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t)
    i, j = t.find("{"), t.rfind("}")
    if i < 0 or j < i: raise ValueError("no JSON object in the answer")
    try: return json.loads(t[i:j + 1])
    except json.JSONDecodeError as e: raise ValueError(str(e))


# ---------- notes ----------

def parse_note(p):
    t = Path(p).read_text()
    m = re.match(r"---\n(.*?)\n---\n(.*)", t, re.S)
    if not m: return None, t
    try: return yaml.safe_load(m.group(1)) or {}, m.group(2)
    except Exception as e: return {"_yaml_error": str(e)}, m.group(2)


def notes(brain, topic=None):
    """Note files: internal/<topic>/<slug>.md, never INDEX.md or _-prefixed work files."""
    pat = f"{topic}/[a-z0-9]*.md" if topic else "*/[a-z0-9]*.md"
    return [p for p in sorted((brain / "internal").glob(pat)) if p.name != "INDEX.md"]


def safe_frontmatter(note):
    """Repair model quoting that makes frontmatter unparsable: re-quote the title, rewrite keywords as a JSON list."""
    m = re.match(r"---\n(.*?)\n---\n", note, re.S)
    if not m: return note
    try: yaml.safe_load(m.group(1)); return note
    except Exception: pass
    fm = m.group(1)
    def kw(mt):
        items = [x.strip().strip("'\"") for x in mt.group(1).strip().strip("[]").split(",")]
        return "keywords: " + json.dumps([x for x in items if x], ensure_ascii=False)
    fm = re.sub(r"^keywords: (.*)$", kw, fm, count=1, flags=re.M)
    try: yaml.safe_load(fm)
    except Exception:
        fm = re.sub(r"^title: (.*)$", lambda mt: "title: '" + mt.group(1).strip().strip("'\"").replace("'", "''") + "'", fm, count=1, flags=re.M)
    return "---\n" + fm + "\n---\n" + note[m.end():]


# ---------- ingested sources ----------

def read_doc(p):
    """An ingested source file: frontmatter (id, title, url, source, author, modified) + text."""
    fm, body = parse_note(p)
    return fm or {}, body


_idx = None
def source_index(cfg):
    """url -> path and normalised title -> [paths] over work/ingest, for resolving a note's cited sources."""
    global _idx
    if _idx is None:
        by_url, by_title = {}, {}
        for p in (cfg.work / "ingest").glob("*/*.md"):
            fm, _ = read_doc(p)
            if fm.get("url"): by_url[str(fm["url"]).rstrip("/")] = p
            if fm.get("title"): by_title.setdefault(norm_title(str(fm["title"])), []).append(p)
        _idx = (by_url, by_title)
    return _idx


def norm_title(s):
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def resolve_sources(cfg, fm, limit=60000):
    """The text of every source a note cites, matched by url, then by exact title. Returns ([(name, text)], [unresolved])."""
    by_url, by_title = source_index(cfg)
    texts, unresolved = [], []
    for src in fm.get("sources") or []:
        if not isinstance(src, dict): continue
        url, title = str(src.get("url") or "").rstrip("/"), str(src.get("title") or "")
        p = by_url.get(url) or by_url.get(url.split("#")[0])
        cands = [p] if p else by_title.get(norm_title(title), [])[:3]
        if not cands: unresolved.append(title or url); continue
        for c in cands: texts.append((c.name, c.read_text()[:limit // len(cands)]))
    return texts, unresolved


def log_cost(cfg, step, llm, extra=None):
    """Append one line per pipeline step to work/costs.jsonl, so a run's spend is visible afterwards."""
    cfg.work.mkdir(parents=True, exist_ok=True)
    row = {"date": time.strftime("%Y-%m-%d %H:%M"), "step": step, "usd": round(llm.cost(), 3), "tokens": llm.usage, **(extra or {})}
    with open(cfg.work / "costs.jsonl", "a") as f: f.write(json.dumps(row) + "\n")
    print(f"{step}: ~${llm.cost():.2f}")
