# Skill: microflow-loop-antipatterns — what a loop body may and may not do

**Use when:** writing section 4 of an app dossier (`skills/app-analysis.md`), reviewing a
microflow that iterates, or diagnosing a runtime that is slow or dies under load.

**Inputs:** `analysis/app-facts/loops.json` and the described microflows under
`analysis/app-facts/mdl/`, from `bin/app-facts.sh`. The MDL files are the evidence; every
finding cites one by line number.

**Origin.** The pattern names come from a production support case on a large Mendix runtime
(2025, customer material stripped). The catalog side was measured on four projects on
2026-09-15; one had 161 loop-containing microflows nothing had ever looked inside.

---

## Why the catalog cannot do this

`activities_data` lists a microflow's activities flat, with a `Sequence` counter and no
parent. A `CommitObjectsAction` row cannot tell you whether it sits inside the
`LoopedActivity` row next to it. `mxcli describe microflow` renders the real structure as
`loop $x in $list begin ... end loop;`, so the instrument describes each loop-containing
microflow and parses those blocks. What the parser records per microflow:

| key in `in_loop` | MDL statement it matched, inside a loop body |
|---|---|
| `RETRIEVE_DB` | `retrieve $x from Module.Entity ...` (database) |
| `RETRIEVE_ASSOC` | `retrieve $x from $obj/Module.Assoc` (association, usually in memory) |
| `COMMIT` | `commit $x ...`, or `change`/`create ... commit` |
| `DELETE` | `delete $x` |
| `ROLLBACK` | `rollback $x` |
| `REST_CALL` | `$r = rest call ...` |
| `MICROFLOW_CALL` | `call microflow Module.Name(...)` |
| `JAVA_CALL` | `call java action Module.Name(...)` |
| `JS_CALL` | `call javascript action ...` |
| `nested_loop_lines` | a `loop` opened while another is open |
| `transaction_action_lines` | any statement naming `StartTransaction` or `EndTransaction`, in or out of a loop |
| `loops_parsed` | loop blocks found: both `loop $x in $list ... end loop;` and the while loop `while <cond> ... end while;` count |
| `reachable_from_scheduled_events` | scheduled events reaching this microflow over call edges; also split into `_enabled` and `_disabled` |

`_meta.parse_mismatch` lists only the microflows where the parser found FEWER loops than
`loops_catalog`. Those are unread and must be opened by hand. Parser found MORE is normal and
is counted in `_meta.catalog_undercount` (also in the manifest under `sections.loops`): the
catalog holds top-level activities only, so a nested loop, or a loop inside another block, is
invisible to it and to every Starlark lint rule. Record the undercount under Method; it is
evidence of that blind spot, not a parser fault.

## The patterns

Finding ids are `LOOP-<PATTERN>-nn`. One finding per microflow per pattern.

### LOOP_TQ: database work per iteration
`RETRIEVE_DB` or `DELETE` inside the loop. Each iteration is a round trip; a list
of 10,000 becomes 10,000 queries. The fix is almost always the same: retrieve once before the
loop (by XPath over the whole set, or over the association), change in the loop, commit the
list once after. **Threshold `LOOP_DB_CALLS_MAX` = 0**: one occurrence is a finding.
Exception: a loop whose iteration count is provably tiny (an enumeration, a fixed config
list); say so in the disposition.

### LOOP_COMMIT_DEFERRED: commit per iteration where one commit after the loop would do
Every `COMMIT` in a loop is this pattern and never also LOOP_TQ: one commit, one id. It is
separate from LOOP_TQ because it multiplies event handlers
(before/after commit) and validation rules per object. Read the entity's `HasEventHandlers`
in `entities_data` before judging severity: with handlers, this is where the runtime spends
its minutes.

### LOOP_NESTED: loop in a loop
`nested_loop_lines` non-empty. Quadratic by construction. Always a finding row, because the
facts cannot tell which loop a body statement belongs to. The reading decides the
disposition: an inner loop that only compares in-memory values is `accept` with that reason;
one that retrieves or calls is the classic N×M and gets a fix slice. Check the outer list
source first.

### REST_IN_LOOP: an HTTP call per iteration
`REST_CALL` inside the loop. Latency per iteration is now the remote system's, and its rate
limit is now your loop bound. Always a finding. Fix: batch endpoint if the remote offers one,
otherwise a queue (task queue, one task per item) so the loop is short and retries are per
item.

### LOOP_CALL: a call whose body you have not read
`MICROFLOW_CALL` or `JAVA_CALL` inside the loop. The parser stops at the call. A LOOP_CALL
row is not a finding; it is an unread pointer with an id (`LOOP-CALL-nn`) so the reading can
be tracked. **Read it** (`mxcli describe Orders.Called`) before deciding. The in-loop call is
depth 1, its callees depth 2; past that, write `unread beyond depth 2` in the evidence
column. What you find one level down becomes its own finding on the outer microflow
(`LOOP-TQ-nn` with evidence in the called file); a pure callee closes the row as `accept:
read, in-memory only`. If the callee is in `loops.json` itself, that is LOOP_NESTED across
two documents. A Java call is a finding (LOOP_TQ) when the action commits, deletes, or
starts or ends a transaction, whichever module ships it (CommunityCommons is the usual one,
not the only one; judge by the action name and its parameters); any other Java action stays
a LOOP_CALL row, closed only by reading the Java source or by the owner's word, recorded.

### END_TRANSACTION and SAVEPOINT_CHAIN: transaction control in a loop
`transaction_action_lines` non-empty, and the statement is inside a loop. Platform fact from
the support case that named these patterns: `EndTransaction` does **not** reset the savepoint
counter. Every nested start creates a savepoint; `StartTransaction`/`EndTransaction` per
iteration walks the counter up and, on HSQLDB, the runtime hard-fails at savepoint 65. On
PostgreSQL it does not fail, it only holds the connection in a transaction for the whole loop
(`idle in transaction`). Always a finding. Fix: one transaction around the batch, or a task
queue per item, never per-iteration transaction control.

### Scheduled-event reachability (severity multiplier, not a pattern)
`reachable_from_scheduled_events_enabled` non-empty. The same loop in a page action is bounded
by a user's patience; from a live scheduled event it runs on the full table at 03:00 with
nobody watching, and two overlapping runs are how a nightly job becomes a permanent one. Any
finding on an enabled-reachable microflow is written first and sized first. Reach only through
`_disabled` events is dormant: note it in the row, do not raise severity for it.

## How to write the section

One table, sorted: enabled-scheduled-reachable first, then by pattern severity (REST_IN_LOOP,
END_TRANSACTION, LOOP_TQ, LOOP_COMMIT_DEFERRED, LOOP_NESTED, LOOP_CALL). Columns: finding id,
microflow, module, pattern, evidence (`mdl/<qn>.mdl:<line>`), scheduled events, disposition
ref. Below the table, one paragraph on the shape: how many loop microflows, how many with
findings, `with_microflow_call_only` (the renderer's count: `in_loop` holds `MICROFLOW_CALL`
and no other key, and no nested loop), the parse mismatches and the `catalog_undercount`.

State every pattern that scored zero as a checked fact with its method, never by leaving the
row out: "parser found REST calls in 9 microflows, none inside a loop body: REST_IN_LOOP = 0".

Loops inside marketplace modules are accepted, not dispositioned as own work. Give the count
one line under Method; the third column of `loops-candidates.tsv` is the module kind.

Keep the reading honest:

- `RETRIEVE_ASSOC` is not a finding by default. A retrieve over an association from an
  object already in memory is served from the object cache in most cases. It becomes a
  finding when the source object was itself retrieved in the same loop.
- `MICROFLOW_CALL` alone is not a finding. It is a pointer to a microflow you must read.
- Zero loop microflows on an app with hundreds of microflows: the section is `fault`, not
  `pass`. Check `activities_data` has `LoopedActivity` rows at all.

## Verdict for the section

- `fail`: any LOOP_TQ, LOOP_COMMIT_DEFERRED, REST_IN_LOOP, END_TRANSACTION or LOOP_NESTED
  without a decision (`later, undecided` is not one).
- `manual`: no open finding, but LOOP_CALL rows remain unread. Say how many under Method.
  `fail` wins over `manual` when both hold.
- `pass`: none, or all decided, and every LOOP_CALL row read or closed.
- `fault`: manifest `sections.loops.status` is not `pass`, or `failed` is above 0, or parse
  mismatches exceed `MAX_PARSE_MISMATCH_PCT` of loop microflows. `rules_not_describable`
  does not fault the section: name the documents under Method and open them in Studio Pro.
- Marketplace-module loops never get rows. Ids issued to them by an earlier run stay in
  Dispositions as `closed <date>: marketplace module`; ids are never deleted or reused.

## Related

`skills/app-analysis.md` (owner), `skills/module-dependency-review.md`,
`skills/existing-app-change.md` (a slice that touches a listed microflow inherits its
finding), `skills/lint-that-actually-runs.md` (the lint-rule form of LOOP_TQ is a follow-up:
it needs loop containment, which the Starlark API does not expose today).
