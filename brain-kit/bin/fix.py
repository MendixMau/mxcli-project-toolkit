#!/usr/bin/env python3
"""Step 8b, repair: the writer model rewrites every note that failed faithfulness, against its sources and the auditor's findings.

Usage:  python3 bin/fix.py --topic security [--config brain.yaml] [--workers 4]

Reads brain/internal/<topic>/_gate.json. Supported claims stay; unsupported ones are removed or rewritten to what the sources say.
A rewrite that loses a frontmatter field or does not parse is rejected and the note is left as it was. Originals go to
work/fix/<topic>/. Run gate.py --checks faith again afterwards: unchanged notes reuse their cached verdict, so only the
repaired ones cost a new audit.
"""
import argparse, json, re, shutil
from concurrent.futures import ThreadPoolExecutor
import yaml
from lib import LLM, load_config, log_cost, parse_note, resolve_sources, safe_frontmatter

SYS = """You correct one note of a company knowledge base so that every factual claim is backed by its sources.
You get the note, the auditor's unsupported and partially supported claims, any leaked names, and the sources.
- Remove unsupported claims, or rewrite them to exactly what the sources say. Fix partial claims to match the sources.
- Remove leaked customer or person names (write "a customer") and any credentials, hosts or record data.
- Keep everything supported, keep the frontmatter and the headings for its kind, keep it short.
- A Status line says exactly what the sources support; never "confirmed" unless a source says so.
- Keep the keywords line; adjust it if you remove what a keyword pointed to.
- If too little remains to be useful, keep the note but set status: draft-thin.
Return the full corrected note only, starting with ---."""


def fix_one(llm, cfg, f, topic):
    p = cfg.brain / "internal" / topic / f"{f['slug']}.md"
    fm, _ = parse_note(p)
    texts, _ = resolve_sources(cfg, fm)
    src = "\n\n".join(f"### SOURCE {n}\n{t}" for n, t in texts)
    msg = (f"## NOTE\n{p.read_text()}\n\n## AUDIT\nunsupported: {json.dumps(f['unsupported_claims'], ensure_ascii=False)}\n"
           f"partial: {json.dumps(f['partial_claims'], ensure_ascii=False)}\nleak: {json.dumps(f['leak'], ensure_ascii=False)}\n\n## SOURCES\n{src}")
    t = llm.text("writer", SYS, msg, 8000)[0].strip()
    t = t[t.find("---"):] if "---" in t else t
    m = re.match(r"---\n(.*?)\n---\n", safe_frontmatter(t), re.S)
    if not m: return f["slug"], "rejected: unparsable"
    try: new = yaml.safe_load(m.group(1)) or {}
    except Exception: return f["slug"], "rejected: frontmatter unparsable"
    lost = [k for k in fm if k not in new]
    if lost: return f["slug"], f"rejected: lost {lost}"
    bak = cfg.work / "fix" / topic; bak.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, bak / p.name)
    p.write_text(safe_frontmatter(t) + "\n")
    return f["slug"], "fixed"


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--topic", required=True); ap.add_argument("--config")
    ap.add_argument("--workers", type=int, default=4); a = ap.parse_args()
    cfg = load_config(a.config); llm = LLM(cfg)
    g = json.loads((cfg.brain / "internal" / a.topic / "_gate.json").read_text())
    todo = [f for f in g.get("faith", []) if "error" not in f and not f["pass"]]
    with ThreadPoolExecutor(a.workers) as ex:
        for s, st in ex.map(lambda f: fix_one(llm, cfg, f, a.topic), todo): print(f"  {s}: {st}")
    print(f"{a.topic}: {len(todo)} notes sent for repair")
    log_cost(cfg, f"fix {a.topic}", llm)


if __name__ == "__main__":
    main()
