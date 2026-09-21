#!/usr/bin/env bash
# test-build-plan-json.sh: pin project-bin/build-plan-status.sh --json.
#
# Field observation 2026-09-16, a language learning app conversion: architecture/build-plan.md
# carried 7 phases with full Step-5 row tables and claims blocks, and mdlsource/ was flat, so
# View A ("no phase folders found") and the --html render were honestly empty while the plan was
# not. The markdown was the only record of phase state, and nothing could read it. --json writes
# architecture/build-plan.json from the markdown's Phase headings, row tables and claims blocks,
# so a viewer (MXTK Studio's Plan room) builds its view from data instead of embedding HTML.
# What is pinned here, in the order a reviewer would ask:
#
#   T1  without --json no build-plan.json appears, and stdout/exit are as before.
#   T2  --json writes a file a real JSON parser accepts, for the real shape: `### Phase N <dash> Name
#       *(note)*` headings, the 7-column row table, `claims:` blocks with and without a BRD id.
#   T3  a Produces cell containing a double quote, a backslash and an escaped pipe survives as
#       valid JSON with the text intact. This is the condition that rules out shell string
#       concatenation: one real project has such a cell, and an invalid file makes the viewer
#       show nothing while the file looks present.
#   T4  a plan whose phases carry no claims block still produces a file: claims is null (no
#       block), not [] (a block with nothing in it) and not an invented list.
#   T5  a plan with no Phase headings at all writes NO file, exits 0, and says so on stdout.
#   T6  an unexpected table shape under a Phase heading is degraded (steps [], a warning naming
#       the phase), never a non-zero exit. Also the variants other real plans use: a middle dot
#       after the phase number, an inline Claims column (warned, not extracted), an unfenced
#       claims block, and "Phase order" / "Phase gates" headings that are prose, not phases.
#   T7  --json and --html together write both files.
#   T8  the JSON is a build product, not a committed artifact: the first --json run in a git
#       project adds /architecture/build-plan.json to .gitignore (the snapshot-mpr.sh rule, a
#       producer guarantees its own output is ignored), a second run adds nothing, and a run
#       without --json never touches .gitignore.
#   T9  the "Phase N — Name" labels brd-to-build-plan.md Step 5 shows inside a fenced code
#       block — a plan-file listing, not a heading — are prose, not Phase headings (HEADING
#       requires a leading `#`), so a plan carrying only that shape is the same as a plan with
#       none: no file, exit 0, "no Phase headings" on stdout. Pinned because Step 5's own
#       worked example used to be exactly this shape until this PR fixed it to real headings.
#
# Usage: bash tests/wave2/test-build-plan-json.sh /path/to/build-plan-status.sh

set -uo pipefail

SCRIPT="${1:?usage: bash tests/wave2/test-build-plan-json.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-plan-json.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
if [ -z "$PY" ]; then
  echo "SKIP: no Python 3 found; the --json flag needs one and so does this fixture's parser."
  echo "PASS=0 FAIL=0"
  exit 0
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# jq-like probe over the written file: prints the python expression's value, or "PARSE-ERROR".
q() { "$PY" -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception as e:
    print("PARSE-ERROR", e); sys.exit(0)
print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }

new_project() {
  local p="$WORK/$1"
  mkdir -p "$p/architecture"
  ( cd "$p" && git init -q . )
  echo "$p"
}

# ── T1 + T2 + T3: the real shape ──────────────────────────────────────────
P1="$(new_project real)"
cat > "$P1/architecture/build-plan.md" <<'MD'
# Build Plan — Sample

## Step 5 — Numbered script sequence

Row schema: `# | Kind | Step | Produces/Proves | Depends on | Skills | State`.

### Phase 0 — App Scaffold *(built earlier — retroactive record)*

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 0.1 | BUILD | `mdlsource/domain-model.mdl` | 12 entities, 4 enumerations | — | generate-domain-model | **built** |
| 0.2 | PROVE | SQL integrity checks | every Question has exactly 1 correct option | 0.1 | verify-with-oql | **built** — done at authoring time |

No claims blocks — pre-dates this plan.

### Phase 1 — Home + Reading *(built — round B1. Proven except LOOK, pending a person)*

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1.1 | BRIEF | check module brief | brief covers both | 0.2 | module-brief | **built** |
| 1.2 | PROVE | J-01 journey walk | **Proven.** answered item 1 ("verify", correct), showed "1 / 100% / —" \| backslash here: C:\tmp | 1.1 | journey-proof, test-microflows | **built** — 2026-09-15 |
| 1.3 | HARNESS | LOOK pass | every page assessed | 1.2 | module-review | **pending a person** — not run this turn by design |

claims: (F001, F002 — written retrospectively)
```
  /useCases/* (2)          [F001]
  /pages/* (1)             [F002]
  /pages/0/buildComposition/rowClick  [F002]
```

**Sweep denominator claim:** N of N — not yet swept.

### Phase 3 — Listening *(not built — F003)*

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 3.1 | BRIEF | extend module brief | row already present above | 1.3 | module-brief | not built |
| 3.2 | BUILD | `Listening_Web` page | page per wireframe | 3.1 | create-page | not built |

claims:
```
  /useCases/* (4)
  /domainEntities/* (6)
```
LEDGERED (Table 2): `/microflows/*` (3) — provenance, already claimed under Phase 1.

---

## Step 7 — Demo user / role mapping

| Target role | Demo user | Notes |
|---|---|---|
| `Learner` | `demo_user` | Used for every happy-path RUN row above |
MD

OUT1="$(bash "$SCRIPT" "$P1" 2>&1)"; RC1=$?
J1="$P1/architecture/build-plan.json"
if [ "$RC1" -eq 0 ] && [ ! -f "$J1" ]; then ok "T1 no --json: exit 0 and no build-plan.json written"; else bad "T1 no --json: rc=$RC1 file-present=$([ -f "$J1" ] && echo yes || echo no)"; fi
case "$OUT1" in *"build-plan.json"*) bad "T1 stdout mentions build-plan.json without the flag" "$OUT1" ;; *) ok "T1 stdout unchanged without the flag" ;; esac

OUT2="$(bash "$SCRIPT" "$P1" --json 2>&1)"; RC2=$?
[ "$RC2" -eq 0 ] && ok "T2 --json exits 0" || bad "T2 --json rc=$RC2" "$OUT2"
[ -f "$J1" ] && ok "T2 build-plan.json written" || bad "T2 build-plan.json missing" "$OUT2"
case "$OUT2" in *"wrote architecture/build-plan.json"*) ok "T2 stdout names the written file" ;; *) bad "T2 stdout does not name the written file" "$OUT2" ;; esac
[ "$(q "$J1" 'len(d["phases"])')" = "3" ] && ok "T2 three phases parsed (0, 1, 3)" || bad "T2 phase count" "$(q "$J1" 'd["phases"]')"
[ "$(q "$J1" 'd["phases"][1]["id"]+"|"+d["phases"][1]["name"]')" = "1|Home + Reading" ] && ok "T2 phase id and name split at the dash, note stripped" || bad "T2 phase id/name" "$(q "$J1" 'd["phases"][1]')"
[ "$(q "$J1" 'd["phases"][1]["note"]')" = "built — round B1. Proven except LOOK, pending a person" ] && ok "T2 heading annotation kept verbatim as note" || bad "T2 note" "$(q "$J1" 'd["phases"][1]["note"]')"
[ "$(q "$J1" 'd["phases"][0]["note"]')" != "None" ] && ok "T2 phase 0 note present" || bad "T2 phase 0 note missing"
[ "$(q "$J1" 'len(d["phases"][1]["steps"])')" = "3" ] && ok "T2 phase 1 has 3 steps" || bad "T2 phase 1 step count" "$(q "$J1" 'd["phases"][1]["steps"]')"
[ "$(q "$J1" 'd["phases"][1]["steps"][1]["dependsOn"]')" = "['1.1']" ] && ok "T2 dependsOn is a list" || bad "T2 dependsOn" "$(q "$J1" 'd["phases"][1]["steps"][1]["dependsOn"]')"
[ "$(q "$J1" 'd["phases"][0]["steps"][0]["dependsOn"]')" = "[]" ] && ok "T2 a dash in Depends on is an empty list" || bad "T2 dash dependsOn" "$(q "$J1" 'd["phases"][0]["steps"][0]["dependsOn"]')"
[ "$(q "$J1" 'd["phases"][1]["steps"][1]["skills"]')" = "['journey-proof', 'test-microflows']" ] && ok "T2 skills split on comma" || bad "T2 skills" "$(q "$J1" 'd["phases"][1]["steps"][1]["skills"]')"
[ "$(q "$J1" 'd["phases"][1]["steps"][2]["state"]')" = "pending a person — not run this turn by design" ] && ok "T2 state cell verbatim, bold markers removed" || bad "T2 state cell" "$(q "$J1" 'd["phases"][1]["steps"][2]["state"]')"
[ "$(q "$J1" 'd["phases"][1]["steps"][1]["kind"]')" = "PROVE" ] && ok "T2 kind column" || bad "T2 kind" "$(q "$J1" 'd["phases"][1]["steps"][1]')"
[ "$(q "$J1" 'd["phases"][1]["claims"]')" = "[{'pointer': '/useCases/*', 'count': 2, 'brd': 'F001'}, {'pointer': '/pages/*', 'count': 1, 'brd': 'F002'}, {'pointer': '/pages/0/buildComposition/rowClick', 'count': None, 'brd': 'F002'}]" ] && ok "T2 claims with BRD ids; a bare pointer (the skill's leaf form) has count null" || bad "T2 claims phase 1" "$(q "$J1" 'd["phases"][1]["claims"]')"
[ "$(q "$J1" 'd["phases"][1]["claimsNote"]')" = "F001, F002 — written retrospectively" ] && ok "T2 claims parenthetical kept as claimsNote" || bad "T2 claimsNote" "$(q "$J1" 'd["phases"][1]["claimsNote"]')"
[ "$(q "$J1" 'd["phases"][2]["claims"]')" = "[{'pointer': '/useCases/*', 'count': 4, 'brd': None}, {'pointer': '/domainEntities/*', 'count': 6, 'brd': None}]" ] && ok "T2 claims without a BRD id carry brd null, not a guess from the heading" || bad "T2 claims phase 3" "$(q "$J1" 'd["phases"][2]["claims"]')"
[ "$(q "$J1" 'd["phases"][0]["claims"]')" = "None" ] && ok "T2 phase with no claims block has claims null" || bad "T2 claims phase 0" "$(q "$J1" 'd["phases"][0]["claims"]')"
[ "$(q "$J1" 'd["phases"][0]["state"]')" = "built" ] && ok "T2 rollup: every step built => built" || bad "T2 rollup phase 0" "$(q "$J1" 'd["phases"][0]["state"]')"
[ "$(q "$J1" 'd["phases"][1]["state"]')" = "pending a person" ] && ok "T2 rollup: only a pending-a-person step left => pending a person" || bad "T2 rollup phase 1" "$(q "$J1" 'd["phases"][1]["state"]')"
[ "$(q "$J1" 'd["phases"][2]["state"]')" = "not built" ] && ok "T2 rollup: every step not built => not built" || bad "T2 rollup phase 3" "$(q "$J1" 'd["phases"][2]["state"]')"
[ "$(q "$J1" 'd["source"]')" = "architecture/build-plan.md" ] && ok "T2 source recorded" || bad "T2 source" "$(q "$J1" 'd')"
# Step 7's table sits after the last phase, behind a `## Step 7` heading: it must not be swallowed.
[ "$(q "$J1" 'len(d["phases"][2]["steps"])')" = "2" ] && ok "T2 a later non-phase table is not swallowed into the last phase" || bad "T2 phase 3 step count" "$(q "$J1" 'd["phases"][2]["steps"]')"

PROD="$(q "$J1" 'd["phases"][1]["steps"][1]["produces"]')"
case "$PROD" in
  PARSE-ERROR*) bad "T3 file did not parse as JSON" "$PROD" ;;
  *'("verify", correct)'*'"1 / 100% / —"'*'| backslash here: C:\tmp'*) ok "T3 double quotes, an escaped pipe and a backslash survive with the text intact" ;;
  *) bad "T3 produces cell text altered" "$PROD" ;;
esac

# ── T4: no claims blocks anywhere ─────────────────────────────────────────
P4="$(new_project noclaims)"
cat > "$P4/architecture/build-plan.md" <<'MD'
# Build Plan

## Phase 1: Core

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1.1 | BUILD | domain | entities | - | mdl-entities | built |
| 1.2 | BUILD | pages | pages | 1.1 | create-page | not built |

## Phase 2 - Extras

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 2.1 | BUILD | reports | a report | 1.2 | create-page | not built |
MD
OUT4="$(bash "$SCRIPT" "$P4" --json --quiet 2>&1)"; RC4=$?
J4="$P4/architecture/build-plan.json"
[ "$RC4" -eq 0 ] && [ -f "$J4" ] && ok "T4 no-claims plan still writes a file, exit 0" || bad "T4 rc=$RC4" "$OUT4"
[ -z "$OUT4" ] && ok "T4 --quiet prints nothing" || bad "T4 --quiet printed" "$OUT4"
[ "$(q "$J4" '[p["claims"] for p in d["phases"]]')" = "[None, None]" ] && ok "T4 claims null on every phase, nothing invented" || bad "T4 claims" "$(q "$J4" 'd["phases"]')"
[ "$(q "$J4" '[p["id"]+"|"+p["name"] for p in d["phases"]]')" = "['1|Core', '2|Extras']" ] && ok "T4 colon and hyphen separators, level-2 headings, both accepted" || bad "T4 headings" "$(q "$J4" 'd["phases"]')"
[ "$(q "$J4" 'd["phases"][0]["state"]')" = "in progress" ] && ok "T4 rollup: mixed built and not built => in progress" || bad "T4 rollup" "$(q "$J4" 'd["phases"][0]["state"]')"

# ── T5: no Phase headings at all ──────────────────────────────────────────
P5="$(new_project nophases)"
cat > "$P5/architecture/build-plan.md" <<'MD'
# Build Plan

## Step 1 — Module dependency graph

| Module | Dep. order | Test shape | Calls out? |
|---|---|---|---|
| `Core` | 1 | UI + Data | no |
MD
OUT5="$(bash "$SCRIPT" "$P5" --json 2>&1)"; RC5=$?
[ "$RC5" -eq 0 ] && ok "T5 no phases: exit 0" || bad "T5 rc=$RC5" "$OUT5"
[ ! -f "$P5/architecture/build-plan.json" ] && ok "T5 no phases: no file written" || bad "T5 a file was written for a plan with no phases" "$(cat "$P5/architecture/build-plan.json")"
case "$OUT5" in *"no Phase headings"*) ok "T5 stdout says why nothing was written" ;; *) bad "T5 stdout silent about the missing file" "$OUT5" ;; esac

P5b="$(new_project noplan)"
OUT5b="$(bash "$SCRIPT" "$P5b" --json 2>&1)"; RC5b=$?
[ "$RC5b" -eq 0 ] && [ ! -f "$P5b/architecture/build-plan.json" ] && ok "T5 no build-plan.md at all: exit 0, no file" || bad "T5 no build-plan.md: rc=$RC5b" "$OUT5b"

# ── T6: unexpected table shape under a Phase heading ──────────────────────
P6="$(new_project oddtable)"
cat > "$P6/architecture/build-plan.md" <<'MD'
## Phase 1 — Odd

| Script | Owner | Done? |
|---|---|---|
| 01-domain.mdl | me | yes |

claims:
```
  N/A — infrastructure row, ledgered as interpretation
```

## Phase order at a glance

prose, not a phase

## Phase 2 · Dotted *(a middle dot after the number, seen on three real plans)*

| # | Kind | Step | Produces / Proves | Depends on | Skills | Claims | State |
|---|---|---|---|---|---|---|---|
| 2.1 | BUILD | thing | a thing | 1.1 | create-page | /pages/* (1) | built |

claims:
  /pages/0/buildComposition/rowClick
  /pages/0/buildComposition/gridColumns/* (7)
LEDGERED (Table 2): the rest, deferred.

## Phase gates (run after the last script in each phase)

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| g.1 | PROVE | gate | clean | - | check-syntax | built |

## Phase 3 — Nested

### 3.1 · the table sits under a per-step sub-heading

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 3.1 | BUILD | nested | a thing | 2.1 | create-page | built |

## Phase 4 — Prose only

Steps written as paragraphs, no table anywhere.

claims:
  F001/domainEntities/Dashboard/attributes/* (3)
MD
OUT6="$(bash "$SCRIPT" "$P6" --json --quiet 2>&1)"; RC6=$?
J6="$P6/architecture/build-plan.json"
[ "$RC6" -eq 0 ] && [ -f "$J6" ] && ok "T6 odd table: exit 0, file written" || bad "T6 rc=$RC6" "$OUT6"
[ "$(q "$J6" 'd["phases"][0]["steps"]')" = "[]" ] && ok "T6 odd table: steps [] rather than misread columns" || bad "T6 steps" "$(q "$J6" 'd["phases"][0]["steps"]')"
[ "$(q "$J6" 'd["phases"][0]["state"]')" = "unknown" ] && ok "T6 odd table: phase state unknown, not guessed" || bad "T6 state" "$(q "$J6" 'd["phases"][0]["state"]')"
[ "$(q "$J6" 'd["phases"][0]["claims"]')" = "[]" ] && ok "T6 a claims block with no pointer rows is [] (block present, nothing parsed)" || bad "T6 claims" "$(q "$J6" 'd["phases"][0]["claims"]')"
[ "$(q "$J6" 'any("Phase 1" in w and "table" in w for w in d["warnings"])')" = "True" ] && ok "T6 warning names the phase and the table" || bad "T6 table warning" "$(q "$J6" 'd["warnings"]')"
[ "$(q "$J6" 'any("Phase 1" in w and "N/A" in w for w in d["warnings"])')" = "True" ] && ok "T6 warning quotes the unparsed claims line" || bad "T6 claims warning" "$(q "$J6" 'd["warnings"]')"
[ "$(q "$J6" '[p["id"]+"|"+p["name"] for p in d["phases"]]')" = "['1|Odd', '2|Dotted', '3|Nested', '4|Prose only']" ] && ok "T6 middle-dot heading is a phase; 'Phase order' and 'Phase gates' headings are not" || bad "T6 headings" "$(q "$J6" 'd["phases"]')"
[ "$(q "$J6" '[s["number"] for s in d["phases"][2]["steps"]]')" = "['3.1']" ] && ok "T6 a table under a deeper sub-heading still belongs to its phase" || bad "T6 nested table" "$(q "$J6" 'd["phases"][2]')"
[ "$(q "$J6" 'any("Phase 4" in w and "no row table" in w for w in d["warnings"])')" = "True" ] && ok "T6 a phase with no table says so in warnings" || bad "T6 no-table warning" "$(q "$J6" 'd["warnings"]')"
[ "$(q "$J6" 'd["phases"][3]["claims"]')" = "[]" ] && [ "$(q "$J6" 'any("Phase 4" in w and "F001/domainEntities" in w for w in d["warnings"])')" = "True" ] && ok "T6 an unfenced claims block in another convention is [] plus a warning quoting the line" || bad "T6 other-convention claims" "$(q "$J6" 'd["warnings"]')"
[ "$(q "$J6" 'd["phases"][1]["steps"][0]["number"]+"|"+d["phases"][1]["steps"][0]["state"]')" = "2.1|built" ] && ok "T6 the 8-column table still maps by header name" || bad "T6 8-column table" "$(q "$J6" 'd["phases"][1]["steps"]')"
[ "$(q "$J6" 'any("Phase 2" in w and "Claims column" in w for w in d["warnings"])')" = "True" ] && ok "T6 inline Claims column is warned about, not silently dropped" || bad "T6 Claims column warning" "$(q "$J6" 'd["warnings"]')"
[ "$(q "$J6" 'd["phases"][1]["claims"]')" = "[{'pointer': '/pages/0/buildComposition/rowClick', 'count': None, 'brd': None}, {'pointer': '/pages/0/buildComposition/gridColumns/*', 'count': 7, 'brd': None}]" ] && ok "T6 unfenced claims block ends at the first non-pointer line, LEDGERED prose not a warning" || bad "T6 unfenced claims" "$(q "$J6" 'd["phases"][1]["claims"]')"
[ "$(q "$J6" 'any("LEDGERED" in w for w in d["warnings"])')" = "False" ] && ok "T6 prose after an unfenced block is not reported" || bad "T6 LEDGERED warned" "$(q "$J6" 'd["warnings"]')"

# ── T7: --json with --html ────────────────────────────────────────────────
OUT7="$(bash "$SCRIPT" "$P1" --json --html --quiet 2>&1)"; RC7=$?
[ "$RC7" -eq 0 ] && [ -f "$P1/architecture/build-plan.html" ] && [ -f "$J1" ] && ok "T7 --json and --html both write" || bad "T7 rc=$RC7" "$OUT7"

# ── T8: a build product is gitignored by its producer ─────────────────────
GI1="$P1/.gitignore"
[ "$(grep -c '^/architecture/build-plan\.json$' "$GI1" 2>/dev/null)" = "1" ] && ok "T8 first --json run added /architecture/build-plan.json to .gitignore" || bad "T8 .gitignore line missing or duplicated" "$(cat "$GI1" 2>/dev/null)"
case "$OUT2" in *"added /architecture/build-plan.json to .gitignore"*) ok "T8 stdout says the line was added" ;; *) bad "T8 stdout silent about .gitignore" "$OUT2" ;; esac
bash "$SCRIPT" "$P1" --json --quiet >/dev/null 2>&1
[ "$(grep -c '^/architecture/build-plan\.json$' "$GI1")" = "1" ] && ok "T8 a second run adds nothing (idempotent)" || bad "T8 .gitignore line duplicated" "$(cat "$GI1")"
( cd "$P1" && git check-ignore -q architecture/build-plan.json ) && ok "T8 git itself now ignores the file" || bad "T8 git does not ignore architecture/build-plan.json"
P8="$(new_project nojson)"
cp "$P1/architecture/build-plan.md" "$P8/architecture/"
printf 'sources/\n' > "$P8/.gitignore"
bash "$SCRIPT" "$P8" --quiet >/dev/null 2>&1
[ "$(cat "$P8/.gitignore")" = "sources/" ] && ok "T8 without --json .gitignore is untouched" || bad "T8 .gitignore changed without --json" "$(cat "$P8/.gitignore")"

# ── T9: fenced plain-text "Phase N — Name" lines are prose, not headings ──
P9="$(new_project fencedplain)"
cat > "$P9/architecture/build-plan.md" <<'MD'
# Build Plan

```
Phase 1 — App Scaffold
  01-app-scaffold.mdl            <- module structure, navigation shell, demo users

Phase 2 — UI Scaffold  (if StyleGallery = Yes)
  design/brand.md                <- brand research
```

Prose after the fence. No real Phase heading anywhere in this file.
MD
OUT9="$(bash "$SCRIPT" "$P9" --json 2>&1)"; RC9=$?
[ "$RC9" -eq 0 ] && ok "T9 fenced plain-text phases: exit 0" || bad "T9 rc=$RC9" "$OUT9"
[ ! -f "$P9/architecture/build-plan.json" ] && ok "T9 fenced plain-text phases: no file written" || bad "T9 a file was written for fenced plain-text phase labels" "$(cat "$P9/architecture/build-plan.json")"
case "$OUT9" in *"no Phase headings"*) ok "T9 stdout says why nothing was written" ;; *) bad "T9 stdout silent about the missing file" "$OUT9" ;; esac

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
