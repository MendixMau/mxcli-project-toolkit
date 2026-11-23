# MDL deltas card — what the toolkit knows that mxcli's guidance does not
**Applies to:** any mxcli project.
**Purpose:** the MDL rules read before every script. mxcli's `CLAUDE.md`, `.ai-context` skills, `mxcli syntax` and `check --references` teach the language and win where this card is silent (`mdl 1;` first, `create or modify`). Each row: trigger, rule, the error it prevents. Measured on mxcli v0.32.0-374, Mendix 11.8.

**Every script:** `mxcli check <script> -p <app>.mpr --references`, read every error and warning, exec (`./bin/exec.sh` in a wired project), then real `mx check` — `exec` writes some scripts `check` flags, and most rows below pass `check`. An identifier fails quoted or unquoted → try the other form.

## The rows

| # | If your script will… | Then… | Fails as | Kind |
|---|---|---|---|---|
| 26 | Bind a DataGrid 2 column over an association | Unquoted: `Attribute: Assoc_A_B/Name` — here "quote every identifier" breaks | `CE1613 The selected attribute 'Shop.Line."Line_Order/Name"' no longer exists.` | page |
| 24 | Set `DesignProperties: [...]` on a widget | `grep -l '<property>' themesource/*/web/design-properties.json`; absent → Atlas class | `CE6083 Design property Column gap is not supported by your theme.` | page |
| 4 | Bind a widget to `AutoChangedBy` | Omit it, or bind `AutoChangedDate` | `CE1613 The selected attribute 'Shop.Audited.changedBy' no longer exists.` | page |
| 18 | Write workflow MDL | Read `learned-workflow-patterns.md`; exec callees before checking the workflow (below v0.32.0-374: an EARLIER script) | `check`: callee `not found`; older mxcli: CE0117 | workflow |
| 21 | Restate a document another script also edits (aggregator, startup chain, navigation) | `describe` it and diff your restatement against the dump; prefer `alter navigation` / `alter microflow` | A sibling's call silently vanishes; `mx check` 0 errors | any |
| 22 | Write a non-idempotent statement (`alter entity … add attribute`, bare `create`) | `create or modify` everywhere; ONE owning script per document | Re-run: `Error: attribute 'X' already exists on entity M.E`, exit 1, nothing written | any |
| 23 | `create or modify` something that may exist | `mxcli diff -p <app>.mpr <script>.mdl --format struct` first; read every `-` line | Attributes replaced, not extended; only warning `removes 2 member(s) … [MDL087]` | any |
| 33 | Change a flow's return type | One script: the change and every caller (`show callers of M.Flow`) | CE0112 at a Studio Pro-authored caller | microflow |
| G | Create a microflow, page or entity | Its grant in the same script | No error; blank screen or CE2729 for non-admins | any |
| P | Walk an association across modules | Prefix every step: `$Item/ModA.Item_Other/ModB.Other/Attr` | `Order_Customer is an association: an expression names it qualified … CE0117` | any |
| 14 | Narrow an existing entity grant | `revoke`, then `grant` the narrower set | `Unchanged entity access: M.E (M.Role)`; wider rights survive | access |
| M1 | Set an association | From the owner (`from` in `describe association`) | `CE0854 Association 'Shop.Line_Order' is not reachable from entity 'Shop.Order'.` | microflow |
| M2 | Retrieve a non-persistable entity from the database | Pass it as a parameter | `CE0056 Entity 'Shop.OrderDto' cannot be retrieved from the database because it is non-persistable.` | microflow |
| M3 | Write `validation feedback` | Name the attribute: `$Obj/Attr` | `CE0091 No member selected.` | microflow |
| M4 | Use `[%CurrentUser%]` as a String | `$currentUser/Name` | `CE0117 Error(s) in expression.` | microflow |
| M5 | Handle errors on a call inside a loop | Loop calls a wrapper microflow that holds the `on error` | `CE0644 Error handling type must be 'Rollback' inside a looped activity.` | microflow |
| M6 | XPath `[Assoc = 'literal']` | Compare to an object: `[M.Assoc = $Obj]` | `CE0161 Error(s) in XPath constraint.` | microflow |
| M7 | Use an enumeration as a String | `getCaption(…)` — exec writes it although `check` flags it | `CE0117 Error(s) in expression.` | microflow |
| W1 | `get workflows for $X`, no workflow on that entity yet | Same step as that workflow | `CE1870 The selected 'Workflow context' is not being used by any workflow.` | workflow |
| E1 | Name an entity `Case` | `CustomerCase`; quoting does not help | `CE7247 The name 'Case' is a reserved word.` | entity |
| E2 | `rename module` | Rewrite each XPath naming the old module | `CE1613 The selected association 'RenMe.Thing_Other' no longer exists.` | any |

## When this card is not enough

A numbered row is `STOP #n` of `learned-mdl-preflight.md` (full text, root causes, write mode in Step 0). Other CE code → `bin/bug-lookup.sh <code>`. Full rules for your kinds → `bin/mdl-rules.sh <kinds>`. mxcli older than v0.32.0-374 → `learned-rules-archive.md`.
