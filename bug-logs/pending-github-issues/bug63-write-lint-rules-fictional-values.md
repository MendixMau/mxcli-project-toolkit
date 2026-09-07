**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-63: write-lint-rules.md documents API values that do
not exist — every action_type example is wrong, and source_type case is wrong — so rules written
from the guide silently match nothing` (originally discovered 2026-08-11 on a WMS demo project
while writing a lint rule; retested and confirmed still open 2026-08-31 on v0.20.0 by direct
inspection of the shipped skill file — see `bug-logs/mxlabs-v0.20.0-retest-2026-08-31.md`)
**Status:** FILED — https://github.com/mendixlabs/mxcli/issues/1027 (2026-09-04)
**Suggested labels:** bug, documentation, lint

---

**Title:** The bundled `write-lint-rules` skill documents `action_type`/`source_type` API values
that do not exist — rules written from the guide's own examples silently match zero violations

**Body:**

## Summary

The bundled skill that documents the Starlark lint-rule API — currently shipped as
`write-lint-rules/SKILL.md` (previously `.ai-context/skills/write-lint-rules.md` in earlier
directory layouts) — is the only documentation of this API, and two of its example tables give
values the API never actually returns. Both failure modes are silent: a rule built against the
documented values compiles, runs, matches nothing, and reports a clean pass with zero violations.
Nothing in the tool warns that the values are wrong.

**`action_type` (currently around line 318 of the directory-shaped `write-lint-rules/SKILL.md`,
previously line ~311/313 of the flat file).** The guide's example values are fictional:

| Guide says | Actually returned |
|---|---|
| `CreateChangeAction` | `CreateObjectAction`, `ChangeObjectAction` |
| `CommitAction` | `CommitObjectsAction` |
| `ShowFormAction` | `ShowPageAction` |
| `CloseFormAction` | `ClosePageAction` |
| `ShowHomeFormAction` | no counterpart exists |

**`source_type`.** The guide gives lowercase examples (`"microflow"`, `"page"`); the API actually
returns uppercase (`PAGE`, `MICROFLOW`, `SNIPPET`, `NANOFLOW`, `ENTITY`, `ASSOCIATION`,
`NAVIGATION`).

## Environment

- mxcli: `v0.20.0` (tag, built from source, `git describe --tags` = `v0.20.0`, clean tree)
- Verified by direct inspection of the skill file shipped inside the v0.20.0 binary's
  distribution: `write-lint-rules/SKILL.md`, ~line 318, same fictional `action_type` row as the
  original 2026-08-11 finding
- Confirmed with real catalog data on a separate real-world project (a WMS demo project's
  `.mxcli/catalog.db`): 294 entities, 1,177 microflows, 10,012 activities, 6,312 typed reference
  edges — see Evidence below
- Originally discovered: 2026-08-11, mxcli (contemporaneous pinned build), while writing a
  Starlark lint rule against the documented API. Independently re-verified by inspection on
  v0.18.0 (2026-08-20) and v0.20.0 (2026-08-31); the fictional values are unchanged across all
  three checks, only the file's location moved (flat file → directory-shaped skill).

## Evidence

```
$ sqlite3 .mxcli/catalog.db "SELECT DISTINCT SourceType FROM refs ORDER BY 1;"
ASSOCIATION / ENTITY / MICROFLOW / NANOFLOW / NAVIGATION / PAGE / SNIPPET

$ sqlite3 .mxcli/catalog.db \
    "SELECT ActionType, COUNT(*) FROM activities GROUP BY 1 ORDER BY 2 DESC;"
MicroflowCallAction|1031   RetrieveAction|775    ChangeObjectAction|483
CreateObjectAction|298     LogMessageAction|292  CommitObjectsAction|129
ShowPageAction|120         ShowMessageAction|105 ClosePageAction|69
...
```

Zero rows for `CreateChangeAction`, `CommitAction`, `ShowFormAction`, `CloseFormAction`,
`ShowHomeFormAction` — the guide's own documented `action_type` examples never occur in real data.

## Impact — not theoretical, it silently broke a shipped rule

A rule scaffolded into downstream projects (a "no undelegated business logic in ACT_ microflows"
convention check) took its allowlist verbatim from the guide's `action_type` table. Because the
real `ShowPageAction` and `ClosePageAction` were absent from the allowlist, the single most common
thing such a microflow does — showing or closing a page — was flagged as a violation. Measured on
one real project: **138 of 282 `ACT_` microflows flagged, 49% false positives.** The rule was not
merely inert; it was inverted, and lint on that project was subsequently demoted to
optional/non-blocking and then stopped being run at all.

## Expected vs. actual

**Expected:** the skill's `action_type` and `source_type` example tables list values the lint API
actually returns, so a rule authored straight from the documentation matches real activities.

**Actual:** every `action_type` example is a name that never occurs, and `source_type` examples
are the wrong case — a rule built from either table compiles and runs cleanly but matches nothing,
with no warning that the values were never valid.

## Severity

**Medium-high.** Silent, confident-looking false negatives (and in the observed real case, false
positives from an inverted allowlist) in exactly the kind of governance/convention tooling meant
to catch defects — a wrong rule that reports "0 violations" is worse than no rule, since it looks
like coverage that isn't there.

## Suggested fix

1. Correct both example tables in the generator for the shipped `write-lint-rules` skill against
   the values the API actually emits (per the Evidence section above).
2. Consider generating the documented value tables from the same enum the adapter emits, so the
   documentation cannot drift from the real API again.
3. Consider having the lint-rule runtime warn (not just silently match zero results) when a rule's
   `action_type`/`source_type` filter values never appear anywhere in the loaded catalog — that
   would have caught this class of defect at rule-authoring time instead of via a 49%
   false-positive measurement on a real project.

## Workaround

Never take an `action_type`/`source_type` value from the skill's documentation. Probe the real
catalog before writing any rule:

```bash
sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType FROM activities;"
sqlite3 .mxcli/catalog.db "SELECT DISTINCT SourceType FROM refs;"
```

---

**Status: FILED — https://github.com/mendixlabs/mxcli/issues/1027 (2026-09-04).**
Duplicate-check: searched `mendixlabs/mxcli` issues (open and closed) for "write-lint-rules
action_type" and "write-lint-rules skill action_type values" — no existing issue found as of
2026-08-31.
