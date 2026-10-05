# Context cost research — how much the toolkit makes every session read (2026-09-30)

**Status:** research done, nothing changed yet beyond the PRs listed in §3. The next step is a
test build (§9) that measures the cut before it becomes the default.

**Measure used throughout:** tokens = characters / 4, taken from master `8abd614` (plus the
open skill-removal PR where noted). Numbers are per file, as loaded at session start.

## 1. TLDR

- A build helper starts by reading **about 109k tokens of skills**. It needs about **15–20k**.
- The cause is simple: the routing table's `agents` column only filters the agent stub files.
  The project's `CLAUDE.local.md` baseline view, `routing_baseline_pack` and gate-check's stage
  map filter **by stage only**. So a page helper at Stage 5 gets the lead's rows, the test
  agent's rows and the reviewer's rows too.
- The biggest single file is the runbook (24k). A page helper needs at most 1.2k of it.
- Five small rule files (10.4k together) can become one always-on card of about 1.3k.
- 19 of 84 probed preflight/microflow rules are still needed; the rest are fixed in the current
  mxcli, or caught by `mxcli check` / `mx check` anyway (§6).
- UI: the screenshot loop is what moves page quality most. Whether the page preflight is still
  worth its tokens next to the loop is not proven either way — tomorrow's build tests it (§8).

## 2. Why this matters (evidence)

| Observation | Number | Source |
|---|---|---|
| Field comparison, direct-tool build | one session, 515 UI calls | field notes |
| Field comparison, toolkit build | 38 helpers, **each** re-paying a start pack of 145–215k; 1,507 UI calls | field notes, transcripts |
| Toolkit build, first UI round | 64% of UI calls; about 20% of tokens went to repairing round-1 regressions | field notes |
| Screenshot loop | wireframe fidelity 1 → 15 | field notes |
| Everyday single sessions on a laptop | toolkit file reads were only 4% of tokens; session length, the 1M window and command output dominate | `bin/context-audit.sh` over real transcripts |

The conclusion holds for orchestrated builds: every helper re-reads the same pack, so the pack
size multiplies by the number of helpers. For a single long session the pack matters less than
session length, which the auto-compact window (§10) addresses.

## 3. Already done

| PR | What | Effect |
|---|---|---|
| #182 (merged) | `learned-mcp-patterns.md` off the Stage 5 always-on list | Stage 5 pack 121k → 116k |
| #183 (merged) | Routing tables are trigger lists; setup no longer says "read the whole runbook" | Wording only; agents still load by stage |
| #184 (merged) | `bin/context-audit.sh` crash fix | The measuring tool works on older transcripts |
| #185 (merged) | Removes the MCP skill and doc; CLI is the default route; preflight 9.8k → 6.1k, microflow patterns 9.9k → 5.9k; three backwards rules corrected | Stage 5 pack 116k → about 109k |
| §11 step 2 (2026-10-05) | Baseline view gets a Role(s) column and a `lead` token; helpers read only their own rows; per-role counts in `render-routing.sh --check` | Stage 5 per helper: mdl 54k, review 43k, gate 34k, test 33k words (all helpers 68k before) |

## 4. Stage packs today (master `8abd614`)

| Stage | Files | Tokens |
|---|---:|---:|
| P | 8 | 47k |
| 0 | 9 | 49k |
| 1–3 | 8 | 43k |
| 4 | 11 | 58k |
| 5 | 22 | 116k (about 109k with #185) |
| 6 | 13 | 69k |
| 7 | 9 | 44k |

## 5. Per-file plan

"Who" is who should load it at start after the change; everyone else reads it only when its
trigger fires. "After" is the trimmed size.

### Spine and rule files (every stage)

| File | Now | After | Who | Action |
|---|---:|---:|---|---|
| `conversion-runbook.md` | 24.1k | core ~3.3k + per-stage files | ba, architect, lead | Trim 9–11k first (no split); then move §1c dispatch to its own file; then split stage sections. Page helper needs 0–1.2k, gate/test/review ~1.5–2k, Stage 0 lead ~7k |
| `tool-output-is-not-ground-truth.md` | 4.5k | 1.9k on demand | — | Into the card |
| `query-the-model.md` | 2.0k | 1.15k | card | Trim in place; **keep the path** (gate-check, skill-routing.sh, sync-project, 4 fixtures cite it) |
| `skills-over-scripts.md` | 1.6k | 0.75k on demand | test/gate when adding a harness script | Toolkit-authoring rule; out of the consumer baseline |
| `degrade-to-judgement.md` | 1.2k | 0.7k on demand | — | Into the card |
| `retesting-learned-rules.md` | 1.1k | 0.6k on demand | mdl/gate at 5 | Probe half on demand; stamping half is authoring |
| **new** `working-rules` card | — | ~1.3k | all | Replaces the five above as the always-on text |

### Build files (Stage 5)

| File | Now | After | Who | Action |
|---|---:|---:|---|---|
| `learned-mdl-preflight.md` | 9.8k | 6.1k (#185) | mdl | Further split by task later (page rows / microflow rows) |
| `learned-microflow-patterns.md` | 9.9k | 5.9k (#185) | microflow helper | Not for page helpers |
| `ui-preflight-pages.md` | 6.2k | 4.8k — or ~2–3k, or 0 (§8) | page helper, **inlined** | Trim history and repeated numbers; B0 to lead/gate. Size depends on tomorrow's A/B |
| `design-spacing.md` | 2.1k | 1.55k | page helper | Drop §4 (owned by `module-review` 4d) |
| `ui-loop.md` | 3.2k | 1.2k core + 0.65k harness | review, test, lead | Split off the screenshot harness |
| `learned-css-that-never-applied.md` | 2.9k | 1.7k on demand | — | Trigger: "a style change did nothing" |
| `microflow-preflight.md` | 2.9k | 1.45k | microflow helper | Version-specific parts to an appendix |
| `security-is-not-a-later-script.md` | 1.2k | 0.95k | domain helper, gate | Load with any `create entity` |

### Test, review and lead files

| File | Now | After | Who | Action |
|---|---:|---:|---|---|
| `testing-shape.md` | 9.3k | 8.1k | test (review on demand for §4/§7) | Trim §5; keep §4 whole ("do not shorten") |
| `module-review.md` | 8.4k | 6.2k | review, lead | Trim; **do not renumber** (§4b–§4e cited by scripts) |
| `agent-roles.md` | 7.5k | ~3k | lead, at setup only | Template shapes duplicate `agents/*.md` → pointer |
| `interview-protocol.md` | 5.1k | 3.3k | ba, architect, lead | Helpers get one stub line: "return open questions to the main session; never ask or assume". Keep headings "Exec approval is a separate knob" and "Asking on a non-Claude agent" |
| `module-brief.md` | 4.8k | 4.0k | ba, architect | mdl reads the brief itself, not the spec. Keep the line-70 anchor (`coherence-cadence.sh`) |
| `learned-detection-gaps.md` | 4.4k | ~1k core + lookup | all, core only | Register via grep or a `gap-lookup.sh` like `bug-lookup.sh` |
| `module-folder-convention.md` | 2.9k | 1.7k | architect at 4; mdl on demand | Re-probe the blocked-type cells against the current mxcli |
| `checkpoint-template.md` | 3.1k | 1.9k | ba, architect, lead | Close-out table is enforced by `gate-check.sh --closeout` |
| `source-triage.md` | 6.2k | 4.7k | ba (already) | Trim incidents; keep the two script-path strings a fixture greps |
| `teamserver-alignment.md` | 1.3k | 1.1k | whoever pushes (usually lead) | Baseline → on demand |

### On-demand rows whose trigger fires on almost every task

118 rows are on demand, but 10 have triggers so broad that agents load them anyway. The top
three are 24.6k together: `iterative-build-loop` (12.3k), `mdl-cookbook-microflows` (6.8k),
`learned-page-patterns` (5.5k). Each gets a sharper "when X happens" trigger (for example:
cookbook only for a construct `learned-microflow-patterns.md` does not cover; grep the recipe,
do not read the file). Four `agents=all` rows are setup or toolkit-author events
(`company-brain`, `field-run`, `upstream-feedback`, `doctor-triage`) and move to the lead. Four
rows have no trigger word at all and get one.

## 6. Obsolete rules (probe results)

Every preflight and microflow-pattern row was re-run against mxcli v0.24.0 on a scratch app,
with `mxcli check` before exec and `mx check` after.

| File | Rows | Fixed in mxcli | Caught by `mxcli check` | Still needed | Unclear | Advice only |
|---|---:|---:|---:|---:|---:|---:|
| `learned-mdl-preflight.md` | 42 | 17 | 9 | 11 | 2 | 3 |
| `learned-microflow-patterns.md` | 42 | 13 | 9 | 8 | 3 | 9 |

- `mx check` (after the script ran) catches 15 of the 19 still-needed rows. Lint catches none, so
  lint is not a route for these rules yet.
- Routing: fixed → delete; caught by `mxcli check` → delete and require `mxcli check` before
  exec; still needed → keep, in the task file where it applies.
- Three rules were written backwards and are corrected in #185 (association paths need the
  module prefix; set associations from the owner side; GRANT needs qualified role names).

## 7. Start load per helper, after the plan

Skill files only; the stub, project `CLAUDE.md` and tool definitions come on top and are the
same before and after.

| Helper (Stage 5) | Today | After | What it loads |
|---|---:|---:|---|
| Page helper | ~109k | **~16k** | runbook slice 0.9k, card 1.3k, preflight 6.1k, ui-preflight 4.8k, spacing 1.55k, gaps core 1k |
| Microflow / domain helper | ~109k | **~18k** | runbook slice 0.9k, card 1.3k, preflight 6.1k, microflow patterns 5.9k, microflow-preflight 1.45k, security 0.95k, gaps core 1k |
| Test helper | ~109k | **~14k** | runbook slice 1.8k, card 1.3k, testing-shape 8.1k, ui-loop core 1.2k, gaps core 1k |
| Review helper | ~109k | **~12k** | runbook slice 1.8k, card 1.3k, module-review 6.2k, ui-loop core 1.2k, gaps core 1k |
| Lead | ~109k | ~20–25k | runbook core + Stage 5 + dispatch, card, interview, brief spec, checkpoint, teamserver |

With 38 helpers (the field build's count) that is roughly 3.5M fewer tokens read at start per
build. This is an estimate from file sizes; tomorrow's build measures the real number.

## 8. The page preflight and the screenshot loop

The question: the loop over built pages gave the best effect. Is `ui-preflight-pages.md` still
needed?

| Evidence | Says |
|---|---|
| 2026-08-31 A/B (`preflight-skill-baseline-2026-08-31.md`) | Without the skill: median 3 shell violations per page. With it inlined: 1, zero variance. A longer revision (+800 words) did slightly worse. |
| Field build | Round 1 was 64% of UI calls; about 20% of tokens repaired round-1 regressions. The loop lifted wireframe fidelity 1 → 15. |
| Research | Two cross-check rows (page column, page scaffold) are enforced after the fact by `check-page-shell.sh`, and B0 by `check-design-reaches-app.sh`; the report-back block with denominators is what the A/B showed working (5/5 vs 0/5). |

Reading: the loop fixes what the preflight misses, but every miss costs a round. A short
preflight (only the rules no script checks) plus running `check-page-shell.sh` **before** exec
could make round 1 cheaper without adding much start load. That is a hypothesis; §9 variant P tests
it, including the option of dropping the preflight entirely.

Blocking dependency if the preflight is demoted or removed: `bin/gate-check.sh:1287` fails
build-ready when `ui-preflight-pages` is missing from `CLAUDE.local.md`, `sync-project.sh` §2c
has the same check, and `obligations.tsv:122` names `skills/ui-loop.md` as the producer of the
fidelity obligation.

## 9. Test build plan

Same scratch app and module list as the field build, same helper model tier, fresh project
scaffold for each variant.

| Variant | Toolkit | Page drafting |
|---|---|---|
| **Base** | master + #185 | as today |
| **Lean** | lean branch (steps 1–4 of §11 applied) | ui-preflight trimmed (~4.8k), inlined |
| **P-loop** | lean branch | no ui-preflight; build, then loop |
| **P-short** | lean branch | ~2–3k preflight (unchecked rules + report block), `check-page-shell.sh` before exec, then loop |

P-loop and P-short run 3 pages each (the same 3 pages).

**Measure** (per helper and per build): start tokens (`bin/context-audit.sh`), total tokens,
tool calls, `mx check` errors after each exec, UI rounds until the page passes, shell
violations (`check-page-shell.sh`), fidelity score (`page-fidelity.js`), wall time.

**Pass criteria for Lean vs Base:** helper start load down by at least 70%; `mx check` errors,
shell violations and fidelity no worse; total build tokens down.
**For P-loop vs P-short:** the variant with fewer total UI tokens wins if its final fidelity and
shell score are equal; if quality differs, quality wins.

## 10. Side findings

- **Auto-compact window.** `/autocompact 250k` writes `"autoCompactWindow": 250000` to the
  user's `~/.claude/settings.json`, which covers every project on that machine. Cloud sessions
  start from a fresh container, so they need it in the project's committed
  `.claude/settings.json`. Proposal: `init-project.sh` and `sync-project.sh` write it there
  unless a value is already set.
- **Stale line citations.** `bin/lib/artifact-manifest.tsv` lines 74, 81 and 93 cite runbook
  line numbers that have moved; the §"One decision register" links in
  `architecture-blueprint.md` and `modularize-domain.md` are broken.
- `gate-check.sh` already prints per-stage runbook line spans (`runbook_span`), but helpers never
  see that output, so it saves nothing today.

## 11. Order of work

Each step is its own PR, checked with `bin/render-routing.sh --check`, `bin/check-scripts.sh`,
`bin/check-portability.sh` and the leak guard; fixtures only where named, and only when asked.

1. Merge #185.
2. **Agent-filtered view:** add a `lead` token, render the project baseline view per agent,
   update the `render-routing.sh` agent audit. This is what makes every other cut reach helpers.
3. **Working-rules card** plus sharper triggers for the 10 broad on-demand rows.
4. **Runbook trim** (no split), then the `agents` column change to `ba,architect`.
5. **Task packs** (page / microflow / test / review), including the `gate-check.sh:1287` and
   `sync-project.sh` §2c update. Page pack content waits for the §9 page result.
6. Runbook split into per-stage files.
7. Auto-compact default in `init-project.sh` / `sync-project.sh`.
8. Fix the stale artifact-manifest citations and broken section links.

Things every step must keep working: gate-check `runbook_span`, the Surface parser, the
`PROTOCOL_ALWAYS` list, the render-routing SURFACES markers, and the headings and anchors named
in §5.
