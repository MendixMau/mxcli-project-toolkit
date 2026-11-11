#!/usr/bin/env python3
"""Step 8, the quality gate: lint, faithfulness and findability for one topic (or all).

Usage:
  python3 bin/gate.py --topic security [--config brain.yaml] [--checks lint,faith,find] [--workers 6] [--limit N]
  python3 bin/gate.py --brain ~/my-brain --checks lint,find        # a hand-built brain, no pipeline, no config

lint   (free)   frontmatter complete and parsable, kind and applies_to valid, sources present, 40 to 650 words, [[links]] resolve,
                no denied names or terms (brain.yaml deny_names / deny_terms).
faith  (judge)  a second model lists every factual claim in the note and checks it against the note's own cited sources
                (resolved back to work/ingest by url or title). Pass = zero unsupported claims and no denied name. Needs the pipeline's ingest.
find   (cheap)  a model writes the question a reader in this situation would ask, in their words; a search agent with ONLY grep and
                read over the brain, following the brain's AGENTS.md, must return the note in its top 3 (hit@3).
Output: brain/internal/<topic>/_gate.json and _gate.md. Exit 1 when a threshold fails, 2 when the find harness itself broke.

Read find results carefully: a harness error (no answer, call cap hit, API error) says nothing about the brain and is never scored
as a miss. In our first build, every early "low findability" score turned out to be a harness bug.
"""
import argparse, hashlib, json, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from lib import KINDS, LLM, load_config, log_cost, notes, parse_json, parse_note, resolve_sources

REQUIRED = ("title", "topic", "kind", "applies_to", "versions", "sources", "status")
MAX_CALLS = 8


# ---------- lint ----------

def lint(cfg, topic):
    out, slugs = [], {p.stem for p in notes(cfg.brain)}
    deny, terms = cfg.deny, cfg.deny_terms
    for p in notes(cfg.brain, topic):
        fm, body = parse_note(p); s, t = p.stem, p.read_text()
        if fm is None or "_yaml_error" in fm:
            out.append((s, "error", f"frontmatter unparsable {(fm or {}).get('_yaml_error', '')}"[:200])); continue
        out += [(s, "error", f"missing {k}") for k in REQUIRED if k not in fm]
        if fm.get("kind") not in KINDS: out.append((s, "error", f"kind {fm.get('kind')}"))
        if fm.get("applies_to") not in cfg.applies_to: out.append((s, "error", f"applies_to {fm.get('applies_to')} not in {cfg.applies_to}"))
        srcs = fm.get("sources") or []
        if not srcs: out.append((s, "error", "no sources"))
        out += [(s, "error", f"bad source entry {x}"[:120]) for x in srcs if not isinstance(x, dict) or not x.get("title")]
        if not fm.get("keywords"): out.append((s, "warn", "no keywords"))
        w = len(body.split())
        if w < 40 or w > 650: out.append((s, "warn", f"body {w} words"))
        out += [(s, "warn", f"dangling link [[{l}]]") for l in set(re.findall(r"\[\[([^\]|]+)\]\]", body)) if l not in slugs]
        if deny: out += [(s, "error", f"denied name {h}") for h in {m.group(0) for m in deny.finditer(t)}]
        if terms: out += [(s, "error", f"denied term {h}") for h in {m.group(0) for m in terms.finditer(body)}]
    return out


# ---------- faith ----------

FAITH = """You audit one note of a company knowledge base against its source documents.
List every factual claim in the note (steps, numbers, versions, causes, fixes, names of settings and APIs, rules, and the certainty its
Status line states). For each claim decide: supported (the sources state it), partial (close, but the note adds or changes detail),
unsupported (not in the sources), or general (connective common knowledge, not a claim that matters).
Do not audit [[slug]] links, the frontmatter fields, or the note's remarks about its own sources.
leak: exact quotes FROM THE NOTE that name a customer or a private person, or expose credentials, hosts or record data. [] when clean.
JSON: {"claims": [{"claim": "...", "verdict": "supported|partial|unsupported|general", "evidence": "short quote or why"}], "leak": []}"""


def faith_one(llm, cfg, p):
    fm, _ = parse_note(p)
    if not fm or "_yaml_error" in fm: return {"slug": p.stem, "error": "frontmatter"}
    texts, unresolved = resolve_sources(cfg, fm)
    if not texts: return {"slug": p.stem, "error": "no resolvable sources", "unresolved": unresolved}
    src = "\n\n".join(f"### SOURCE {n}\n{t}" for n, t in texts)
    try:
        d = llm.json("judge", FAITH, f"## NOTE\n{p.read_text()}\n\n## SOURCES\n{src}", 8000)
    except Exception as e:
        return {"slug": p.stem, "error": str(e)[:200]}
    c = d.get("claims") or []
    n = {v: sum(1 for x in c if x.get("verdict") == v) for v in ("supported", "partial", "unsupported", "general")}
    low = p.read_text().lower()
    leak = [x for x in (d.get("leak") or []) if x and x.lower().strip(" '\"") in low]  # only quotes that really are in the note
    return {"slug": p.stem, **n, "unsupported_claims": [x["claim"] for x in c if x.get("verdict") == "unsupported"],
            "partial_claims": [x["claim"] for x in c if x.get("verdict") == "partial"], "leak": leak, "unresolved": unresolved,
            "pass": n["unsupported"] == 0 and not leak}


# ---------- find ----------

QUESTION = """You write a test question for a knowledge base search. Given one note, write ONE question a reader would type when they are
in the situation this note helps with. Describe the situation or symptom in their words. Do not reuse the note's title words, slug or
error codes unless a reader would naturally have them (an error message they see is fine). Answer with the question only."""

TOOLS = [
    {"name": "grep", "description": "Case-insensitive extended-regex search over all notes. Returns matching files ranked by hit count, with title and first hit.",
     "input_schema": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}},
    {"name": "read", "description": "Read one note or INDEX.md by the path grep returned (relative to internal/).",
     "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
    {"name": "answer", "description": "Final answer: the slugs (file names without .md) of the notes that help, best first, at most 3; [] if none fits.",
     "input_schema": {"type": "object", "properties": {"notes": {"type": "array", "items": {"type": "string"}}}, "required": ["notes"]}},
]


def searcher_system(cfg):
    agents = cfg.brain / "AGENTS.md"
    guide = agents.read_text() if agents.exists() else "(this brain has no AGENTS.md: that alone will hurt findability)"
    return ("You answer a reader's question by finding the right notes in a knowledge base. The repo's instructions follow.\n\n" + guide +
            f"\n\nYour tools work inside internal/: grep(pattern) and read(path). You have at most {MAX_CALLS} tool calls; every result says "
            "how many are left. Usually 2 to 4 are enough: stop when you have seen the matching note. Do not answer the question yourself: "
            "finish by calling answer(notes) with at most 3 slugs, best first, or [] if nothing fits. Never run out of calls without answering.")


def tool_grep(root, pattern):
    r = subprocess.run(["grep", "-rniE", "--include=*.md", "--exclude=INDEX.md", "--exclude=_*", "--exclude-dir=_*", pattern, "."],
                       cwd=root, capture_output=True, text=True, timeout=30)
    hits = {}
    for l in r.stdout.splitlines():
        path, _, rest = l[2:].partition(":")
        hits.setdefault(path, []).append(rest.partition(":")[2].strip())
    if not hits: return "no matches" + (f" ({r.stderr.strip()[:120]})" if r.stderr.strip() else "")
    out = [f"{len(hits)} files match"]
    for path, lines in sorted(hits.items(), key=lambda kv: -len(kv[1]))[:25]:
        title = next((x[7:] for x in lines if x.startswith("title: ")), "") or \
                (root / path).read_text()[:500].partition("title: ")[2].split("\n")[0]
        first = next((x for x in lines if not x.startswith("title: ")), "")
        out.append(f"{path} ({len(lines)}) {title[:100]} | {first[:120]}")
    return "\n".join(out)


def tool_read(root, path):
    path = path.strip().lstrip("./").removeprefix("internal/")
    p = (root / path).resolve()
    if not p.exists() and "/" not in path: p = next(iter(root.glob(f"*/{path.removesuffix('.md')}.md")), p)
    if root not in p.parents or not p.exists(): return "no such note"
    return p.read_text()[:8000]


def find_cc(llm, cfg, q, base, system):
    """claude-code backend: a real headless Claude Code session in internal/ with only Grep, Glob and Read."""
    sysm = system.replace("grep(pattern) and read(path)", "the Grep, Glob and Read tools (you are in internal/)").replace(
        "calling answer(notes) with at most 3 slugs, best first, or [] if nothing fits",
        'answering with ONE JSON object {"notes": ["<slug>", ...]}: at most 3 slugs (file names without .md), best first, [] if nothing fits')
    schema = {"type": "object", "properties": {"notes": {"type": "array", "maxItems": 3, "items": {"type": "string"}}}, "required": ["notes"]}
    try:
        t, env = llm.claude(llm.model("cheap"), sysm, q, tools="Grep,Glob,Read", cwd=cfg.brain / "internal",
                            max_turns=MAX_CALLS + 2, timeout=600, schema=schema)
    except Exception as e:
        return {**base, "question": q, "status": "harness_error", "reason": f"exception: {str(e)[:200]}"}
    if env.get("subtype") == "error_max_turns": return {**base, "question": q, "status": "harness_error", "reason": "turn cap hit without an answer"}
    out = env.get("structured_output")
    if out is None:
        try: out = parse_json(t)
        except ValueError: return {**base, "question": q, "status": "harness_error", "reason": f"answer not JSON: {t[:120]}"}
    # map each answer onto a real slug: a path, a slug with .md, or a slug inside a sentence all count as that slug
    slugs = {p.stem for p in notes(cfg.brain)}
    got = []
    for x in out.get("notes", []):
        s = Path(str(x).strip()).stem
        s = s if s in slugs else next((w for w in re.findall(r"[a-z0-9][a-z0-9-]{2,}", str(x)) if w in slugs), s)
        if s not in got: got.append(s)
    hit3 = base["slug"] in got[:3]
    return {**base, "question": q, "got": got, "hit1": got[:1] == [base["slug"]], "hit3": hit3, "status": "hit" if hit3 else "miss",
            "calls": env.get("num_turns")}


def find_one(llm, cfg, p, system):
    """status hit | miss | harness_error. Only hit and miss are scored."""
    base, root = {"slug": p.stem}, cfg.brain / "internal"
    model = llm.model("cheap")
    try:
        q = llm.text("cheap", QUESTION, p.read_text(), 300)[0].strip()
        if not q: return {**base, "status": "harness_error", "reason": "empty question"}
        if llm.backend == "claude-code": return find_cc(llm, cfg, q, base, system)
        msgs, calls, trace, choice = [{"role": "user", "content": q}], 0, [], {"type": "any"}
        for _ in range(MAX_CALLS + 3):
            forced = calls >= MAX_CALLS
            tc = {"type": "tool", "name": "answer"} if forced and choice else choice
            kw = {"tool_choice": tc} if tc else {}
            try:
                r = llm.client.messages.create(model=model, max_tokens=1500, system=system, tools=TOOLS, messages=msgs, **kw)
            except Exception as e:
                if choice and "tool_choice" in str(e):  # a gateway that rejects forced tools: fall back to auto
                    choice = None; continue
                raise
            llm.track(model, r.usage)
            msgs.append({"role": "assistant", "content": r.content})
            uses = [b for b in r.content if b.type == "tool_use"]
            trace.append([(b.name, json.dumps(b.input, ensure_ascii=False)[:120]) for b in uses])
            if not uses:
                if choice is None and not forced:
                    msgs.append({"role": "user", "content": "Use the tools, then call answer(notes)."}); continue
                return {**base, "question": q, "status": "harness_error", "reason": f"no tool call ({r.stop_reason})", "trace": trace}
            ans = next((b for b in uses if b.name == "answer"), None)
            if ans:
                got = [Path(x).stem for x in (ans.input.get("notes") or [])]
                if not got and forced: return {**base, "question": q, "status": "harness_error", "reason": "call cap hit, empty answer", "trace": trace}
                hit3 = p.stem in got[:3]
                return {**base, "question": q, "got": got, "hit1": got[:1] == [p.stem], "hit3": hit3,
                        "status": "hit" if hit3 else "miss", "calls": calls, "trace": trace}
            res = []
            for b in uses:
                calls += 1
                out = tool_grep(root, b.input.get("pattern", "")) if b.name == "grep" else tool_read(root, b.input.get("path", ""))
                left = max(0, MAX_CALLS - calls)
                res.append({"type": "tool_result", "tool_use_id": b.id, "content": out + f"\n[{left} tool calls left" + ("; call answer now]" if left == 0 else "]")})
            msgs.append({"role": "user", "content": res})
        return {**base, "question": q, "status": "harness_error", "reason": "loop ended without answer", "trace": trace}
    except Exception as e:
        return {**base, "status": "harness_error", "reason": f"exception: {str(e)[:200]}"}


# ---------- run ----------

def gate_topic(cfg, llm, topic, checks, workers, limit, no_cache):
    d = cfg.brain / "internal" / topic
    ns = notes(cfg.brain, topic)[: limit or None]
    res = {"topic": topic, "date": time.strftime("%Y-%m-%d %H:%M"), "notes": len(ns)}
    prev = json.loads((d / "_gate.json").read_text()) if (d / "_gate.json").exists() and not no_cache else {}
    if "lint" in checks: res["lint"] = [list(x) for x in lint(cfg, topic)]
    if "faith" in checks:  # reuse verdicts for notes whose text did not change since the last gate
        old = {f["slug"]: f for f in prev.get("faith", []) if f.get("hash") and "error" not in f}
        def cached(p):
            h = hashlib.sha1(p.read_bytes()).hexdigest()
            return old[p.stem] if old.get(p.stem, {}).get("hash") == h else {**faith_one(llm, cfg, p), "hash": h}
        with ThreadPoolExecutor(workers) as ex: res["faith"] = list(ex.map(cached, ns))
    elif prev.get("faith"): res["faith"] = prev["faith"]
    if "find" in checks:
        sysm = searcher_system(cfg)
        with ThreadPoolExecutor(workers) as ex: res["find"] = list(ex.map(lambda p: find_one(llm, cfg, p, sysm), ns))
    elif prev.get("find"): res["find"] = prev["find"]
    return res


def summarise(cfg, res):
    s, ok = [f"# Gate: {res['topic']} ({res['date']}), {res['notes']} notes"], True
    if "lint" in res:
        e = [x for x in res["lint"] if x[1] == "error"]; ok &= not e
        s.append(f"- lint: {len(e)} errors, {len(res['lint']) - len(e)} warnings" + "".join(f"\n  - {x[0]}: {x[1]} {x[2]}" for x in res["lint"][:60]))
    if "faith" in res:
        good = [f for f in res["faith"] if "error" not in f]; bad = [f for f in res["faith"] if "error" in f]
        rate = sum(f["pass"] for f in good) / max(1, len(good)); res["faith_rate"] = rate; ok &= rate >= cfg.thresholds["faith"]
        s.append(f"- faith: {sum(f['pass'] for f in good)}/{len(good)} notes pass ({100 * rate:.0f}%), {len(bad)} not checkable")
        s += [f"  - {f['slug']}: unsupported {f['unsupported_claims'][:4]} leak {f['leak']}" for f in good if not f["pass"]]
        s += [f"  - {f['slug']}: {f['error']} {f.get('unresolved', '')}" for f in bad]
    if "find" in res:
        val = [f for f in res["find"] if f["status"] != "harness_error"]; err = [f for f in res["find"] if f["status"] == "harness_error"]
        rate = sum(f["hit3"] for f in val) / max(1, len(val)); res["find_rate"] = rate; res["find_valid"] = not err
        if err:
            s.append(f"- find: HARNESS ERROR in {len(err)}/{len(res['find'])} runs, score INVALID (not a 0%); hit@3 over {len(val)} valid runs {100 * rate:.0f}%")
            s += [f"  - harness error {f['slug']}: {f['reason']}" for f in err]
        else:
            ok &= rate >= cfg.thresholds["find"]
            s.append(f"- find: hit@1 {100 * sum(f['hit1'] for f in val) / max(1, len(val)):.0f}%, hit@3 {100 * rate:.0f}%")
        s += [f"  - miss {f['slug']}: \"{f['question'][:140]}\" got {f['got']}" for f in val if not f["hit3"]]
    return s, ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--topic", help="one topic; default all"); ap.add_argument("--config"); ap.add_argument("--brain")
    ap.add_argument("--checks", default="lint,faith,find"); ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--limit", type=int, default=0, help="first N notes only (cheap smoke run)"); ap.add_argument("--no-cache", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.config, a.brain)
    checks = set(a.checks.split(","))
    llm = LLM(cfg) if checks & {"faith", "find"} else None
    topics = [a.topic] if a.topic else [t for t in cfg.topics if (cfg.brain / "internal" / t).is_dir()]
    all_ok, harness_broken = True, False
    for t in topics:
        res = gate_topic(cfg, llm, t, checks, a.workers, a.limit, a.no_cache)
        s, ok = summarise(cfg, res)
        d = cfg.brain / "internal" / t
        (d / "_gate.json").write_text(json.dumps(res, indent=1, ensure_ascii=False)); (d / "_gate.md").write_text("\n".join(s) + "\n")
        print("\n".join(s[:1] + [x for x in s if x.startswith("- ")]) + f"\n  -> {'PASS' if ok else 'FAIL'}  (details: {d / '_gate.md'})")
        all_ok &= ok; harness_broken |= res.get("find_valid") is False
    if llm: log_cost(cfg, f"gate {a.topic or 'all'} {a.checks}", llm)
    sys.exit(2 if harness_broken else 0 if all_ok else 1)


if __name__ == "__main__":
    main()
