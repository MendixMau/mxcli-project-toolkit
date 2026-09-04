Quoting a microflow parameter as `"$Name"` keeps the `$` inside the stored parameter name — `check --references` passes, mxbuild fails CE1613


## Summary

The documented house rule is "always quote identifiers; quotes are stripped automatically". Applied to a microflow parameter it produces a corrupt name:

```sql
create microflow M.Flow ("$Item": M.Item)
begin
  return $Item/Name;
end;
```

The quotes are stripped but the `$` stays **inside** the parameter name, so the model holds a parameter literally named `$Item`. The body's `$Item` then resolves as sigil + `Item` and matches nothing.

## Environment

- mxcli built from source at `4b58b89` (2026-08-26); Mendix 11.13.0

## Steps to reproduce

1. `mxcli check --references flow.mdl -p App.mpr` → passes.
2. `mxcli exec flow.mdl -p App.mpr` → `Created microflow M.Flow`.
3. `mxbuild` → `CE1613` (unknown variable) on the body reference.
4. `DESCRIBE MICROFLOW M.Flow` shows the parameter as `$$Item` or `"$Item"` depending on the quoting mode.

## Expected vs. actual

**Expected:** either the sigil is stripped along with the quotes (parameter name `Item`, referenced as `$Item`), or `check` rejects `"$…"` as a parameter name.

**Actual:** the sigil is stored as part of the name; `check --references` does not see it; the failure appears only at mxbuild.

## Severity

High for agent-driven use: the always-quote rule is what LLM authors are told to follow, and this is the one place it produces a corrupt model instead of a safe one.

## Workaround

Never quote the `$`-prefixed form: `$Item: M.Item`. Regenerate any microflow already written the wrong way.

## Suggested fix

Strip a leading `$` from a quoted parameter name at parse time (matching the unquoted form), or make `check --references` reject a parameter name that starts with `$`.
