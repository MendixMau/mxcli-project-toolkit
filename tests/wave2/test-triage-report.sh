#!/bin/bash
# test-triage-report.sh — pin the Stage 0 triage scaffold and its renderer.
#
# Three things are worth pinning here, and the happy path is only one of them.
#
#   1. THE SCAFFOLD MUST NOT SELF-SIGN. Stage 0's gate asks exactly one question — has a human
#      signed this off — and a template that answers it is worse than no template at all. The
#      same mistake has already been made twice in this toolkit: gate-check.sh:380's own comment
#      records "Confirmed by: [user] on [date]" passing a human-sign-off gate, and
#      init-project.sh's intake heredoc once shipped an answer marker that made a
#      two-seconds-old project PASS Stage P. So: init writes triage.md, and gate-check.sh
#      <project> 0 FAILS on it. That assertion is the reason this file exists.
#
#   2. SYNC MUST NOT CLOBBER WORK. triage.md carries hand-written verdicts a human argued about.
#      It is refreshed only while it is provably an untouched scaffold — the agent-stub contract
#      (marker + placeholder), not a blind copy.
#
# Usage: bash test-triage-report.sh [path-to-triage-report.sh]
#
#   3. THE RENDERER RENDERS, AND REFUSES WHAT IT CANNOT DESCRIBE. Two differing triage.md files
#      is not a page it can honestly draw; a missing one is not an empty page.

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT="$TOOLKIT/bin/init-project.sh"
SYNC="$TOOLKIT/bin/sync-project.sh"
GATE="$TOOLKIT/bin/gate-check.sh"
TR="${1:-$TOOLKIT/bin/triage-report.sh}"

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

# A scaffold with the sign-off actually filled in and the placeholders removed — i.e. what a
# human hands over. MXTK_NO_GUIDE keeps the browser shut; --ignore-sources keeps init off the TTY.
scaffold() {
  MXTK_NO_GUIDE=1 "$INIT" "$1" --ignore-sources >/dev/null 2>&1
}

# A real init runs `mxcli init` and the agent wiring and takes the better part of a minute, so
# it is run TWICE in this file (once for the scaffold, once to prove re-running it is a no-op)
# and every other fixture is a copy of the first. Copying is not a weaker fixture here: what is
# under test downstream is triage.md and the two scripts that read it, and a copied tree is
# byte-identical to the scaffolded one.
clone() { cp -R "$1" "$2"; }

echo "== init scaffolds triage.md, and it does not self-sign =="

P="$TMP/p1"
scaffold "$P"
# Snapshot BEFORE any test mutates $P — every later fixture clones from this, so a test that
# edits its own copy cannot leak into the next one.
PRISTINE="$TMP/pristine"; cp -R "$P" "$PRISTINE"
[ -f "$P/triage.md" ] && ok "init writes triage.md" || bad "init writes triage.md"

OUT=$("$GATE" "$P" 0 2>&1); RC=$?
check "a freshly scaffolded triage.md FAILS Stage 0" "$RC" "1"
has "  and the reason is the unsigned sign-off" "$OUT" "still holds template placeholders"
hasnt "  it is not reported as a pass" "$OUT" "Stage 0 (Triage): PASS"

# The five verdict words and the two-way call live IN the file, because that is where the author
# is typing. This is the VB-USI drift: a hand-written triage invented "Direct read (recommended)"
# as a third option and concluded "Build no extractor".
T=$(cat "$P/triage.md")
has "the five verdicts are stated inline" "$T" "**Extract-only**"
has "  all of them" "$T" "**Unknown**"
has "the extraction decision is two-way" "$T" "two-way call, not three-way"
check "  and has exactly two decision rows" \
  "$(grep -c '^| \*\*\(Reuse existing\|Build new\) pipeline\*\* |' "$P/triage.md")" "2"
has "the coverage matrix carries its real headers" "$T" "| Capability | Extractable? | Mapper -> BRD? | Reliable? | Verdict |"
has "the slice section keeps the skill's rule" "$T" "A slice is an ordering, not an exclusion"
has "  and the skill's format" "$T" "capability -> verdict -> recommended for this slice (yes/no/deferred) -> why"
has "the multi-app flag section is present" "$T" "Architecture Scale Flag"
has "example rows are marked for deletion" "$T" "DELETE ME"

# Idempotent: a second init must not overwrite a triage someone has since filled in.
printf '\nlocal note\n' >> "$P/triage.md"
BEFORE=$(cat "$P/triage.md")
OUT=$(scaffold "$P"; cat "$P/triage.md")
check "re-running init does not overwrite triage.md" "$OUT" "$BEFORE"

echo "== a signed triage passes the same gate =="

P2="$TMP/p2"; clone "$PRISTINE" "$P2"
# Only the sign-off changes. Nothing else about the file is different from the one that failed
# above, which is what makes the failure above attributable to the sign-off and not to noise.
sed 's/^Confirmed by: \[user\] on \[date\].*/Confirmed by: M. Visser on 2026-08-19/' \
  "$P2/triage.md" > "$P2/triage.md.new" && mv "$P2/triage.md.new" "$P2/triage.md"
OUT=$("$GATE" "$P2" 0 2>&1); RC=$?
check "signing it off passes Stage 0" "$RC" "0"
has "  and the signer is named back" "$OUT" "M. Visser"

echo "== sync refreshes an untouched scaffold, and only an untouched one =="

# A project that predates the scaffold has no triage.md at all.
P3="$TMP/p3"; clone "$PRISTINE" "$P3"
rm -f "$P3/triage.md"
OUT=$("$SYNC" "$P3" 2>&1)
has "sync installs a missing triage.md" "$OUT" "Created: triage.md"
[ -f "$P3/triage.md" ] && ok "  and the file is there" || bad "  and the file is there"

# Untouched scaffold whose template has since moved: refreshed wholesale.
printf 'stale scaffold\n<!-- MXTK-TRIAGE-STUB -->\n{{APPLICATION_NAME}}\n' > "$P3/triage.md"
OUT=$("$SYNC" "$P3" 2>&1)
has "sync refreshes an untouched scaffold" "$OUT" "Refreshed: triage.md"
grep -q 'two-way call, not three-way' "$P3/triage.md" \
  && ok "  with the current template" || bad "  with the current template"

# Already current: no churn. (Idempotence — the second run must say nothing about triage.md.)
OUT=$("$SYNC" "$P3" 2>&1)
hasnt "a second sync does not re-refresh it" "$OUT" "Refreshed: triage.md"

# Worked-on file: kept, and said so.
P4="$TMP/p4"; clone "$PRISTINE" "$P4"
cat > "$P4/triage.md" <<'EOF'
# Source Triage: Acme Orders

## Extraction Approach
| Decision | Chosen? | Which pipeline |
|---|---|---|
| **Reuse existing pipeline** | yes | java-angular |
| **Build new pipeline** | no | — |

## Sign-off
Confirmed by: M. Visser on 2026-08-19
EOF
BEFORE=$(cat "$P4/triage.md")
OUT=$("$SYNC" "$P4" 2>&1)
has "sync keeps a triage someone has worked on" "$OUT" "Kept: triage.md has been worked on"
check "  and does not change a byte of it" "$(cat "$P4/triage.md")" "$BEFORE"

# --dry-run writes nothing. This script's own history is why: a run that printed
# "(--dry-run: nothing will be written)" created 11 agent files across 5 real projects.
P5="$TMP/p5"; clone "$PRISTINE" "$P5"
rm -f "$P5/triage.md"
"$SYNC" "$P5" --dry-run >/dev/null 2>&1
[ -f "$P5/triage.md" ] && bad "--dry-run does not write triage.md" || ok "--dry-run does not write triage.md"

echo "== triage-report renders =="

P6="$TMP/p6"; clone "$PRISTINE" "$P6"
sed 's/{{APPLICATION_NAME}}/Acme Orders/' "$P6/triage.md" > "$P6/t" && mv "$P6/t" "$P6/triage.md"
OUT=$("$TR" "$P6" 2>&1); RC=$?
check "rendering a filled triage exits 0" "$RC" "0"
[ -s "$P6/analysis/triage.html" ] && ok "  and writes analysis/triage.html" || bad "  and writes analysis/triage.html"
H=$(cat "$P6/analysis/triage.html")
has "  with a title naming the project" "$H" "<title>Source triage"
has "  the heading survives" "$H" "Acme Orders"
has "  tables become tables" "$H" "<th>Capability</th>"
has "  bold becomes strong" "$H" "<strong>Reuse existing pipeline</strong>"
has "  inline code becomes code" "$H" "<code>skills/source-triage.md</code>"
has "  theme-aware" "$H" "prefers-color-scheme"
has "  honours an explicit theme" "$H" 'data-theme="dark"'
# It renders; it does not grade. A page that announced a verdict would be a second gate.
hasnt "  it prints no verdict of its own" "$H" "PASS"
has "  and says where the verdict comes from" "$H" "gate-check.sh"

# Markdown that is not in the subset must not become markup, and a stray < must not become a tag.
P7="$TMP/p7"; mkdir -p "$P7"
cat > "$P7/triage.md" <<'EOF'
# T
Text with <script>alert(1)</script> and a [link](http://x) in it.
EOF
"$TR" "$P7" --quiet >/dev/null 2>&1
H=$(cat "$P7/analysis/triage.html")
hasnt "html in the source is escaped, not executed" "$H" "<script>alert"
has "  it is shown as text" "$H" "&lt;script&gt;"
has "a link stays literal — the subset is closed" "$H" "[link](http://x)"

OUT=$("$TR" "$P7" --html "$P7/elsewhere.html" --quiet 2>&1)
[ -s "$P7/elsewhere.html" ] && ok "--html redirects the output" || bad "--html redirects the output"
check "  --quiet says nothing on success" "$OUT" ""

echo "== the refusals =="

# Two DIFFERENT triage.md files. This mirrors gate-check.sh's check_stage_0 AMBIGUOUS branch:
# one of them is stale, only a human knows which, and one page cannot describe both.
P8="$TMP/p8"; mkdir -p "$P8/analysis/ws/knowledge-base"
printf '# T\nroot copy\n\n## Sign-off\nConfirmed by: A on 2026-01-01\n'   > "$P8/triage.md"
printf '# T\nnested copy\n\n## Sign-off\nConfirmed by: A on 2026-01-01\n' > "$P8/analysis/ws/triage.md"
OUT=$("$TR" "$P8" 2>&1); RC=$?
check "two differing triage.md files refuse" "$RC" "4"
has "  and both paths are named" "$OUT" "two different triage.md files"
has "  including the nested one" "$OUT" "analysis/ws/triage.md"
# gate-check must be refusing on the same input, or the two have drifted apart.
OUT=$("$GATE" "$P8" 0 2>&1)
has "  gate-check refuses the same shape" "$OUT" "two different triage.md files"

# Byte-identical copies are NOT ambiguous — either one renders the same. Refusing over them
# would be pure cry-wolf, which is the stance resolve_stage_file() settled on.
cp "$P8/triage.md" "$P8/analysis/ws/triage.md"
OUT=$("$TR" "$P8" 2>&1); RC=$?
check "byte-identical copies are not a refusal" "$RC" "0"

# No triage.md at all: exit 3, and say how to get one. Never an empty page.
P9="$TMP/p9"; mkdir -p "$P9"
OUT=$("$TR" "$P9" 2>&1); RC=$?
check "a project with no triage.md exits 3" "$RC" "3"
has "  and says where it looked" "$OUT" "no triage.md (looked in"
has "  and how to make one" "$OUT" "init-project.sh"
[ -e "$P9/analysis/triage.html" ] && bad "  and writes no page" || ok "  and writes no page"

OUT=$("$TR" "$TMP/does-not-exist" 2>&1); RC=$?
check "a missing project dir is a usage error" "$RC" "2"
has "  in this script's voice" "$OUT" "triage-report: not a directory"

OUT=$("$TR" 2>&1); RC=$?
check "no argument is a usage error" "$RC" "2"

OUT=$("$TR" "$P6" --nonsense 2>&1); RC=$?
check "an unknown option is a usage error" "$RC" "2"
has "  and names the option" "$OUT" "unknown option: --nonsense"

echo "== the skill and the template cannot silently diverge =="
#
# Not a diff — the fence in the skill is prose and the template is a working document. What is
# pinned is that the skill POINTS at the template, so the next person to change one is told
# where the other lives.
S=$(cat "$TOOLKIT/skills/source-triage.md")
has "source-triage.md points at the scaffold" "$S" "bin/lib/triage-template.sh"
has "  and at the renderer" "$S" "bin/triage-report.sh"
R=$(cat "$TOOLKIT/skills/conversion-runbook.md")
has "the runbook's Stage 0 Surface row names what generates triage.html" "$R" "\`triage.html\` (\`bin/triage-report.sh"

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
