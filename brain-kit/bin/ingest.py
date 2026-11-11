#!/usr/bin/env python3
"""Step 3, harvest: copy raw material into work/ingest/<source>/<id>-<slug>.md, one file per document, with a uniform header.

Usage:  python3 bin/ingest.py [--config brain.yaml]

Each entry under `sources:` in brain.yaml is a folder of exported documents (.md, .txt, .html). Export from your systems first
(Confluence space export, SharePoint download, a git repo, a Slack channel dump); this script only normalises. The header holds
id, title, url, source, author, modified: the gate later resolves a note's cited url back to this file, so get the url right.

  sources:
    - name: wiki
      path: exports/confluence-ARCH          # relative to brain.yaml
      include: ["**/*.md"]
      url_base: https://wiki.example.com     # url = url_base + frontmatter url, or + the relative path when the file has none
No model calls, no cost.
"""
import argparse, hashlib, html, json, os, re, subprocess, time
from pathlib import Path
from lib import load_config, parse_note


def title_of(fm, body, p):
    if fm.get("title"): return str(fm["title"])
    m = re.search(r"^#\s+(.+)$", body, re.M) or re.search(r"<title>(.*?)</title>", body, re.S | re.I)
    return m.group(1).strip() if m else p.stem.replace("-", " ").replace("_", " ")


def html_to_text(t):
    t = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", t, flags=re.S | re.I)
    t = re.sub(r"<(br|/p|/div|/li|/h\d|/tr)[^>]*>", "\n", t, flags=re.I)
    t = re.sub(r"<h(\d)[^>]*>", lambda m: "\n" + "#" * int(m.group(1)) + " ", t, flags=re.I)
    t = re.sub(r"<li[^>]*>", "- ", t, flags=re.I)
    return re.sub(r"\n{3,}", "\n\n", html.unescape(re.sub(r"<[^>]+>", "", t))).strip()


def modified(p):
    r = subprocess.run(["git", "log", "-1", "--format=%cs", "--", p.name], cwd=p.parent, capture_output=True, text=True)
    return r.stdout.strip() or time.strftime("%Y-%m-%d", time.localtime(p.stat().st_mtime))


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--config"); a = ap.parse_args()
    cfg = load_config(a.config)
    total = 0
    for s in cfg.d.get("sources", []):
        base = (cfg.root / os.path.expandvars(os.path.expanduser(s["path"]))).resolve()
        out = cfg.work / "ingest" / s["name"]; out.mkdir(parents=True, exist_ok=True)
        files = sorted({p for g in s.get("include", ["**/*.md"]) for p in base.glob(g) if p.is_file()})
        files = [p for p in files if not any(re.search(x, str(p.relative_to(base))) for x in s.get("exclude", []))]
        n = 0
        for p in files:
            raw = p.read_text(errors="replace")
            fm, body = parse_note(p) if p.suffix == ".md" else ({}, raw)
            fm = fm if isinstance(fm, dict) and "_yaml_error" not in fm else {}
            if p.suffix in (".html", ".htm"): body = html_to_text(body)
            if len(body.split()) < s.get("min_words", 80): continue  # stubs and index pages carry nothing
            rel = str(p.relative_to(base))
            url = fm.get("url") or "/" + re.sub(r"\.(md|txt|html?)$", "", rel)
            if s.get("url_base") and str(url).startswith("/"): url = s["url_base"].rstrip("/") + str(url)
            title = title_of(fm, body, p)
            did = hashlib.sha1(f"{s['name']}:{rel}".encode()).hexdigest()[:10]
            slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:60]
            head = {"id": did, "title": title, "url": str(url), "source": s["name"], "path": rel,
                    "author": str(fm.get("author", s.get("author", ""))), "modified": modified(p), "layer": s.get("layer", "internal")}
            (out / f"{did}-{slug}.md").write_text("---\n" + "\n".join(f"{k}: {json.dumps(v, ensure_ascii=False)}" for k, v in head.items())
                                                  + "\n---\n" + body.strip() + "\n")
            n += 1
        print(f"{s['name']}: {n} documents from {len(files)} files -> {out}")
        total += n
    print(f"ingest: {total} documents")


if __name__ == "__main__":
    main()
