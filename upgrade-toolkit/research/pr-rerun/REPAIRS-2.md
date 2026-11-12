# Purchase Request run1: repairs 2 (R22-R28)

Run folder `real/run1`, app repo `real/run1/app` (local git, no remote), model 11.12.5. Full text in `DECISIONS.md` R22-R28 (copy next to this file is not refreshed; the run folder is the source). Specs: `research/design-2026-10-14/atlas-topbar.md`, `repair-rows.md`.

## Done
- A1 Top bar rebuilt from the Atlas 4 top bar (owner decision: existing design system and design properties, no custom CSS, no compat stylesheet). `alter layout PurchaseApprovals.Atlas_TopBar_Customized`: `topbar-wrapper` grid, left cell = `navbar-brand` container (flex row, item gap small, align Y centre) with logo + title, centre cell = menu bar, right cell = help icon, profile snippet, Sign Out. Vendor theme files `_navigation-bar.scss` (Atlas_Core 4.5.0) and `_heroheader.scss` (Atlas_Web_Content 3.6.0, what the app has installed) restored to the package versions; the two replay patches moved aside. Hero image widgets on Admin_Homepage, MyRequests, TaskInbox got widget width/height 100% (widget property). Hero widget on Admin_Homepage renamed `imageHero`, so `image2` is the layout logo only.
- A2 Comment author: data view over `DS_GetOwnerOfComment` holding the author text `{1} = DisplayName`; describe diff before/after shows only those lines.
- A3 `PurchaseApprovals.ASU_Main` (MendixSSO after-startup, then `WorkflowCommons.ASU_UserTaskView_Migrate`) set as AfterStartupMicroflow; runtime log shows the migration ran. Pre-update comment check on the old database: 5 comments, 5 with empty `WorkflowComment_Workflow`, all view-linked, 0 views with a workflow: 5 seeded comments cannot be migrated (query in `work/r22/comment-precheck.sql`).

## Results
- mx check: 0 errors (check-27, -28, -33). mxbuild + quick start PASS (3 builds). Administrator smokewalk: 7 PASS, 0 FAIL, 0 regressions. Journeys not rerun.
- Screenshots looked at (run1/work/r22/shots, not copied): admin-home-1440-final (top bar: logo, title, centred Home, help/profile/Sign Out right; hero photo full width with title), admin-home-600-final (narrow: hamburger, logo+title centred, profile + Sign Out wrapped to a second row: not tidy), admin-topbar-1440-final, flow-6b-open-tasks (Approver home: hero full width, task card), task-approver-comments-final (comments panel: form, three comments with author "Alice Approver" in bold brand colour, date, delete/edit icons).
- Seeded smoke users have an EMPTY DisplayName, so the author line is blank on that data; the test showed DisplayName after setting it in the scratch DB.

## Owner sign-offs needed (visual / choice)
1. Menu centred (Atlas 4 default) instead of next to the title; hidden on tablet and phone (app hid on phone only).
2. Title no longer clickable (ShowHomePage cannot be authored by mxcli; the logo keeps it). Help icon wrapped in a container to keep its link.
3. Heroes: full photo, Image fit Cover, instead of the old dark blurred band (which came from the removed `top:-200%` edit).
4. Narrow layout (600 px): sidebar toggle (cannot be moved by mxcli) is a direct child of the grid; profile + Sign Out wrap under it. Tablet/phone not otherwise looked at.
5. Atlas_Web_Content is still 3.6.0 in the app (plan said 4.4.0, no step commit exists); Atlas_Core is 4.5.0. Decide whether to update AWC.
6. 5 seeded comments are lost by the WorkflowCommons 4.x step (no workflow link to migrate them onto).

## Assumptions
- ASU_Main wraps the vendor after-startup in the app's own module (vendor MendixSSO microflow untouched). One layout widget name clash found: layout Sign Out is `actionButton1` like page buttons (scope selectors to `.region-content`).
