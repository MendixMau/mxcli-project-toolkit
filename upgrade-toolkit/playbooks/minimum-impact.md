# Playbook: minimum-impact upgrade order (TRIAL)

Source: a colleague's upgrade practice (input 2026-10-08); no field run yet. Status: **trial**. The default order in
SKILL.md ("Version path") and [steps/upgrade.md](../steps/upgrade.md) stays in force until a side-by-side run (section 4)
shows this order needs fewer repair rounds. Nothing here relaxes a gate: every rung still goes through steps 3 to 6 with
its own verdict.

## 1. The order

Phase A, make it work with the least change:
1. Convert the platform to the target version (the playbook for the path: [9-to-10](9-to-10.md), [10-to-11](10-to-11.md),
   [11-to-11](11-to-11.md)).
2. Per Marketplace module that does not load or has errors: install the **lowest** version that supports the target
   (its "min Mendix" at or below the target and its "max" not below it), not the newest. Same batch runner, same step
   idcheck: `stepupdate.sh` with a plan of those versions.
3. Repair what is left until `mx check` has 0 errors (step 4). Each error code goes through `repair/` and the playbooks.
4. Gate the rung (step 5). This verdict is the **platform verdict**: it answers "did the convert break the app".

Phase B, bring the essentials up to date:
5. Per essential module (security fixes, modules the app's own logic calls), update to the newest version that fits the
   target, one `step:` commit each.
6. Gate again with `--only` for the rungs the module touches, then the full gate once at the end. This verdict is the
   **module verdict**: a difference that first shows here belongs to a module release, not the convert.

Phase C, optional, never in the same rung as A or B:
7. Modernisation, from the advisory reports triage already writes: Dojo widgets to React (`dojo_report.py`,
   `$W/dojo-react.md`), Atlas 3 to 4, strict mode, platform replacements for modules (`replacement_check.py`,
   `$W/replacements.md`: deep link to page and microflow URLs, OQL module to view entities, old custom widgets).
   Each one is its own change with its own gate.

Why this order: in the default order a module update and the convert land in one rung, so a FAIL can come from either.
Here phase A has the fewest moving parts, and a FAIL in phase B points at one module.

Where it differs from the default: the default takes the newest version that fits each step. On a 10.x source below
10.24 the default's pre-convert module pass stays REQUIRED (it makes the `step:` commits `convertmade.sh` needs, T7-3);
this playbook adds no shortcut around it.

## 2. Modules that need more than one deployment (data conversion)

Some module releases convert stored data, and the data only converts if the app is **deployed and started** on an
intermediate version before the next one is installed (a migration that runs after startup, a legacy column read once
and then dropped). Skipping that start loses or corrupts the data, and a gate that starts the new app only once on the
old data can miss it.

At triage, per module jump, read its release notes (`release_impact.py` rows) for: migration, "run ... before
upgrading", "after startup", "deploy version X first", "legacy" attribute or entity removed. For each hit:
- Split the jump into module rungs: install the intermediate version, build, **start on a copy of the old database**
  until the migration has run (its log line or the converted rows), snapshot, then install the next version.
- Each intermediate start is a data rung of its own in the gate (`--psql`), compared with the old data; the effect
  record must show the converted rows.
- Record the chain in `$W/module-rungs.md` (module, versions in order, what proves each migration ran). In production
  this is one deployment per rung: say so in the report, it is a release plan item, not a technical detail.

Known modules of this kind: _to be filled_ (list asked from the colleague; add each with its release-note line).

## 3. What the report must say

Per rung: the platform verdict (phase A) and the module verdict (phase B), separately. Phase C items appear only as
advisory rows unless the user asked for them. A module left at its lowest compatible version is listed with the
newest available version beside it, so nobody reads "compatible" as "current".

## 4. Trial: how this order is judged

Run one small app (batch-5 size, under 60 actions) twice from the same source, once in the default order and once in
this one, same target, same gate. Compare per run, from the JOURNAL: repair rounds, gate rounds, minutes, cost, and
whether each FAIL could be traced to one cause. This order becomes the default only if it is no worse on verdict and
better on repair rounds or traceability; write the result here and in FEEDBACK.md.
