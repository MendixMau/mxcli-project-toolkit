**Repo:** `mendixlabs/mxcli`
**Type:** Bug / feature request
**Source:** `skills/learned-mdl-preflight.md` STOP row 22 (confirmed 2026-08-31 on a migration project, mxcli v0.20.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, exec, silent-success
**Duplicate check:** #954 (WriteTransaction.Commit warn-and-continues on unit rename failures) is the storage layer. This is the statement layer: a failed statement stops the script with the remainder silently unapplied. Cite #954 as related.

---

**Title:** `mxcli exec` stops at the first failing statement and silently leaves every later statement unapplied — no summary, exit status does not say how much of the script landed

**Body:**

## Summary

A script with N statements fails on statement k. Statements k+1..N are never applied. The output reports the one error; nothing says "N-k statements not executed". The model is valid (mxbuild 0 errors) because it is merely missing work, so no downstream gate can see it.

Field case: a script added two attributes with `alter entity … add attribute`, then defined two microflows. Re-run after the attributes already existed, it died on statement 1 ("attribute already exists") and the two microflows at the end were never re-applied. It surfaced days later as a microflow quietly missing a call it had had an hour earlier, found by `DESCRIBE MICROFLOW` on a hunch.

## Environment

- mxcli v0.20.0; Mendix 11.14.0

## Steps to reproduce

```sql
alter entity M.Item add attribute Flag: Boolean;   -- succeeds first run, fails second run
create or modify microflow M.Uses_Flag ... ;        -- never reached on the second run
```

Run twice. Second run: one error line, exit non-zero, no statement count, microflow unchanged.

## Expected

Any of, in order of preference:

1. An `--atomic` (or default) mode that validates every statement before writing any, or rolls back the units touched when a later statement fails.
2. Failing that, an explicit trailer: `Applied 1 of 4 statements; 3 NOT applied (from line 7)`, and a distinct exit code for partial application.
3. `check --references` warning on non-idempotent statements (`alter … add attribute`, bare `create` on an existing name) so authors can use the `create or modify` forms.

## Workaround

One owning script per document, `create or modify` throughout, and a from-empty replay of the whole script directory to prove completeness. That is a lot of discipline to substitute for one summary line.
