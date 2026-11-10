#!/usr/bin/env python3
"""Step 4, classify: a cheap model reads every ingested document once and decides keep / maybe / no, topic and kind.

Usage:  python3 bin/classify.py [--config brain.yaml] [--workers 8] [--limit N]

Output: work/classified.jsonl, one row per document. Documents already in the file are skipped (rerun after a new export).
Cost: about $3 per 1,000 documents on a Haiku-class model. Nothing here enters the brain; the shortlist step reads this file.
"""
import argparse, json
from concurrent.futures import ThreadPoolExecutor
from lib import LLM, Budget, load_config, log_cost, read_doc

BODY_LIMIT = 14000


def system(cfg):
    topics = "\n".join(f"- {k}: {v}" for k, v in cfg.topics.items())
    return f"""You classify one document for a company knowledge base ("brain") read by {cfg.audience}.
The brain wants durable, reusable practitioner knowledge: how to design, build, test, secure, integrate, deliver and operate systems,
pitfalls with their fix, measured results, house rules and repeatable procedures. It does NOT want meeting notes, retros, planning,
status reports, rosters, event logistics, personal pages, or pages that are only a list of links.
{cfg.d.get('classify_rule', '')}

Topics:
{topics}

Fields:
- keep: "yes" | "maybe" | "no"   ("yes" only if a practitioner would still act on it today)
- reason: one short sentence
- topics: 1 to 2 topic names from the list, best first; [] when none fits
- kind: the note kind this would become: pitfall | procedure | practice | decision | reference
- summary: at most 2 sentences, what a reader learns
- key_facts: up to 6 short concrete statements (rules, numbers, settings, do/don't); [] if none
- names: customer, partner or person names that appear in the text (author lines excluded); [] if none
- secrets: true if credentials, tokens or keys appear
- freshness: current | dated | obsolete
- quality: 1 to 5 (5 = precise, complete, actionable)"""


def one(llm, cfg, p):
    fm, body = read_doc(p)
    user = f"title: {fm.get('title')}\nurl: {fm.get('url')}\nmodified: {fm.get('modified')}\n\n{body[:BODY_LIMIT]}"
    try:
        d = llm.json("cheap", system(cfg), user, 1500)
        d["topics"] = [t for t in d.get("topics") or [] if t in cfg.topics]
    except Budget: raise
    except Exception as e:
        d = {"error": str(e)[:200]}
    return {"id": fm.get("id"), "file": str(p.relative_to(cfg.work)), "title": fm.get("title"), "url": fm.get("url"),
            "chars": len(body), "truncated": len(body) > BODY_LIMIT, **d}


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--config"); ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=0); a = ap.parse_args()
    cfg = load_config(a.config); llm = LLM(cfg)
    out = cfg.work / "classified.jsonl"
    done = {json.loads(l)["id"] for l in out.open()} if out.exists() else set()
    todo = [p for p in sorted((cfg.work / "ingest").glob("*/*.md")) if p.name.split("-", 1)[0] not in done]
    if a.limit: todo = todo[:a.limit]
    print(f"classify: {len(todo)} documents ({len(done)} already done)")
    with out.open("a") as f, ThreadPoolExecutor(a.workers) as ex:
        for r in ex.map(lambda p: one(llm, cfg, p), todo):
            f.write(json.dumps(r, ensure_ascii=False) + "\n"); f.flush()
    rows = [json.loads(l) for l in out.open()]
    by = {k: sum(1 for r in rows if r.get("keep") == k) for k in ("yes", "maybe", "no")}
    print(f"classified {len(rows)}: {by}, errors {sum(1 for r in rows if 'error' in r)}")
    log_cost(cfg, "classify", llm, {"documents": len(todo)})


if __name__ == "__main__":
    main()
