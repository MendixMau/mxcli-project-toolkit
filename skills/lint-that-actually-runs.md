# Making mxcli lint actually run

Measured across four Mendix projects, 2026-08-14 → 08-19. Lint had shipped in every project for
months and had effectively never run. A bare `mxcli lint` emits hundreds to thousands of findings
with **zero errors** on every project measured — simultaneously unreadable and unable to fail any
gate that counts errors. Both halves must be fixed or lint stays off.

This page is the *method*. The rule catalogue, the per-rule configuration and the copy path live
in **`lint-rules/README.md`** — read that when you are installing or editing a rule, this when you
are deciding whether lint is telling you the truth.

## The one thing to internalise

**A blind rule reports a clean pass.** Every failure below has that same shape: the rule ran, the
gate went green, and nothing was inspected. Lint's failure mode is not a wrong answer, it is a
confident silence. Treat "0 findings" as a claim requiring evidence, never as a result.

## 1. Fix the rules' vocabulary. This is the whole game.

Starlark rules compare against hardcoded model strings. Get one wrong and the rule is either
silently blind or loudly wrong — **both worse than no rule**. Three confirmed instances in one
project's *stock* rule set:

| Rule | Bug | Effect |
|---|---|---|
| ARCH002 | `entity_type != "PERSISTENT"` | every entity skipped — **rule dead** |
| ARCH003 | same | **rule dead**, 8 real findings invisible |
| CONV010 | allowlist held `ShowFormAction`, `CloseFormAction` (fictional) and omitted `MicroflowCallAction` | flagged correct code; ~49% false positives |

The API returns **`"Persistent"`** — mixed case — while `microflow_type`, `container_type`,
`source_type` and `access_type` all return UPPERCASE. That single asymmetry killed two rules.

The source of every one of these bugs is the same: mxcli's own `write-lint-rules.md` documents the
casing **wrong in six places** and names action types that exist in no model. **Treat every
vocabulary string in that guide as unverified.** Probe instead:

```sh
sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActivityType FROM activities;"
sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType   FROM activities;"
```

**Diagnostic trick:** to prove a rule is dead rather than merely clean, find a sibling rule using
the same API with different casing and run both. `CONV015` (`"Persistent"`) returned 4;
`ARCH002`/`ARCH003` (`"PERSISTENT"`) returned 0. One command, conclusive.

**Verified on v0.24.0 (2026-09-25, probe rule on a scratch copy of a small PoC model; also found
in the field on v0.23.0).** Three more facts the bundled guide gets wrong or leaves out:

- `mf.microflow_type` is `"MICROFLOW"` / `"NANOFLOW"` / `"RULE"`. The guide says `"microflow"`.
  `microflows()` yields all three flavours from non-platform modules, so a microflow-only rule
  must filter on the type.
- SQL and Starlark spell entity types differently. `CATALOG.ENTITIES` gives `PERSISTENT` /
  `NON_PERSISTENT`, while Starlark `entity_type` gives `Persistent` / `NonPersistent`. A rule
  prototyped in SQL and pasted into Starlark goes blind. That happened twice in the field, 0 of 16
  and 0 of 28 real hits.
- `mf.activity_count` counts **top-level flow objects**: actions, splits, loops and annotations,
  excluding start, end and merge. It does not count actions inside a loop. `activities_for()` has
  the same top-level scope. So CONV009 over-reports actions, and nothing counts loop bodies.

```python
# before: reads as "actions", measures objects (annotation + retrieve + if + loop{change} + commit + log → 6)
if mf.microflow_type == "microflow" and mf.activity_count > 15:
# after: matches, and counts actions (→ 3; the change inside the loop is still invisible, say so in the message)
acts = [a for a in activities_for(mf.qualified_name) if a.activity_type == "ActionActivity"]
if mf.microflow_type == "MICROFLOW" and len(acts) > 15:
```

Ledger: BUG-63 (addendum 2026-09-25).

**`options:` in `lint-config.yaml` reaches only rules that call `get_option()`.** Nothing
checks the key: a rule that never reads it ignores it silently, exit 0, same count. The file
`mxcli init` writes uses stock CONV009 as its example, and stock CONV009 (0.17.0 to 0.26.0)
hard-codes 15:

```yaml
rules:
  CONV009:
    options:
      maxObjects: 20   # stock rule: still 5 findings at 15 on a field model; toolkit rule: 5 at 20, 10 at 10
```

The toolkit ships its own `conv009_max_microflow_objects.star`, which reads `maxObjects`
(default **15**, the stock value; `microflow-preflight.md` splits at 20 counting loop bodies,
so `maxObjects: 20` plus `countLoopBodies: true` matches it) through the replace-the-stock path
in `lint-rules/STOCK-HASHES.txt`. Before you tune any other rule, grep it for `get_option`. If the
call is not there, the option does nothing. Also, an option reaches Starlark only as a bool, a
number or a text. A YAML list or map arrives as `None`, so write a list as one text:
`external_roles: "Partner, Customer"`.

## 2. A rule that matches nothing must say so

Fixing the casing is not the end of it. A rule can reach the model and still inspect nothing,
because its *filter* matched nothing.

ARCH002 went 0 → 38 on the casing fix. That looked like a repair. All 38 were `System` entities —
the rule had never skipped the platform modules its sibling ARCH003 always skipped, which was
invisible while it was dead. With the same `SKIP_MODULES`, the same project measures **0**.

CONV010/CONV020 identify a page action only by an `ACT_` name prefix (`refs_to()` reports the same
`ref_kind` for a button click and a datasource, so the name is the only signal). That prefix is
Mendix's Development Best Practices convention, but it is a convention: on a project naming things
differently, both rules matched nothing and reported clean.

> **The guard you reach for first is the wrong one.** `if inspected == 0` is true on an empty
> project, so it fires spuriously. Count the population *before* the filter and guard on
> `population > 0 and matched == 0` — "there was something to inspect and my filter found none of
> it". Emit that as a finding with `module="_rule"`, and have the gate treat `_rule` as blindness.
> A line in a report nobody reads is not a signal; a failed gate is.

Verify both directions by fixture: set the prefix to an unused string (the finding must appear)
and to the real one (it must not). A guard tested only in the firing direction is untested.

## 3. Aggregate per document, not per item

CONV010 fired once per *activity*, so one fat microflow emitted 43 near-identical rows. Measured
fan-out (findings ÷ distinct documents) across four projects: **4.5×, 7.1×, 9.6×, 7.3×**. It is
the top rule on every project at 40–61% of all findings. `CONV008` is worse in kind — 45 rows onto
a single pseudo-document.

Signature to hunt: `violations.append()` inside a nested loop. One finding per document, listing
the offending kinds and a count, loses nothing and is ~8× shorter.

## 4. Ratchet, don't threshold

With hundreds of legitimate pre-existing findings, promoting severities to `error` fails every
gate forever and the gate gets switched off within a day — which is how lint died the first time.
Freeze per-rule counts as a committed baseline; fail only on an **increase**.

Confirmed workable everywhere: post-filter totals were 302 / 499 / 611 / 614 across four projects,
all the same order of magnitude, and no project produced a single real error-severity finding — so
the ratchet is the *only* mechanism available. `project-bin/lint-gate.sh` implements it
(`--update-baseline` to accept current counts).

**Accepting a rise is a recorded decision, not a reflex.** Three apps built in four days
re-baselined 61 times, every time by the agent whose script caused the rise; baselines grew
8 -> 757, 440 -> 677 and 9 -> 187, with security warnings accepted in the same batches as naming
info. So an update that raises any rule needs `--reason "<why>"` and is appended to
`.claude/lint-acceptances.tsv` (commit it with the baseline); a rise in a security-tier rule
(default `SEC*` and `CONV006`, override in `.claude/lint-security-rules.txt`) also needs
`--approved-in-chat`, set only after the user saw the findings and said yes. A first baseline
and a ratchet-down need neither.

**The ratchet remembers one number per rule; the ledger remembers every run.** Every gate run
appends one row per rule to `.claude/loop/lint-ledger.tsv` (timestamp, verdict, rule, count,
severity, blind), and `project-bin/lint-trend.sh` reads it back: runs a rule fired in, first and
last count with dates, best/worst, and how many runs it was blind. That is the answer to "did
the rule we shipped ever catch anything here, and did the count go down once people saw it" —
the evidence `process/lint-backlog.md` asks for before a warning becomes an error. A rule that
never appears in the ledger is clean here *or* wrong; `--rule <id>` and the blind column say
which. Before this file existed the only history was `lint-baseline.json` in git, which records
the count that was *accepted*, not what each run saw.

**The metrics ledger is the outcome side of the same question.** `project-bin/exec.sh` appends
one row per run to `.claude/loop/metrics-ledger.tsv` via `metrics-ledger.sh` (outcome class,
elapsed seconds, mxbuild errors, lint total, and — after a clean build — the `mxcli report`
overall score plus its seven category scores and violation count), and `metrics-trend.sh`
reads it back: applied-vs-failed counts, median elapsed first half → second half, lint total
and report score first → last. Lint counts say whether a rule fires; this says whether the app
got better and the sessions faster while it did. `bin/harvest-learnings.sh` carries the
trend summary (never the rows — those name scripts) into the toolkit inbox at wrap-up.

## Stock rules against the toolkit's own conventions

Three stock rules flag things this toolkit does on purpose. Each needs a known answer; otherwise an
agent "fixes" the finding by renaming a working flow, adding a fake caller, or moving a doc comment
onto the wrong document. Each answer is the user's decision, recorded in `PROJECT.md`, like any opt-out
(`lint-rules/README.md` → "Opting out of a rule").

| Finding | Why it is not a defect | What to do today |
|---|---|---|
| **QUAL004** on a `DS_` flow whose only caller is a Data grid 2 datasource (#360) | The stock rule already counts `datasource` refs (v0.24.0+), yet v0.26.0 flagged two working Data grid 2 datasources. The catalog likely misses the pluggable widget's ref. | Confirm with `describe page`, then accept the rise: `--update-baseline --reason "QUAL004 DS_ datasource false positive"`. Never rename or add a caller. Upstream: `pending-github-issues/qual004-dg2-datasource-ref.md` |
| **QUAL004** on a `TEST_` helper (#241) | It is called from `tests/*.test.mdl`, which lint cannot see. `ENTRY_POINT_PREFIXES` is a constant, not an option. | Baseline with a reason. Keep QUAL004 on: it is the orphan check `process-coherence-pass.md` runs. Upstream: `pending-github-issues/lint-naming-prefixes-as-options.md` |
| **CUSTOM002** on `TEST_`, `GET_`, `PRS_`, `STUB_` (#241) | `example_microflow.star` is an *example* rule from `mxcli init` ("customize the prefixes"). Its `VALID_PREFIXES` is a constant. | `rules: CUSTOM002: enabled: false`, recorded in `PROJECT.md`, or baseline with a reason. Never edit the `.star` file. Upstream: `pending-github-issues/lint-naming-prefixes-as-options.md` |
| **QUAL002** on import mappings, published REST services and Marketplace Java actions (#246) | MDL cannot store documentation on the first two (MDL089); a doc comment above them moves to the next microflow. | The rule has per-kind options (mxcli >= 0.24.0): `rules: QUAL002: options: check_import_mappings: false`, `check_published_rest_services: false`, `check_java_actions: false`, `check_java_action_params: false`. Or document them in Studio Pro. Upstream: `pending-github-issues/qual002-skip-mdl089-types.md` |

The QUAL002 option names come from the `missing_documentation.star` that `mxcli init` v0.24.0–v0.26.0
writes (it reads them with `get_option`). Grep your copy for `get_option` before relying on them;
they have not been field-run yet.

## Two false-pass bugs already designed out of `lint-gate.sh` — keep them out

Both were found by testing the gate, not by reading it:

1. **A crashed rule is not a finding.** mxcli reports a Starlark crash as `severity=error` with an
   **empty** module and a `Starlark rule error:` message prefix — *not* via the `_rule` convention.
   A gate keying only on `_rule` baselines the crash as a legitimate error and reports PASS while
   the rule sees nothing. Key on the message prefix too, and exclude crashed rules from the ratchet
   entirely — baselining a crash makes the crash the expected state.
2. **A collapse looks like a triumph.** A ratchet that only watches increases treats "lint saw
   nothing" as the best possible outcome. Fed a near-empty result the gate printed *"PASS — 28
   rules improved."* If the catalog is empty or the rules fail to load, every count drops to zero
   and the gate celebrates. Guard: a broad drop is a malfunction until proven otherwise.

## Linting a copy of the model: copy the rules in first

`mxcli lint` looks for the Starlark rules in `.claude/lint-rules/` from the `.mpr`'s folder
upward, and stops at the repository root. A copy of the model **outside the repository** (a
pre-exec snapshot copied to `/tmp` to attribute a ratchet rise, a scratch copy for a
before/after diff) therefore lints with the built-in rules only. Nothing says so and the exit
code is 0.

Field run, v0.25.0, 2026-10 (BUG-158, #240). The same model gave:

| Where the `.mpr` sat | Findings | Rules that ran |
|---|---|---|
| project folder | 721 | 29 |
| copy in `/tmp`, no rules beside it | 51 | 8 (MPR\*, CONV013, SEC003, MDL-FLOW01) |

A before/after diff over those two outputs reports 670 "new" findings that are not new.

**Recipe.** Copy the rules and the lint config beside the copy, then lint it:

```sh
COPY=/tmp/pre                        # the folder that holds the copied App.mpr
mkdir -p "$COPY/.claude" && cp -R .claude/lint-rules "$COPY/.claude/"
[ -f .claude/lint-config.yaml ] && cp .claude/lint-config.yaml "$COPY/.claude/"
./mxcli lint -p "$COPY/App.mpr" --format json > pre.json
```

**Before you diff two lint outputs, compare their rule sets.** Both runs must report the same
number of distinct `ruleId`s (or the copy's set must be a subset you can explain), counted over
the two files. If the copy shows only the built-in rules above, it did not load the project rules
and the diff is meaningless. "51 findings" from a copy is not a result until its rule count
matches.

- A copy **inside** the repository (`.mpr-snapshots/<stamp>/`, left where `exec.sh` puts it)
  finds the rules by walking up. It does **not** find `lint-config.yaml`: in mxcli's source
  (v0.26.0) that file is read only from beside the `.mpr`, never above it. Its module excludes
  and rule overrides then do not apply, so copy both files every time.
- A copy outside any repository is searched all the way up to `/`. In the v0.26.0 source the
  walk stops only at a `.git`, so a stray `~/.claude/lint-rules` or `/tmp/.claude/lint-rules`
  would supply its rules to the copy. Copying the project's rules in puts the nearest match
  beside the `.mpr`, which wins.
- There is no `--rules-dir` option on v0.25.0. Check `mxcli lint --help` on your binary before
  you rely on one.
- `project-bin/lint-gate.sh` guards against the collapse inside the gate (see "A collapse looks
  like a triumph" above). Running lint directly has no such guard, and this recipe stands in for
  it.

## What does NOT generalise — do not build this

**A vendor-module exclusion list.** `mxcli lint` **already skips Marketplace-sourced modules and
System natively.** Measured: a list of 13 Marketplace names plus System removed *exactly zero*
findings. On three of four projects the entire mechanism removed **0%**.

It looked like a 63% win on one project only because five Mendix GenAI modules had been imported
there **without Marketplace metadata** (blank `Source` in `SHOW MODULES`), so lint treated them as
first-party. Elsewhere the same five carried proper metadata and were auto-skipped.

So the *mechanism* ships (`lint-gate.sh -e`, fed from `.claude/lint-vendor-modules.txt`) and the
*list* does not. Correct procedure, once, per project: run `SHOW MODULES` and look **only** for
blank-`Source` modules you recognise as vendor. Most projects need zero entries. An empty file is
the normal outcome, not an unfinished one.

## The trap that wasted the most time

**A rule's `RULE_ID` need not resemble its filename.** `orphaned_elements.star` reports as
`QUAL004`. I checked whether it worked by grepping findings for "orphan"/"unused"; its actual
message is *"is not called from anywhere"*, so the grep found nothing and I reported a working
rule as blind. **Verify a rule by its `RULE_ID`, never by its message text.**

## Distribution — and the adversary

Lint rules had **no distribution mechanism at all** until 2026-08-19. Verified: the toolkit's fixed
CONV010 had reached **zero of 13 projects** — every one carried the identical stock rule emitted by
`mxcli init`. Nothing in `bin/` copied `.star` files; the instruction was a sentence in a README
telling a human to do it.

`bin/lib/install-lint-rules.sh` now does it, called by both `init-project.sh` and
`sync-project.sh`. Mechanics are in `lint-rules/README.md`. Two things to know here:

- **`mxcli` embeds the stock rules in the binary and re-emits them on `init`.** Verified v0.17.0:
  a second `init` in a scratch dir silently overwrote an edited `.star`, exit 0, no warning. Lint
  rules are the only copied artifact with an *active adversary* — they revert on their own, and a
  reverted ARCH002/ARCH003 reports a clean pass while inspecting nothing. This is why the install
  receipt lives outside `lint-rules/` and why installing rules **after** `mxcli init` is not a
  style preference.
  Between syncs, `bin/lint-gate.sh` reads the same receipt before every lint: a stock-seeded rule whose md5
  no longer matches and whose header is gone stops the run as `BLIND — lint rules reverted to
  stock` (exit 1, exec.sh logs `LINT BLIND`), not as a rise on the next script (#264).
- **Registering a file is not enough — register the pointer.** An earlier workstream's scripts sat
  in the toolkit unused for weeks because the routing row naming them existed in 2 of 6 projects.
  Nothing told any agent they existed. A skill without a `bin/lib/skill-routing.tsv` row is
  shipped, not delivered.
