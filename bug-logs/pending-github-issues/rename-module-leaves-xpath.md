**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-DRAFT-rename-module-leaves-xpath` — found 2026-09-25 (field report on v0.23.0, retested on v0.24.0)
**Status:** NOT YET FILED
**Suggested labels:** bug, rename, xpath
**Duplicate check:** searched 2026-09-25 (`rename module does not rewrite XPath constraints`). No match. Related but different: #910 / 35efa0207 (XPath rewrite on **attribute** rename, unreleased), #1049 (dangling XPath member passes `check --references`), #473 and #426 (rename module implementation).

---

**Title:** `rename module` reports its references updated but leaves XPath constraints naming the old module (CE1613 at build)

**Body:**

## Summary

`mxcli rename module A B` rewrites the structural references and reports a count, but a qualified name inside a retrieve's XPath constraint still names the old module. In a field run on a larger app this gave "407 references updated" and then 34 CE1613 from 10 microflows plus one legacy data grid's XPath.

**Version:** mxcli v0.24.0 (also v0.23.0), Mendix 11.12.1 / 11.12.4, MPR v2.

## Repro

```
create persistent entity RenA.Owner (Label: String(50));
create association RenA.Item_Owner from RenA.Item to RenA.Owner;
create microflow RenA.SUB_Assoc ()
returns Boolean as $Ok
begin
  declare $Ok Boolean = false;
  retrieve $Items from RenA.Item
    where RenA.Item_Owner/RenA.Owner/Label = 'x';
  if $Items != empty then
    set $Ok = true;
  end if;
  return $Ok;
end;
/
```

```
mxcli exec repro.mdl -p App.mpr
mxcli rename -p App.mpr module RenA RenB
mxcli -p App.mpr -c "describe microflow RenB.SUB_Assoc"
```

## Measured (v0.24.0)

```
Renamed module: RenA → RenB
Updated 6 reference(s) in 4 document(s)
...
    where RenA.Item_Owner/RenA.Owner/Label = 'x';
```

A simpler `where RenA.Item/Name = 'x'` in another microflow is left unchanged as well. `SEARCH 'RenA.'` returns "No matches found.", so the stale names cannot be found in-tool either. `grep -rl RenA mprcontents/` finds the units.

## Expected

Every module-qualified name in XPath constraints (retrieves, widget datasources, access rules) and in expressions follows the rename, as #910 now does for attribute renames.

## Workaround

Describe each affected microflow, correct the module name by hand, and re-create it, then run `mx check`.
