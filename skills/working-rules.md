# Working rules

**Applies to:** any mxcli project
**Purpose:** the always-on card. It replaces five long rule files at session start
(`query-the-model.md`, `tool-output-is-not-ground-truth.md`, `degrade-to-judgement.md`,
`retesting-learned-rules.md`, `skills-over-scripts.md`); each long form is read only when a line
below sends you there.

## 1. Ask the right source, in this order  (long form: query-the-model.md)
Query the model -> read the source -> ask the human. Never skip to the last.
- Legacy behaviour: KB JSON + source, not the BRD (a BRD is derived). Legacy intent: KB docs, then SME. Never invent intent from code.
- What the Mendix model contains: SHOW / DESCRIBE / SEARCH / catalog. Never the BRD or build plan (those say what was planned).
- Blast radius: SHOW CALLERS / CALLEES / IMPACT. Decisions (boundaries, buy-vs-build, roles): the user, via a proposal with evidence.
- Before CREATE ASSOCIATION: SHOW ASSOCIATIONS (no IF NOT EXISTS; a rerun duplicates it, CE0065/CE0069).
  Before referencing a marketplace module: SHOW ENTITIES IN it.
- When sources disagree, rank: production data > declared config tables > client statements > source code > our own earlier conclusions.
  A lower tier only fills gaps. (Example: a .bak sat in the source folder while the data was recorded as "unrecoverable".)
- "Not implemented / does not exist" names what was searched and its date. A number carries its query or is marked an estimate.

## 2. Tool output is a projection, not the truth  (tool-output-is-not-ground-truth.md)
- Silence in output is not absence in the model. Before reporting "X is missing/unset", run the same method on a known-good X (control).
  `grep -rl thing dir` returning 0 could just mean you needed `-a`.
- Success output is not a write. After writing, DESCRIBE the element and check what was stored. A read-back that shows it proves it landed;
  one that does not show it proves nothing alone (DESCRIBE is lossy): compare with a known-good element.
- Measure exit codes unpiped: `cmd | tail; echo $?` reports tail's status. Redirect to a file, then read it.
  "0 problems found" plus a non-zero exit means NOT MEASURED, never clean.
- A green gate only means something if it can go red for this defect. Give it one deliberately broken input (negative control).
  Ladder: mxcli check < --references < mx check < Studio Pro opens it < the element renders < it works in the running app.
- Label claims: observation ("SHOW ACCESS lists no roles"), inference ("X has no grants"), prediction ("X fails at runtime").
- A destructive remedy (rebuild a page, drop a document, restore) needs a higher evidence bar, not a lower one.
  If the person who built it says it works, that outranks your inference: ask before drafting a fix.

## 3. A missing input never cancels the verdict  (degrade-to-judgement.md)
Missing wireframe, BRD, design system or instrument changes what you assess AGAINST, not whether you assess. Every degraded row carries:
1) Named: the path that is absent. 2) Substituted: the yardstick used instead. 3) Still a verdict, per item.
UNMEASURED is legal only for a mechanical dimension (a11y without axe, count without a DB). Never for a judgement one.
Ladder: declared artifact > next-nearest artifact (BRD, build-plan row, blueprint) > requirements as the user stated them >
what this stage is for (runbook) > unaided judgement with the rubric cited. An instrument that faults (exit 2) is a handoff: assess by hand, report both.
Report headline keeps its denominator: "12 of 12 reviewed: 4 vs wireframes, 8 unaided (no wireframe)".

## 4. Two triggers that are read on demand, not now
- About to route around a learned-* STOP that costs a detour: `./mxcli --version` vs the rule's stamp; if newer, `mxcli check` a scratch script,
  exec it through bin/exec.sh, read the mxbuild verdict and DESCRIBE what was stored, then delete the probe (retesting-learned-rules.md).
  Never conclude from docs, `mxcli syntax`, or `strings ./mxcli`.
- About to write a new .js/.sh for a check, gate or report: does it touch something an agent cannot (browser, DB socket, build binary),
  need byte-identical CI output, or compare more rows than a person can read? If not, write the rule as a sentence in a skill (skills-over-scripts.md).
