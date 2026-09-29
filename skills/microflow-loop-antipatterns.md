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

### LOOP_NESTED: loop in a loop. An amplifier, not a finding
`nested_loop_lines` non-empty. Quadratic by construction **when the bodies do something**, and
free when they do not, which is why `bin/app-report.sh` no longer scores it as a row of its
own: it adds +1 to the query or the save in the same microflow instead. Scoring it alone was
one of the three reasons the first version of the page put 187 of 229 findings in one band.

Write it the same way. A nested loop with nothing scored in either body gets a count under
Method, not a disposition line. A nested loop around a retrieve or a call is the classic N×M
and gets a fix slice, on the LOOP_TQ row, with the nesting named as what makes it urgent.
Check the outer list source first.

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

### Scheduled-event reachability (a severity input, not a pattern)
`reachable_from_scheduled_events_enabled` non-empty. The same loop in a page action is bounded
by a user's patience; from a live scheduled event it runs on the full table at 03:00 with
nobody watching, and two overlapping runs are how a nightly job becomes a permanent one. Any
finding on an enabled-reachable microflow is written first and sized first. Reach only through
`_disabled` events is a loaded gun, not a fire: it scores +1 and can reach `medium`, and it can
never on its own make a finding `high`, because nothing is running it today. Note the event by
name in the row, so that switching it on is a decision somebody makes with this in front of them.

## Say what a loop body is, in the section, in words

The reader of section 4 is a Mendix developer who has never seen this tool, or a manager who
reads the first screen. The first real reader of the rendered page got as far as `LOOP_TQ` and
asked what a loop body was. Open the section with the sentence and then use the codes:

> A loop repeats a set of actions once for each item in a list. The loop body is the actions
> inside it, so anything there runs once per item: with 10,000 items it runs 10,000 times.

Then never print a code without its plain name beside it. `LOOP_TQ` is "a database query inside
a loop". `LOOP_COMMIT_DEFERRED` is "a save inside a loop". `catalog_undercount` is "loops the
catalog cannot see, which is expected". The renderer holds all of them in its `TERMS` table and
its test fails if a code can reach the page without a sentence; a hand-written section owes the
reader the same.

## How to write the section

One table, sorted worst first by the severity score in `skills/app-analysis.md` (pattern class
+ scheduled reach + amplifiers, under the amplifier ceiling), which puts an enabled-scheduled
row above the same pattern in a quiet module. Columns: severity, finding id, microflow, module, pattern, evidence
(`mdl/<qn>.mdl:<line>`), scheduled events, disposition ref. `bin/app-report.sh` scores the same
findings independently from the facts and prints its own list above yours; where the two
disagree, one of you read something the other did not, so reconcile before publishing. Below the table, one paragraph on the shape: how many loop microflows, how many with
findings, `with_microflow_call_only` (the renderer's count: `in_loop` holds `MICROFLOW_CALL`
and no other key, and no nested loop), the parse mismatches and the `catalog_undercount`.

State every pattern that scored zero as a checked fact with its method, never by leaving the
row out: "parser found REST calls in 9 microflows, none inside a loop body: REST_IN_LOOP = 0".

**And say what the absence means.** REST_IN_LOOP and END_TRANSACTION are the two patterns that
take a Mendix runtime down. On the R&D app both were zero, and the section still read as an
emergency because 229 findings sat above them. Write the proportion in the first paragraph:
how many loop microflows there are, how many loop bodies do nothing worth scoring, how many
findings an enabled timer actually reaches, and that the two worst patterns were looked for and
not found. A count without a denominator overstates every time.

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

- `fail`: any LOOP_TQ, LOOP_COMMIT_DEFERRED, REST_IN_LOOP or END_TRANSACTION without a
  decision (`later, undecided` is not one). LOOP_NESTED on its own is not one of these.
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
finding), `skills/lint-that-actually-runs.md` (a commit inside a loop is already caught by the
Go built-in rule CONV011 NoCommitInLoop; retrieve, delete, REST and call inside a loop still have
no lint rule, since the Starlark API does not expose loop containment — `skills/microflow-preflight.md`
is the pre-write check for those).
