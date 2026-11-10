#!/usr/bin/env python3
"""Step 9, publish the usage layer: the root INDEX.md (topics with note counts) and QUALITY.md (gate scores per topic).

Usage:  python3 bin/index.py [--config brain.yaml | --brain DIR]

Reads each topic's INDEX.md and _gate.json. AGENTS.md and ROUTING.md are written by hand from the template (they are the
judgment part: when to consult the brain, and which trigger opens which topic); this script never touches them.
No model calls.
"""
import argparse, json, time
from lib import load_config, notes, parse_note


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--config"); ap.add_argument("--brain"); a = ap.parse_args()
    cfg = load_config(a.config, a.brain)
    b = cfg.brain
    topics = [t for t in cfg.topics if (b / "internal" / t).is_dir()]
    rows, q = [], []
    for t in topics:
        ns = notes(b, t)
        kinds = {}
        for p in ns:
            fm, _ = parse_note(p); k = (fm or {}).get("kind", "?"); kinds[k] = kinds.get(k, 0) + 1
        rows.append(f"| [{t}](internal/{t}/INDEX.md) | {len(ns)} | {', '.join(f'{v} {k}' for k, v in sorted(kinds.items()))} | {cfg.topics[t]} |")
        g = b / "internal" / t / "_gate.json"
        if g.exists():
            r = json.loads(g.read_text())
            lint_err = sum(1 for x in r.get("lint", []) if x[1] == "error") if "lint" in r else "-"
            fa = [f for f in r.get("faith", []) if "error" not in f]
            faith = f"{sum(f['pass'] for f in fa)}/{len(fa)}" if "faith" in r else "-"
            nc = sum(1 for f in r.get("faith", []) if "error" in f) if "faith" in r else "-"
            fv = [f for f in r.get("find", []) if f["status"] != "harness_error"]
            find = (f"{100 * sum(f['hit3'] for f in fv) / max(1, len(fv)):.0f}%" + ("" if r.get("find_valid", True) else " (harness errors)")) if "find" in r else "-"
            q.append(f"| {t} | {len(ns)} | {lint_err} | {faith} | {nc} | {find} | {r['date']} |")
        else:
            q.append(f"| {t} | {len(ns)} | not gated | | | | |")
    (b / "INDEX.md").write_text("# Topics\n\nStart with the topic's INDEX.md; each lists one line per note and a `## Gaps` list.\n\n"
                                "| topic | notes | kinds | scope |\n|---|---|---|---|\n" + "\n".join(rows) + "\n")
    (b / "QUALITY.md").write_text(
        f"# Quality gate results\n\nUpdated {time.strftime('%Y-%m-%d')}. Automatic checks, not human review: notes stay `draft-unreviewed` "
        "until a person reviews them.\n\n- **lint errors**: frontmatter, kinds, sources, size, links, denied names.\n"
        "- **faithful**: notes with zero unsupported claims when a second model checks each claim against the note's own sources.\n"
        "- **not checkable**: notes whose sources could not be matched to a stored document. Treat with extra care.\n"
        "- **findable**: share of notes a grep-only search agent returns in its top 3 for a question written in the reader's words. Bar "
        f"{100 * cfg.thresholds['find']:.0f}%.\n\n"
        "| topic | notes | lint errors | faithful | not checkable | findable (hit@3) | gated |\n|---|---|---|---|---|---|---|\n" + "\n".join(q) + "\n")
    print(f"index: {len(topics)} topics, {sum(len(notes(b, t)) for t in topics)} notes -> {b / 'INDEX.md'}, {b / 'QUALITY.md'}")


if __name__ == "__main__":
    main()
