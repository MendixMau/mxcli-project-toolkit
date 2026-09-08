**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-86: MDL044's new write barrier is microflow-only —
the identical expression in a create nanoflow passes check, is written, and fails the build with
CE0117` (originally discovered 2026-08-20 on a scratch project, mxcli v0.18.0, while retesting
BUG-30; retested and confirmed still open 2026-08-31 on v0.20.0 — see
`bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1033 (2026-09-04)
**Suggested labels:** bug, nanoflow, validation

---

**Title:** MDL044 write barrier (`currentDeviceType()` validation) only runs for `CREATE
MICROFLOW`, not `CREATE NANOFLOW` — the identical invalid expression passes `check`, is written,
and fails the build with `CE0117`

**Body:**

## Summary

`currentDeviceType()` used as an expression inside a `CREATE NANOFLOW` body passes `mxcli check`
cleanly, is written by `mxcli exec` with no error, and then fails native mxbuild with `CE0117`.
This is the same underlying invalid-expression defect mxcli previously fixed for microflows
(closed issue #828, "`exec` still writes an invalid `currentDeviceType()` expression even though
`check` now flags it (MDL044)") — but the fix (MDL044's write barrier / check-time rule) was wired
into the microflow code path only, and was never extended to nanoflows. For nanoflows, `check`
does not even lint the case at all, which is worse than the pre-#828 microflow situation: there is
no warning anywhere in the mxcli-side toolchain, only a native-mxbuild failure at the end.

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new`
- Verdict source: native `mxbuild`/`mx check` (`mxcli docker check`), isolated by dropping the
  nanoflow and re-checking (confirmed the CE0117 is attributable to it, not another activity)
- Originally found: 2026-08-20, mxcli v0.18.0, Mendix 11.12.0, while retesting BUG-30. Reproduced
  independently since on v0.20.0 (2026-08-31), on a disposable scratch project.

## Steps to reproduce

```sql
create nanoflow Test.NF_Dev ()
begin
  log info 'device: ' + currentDeviceType();
end;
/
```

```
$ ./mxcli check devtype-nf.mdl -p Test.mpr
All references valid.

$ ./mxcli exec devtype-nf.mdl -p Test.mpr
Created nanoflow: Test.NF_Dev

$ ./mxcli docker check -p Test.mpr
[error] [CE0117] "Error(s) in expression." at ... Test.NF_Dev ...
```

Dropping `Test.NF_Dev` and re-running `mxcli docker check` clears the error — confirming it is
attributable to the nanoflow's `currentDeviceType()` expression, not another activity.

The equivalent microflow shape (`currentDeviceType()` inside a `CREATE MICROFLOW` body) is now
correctly refused/flagged by `mxcli check` per the MDL044 rule (issue #828's fix) — the defect
here is specifically the nanoflow path never being wired to the same rule set.

**Note on the token-form remediation:** `[%CurrentDeviceType%]` (the bracket-percent token form)
is a known-safe substitute for `currentDeviceType()` in a page conditional-visibility expression
(per the original BUG-30 workaround). That workaround does **not** carry over to a nanoflow
expression context — on Mendix 11.13, `[%CurrentDeviceType%]` inside a nanoflow now builds clean
(no CE0117), while the function-call form `currentDeviceType()` still fails. Anyone applying the
page-context workaround inside a nanoflow expression by analogy would previously have swapped one
`CE0117` for another; on current Mendix this specific substitution (function → token) now happens
to fully resolve the nanoflow case, but that is incidental to this bug, not evidence the
underlying gap is fixed — `currentDeviceType()` itself is still silently accepted and still fails
the build.

## Expected vs. actual

**Expected:** `mxcli check`/`mxcli exec` apply the same MDL044 validation to `CREATE NANOFLOW`
bodies that they now apply to `CREATE MICROFLOW` bodies, refusing or at minimum warning on
`currentDeviceType()` before it is written.

**Actual:** the nanoflow path bypasses this validation entirely — `check` reports success, `exec`
writes the invalid expression, and only a native mxbuild catches it, with `CE0117` giving no hint
that the root cause is the same known-invalid function call MDL044 already knows how to catch on
the microflow side.

## Severity

**High.** `check` does not even lint the nanoflow case, so for nanoflow authors this is worse than
the pre-MDL044 microflow situation: there is no signal anywhere in the mxcli-side toolchain before
a native build fails.

## Suggested fix

Call the same validation rule set (MDL044 / the check that now runs for `CREATE MICROFLOW`) from
the nanoflow creation path (`check`'s nanoflow validation and `exec`'s nanoflow write path), so
`currentDeviceType()` in a nanoflow body is caught before it is written, the same way it now is
for microflows.

## Workaround

Compute the device type outside the nanoflow (e.g. on a page conditional-visibility expression,
where the `[%CurrentDeviceType%]` token form is genuinely valid), or use the `[%CurrentDeviceType%]`
token form directly inside the nanoflow expression instead of the `currentDeviceType()` function
call (confirmed to build clean on Mendix 11.13 as of this retest, though this is not guaranteed to
generalize to every nanoflow expression position).

## Related

Closed issue #828 fixed the identical gap for microflows (`exec` writing an invalid
`currentDeviceType()` expression despite `check`'s MDL044 rule flagging it) — that fix's scope is
explicitly microflow-only per its own issue text, which is exactly the gap this report extends to
nanoflows.

---

**Status: FILED — https://github.com/mendixlabs/mxcli/issues/1033 (2026-09-04).**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "currentDeviceType
nanoflow CE0117" and "currentDeviceType" — found closed issue #828 (the microflow-side
predecessor, confirmed scoped exclusively to microflows, no mention of nanoflows) but no existing
issue covering the nanoflow gap as of 2026-08-31.
