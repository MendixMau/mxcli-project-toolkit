#!/usr/bin/env bash
# test-progress-report-pages.sh: pin the "Project pages" section of architecture/progress-report.html
# (project-bin/progress-report.py, render_pages / collect_pages / rel_href), written through
# project-bin/build-plan-status.sh --html. Every name, path and number below is invented; the project
# trees are synthetic, built here, on both layouts.
#
#   P1  single tree: every HTML page under the scanned folders is a relative link from architecture/,
#       counted per folder; the root index.html is ../index.html; a name with a space is %20-encoded.
#   P2  the report itself and pages in excluded folders (node_modules, .mpr-snapshots, deployment,
#       mprcontents, theme, .git, vendor) or unscanned folders (sources/) are never listed.
#   P3  a folder with more than PAGE_GROUP_OPEN (8) pages is folded behind a <details> with its count;
#       a small one is not. Subfolders are indented under their listed parent.
#   P4  each page shows its modified date (date only).
#   P5  two tree (.mpr under app/): the same links from the repo root; app/theme, app/deployment and
#       app/mprcontents pages are not listed.
#   P6  Windows: rel_href gives forward-slash, percent-encoded hrefs for a Windows path (ntpath).
#   P7  a --refresh with nothing changed leaves the page untouched (the dates do not churn it).
#   P8  a project with no pages yet says so instead of an empty card.
#
# Usage: bash tests/wave2/test-progress-report-pages.sh /path/to/build-plan-status.sh

set -uo pipefail
SCRIPT="${1:?usage: bash tests/wave2/test-progress-report-pages.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/progress-pages.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
# shellcheck disable=SC1091
. "$ROOT/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
if [ -z "$PY" ]; then echo "SKIP: no Python 3 found"; echo "PASS=0 FAIL=0"; exit 0; fi
EMPTY="$WORK/cfg"; mkdir -p "$EMPTY/projects"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
# the Project pages section only, so a link elsewhere on the page never satisfies an assertion
# (from the count line on: the heading's own text names the excluded folders)
section() { "$PY" -c 'import sys;h=open(sys.argv[1],encoding="utf-8").read();i=h.find("<h2 id=pages>");j=h.find("</div>",i);print(h[j:h.find("<footer",i)] if i>=0 else "")' "$1"; }
has() { printf '%s' "$1" | grep -q -- "$2" && ok "$3" || bad "$3"; }
hasnt() { printf '%s' "$1" | grep -q -- "$2" && bad "$3" || ok "$3"; }
page() { mkdir -p "$(dirname "$1")"; echo "<html>x</html>" > "$1"; }

mkplan() {  # repo-root
  mkdir -p "$1/architecture"
  cat > "$1/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Orders

| # | Kind | Step | State |
|---|---|---|---|
| 1 | BUILD | Create entity | built |
MD
}

mkpages() {  # repo-root: the pages the toolkit writes, plus decoys that must stay out
  local r="$1" i
  page "$r/index.html"
  page "$r/analysis/brd-report.html"; page "$r/analysis/app-report.html"
  page "$r/analysis/srcA/knowledge-base/extraction-report.html"
  page "$r/architecture/blueprint.html"; page "$r/architecture/module-design.html"
  page "$r/design/design-system.html"; page "$r/design/process-map.html"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do page "$r/design/wireframes/screen-$i.html"; done
  page "$r/design/ui-reviews/ui-review-2026-01-02.html"
  page "$r/docs/verification/report.html"; page "$r/journeys/orders/journey report.html"
  touch -t 202601021200 "$r/design/ui-reviews/ui-review-2026-01-02.html"
  # decoys
  page "$r/node_modules/pkg/index.html"; page "$r/analysis/node_modules/x/readme.html"
  page "$r/.mpr-snapshots/20260101/stale.html"; page "$r/design/.git/hook.html"
  page "$r/docs/vendor/lib.html"; page "$r/sources/legacy/screen.html"; page "$r/design/notes.md"
}
# 1 root + 3 analysis + 2 architecture + 2 design + 12 wireframes + 1 ui-review + 1 docs + 1 journeys
WANT_PAGES=23; WANT_FOLDERS=9

check_layout() {  # label repo-root
  local L="$1" R="$2" S
  CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$R" --html --quiet >/dev/null 2>&1
  [ -f "$R/architecture/progress-report.html" ] && ok "$L: page written" || { bad "$L: page written"; return; }
  S="$(section "$R/architecture/progress-report.html")"
  grep -q "<h2 id=pages>Project pages" "$R/architecture/progress-report.html" && ok "$L: Project pages section present" || bad "$L: Project pages section present"
  has "$S" "$WANT_PAGES pages in $WANT_FOLDERS folders" "$L: counts $WANT_PAGES pages in $WANT_FOLDERS folders"
  [ "$(printf '%s' "$S" | grep -o "<a href=" | wc -l | tr -d ' ')" -eq "$WANT_PAGES" ] && ok "$L: exactly $WANT_PAGES links" || bad "$L: exactly $WANT_PAGES links (got $(printf '%s' "$S" | grep -o "<a href=" | wc -l))"
  has "$S" "href='../index.html'" "$L: root gate dashboard is ../index.html"
  has "$S" "href='../analysis/brd-report.html'" "$L: analysis page linked from architecture/"
  has "$S" "href='../analysis/srcA/knowledge-base/extraction-report.html'" "$L: a deep analysis/** page is found"
  has "$S" "href='blueprint.html'" "$L: an architecture/ page is a sibling link"
  has "$S" "href='../design/wireframes/screen-12.html'" "$L: wireframes linked"
  has "$S" "href='../design/ui-reviews/ui-review-2026-01-02.html'" "$L: ui review linked"
  has "$S" "href='../docs/verification/report.html'" "$L: test report linked"
  has "$S" "href='../journeys/orders/journey%20report.html'" "$L: journey report linked, space percent-encoded"
  hasnt "$S" "progress-report.html" "$L: the report never lists itself"
  hasnt "$S" "node_modules\|mpr-snapshots\|stale.html\|hook.html\|lib.html\|legacy\|notes.md" "$L: excluded and unscanned folders stay out"
  has "$S" "<summary>12 pages, newest" "$L: 12 wireframes folded behind a count"
  [ "$(printf '%s' "$S" | grep -o "<details" | wc -l | tr -d ' ')" -eq 1 ] && ok "$L: only the big folder is folded" || bad "$L: only the big folder is folded"
  has "$S" "style='padding-left:16px'><b class=dir title='design/wireframes/'>wireframes/" "$L: subfolder indented under design/"
  has "$S" "ui-review-2026-01-02.html</a> <span class=mut>2026-01-02<" "$L: modified date shown"
  "$PY" - "$S" <<'PYEOF' && ok "$L: screen-2 sorts before screen-10" || bad "$L: screen-2 sorts before screen-10"
import sys; s = sys.argv[1]; sys.exit(0 if 0 <= s.find("screen-2.html") < s.find("screen-10.html") else 1)
PYEOF
}

echo "P1-P4 single tree"
P1="$WORK/single"; mkplan "$P1"; mkpages "$P1"; : > "$P1/Shop.mpr"; mkdir -p "$P1/mprcontents"; page "$P1/mprcontents/a.html"
page "$P1/theme/web/index.html"; page "$P1/deployment/web/index.html"
check_layout single "$P1"

echo "P5 two tree (.mpr under app/)"
P2="$WORK/two tree"; mkplan "$P2"; mkpages "$P2"; mkdir -p "$P2/app/mprcontents"; : > "$P2/app/Shop.mpr"
page "$P2/app/theme/web/index.html"; page "$P2/app/deployment/web/index.html"; page "$P2/app/mprcontents/b.html"
check_layout two-tree "$P2"
S2="$(section "$P2/architecture/progress-report.html")"
hasnt "$S2" "app/\|theme\|deployment" "two-tree: nothing from the app tree is listed"

echo "P6 Windows hrefs"
"$PY" - "$ROOT/project-bin/progress-report.py" <<'PYEOF' && ok "rel_href: Windows path gives a forward-slash, encoded href" || bad "rel_href: Windows path gives a forward-slash, encoded href"
import sys, ntpath, importlib.util
sp = importlib.util.spec_from_file_location("pr", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
got = m.rel_href("C:\\work\\shop\\design\\wireframes\\order list.html", "C:\\work\\shop\\architecture", ntpath)
assert got == "../design/wireframes/order%20list.html", got
assert m.rel_href("C:\\work\\shop\\index.html", "C:\\work\\shop\\architecture", ntpath) == "../index.html"
assert m.rel_href("C:\\work\\shop\\architecture\\blueprint.html", "C:\\work\\shop\\architecture", ntpath) == "blueprint.html"
PYEOF

echo "P7 a refresh with nothing changed does not rewrite the page"
touch -t 202601011200 "$P1/architecture/progress-report.html"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P1" --refresh >/dev/null 2>&1
"$PY" -c 'import os,sys,time;sys.exit(0 if time.localtime(os.path.getmtime(sys.argv[1])).tm_year==2026 and time.localtime(os.path.getmtime(sys.argv[1])).tm_yday==1 else 1)' "$P1/architecture/progress-report.html" \
  && ok "unchanged refresh leaves the page alone" || bad "unchanged refresh leaves the page alone"
page "$P1/design/wireframes/screen-13.html"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P1" --refresh >/dev/null 2>&1
has "$(section "$P1/architecture/progress-report.html")" "<summary>13 pages" "a new page does rewrite it"

echo "P8 no pages yet"
P3="$WORK/bare"; mkplan "$P3"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P3" --html --quiet >/dev/null 2>&1
has "$(section "$P3/architecture/progress-report.html")" "No HTML pages found yet" "an empty project says so"
grep -q "<a href='#pages'>Pages</a>" "$P3/architecture/progress-report.html" && ok "stage nav links to the section" || bad "stage nav links to the section"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
