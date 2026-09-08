**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-73: raise error; in a microflow's main flow always
fails mxbuild with CE0710` (project/date of original discovery not recorded in the source log;
pinned mxcli build used for the surrounding BUG-70–BUG-77 cluster; retested and confirmed still
open 2026-08-31 on v0.20.0 — see `bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1030 (2026-09-04)
**Suggested labels:** bug, microflow, codegen

---

**Title:** `raise error;` used directly in a microflow's main flow (not inside an error handler)
always fails native mxbuild with `CE0710` — a genuine flow-graph codegen defect

**Body:**

## Summary

Any microflow that uses `raise error;` anywhere in its main flow — including as the sole
statement of an otherwise-empty microflow, or as one arm of an `if`/`else` where both branches are
individually terminal — fails native mxbuild with:

```
CE0710: "The main flow cannot join an error flow or end in an error event"
```

This is not a linter/`mxcli check` false-negative; it is a real, structurally invalid generated
model. `raise error;` used *inside* an `on error { ... }` handler block builds cleanly — the defect
is specific to `raise error;` appearing directly in the main flow.

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new`
- Verdict source: native `mxbuild`/`mx check` (`mxcli docker check`), confirmed with a direct
  `mxbuild --write-errors=... --target=deploy` invocation bypassing mxcli's own `check`/lint
  entirely
- Originally found on an earlier pinned mxcli build (same era as the BUG-70–BUG-77 cluster, prior
  to v0.18.0); reproduced independently since on v0.20.0 (2026-08-31)

## Steps to reproduce

Any of the following microflow bodies produce the identical CE0710, isolated by bisection
(least-to-most minimal):

```sql
-- 1: entire body is raise error
create microflow Test.MF_RaiseOnly ()
begin
  raise error;
end;
/
```

```sql
-- 2: same, with a declared return type
create microflow Test.MF_RaiseTyped () returns boolean as $Result
begin
  raise error;
end;
/
```

```sql
-- 3: both branches individually terminal
create microflow Test.MF_RaiseIf ($X: boolean) returns boolean as $Result
begin
  if $X then
    return true;
  else
    raise error;
  end if;
end;
/
```

```sql
-- 4: guard-clause shape
create microflow Test.MF_RaiseGuard ($X: boolean) returns boolean as $Result
begin
  if $X = false then
    raise error;
  end if;
  return true;
end;
/
```

All four: `mxcli check` passes (or is only a warning under `SKIP_CHECK=1`, an unrelated
pre-existing MDL003 linter gap), `mxcli exec` succeeds, and native `mx check`/`mxbuild` reports:

```
[error] [CE0710] "The main flow cannot join an error flow or end in an error event"
```

Nesting depth, if/elsif/else flattening, and the presence/absence of a trailing `return` after the
`raise error;` statement all make no difference.

## Expected vs. actual

**Expected:** `raise error;` as the final statement of a terminal branch (main flow or any
statement-processing scope) is treated as closing that scope, the same way a `return` statement
is — no trailing `EndEvent`/`SequenceFlow` should be appended after it.

**Actual:** mxcli's flow-graph builder unconditionally appends a trailing `EndEvent` (and wires an
outgoing `SequenceFlow` to it from whatever the last-processed node was) unless an internal
"ends with return" flag is set. That flag is set only by `return`-statement handling paths (and a
narrow `if`-both-branches-terminal special case that itself does not cover a branch ending in
`raise error;`) — never by `raise error;`'s own dispatch. So whenever a `raise error;`-created
`ErrorEvent` ends up being the last node in any scope, the closing logic wrongly appends a second
`EndEvent` and wires an illegal outgoing `SequenceFlow` FROM the terminal `ErrorEvent` — an
`ErrorEvent` cannot legally have an outgoing flow in real Mendix semantics, which is exactly
CE0710.

## Severity

**High.** No MDL-only workaround exists — this blocks the plain, idiomatic way to propagate a
technical failure to a microflow's caller (`raise error;`) in the main flow entirely, for every
shape tried.

## Workaround

Avoid `raise error;` in the main flow. Add a small Java action that always throws
(`create java action Module.JA_RaiseTechnicalError(Message: string not null) returns boolean as $$
throw new com.mendix.systemwideinterfaces.MendixRuntimeException(Message); $$;`) and call it as an
ordinary activity where `raise error;` was wanted, followed by a normal (unreachable at runtime,
but required to satisfy Mendix's static "every path returns" check) `return` statement. Calling a
Java action goes through regular activity codegen, unaffected by this bug, and the thrown
exception terminates the microflow with a runtime error visible to the caller's `ON ERROR`
handling the same way a native `raise error` activity would.

## Suggested fix

The `RaiseErrorStmt` dispatch in the flow-graph builder should set the same "ends with return"
flag that `ReturnStmt` handling sets, and/or the per-branch statement loops inside `if`-statement
handling need to treat a branch ending in `RaiseErrorStmt` as already-closed the same way they
treat one ending in `ReturnStmt`.

---

**Status: FILED — https://github.com/mendixlabs/mxcli/issues/1030 (2026-09-04).**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "CE0710 raise error
main flow" and "CE0710 error event outgoing sequence flow main flow" — no existing issue found as
of 2026-08-31. Semantic search on "CE0710 raise error" surfaced only unrelated issues (#622 —
CALL MICROFLOW return-value assignment, CE0111; #506 — REST retry-loop error handler variable
scope, CE0108) — neither is this defect.
