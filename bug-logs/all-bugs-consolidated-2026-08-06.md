# Consolidated mxcli / engalar-mxcli bug report — 2026-08-06

Sources: toolkit master log (`bug-logs/mxcli-bugs.md`, 69 `BUG-*`/`BUG-ENGALAR-*` headers),
WMS-Demo bakeoff (`bug-logs/bakeoff-2026-07-31/`, 14 `BUG-LOCAL-*` files), WMS-Demo
gh-issues-ready (17 files, filed as #827-843), TFC gh-issues-ready (3 files, filed as
#844-846). All GitHub states below were re-checked live via `gh issue view --repo
mendixlabs/mxcli`, not read off any log's prose.

## Summary

- **Raw entries surveyed:** 83 (69 toolkit headers + 14 bakeoff `BUG-LOCAL-*` files; the 3 TFC
  files are the same defects as toolkit `BUG-WF03/WF05/WF06`, not additional entries).
- **Distinct defects after dedup: 72.** 7 toolkit headers fold into a canonical sibling
  (`BUG-24`→`WF06`, `WF02`→`WF05`, `WF04`→ guidance note only, `35`→`ENGALAR-02`,
  `37`→`ENGALAR-03`, `42`→`ENGALAR-04`, `47`→`ENGALAR-05`). 2 bakeoff files fold into existing
  toolkit rows (`LOCAL-01`→`BUG-21`, `LOCAL-07`→`BUG-20`). 10 bakeoff files remain distinct.
- **Filed as GitHub issues: 20** (all `mendixlabs/mxcli`). **Live state: 17 OPEN, 3 CLOSED**
  (#840, #841, #845) — **all three closures rest on the same unmerged PR #853; see "flagged"
  below, this is not a settled fix.**
- **Not filed: 52**, broken down:
  | Reason | Count |
  |---|---|
  | Resolved / no longer reproduces (verified in the 2026-08-03/04 retest passes) | 14 |
  | Fork-only (Engalar-specific), not an upstream RnD defect | 6 |
  | Stale — predates any retest wave, current status unconfirmed | 21 |
  | Doc-gap / feature-request, not a corruption or logic defect | 3 |
  | Not an mxcli bug at all (Studio Pro / DataGrid2 widget) | 1 |
  | Root-cause-undiagnosed (2026-07-31 bakeoff only, no upstream retest) | 5 |
  | **Submission-ready but not yet filed — flagged, see below** | **2** |

## Flagged for attention

1. **#840, #841, #845 are CLOSED but the fix is not merged.** All three were closed
   2026-08-06 within ~70 minutes of each other, each citing PR **#853** (`ako/mxcli`, branch
   `main`→`main`). Verified live: `gh pr view 853` → `state: OPEN, mergedAt: null, closed:
   false`. PR #853's own body claims four *other* filed issues (#838, #839, #844, #846) are
   "already fixed on upstream main" — checked live 2026-08-06, **all four are still OPEN**,
   contradicting that claim. Treat #840/#841/#845 as unresolved in practice until #853 (or an
   equivalent merge) actually lands. This is the same caveat the task briefing gave for #845
   alone; it verifiably extends to #840 and #841 too.
2. **BUG-20 (cross-module association datasource writes null `DestinationEntityId`)** —
   confirmed independently on 2026-08-04 via `BUG-LOCAL-07` (FAIL on both RnD and the Wengao
   fork, exact same root cause: null `DestinationEntityId` on the `EntityRefStep`). Root cause
   has been understood since the original 2026-07-xx report. No draft exists in any
   `gh-issues-ready/` folder. **Submission-ready, not filed.**
3. **BUG-11 (`ALTER PAGE` cannot change a DataView's datasource type)** — carries an explicit
   `Status: Open — no fix in mxcli` note and a documented MCP workaround, but was never
   drafted or filed. **Submission-ready, not filed.**
4. **BUG-22 vs `BUG-LOCAL-05`** — `BUG-22` (`alter settings configuration/model` corrupts the
   Settings unit) has no retest annotation in the toolkit log itself, but `BUG-LOCAL-05` retested
   the identical trigger on 2026-08-04 and got **PASS on both RnD and Wengao** — i.e. independent
   evidence this may already be fixed, that the toolkit log was never updated to reflect. Not
   re-verified by this report beyond that one data point — flagged, not resolved.
5. **`BUG-LOCAL-04`** (short-form cross-module nav-through, no target-entity qualifier, CE0117)
   looks like it may be the same defect as **BUG-33 / #829** (cross-module nav requiring a
   fully-qualified target entity) — both are CE0117 on an unqualified segment after crossing a
   module boundary, but the exact expression shapes differ (BUG-33's example has an explicit
   entity segment; BUG-LOCAL-04's does not) and this wasn't independently confirmed byte-for-byte.
   **Kept as a separate row below — uncertain, not merged.**
6. **`BUG-19` (dataview widget-list `DivContainer`→`WidgetObject` cast crash) and
   `BUG-LOCAL-17`** (datagrid `customContent` column, same `Unable to cast ... DivContainer ...
   WidgetObject` error) share the identical crash signature in two different host widgets.
   Possibly one systemic codec bug, not confirmed as such. **Flagged, not merged.**
7. **`BUG-LOCAL-10c`** (filed as **#839**) may overlap **BUG-48** (pluggable-DataGrid2
   microflow-datasource drop, marked RESOLVED 2026-08-03 on both forks) — `BUG-LOCAL-10c`
   reproduced a *failure* on RnD one day later (2026-08-04) using a plain, not explicitly
   "pluggable", `datagrid` keyword. GitHub's own live title for #839 has since been reframed to
   "read-back bug, not data loss," which may or may not be the same underlying issue as BUG-48.
   **Uncertain relationship — not merged into BUG-48's RESOLVED verdict.**

## Full distinct-defect table

Legend — Category (when not filed): RESOLVED / ENGALAR-ONLY / STALE / DOC-FEATURE / NOT-MXCLI /
ROOT-CAUSE-UNDIAGNOSED / **SUBMISSION-READY**.

| Defect | Toolkit / bakeoff ID(s) | Filed as | Live GH state | Category if not filed |
|---|---|---|---|---|
| `ALTER ENTITY DROP ATTRIBUTE` corrupts MPR w/ access rules | BUG-01 | — | — | STALE |
| Cross-module `CREATE ASSOCIATION` corrupts MPR | BUG-02 | — | — | RESOLVED (fixed v0.13.0) |
| XPath assoc-path retrieve syntax undocumented | BUG-03 | — | — | DOC-FEATURE |
| `grant execute`, no-roles module, silently fails | BUG-04 | — | — | STALE |
| `$` not allowed in MDL parameter declarations | BUG-05 | — | — | DOC-FEATURE |
| SQLITE_BUSY partial-apply leaves orphan objects | BUG-06 | — | — | STALE |
| `ALTER PAGE SET content` fails on DYNAMICTEXT+ContentParams | BUG-07 | — | — | STALE |
| `ALTER PAGE REPLACE` duplicate-name failure | BUG-08 | — | — | STALE |
| Gallery `filter{}` can't express assoc-path filters | BUG-09 | — | — | STALE |
| Filter `Attributes` list: check/exec disagree | BUG-10 | — | — | STALE |
| `ALTER PAGE` can't change DataView datasource type | BUG-11 | — | — | **SUBMISSION-READY** |
| `ALTER PAGE DROP+INSERT BEFORE` w/ MICROFLOW corrupts BSON | BUG-14 | — | — | STALE |
| Assoc-path-from-variable retrieve → broken "by association" BSON | BUG-15 | — | — | STALE |
| `XPathConstraint`/`XpathConstraint` case-mismatch drops all XPath filters | BUG-15b | — | — | RESOLVED (fixed v0.13.0) |
| DataGrid2 `customContent` columns corrupt pluggable-widget BSON | BUG-16 | — | — | STALE |
| `[%BeginOfToday%]`/`[%EndOfToday%]` serialized with wrong quoting → CE0161 | BUG-17 | — | — | STALE |
| `visible:` on CONTAINER inside customContent corrupts MPR | BUG-18 | — | — | STALE (narrower case of BUG-50/#834?) |
| `ALTER PAGE REPLACE` wraps widget in CONTAINER → DivContainer/WidgetObject cast crash | BUG-19 | — | — | STALE (poss. same class as BUG-LOCAL-17, flagged) |
| Cross-module assoc traversal as widget datasource → null `DestinationEntityId` | BUG-20, BUG-LOCAL-07 | — | — | **SUBMISSION-READY** |
| Inline assoc-set in CHANGE/CREATE, incl. ReferenceSets, → invalid `AttributeIdentifier` BSON | BUG-21, BUG-LOCAL-01 | **#838** | OPEN | — |
| `ALTER SETTINGS CONFIGURATION/MODEL`/`ALTER PROJECT SECURITY LEVEL` corrupt Settings unit | BUG-22 (BUG-LOCAL-05 retest: PASS both forks 2026-08-04, unreconciled) | — | — | STALE |
| `ContentParams` with explicit `$currentObject/` prefix → literal broken path, CE1613 | BUG-23 | — | — | STALE |
| `ANNOTATION` in workflow body → BSON constructor crash | BUG-WF01 | — | — | STALE |
| Workflow `WITH` param mapping → null `ParameterId` (11.12.1, silent) | BUG-WF02 (folds into WF05) | see WF05 | — | — |
| Workflow `DECISION` enum compare → CE0117 — root cause: lowercase `$workflowContext` casing not normalized in DECISION | BUG-WF03 | **#845** | **CLOSED** (unmerged PR #853 — see flagged §1) | — |
| `CALL MICROFLOW` w/o WITH → red pin / runtime crash | BUG-24 (misdiagnosed; folds into WF06) | see WF06 | — | — |
| `CREATE WORKFLOW` writes null ContentsBlob → mx check InvalidCastException | BUG-25 | — | — | STALE |
| `--mcp exec` unreliable for `ALTER PAGE` (widget-not-found / malformed patch) | BUG-26 | — | — | STALE |
| Cross-module `grant execute` → CE0148 (distinct from BUG-04) | BUG-27 | **#836** | OPEN | — |
| `reset layout` check/exec disagreement → reclassified as feature gap (RnD never implemented it) | BUG-28 | **#837** | OPEN | — |
| Quoted attribute segment in nav expressions passes check, fails CE0117 | BUG-29 | **#827** | OPEN | — |
| `currentDeviceType()` function form: exec still writes invalid expr | BUG-30 | **#828** | OPEN | — |
| Void/boolean JS action in nanoflow → malformed BSON | BUG-31 | — | — | RESOLVED |
| MCP `CREATE` document leaves dangling unregistered `.mxunit` | BUG-32 | — | — | STALE |
| Cross-module assoc nav-through needs fully-qualified target entity | BUG-33 (poss. BUG-LOCAL-04, uncertain — see flagged §5) | **#829** | OPEN | — |
| MCP `pg_patch_page` rejects `AttributeRef[]` for DG2 filter bars | BUG-34 | — | — | STALE |
| `autochangedby`/`autocreateddate`/`autochangeddate` missing | BUG-35 (folds into ENGALAR-02) | see ENGALAR-02 | — | — |
| Scalar param, page button → microflow, silent bind failure | BUG-36 | — | — | RESOLVED (check/exec layer; runtime unverified) |
| COMBOBOX association-mode rejected | BUG-37 (folds into ENGALAR-03) | see ENGALAR-03 | — | — |
| `DatagridDropdownFilter` in association/ref mode uncreatable | BUG-38 | **#830** | OPEN | — |
| XPath filter can't use assoc-traversal expr as comparand | BUG-39 | **#831** | OPEN | — |
| `ALTER WORKFLOW INSERT` lacks USER TASK support | BUG-40 | — | — | RESOLVED |
| Pluggable DG2 `textfilter.attributes` accepted, not persisted | BUG-41 | — | — | RESOLVED (RnD) |
| Pluggable DG2 `Action:`+`DynamicCellClass`+filter combo unsupported | BUG-42 (folds into ENGALAR-04) | see ENGALAR-04 | — | — |
| `ALTER SETTINGS CONSTANT` corrupts Settings BSON | BUG-43 | — | — | RESOLVED |
| Validation rule on non-persistent entity attr → CE0070 | BUG-44 | **#832** | OPEN | — |
| XPath `id=` lookups fail (MDL048 not yet released) | BUG-45 | **#833** | OPEN | — |
| CE0066 security-hash reconciliation failure after GRANT | BUG-46 | — | — | RESOLVED (RnD; Engalar folds into ENGALAR-01) |
| CE0639 validation-feedback `Variable` not wired | BUG-47 (folds into ENGALAR-05) | see ENGALAR-05 | — | — |
| Silent microflow-datasource drop, pluggable datagrids | BUG-48 | — | — | RESOLVED (RnD; Engalar folds into ENGALAR-01; poss. overlap w/ #839, flagged §7) |
| `CREATE OR REPLACE PAGE` drops existing view-access grants | BUG-49 | — | — | RESOLVED (RnD; Engalar folds into ENGALAR-01) |
| `ALTER PAGE` can't reach widgets nested in customContent (broader than BUG-18) | BUG-50 | **#834** | OPEN | — |
| Quoted ref-target before param list breaks parsing | BUG-51 | — | — | RESOLVED (not reproducible; adjacent new defect = BUG-56) |
| CHANGE-activity attribute quoting → StorageLoadException | BUG-52 | — | — | RESOLVED (stale repro) |
| `Visible:` on action button in plain DataView corrupts BSON | BUG-53 | — | — | RESOLVED (RnD; Engalar has a different bug, ENGALAR-06) |
| `--mcp exec` silently renames entities before failing mid-script | BUG-54 | — | — | STALE |
| `ALTER PAGE DROP+REPLACE` transient collision (55a) | BUG-55 / 55a | — | — | RESOLVED |
| Cross-module GRANT EXECUTE/page-view grants silently no-op (55b) | BUG-55 / 55b | — | — | RESOLVED (RnD; Engalar folds into ENGALAR-01) |
| "Multiple Security$ModuleSecurity units" crash on module-role/GRANT ops | ENGALAR-01 (consolidates BUG-27,46,48,49,55b's Engalar side) | — | — | ENGALAR-ONLY |
| Missing `autochangedby`/`autocreateddate`/`autochangeddate` types | ENGALAR-02 (=BUG-35) | — | — | ENGALAR-ONLY |
| COMBOBOX association-mode regression vs RnD's `240e7d2c` | ENGALAR-03 (=BUG-37) | — | — | ENGALAR-ONLY |
| Pluggable DG2 `Action:`/`DynamicCellClass`/filter combo drops properties | ENGALAR-04 (=BUG-42) | — | — | ENGALAR-ONLY |
| Validation feedback, object-only form → blank Attribute, CE0091 | ENGALAR-05 (narrower version of BUG-47) | — | — | ENGALAR-ONLY |
| `$currentObject/` qualifier dropped on `Visible:` expression | ENGALAR-06 (related to, not identical to, BUG-53) | — | — | ENGALAR-ONLY |
| DG2 parameterized microflow datasource silently loses param binding, CE1571 | BUG-56 | **#835** | OPEN | — |
| Workflow `CALL MICROFLOW` — corrected consolidated guidance (not itself a defect) | BUG-WF04 (supersedes WF02+24; itself superseded by WF06) | — | — | — (guidance note, not a defect) |
| Workflow `CALL MICROFLOW` fully-qualified WITH → null ParameterId, MPR unloadable on 11.13 | BUG-WF05 (escalation of WF02) | **#844** | OPEN | — |
| `assess-quality.md` prescribes nonexistent `HTMLSanitize()` (should be `XSSSanitize`) | BUG-57 | — | — | DOC-FEATURE |
| Malformed pluggable-widget warning (`code: "Error"`) kills SP's entire Errors pane | BUG-SP01 | — | — | NOT-MXCLI |
| Workflow `CALL MICROFLOW`: v0.16.0 writes pre-11.9 `$Type` → red pin, app won't boot | BUG-WF06 (supersedes BUG-24's attribution) | **#846** | OPEN | — |
| ReferenceSet `CHANGE` corrupts project | BUG-LOCAL-01 | see BUG-21 above | — | — |
| Short-form cross-module nav-through, no target-entity qualifier → CE0117 | BUG-LOCAL-04 | — | — | STALE (poss. dup of BUG-33/#829, flagged §5) |
| `alter settings configuration` — did not reproduce 2026-08-04 | BUG-LOCAL-05 | see BUG-22 above | — | — |
| Cross-module assoc as widget datasource → unloadable | BUG-LOCAL-07 | see BUG-20 above | — | — |
| OpenAPI `$ref` not resolved on REST client import | BUG-LOCAL-08 | — | — | ROOT-CAUSE-UNDIAGNOSED (Wengao: partial improvement, no isolated commit) |
| Quoted identifiers inside `create import mapping{}` body not stripped → CE1613 | BUG-LOCAL-09 | **#842** | OPEN | — |
| REST client `Response: mapping` clause silently discarded | BUG-LOCAL-10a | **#843** | OPEN | — |
| Datagrid microflow datasource silently dropped | BUG-LOCAL-10c | **#839** | OPEN | — (poss. overlap w/ BUG-48, flagged §7) |
| Invented `on error rollback` on activities with no clause | BUG-LOCAL-11 | **#840** | **CLOSED** (unmerged PR #853 — see flagged §1) | — |
| Import mapping drops array segment of JsonPath | BUG-LOCAL-13 | — | — | ROOT-CAUSE-UNDIAGNOSED |
| `create json structure` writes every occurrence as `0..0` | BUG-LOCAL-14 | **#841** | **CLOSED** (unmerged PR #853 — see flagged §1) | — |
| ACTIONBUTTON inside datagrid customContent → unloadable (DivContainer/WidgetObject cast) | BUG-LOCAL-17 | — | — | STALE (poss. same class as BUG-19, flagged §6) |
| `ALTER PAGE SET Attribute=X ON widget` removes binding instead of retargeting | BUG-LOCAL-18 | — | — | ROOT-CAUSE-UNDIAGNOSED |
| Listview microflow-datasource argument silently discarded | BUG-LOCAL-19 | — | — | ROOT-CAUSE-UNDIAGNOSED (poss. same family as BUG-56/#835, different widget) |

## Notes on scope

- The 14 `BUG-LOCAL-*` bakeoff files are a **separate, project-local numbering space**
  (WMS-Demo's own `bug-logs/mxcli-bugs.md`, not the toolkit's master log) — only `BUG-LOCAL-06`
  had previously been folded into the toolkit log (as `BUG-32`). The other 13 were not in the
  toolkit's 69 headers at all until this reconciliation.
- BSON codec bug (`BUG-15b`) and the mxcli v0.13.0 association fix (`BUG-02`) are the only two
  entries confirmed fixed *in a shipped, tagged release* — every other "RESOLVED" row above was
  resolved against an unreleased RnD `main` build (`504aec67`) or the Engalar fork, not against
  the current tagged `v0.16.0` release that most projects actually run.
