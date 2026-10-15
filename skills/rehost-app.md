# Rehost App — Regenerating an Existing Mendix App as MDL into a Fresh App

**Applies to:** migration — a Mendix model (`.mpr`, Mendix 9 or later) is the legacy source, and the
whole app is regenerated as MDL into a clean target app.
**Purpose:** Run the Rehost extractor, drive its check → quarantine → exec → resume loop to a
fidelity ledger, and report the done-criterion — *build-green with hand-offs plus journey parity on
the main flows* — instead of a fidelity percentage. Upstream of the ledger this is a pipeline (`pipelines/mendix-mpr/`);
downstream, runbook Stages 2–6 apply unchanged (Stages 2–4 are WAIVED with a reason for a 1:1
regenerate).
**Evidence:** `pipelines/mendix-mpr/README.md` → "Field runs" — public apps only: a banking sample
(Mendix 11.13, 155 documents, build-green), a GenAI showcase app (Mendix 11.12, 2776 documents, 36/36
modules landed, not build-green) and a field-service template (Mendix 9.24, read probe and MPK moves).

---

## Step 0 — Rehost or MPK move?

Bound: the choice and its reason are a `PROJECT.md` register line.

| You want | Route |
|---|---|
| The whole app re-platformed into a clean project; MDL source you own afterwards | **Rehost** (this skill) |
| One or a few modules moved into another app, Java bodies and IDs intact | **MPK move** — `decompose-app.md` Stage 3 |
| Split a monolith into several apps | `decompose-app.md` (it moves slices by MPK, not by regeneration) |

**Rehost vs MPK move.** Rehost (MDL regeneration) is a full re-platform into a clean project, and it
fails wherever mxcli's describe cannot express the model. An MPK move carries modules as they are:
byte-identical, IDs preserved, no clean-up. The MPK route is `decompose-app.md`.

Measured scope: Rehost has run same-version only (11.13 → 11.13, 11.12 → 11.12). A 9/10 source read
works (field-service template 9.24 read probe), but regeneration from 9/10 into 11 is **not yet exercised**
(`pipelines/mendix-mpr/README.md` → "Not yet exercised"). Say so in the plan; do not promise it.

## Step 1 — Prepare the target

Bound: the target opens in `mx check`; every row below has a state, and every hand-off row an owner
in `PROJECT.md`.

Tag **[fixed after 0.26.0]**: fixed on mxcli main after 0.26.0 (`nightly-80-gbd45c47e`, nightly retest 2026-10-13), not yet released — keep the workaround while `mxcli --version` reports ≤ 0.26.0; drop it once your mxcli includes the fix.

`mxcli new <App> --version <target> --theme none`, then walk what a rehost carries:

| Item | State | Action |
|---|---|---|
| Entities, flows, pages, nanoflows | copied; gaps on large apps | Steps 2–4; ledger rows |
| Java actions | user code copied; helper classes and jars **not** | copy helpers and userlib jars by hand. The MDL route lands only the action body; without its helpers mxbuild failed `package org.apache.tika does not exist` (field-service template, 2026-10-12) |
| User roles, app settings | copied (`describe userrole`, `describe settings`) | `describe userrole` drops `CheckSecurity: false` — re-set it **[fixed after 0.26.0]** |
| Demo-user passwords, project security level | `***` / a report — hand-off | re-enter real passwords; write `alter app security` |
| Constants | copied with default values | per-environment values: environment row |
| Navigation | not emitted by the extractor | re-enter menus and home pages; record as hand-off |
| Theme / styling | not carried (`(app)` ledger row) | copy `theme/` and `themesource/<module>/` |
| Marketplace modules | re-installed, never regenerated (`mxcli marketplace install`) | each gap is a hand-off: Mendix-9-built packages refuse into 11 (3 on the GenAI showcase app; convert through 10.24 or replace); delisted versions; template modules at other versions |
| Custom widgets | installed from the source's `.mpk` files | before Step 2 |
| Environment configuration: certificates, DB credentials, per-environment constants, scheduled events on/off, deployment settings | outside the `.mpr` entirely | its own per-environment checklist, owned by whoever runs the environment |

**CRLF inside string literals is load-bearing — never normalise a `describe` file.** Studio Pro stores annotation text with `\r\n` and `describe` emits it verbatim inside the `'…'` literal. A helper that reads the file in text mode (Python universal newlines, `dos2unix`, an editor on save) silently writes `\n`; `check` then refuses the flow with `this change cannot be spliced into the stored flow: the free annotations change … [MDL-V1-REBUILD]` (mxcli v0.26.0, 2026-10-12). Read and write byte-for-byte (`newline=''`, `sed -b`) and treat a `.mdl` as binary in any step that touches it.

## Step 2 — Run the extractor

Bound: `fidelity-ledger.tsv` exists and its header states the denominator (every describable
document in the source catalog for the modules run).

```
MXCLI=<path to mxcli> pipelines/mendix-mpr/rehost-extract.sh <source.mpr> <target.mpr> <out-dir> [Module ...]
```

Read the script header for outputs. Defaults: every own module (empty Source column), System
excluded. Switches:
- `REHOST_REUSE_MDL=1` — reuse `<out>/mdl/<M>.mdl` from an earlier run; use it on every rerun after
  fixing the check/exec side, because the describes are the slow part.
- `REHOST_KEEP_ORDER=1` — replay modules in the order given instead of reference order (use when
  you have resolved a module cycle by hand).

**Budget** (GenAI showcase app, 36 modules): describes ~30 min; first check/exec ~14 min; rerun with reused
describes 36 min. One module: 35 s.

## Step 3 — Understand the loop the script runs

Bound: for every module, either it landed or the run log says why it did not.

Per module, in order:
1. `describe module <M> with all` via `-c`, plus every document `with all` omits (nanoflows,
   snippets, JS actions, JSON structures, mappings, task queues, image collections), described one
   by one from the project tree.
2. `lib/topo-order-mdl.py` — callees before callers; a flow and its grants move as one unit.
3. `lib/fix-describe-output.py` — repairs the Java-action parameter comma mxcli emits inside a
   `--` comment **[fixed after 0.26.0]**; on a fixed mxcli it moves 0 commas and can be skipped (keep it).
4. **check → quarantine**: `mxcli check` is all-or-nothing per file; `lib/quarantine-mdl.py` moves
   the statements it rejects (with their same-module closure) to `<M>.deferred.mdl`.
5. **exec → resume**: exec stops at the first statement it cannot write; `lib/exec-resume.py`
   defers that statement with the verbatim error and continues with the rest.
6. Deferred statements retry in fixed-point passes (most are forward references into modules not
   yet created); what still fails reaches the ledger with its error.

The failure this loop exists for: the first full run on the GenAI showcase app (2026-10-12)
executed **1 of 36 modules** — one emitter defect plus all-or-nothing check sank the other 35.

When quarantine and exec-resume cannot place an error on a statement, the script falls back to
`lib/exec-each.py` (one statement at a time). Before that fallback, the rest of the module dropped
silently: 7 modules, 1520 ledger rows reading `absent from target describe` (GenAI showcase app,
2026-10-12; fixed 2026-10-13, 7/7 modules then landed). A whole module of `failed-exec` rows is an
extractor fault, not N failed documents. Count what never ran from the `-- deferred:` lines in
`<M>.deferred.mdl`, not from the run log.

## Step 4 — Read the fidelity ledger

Bound: every row is landed or a named hand-off; the hand-off count is reported.

| Verdict | Means | Action |
|---|---|---|
| `emitted-identical` | target describe equals source | none — the build still decides |
| `emitted-drift` | landed, describe differs | read the evidence; on the GenAI showcase app ~190 of 271 were microflow layout (#923) or doc whitespace |
| `failed-exec` | not in the target | find the first error naming it: a dropped module, a deferred dependency, or a root cause |
| `not-emitted` | in the catalog, no describe statement | hand-off or extractor gap |
| `not-expressible` | MDL cannot carry it (NOT re-executable widgets, #923 decisions, app-level rows) | hand-off |
| `target-extra` | only in the target | check it is the template's, not a stray |

**The ledger does not decide done; the build gate does.** The failure: a sort on an inherited
attribute was `emitted-identical` on the ledger and still CE1613 in `mx check` (GenAI showcase app,
2026-10-12; that defect is **[fixed after 0.26.0]**, the lesson stands).

## Step 5 — Gate and report

Bound: the report states `mx check` errors, mxbuild result, and the hand-off count by class.

**Build gate** (CONFIRMED 2026-10-12): `mx check` 0, `BUILD SUCCEEDED`, every ledger row landed or
a named hand-off. Run it yourself — the script does not (`project-bin/exec.sh`'s mxbuild gate, or
`mx check <target.mpr>`). Then Step 5b; done needs both.

Hand-off classes by construction in mxcli 0.26 — record each document, fix in Studio Pro:

| Class | Why |
|---|---|
| Java action type parameters | described with no type parameter; exec writes entity `.Entity` (CE1613) |
| ~~Message definitions~~ | **not a hand-off** (corrected 2026-10-12): `create message definition collection` exists in 0.26.0; the extractor must emit the collection before the export mappings that use it. The GenAI showcase failure was ordering, and the error text does not point at the command |
| Rules | cannot be described or created **[fixed after 0.26.0]**; once fixed, check each decision call — `describe microflow` drops the rule's argument. Also missing from the extractor's denominator |
| Mutual recursion | exec refuses forward references, so both flows and their callers stay deferred |
| NOT re-executable widgets | describe marks them; e.g. `Forms$FileManager` |
| Step 1 hand-off rows | not carried by describe |

If the model will not load (`ArgumentNullException … EntityType.set_EntityId`), mxcli wrote a
microflow whose `import from mapping` result has a null entity: `drop microflow` then the source
`create or modify` in one script (GenAI showcase app, 2026-10-12). **[fixed after 0.26.0]**: exec refuses the forward reference
(MDL-ORDER01) and writes nothing — move the mapping above the microflow.

## Step 5b — Journey parity, source vs target

Bound: N/N journeys pass on **both** apps with the same data effects, or the report says
`journeys NOT RUN: <reason>`. Silence is not a result.

Describe-identical is not behaviour-identical (the CE1613 sort above). Run the same Playwright journeys against the source app and the
rehosted app and compare outcomes, with the existing machinery — `journey-proof.md` for the journey
shape, `e2e-harness-base.md` for the harness (as `existing-app-assurance.md` uses it), `project-tests/e2e/journey-runner.js` to run them.

1. One journey per main user flow; assert its data effect in both databases.
2. Make every journey idempotent: run-unique IDs, never an empty grid assumed. Failure: the
   field-service template journey (2026-10-12) broke on its third run because accumulated rows let
   the grid's sticky header cover "New Part". Run each twice.
3. A journey passing on one app only is a rehost defect; trace it to its ledger row.

Measured so far: the banking sample (same-version, 155 docs) was proven statically only; the GenAI
showcase app ran no journey (it needs live LLM credentials).

**Done = build-green with hand-offs plus journey parity on the main flows** — or build-green with
hand-offs and `journeys NOT RUN` with a written reason. Say which.

## Step 6 — Learnings

New mxcli defects → a `contrib/inbox/` drop (the contribution lane); extractor defects → the
pipeline with a captured fixture; judgement about what to regenerate or hand off → this skill. Known
emitter defects are in `pipelines/mendix-mpr/README.md` ("Field runs", "mxcli findings") and the
pipeline's `lib/*.py` headers — read them before re-diagnosing. `CHANGELOG.md` line in the same commit, crediting the source app.
