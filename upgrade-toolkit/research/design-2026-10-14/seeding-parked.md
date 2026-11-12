# Seeding: the three parked questions + review of skills/fixture-seeding.md (PR #331)
Evidence: mxcli DESCRIBE against /root/run1/{vi,cl}/app, /root/run1/*/work/actions.json, upgrade-toolkit bin/*.py. Read-only.

## 1. Destructive actions: why today's ordering misses them, detection, isolation, labels
Why it failed: `gen_journeys.py:1359` sets `_destructive` on ANY `delete` effect; `run_journeys.py data_waves()` moves to the
`~last` pass only journeys that are `_destructive` AND `_path_needs`. Reset (`MasterData.Dashboard_Admin.actionButton2`) has
`needs: []`, so it runs in pass 1, and with `plan.json role_order` = None roles run alphabetically: Administrator first.
Also `delete` is noise as a signal: 47 of VI's / 44 of Checklist's runnable actions carry it (helper cleanups, Cancel).
Detection (add to `action_inventory.py flow()`, per action, transitive; emit `scope` next to `kind`):
- `delete-all`: a DB retrieve with NO XPath followed by delete of that list. Verbatim `DemoData.Demodata_DeleteAll`:
  `retrieve $InspectionList from Inspection.Inspection; delete $InspectionList;` (x5 entities).
- `identity`: the delete closure reaches `System.User`/`Administration.Account`, directly
  (`Demodata_ResetAccounts`: `retrieve ... from Administration.Account where id != '[%CurrentUser%]'; delete`) or by cascade.
  Closure = entities deleted + every association whose `DESCRIBE ASSOCIATION` says `on delete cascade` from them
  (`Employee_Account ... owner Both on delete cascade`) + explicit sub-flow deletes (`ACT_Employee_Delete` calls `Account_Delete`).
- `reimport`: deletes AND creates/commits the same entities, or reaches a module/flow named `*DemoData*|*Reset*|*Import*`
  (VI reach: `DemoData.ACT_Demodata_Reset`, `Demo_Import1..5`); name match only raises, never clears, the flag.
- `row`: everything else that deletes (one object it is given). Keep today's `~last` treatment for this tier only.
Isolation (default, in instrument order): `identity`/`delete-all`/`reimport` journeys never share a database with other
journeys: run them in a final pass on their own copy (`createdb -T X_frozen X_destr`, the baseline.md copy discipline), one
copy per journey when there are several, after the main set. `row` stays `~last`. Snapshot-restore between journeys is the
fallback when copies are too slow (cost: one restore per destructive journey). DEFECT_MAX comparability: count the
isolated pass separately (`destructive: P/F of N`) and keep it OUT of the main ratio, so before/after stay comparable
whichever side has the reset. Report label: `DESTRUCTIVE(identity)` on the journey line plus a header line
`destructive journeys: N isolated (identity a, delete-all b, reimport c)`; a login FAIL after any such journey in the same
DB is labelled `CONTAMINATED`, never FAIL. Toolkit side: this is the generator for journey-proof's existing hand tag
`"resetsData": true` (`--protect-state` refuses them); the skill should say so instead of "grep the inventory".

## 2. "Shown only if X" -> the seed row that satisfies it
Where it lives: each widget's `ConditionalVisibilitySettings` (expression, attribute+values, module roles). Already read:
`action_inventory.py shown_if()` -> per hop `shown_if`, carried to steps by `gen_journeys.py:808`, printed by
`run_journeys.py` as ` [shown only if ...]`. mxcli shows it too: `DESCRIBE PAGE` prints `Visible: <expr>`. Checklist: 111
of 292 actions are conditional; 54 attribute-form, 75 expression-form conditions.
Missing step = translate to a requirement, emitted beside the journey (`seed-needs.json`):
`{action, entity (the enclosing data view/list context entity), predicate (OQL WHERE), list_xpath (the list's data-source
XPath AND the role's access-rule XPath), role, measured: count}`. Translation: attribute form `Attr in [vals]` -> `Attr IN
(...)`; expression form: parse only `$currentObject/Attr` compared to a literal/`empty`/enum, `not()`, `and`; anything
else -> `predicate: MANUAL` with the raw text (never silently dropped). Module-role form -> NOT a seed need; persona issue
(interview Q1). Then measure with OQL; 0 rows = DATA-STATE finding before the run, not a FAIL after it. The runner must
also PICK the satisfying row (journeys click the first row: VI Inspection_Review `Status != Tickets_done` opened a closed
row), so pass the predicate to the row selector too.
Concrete miss it would have caught: `Masterdata.Dashboard_DepartmentManager.container34: not($currentObject/IsActive) and
$currentObject/RetiredDateTime = empty` (draft template). The seed's only inactive template `c_rack` HAS `RetiredDateTime =
-30d`, so 0 rows satisfy it: the 11 "INSTRUMENT (container34 conditional card)" fails are DATA-STATE. Fix: one draft row.

## 3. Checklist "Total number of checks during last 30 days: 2" -> app behaviour (misleading label), seed is right
`TotalKPIThisMonth` = `sum` over `KPIChartHelperNP_CreateChart_NonCompliantAnswersThisMonth`, which counts InstanceQuestions
`[Compliant = NotCompliant]` of instances with `StartDateTime` in the last 30 days, status Submitted/Resolved/Overdue_done,
of the department on the SELECTED TAB (and selected ChecklistType). It counts non-compliant ANSWERS, not checks, and uses
StartDateTime (not SubmittedDateTIme; the seed sets both, all within 30 days). Seed per department: Assembly (TabIndex 1,
first tab) = i6 Resolved, NC answers [3,7] -> 2, i8 -> 0 => **2**, exactly the shown value. Warehouse = 1, Quality Lab = 3.
Verdict: not a seed error; the label says "checks", the microflow counts non-compliant answers per tab. Record as an
app finding (label/semantics), not a fixture gap.

## 4. Review of skills/fixture-seeding.md (229 lines, 2482 words; +79 in this PR)
Rule 6 (over-long, one situation) - CUT:
- L166-176 "Generic traps" table rows 1-2 (ports `base+10+off`, container label): harness-specific to the upgrade
  toolkit's `run_variant.sh`; no consumer of this repo has that harness. Keep rows 3-7 (snapshot dup key, dates, sole
  target, role names, file rows) as a 5-row table.
- L83-86 "A reference implementation exists in the upgrade toolkit's research notes ... example, not a dependency":
  unreachable from a consuming project; cite nothing or the file once it is promoted into `bin/`.
- L197-205 "What seeding buys": keep the two ratios in one sentence; cut the bucket prose (duplicated by Done-when).
- L5-8 positioning paragraph ("sits above the mechanism references"): cut to one line in Related.
Rule 7 (show the failure) - REWRITE:
- L156-164 "Scan the actions": replace "Grep the action inventory (buttons, microflow names)" with: "Tag every journey
  that reaches a delete-all, an Account delete, or a cascade into Account `"resetsData": true` (journey-proof.md item 2)
  and run the set with `--protect-state`; run tagged ones on their own copy." A name grep misses the Employee cascade
  (`Employee_Account ... on delete cascade`), which is the one that cost 157 of 183.
- L92-101 bullets "5-20 rows", "Realistic invented values" carry no failure; add the draft-template miss from section 2
  to "one record in every status": status alone is not enough, a widget's `Visible:` can need a combination.
- Interview Q3/Q4 (L118-121): no failure shown; cut Q3 to one line or attach the case where a volume choice mattered.
Rule 4 (denominators): Done-when L216-220 is good. ADD: "- [ ] Every `shown_if` on a journey path has a measured row
count or `MANUAL` (C of C conditions)" and "- [ ] Every remaining FAIL classified DATA-STATE/INSTRUMENT/ENVIRONMENT/NO
BACKEND (F of F)". Change L219 to "Destructive journeys: D found, D tagged resetsData, D run on a copy".
Correctness:
- L135 `import from` "Bulk rows, from a file": WRONG. demo-data.md: "For bulk imports from an external database"
  (`sql connect ... as source; import from source query '...' into ... map (...) link (...)`). Rewrite "from another database".
- L132 `create demo user 'n' password 'P1!' entity Administration.Account (Role);`: real (manage-security.md:263).
- L82-83 `SHOW ENTITIES`, `DESCRIBE ENTITY`, `SHOW ASSOCIATIONS`: run OK here. Name the vague "enumeration and access
  listings" as `SHOW ENUMERATIONS IN <Module>`, `SHOW ACCESS ON <Module.Entity>`, and add `DESCRIBE ASSOCIATION` (shows
  `on delete cascade`) and `DESCRIBE PAGE` (shows `Visible:` and data-source XPath): both verified, both carry this skill.
- L33/L36 `bin/fixture-manifest.sh`: exists as `project-bin/fixture-manifest.sh` (install source); consistent with L36. OK.
- L3 `**Applies to:**` is free text; CLAUDE.md form is `migration | any mxcli project | requirements-driven`. Put the
  trigger words in the routing row, use `any mxcli project` here.
Routing (rule 1/8), `bin/lib/skill-routing.tsv:162`: fires on "seed data", "test data", "fixtures"/"fixture", "pages come
up empty" (≈ "empty pages"). Cut the summary tail ("Explore the data structure, choose rows ... never seed from inside the
harness"): content, not trigger. Suggested row: "Seed, test or demo data or fixtures are needed; pages, lists or
dashboards come up empty; a journey FAILs on a button 'shown only if'; a reset/delete journey wipes test users - BEFORE a
journey run". Re-render with `bin/render-routing.sh` and `--check`.
