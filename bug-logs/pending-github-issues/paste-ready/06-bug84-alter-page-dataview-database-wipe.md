`ALTER PAGE { SET DataSource = DATABASE Module.Entity ON <dataview>; }` reports success but silently wipes the DataView's datasource entirely — `CE7007` downstream


## Summary

`ALTER PAGE ... { SET DataSource = DATABASE Module.Entity ON <dataview-widget>; }` — a `DATABASE`
datasource, which is not a legal datasource type for a DataView in Mendix — is accepted by mxcli,
reports success (`Altered page ...`, exit 0), and leaves the DataView with **no DataSource
property at all**. The only downstream signal is a `CE7007` error at native build time, on a page
that mxcli itself reported as successfully altered.

mxcli already rejects the *association*-typed form of this same operation at MDL time with an
actionable error naming `REPLACE` as the supported route (see the related, already-filed issue
#855 / `bug-logs/pending-github-issues/bug11-dataview-datasource-type.md`) — the `DATABASE` form
should be rejected the same way instead of being half-applied (accepted, but silently destructive).

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Mendix Studio Pro / mxbuild: `11.13.0`
- OS: Linux amd64
- Baseline: a blank Mendix 11.13.0 project scaffolded fresh by `mxcli new`
- Verdict source: native `mxbuild`/`mx check` (`mxcli docker check`), plus `DESCRIBE PAGE`
  read-back confirming the DataSource property is gone
- Originally discovered: 2026-08-20, mxcli v0.18.0, Mendix 11.12.0, on a scratch page project
  while retesting BUG-11. Reproduced independently since on v0.20.0 (2026-08-31); note the
  bracketed `ALTER PAGE Module.Page { SET ... ; }` syntax form is required on current mxcli — the
  older flat `alter page x set p = v on w;` form no longer parses.

## Steps to reproduce

Setup: a page with a DataView `dvCust` whose datasource is anything valid (e.g. a microflow
datasource):

```sql
create page Test.MyPage (
  params: { },
  title: 'My Page',
  layout: Atlas_Core.Atlas_Default
) {
  dataview dvCust (datasource: microflow Test.ACT_GetCustomer) {
    textbox txt (label: 'Name', attribute: 'Name')
  }
};
```

```
$ ./mxcli exec setup.mdl -p Test.mpr
Created page: Test.MyPage
```

Now attempt to point the DataView at a `DATABASE` datasource:

```sql
ALTER PAGE Test.MyPage {
  SET DataSource = DATABASE Test.Customer ON dvCust;
};
```

```
$ ./mxcli exec alter-set.mdl -p Test.mpr
Altered page Test.MyPage
```

```
$ ./mxcli describe page Test.MyPage -p Test.mpr
...
dataview dvCust {
  # DataSource property is gone entirely
  textbox txt (label: 'Name', attribute: 'Name')
}
...

$ ./mxcli docker check -p Test.mpr
[error] [CE7007] "Selected value is not valid for entity 'Customer'." at ... dvCust ...
```

`mxcli exec` reports success and exit 0 in every run; the datasource loss and the `CE7007` are
both silent until the native build step.

## Expected vs. actual

**Expected:** a DataView cannot legitimately take a `DATABASE` datasource — `mxcli check`/`exec`
should reject the statement at MDL time with an actionable error, the same way the `association`-
typed form is already rejected (naming `REPLACE` as the supported route for changing a DataView's
datasource structural type).

**Actual:** the statement is accepted, `exec` reports success, and the DataView's `DataSource`
property is left entirely absent — a strictly worse outcome than an explicit rejection, since
nothing signals the failure until a native build.

## Severity

**High.** Silent success on a write that destroys a widget's datasource, surfacing only at native
build/check time via an error (`CE7007`) that does not point back to the actual cause (the earlier
silent `ALTER PAGE SET`).

## Workaround

Never issue the `DATABASE` form of `SET DataSource` against a DataView. Use `ALTER PAGE ...
REPLACE` to rebuild the widget with the desired datasource instead (the same workaround documented
for the related association-type rejection), or set a microflow/page-parameter datasource.

## Suggested fix

Extend the existing structural-type rejection (already in place for `association`-typed
reassignment) to also reject `DATABASE`-typed reassignment on a DataView, with the same actionable
error pointing at `REPLACE`, instead of accepting the statement and leaving the widget with no
datasource at all.

## Related

- #855 (closed, filed from this toolkit's BUG-11) — `SET` already rejects reassigning a DataView's
  datasource to a `parameter`-typed value with an explicit error naming `REPLACE`; this report asks
  for the same treatment for the `DATABASE` form, which is currently accepted and silently
  destructive instead of rejected.

---

**Status: DRAFTED 2026-08-31, not yet filed.**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "DataView DataSource
DATABASE silently wipes CE7007" and "DataView DATABASE datasource wipe" — no existing issue found
as of 2026-08-31. Closed issue #855 (already filed from this toolkit, BUG-11) covers the related
but distinct `parameter`-type rejection case — not a duplicate of this `DATABASE`-type silent-wipe
case.
