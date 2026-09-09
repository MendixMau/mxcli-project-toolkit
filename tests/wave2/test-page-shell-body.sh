#!/bin/bash
# test-page-shell-body.sh — pin check-page-shell.sh's two blind spots.
#
# The script had NO fixture at all, which is why both defects below sat in it: it is
# routed baseline for mdl/gate/review, installed into every project, and until
# 2026-09-09 it had never passed once on a project whose wireframes are named after the
# SOURCE screens rather than the target pages.
#
# 1. IT COULD NOT RESOLVE ITS OWN INPUT. The wireframe path was hardcoded as
#    `design/wireframes/<PageName>.html`. Wireframes drawn from a legacy system are named
#    after that system's screens (`moc-project-detail.html`) while Mendix pages are named
#    in Mendix convention (`MOCProject_Detail`). Measured: 15 wireframes, 8 built pages,
#    "no wireframe" reported for every page, exit 2. A check that cannot find its input on
#    a whole class of project is a check that gets switched off.
#
# 2. IT COULD NOT BOUND THE PAGE BODY. "To the closing brace at column 0" reads the rest of
#    the FILE for a page whose body is on one line, so a nav-shell script with five such
#    stubs reported "declares 5 H1 titles; its wireframe draws one" for the first page —
#    the count for the whole file. That is the worse kind of false positive: it fires on
#    correct code, it cites a real rule, and the fix it asks for would break four pages.
#    Two line-based repairs were tried and each broke the other case, which is why the
#    extractor now counts characters and tracks parens. Both cases are pinned here, in the
#    same file, because that is the pair that has to hold at once.
#
# Usage: bash test-page-shell-body.sh [path-to-check-page-shell.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/check-page-shell.sh}"

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

[ -x "$SUT" ] || { printf '%s is not executable\n' "$SUT" >&2; exit 2; }

# A wireframe with one <h1> and no page column, so only the H1 checks can fire.
wireframe() {
  mkdir -p "$1/design/wireframes"
  cat > "$1/design/wireframes/$2" <<'EOF'
<html><body>
<div class="wf-head"><div><h1>A screen</h1><p class="sub">purpose</p></div></div>
</body></html>
EOF
}

proj() { d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d/mdlsource"; printf '%s' "$d"; }
run()  { ( cd "$1" && bash "$SUT" mdlsource/pages.mdl 2>&1 ); }
code() { ( cd "$1" && bash "$SUT" mdlsource/pages.mdl >/dev/null 2>&1; printf '%s' "$?" ); }

printf 'test-page-shell-body: %s\n' "$SUT"

# ── 1. five one-line bodies in one file: each page's H1 is its own ───────────────────────
d="$(proj oneline)"
for w in One.html Two.html Three.html Four.html Five.html; do wireframe "$d" "$w"; done
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.One
  (Title: 'One', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'One', RenderMode: H1) } }

CREATE OR REPLACE PAGE MOC.Two
  (Title: 'Two', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Two', RenderMode: H1) } }

CREATE OR REPLACE PAGE MOC.Three
  (Title: 'Three', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Three', RenderMode: H1) } }

CREATE OR REPLACE PAGE MOC.Four
  (Title: 'Four', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Four', RenderMode: H1) } }

CREATE OR REPLACE PAGE MOC.Five
  (Title: 'Five', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Five', RenderMode: H1) } }
EOF
out="$(run "$d")"
check "five correct one-line pages exit 0"        "$(code "$d")" "0"
hasnt "does not report 5 H1s on the first page"    "$out" "declares 5 H1"
hasnt "does not report any multiple-H1 violation"  "$out" "H1 titles; its wireframe draws one"
has   "counted all five pages"                     "$out" "5 page(s)"

# ── 2. a multi-line declaration whose Params carry a brace ──────────────────────────────
d="$(proj params)"
wireframe "$d" "Edit.html"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.Edit
  (
    Title: 'Edit',
    Layout: MOC.App_Default,
    Folder: 'F',
    Params: { $Template: MOC.Thing }
  )
  {
    HEADER hdrEdit {
      DYNAMICTEXT h1Edit (Content: 'Edit', RenderMode: H1)
    }
  }
EOF
out="$(run "$d")"
check "a Params brace does not end the body early" "$(code "$d")" "0"
hasnt "finds the H1 that is there"                 "$out" "has no RenderMode: H1 title block"

# ── 3. and the rule still FIRES when the H1 really is missing ───────────────────────────
d="$(proj noh1)"
wireframe "$d" "Bare.html"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.Bare
  (Title: 'Bare', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Bare', Class: 'h1') } }
EOF
out="$(run "$d")"
check "a Class-only title still violates"          "$(code "$d")" "1"
has   "names the missing render mode"              "$out" "has no RenderMode: H1 title block"

# ── 4. two H1s in ONE body is still a violation ─────────────────────────────────────────
d="$(proj twoh1)"
wireframe "$d" "Double.html"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.Double
  (Title: 'Double', Layout: MOC.App_Default, Folder: 'F')
  {
    HEADER hdr {
      DYNAMICTEXT h1a (Content: 'One', RenderMode: H1)
      DYNAMICTEXT h1b (Content: 'Two', RenderMode: H1)
    }
  }
EOF
out="$(run "$d")"
check "two H1s in one page still violate"          "$(code "$d")" "1"
has   "reports the real count"                     "$out" "declares 2 H1 titles"

# ── 5. PAGE-MAP.tsv resolves a source-named wireframe ───────────────────────────────────
d="$(proj map)"
wireframe "$d" "moc-project-detail.html"
printf '# comment\n\nMOCProject_Detail\tmoc-project-detail.html\n' > "$d/design/wireframes/PAGE-MAP.tsv"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.MOCProject_Detail
  (Title: 'Project', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Project', RenderMode: H1) } }
EOF
out="$(run "$d")"
check "a mapped wireframe resolves"                "$(code "$d")" "0"
has   "says the map is in use, with a count"       "$out" "PAGE-MAP.tsv in use - 1 row(s)"

# ── 6. the map cannot hide a page by omission ───────────────────────────────────────────
d="$(proj mapomit)"
wireframe "$d" "moc-project-detail.html"
printf 'MOCProject_Detail\tmoc-project-detail.html\n' > "$d/design/wireframes/PAGE-MAP.tsv"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.SomethingElse
  (Title: 'Else', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Else', RenderMode: H1) } }
EOF
out="$(run "$d")"
# Exit 2, not 1: the page is reported AND zero pages were inspectable, and the script
# treats "inspected nothing" as its own non-pass. Both are failures; what matters is
# that it is not 0 and that the report names the map.
check "an unmapped page is still a miss"           "$(code "$d")" "2"
has   "names the map in the report"                "$out" "not named in design/wireframes/PAGE-MAP.tsv"

# ── 7. a stale map row is reported ──────────────────────────────────────────────────────
d="$(proj mapstale)"
wireframe "$d" "moc-project-detail.html"
printf 'MOCProject_Detail\tmoc-project-detail.html\nGone\tdeleted-wireframe.html\n' \
  > "$d/design/wireframes/PAGE-MAP.tsv"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.MOCProject_Detail
  (Title: 'Project', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Project', RenderMode: H1) } }
EOF
out="$(run "$d")"
check "a stale map row fails the run"              "$(code "$d")" "1"
has   "names the missing wireframe"                "$out" "deleted-wireframe.html, which does not exist"

# ── 8. the per-line opt-out is honoured, and needs no wireframe ─────────────────────────
d="$(proj optout)"
mkdir -p "$d/design/wireframes"
wireframe "$d" "Other.html"
cat > "$d/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE MOC.DevOnly  -- page-shell-ok: developer-facing diagnostic, not a product screen
  (Title: 'Dev', Layout: MOC.App_Default, Folder: 'F')
  { HEADER hdr { DYNAMICTEXT h1 (Content: 'Dev', Class: 'h1') } }
EOF
check "an opted-out page is skipped entirely"      "$(code "$d")" "2"
out="$(run "$d")"
has   "and inspecting nothing is NOT a pass"       "$out" "NOT a pass"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
