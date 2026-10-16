# Increment 8 (Decompose, Dispatch & Workforce) — new mxcli 0.26.0 findings

**From:** MendixMau — toolkit lab run, Decompose increment 8, Dispatch & Workforce (split from #293)
**Date:** 2026-10-13
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM), monolith 10.24 copy (MPR v1), slice DispatchApp 11.13 (MPR v2); captures not committed (lab run, #293). mxcli v0.26.0.
**Proposed target:** `bug-logs/mxcli-bugs.md`; platform bullets to `skills/mendix-service-seam.md`

---

New defects only; known ones are listed at the end.

1. **describe page → create refuses its own output (ContentParams path).** `describe page Scheduler.PageContext_View`
   prints `ContentParams: ({1} = $currentObject/FilterCaption)`; exec of that output refuses:
   `dynamictext "text7": ContentParams parameter {1} is written as "$currentObject/FilterCaption" — a template parameter is
   evaluated against the widget's own context object, so it takes the attribute name …`. Workaround: `{1} = FilterCaption`.
2. **describe page → create resolves a nested visibility rule against the wrong entity.** Same page, after its
   `TicketManagement.WorkOrder` became an external entity: `Error: failed to build page: failed to build widget: dynamictext
   text14: Visible: Status in (…): Scheduler.PlannerContext_WorkOrder_Selected has no attribute Status`. The statement before
   it in the script (a microflow) was already written. Workaround: `alter page … { set (Visible: …) on text14; }` instead of
   re-creating the page.
3. **exec pre-check does not see what an earlier statement of the same script created** — variant of mendixlabs/mxcli#1061
   (queues): an attribute added by `alter entity M.E add attribute if not exists PublicID: AutoNumber default 1;` →
   `retrieve from TicketManagement.Appointment: the constraint names "PublicID", which is neither an attribute nor an
   association of it`; entities from `create external entities …` → `page 'DispatchSeam.Appointments_FromCore' has
   reference errors: - entity not found: DispatchSeam.Appointment`. Both scripts are valid; `--no-check` applies them.
4. **A rule-based decision describes as `if not(Rule(...)) then`.** drop + create then writes an expression split, and an
   expression cannot call a rule: `[CE0117] "Error(s) in expression." at Decision 'User is SDE?'`
   (`Scheduler.PlannerContext_GetWorkOrders`). This is the root cause of increment 7 inbox #6. Workaround: inline the
   rule's test (`retrieve $R from System.UserRole where [id = '[%UserRole_ServiceDeskEmployee%]'][System.UserRoles = $currentUser] first;`
   then `if $R = empty then`).
5. **`alter microflow X { insert before return true begin … end; };` is not idempotent.** Each re-run of the script inserts
   the call again (3 runs → 3 calls in `General.ASU_General`). Expected: refuse, or report that the activity is present.

Platform behaviour worth a learned-* line (not mxcli):
- external entities: an XPath on an attribute not published **Filterable** fails as a bare `CE0161 "Error(s) in XPath
  constraint."` (30 probe microflows to find it); sorting needs **Sortable** (`CE7247 "Cannot sort on attribute
  'PlannedWorkStart' because it does not support sorting."`); a navigation is published on its owner only, so a reverse
  traversal is CE0161 and a gallery over one is `CE8812 "Entity 'TicketManagement.WorkOrder' has no association
  'TicketManagement.Appointment_WorkOrder'."`;
- enumerations as Strings (P8) also break enum visibility rules: `CE0749 "The selected value 'Status' is not of type Boolean or Enumeration."`;
- `on error without rollback` inside a loop: `CE0644 "Error handling type must be 'Rollback' inside a looped activity."`;
- `mx check` text output has no document names; `mx check -j out.json` has them (`locations[].document-name`);
- Mendix 11 Java API vs 10.24 user code: `context()` → `getContext()`, `Core.isSubClassOf(String,String)` gone
  (`Core.getMetaObject(type).isSubClassOf(…)`), proxy parameters need `getMendixObject()`;
- a legacy `Forms$Table` hides its children from describe and `replace` (`widget "referenceSetSelector1" not found`):
  replace the table.

Known, seen again: BUG-87 (`entity <>`), bare `TypeParameter` Java action parameter (CE1613 `'.TypeParameter'`),
`format (decimalPrecision: -1)` not re-parsable, increment 7 #3 (nested widget not found) and #5 (consumed-service
metadata not refreshable: `0 created, 0 updated, 9 skipped`), non-atomic exec.
