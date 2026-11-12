# Playbook: what the publishers did in their own upgrades that the toolkit did not

Source: the COMPARE.md of batch 1 (branches `origin/runs/<slug>`), where a worker compared its toolkit result with
the publisher's own newer versions of the same Marketplace template. References existed for T1 (Purchase Request,
publisher 2.0.0 on 10.0 and 3.3.0 on 10.24), T2 (Opcenter EF, 3.0.0 to 8.0.0 on 10.6 to 11.12), T3 (PFEP, 3.2.1 and
3.3.1, a rebuild), T4 (Kanban with Opcenter 2.0.0, 10.24), T5 (Visual Inspection 4.0.0, 10.12), T6 (Checklist to go
2.0.0, 10.6). T7 and T8 had no publisher upgrade. FEEDBACK.md row R1-2.

Feature work (new modules, new pages, redesigns, new Siemens widgets, demo-data loaders) is left out: it is not
upgrade work. What is left, by theme, with what the toolkit should do.

## 0. Never use the publisher's newer package as the customer's upgrade path

Before the lessons, the warning the comparisons gave four times: a template's next version is a new product, not a
migration. Taking it over a customer database loses data.
- T2: Administration Account / AccountExtension / AccountProfilePicture re-created with new GUIDs in 6.0.0 to 8.0.0
  (9 GUID_CHANGED): Email, FullName and all AccountExtension rows lost.
- T6: every DeepLink entity re-created with new GUIDs in 2.0.0 (40 GUID_CHANGED): all configured deep links lost.
- T1: 6 request-role associations and Account.AvatarURL removed (2.0.0 and 3.3.0).
- T4: EmployeeManagement.Employee moved to another module (2.0.0). T3: all 7 own modules replaced (3.x).
The toolkit kept all of it (data diff 0 FAIL on every run). Use the publisher's version only as a source of fixes to
copy, by element, through the gate.

## 1. Administration 2.x/3.x to 4.x: the publisher did it, the toolkit kept the module (T1, T4, T5, T6; T2 kept too)

Every run with an old Administration kept it (RED local edit or xmod stop rule), and every publisher moved to 4.x.
T6's comparison shows it can be done without loss: the publisher's 4.1.0 kept the GUID of the app's own
`EmployeeManagement.Employee_Account` association. What the publishers did around the update (T5, T6, T7):
1. Kept the own associations into `Administration.Account` (Studio Pro keeps them; headless: the edited-modules
   playbook, drop and create plus `restore_guid.py`, as T7 did for 7 associations).
2. Copied `Administration.UserRole_Select` into an own module where own pages used it (T5 ref: into
   EmployeeManagement), because 4.x dropped it. T7 instead rebuilt Account_Edit/New with the combo boxes of
   Administration 4.5's own Account_Edit (`ALTER PAGE ... REPLACE`); both are fine.
3. Re-pointed the after-startup microflow from `Administration.MendixSSO_AfterStartup` to
   `MendixSSO.MendixSSO_AfterStartup` (T5 ref).
4. Replaced reference selectors on account pages by combo boxes (T1, T4, T6 refs; T7 did it).
Toolkit action: this is the edited-modules route with these four replay items; plan it in triage instead of
reporting "kept". Without it the React-client backlog stays (T4: Administration 3.0.0 holds all 7 classic reference
selectors and 5 of 8 classic data grids).

## 2. Dead and stale things the publisher removed

| what | runs | toolkit action |
|---|---|---|
| Marketplace modules nobody uses (DataGrid example module, AppSwitcher, DemoUserSwitcher, ExcelImporter, ODataQueryBuilder) | T1, T3, T4 | triage lists modules with no reference from own modules (impact map); report them as "removal candidate, owner decides". Do not delete in an upgrade run |
| a renamed module (DataGrid -> DataWidgets, same content id) | T1 (T1-14) | triage prints RENAMED; route: install the new module, move references, delete the old, idcheck first |
| userlib jars of modules not in the project (`*.OIDC.RequiredLib` with no OIDC module, PushNotifications, UnitTesting markers) | T2 (T2-14), T7, T8 | remove at repair row 3 by hand until jardedupe does it; publisher 8.0.0 (T2) has an empty userlib, T5's ref cut userlib from 100 to 9 jars via managed dependencies |
| deprecations, among them Document Templates / Generate Document (removed in Mendix 11) and "System context tasks" | T3 (T3-23): ours 67 deprecations at 10.24, publisher 2 | run `mx check -d` at the 10.24 gate and list every deprecation with the version that removes it; anything removed in the next rung's major is a blocker for that rung |

## 3. Mapping new module roles

New Marketplace versions add module roles (Atlas_Core 3.21: Administrator, User). mx check only warns (CW0029 /
CW0114), so repair row 8 (mapped on CE2729) never fires (T4, T5, T6: 2 to 3 more unmapped roles than the
publisher). Toolkit action: after each module step, read the "module roles +[...]" line of the step idcheck and map
each new role the way the publisher's newer version maps it, or to the user roles that held the module's old roles.

## 4. Workflow assignees (Mendix 10, WorkflowCommons 3.x): the publisher rebuilt the task pages

Mendix 10 turned the user task assignee into a reference set (`WorkflowUserTask_Assignees`). The toolkit's fix kept
the build green with a minimal `!= empty` visibility (T1 R13); the publisher rebuilt its task pages on WorkflowCommons'
own pattern (GetCurrentAssignee data view, Assign to me / Unassign). Weaker visibility is a behaviour change, not a
cosmetic one. Toolkit action: for own task pages, copy the visibility from WorkflowCommons 3.x's own task page
snippets instead of `!= empty`, and add a journey per task role. On 11: run WorkflowCommons' 3.x assignee migration
before WorkflowCommons 4 (T7 rung 2).

## 5. Theme edits in vendor files

T5's publisher had edited `atlas_core/_variables.scss` (brand colours); its newer version keeps that edit and adds
`$brand-primary` to its own theme module. The toolkit's Atlas_Core update dropped the edit (localedits does not
compare theme files), shotdiff caught it, and the repair moved the 11 variables to `theme/web/custom-variables.scss`.
Toolkit action: triage diffs `themesource/atlas_core/` against the installed package and lists edited theme files
as UI local edits; the fix is the T5 one (own file), not re-editing the vendor file.

## 6. Configuration that should not live in constants

T5: the publisher moved the Encryption key from the constant into the Default configuration; the toolkit restored
the constant default after constcheck caught the reset. Constants reset on a module update (constcheck exists for
this). Toolkit action: report keys and credentials held in constants as a hygiene item; T6 had the same pattern with
AWS keys left in removed AmazonTranslateConnector constants.

## 7. Where the toolkit did better than the publisher (keep doing it)

- Data continuity (section 0) on every run.
- Newer, compatible module versions: T2's publisher 11.12 package still has NanoflowCommons 6.2.1 (T2 reported CE4271 on
  11.15 from `mx check -w -d` of the converted reference; N1 did NOT reproduce it: 8.0.0 converted to 11.15.0 gave 0
  errors and built, N1-12). Cite the version gap (6.2.1 against 7.4.0) and the module's min Mendix, not CE4271, until a
  rerun on the same converted tree shows it.
- Clean classpath: T4 0 jar clashes against the publisher's 112; T6 removed 33 jars of absent modules.
- Theme fixes the publisher still carries (T2: wrong-case SCSS import breaks on Linux).

## 8. Same as the publisher (no lesson, recorded to stop re-checking)

- Atlas 4: no publisher took it on 11 (T2 D on 11.12 still Atlas_Core 3.19). Exception: WorkflowCommons 4.3+ needs
  Atlas Core 4 (T7-25): see playbooks/10-to-11.md.
- Dojo data grids and other classic widgets on 11: T2's publisher kept them too (CW9516 33 against our 37).
- Legacy Charts: T5's publisher still ships Charts 2.0.1 on 10.12; it breaks on 11.6+, see [widgets](widgets.md).
- Java: Viewer3D API fixes for 10 (T3) and own Java action sets (T2) identical to the publisher's.
