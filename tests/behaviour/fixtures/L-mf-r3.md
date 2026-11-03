### MDL

```mdl
-- mdlsource/11-orders-submit.mdl
-- Module: Sales · feature group: Orders · drafted by mdl-agent (Stage 5) — DRAFT ONLY, not executed.
--
-- Documents:
--   Sales."SUB_Orders_SubmitReady"   NEW   — owned by this script
--   Sales."SUB_Nightly_Maintenance"  RESTATED (create or replace) — STOP #21 applies, see below
--
-- STOP #21 — SUB_Nightly_Maintenance is also edited by mdlsource/04-maintenance.mdl.
-- supersedes: mdlsource/04-maintenance.mdl (its SUB_Nightly_Maintenance statement only; the lead
--   must remove or retire that statement so the document has ONE owning script — STOP #22).
-- Call sites preserved from the CURRENT body (as stated by the lead in the task, NOT from a live
--   DESCRIBE — describe was NOT RUN; exec is blocked until it is):
--   1. call Sales."SUB_PurgeOldDrafts"   (kept, first)
--   2. call Sales."SUB_RecalcTotals"     (kept, second)
-- Added: retrieve of all Draft orders, then call Sales."SUB_Orders_SubmitReady" (last).
-- Before exec: DESCRIBE MICROFLOW Sales."SUB_Nightly_Maintenance" and diff against the body below;
--   bin/describe-baseline.sh stamp mdlsource/11-orders-submit.mdl; SHOW ACCESS ON MICROFLOW
--   Sales."SUB_Nightly_Maintenance" and re-grant what it lists (STOP #28);
--   mxcli diff -p <app>.mpr mdlsource/11-orders-submit.mdl --format struct (STOP #23).

/**
 * Submits every order in the list that has a customer and a positive total.
 * Orders failing that rule get validation feedback on TotalAmount and stay unchanged.
 * @param $OrderList orders to submit (multi-select grid, or the nightly Draft retrieve)
 * @returns true when every order in the list was submitted
 */
create or modify microflow Sales."SUB_Orders_SubmitReady" ($OrderList: List of Sales."Order")
returns Boolean as $AllSubmitted
folder 'Orders/Microflows'
begin
  declare $AllSubmitted Boolean = true;
  $Order_CommitList = create list of Sales."Order";

  loop $Order in $OrderList
  begin
    if $Order/Sales."Order_Customer" = empty or $Order/TotalAmount = empty or $Order/TotalAmount <= 0 then
      @annotation 'Feedback shows only when a page called this; on the nightly (system) path it is a no-op and the order simply stays Draft.'
      validation feedback $Order/TotalAmount message 'Order cannot be submitted: customer and a positive total are required.';
      set $AllSubmitted = false;
    else
      change $Order ("Status" = Sales."ENUM_OrderStatus".Submitted);
      add $Order to $Order_CommitList;
    end if;
  end loop;

  @annotation 'One commit after the loop (no commit inside the loop, CONV011). refresh serves the grid caller; it is meaningless but harmless on the nightly path.'
  commit $Order_CommitList with events refresh;
  return $AllSubmitted;
end;

grant execute on microflow Sales."SUB_Orders_SubmitReady" to Sales."User";

create or replace microflow Sales."SUB_Nightly_Maintenance" ()
folder 'Orders/Microflows'
begin
  call microflow Sales."SUB_PurgeOldDrafts"();
  call microflow Sales."SUB_RecalcTotals"();

  @annotation 'Unbounded retrieve of all Draft orders, as the lead asked; see the Bounded-lists note in the report.'
  retrieve $DraftOrders from Sales."Order"
    where [Status = 'Draft'];
  $AllSubmitted = call microflow Sales."SUB_Orders_SubmitReady"(OrderList = $DraftOrders);
end;

-- Grant per the brief excerpt ("Sales.User may execute every microflow below") — confirm against
-- SHOW ACCESS ON MICROFLOW before exec (STOP #28); see open question 2 in the report.
grant execute on microflow Sales."SUB_Nightly_Maintenance" to Sales."User";
```

### WRITE MODES

- create or modify microflow Sales."SUB_Orders_SubmitReady" — CLI (`./bin/exec.sh`, Studio Pro closed) — Step 0 default; plain microflow MDL expresses it fully, no STOP row routes it to Studio Pro.
- grant execute on microflow Sales."SUB_Orders_SubmitReady" to Sales."User" — CLI — co-located grant, per the brief's access slice.
- create or replace microflow Sales."SUB_Nightly_Maintenance" — CLI, **blocked until STOP #21/#23/#28 pre-exec steps are done** — whole-document restatement is the only write mxcli offers for an existing body (no ALTER MICROFLOW); the live DESCRIBE diff, the `mxcli diff` and the `show access` read must come first.
- grant execute on microflow Sales."SUB_Nightly_Maintenance" to Sales."User" — CLI — re-grants the access after the replace (STOP #28), per the brief's access slice; to be reconciled with the live `show access` output.

All four operations are one CLI exec of one script. No operation needs Studio Pro open.

### PREFLIGHT

**Role-stub check:** `agents/mdl-agent.md` in the pack still has unfilled `{{…}}` placeholders (`{{PROJECT}}`, `{{APP_PURPOSE}}`, `{{BUSINESS_RULES_SOURCE}}`, `{{PROJECT_LOCAL_SOURCES_OF_TRUTH}}`). The stub says to refuse when this happens. I went ahead because the dispatch supplied the project facts, the brief excerpt and the domain model directly, and said not to ask for more. Reported to the main session: the agent stub's generation is incomplete.

**Brief / skill inputs (degrade-to-judgement):** there is no Wiring block, no brief file and no live model. I worked from rung 1 as the dispatch gave it: the brief excerpt (`architecture/modules/Sales-brief.md`, roles and access plus the folder plan) and the stated domain model. The brief has no unchecked open questions on this slice.

**microflow-preflight — Sales."SUB_Orders_SubmitReady" — tier: Guided**
- Loops: 1. Per loop: retrieve n · commit/delete n · call n · batch strategy: none inside the SUB_. The caller passes the list. · expected list size: up to a few hundred from the grid. From the nightly path it is all Draft orders, which is unbounded (see note).
- Retrieves inside loops: 0
- Commits/deletes inside loops: 0. Changed orders go into `$Order_CommitList`, with one `commit … with events refresh` after the loop.
- REST/Java/web-service calls inside loops: 0
- Nested loops: 0
- Lists built from lists: 1, `$Order_CommitList`. This is justified: it is the CONV011 commit list, and the per-item split depends on a two-part condition with a side effect (validation feedback). A single `filter` cannot express that.
- Activities: top-level T = 4 (declare, create list, loop, commit) + loop body B = 5 (decision, validation feedback, set, change, add) = 9 (≤ 20)
- Top-level activities: 4 (≤ 15)
- Decisions + loops: 2 (≤ 9)
- Layout: no `@position`. The commit sits after the loop at top level, not inside an `if` branch, so the v0.24.0 loop-in-if MPR008 defect does not apply.
- Validation-feedback placement: in a `SUB_`, not an `ACT_` (CONV010 satisfied). Collect-all: no early `return`. Each failing order gets its feedback and `$AllSubmitted` turns false. The attribute is named (avoids CE0091).
- Commit late, events on purpose: one bare-semantics commit `with events`.

**microflow-preflight — Sales."SUB_Nightly_Maintenance" — tier: Guided** (trigger 6: it retrieves `Sales.Order` and, through the SUB_, commits the same entity)
- Loops: 0 (the loop is in the called SUB_, above)
- Retrieves inside loops: 0 · Commits/deletes inside loops: 0 · REST/Java in loops: 0 · Nested loops: 0 · Lists from lists: 0
- Activities: T = 4 (call, call, retrieve, call) + B = 0 = 4
- Decisions + loops: 0
- Bounded lists: **deviation, flagged.** `retrieve … where [Status = 'Draft']` has no limit, because the lead asked for "all Draft orders". A batched `limit … offset` loop is not safe here: invalid orders stay Draft, so offset paging over a moving set skips or repeats rows. If volume needs a bound, use one `limit N` per night and let the backlog roll over. That is a lead decision.
- System-session check: the body has no `[%CurrentUser%]`. `validation feedback` does nothing in a scheduled or system context. Store-by-owner `changedBy` will be empty for orders committed nightly.
- Layout: no `@position`.

**STOP-table check — STOP rows for kinds any, microflow, access: 9/9 checked**

| # | Applies? | Disposition |
|---|---|---|
| 14 | No | No entity grant is narrowed. |
| 16 | No | No access-rule XPath. |
| 21 | **Yes, flagged** | `SUB_Nightly_Maintenance` is shared with `04-maintenance.mdl`. The header names the preserved call sites and `-- supersedes:`. The live DESCRIBE diff and the `describe-baseline.sh stamp` were **NOT RUN** (no tool access), so exec is blocked until they are done. |
| 22 | Yes, handled | Both statements are idempotent (`create or modify` / `create or replace`), and grants re-run cleanly. One-owner rule: the lead must retire 04's statement for this microflow (open question 1). |
| 23 | **Yes, flagged** | Existing name replaced. `mxcli diff --format struct` **NOT RUN**. Read every `-` line before exec. |
| 25 | Yes, handled | A loop is present, so microflow-preflight is posted above. |
| 28 | **Yes, flagged** | An existing microflow is replaced. `show access on microflow Sales."SUB_Nightly_Maintenance"` **NOT RUN**. The script re-grants per the brief; reconcile it with the live output. |
| 29 | No | No nanoflow, no constant. |
| 33 | No | Return type of `SUB_Nightly_Maintenance` stays unchanged (none, assumed from the stated body; DESCRIBE will confirm). `SUB_Orders_SubmitReady` is new, so it has no callers yet. |

**Gotchas checked:** assoc empty test `$Order/Sales."Order_Customer" = empty` (a bare `= empty` test, module-prefixed anyway). There is no enum in a String context. Enum literal is fully qualified. Every CREATE result is assigned. No `on error` in the loop (CE0644). No `mdl 1;` header. Grants use qualified roles. The microflow header has `()`, then `returns`, then `folder`.

**Checks not run (no tool access in this dispatch):**
1. `mxcli check mdlsource/11-orders-submit.mdl -p <MPR> --references`: NOT RUN, no tool access
2. `mxcli diff -p <MPR> mdlsource/11-orders-submit.mdl --format struct` (STOP #23): NOT RUN, no tool access
3. `DESCRIBE MICROFLOW Sales."SUB_Nightly_Maintenance"` and diff (STOP #21): NOT RUN, no model
4. `SHOW ACCESS ON MICROFLOW Sales."SUB_Nightly_Maintenance"` (STOP #28): NOT RUN, no model
5. `bin/mdl-rules.sh --for mdlsource/11-orders-submit.mdl`: NOT RUN, no shell. Judged by hand, the kinds written are microflow and access, both loaded.
6. `bin/describe-baseline.sh stamp mdlsource/11-orders-submit.mdl`: NOT RUN, no shell

Also not done: the dispatch log line (step 8a, `.claude/loop/dispatch/Sales/scripts.tsv`), because I am only allowed to write to the output file.

**Folder per created document:** `Sales."SUB_Orders_SubmitReady"` goes to `Orders/Microflows`, and so does `Sales."SUB_Nightly_Maintenance"`. Both paths come from the brief's folder plan ("microflows → Orders/Microflows"). Generic convention would put a `SUB_` in `Orders/Services`, but the brief's row takes precedence. Restating the nightly flow with this folder **moves it** if 04 placed it elsewhere. The DESCRIBE will show that.

### REPORT

```report
scripts: 1
operations: 4
studio_pro_ops: 0
stops_flagged: 3
checks_not_run: 6
open_questions: 2
```

Notes:
- **What the script does:** it adds `Sales."SUB_Orders_SubmitReady"`. For each order without a customer or without a positive total, it gives validation feedback on `TotalAmount` and records that not every order succeeded. Every other order is set to `Submitted`, collected, and committed once after the loop. The flow returns `true` only if every order was submitted. The script also restates `Sales."SUB_Nightly_Maintenance"` to purge old drafts, recalc totals, retrieve all Draft orders and pass them to the new SUB_. Grants for `Sales."User"` follow each microflow.
- **Open question 1 (STOP #21/#22, ownership):** `SUB_Nightly_Maintenance` would have two owning scripts (04 and 11). Whichever runs last wins, and a replay of 04 after 11 silently removes the SubmitReady call. The lead needs to retire 04's statement for this microflow, or move this restatement into 04.
- **Open question 2 (access):** the brief says `Sales."User"` may execute "every microflow below", so I granted the nightly chain too. That lets any user run the purge, the recalc and the bulk auto-submit by hand. Please confirm the intent against `show access` before exec. The brief excerpt also mentions "both pages below", but this slice lists no pages.
- **Business-effect flag:** the nightly chain will now auto-submit every valid Draft order every night. This is what the lead asked for and it is recorded here. The nightly path does not log failures: SubmitReady's `false` result is assigned and not acted on. A `log warning` would make failures visible, but I left it out rather than invent unrequested behaviour.
- **Unverified-syntax risks (mxcli v0.26.0, check not run):** (a) attribute paths `$Order/TotalAmount` and the XPath `[Status = 'Draft']` are unquoted, against the project's quote-everything convention. The skill records attribute paths as unquoted. If check fails, apply the quote/unquote retry rule. (b) `commit <list> with events refresh` on a list variable. (c) `@annotation` before a statement inside an `if` branch.
- **Exec is blocked** until checks 1–4 and 6 are done. Draft only: nothing was executed.
