#!/usr/bin/env python3
"""Step 5, curate: turn the classification into one shortlist per topic, written as a table a person can review and edit.

Usage:  python3 bin/shortlist.py [--config brain.yaml] [--min-quality 3] [--maybe-quality 4]

Rule: keep=yes with quality >= --min-quality, plus keep=maybe with quality >= --maybe-quality, on its FIRST topic only (one document
feeds one topic, so two topics never write the same lesson). Documents with secrets: true are always left out.
Output: work/shortlists/<topic>.md, one row per document. Delete a row to drop it; the compact step reads the file as it is.
This is the human checkpoint: nothing reaches a note that a person did not leave on a shortlist. No model calls.
"""
import argparse, json
from collections import defaultdict
from lib import load_config


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--config")
    ap.add_argument("--min-quality", type=int, default=3); ap.add_argument("--maybe-quality", type=int, default=4)
    a = ap.parse_args()
    cfg = load_config(a.config)
    rows = [json.loads(l) for l in (cfg.work / "classified.jsonl").open()]
    by = defaultdict(list); dropped = 0
    for r in rows:
        q, keep = r.get("quality") or 0, r.get("keep")
        ok = (keep == "yes" and q >= a.min_quality) or (keep == "maybe" and q >= a.maybe_quality)
        if not ok or r.get("secrets") or not r.get("topics"): dropped += 1; continue
        by[r["topics"][0]].append(r)
    d = cfg.work / "shortlists"; d.mkdir(parents=True, exist_ok=True)
    for t in cfg.topics:
        lst = sorted(by.get(t, []), key=lambda r: -(r.get("quality") or 0))
        lines = [f"# Shortlist: {t}", "", f"{cfg.topics[t]}", "",
                 "Delete a row to drop the document. `names` lists names the classifier saw: the compact step is told to redact them.", "",
                 "| id | title | kind | q | fresh | names | why |", "|---|---|---|---|---|---|---|"]
        for r in lst:
            cell = lambda s: str(s).replace("|", "/").replace("\n", " ")[:160]
            lines.append(f"| {r['id']} | {cell(r['title'])} | {r.get('kind', '')} | {r.get('quality', '')} | {r.get('freshness', '')} | "
                         f"{cell(', '.join(r.get('names') or []))} | {cell(r.get('reason', ''))} |")
        (d / f"{t}.md").write_text("\n".join(lines) + "\n")
        print(f"  {t}: {len(lst)} documents")
    print(f"shortlist: {sum(len(v) for v in by.values())} kept, {dropped} dropped -> {d}")


if __name__ == "__main__":
    main()
