### MDL

```mdl
-- mdlsource/11-orders-submit.mdl
-- Draft only. Not executed.

/**
 * Submits every order in the list that has a customer and a positive total.
 * Orders failing the check get validation feedback on TotalAmount.
 *
 * @param $OrderList Orders selected for submission
 * @returns true when every order in the list was submitted
 */
CREATE OR REPLACE MICROFLOW Sales."SUB_Orders_SubmitReady" (
  $OrderList: List of Sales."Order"
)
RETURNS Boolean AS $AllSubmitted
FOLDER 'Orders/Microflows'
BEGIN
  DECLARE $AllSubmitted Boolean = true;

  LOOP $Order IN $OrderList
  BEGIN
    IF $Order/Sales."Order_Customer" = empty OR $Order/"TotalAmount" <= 0 THEN
      VALIDATION FEEDBACK $Order/"TotalAmount" MESSAGE 'Order cannot be submitted: customer and a positive total are required.';
      SET $AllSubmitted = false;
    ELSE
      CHANGE $Order ("Status" = Sales."ENUM_OrderStatus".Submitted);
      COMMIT $Order;
    END IF;
  END LOOP;

  RETURN $AllSubmitted;
END;
/

/**
 * Nightly maintenance chain: purge old drafts, recalculate totals,
 * then submit all remaining Draft orders that are ready.
 */
CREATE OR REPLACE MICROFLOW Sales."SUB_Nightly_Maintenance" ()
BEGIN
  CALL MICROFLOW Sales."SUB_PurgeOldDrafts" ();
  CALL MICROFLOW Sales."SUB_RecalcTotals" ();

  DECLARE $DraftOrders List of Sales."Order" = empty;
  RETRIEVE $DraftOrders FROM Sales."Order"
    WHERE "Status" = Sales."ENUM_OrderStatus".Draft;

  DECLARE $AllSubmitted Boolean = false;
  SET $AllSubmitted = CALL MICROFLOW Sales."SUB_Orders_SubmitReady" ($OrderList = $DraftOrders);
END;
/

GRANT EXECUTE ON MICROFLOW Sales."SUB_Orders_SubmitReady" TO Sales."User";
GRANT EXECUTE ON MICROFLOW Sales."SUB_Nightly_Maintenance" TO Sales."User";
```

### WRITE MODES

- create or replace microflow Sales."SUB_Orders_SubmitReady" — ./bin/exec.sh (Studio Pro closed) — no inline association set; the association is only read in an `= empty` test
- create or replace microflow Sales."SUB_Nightly_Maintenance" — ./bin/exec.sh (Studio Pro closed) — plain calls plus a retrieve; no association writes
- grant execute on microflow Sales."SUB_Orders_SubmitReady" to Sales."User" — ./bin/exec.sh (Studio Pro closed) — access rule per the brief
- grant execute on microflow Sales."SUB_Nightly_Maintenance" to Sales."User" — ./bin/exec.sh (Studio Pro closed) — re-asserted because replacing the microflow may drop its grants

### PREFLIGHT

No project skills or preflight checklists were loaded for this session. I therefore have no skill-mandated checklist to post and no STOP table to check against. NOT RUN — no preflight skill, STOP table, or checklist was provided.

The following are my own checks, not a substitute for the STOP table:
- Syntax check (`./mxcli check`): NOT RUN — cannot run tools here.
- Reference check (`check --references`): NOT RUN — cannot run tools here.
- mxbuild / `mx check`: NOT RUN — cannot run tools here.
- Quoting: every identifier I wrote is double-quoted, per the project convention.
- Loop size: a few hundred orders with one commit per iteration is acceptable. Collecting the orders and committing the list once after the loop would be faster. I kept per-order commits so that a failure only affects one order.

Risks to resolve before exec:
1. `SUB_Nightly_Maintenance` is also edited by `mdlsource/04-maintenance.mdl`. A `create or replace` here overwrites those edits, and the result depends on script order. I could not see that script, so I do not know what it changes.
2. I assumed the existing signature has no parameters and no return value, and I restated the body from the description alone. The existing folder, documentation, annotations, error handling and any other grants are unknown and may be lost. `DESCRIBE MICROFLOW Sales."SUB_Nightly_Maintenance"` should be run first. I could not run it.
3. The folder for `SUB_Nightly_Maintenance` is not restated, because I do not know it. If it lives in a folder, replacing it may move it to the module root.
4. Behaviour: the nightly job now submits every Draft order that passes validation. Validation feedback raised in a non-UI context is only logged and does not stop the job. This is worth confirming with the lead.

### REPORT

```report
scripts: 1
operations: 4
studio_pro_ops: 0
stops_flagged: 0
checks_not_run: 3
open_questions: 3
```

Notes: `checks_not_run` counts the syntax, reference and mxbuild checks. The open questions are the conflict with `04-maintenance.mdl`, the unknown existing signature and folder of `SUB_Nightly_Maintenance`, and whether the nightly job should auto-submit Draft orders. `stops_flagged` is 0 only because no STOP table was available to check against.
