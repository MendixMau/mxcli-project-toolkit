#!/usr/bin/env python3
"""Step 7, keywords: give every note without a `keywords:` line 6 to 12 grep terms (cheap model).

Usage:  python3 bin/keywords.py --topic security [--config brain.yaml] [--all]

Why: agents search with grep, and they type the symptom, not the note's title. The keywords line is where the reader's words meet
the note's words. --all rewrites keywords on every note (after a big merge round). Cost: cents per topic.
"""
import argparse, json, re
from concurrent.futures import ThreadPoolExecutor
from lib import LLM, load_config, log_cost, notes, parse_note

SYS = """You add search keywords to one note of a knowledge base. Readers find notes with grep.
Return 6 to 12 terms a reader facing this situation would type: the symptom in plain words, exact error messages or codes in the note,
product / module / API / setting names, common synonyms and abbreviations. Only terms that fit the content. 1 to 3 words each.
JSON: {"keywords": [...]}"""


def one(llm, p, force):
    fm, _ = parse_note(p); t = p.read_text()
    if not fm or "_yaml_error" in fm or (re.search(r"^keywords:", t, re.M) and not force): return p.stem, None
    kw = [k.strip() for k in llm.json("cheap", SYS, t, 500).get("keywords", []) if k.strip()][:12]
    line = "keywords: " + json.dumps(kw, ensure_ascii=False)
    if re.search(r"^keywords:.*$", t, re.M): t = re.sub(r"^keywords:.*$", lambda m: line, t, count=1, flags=re.M)
    else: t = re.sub(r"^(versions:.*)$", lambda m: m.group(1) + "\n" + line, t, count=1, flags=re.M)
    p.write_text(t)
    return p.stem, kw


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--topic", required=True); ap.add_argument("--config")
    ap.add_argument("--all", action="store_true"); a = ap.parse_args()
    cfg = load_config(a.config); llm = LLM(cfg)
    with ThreadPoolExecutor(8) as ex:
        res = list(ex.map(lambda p: one(llm, p, a.all), notes(cfg.brain, a.topic)))
    print(f"{a.topic}: keywords added to {sum(1 for _, k in res if k)} notes")
    log_cost(cfg, f"keywords {a.topic}", llm)


if __name__ == "__main__":
    main()
