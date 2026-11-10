#!/usr/bin/env python3
"""Step 6, compact: the writer model turns one topic's shortlisted documents into short notes, one lesson each, plus the topic INDEX.

Usage:  python3 bin/compact.py --topic security [--config brain.yaml] [--dry-run] [--force] [--merge]

Documents are packed into batches of ~BATCH_CHARS. Batch 1 writes fresh notes; every later batch is a MERGE round over the notes
written so far (confirm, correct or extend existing notes, add new ones), so the topic converges instead of growing duplicates.
--merge runs a merge round over an existing topic (new documents on the shortlist since the last build).
Output: brain/internal/<topic>/<slug>.md and INDEX.md (with a ## Gaps list); raw model output in work/compact/<topic>/.
Every note starts as status: draft-unreviewed. Cost: roughly $1 to $3 per topic of 20 to 40 documents on an Opus-class writer.
"""
import argparse, json, re, shutil, time
from pathlib import Path
from lib import LLM, load_config, log_cost, notes, read_doc, safe_frontmatter

BATCH_CHARS = 300000
PAGE_LIMIT = 40000


def system(cfg, topic):
    return f"""You write notes for a company knowledge base ("brain"). Readers are {cfg.audience}; agents find notes with grep.
You turn raw sources on ONE topic into short, durable notes. Each note holds ONE lesson and fits on one screen (40 to 400 words).
TOPIC: {topic}: {cfg.topics[topic]}

Output format, nothing else:
=== NOTE: <kebab-slug> ===
---
title: <descriptive title, says what the note is about>
topic: {topic}
kind: <pitfall | procedure | practice | decision | reference>
applies_to: <one of {', '.join(cfg.applies_to)}>
versions: "<versions the lesson is valid for, or 'any'>"
keywords: [<6 to 12 terms a reader would grep for: the symptom in their words, exact error messages or codes, product, module, API and setting names, synonyms>]
sources:
  - {{title: "<source title exactly as given>", url: "<source url exactly as given>", author: "...", date: "YYYY-MM-DD"}}
status: draft-unreviewed
---
<body>

Body by kind:
- pitfall: **Symptom** / **Root cause** / **Fix** / **Status** (exactly what the source supports: fixed in version X, workaround only,
  seen once, reported by several teams, unknown; "confirmed" only when a source says so)
- procedure: **When** / **Steps** (numbered, short) / **Checks** / **Watch out** (link other notes as [[slug]])
- practice or decision: **Rule** / **Why** / **How to apply**
- reference: a compact table

Rules:
- Only facts present in the sources. No invented steps, numbers, versions or examples. If a source is unclear, say so in the note.
- No advice or conclusions of your own: every Rule, Fix and How-to-apply line traces to a source.
- Merge duplicates across sources into one note listing all sources. When sources conflict, keep the better-evidenced claim and state the conflict.
- {cfg.novelty}
- Redact names of customers and people outside the author line (write "a customer"); never copy credentials, hosts or record data.
  {('Always redact: ' + ', '.join(cfg.d.get('deny_names', []))) if cfg.d.get('deny_names') else ''}
- Copy each source's title and url EXACTLY as given in its header: the quality gate resolves the note back to the source by them.
- Aim for one note per distinct lesson, typically 10 to 30 per topic. Short lines. No filler.
After the last note output:
=== INDEX ===
one line per note: - [[slug]] kind, versions: one-line hook (the words a reader would recognise their situation by)
=== GAPS ===
bullets: what a reader of this topic would need that the sources do not cover, and conflicts you could not resolve."""


MERGE = """

MERGE ROUND. You get the EXISTING notes of this topic and NEW sources. Do not output notes the new sources do not touch.
- An existing note the new sources confirm, correct or extend: output the full revised note under its SAME slug, new source added.
- A new lesson: a new note with a new slug.
- A contradiction: keep the better-evidenced claim and say so in the note.
- The INDEX lists ALL notes (unchanged, revised and new). GAPS replaces the old list: drop gaps the new sources close.
After GAPS output:
=== CHANGES ===
bullets: revised <slug>: what changed | new <slug>: why | gaps closed."""


def shortlisted(cfg, topic):
    f = cfg.work / "shortlists" / f"{topic}.md"
    if not f.exists(): raise SystemExit(f"no shortlist {f}: run shortlist.py first")
    ids = re.findall(r"^\| ([0-9a-f]{10}) \|", f.read_text(), re.M)
    files = {p.name.split("-", 1)[0]: p for p in (cfg.work / "ingest").glob("*/*.md")}
    return [files[i] for i in ids if i in files]


def batches(paths):
    out, cur, size = [], [], 0
    for p in paths:
        n = min(p.stat().st_size, PAGE_LIMIT)
        if cur and size + n > BATCH_CHARS: out.append(cur); cur, size = [], 0
        cur.append(p); size += n
    return out + ([cur] if cur else [])


def block(p, label="SOURCE"):
    fm, body = read_doc(p)
    cut = body[:PAGE_LIMIT] + (" [truncated]" if len(body) > PAGE_LIMIT else "")
    return (f"\n## {label}\ntitle: {fm.get('title')}\nurl: {fm.get('url')}\nauthor: {fm.get('author') or 'unknown'}\n"
            f"date: {fm.get('modified')}\n\n{cut}")


def merge_prompt(cfg, topic, batch):
    d = cfg.brain / "internal" / topic
    parts = ["## EXISTING NOTES"] + [f"\n=== EXISTING NOTE: {p.stem} ===\n{p.read_text()}" for p in notes(cfg.brain, topic)]
    idx = d / "INDEX.md"
    parts.append(f"\n## EXISTING GAPS\n{idx.read_text().split('## Gaps')[-1] if idx.exists() else ''}")
    parts += [block(p, "NEW SOURCE") for p in batch]
    return "\n".join(parts) + "\n\nWrite the revised and new notes, then the full INDEX, GAPS and CHANGES."


def write(cfg, topic, text, model):
    d = cfg.brain / "internal" / topic; d.mkdir(parents=True, exist_ok=True)
    raw = cfg.work / "compact" / topic; raw.mkdir(parents=True, exist_ok=True)
    (raw / f"output-{time.strftime('%Y%m%d-%H%M%S')}.md").write_text(text)
    got = re.findall(r"=== NOTE: ([a-z0-9-]+) ===\n(.*?)(?=\n=== (?:NOTE|INDEX|GAPS|CHANGES)|\Z)", text, re.S)
    for slug, body in got: (d / f"{slug}.md").write_text(safe_frontmatter(body.strip()) + "\n")
    idx = re.search(r"=== INDEX ===\n(.*?)(?=\n=== (?:GAPS|CHANGES)|\Z)", text, re.S)
    gaps = re.search(r"=== GAPS ===\n(.*?)(?=\n=== CHANGES|\Z)", text, re.S)
    (d / "INDEX.md").write_text(f"# {topic}: notes\n\n{cfg.topics[topic]}\n\nGenerated {time.strftime('%Y-%m-%d')} by {model}; every note is "
                                f"draft-unreviewed until a person reviews it.\n\n{idx.group(1).strip() if idx else ''}\n\n"
                                f"## Gaps\n\n{gaps.group(1).strip() if gaps else ''}\n")
    return len(got)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--topic", required=True); ap.add_argument("--config")
    ap.add_argument("--dry-run", action="store_true"); ap.add_argument("--force", action="store_true"); ap.add_argument("--merge", action="store_true")
    a = ap.parse_args()
    cfg = load_config(a.config)
    if a.topic not in cfg.topics: raise SystemExit(f"unknown topic {a.topic}; topics: {', '.join(cfg.topics)}")
    paths = shortlisted(cfg, a.topic); bs = batches(paths)
    print(f"{a.topic}: {len(paths)} documents in {len(bs)} batches")
    if a.dry_run or not bs: return
    d = cfg.brain / "internal" / a.topic
    if notes(cfg.brain, a.topic) and not a.merge:
        if not a.force: raise SystemExit("notes exist: --merge to add new documents, --force to rebuild from scratch")
        shutil.move(str(d), str(cfg.work / "compact" / f"old-{a.topic}-{time.strftime('%Y%m%d-%H%M%S')}"))
    llm = LLM(cfg); model = llm.model("writer")
    for n, b in enumerate(bs, 1):
        t0 = time.time()
        fresh = n == 1 and not a.merge
        prompt = ("\n".join(block(p) for p in b) + "\n\nWrite the notes now.") if fresh else merge_prompt(cfg, a.topic, b)
        text, msg = llm.text("writer", system(cfg, a.topic) + ("" if fresh else MERGE), prompt, max_tokens=64000)
        k = write(cfg, a.topic, text, model)
        print(f"  batch {n}: {k} notes written, stop={msg.stop_reason}, {time.time() - t0:.0f}s", flush=True)
        if msg.stop_reason == "max_tokens": print("  WARNING: output cut at max_tokens; the last note may be incomplete (the gate's lint will show it)")
    print(f"{a.topic}: {len(notes(cfg.brain, a.topic))} notes")
    log_cost(cfg, f"compact {a.topic}", llm, {"documents": len(paths)})


if __name__ == "__main__":
    main()
