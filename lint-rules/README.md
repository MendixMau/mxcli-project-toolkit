# Lint rules

Starlark rules for `mxcli lint`, held here so they can be reviewed and carried between
projects instead of being reinvented per repo. Copy into a project's `.claude/lint-rules/`
and configure the marked constants — **after** running `mxcli init`, never before; see below.

| Rule | What it catches | Configure? |
|---|---|---|
| `conv009_max_microflow_objects.star` | CONV009 — a microflow over the object threshold. Replaces the stock rule, which hard-codes 15 and ignores the `maxObjects` option its own generated `lint-config.yaml` advertises | in `.claude/lint-config.yaml`, never in the file: `rules: CONV009: options: maxObjects: 20`, `countLoopBodies: true` (default 15 / false) |
| `conv010_act_microflow_content.star` | `ACT_` page-action microflows holding business logic instead of delegating to `SUB_` | if your prefixes differ — `ACTION_PREFIX`, `DELEGATE_PREFIX` |
| `conv020_action_user_feedback.star` | Page-triggered microflows that commit / import / delete but tell the user nothing | no — `PROJECT_MODULES` defaults to `"*"` (all modules the lint run includes, minus `.claude/lint-vendor-modules.txt`); `ACTION_PREFIX` if your prefixes differ |
| `data_change_microflows.star` | ARCH002 — persistent entities written from pages instead of microflows | no |
| `entity_business_key.star` | ARCH003 — persistent entities with no UNIQUE NOT NULL business key | no |
| `ux001_confirm_before_destructive.star` | UX001 — a button that deletes, approves, rejects, submits or archives (direct delete action, or a flow that deletes / is named so) without "Ask confirmation" | `DESTRUCTIVE_NAME_PATTERN` if your verbs differ |
| `ux002_decisions_captioned.star` | UX002 — decisions (`ExclusiveSplit`) with an auto-generated caption instead of the question they answer; flows of 8+ activities with neither an annotation nor a documentation text | `ANNOTATE_FROM` |
| `err001_error_swallowed.star` | ERR001 — an activity set to Continue / Custom / Custom-without-rollback in a flow that never logs, raises an error event, or calls a flow named like a handler (`SUB_LogError`, `ERR_…`): the error is swallowed | `HANDLER_NAME_PATTERN` if your handler flows are named differently |
| `loop001_expensive_action_in_loop.star` | LOOP001 — a database retrieve, delete, REST call, external call or Java action inside a loop body (any depth): one round trip per row | `EXPENSIVE` if a call type is cheap in your setup |
| `perf001_generalization_depth.star` | PERF001 — an entity more than two generalization levels deep (a System.* ancestor counts one level); every retrieve joins one table per level | `MAX_DEPTH`, `SYSTEM_ANCESTOR_LEVELS` |
| `perf002_nested_data_widgets.star` | PERF002 — a data view / list view / data grid / gallery nested inside two or more other data widgets on the same page: re-queries per row at every level | `MAX_NESTING`, `DATA_WIDGET_CANDIDATES`, `EXCLUDE` (widget_type vocabulary: probe first) |
| `perf004_npe_system_user_assoc.star` | PERF004 — an association between a non-persistable entity and System.User / System.Session (or an entity generalizing them), which pins session objects to the shared side | `NON_PERSISTABLE_CANDIDATES`, `SYSTEM_TARGETS` (entity_type vocabulary: probe first) |
| `txt001_build_words_in_user_text.star` | TXT001 — user-visible text (titles, captions, templates, messages, menu items) holding build-process words: `Stage N`, `BR-10`, `F004`, TODO, a version tag, "(local, …)" | `PROJECT_WORDS` (sibling-app and project code names); `LEAK_PATTERNS` if "Stage N" is a real domain word |
| `txt002_non_iso_date_in_user_text.star` | TXT002 — user-visible text holding a non-ISO literal date (10/12/2026, 12 Oct 2026) or a day/month format pattern (dd MMM, MM/dd); blind to format strings inside expressions | no. ISO dates are a toolkit opinion, not a Mendix rule: if the display standard is not ISO, the user may opt out (`rules: TXT002: enabled: false`), see "Opting out of a rule" |
| `ui001_widget_layout_traps.star` | UI001 — a list view inside a Data grid 2 column (its own "Load more" / "No items found" in every cell); an inline `width` on an Atlas input without `flex` (ignored) | `DATAGRID_TYPES`, `LISTVIEW_TYPES`, `INPUT_TYPES` (widget_type vocabulary: probe first) |
| `sec014_external_role_write.star` | SEC014 — an external user role (partner, customer, portal) that can write every member, a state enumeration (`Status`, `State`, …), an audit attribute (`…At` / `…By`) or the association its own XPath uses for ownership: the client API lets it skip the approval microflow | **yes, required**, in `.claude/lint-config.yaml`: `rules: SEC014: options: external_roles: "Partner, Customer"` (one text, not a YAML list), or `"none"`. Until it is set the rule reports nothing and `bin/sync-project.sh` prints a NOTE on every sync; a list, a blank value or an unknown role is a `_rule` finding |

`err001` and `loop001` first field count (2026-10-12, mxcli 0.26.0, 21-module Mendix 11.12 model,
876 microflows): ERR001 8 (3 true, 5 debatable — flows that return an error payload instead of
logging), LOOP001 4 (4 true). Warning severity until a second project reports.

`perf001`, `perf002` and `perf004` (Lint Batch 2) first field run (2026-10-12, mxcli 0.26.0,
same 21-module Mendix 11.12 model, catalog FULL, 1.4 s, no load errors): 0 / 0 / 0 findings and
no `_rule` blindness finding. The zeros are a null result, not a pass: the Starlark accessors
only expose the app's own modules (271 of 4346 widgets, 9 of 356 entities), and those had no
generalization, no data widget below depth 0 and no System.User association — while the
marketplace modules out of scope held 41 data widgets at depth 2+. The vocabulary probe did
land: `generalization` is `""` / `System.X` / `Module.Entity`, `entity_type` is `PERSISTENT` /
`NON_PERSISTENT` / `VIEW`, and the widget_type spellings are now in each rule's header
(`Forms$ListViewTemplate` was added to PERF002's EXCLUDE on that probe). Status stays `drafted`
until a project with real inheritance and nesting reports a count
(`tests/lint-rules/test-batch2-rules.sh`, 16 cases).

`txt001`, `txt002` and `ui001` (Lint Batch 3, issues #280 / #282) first field run (2026-10-13,
mxcli 0.26.0, the same 21-module Mendix 11.12 model, catalog FULL, 2.1 s, no load errors): 0 / 0 / 0
findings and no `_rule` blindness finding, over 478 user-visible strings and 271 widgets in the
app's own modules. A null result again, so the run carried positive controls: loosened copies of
the three rules (a project word "the", a bare-digit date pattern, data view / dynamic text as
the grid / list types) returned 27 / 50 / 17 findings through the same accessors, so `strings()`
and the widget parent walk do reach real rows at runtime. Replaying the rules' patterns over the
marketplace modules (outside the lint scope; `strings()` and `widgets()` never return them):
TXT001 9 — one admin-help sentence naming a dependency version, repeated, a debatable hit; TXT002
0; UI001 2 list views inside Data grid 2 columns. Vocabulary landed in each header: `strings()`
`object_type` is uppercase, `context` is the Mendix property path, and `strings()` needs
mxcli >= 0.25.0. On an older binary the file does not load at all (an undefined builtin is a
Starlark compile error): mxcli prints "rule file skipped" on stderr and no `_rule` finding can be
emitted, so pin the binary rather than trusting the count (`tests/lint-rules/test-batch3-rules.sh`,
23 cases; the harness gained a `strings()` mock).

`conv009` and `sec014` (Lint Batch 4, issues #267 / #268) first field run (2026-10-13, official
mxcli 0.26.0 release binary, two scratch model copies: the 21-module Mendix 11.12 model used for
Batches 2 and 3, and a 9-module one; catalog FULL, 0.2 s each, no load errors).
CONV009 on the first model's own modules: 5 findings with no option, **still 5 from the stock rule
with `maxObjects: 20`** (the bug, reproduced), 10 with ours at `maxObjects: 10` (the option reaches
the rule), 5 at 20 (every offender is above 25), 6 at 20 with `countLoopBodies`; a YAML list as
the value gives one `_rule` finding. The second model: 0 at every setting (its app modules hold no
flow over 10 objects). SEC014 with the model's one external-style role configured: **1 finding** —
write on all 7 attributes of a decision entity, one of them an audit attribute, plus the ownership
association its own XPath scopes on; a true positive by the rule's definition, the same shape as
#268. Positive control with every user role configured: 7 findings across 6 entities, and a SQL
replay of the same logic over `.mxcli/catalog.db` gives the same 7 (0 on the second model, which
has no external role; `"none"` there gives 0 and no `_rule`). A list or a misspelt role each give
exactly one `_rule` finding; an absent option gives nothing on exec and a sync NOTE instead. Both files also load and give the same counts on mxcli
0.17.0 and 0.24.0 (SEC014 avoids `associations()`, which does not exist before 0.25.0 and would
make the file fail to load). Vocabulary landed in SEC014's header: `MEMBER_WRITE` rows carry
qualified member and module-role names, attribute `data_type` for an enum is `Enumeration`.
Unit cases: `tests/lint-rules/test-batch4-rules.sh` (32; the harness gained `get_option`,
`permissions_for`, `attributes_for`, `user_roles`, `role_mappings` mocks).

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

`ux001` and `ux002` read widget `action_type` / `has_confirmation` and activity
`caption` / `auto_generate_caption`, which exist from **mxcli 0.25.0** (catalog schema with
widget actions and activity captions). On an older binary both rules emit a single `_rule`
finding ("needs mxcli >= 0.25.0") and nothing else — `bin/lint-gate.sh` reads that as blindness,
never as a clean pass. Their vocabulary (`Forms$DeleteClientAction`, `Forms$MicroflowAction`,
`ExclusiveSplit`, `DeleteObjectAction`) was read from the mxcli source at 0.25.0, then field-probed
on 2026-10-12 with mxcli 0.26.0 against a scratch copy of a 21-module Mendix 11.12 model (876
microflows, 124 pages). That probe found two defects the unit suite could not see: the stored
microflow-button action type is `Forms$MicroflowAction`, not the `…ClientAction` the source read
suggested, and `auto_generate_caption` is never set on a decision — a bare decision carries its
condition expression as its caption. Both fixed; after the fix UX002 reports every one of the
model's 39 top-level custom decisions as bare (all were), UX001 stays at 0 there (its 4 microflow
buttons reach no delete and match no verb). Re-probe on your own model before trusting the counts. Their *logic* is proven: `tests/lint-rules/`
runs both under the real Starlark interpreter (`go.starlark.net` at mxcli's pinned version) over
33 hand-written fixtures — self-checks, call depth both sides of the bound, cycles, the name
pattern, module skips, snippet locations, start/end events not counted — plus a synthetic
3000-flow / 20000-widget model each rule finishes in under a second. Fixtures encode the
projection as read from the mxcli source; they are not captured output, so they prove the
rule, not the vocabulary.

`conv010` here is likewise the repaired form of the rule mxcli seeds, and supersedes the
version this directory shipped on 11 Aug: one violation per microflow instead of one per
activity, plus four action types allowlisted. On PROJECT-C that is 399 rows -> 51 findings.

Candidates that are not rules yet, and the order they ship in: `process/lint-backlog.md`.

## A rule that matches nothing now says so

`CONV010` and `CONV020` can only identify a page action by its name — `refs_to()` reports the
same `ref_kind` for a button click and a datasource, so the `ACT_` prefix is the only available
signal. That prefix is Mendix's own Development Best Practices convention, but it is a
convention: on a project that names things differently both rules matched nothing, found
nothing, and reported a clean pass.

Both now emit a `_rule` finding when the prefix matches zero microflows (CONV010 guards on the
project having any microflows at all; CONV020 on `PROJECT_MODULES` being non-empty and containing any). Verified by
fixture on TestCLIApp — setting `ACTION_PREFIX` to an unused string produces the finding, and
the real prefix produces none. `bin/lint-gate.sh` treats `module == "_rule"` as blindness, so
this turns a silent pass into a gate failure rather than a line in a report nobody reads.

Set `ACTION_PREFIX` / `DELEGATE_PREFIX` to your project's prefixes. CONV010 cannot be opted out
(`mxcli init` seeds that file name, see below), so on a project without the `ACT_` convention set
`ACTION_PREFIX` to the prefix its page-action microflows do use. CONV020 can be opted out, as a
user decision, if the project has no such convention (see "Opting out of a rule").

## Opting out of a rule

Disabling a rule is **the user's decision**, never an agent's: ask in chat and record the answer
in `PROJECT.md`. There are two mechanisms, and neither one deletes or edits a `.star` file.

1. **Stop it reporting: `enabled: false` in `.claude/lint-config.yaml` (preferred).** mxcli
   skips a rule whose `enabled` is false. That applies to Starlark rules too, by `RULE_ID`
   (verified 2026-10-13 on mxcli 0.26.0: a toolkit rule with 1 finding gave 0 once disabled).
   The file stays installed and keeps refreshing, so switching the rule back on is one line.
   TXT002 is the usual case, because ISO dates are this toolkit's opinion and not a Mendix rule:

   ```yaml
   rules:
     TXT002:
       enabled: false   # display standard is dd/MM/yyyy: user decision, PROJECT.md D-14
   ```

2. **Stop sync installing it: `.claude/lint-rules-disabled.txt`.** Add one line per rule, with
   its reason:

   ```
   txt002_non_iso_date_in_user_text.star  # reason: display standard is dd/MM/yyyy (PROJECT.md D-14)
   ```

   A listed rule is never installed or restored by `sync-project.sh`, its receipt row is
   dropped, and `bin/lint-gate.sh` does not report it as gone. Use it together with 1, which is
   what actually stops the reporting. Two kinds of line are **ignored, with a warning**:

   - a line with no `# reason:` text;
   - a stock-seeded rule (`conv009`, `conv010`, `data_change_microflows`,
     `entity_business_key`; `MXTK_LINT_RULES_STOCK` in `bin/lib/install-manifest.sh`). `mxcli
     init` writes a stock copy of those file names back. The stock versions either inspect
     nothing and report a clean pass, or (CONV009) ignore their options. For these, use 1.

Never delete the file. Sync restores a rule it installed before, and lint-gate reads a
receipt-listed rule that is missing as a re-seed, so every exec reports `LINT BLIND` (#264).
SEC014's `external_roles: "none"` and `rules: SEC014: enabled: false` are the same user decision,
asked in chat and recorded in `PROJECT.md` (see below).

## How these reach a project

`bin/init-project.sh` installs them at scaffold time and `bin/sync-project.sh` refreshes them
on every sync; both call `mxtk_install_lint_rules` in `bin/lib/install-lint-rules.sh`, so there
is one implementation rather than two that drift. Nothing a human edited is ever overwritten
without `--upgrade-lint-rules <rule|all>`, which backs the local copy up first.

A project's `.claude/.mxtk-lint-receipt` records the md5 of each rule *as installed*, and its
kind (`stock`, `toolkit` or `configurable`, from the manifest) so that `bin/lint-gate.sh`, which
runs in a project with no manifest, checks for a re-seed only where `mxcli init` can cause one. Because
rules are copied verbatim, that one hash answers both questions the copy path needs: if the
project's file still matches it, nobody here edited it; if the toolkit's file still matches it,
the template has not moved. The receipt lives outside `lint-rules/`, which is what makes it
survive `mxcli init` — and surviving matters, because init wipes every in-file marker at once,
which would otherwise make a genuine revert indistinguishable from a first install.

**SEC014 needs two decisions from the user, not from an agent.** Until `external_roles` is
set, SEC014 reports nothing on exec, and `bin/sync-project.sh` prints a NOTE on every sync with the exact
lines to add (`bin/lib/sec014-notice.sh`), and `bin/lint-gate.sh` prints one uncounted note line
on every run (no exit-code change, no lint row). It is not a `_rule` finding, because that would make
lint-gate exit PASS-BLIND on every exec of every synced project until someone answered, which is
the #229 pattern an unconfigured CONV020 caused. Which roles are external is the user's answer,
asked in chat. `external_roles: "none"` switches off a security rule, and so does
`rules: SEC014: enabled: false`. Either one is set only on the user's answer and recorded as a
decision row in `PROJECT.md`. An agent never sets one to make the NOTE go away. The first run after configuring raises SEC014 from 0 to N at once, and lint-gate
would blame that security-tier rise on whatever script ran next. So re-baseline in the same step:
`bin/lint-gate.sh --update-baseline --reason "SEC014 configured"`, then the user, having seen the
findings, runs `bin/baseline-approve.sh lint` in a separate terminal window.

**Tuning a toolkit rule never means editing it.** `conv009` and `sec014` read their settings
with `get_option()` from `.claude/lint-config.yaml` (`rules: <RULE_ID>: options:`), so the file
stays byte-identical to the toolkit's and keeps refreshing. mxcli passes an option to Starlark
only as a bool, a number or a text; a YAML list or map arrives as `None`. Both rules report that
as a `_rule` finding instead of quietly using their default.

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
Show-page, close-page and show-home-page actions count as feedback (presence only, not order). Refresh-in-client is not visible to the Starlark API, so a flow that only refreshes is still flagged until mxcli exposes it.
A rule that fires on everything gets switched off, and a switched-off rule catches nothing —
which is how `CONV010` and the lint gate both ended up idle.

Known limitation, documented in the rule rather than hidden: `refs_to()` reports
`ref_kind == "action"` for *every* page reference, so a button click and a grid datasource
are indistinguishable. `CONV020` therefore filters on the `ACT_` naming convention. A real
user action named something else is missed. That is a deliberate false-negative, chosen over
firing a notification warning on every page load.
