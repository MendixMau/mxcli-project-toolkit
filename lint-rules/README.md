# Lint rules

Starlark rules for `mxcli lint`, held here so they can be reviewed and carried between
projects instead of being reinvented per repo. Copy into a project's `.claude/lint-rules/`
and configure the marked constants — **after** running `mxcli init`, never before; see below.

| Rule | What it catches | Configure? |
|---|---|---|
| `conv010_act_microflow_content.star` | `ACT_` page-action microflows holding business logic instead of delegating to `SUB_` | if your prefixes differ — `ACTION_PREFIX`, `DELEGATE_PREFIX` |
| `conv020_action_user_feedback.star` | Page-triggered microflows that commit / import / delete but tell the user nothing | **yes** — `PROJECT_MODULES`, and `ACTION_PREFIX` if your prefixes differ |
| `data_change_microflows.star` | ARCH002 — persistent entities written from pages instead of microflows | no |
| `entity_business_key.star` | ARCH003 — persistent entities with no UNIQUE NOT NULL business key | no |

`data_change_microflows` and `entity_business_key` are **repaired copies of rules `mxcli init`
already seeds**, not new ones. Both shipped comparing `entity.entity_type` to `"PERSISTENT"`
while the model returns `"Persistent"`, so both skipped every entity and reported a clean pass
for their entire life. One word each.

Measured on TestCLIApp 2026-08-18, ARCH002 went from 0 to 38 findings on the casing fix —
which proved the rule *reached* entities, and nothing more. **All 38 were `System` entities.**
ARCH003 has always skipped `System`/`Administration`; ARCH002 never did, which was invisible
while it was dead. It now carries the same `SKIP_MODULES` list, and the same project measures
**0** — the 38 were entirely platform noise. Marketplace modules are a separate concern and
are excluded at the gate (`bin/lint-gate.sh -e`, from a per-project
`.claude/lint-vendor-modules.txt`), not hardcoded in a shared rule.

`conv010` here is likewise the repaired form of the rule mxcli seeds, and supersedes the
version this directory shipped on 11 Aug: one violation per microflow instead of one per
activity, plus four action types allowlisted. On WMS-Demo-main that is 399 rows -> 51 findings.

## A rule that matches nothing now says so

`CONV010` and `CONV020` can only identify a page action by its name — `refs_to()` reports the
same `ref_kind` for a button click and a datasource, so the `ACT_` prefix is the only available
signal. That prefix is Mendix's own Development Best Practices convention, but it is a
convention: on a project that names things differently both rules matched nothing, found
nothing, and reported a clean pass.

Both now emit a `_rule` finding when the prefix matches zero microflows (CONV010 guards on the
project having any microflows at all; CONV020 on `PROJECT_MODULES` containing any). Verified by
fixture on TestCLIApp — setting `ACTION_PREFIX` to an unused string produces the finding, and
the real prefix produces none. `bin/lint-gate.sh` treats `module == "_rule"` as blindness, so
this turns a silent pass into a gate failure rather than a line in a report nobody reads.

Set `ACTION_PREFIX` / `DELEGATE_PREFIX` to your project's prefixes. If the project has no such
convention, delete the rule deliberately rather than leaving it inert.

## How these reach a project

`bin/init-project.sh` installs them at scaffold time and `bin/sync-project.sh` refreshes them
on every sync; both call `mxtk_install_lint_rules` in `bin/lib/install-lint-rules.sh`, so there
is one implementation rather than two that drift. Nothing a human edited is ever overwritten
without `--upgrade-lint-rules <rule|all>`, which backs the local copy up first.

A project's `.claude/.mxtk-lint-receipt` records the md5 of each rule *as installed*. Because
rules are copied verbatim, that one hash answers both questions the copy path needs: if the
project's file still matches it, nobody here edited it; if the toolkit's file still matches it,
the template has not moved. The receipt lives outside `lint-rules/`, which is what makes it
survive `mxcli init` — and surviving matters, because init wipes every in-file marker at once,
which would otherwise make a genuine revert indistinguishable from a first install.

## `mxcli init` overwrites these without asking

Verified 2026-08-18 on v0.17.0: a line appended to a seeded `.star` was gone after a second
`mxcli init` in the same directory — exit 0, no prompt, no warning, nothing in the output.

So these rules are the only copied artifact with an *active adversary*: they revert on their
own, and a reverted ARCH002/ARCH003 reports a clean pass while inspecting nothing. Each file
therefore carries a `# mxtk-lint-rule:` header ending in an explicit terminator line, and
`STOCK-HASHES.txt` records the md5 of each rule as mxcli seeds it. Together those let a copy
path tell six states apart: ours; ours-but-older (refresh); ours-without-the-header, from a
project that applied the fixes by hand before this path existed (refresh, and say so);
untouched-stock (safe to replace); a configured `conv020` (never touch); and a file the project
wrote (report, never overwrite). `install-manifest.sh` names the rules in two lists —
`MXTK_LINT_RULES` for the toolkit-owned ones and `MXTK_LINT_RULES_CONFIGURABLE` for `conv020`,
which is installed once and never refreshed because refreshing it would silently discard the
`PROJECT_MODULES` a project had configured.

---

## Read this before writing a rule: the vendor guide's API names are wrong

`.ai-context/skills/write-lint-rules.md` is generated by mxcli and documents the rule API.
Two of its tables are factually wrong, and both fail **silently** — a rule written from
them matches nothing, returns zero violations, and reads as a clean pass.

Verified 2026-08-11 against `.mxcli/catalog.db` on a 294-entity / 1,177-microflow project
(10,012 activities, 6,312 typed edges):

**`action_type` (guide line ~311).** All three examples the guide gives are names that do
not exist in the model:

| Guide says | Real value |
|---|---|
| `CreateChangeAction` | `CreateObjectAction`, `ChangeObjectAction` |
| `CommitAction` | `CommitObjectsAction` |
| `ShowFormAction` | `ShowPageAction` |
| `CloseFormAction` *(from the scaffolded CLAUDE.md)* | `ClosePageAction` |
| `ShowHomeFormAction` | *no counterpart — do not guess one* |

**`source_type` (guide line ~357).** The guide says `"microflow"`, `"page"`. The API
returns **uppercase**: `PAGE`, `MICROFLOW`, `SNIPPET`, `NANOFLOW`, `ENTITY`, `ASSOCIATION`,
`NAVIGATION`.

### What this cost

`CONV010` was written from that table and was **inverted for its entire life**. Because
`ShowPageAction` and `ClosePageAction` were missing from its allowlist, the most common
thing an `ACT_` microflow does — showing or closing a page — was reported as undelegated
business logic. Measured before the fix: **138 of 282 `ACT_` microflows flagged, 49% false
positives.**

That noise is the most likely reason lint was made "optional, non-blocking" on that
project, after which it stopped running at all. A wrong rule is more expensive than a
missing one, because it discredits the whole gate.

### Probe, don't trust

The catalog is a plain SQLite database. Confirm every API string before you use it:

```bash
sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType FROM activities ORDER BY 1;"
sqlite3 .mxcli/catalog.db "SELECT DISTINCT SourceType FROM refs ORDER BY 1;"
sqlite3 .mxcli/catalog.db "SELECT DISTINCT RefKind FROM refs ORDER BY 1;"
```

---

## Every rule must fail loudly when it cannot see

`activities_for()` returns `[]` in mxcli builds that postdate the graphcatalog refactor.
A rule that reads no activities finds no violations and looks **clean**. This is the same
failure shape as `[].every()` passing on an empty span set — the instrument reports success
because it measured nothing.

Both rules here carry a self-check: if they inspected candidate microflows and *not one*
yielded a single activity, they emit a violation saying the rule checked nothing. `CONV020`
additionally refuses to run while `PROJECT_MODULES` is still the empty toolkit default.

Apply the same guard to any new rule. The test is one question:

> If the API I depend on returned nothing at all, would this rule report a pass?

If yes, it needs a self-check before it is worth installing.

---

## Narrow beats comprehensive

`CONV020` deliberately ignores retrieves, changes without commit, non-page-reachable
microflows, and validation-only paths. It flags roughly what a reviewer would flag by hand.
A rule that fires on everything gets switched off, and a switched-off rule catches nothing —
which is how `CONV010` and the lint gate both ended up idle.

Known limitation, documented in the rule rather than hidden: `refs_to()` reports
`ref_kind == "action"` for *every* page reference, so a button click and a grid datasource
are indistinguishable. `CONV020` therefore filters on the `ACT_` naming convention. A real
user action named something else is missed. That is a deliberate false-negative, chosen over
firing a notification warning on every page load.
