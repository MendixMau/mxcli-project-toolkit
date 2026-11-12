# Seeding learnings: Visual Inspection 3.0.0 (9.24.23) and Checklist to go 1.0.0 (9.24.2)

Final numbers are in the section "Results". Public template apps, invented
values, no customer data. Scripts and specs sit beside this file.

## What had to be derived (and from where)

| question | answered by | tool |
|---|---|---|
| which entities are persistent, what must be filled, which association hangs a child on a page | the .mpr | `domain_map.py` (offline, over `bin/mprmodel.py`) |
| which page lists which entity under which XPath, for which role | the .mpr page tree | `page_data_needs.py` |
| which enum value a page filters on (so every value needs a row) | XPath strings in the page needs + enumerations | `page_data_needs.py` + `domain_map.py` |
| which Employee/Account link scopes the Inspector's list | access-rule XPath (`[Employee_Account='[%CurrentUser%]']`, `InstanceChecklist_Employee_Responsible/...`) | `domain_map.py` (access lines) |
| what the publisher already shipped | `data-snapshot.zip` inside the .mpk (Visual Inspection only) | `seed_snapshot.py`, then count per entity |
| what is still missing after the snapshot | counts in Postgres vs the page needs | `gen_vi_spec.py` (reads keys by lookup) |

## Route that worked
- Visual Inspection: route (a), publisher snapshot, then a small gap spec (route b) for what the snapshot does not hold
  (Employee links to the test users, Tasks, inspections owned by the Inspector, the two Settings rows) and a uniform date
  shift so "this week" counters are not 0.
- Checklist: no snapshot in the package, so route (b): a hand-written use-case spec (`gen_checklist_spec.py`) through
  `seed_usecase.py` (same id scheme and mapping reader as `seed_pg.py`, but it fills only what a use case needs, in the
  states pages filter on, with links). 429 objects: 3 departments, 6 templates, 2 groups x 4-5 questions with all five
  question types, 11 instances covering all 8 statuses, history items, 6 employees (3 linked to the test users).
- Route (c) (UI) was not needed; nothing in these two apps needs state that SQL cannot build, except file contents
  (Image/FileDocument), which we left out on purpose.

## Traps, with the exact symptom

1. **Destructive journey wipes the seed and the test users.** VI `Dashboard_Admin` has the button "Reset all demodata";
   the generated journey `act-MasterData.Dashboard_Admin.actionButton2` presses it (Proceed). The app deletes every
   account and re-imports its own 25-inspection demo set. Symptom: Administrator passes, then every Inspector and
   QualityManager journey reports `login FAIL: The username or password you entered is incorrect`
   (104 of 127 journeys), the same on an empty and a seeded database, so before/after look identical. Fix used: run the
   set without that one journey (`JOURNEYS=` override in `run_variant.sh`), count it separately as a data-destroying action.
   A seed skill must scan the action inventory for reset/delete-all/import actions before the run and run them last or
   on a copy.
2. **Port offsets collide.** `PORT_OFF` shifts both ports: app = 8080+off, admin = 8090+off, so off=10 puts the app on
   8090 = the admin port of off=0. Symptom: `INFRA port 8090 in use by mig-...`. Use offsets that are multiples of 20.
3. **Container name = prefix of the label.** `run_variant.sh` names the runtime `mig-<label>-j<label>`. Two apps with the
   same label (`empty`) get the same container; removing one removed the other's running app mid-run, symptom: every role
   `login INVALID`, 183 journeys `runner did not run`, `Timeout navigating to login.html`. Use app-specific labels.
4. **`seed_snapshot.py` stops on the HSQLDB LOB block map.** Symptom: `UNMAPPED (1): statement not understood: INSERT
   INTO BLOCKS VALUES(0,2147483647,0) (default.log:2)` and `--skip BLOCKS` does not help (skip is per mapped table).
   Fixed in `bin/seed_snapshot.py` (statement ignored, it is HSQLDB bookkeeping).
5. **Snapshot vs rows the app creates at first start.** Loading onto a database the app already started on:
   `ERROR: duplicate key value violates unique constraint "uniq_deeplink$deeplink_name"` (the app creates its deeplink
   rows itself). Waive that table with `--skip 'deeplink$deeplink'`; the tool reports the waiver. Expect one such table per
   Marketplace module that seeds itself at startup.
6. **Snapshot dates.** The VI snapshot is dated 2024-07; the manager dashboard counts "this week". `rebase_dates.py`
   shifts every timestamp by one interval (keeps gaps); it must run BEFORE a gap spec that uses relative dates, or the
   anchor is the new rows and the tool says `nothing to do: the newest value is already after the target`.
7. **`--sole-target` removes the snapshot's own demo users from their roles** (`role Inspector taken from 6 other user(s)`):
   intended, but it means the snapshot's inspections are owned by employees nobody can log in as; the gap spec therefore
   re-owns three inspections to the Inspector's employee.
8. **Role names are not the same across the two apps** (VI: QualityManager, Checklist: DepartmentManager); users.json and
   the `--roles` list must come from `system$userrole` of the actual database, not from habit.
9. **Administrator "delete" journeys cascade into the test users (Checklist).** `Employee_Account` deletes the Account when the
   Employee goes (`DeleteMeAndReferences` on both sides), and the Employee_Overview delete journey (and others) runs as
   Administrator FIRST. Symptom after that pass on the seeded Checklist database: 0 instance checklists left, 1 account of 3,
   and 157 of 183 journeys `login FAIL: The username or password you entered is incorrect`; the first full run showed
   18 PASS (worse than empty, 20). Fix used: Administrator journeys on one fresh copy, the other roles on another fresh copy
   (journeys folder split, `JOURNEYS=`), results added up. Seeds that link Employee to Account are exactly what makes this
   bite; an empty database hid it (nothing to delete).
10. **Container name is `mig-<label>-<name>`**: `docker rm -f mig-vishot-jvishot` removed nothing and the next app on that
   port failed with `INFRA port 8140 in use by mig-vishot-vishot`; a screenshot run then silently hit the OLD app and printed
   another app's page. Check the landing text names the right app.
11. `pkill -f <pattern>` inside a Bash tool call matches the tool call's own command line and kills the shell (exit 144).
   Use `kill <pid>` from `pgrep`.

## What baseline.md / fixture-seeding.md were missing
- Neither says to look for **data-destroying actions** (reset, import, delete-all) before the journeys run (trap 1).
- baseline.md names the three routes but not how to pick the *content* inside a route: no step "read the XPaths on the
  pages and make one row per enum value the pages filter on", no step "link the test users to a domain object (Employee)
  so role-scoped lists are not empty".
- fixture-seeding.md derives needs from journeys (`fixture-manifest.sh`); for a legacy app with a snapshot the better
  source is the page tree (`page_data_needs.py`), because journeys that never reach a page declare no need for it.
- No mention that a snapshot's FileDocument/Image rows need their files copied after every start
  (`start_with_files.sh`; `FileNotFoundInStorageException` otherwise) and that `runapp.py start` wipes `data/files`.
- Dates: nothing says a snapshot must be time-shifted.

## Proposals for a seed-data skill
1. **Explore** in this order, all offline: entities (persistent only) with required/unique/default; associations with
   owner and delete behaviour (parent -> child is the direction a page needs); enumerations; access rules per role with
   XPath; page data sources with XPath. Output one table: entity | who needs it | state. (`domain_map.py` +
   `page_data_needs.py` + the two data-map files here are the worked example.)
2. **Choose data per use case**, not per entity: name the story (a plant with 3 departments; an inspector with two ongoing
   inspections), then give every enum value the pages filter on at least one row, give the test user's own scope (the
   XPath-limited list) 2-3 rows, give every "children" list at least 2 children, one entity per status in the middle of
   its lifecycle and one in each end state.
3. **Referential integrity first**: set every association a page follows; make derived counters consistent with their
   children (NumberOfTickets = number of defects) because microflows maintain them, SQL does not.
4. **Realistic invented values** (names, serial numbers `SI-20261013-001`, mail at example.com), relative dates from "now",
   deterministic ids (uuid5) so reruns give the same SQL; idempotency by always rebuilding from an empty frozen copy.
5. **Check before trusting**: count per entity and per status in SQL, open one page per role and read it, grep the runtime
   log for errors, then run the journeys with the destructive ones aside.


## Results (journeys on the ORIGINAL apps, 9.24, Responsive profile, DEFECT_MAX untouched)

Journey counts are PASS / FAIL / INVALID; INVALID is the generated-but-not-runnable set (no click path, no role,
external call, Phone profile) and is the same before and after, seeding cannot change it.

| app | empty database | seeded | note |
|---|---|---|---|
| Visual Inspection 3.0.0 | 33 / 93 / 68 | **58 / 68 / 68** | without the data-wiping "Reset all demodata" journey (126 run). With it: empty 8 / 119 / 68 (104 login failures after the wipe); the seeded run with it was stopped, same mechanism. Coverage of actions 15% -> 28% |
| Checklist to go 1.0.0 | 20 / 163 / 114 | **51 / 132 / 114** | Administrator and the other roles run on separate fresh copies (trap 9). Single run on the seeded copy: 18 / 165 / 114. Coverage 5% -> 10% for the non-admin part alone (31/292), admin part not summed |

Seeded rows. Visual Inspection (snapshot 639 rows in 33 tables + 29 gap objects): 28 inspections (9 Open, 12 Inspection_done,
7 Tickets_done), 89 defects in 3 statuses, 5 tasks, 13 employees (3 linked to the smoke users), 2 products with views,
locations, 23 defect types. Checklist (429 objects, no snapshot): 3 departments, 3 checklist types, 6 templates (5 active, 1
retired), 12 groups, 54 template questions of the 5 types with options, 11 instances covering all 8 statuses with 99 instance
questions and 143 options, history items, 6 employees (3 linked to smoke users).

Pages read per role (screenshots in the run folder, not committed): VI Inspector landing lists 9 ongoing inspections, QualityManager
dashboard shows counters (6 defects, 2 inspections this week, status pie 42.9/32.1/25) and 12 inspections to review, Defects
overview lists code-labelled defect types; Checklist DepartmentManager dashboard shows 3 department tabs, checklist cards,
non-compliant charts and 4 open reviews, Executed checklists lists 3 rows with "No 5/9" compliance, Inspector landing lists the
two departments with 1 and 3 checklists. No empty page found. Runtime log: VI `Failed to load PDF file` / `importScripts
cdnjs.cloudflare.com pdf.js` (122x, no outbound CDN in the sandbox), `No configuration set to active` (chatbot, 8x), and
before the snapshot files were copied `The file 'eRod-... view.svg' could not be found` (54x each).

### Remaining failures, classified (seeded runs)
Visual Inspection, 68 FAIL: 29 INSTRUMENT (SelectArea `dataGrid23`: rows render but the engine finds no visible row; the grid
is conditional on a marker click in the plan viewer); 9 ENVIRONMENT (plan viewer / marker widgets never appear:
pdf.js from cdnjs unreachable); 8 DATA-STATE or row pick (Inspection_Review: action shown only when Status != Tickets_done, the
journey opened a closed row); 7 NO BACKEND (chatbot popup, AWS Bedrock not configured; the seeded config row is inactive on
purpose); 15 INSTRUMENT (microflow-button journeys on grids: `dataGrid21/23/24`, `listView6`, AWS settings tab, top bar).
Files copied from the snapshot changed no count (58 before and after): the missing-file errors were real but not what failed.
Checklist, 132 FAIL: 42 NO CLICK PATH / conditional (Group_NewEdit: button shown only if `not(IsActive)` or a question type the
journey did not pick); 24 DATA-STATE (Executed / Overdue checklists reached but the target action button
`actionButton16` needs a reviewed or reported row, none seeded: add a Resolved instance with a mitigation and a reported flag);
16 DATA-STATE or INSTRUMENT (InstanceChecklist_Review accordion never appears, needs an instance with findings); 11 INSTRUMENT
(manager dashboard `container34` is a conditional card); 10 INSTRUMENT (Checklist_Details); 29 other small groups
(Employee_New, DemoUserSwitcher, SelectResponsibleEmployee, ApplicationSettings tabs, Frequency page).
I did not fix the instrument; the DATA-STATE rows are the next seeding iteration.

## Commands (so the run can be repeated)
Setup `bash upgrade-toolkit/bin/setup-container.sh ~/run1 9.24.23.37735 9.24.2.6130`; apps from `mxcli marketplace download 205432
--version 3.0.0` (VI) and `220329 --version 1.0.0` (Checklist), unzip the .mpk into `<run>/<app>/app`; build with `mx9.sh <ver>
mxbuild --target=package -o work/old.mda`; journeys `impact_map.py old old`, `action_inventory.py`, `gen_journeys.py --roles-with-users`;
seed `seed_vi.sh` / `seed_cl.sh`; run `run_variant.sh <run> <vi|cl> <label> <frozen db> <full ver> <port off, multiples of 20>
[snapshot.zip]` (env `JOURNEYS=` for another journey set). Empty baselines were `vi_empty_frozen` / `cl_empty_frozen` (app started
once on an empty Postgres, then frozen).

## PARKED FOR A STRONG MODEL
- Decide, per journey generator, how destructive actions (delete employee, reset demodata, delete department) are ordered or
  isolated by default; today the generator does not know an action destroys the users that later roles need. This changes
  instrument semantics (DEFECT_MAX comparability), so it is not decided here.
- Checklist dashboard "Total number of checks during last 30 days: 2" while 5 instances are Submitted/Resolved/Overdue_done:
  not checked whether the counter excludes rows by SubmittedDateTIme or by compliancy; needs reading the dashboard microflow.
- Which DATA-STATE journeys need which extra rows (reported flag, mitigation, Resolved with findings): needs reading the
  Review/Executed page microflows; the mapping from "button shown only if X" to the seed row is mechanical but not automated.

## BLOCKERS
None that only the user can resolve. Not done: file-bearing rows for the Checklist (images, signature, report) and any route-(c) UI
seeding; the chatbot/AWS pages cannot be exercised without credentials the user would have to supply.
