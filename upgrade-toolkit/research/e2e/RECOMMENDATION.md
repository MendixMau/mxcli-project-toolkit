# E2E after an upgrade: impact-picked journeys or a full suite

Status: research, 2026-10-02. Everything marked "measured" was run on this machine; everything marked "unproven"
was not. Evidence is local (`~/upgrade-lab/e2e-research/`), never in this repo.

## Recommendation

Run a light, impact-picked set on every upgrade, and never skip the always-on part of it:

1. **Always on**, whatever changed: login per role (role home renders, the role's menu is shown, menus it may not
   open are not), a negative MFA journey when an MFA module is present (password alone must NOT get in), and one
   core create-and-save per app.
2. **Impact-picked**: one journey per menu entry the impact map ties to a change, for each role that can open it.
3. **Not browser journeys**: the map also lists the checks that belong elsewhere (start log "active" lines,
   scheduled events, published services, screenshots of changed vendor pages). These are listed, not skipped.

Do not build a full e2e suite for the upgrade gate. On both cases the defect that mattered was not a missing page
in a long walk. It was a negative fact (a gate that silently opened) or a visual one (charts with no bars). A wider
happy-path suite misses both, and costs hours of authoring per app. Escalate to more journeys only on the triggers
below.

## The two cases

| | app A (E1): 10.12.9 to 10.24.16, MFAmodule 1.5 to 5.0 | app B (E5): 9.24.32 to 10.24.9, 10 modules |
|---|---|---|
| what went wrong | `MFAmodule.EnabledMFA` default reset True to False; the project's after-startup tree stopped calling `MFAmodule.ASU_MFA` (still in the model, hollowed out) and calls `ASU_MFA_v2`. MFA was off; every gate check passed | TaskQueueHelpers 3.1.0 dashboard charts render axes but no bars or slices (seen by eye; old dashboard not captured, so regression or no data is undecided) |
| current gate (data, REST, start log ERRORs, smoke walk) | missed: no data changed, no ERROR (the log line is a WARNING "MFA module login NOT active"), every page still opens | missed: the page opens, no error |
| impact map (measured) | constant `EnabledMFA` high, "read in the startup tree by ASU_MFA, ASU_MFA_v2"; startup change lists `MFAmodule.ASU_MFA` as "no longer called at startup but still in the model"; P1 login, MFA and startup candidates | 136 changes, 26 candidates; `caller: Home_Web calls TaskQueueHelpers.MonitoringDashboard (changed)`, `module-pages:TaskQueueHelpers` screenshot check, startup tree change |
| light set | **caught** (measured): `mfa-password-only-refused` FAILs on the reset build, PASSes on the old app and on the fixed build | 10 journeys generated (login x3 roles, 7 menu). Assertions would most likely pass on empty charts (unproven: not run live). The catch is the listed screenshot check old vs new |
| full happy-path suite | would miss: every login succeeds, even more easily with MFA off. Only a negative auth journey catches it, and that is in the always-on set | would miss unless a journey asserts chart content; screenshot compare is still the catch |

So the value is in **which** assertions exist (negative auth, landing guard, menu present and absent), not in
how many pages are walked. The smoke walk already covers breadth (app A: 35 pages over 7 roles).

## Time cost (measured unless marked)

| step | app A | app B |
|---|---|---|
| impact map (both MPRs, no build) | 2.9 s | 2.3 s |
| generate journeys | under 1 s | under 1 s |
| run 6 journeys, 3 roles, one app | 2 min 27 s to 2 min 35 s (100 s of it is the 50 s pause between roles for the trial session cap) | unproven |
| run on old + new | about 5 min, plus app starts that the gate already does | unproven |
| one-time setup per app | a test user per role and an MFA user (bcrypt on the DB copy), `--create` spec for create-and-save | same |
| whole upgrade run, for scale | 3 h 25 min | 2 h 25 min |

A full suite, for scale (counted from the models, authoring time not measured): app A has 206 role-gated pages
(107 in own modules) and 47 menu entries over 8 roles; app B has 91 role-gated pages (66 own). A walk per page per
role is the smoke walk, which already exists. Task journeys (create, edit, workflow) need app-specific widget
names and seeded data, so each is hand work, and their data rungs need `mxcli oql --direct`, which the gate's
runtime does not offer (see runner findings). That is the real cost of "full", not the run time.

## When to escalate

Add hand-written journeys, or widen to every menu entry per role, when any of these holds:

- An authentication or SSO module changes major version and the login page is the default `login.html` (no model
  login widgets, so the MFA journey cannot be generated; the generator says so in plan.json). Write it by hand.
- Project security changes (security level, role added or removed, module-role mapping of a user role changed).
- The map lists a high change in an own module's page or microflow that no menu reaches (plan.json `todo`, kind
  `page` or `client_microflow`). Write the step from the page that opens it.
- A Marketplace module that owns user-facing pages jumps a major version (`module-pages:<Module>`): screenshot old
  vs new for those pages, as a gate step, not as a journey.
- A data-bearing element changed GUID or a RED local edit was updated (idcheck). Add a create-and-save on that
  entity on top of the data diff.
- The customer already has a suite. Run it; it costs nothing to write.

Escalate the other way too: a role with no test user is INVALID, never PASS. Get the user before calling it done.

## Runner findings (measured on app A, proposed upstream; the shared toolkit was only read)

a. **Vacuous login PASS.** `helpers.login` treats `.mx-page` as "in the app". When the anonymous home is a Mendix
   page (app A: an MFA login page), the runner reported login PASS while still on the login page, and the next
   `page.goto` aborted the real login. Fix used: per role `READY_SELECTORS` set to a landing widget that the login
   page and guest home do not render (the map computes it).
b. **`fill` misses login widgets.** It looks for `.mx-name-X input`; Mendix login id and password widgets render the
   `<input>` itself with the class. The driver patches its engine copy to add `input.mx-name-X`.
c. **Seeds and data rungs need live-preview dev flags.** `mxcli oql --direct` answers "Action not found" on a runtime
   started the gate's way (runapp, m2ee). Seeds, data, assoc and outcome rungs are INVALID there. Either start the
   gate runtime with the dev flags, or keep upgrade journeys UI-only and leave data to diff.py (current choice).
d. **Trial session cap.** A trial runtime allows 6 sessions and anonymous sessions count; the runner then reports
   "login form did not render". Fix used: SessionTimeout 30 s, ClusterManagerActionInterval 15 s, 50 s pause
   between roles.
e. **Demo users are re-synced at start in DTAP mode D** and their password reset. Set test passwords AFTER the app
   started.
f. **Stale example.** `project-tests/e2e/example.journey.json` uses an older shape (page, expectPage); the runner
   parses id, persona, steps[actions, ui, data]. `examples/journeys/minimal.journey.json` does not exist.

## Proof

| run (app A) | result | evidence (local) |
|---|---|---|
| mapper on app A, reset build | surfaces `EnabledMFA` True to False (high, in startup tree) and `ASU_MFA` no longer called at startup | `maps/e1-cdffd75.md` |
| mapper on app B | 136 changes, 26 candidates, TaskQueueHelpers dashboard caller and screenshot check | `maps/e5.md` |
| old app 10.12.9 (MFA on) | 6 of 6 PASS, exit 0 | `run/e1-old-10.12.9/` |
| upgraded, reset build cdffd75 (MFA off) | 5 PASS, `mfa-password-only-refused` FAIL (the login page never came back; the screenshot shows the MFA user in the app with the role menu), exit 1 | `run/e1-cdffd75/shots-User/` |
| fixed build 693f127 (MFA on) | 6 of 6 PASS, exit 0; page shows "username or password incorrect" | `run/e1-693f127/` |
| positive control on 693f127 | ui-landing mutant caught on 6 of 6 journeys, ui-text mutant caught on 3 of 3 login journeys; 0 FAIL; trace, data and outcome rungs INVALID (nothing declared, OQL unavailable) | `run/e1-693f127-control/` |
| always-on set from the old project only (map old vs old) | identical journeys (apart from `_why`) to the set from the upgrade map | regenerated, compared, deleted |

Runtime log ground truth: old and 693f127 log "MFA module login active"; cdffd75 logs "MFA module login NOT active,
to enable change your constant MFAmodule.EnabledMFA to true" as a WARNING, which is why the ERROR-only log check
passed.

## Unproven

- create-and-save: no `--create` spec was written for either app, and its data rung would be INVALID on the gate
  runtime (finding c). Generated as TODO only.
- app B journeys were generated but never run against a live app B; the claim that they would miss the empty charts
  is reasoning, not a run.
- Menu journeys and the MFA journey carry no `textPresent`, so the ui-text control rung is INVALID for them; the
  MFA journey's own assertion is proven by the real FAIL on cdffd75, not by a mutant.
- trace, data and outcome rungs: not exercised at all.
- `--catalog-check` of the mapper against `mxcli catalog`: not run in this round.
- Only one MFA style (MFAmodule with a model login page). Default `login.html` apps and SSO-only apps: not tried.
