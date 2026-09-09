#!/usr/bin/env bash
# html-to-md.sh — convert every HTML page in a project's source corpus to Markdown, ONCE.
#
#   bin/html-to-md.sh <project-root> [--source <dir>] [--out <dir>] [--force]
#
# WHY THIS EXISTS (2026-09-09). A requirements-driven project whose corpus was Markdown files
# plus saved-webpage exports (each .html with its `_files` sidecar folder) was slow and
# token-hungry through Stages 1–4, and the measured cause was that every session read the raw
# HTML: 3–10× the tokens of the page's own text, paid again each time. Convert once, and the
# knowledge base IS the converted text — that is the "docs-ready" fast path in
# skills/conversion-runbook.md → Entry Modes → "Requirements-driven, docs-ready corpus".
#
# WHAT IT WRITES (all under <out>, default analysis/knowledge-base/text/):
#   <same relative path>.md         headings, paragraphs, lists, tables, links, code; every <img>
#                                   as ![alt](src); scripts, styles, nav/footer/sidebar chrome gone
#   <same relative path>_images/    every inline base64 image decoded to a file, so it can be
#                                   read with vision without opening the HTML
#   ../documents-index.md           ONE row per file under the source root — pages, markdown,
#                                   sidecar images, css, js, fonts — so a single ledger mark can
#                                   point at it:  bin/source-ledger.sh mark <p> '*' --artifact
#                                   analysis/knowledge-base/documents-index.md --evidence "..."
# Each .md opens with a header — source path, raw size, words, images, and the section list with
# md line numbers — which is the denominator a reader states ("all N sections covered").
#
# Source root: --source wins; else sources/, then source/ (the two drop-folder spellings
# bin/init-project.sh scaffolds — the same detection as bin/source-sufficiency.sh, minus that
# script's legacy analysis/ fallback, which would convert the project's own outputs).
#
# Idempotent: a page whose .md is newer than its source is skipped; --force reconverts all.
# Bash 3.2 + any Python 3 (bin/lib/portable.sh); the converter is bin/lib/html-to-md.py,
# standard library only. Exit 0 converted (or nothing to do) · 2 usage · 3 no files found.
#
# Fixture: tests/wave2/test-html-to-md.sh (a synthetic saved-webpage export; see its CAPTURE.md).
set -u

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

usage() {
  echo "usage: html-to-md.sh <project-root> [--source <dir>] [--out <dir>] [--force]" >&2
  exit 2
}

PROJECT_DIR=""; SOURCES_DIR=""; OUT_DIR=""; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCES_DIR="${2:-}"; shift 2 ;;
    --out)    OUT_DIR="${2:-}"; shift 2 ;;
    --force)  FORCE="--force"; shift ;;
    -h|--help) usage ;;
    -*) echo "html-to-md: unknown option: $1" >&2; usage ;;
    *)  [ -z "$PROJECT_DIR" ] || usage; PROJECT_DIR="$1"; shift ;;
  esac
done
[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "html-to-md: not a directory: $PROJECT_DIR" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [ -z "$SOURCES_DIR" ]; then
  if   [ -d "$PROJECT_DIR/sources" ]; then SOURCES_DIR="$PROJECT_DIR/sources"
  elif [ -d "$PROJECT_DIR/source"  ]; then SOURCES_DIR="$PROJECT_DIR/source"
  else
    echo "html-to-md: no sources/ or source/ under $PROJECT_DIR — name the corpus with --source <dir>" >&2
    exit 2
  fi
fi
[ -d "$SOURCES_DIR" ] || { echo "html-to-md: source root is not a directory: $SOURCES_DIR" >&2; exit 2; }
[ -n "$OUT_DIR" ] || OUT_DIR="$PROJECT_DIR/analysis/knowledge-base/text"

CONVERTER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/html-to-md.py"
[ -f "$CONVERTER" ] || { echo "html-to-md: $CONVERTER missing" >&2; exit 2; }
require_py

"$PY" "$CONVERTER" "$PROJECT_DIR" "$SOURCES_DIR" "$OUT_DIR" $FORCE
