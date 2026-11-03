### MDL

```mdl
-- 11-orders-submit.mdl  (Sales / Orders feature)  -- DRAFT, never exec'd by the drafter
--
-- Owns: Sales."SUB_Orders_SubmitReady" (new).
-- Restates (STOP #21, shared document): Sales."SUB_Nightly_Maintenance". The restatement below is
-- written from the body the lead described, NOT from a live describe (NOT RUN, no model access).
-- Call sites preserved, in order: Sales."SUB_PurgeOldDrafts", then Sales."SUB_RecalcTotals".
-- Call site added: Sales."SUB_Orders_SubmitReady", last.
-- mdlsource/04-maintenance.mdl also edits SUB_Nightly_Maintenance; do not exec this script until the
-- owner question in the report is settled and `describe microflow Sales.SUB_Nightly_Maintenance`
-- has been diffed against the second statement.

/**
 * Submits every order in the list that has a customer and a positive total.
 * Orders that fail either rule get validation feedback on TotalAmount and stay unchanged.
 *
 * @param $OrderList The orders to submit (multi-select grid, up to a few hundred)
 * @returns true when every order in the list was submitted
 */
create or modify microflow Sales."SUB_Orders_SubmitReady" (
  $OrderList: List of Sales."Order"
)
returns Boolean as $AllSubmitted
folder 'Orders/Microflows'
begin
  declare $AllSubmitted Boolean = true;
  $Order_CommitList = create list of Sales."Order";

  loop $Order in $OrderList
  begin
    if $Order/Sales.Order_Customer = empty or $Order/TotalAmount <= 0 then
      validation feedback $Order/TotalAmount message 'Order cannot be submitted: customer and a positive total are required.';
      set $AllSubmitted = false;
    else
      change $Order ("Status" = Sales."ENUM_OrderStatus".Submitted);
      add $Order to $Order_CommitList;
    end if;
  end loop;

  @annotation 'One commit after the loop: orders are collected in the loop and committed together (no commit per item).'
  commit $Order_CommitList with events refresh;

  return $AllSubmitted;
end;
/

grant execute on microflow Sales."SUB_Orders_SubmitReady" to Sales."User";

/**
 * Nightly maintenance chain: purge old drafts, recalculate totals, then submit the ready draft orders.
 */
create or replace microflow Sales."SUB_Nightly_Maintenance" ()
folder '<<FOLDER OF THE EXISTING DOCUMENT, read from describe microflow Sales.SUB_Nightly_Maintenance>>'
begin
  call microflow Sales."SUB_PurgeOldDrafts"();
  call microflow Sales."SUB_RecalcTotals"();

  retrieve $DraftOrders from Sales."Order"
    where "Status" = Sales."ENUM_OrderStatus".Draft;

  $AllSubmitted = call microflow Sales."SUB_Orders_SubmitReady"(OrderList = $DraftOrders);
end;
/
```

### WRITE MODES

- create or modify microflow Sales."SUB_Orders_SubmitReady" (folder Orders/Microflows) — CLI via `./bin/exec.sh`, Studio Pro closed — microflow with no inline association set; the association is only read (`= empty`), nothing in the STOP table applies to the write.
- grant execute on microflow Sales."SUB_Orders_SubmitReady" to Sales."User" — CLI via `./bin/exec.sh`, same script — grant is co-located with the element, per the brief's access table.
- create or replace microflow Sales."SUB_Nightly_Maintenance" — CLI via `./bin/exec.sh`, but BLOCKED on STOP #21/#23 checks (describe, diff, ownership) — mxcli has no ALTER MICROFLOW for an existing body, so whole-document restatement is the only write; the existing grants and folder must be read from the live model first.

No operation needs Studio Pro. No enumeration or constant is created, so no `move` statement is owed.

### PREFLIGHT

**Step 0, write mode.** Default CLI through `bin/exec.sh` for all three operations (see WRITE MODES). Folder decided per document: SubmitReady from the brief's folder plan (`Orders/Microflows`). SUB_Nightly_Maintenance has no row in the brief's folder plan (the plan names feature group Orders only, and Nightly is maintenance, not an order feature), so I did not invent one: the statement carries a deliberate placeholder that fails `mxcli check` until the folder of the existing document is read off `describe` (or the architect names one). I did not fall through to module root.

**microflow-preflight: Sales.SUB_Orders_SubmitReady — tier: Guided**
- Loops: 1. Per loop: retrieve n · commit/delete n (collected) · call n · batch strategy: none needed, one commit after the loop · expected list size: up to a few hundred
- Retrieves inside loops: 0
- Commits/deletes inside loops: 0 — collected into Order_CommitList, one commit after the loop
- REST/Java/web-service calls inside loops: 0
- Nested loops: 0
- Lists built from lists: 1 — the commit list is built by `add` in the loop on purpose (it is the CommitList pattern from the skill, not a filter-able list operation, because each item is changed and conditionally included)
- Activities: top-level T + all loop bodies B = 5 + 5 = 10 (≤ 20, no SUB_ split needed)
- Top-level activities: 5 (declare, create list, loop, commit, return) (≤ 15)
- Decisions + loops: 2 (≤ 9)
- Layout: no @position

**microflow-preflight: Sales.SUB_Nightly_Maintenance — no trigger** (no loop, 4 top-level activities, one retrieve of Order that is not committed in this flow; the commit happens inside the called SUB_). Size note: the retrieve of all Draft orders is unbounded; the expected volume is not stated, so see open question 3.

**Validation-feedback rule (learned-microflow-patterns.md):** feedback lives in a SUB_ that returns a verdict, attribute named, collect-all (no `return` inside the loop, no `else` chaining past the failure), no `log error`, no annotation on it. The caller (ACT_ or the nightly flow) branches on the Boolean.

**STOP-table check (learned-mdl-preflight.md), every row against the planned operations:**
- #21 (create or replace on a document another script also edits): TRIGGERED. SUB_Nightly_Maintenance is also edited by `mdlsource/04-maintenance.mdl`. Required: `describe microflow Sales.SUB_Nightly_Maintenance` first, diff my restatement against it, name preserved call sites in the header. NOT RUN (no model access). Header names the two call sites the lead described; any other call site (including one 04 adds) would be lost. Also breaks the one-owner-per-document rule (#22): two scripts own one microflow, so whichever runs last decides its body.
- #22 (non-idempotent statement): checked. The new microflow uses `create or modify`; the Nightly statement is `create or replace` (idempotent) as the lead asked. No bare CREATE.
- #23 (create or replace on a name that may exist): TRIGGERED for Nightly. `mxcli diff -p <app>.mpr mdlsource/11-orders-submit.mdl --format struct` must be run and every `-` line read before exec. NOT RUN.
- #25 (loop in a microflow): TRIGGERED for SubmitReady; discharged by the checklist above.
- #28 (change near a return in a dense flow): not applicable, whole-body restatement, no insert before a return.
- #1, #1b, #4, #12, #24, #26 (page and widget rows): not applicable, no page or widget in this script.
- #18 (workflow): not applicable.
- #14, #16: not applicable, no entity grants are narrowed, no access-rule XPath.
- Other rows are retired.
- Gotchas checked: association path in the expression is the bare `= empty` test (allowed without the long form); `validation feedback` names the attribute (CE0091); enum value qualified as `Sales."ENUM_OrderStatus".Submitted`, no enum-to-String use; grant role is module-qualified (`Sales."User"`); no `[%CurrentUser%]` (the flow is also reachable from a nightly/system session); no `mdl 1;` header; no `@position`.
- Other preloaded rules applied: security-is-not-a-later-script (entity access for Sales."User" already granted by the domain script, taken from the prompt, not verified with SHOW SECURITY MATRIX: NOT RUN); degrade-to-judgement (missing live model named in each NOT RUN, verdicts still given).

**Final self-check (re-read against the table):** no conditional visibility in a grid, no quoted DataGrid association paths, no unprefixed association step beyond the bare `= empty`, no quoted `Editable:`. Clean on re-read.

**Page checklist:** `ui-preflight-pages.md`: no trigger, this script creates no page or snippet.

### REPORT

```report
scripts: 1
operations: 3
studio_pro_ops: 0
stops_flagged: 3
checks_not_run: 5
open_questions: 3
```

Notes.

- stops_flagged counts STOP #21, #23 (both on the Nightly restatement, blocking exec until the live describe and diff are read) and #25 (SubmitReady loop, discharged by the posted checklist).
- checks_not_run (all because I may not run tools): (1) `mxcli check mdlsource/11-orders-submit.mdl -p <mpr> --references`; (2) `mxcli diff ... --format struct` (rule 23); (3) `describe microflow Sales.SUB_Nightly_Maintenance` and the diff of my restatement against it (rule 21); (4) `show access on microflow Sales.SUB_Nightly_Maintenance`, to re-grant whatever it lists after the replace; (5) the step 8a dispatch log line in `.claude/loop/dispatch/Sales/scripts.tsv` (script path, date, check result) — the check result cannot be recorded because the check did not run, so the main session should log it after the check. Also not done: post-exec `describe microflow Sales.SUB_Orders_SubmitReady` read-back (belongs to the main session after exec). I did not read the Wiring block or the brief from disk; I used the brief excerpt in the prompt.
- Open questions:
  1. Who owns SUB_Nightly_Maintenance, this script or `04-maintenance.mdl`? Two scripts owning one document means the later one silently overwrites the other. Recommend the edit move into `04-maintenance.mdl` (or 04 stops touching it), and then 11 only creates SubmitReady.
  2. Folder for SUB_Nightly_Maintenance: no row in the brief's folder plan and not an Orders-feature document. The statement holds a deliberate placeholder (it fails `check` on purpose). Needs the existing folder from `describe`, or an architect answer. I did not guess `Orders/Microflows`.
  3. The current Nightly signature (parameters, return type) and any call sites beyond the two described are unverified; I assumed no parameters and no return. Also unbounded retrieve of all Draft orders: confirm the nightly volume or add a limit/batch.
- Unverified-syntax risks (nothing was run): placement of `folder '...'` between the `returns ... as $x` clause and `begin`; `where "Status" = Sales."ENUM_OrderStatus".Draft` as an enum comparison in the retrieve (if `check` rejects it, retry unquoted, or compare as a string literal); `$Order/Sales.Order_Customer` written unquoted (paths stay unquoted per the skills, against the project's quote-everything convention; retry the quoted form if `check` objects); `call microflow ... (OrderList = $DraftOrders)` with the parameter name unquoted as in the skill examples.
- Decision to confirm: `commit ... with events refresh` — `refresh` is right for the grid caller but is meaningless in the nightly path (no client). Harmless; kept because the shared SUB_ is mostly page-called. The nightly path will also produce validation feedback with nobody to read it; the returned Boolean is assigned and ignored there.
- The empty list returns true (nothing failed). A null `TotalAmount` is not treated as invalid beyond what `<= 0` does; add `or $Order/TotalAmount = empty` if the model allows empty amounts.
- Folder per created document: `Sales."SUB_Orders_SubmitReady"` goes to `Orders/Microflows`; `Sales."SUB_Nightly_Maintenance"` is unresolved (open question 2). Sequencing: the main session should do the describe/diff/show-access for Nightly before exec, and consider splitting the Nightly restatement into its own script so a failure there cannot hide the SubmitReady write.
