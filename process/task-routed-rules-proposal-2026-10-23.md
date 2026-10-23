# Research proposal — rules by task, not by stage (A + B + C), 2026-10-23

**Status:** EXPERIMENT on branch `experiment/task-routed-rules`. Nothing here merges until the
behaviour A/B (§5) says the candidate is no worse than master. Base: master `888b4b2`.
**Builds on:** `process/context-cost-research-2026-09-30.md` §11 step 5 ("task packs"), never built.

## 1. Problem

The mdl helper starts every Stage 5 dispatch with **30,443 words / 14 files** of always-read
text (`bin/render-routing.sh --check`, role `mdl`), whatever the step builds. Measured on master:

| Kind of text | Files | Words |
|---|---|---:|
| Page-only | ui-preflight-pages, design-spacing, and three **script sources** read as skills: `page-fidelity.js` (8,274), `check-design-reaches-app.sh` (3,587), `check-page-shell.sh` (3,222) | 19,984 |
| Microflow-only | learned-microflow-patterns, microflow-preflight | 5,439 |
| Mixed | learned-mdl-preflight — its STOP table has 34 rows, **15 of them retired** | 4,111 |
| Every step | module-brief, learned-detection-gaps, tool-output-is-not-ground-truth, … | ~16,000 |

Side finding: a baseline row whose path is a script makes the helper read the whole source,
when what it needs is the header (the usage contract): 15,083 words of code → 2,275 of header.

## 2. A — task packs: the context pack delivers the kind's rules

Built on the branch:
- `bin/lib/task-rules.sh` → `task_rules_pack <root> "<kinds>" [text…]` prints, inlined:
  learned-mdl-preflight with its STOP table filtered to the step's kind
  (`bin/lib/stop-row-kinds.tsv`: page | logic | domain | any | retired; an unmapped row is kept),
  the kind's files (`bin/lib/task-kinds.tsv`; scripts as their header only), and part B's hits.
  Unknown/empty kind → every kind (fail open).
- `project-bin/context-pack.sh` already classified each Build-steps row as page / logic / domain
  and only *named* the files; it now inlines them via the library, printed last so part B sees the
  live DESCRIBE output. A toolkit without the library gets the old reading list.
- `bin/lib/skill-routing.tsv`: the eight kind files go `mdl?` (on demand for mdl only; gate,
  review, test and architect keep them as before; tier stays `baseline`, so gate-check's stage map
  is unchanged).

**Measured start load for the mdl helper, Stage 5 (words):**

| Step kind | Master | Branch: baseline + kind pack | Change |
|---|---:|---:|---:|
| page | 30,443 | 15,992 + 10,719 = 26,711 | −12% |
| logic (microflow) | 30,443 | 15,992 + 8,567 = 24,559 | −19% |
| domain | 30,443 | 15,992 + 2,779 = 18,771 | −38% |

## 3. B — trigger-only rules: a rare rule arrives only when it applies

- `bin/rule-lookup.sh` + `bin/lib/rule-triggers.tsv` (id, file, heading, ERE). Input: files or
  stdin — the step's brief row and DESCRIBE text (from context-pack), a drafted `.mdl`, or a
  pasted error. Output: the matched sections, inlined. Code only fetches; rule text stays in skills.
- First rule: #565 → `skills/learned-runtime-traps.md` (on-demand row, 0 always-loaded words),
  trigger `commitInSeparateDatabaseTransaction|illegally add an object to the state`.
- Not yet: running it on a drafted script at preflight (`learned-mdl-preflight.md` final
  self-check). `bin/mdl-scan.sh` already scans a draft for STOP patterns *after* drafting;
  rule-lookup delivers rule *text before* drafting. Both read the same kind of table.

## 4. C — reference knowledge and gold MDL examples

1. **Lookup sources, by value:** learned rules (mxcli quirks, runtime traps — the model cannot
   know them) › the company brain (conventions; `mendix-company-brain-full` already has
   trigger-based lookup rules in its `AGENTS.md`) › `skills/mendix-best-practices-index.md` ›
   a local Mendix-docs snapshot (only for features newer than the model's training). Top 3 hits,
   ~600 words cap. Read from a local clone by path; nothing private is copied into this repo.
2. **Gold examples — two sources:**
   - **Reference projects per subject (preferred):** purpose-built apps, one per subject —
     performance (batching, indexes, loops), workflows, pages (overview/edit/master-detail),
     integrations (REST/OData), security (roles, XPath constraints), validation. Each is
     perfected deliberately: every gate green, `mx check` 0, lint clean, reviewed, journeys pass,
     re-run on each mxcli release. Their MDL becomes the example library. No client IP, made for
     the purpose, versioned with the toolkit's mxcli pin.
   - **Mined from past apps (only if the probe pays):** extract with `pipelines/mendix-mpr/`,
     label gold only after check + lint + review. Risk: most past apps were built with this
     toolkit (echo chamber), many are POCs, and their MDL spans old mxcli versions.
3. **Delivery:** `context-pack.sh`'s Example column falls back to the library's closest example
   when the app has none (the 2026-10-01 A/B: the app's own example carried the patterns; the
   generic cookbook skill added nothing).
4. **Not doing:** training or fine-tuning a model — MDL syntax moves every mxcli release; a
   re-checked library gives most of the value under our control.

## 5. The A/B — `tests/behaviour/`, arms by git ref

The behaviour suite already compares packs built from any two refs, scored mechanically
(`score.sh`, no mxcli needed for most metrics). `build-packs.sh` gains `--kind` / `--task`:

```
bash tests/behaviour/build-packs.sh M origin/master                       --kind page  --task tasks/page.md
bash tests/behaviour/build-packs.sh T experiment/task-routed-rules        --kind page  --task tasks/page.md
bash tests/behaviour/build-packs.sh M origin/master                       --kind logic --task tasks/mf.md
bash tests/behaviour/build-packs.sh T experiment/task-routed-rules        --kind logic --task tasks/mf.md
```

A ref without the library appends nothing, so M is master's full baseline (the control). Reps per
RUNBOOK.md: 5 × page and 5 × mf per arm, one fixed model, fresh agents, interleaved. Decision rule
(agreed before running): **T no worse than M on every scored metric** — the planted STOP request
(page: STOP 4; mf: STOP 21) refused, mdl-scan hits, structure metrics — with fewer start tokens.
Later arms: +B on a task with a planted trigger; +C with 5 hand-picked examples.

**Result, 2026-10-23 (`tests/behaviour/results/2026-10-23-task-routed-rules.tsv`, 20 reps):**
T no worse than M on every scored metric, for both tasks — planted STOP request refused 5/5 in
every cell, 0 mdl-scan hits, structure metrics equal. Tokens per rep: page −4.7%, mf −10.0%.
0 partial reads. Limits: n = 5 per cell; no `mxcli check` here; every rep inherited the toolkit
CLAUDE.md (both arms alike); B was not exercised (neither task carries a trigger).

## 6. Risks

| Risk | Guard |
|---|---|
| A rule a step needed is filtered out | The A/B; unmapped rows kept; unknown kind → all kinds |
| `Context packs: off` projects | They get the old reading list, and the files stay in the mdl stub's on-demand rows |
| Script header too thin for a helper that must run the tool | The helper still has the path; the gate and review roles still read it whole |
| Docs that call these files "always-on" (CLAUDE.md, README "Baseline routing") | Re-rendered by `render-routing.sh`; CLAUDE.md prose updated only if the A/B passes |

## 7. Order of work

1. ✅ A + B built on the branch. 2. ✅ `test-context-pack.sh` 55/55 (with and without `MXTK_ROOT`)
and the A/B above: pass. 3. If T passes: field run on a real project,
then a PR with the independent review. 4. C: reference projects, then the +C arm.
