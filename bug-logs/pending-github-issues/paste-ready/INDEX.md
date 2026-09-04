# Paste-ready mxcli issues — 2026-09-04

One file per issue. Line 1 = title, rest = body. File in this order (worst first).
After filing, write the issue URL back into the draft's **Status:** line and into
`bug-logs/mxcli-bugs.md`, then re-run this script.

| # | File | Suggested labels | Duplicate check |
|---|---|---|---|
| 01 | `01-bug76-workflow-decision-enum-identifier.md` | bug, critical, workflow, data-corruption | see draft |
| 02 | `02-bug107-workflow-call-with-unquoted-value-segfault.md` | bug, crash, workflow | searched `workflow segfault panic` 2026-09-03 — #1005 (dangling jump target), #945, #948 are workflow issues but none is a panic. New. |
| 03 | `03-bug109-jump-to-in-boundary-event-writes-targetless-jump.md` | bug, workflow, codegen | #1005 covers a *dangling* jump target stored as self-reference (CE6681). This is a *valid* target inside a boundary-event body written with no Target and a colliding name (CE0495 + CE6680). Related, not the same; cite #1005 when filing. |
| 04 | `04-create-association-corrupts-mpr.md` | bug | see draft |
| 05 | `05-bug102-alter-page-set-datasource-datagrid-silent-noop.md` | bug, alter-page, silent-success | searched `ALTER PAGE DataSource DataGrid` 2026-09-03 — #891 (DataGrid2 column edits silently destructive) and #919 (DynamicCellClass) are siblings, not this. Distinct from our #-pending BUG-84 (DataView datasource *wiped*). |
| 06 | `06-bug84-alter-page-dataview-database-wipe.md` | bug, page, alter-page, data-loss | see draft |
| 07 | `07-exec-non-transactional-silent-skip.md` | bug, exec, silent-success | #954 (WriteTransaction.Commit warn-and-continues on unit rename failures) is the storage layer. This is the statement layer: a failed statement stops the script with the remainder silently unapplied. Cite #954 as related. |
| 08 | `08-bug70-95-show-page-arg-rebound-currentobject.md` | bug, page, action-button | see draft |
| 09 | `09-bug104-quoted-parameter-keeps-dollar-sigil.md` | bug, parser, check-references | none found for `parameter quoted $` on 2026-09-03. |
| 10 | `10-bug106-widget-names-burned-after-rollback.md` | bug, cache, pages | #978 (DESCRIBE PAGE derived widget names rejected by check) is about name derivation, not the cache. Nothing on cache survival across a file restore, 2026-09-03. |
| 11 | `11-bug112-mxcli-new-path-too-long-hangs.md` | bug, new, hang | none found for `new path too long hang` on 2026-09-03. |
| 12 | `12-bug100-docker-init-compose-project-name.md` | bug, docker, data-loss | searched `COMPOSE_PROJECT_NAME` 2026-09-03 — nothing. |
| 13 | `13-bug73-raise-error-main-flow-ce0710.md` | bug, microflow, codegen | see draft |
| 14 | `14-bug67-snippet-primitive-param.md` | bug, snippet, documentation | see draft |
| 15 | `15-bug86-nanoflow-devicetype-write-barrier.md` | bug, nanoflow, validation | see draft |
| 16 | `16-gallery-widget-ce0463-survives-regeneration.md` | bug | see draft |
| 17 | `17-widget-init-docs-do-not-parse.md` | bug | see draft |
| 18 | `18-bug87-describe-java-action-type-param-name.md` | bug, java-action, describe, round-trip | see draft |
| 19 | `19-bug63-write-lint-rules-fictional-values.md` | bug, documentation, lint | see draft |
| 20 | `20-bug82-calculated-attribute-not-wired.md` | bug | see draft |
| 21 | `21-feature-mxcli-doctor.md` | enhancement, dx | searched `doctor diagnose health` 2026-09-03 — nothing. |
| 22 | `22-feature-mxcli-new-teamserver-app.md` | bug | see draft |
