# Upgrade proposal: 10.24.28.129343 -> 11.12.7

<!-- proposal inputs-hash: 08819802a3c67fb832b40738b44f70ed074b59f58c7e021d9300c6bb4e9dd4d4 -->

Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. Every line starting with `- ` is an item; sub-lines are evidence.

## 1. Summary

- From 10.24.28.129343 to 11.12.7 (rung 1 10.24.28.129343 -> 11.12.7). App size: 58 modules, 249 pages, 1900 microflows, 725 actions.
- 4 items the toolkit expects to handle, 7 need your decision, 5 need a person anyway.

## 2. Done by the toolkit

Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no successor are never here; they are in section 3.

- module update Atlas_Web_Content 3.9.0 -> 4.4.0 (after the convert)
- module update Logging 2.3.0 -> 2.4.0 (after the convert)
- module update NanoflowCommons 5.2.1 -> 7.4.0 (after the convert)
- module update NativeMobileResources 10.1.17 -> 12.6.0 (after the convert)

## 3. Needs your decision before we start

Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. Signing section 6 without an answer accepts the recommendation of that item.

- [P-1] module: Administration
  - evidence: RED local edit (data-bearing): ADDED association Administration.Account_NativeTechnician; ADDED association Administration.Account_Technician (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: data loss if a RED edit is replaced
  - answer: keep old version (kept list); the stop rule keeps it unattended (ASSUMED (unattended))
- [P-2] module: BizzomateScheduler
  - evidence: kept at its version by the update step: 3.12.4 target package made before 10.21 (pre-convert plan) (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: behaviour of local edits is lost on update
  - answer: keep old version (kept list); the stop rule keeps it unattended (ASSUMED (unattended))
- [P-3] module: DataWidgets
  - evidence: kept at its version by the update step: UNSAVED: no-baseline route saved 0 of its UI edits (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: behaviour of local edits is lost on update
  - answer: keep old version (kept list); the stop rule keeps it unattended (ASSUMED (unattended))
- [P-8] module: JWT
  - evidence: kept at its version by the update step: elements could not be read, module not shown unedited (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: behaviour of local edits is lost on update
  - answer: keep old version (kept list); the stop rule keeps it unattended (ASSUMED (unattended))
- [P-4] module: MendixSSO
  - evidence: kept at its version by the update step: idcheck REVIEW (persistence loss or removal: accept it in approved.txt with a reason, or keep), see .stepupdate/step9-MendixSSO.idcheck (localedits.json / kept.txt)
  - options: keep the module (S, until it leaves the Marketplace) | OIDC SSO with the IdP (M-L) | SAML / LDAP / local credentials (M) | OIDC Provider for custom SSO
  - recommendation: OIDC with the IdP once the IdP decision is made; keep until then. [RA-16, idea, playbooks/rearchitecture.md]; effort L; risk: behaviour of local edits is lost on update
  - answer: OIDC with the IdP once the IdP decision is made; keep until then. [RA-16, idea, playbooks/rearchitecture.md] (ASSUMED (unattended))
- [P-5] theme: BizzomateScheduler themesource edits
  - evidence: localedits.json FILES-EDITED rows of BizzomateScheduler in themesource/
  - options: replay as is (S, repeats the break) | restore the package file and move wanted styling to the app's `theme/web/main.scss` (S) | express it with design properties of the widget (M, best) | hand off
  - recommendation: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md]; effort S; risk: look only
  - answer: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md] (ASSUMED (unattended))
- [P-6] theme: DataWidgets themesource edits
  - evidence: localedits.json FILES-EDITED rows of DataWidgets in themesource/
  - options: replay as is (S, repeats the break) | restore the package file and move wanted styling to the app's `theme/web/main.scss` (S) | express it with design properties of the widget (M, best) | hand off
  - recommendation: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md]; effort S; risk: look only
  - answer: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md] (ASSUMED (unattended))

## 4. Needs a person anyway

- release-impact rows a person must judge
  - 274 of 274 rows have no 'handled' entry yet (release-impact.md)
- key-user confirmation of the user processes (status: confirmed is set only by a person)
  - templates/process-interview.md; the number of processes is unknown at this point
- visual sign-off of the changed screens (shotdiff REVIEW pairs)
  - the number of changed screens is known only after the gate
- real test systems for external APIs: unclassified
  - 7 endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)
- go-live actions (deployment, data migration window, rollback decision)
  - outside the toolkit

## 5. Human effort

- decision touchpoints: module 5, theme 2
- person-anyway touchpoints: 5, release rows to judge 274
- range for the decisions alone: 17 to 76 hours (toolkit assumption per item: S 0.5-2 h, M 2-8 h, L 8-40 h; not measured). Key-user time, screen review and go-live are not in it.
- unknown at this point:
  - not measured: stranded.md: steps/triage.md item 3 lists stranded modules and add-on modules built before 10.21 there
  - not measured: replacements.md: steps/triage.md item 10: replacement_check.py --out
  - not measured: dojo-react.md: steps/triage.md item 10: dojo_report.py --out
  - not measured: widgetcover.py: it judges which widget packages the walks render; the walks of the new app exist only at the gate (widgets rung)
  - not measured: theme_clash.py: it compares the app's styling with the NEW Atlas, which exists only after the update
  - not measured: rolecheck.py: it compares the OLD and the NEW model; module roles are checked after each module update
  - not measured: usercode.py: it compares a module's Java user code per module, after the update step (.stepupdate/step<n>-<module>.usercode); Java edits that exist now are the localedits.json FILES-EDITED rows

## Testing plan

What the gate tests, what it cannot test in a sandbox, and how each gap is closed. Numbers come from the inputs named in section 5.

### What is tested and how

- build: mx check and mxbuild of the converted app, errors listed per code (58 modules, 249 pages, 1900 microflows)
- data: the old and the new app each start on a copy of the same database; every table is compared row by row (a row that differs is FAIL until accepted with a written reason)
- journeys: one browser journey per action (725 actions in the inventory), per role, run on the old app and the new app; a difference is a regression
  - journeys in scope: 471 reachable, 254 out of scope (unreachable 202, marketplace 25, no-role 27)
  - testability work: 0 reachable actions have no click path yet (record a click path, or test at deploy); each of these stays INVALID in the gate until it has a path
- external calls on a stand-in: 7 endpoints and constants found, 2 can be answered by the stand-in (apimock.py), 5 are UNKNOWN; the apis rung checks that the stand-in was asked what the model says it should be asked

### What cannot be tested in the sandbox

- 5 of 7 external endpoints are UNKNOWN: no stand-in route exists, so a journey that needs one is INVALID, not PASS (examples: DeepLink.LoginLocation, DeepLink.SSOHandlerLocation, MendixSSO.OpenIdConnectProvider, MendixSSO.SUB_GetUserInfoFromIdentityProvider, MendixSSO.SUB_RefreshTokens)
- the real behaviour of an external system (answers, limits, errors): a stand-in only returns shaped data, so a pass on it is reported as PASS (on stand-in APIs), never plain PASS
- single sign-on and any login through an identity provider: the sandbox uses local smoke users
- data the sandbox database does not hold (an action that needs rows of a kind that does not exist yet): the heal step seeds identical rows in both databases where it can, the rest stays INVALID

### How each gap is closed

- classify every UNKNOWN endpoint (static, data-driven or add-on) in apimock-classify.txt; owner: the person who knows the integration
- seed the data that data-driven endpoints need, in the old and the new database alike; owner: the app owner
- run the apis rung against a real test system before go-live and compare with the stand-in run; owner: a named person on the customer side
- go-live decision on every INVALID journey that remains: accept in writing or test by hand; owner: a named person

## 6. Sign-off

A person writes exactly one of these two lines below (an agent never does):

`Signed-off: <name> <yyyy-mm-dd>`   or   `Status: PAUSED <reason>`

Status: open
