# Purchase Request 3.3.0, 10.24.0.73019 -> 11.12.5: punch list after run 5 (owner decisions D1-D10 applied)

Done-states as in research/design-2026-10-15/trust.md section 1: the toolkit closes FIXED only; everything below is PREPARED for the owner as EVIDENCED, DECIDED or HANDED-OFF. The owner accepted every recommendation of the run-4 list in chat on 2026-10-19 ("Ok agree"); each decision is recorded `CONFIRMED (owner, chat 2026-10-19: accepted the recommendation)` as S-1..S-10 and P-1..P-4 (`DECISIONS.owner-s1-s10-p1-p4.md`) and R37-R40 (`DECISIONS.run5.md`). Evidence files sit beside this one (`*.run5.*`, `release-impact.run5.md`, `release-notes-evidence.txt`, `allow-files.run5.txt`, `approved.run5.txt`, `roles-waived.txt`, `Atlas_Web_Content.ported.patch`).

Progress: 5 of 10 checks closed (50%). 1 with REGRESSIONS to fix, 1 need a decision, 2 not measured yet, owner sign-off pending.
Changes: 29 (toolkit 5, agent 0, person 0, unlabelled 24)

- Gate verdict: **FAIL** (exit 1), 5 of 9 required rungs PASS or PASS* (build, idcheck, const, data, logdiff), journeys FAIL, screens FAIL (REVIEW), smoke and release NOT RUN by the pipeline's gate step. Run 4 was 2 of 10 (20%). The two "FAIL" rungs are open for evidence and a screen look, not for a regression: **0 regressions**.
- Baseline defects: **31 of 138** generated actions fail on the old 10.24 app (22.5%); the limit is 30% = **41** at 138 (it was 43 at 144). Run 4: 40 of 144. DEFECT_MAX 0.30 untouched, no `--bar processes`, no hand-edited verdict, no baseline-evidence file written: the defects are still "without evidence" (INVALID). The 32nd failing journey is `login-Administrator`, a false baseline defect of the instrument (PRF-3, H11).
- Processes: **15 of 15** compiled processes pass on the old and the new app, P09 included (was 14 of 14 plus a draft). P09's three one-click defects (Comments_TaskInbox 16/17, WorkflowCommentHelper_Edit 5) are now walked by the process and listed as covered.
- Regressions: **0**.
- Toolkit: PRF-1 (D5) and PRF-2 (D6) FIXED with controls and one mutation each (FEEDBACK.md, pr-final 360454c7); PRF-3 found and left as backlog.
- Release-impact sheet: **261** rows, not 30 (the run-4 text counted the 30 the check prints); all 261 written (`not relevant` or `handled`, 0 open). Rows that DO touch the app on a careful read: the four drop-down filter text rows (174, 177, 179, 181), the Feedback PopulateAttributes row (186), the Data Widgets 3.x conversion rows (CE0463, 48 errors cleared by the update-widgets repair) and the AWC 4.x rows; each is `handled` with evidence, none left open.
- Why the Progress line reads 50% and not more: the journeys rung is FAIL on 32 evidence-less baseline defects (H2-H5, H7, H11) and 499 REVIEW / 27 INVALID screen pairs (L2), the screens rung holds 17 smoke REVIEW pairs, smoke and release are not run by the pipeline's gate step, and the proposal sign-off is the owner's chat confirmation.

## Needs owner (found while applying the decisions)

| id | item | state | evidence | what I did | owner action |
|---|---|---|---|---|---|
| N1 | P-3 (Atlas_Core `_navigation-bar.scss` replay) conflicts with A1 | NEEDS OWNER | the saved edit is `min-height: 500%` on `.region-topbar .mx-navbar` (work/replay/dropped/Atlas_Core.patch); owner decision A1 (R22) rebuilt the top bar from the Atlas 4 top bar with no custom CSS and the edit was removed on purpose; replaying it would make the rebuilt top bar 500% high | NOT replayed; P-3 recorded as answered "replay" with this caveat (DECISIONS P-3, R40) | say "keep removed" (the A1 answer stands) or "replay" (then the top bar needs a visual re-check) |
| N2 | P-4 (Atlas_Web_Content `_heroheader.scss` replay) brings back the blurred hero band | NEEDS OWNER (done as told, one commit to revert) | the saved patch no longer applied on 4.4.0 (`$header-bgimage-filter` is now `var(--header-bgimage-filter)`); ported by hand to the same change (`top: -200%` and the nested `> img`), `34acc43`, `Atlas_Web_Content.ported.patch`; R23(f) had replaced that look by the full photo (Image fit Cover) | replayed as D1 says; the three hero pages (Admin_Homepage, MyRequests, TaskInbox) are expected among the screen REVIEW pairs | look at the three heroes with L2; keep, or `git revert 34acc43` |
| N3 | AWC 4.4.0 makes `Atlas_Web_Content.LoginContext` non-persistent | DECIDED within D1, flagged | idcheck REVIEW (persistence lost); 5 old rows, all transient login-form values (Username, RememberMe, ValidationMessage; Password never stored); publisher change since 3.7.0 (steps/upgrade.md) | accepted in work/approved.txt and 2 lines in work/allow.txt (S-1); the step could not commit without it | veto: `git revert 6a15d06` and keep AWC 3.6.0, or confirm |
| N4 | 3 new Atlas_Web_Content module roles (Administrator, Anonymous, User) have no user role | DECIDED within D1 (least privilege), flagged | rolecheck UNMAPPED; no page of the app uses an AWC page at runtime | waived in work/roles-waived.txt, nothing granted; the D4 mapping stays Atlas_Core only | confirm, or map them (a security change) |
| N5 | 3 more Workflow Commons INFO lines in the start log | DECIDED in the class of D8 | logdiff REVIEW 3: the WorkflowCommons 4.x after-startup UserTaskView migration check ("migration required: false", "no objects require migration", R25), visible now because the `after` step ran again with the R22 after-startup action | accepted in work/log-allow.txt with the reason (S-8 class) | confirm |

## Decide now (the owner answers in chat): all ten answered

| id | item | state now | evidence | what happened | owner action |
|---|---|---|---|---|---|
| D1 | Atlas Web Content 3.6.0 -> 4.4.0 | DECIDED, applied, EVIDENCED | step commit `6a15d06`, replay `34acc43`, mx check 0 errors after the update-widgets repair (work/check-36.log, `check-36-final-0-errors.txt`), mxbuild BUILD SUCCEEDED, quick start and walks ran; pair Atlas_Core 4.5.0 + AWC 4.4.0; app HEAD `6517669` | updated with stepupdate (one-module plan, `--accept-unsaved`); see N2, N3, N4 for what came with it; work/kept.txt is empty now | see N2-N4 |
| D2 | "Complete PO(s)" is not destructive | DECIDED | unchanged: a normal step of the processes (P02 leg 3, P06c) | no change needed | none |
| D3 | OQL version 2 on | DECIDED | unchanged, mx check 0 errors | none | none |
| D4 | Atlas_Core role mapping | DECIDED | unchanged | none | none |
| D5 | a confirmed process may fill a conditionally visible field after an earlier step opened the task | DECIDED and FIXED | PRF-1: `process_journeys.py field_acts`, controls process-hidden-field-after-open-task-pass / -no-open-task-catch, mutations both ways fail; P09 compiles (2 legs) and PASSES on the old and the new app (journeys-after.run5.out: `proc-p09-01` PASS, `proc-p09-02` covered) | P09 set to `status: confirmed (agent-written, needs key-user confirmation)` like the other 13; closes H6 | key user reads P09 (C1) |
| D6 | "Assign to me" classified `assign-to-me-dead` | DECIDED and FIXED | PRF-2: the coverage line now reads `138 generated (141 todo: ... assign-to-me-dead 6 ...)`; 144 -> 138, defects 40 -> 31 together with P09; the six are in plan.json `skipped` (never dropped). The Administrator's "Assign to user" PASSES on the old app, so the rule applies only behind a participant's task list (found while checking the field: the first version would have called it dead) | closes H1 as a todo, not a defect | none |
| D7 | 5 seeded comments lost | DECIDED | accepted | none | none |
| D8 | 14 expected differences | DECIDED, applied | work/allow.txt (12 data lines), const-allow.txt (1), log-allow.txt (1), each naming the owner confirmation; data rung PASS* (20 accepted, 0 open), const PASS*, logdiff PASS* (4 accepted) | the extra lines for N3 and N5 are listed there | none |
| D9 | release-impact sheet | DECIDED and EVIDENCED | 261 of 261 rows filled, `release_impact.py --check` exit 0, 0 unsound closures (release-impact.run5.md; evidence for the filter rows in release-notes-evidence.txt) | rows touching the app are `handled` with evidence, the others `not relevant: <reason> (owner confirmed 2026-10-19)`; the database-engine rows say the production engine is a go-live item | glance at the sheet |
| D10 | proposal P-1..P-4 and sign-off | DECIDED, signed | `Signed-off: owner (chat confirmation) 2026-10-19` in work/PROPOSAL.md; the propose step exits 0 ("signed by owner") | P-1 update, P-2 keep, P-3 answered replay but not done (N1), P-4 replayed (N2) | see N1 |

## Look at (screens)

| id | item | proposed state | evidence | recommendation | owner action |
|---|---|---|---|---|---|
| L1 | Top bar visual sign-off | HANDED-OFF | R22/R23: the customised top bar was rebuilt from the Atlas 4 top bar (no custom CSS); assumptions: menu centred, menu hidden on tablet and phone, title lost its click-to-home action (logo keeps it), help icon wrapped; screenshots `work/r22/shots/admin-topbar-1440-final`, `admin-home-1440-final`, `admin-home-600-final` (local, not copied) | look at the three images; if the title must go home again, that is one Studio Pro step (mxcli cannot author ShowHomePage) | accept, or ask for the title action |
| L2 | Screens rung: 499 REVIEW, 27 INVALID pairs (Atlas 4 layout everywhere) | HANDED-OFF | `screens: 1 PASS, 0 PASS*, 499 REVIEW, 27 INVALID` in `journeys-after.run5.out` (smoke screens: 17 REVIEW); the three hero pages are N2; 119 REVIEW lines were already there in run 3 | open ten pairs (top bar, task inbox, task page, admin instance view, my requests), then accept the rest by cluster in `shot-accept.txt` with the sha pin | a look of about 15 minutes; the agent writes accept lines only for pairs you name |
| L3 | Comment author shows DisplayName | HANDED-OFF | R24: author text `{1} = DisplayName` via DS_GetOwnerOfComment; seen live as "Alice Approver" on a scratch DB copy | look at one task page with a comment | accept |

## Confirm (key user)

| id | item | proposed state | evidence | recommendation | owner action |
|---|---|---|---|---|---|
| C1 | 14 agent-written or agent-changed processes | HANDED-OFF | `processes.md`: P02 (leg 4 changed), P04, P04b, P05 (marker added in this run), P06, P06b, P06c, P06d (Decline at the first state, new), P07, P08, P10, P12, P13, and now P09 (D5); each is `status: confirmed (agent-written, needs key-user confirmation)`; all 15 compiled processes pass on both apps | a key user reads the steps (one page each) and strikes what a real user would not do | the key user confirms or edits; only then does `confirmed` mean confirmed |
| C2 | P11 second approver | HANDED-OFF | the model routes SumTotalPrice >= 2500 to a second approver but FindTargetUsers_SecondApprover excludes the first one and the fixture has one Approver (demo_approver_2 exists in the demo list only); 2 defects wait (Task_Approver 10/11 are the second-approver buttons) | add a second Approver to `users.json` and write P11 with a leg per approver | key user says whether the route matters |
| C3 | The .pdf seed is a text file named .pdf | EVIDENCED | `journey-verbs` upload seed; fine for the UI, not a valid PDF | none unless a preview widget starts to check the type | none |

## Hand off (a defect that cannot be measured here)

All 31 baseline defects are listed by cluster, plus one instrument artifact (H11). Proposed state is EVIDENCED (a person confirms the evidence line) unless the cluster says otherwise; none is a regression, the old app fails them too.

| id | item | proposed state | evidence | recommendation | owner action |
|---|---|---|---|---|---|
| H1 | Assign to me, 6 | CLOSED as a todo (D6, PRF-2) | `assign-to-me-dead 6` in the coverage line | none | none |
| H2 | Admin task details and assign, 7: Snip_UserTaskView_Details 5/9/11, UserTask_Assign 2/7/8/9 | EVIDENCED | need a task with no targets or a non-single completion; every task in the fixture has one target (DB: 27 tasks, target count 1 except one with 2) | no route in this app; a second target user (C2) would make 4 of them reachable | confirm |
| H3 | Audit trail and activity, 7: Snip_AuditTrailViewer_Toolbar 1-5, Snip_WorkflowActivityRecord_Details 4, Snip_Workflow_ActivityTimelineOnly_Full 5 | EVIDENCED | reachable only through "open parent workflow"; the app has no sub-workflows | none | confirm |
| H4 | Workflow operations, 4: Snip_Workflow_MoreActions 13/18, Workflow_Retry_Options 1/2 | EVIDENCED | Continue and Retry need an Incompatible or Failed workflow; no UI route makes one | none | confirm |
| H5 | Admin comment and attachment row, 8: Snip_WorkflowView_CommentsAndAttachments_Admin 3/4/6/8 + listView6, WorkflowAttachment_View 16/17, WorkflowComment_Edit_Admin 5 | HANDED-OFF | comments and attachments exist (P04, P10 seed them); the row buttons need a per-row verb scoped to the row that owns the button (a delete click in the comment row opened the attachment view in a debug pass) | an engine item for the next run | confirm |
| H6 | Own comment, 3 | CLOSED (D5, PRF-1) | walked by process P09, passes on both apps | none | key user confirms P09 (C1) |
| H7 | Task pages, 5: Attachments container12 / actionButton6, Task_Receiver 5 (edit of an already completed line), Task_Approver 10/11 (second approver, C2) | EVIDENCED | the task-page attachment snippet needs an attachment on the open task; Receiver 5 needs a line not yet completed | none | confirm |
| H8 | `MyRequests.container6` "regression" | FIXED (re-measured: 0 regressions) | live DOM on both apps: `.mx-name-container6` is the top bar's container6 (visible, text "Purchase Request") on the old app, so the old PASS was false; the page's attachment tile never rendered on either (newest request k307 has no attachment on both, identical selected row and data; the attachments belong to the P10 and P06c requests) | done: PRC-6 (name collision with a layout widget is a todo) and PRC-7 (stale generated journeys are removed) | none |
| H9 | Gate step needs a signed proposal and a filled release sheet | CLOSED | both done (D9, D10); the gate step now stops only on the mutant control (`todo_mutant_control`, acknowledged in work/notrun-ack.txt: the full controls suite was not run) | none | none |
| H10 | NanoflowCommons accepted UNSAVED (accept-unsaved.txt) and the MendixSSO validation-rule replay (R11/R12) | EVIDENCED | both were assumptions in runs 1-2; the journeys and 14 processes ran with them, no failure traced to them | re-check once in Studio Pro | confirm |
| H11 | `login-Administrator` fails on the OLD app | HANDED-OFF (toolkit backlog PRF-3) | its guard is `.mx-name-imageHero`, the hero image renamed from `image2` by the repair; impact.json was regenerated by the `after` step and now carries the new-model-only pick, run 4 had `layoutGrid2` from an older impact.json; passes on the new app; not one of the 31 action units | not fixed in this round (a rerun of the journeys is about 3 hours); the fix is one line in gen_journeys (take `both_landing` for the role home) | say whether to fix it in the next round |

## Counts

needs owner 5 (N1-N5), decided 10 of 10 (D1-D10, all applied), look at 3 (L1-L3), confirm 3 (C1-C3), hand off 11 (H1-H11; H1, H6, H8, H9 closed). Toolkit-closable and still open: 1 (PRF-3, backlog).
