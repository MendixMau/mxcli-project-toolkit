**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-76: DECISION activities in a native WORKFLOW are
unconditionally storage-corrupted` (originally discovered 2026-08-13 on a client project, mxcli
v0.17.0; retested and confirmed still open 2026-08-20 on v0.18.0 and again 2026-08-31 on v0.20.0
— see `bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`)
**Status:** NOT YET FILED
**Suggested labels:** bug, critical, workflow, data-corruption

---

**Title:** `CREATE WORKFLOW ... DECISION` writes the outcome label as a raw string instead of an
`EnumerationValueIdentifier` — project fails to load with `StorageLoadException`

**Body:**

## Summary

Any `.mpr` containing one or more `DECISION` activities inside a `CREATE WORKFLOW` (or `CREATE OR
MODIFY WORKFLOW`) round-trips cleanly through every mxcli-native validation path — `mxcli check
--references`, `mxcli exec`, `DESCRIBE WORKFLOW` — all report success, and `exec` prints `Created
workflow: ...` with no error. But the project **fails to load at all** in real Mendix tooling
(Studio Pro, native `mxbuild`, and `mxcli docker check`, which shells out to the same native
loader). The failure is a hard `Mendix.Modeler.Storage.StorageLoadException` thrown before any
check/build logic even runs — the project is unloadable, not merely un-buildable.

This is CRITICAL: it silently corrupts the model in a way invisible to every mxcli-side command,
and by the time it's discovered (only a real Studio Pro/native-mxbuild load surfaces it), an
arbitrary number of subsequent scripts may have executed and been gate-passed on top of the
corruption.

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new` (split-model MPR v2)
- Verdict source: native `mxbuild`/`mx check` via `mxcli docker check` (real consistency check,
  not just `mxcli check`'s own reference validation)
- Originally discovered: 2026-08-13, mxcli v0.17.0, Mendix 11.13.0, on a real project's native
  Approval-workflow build. Reproduced independently since on v0.18.0 (2026-08-20) and v0.20.0
  (2026-08-31), on a disposable scratch copy each time — never on a real project after the first
  discovery.

## Steps to reproduce

Minimal repro, on a fresh `mxcli new`-scaffolded project with any module/entity in scope for the
workflow's context parameter:

```sql
create workflow Flow.WF_Dec
  parameter $Ctx: Flow.Item
begin
  decision '1 = 1'
    outcomes 'OutcomeA' -> { }
             'OutcomeB' -> { };
end workflow;
/
```

```
$ ./mxcli check flow.mdl -p Test.mpr
All references valid.

$ ./mxcli exec flow.mdl -p Test.mpr
Created workflow: Flow.WF_Dec

$ ./mxcli docker check -p Test.mpr
ERROR: Mendix.Modeler.Storage.StorageLoadException: One or more invalid values were detected
while loading the project: Mendix.Modeler.Projects.Project:
 - Enumeration value condition outcome in  has an invalid value '' for property Value. The text
   'OutcomeA' is not a valid EnumerationValueIdentifier.
 - Enumeration value condition outcome in  has an invalid value '' for property Value. The text
   'OutcomeB' is not a valid EnumerationValueIdentifier.
```

One error line per `DECISION` outcome — the flagged text is always the outcome's own label. The
outcome names are brand-new, never-before-used strings on a trivial literal boolean expression
(`1 = 1`, no attribute or enumeration involved at all) — this rules out any theory that the bug is
tied to enum-valued expressions specifically. It reproduces identically whether the decision's
condition expression reads an actual enumeration attribute or a plain String attribute.

## Expected vs. actual

**Expected:** `mxcli exec` either writes a real `EnumerationValueIdentifier` object into the
`ConditionOutcome.Value` field (matching what Studio Pro itself writes when a DECISION is added
via the GUI), or refuses to write a `DECISION` activity at all with a clear error, rather than
reporting success on a write that corrupts the project.

**Actual:** `mxcli exec` writes the literal outcome label (`'OutcomeA'`, `'OutcomeB'`, or any
user-chosen name) straight into a storage field that Mendix's loader requires to deserialize as a
proper `EnumerationValueIdentifier` object, not a bare string — reporting success while doing so.
The corruption is invisible to `mxcli check --references`, `mxcli exec`'s own output, and
`DESCRIBE WORKFLOW`/`DESCRIBE MICROFLOW` (both print the outcomes back correctly, with no
indication of the underlying storage-type mismatch). Only a real native `mxbuild`/Studio Pro load
surfaces it.

## Severity

**Critical.** The project becomes completely unloadable in Studio Pro and native `mxbuild` — not
a build-time error on an otherwise-open project, a load-time crash before any tooling can even
inspect the model. No MDL-only workaround exists: varying the outcome names, the expression shape
(string vs. enum-typed attribute vs. literal), or adding the `DECISION` via `CREATE` vs. `CREATE
OR MODIFY WORKFLOW` all corrupt identically.

## Suggested fix

`DECISION` activity codegen needs to construct a real `EnumerationValueIdentifier` object (or
whatever internal identifier type Mendix's loader expects for `ConditionOutcome.Value`) instead of
writing the outcome's display label as a raw string. Given the severity (unloadable project, zero
detection by any mxcli-side command), also worth having `mxcli check` and/or `mxcli exec` refuse
`DECISION` activities up front until the writer is fixed, rather than reporting silent success.

## Workaround

Do not use `DECISION` activities in mxcli-authored `WORKFLOW` definitions at all, for any
expression type. Build the native workflow with decision points left out, then add the `DECISION`
gateways manually in Studio Pro after the fact.

## Related

`mxcli syntax workflow --json`'s own documented DECISION grammar (`DECISION ['<caption>'] OUTCOMES
'<outcome>' { ... } ...;`, no arrow) is also wrong/incomplete — the real required grammar needs
`DECISION '<boolean-expression>' OUTCOMES 'name' -> { } ...;` (arrow required), and `mxcli -c "HELP
DECISION"` returns no help text at all. Neither the wrong docs nor the missing help contributed to
this specific corruption (it reproduces with correct arrow syntax too), but both should be fixed
alongside it.

---

**Status: DRAFTED 2026-08-31, not yet filed.**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "EnumerationValueIdentifier",
"workflow decision EnumerationValueIdentifier", and "workflow DECISION EnumerationValueIdentifier
StorageLoadException" — no existing issue found as of 2026-08-31.
