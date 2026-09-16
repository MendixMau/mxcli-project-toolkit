#!/usr/bin/env bash
# images-to-md.sh — one worklist of every unique picture in a project's source corpus, one
# description file each, coverage checked.
#
#   bin/images-to-md.sh <project-root> [--source <dir>] [--out <dir>] [--check] [--inline] [--force]
#
# WHY THIS EXISTS (2026-09-14). `bin/html-to-md.sh` converts a corpus's HTML to Markdown once
# and lists every image in `documents-index.md` with an "Images to read (vision)" denominator —
# but nothing then reads the pictures except whichever session happens to look, and the
# description is never stored anywhere another session can find it. Field precedent: a 25-slide
# functional-description deck (22 distinct PNGs) was read as prose at Stage P and its images
# were extracted 20 days later by hand; the pictures overturned an analysis conclusion and
# closed four open questions, and the hand capture left no per-image file, so nothing downstream
# could cite a picture. This makes that repeatable: the SCRIPT prepares a worklist and verifies
# coverage; the MODEL (a session or a fanned-out subagent) reads and writes
# (skills-over-scripts.md).
#
# WHAT IT COLLECTS: loose image files under the source root; HTML sidecar images (`<page>_files/`)
# plus the inline base64 images bin/html-to-md.sh already decoded; every .pptx/.docx under the
# source root (media, with the pptx slide->image mapping and slide text kept as context, and a
# docx image mapped to its nearest preceding heading); PDF images, best effort — see
# bin/lib/images-to-md.py's header for exactly which PDF filters it can decode.
#
# WHAT IT WRITES (all under <out>, default analysis/knowledge-base/images/):
#   manifest.json   one row per UNIQUE image (deduped by sha256): dimensions, role
#                   (content|chrome|vector|needs-render), every location, the copy at
#                   images/<id>.<ext>.
#   worklist.md     one section per content image — the read's denominator — with the exact
#                   path of the description file it owes.
# Plus, per pptx deck, analysis/knowledge-base/text/<deck-stem>/slideNN.md + slides.json.
#
# Write the description files per skills/image-transcription.md, then run with --check: it
# verifies every content image's description file exists, is non-empty, and carries the
# template's headings, reports "described N of M", and — once complete — inlines each
# description's verbatim text and summary right under the page's `![alt](path)` line
# (--inline; runs automatically at the end of a clean --check) and prints the
# `bin/source-ledger.sh mark` command owed per source file (printed, never run).
#
# Source root: --source wins; else sources/, then source/ — identical detection to
# bin/html-to-md.sh, which should already have run over the same corpus.
#
# Idempotent: an image's id is stable across runs (carried over by sha256), so a description
# written against img-014 never orphans; unchanged bytes are never rewritten. --force forgets
# the old id assignment and rebuilds from zero.
#
# Bash 3.2 + any Python 3 (bin/lib/portable.sh); the worker is bin/lib/images-to-md.py, standard
# library only. Exit 0 a plain run, or --check/--inline with nothing missing · 1 --check found
# undescribed content images (listed) · 2 usage.
#
# Fixture: tests/wave2/test-images-to-md.sh.
set -u

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/portable.sh"

usage() {
  echo "usage: images-to-md.sh <project-root> [--source <dir>] [--out <dir>] [--check] [--inline] [--force]" >&2
  exit 2
}

PROJECT_DIR=""; SOURCES_DIR=""; OUT_DIR=""; CHECK=""; INLINE=""; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCES_DIR="${2:-}"; shift 2 ;;
    --out)    OUT_DIR="${2:-}"; shift 2 ;;
    --check)  CHECK="--check"; shift ;;
    --inline) INLINE="--inline"; shift ;;
    --force)  FORCE="--force"; shift ;;
    -h|--help) usage ;;
    -*) echo "images-to-md: unknown option: $1" >&2; usage ;;
    *)  [ -z "$PROJECT_DIR" ] || usage; PROJECT_DIR="$1"; shift ;;
  esac
done
[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "images-to-md: not a directory: $PROJECT_DIR" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [ -z "$SOURCES_DIR" ]; then
  if   [ -d "$PROJECT_DIR/sources" ]; then SOURCES_DIR="$PROJECT_DIR/sources"
  elif [ -d "$PROJECT_DIR/source"  ]; then SOURCES_DIR="$PROJECT_DIR/source"
  else
    echo "images-to-md: no sources/ or source/ under $PROJECT_DIR — name the corpus with --source <dir>" >&2
    exit 2
  fi
fi
[ -d "$SOURCES_DIR" ] || { echo "images-to-md: source root is not a directory: $SOURCES_DIR" >&2; exit 2; }
[ -n "$OUT_DIR" ] || OUT_DIR="$PROJECT_DIR/analysis/knowledge-base/images"
TEXT_DIR="$PROJECT_DIR/analysis/knowledge-base/text"

WORKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/images-to-md.py"
[ -f "$WORKER" ] || { echo "images-to-md: $WORKER missing" >&2; exit 2; }
require_py

"$PY" "$WORKER" "$PROJECT_DIR" "$SOURCES_DIR" "$OUT_DIR" "$TEXT_DIR" $CHECK $INLINE $FORCE
