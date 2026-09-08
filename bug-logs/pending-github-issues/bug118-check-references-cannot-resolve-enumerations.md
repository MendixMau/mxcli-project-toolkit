**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-118` — found 2026-09-07 writing script `88` of a
Phase-19 conversion project (Mendix 11.13.0)
**Status:** DRAFT — not yet filed
**Suggested labels:** bug, check, references, false-positive

---

**Title:** `mxcli check --references` reports "enumeration not found" for every enumeration,
including ones the shipped model already uses

**Body:**

## Summary

`mxcli check <script> -p <project>.mpr --references` cannot resolve **any** enumeration named in an
attribute declaration. It resolves entities, associations, microflows and pages in the same script
correctly; enumerations alone fall through and are reported missing.

## Repro

```
alter entity Approval."ApprovalRun"
  add attribute if not exists "CriticalPathStation": Enumeration(Approval.StationKey);
```

```
mxcli check script.mdl -p project.mpr --references
→ Reference errors:
    statement 4: attribute 'CriticalPathStation': enumeration not found: Approval.StationKey
```

The enumeration exists. `DESCRIBE ENUMERATION Approval.StationKey` returns all 19 values and
`SHOW ENUMERATIONS IN Approval` lists it. `mxbuild` validates the same declaration and returns
0 errors on the applied script.

## A/B probe — not the enum, not the statement form, not quoting

Four variants, one result each:

| Probe | Result |
|---|---|
| `alter entity … add attribute … Enumeration(Approval.StationKey)` | not found |
| same, enum name quoted — `Approval."StationKey"` | not found |
| `create or modify non-persistent entity … ("K": Enumeration(Approval.StationKey))` | not found |
| same, with `Approval.RunStatus` — an enum a dozen live attributes already use | **not found** |

The last row settles it. `Approval.RunStatus` is referenced by `ApprovalRun.RunStatus` in the
shipped model; a checker that could resolve enumerations at all would resolve that one.

## Impact

Most domain-model scripts declare at least one enumerated attribute, so most domain-model scripts
can never reach a clean `--references` run. The cost is not the noise itself — it is that the noise
**trains the reader to skim past reference errors**, which is how a real CE1613 gets shipped. On
projects where `check --references` is the pre-flight gate for every script, that is a standing
false negative in the one place the pipeline is supposed to be strict.

## Expected

Resolve enumerations the same way entities are resolved. Failing that, stay **silent** about
enumerations rather than reporting a false negative — an unchecked reference is better than a
wrong answer, because it does not erode trust in the checker's real findings.
