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
- **Registering a file is not enough — register the pointer.** An earlier workstream's scripts sat
  in the toolkit unused for weeks because the routing row naming them existed in 2 of 6 projects.
  Nothing told any agent they existed. A skill without a `bin/lib/skill-routing.tsv` row is
  shipped, not delivered.
