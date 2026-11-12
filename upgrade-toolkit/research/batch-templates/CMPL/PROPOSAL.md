# Upgrade proposal: 9.24.2.6130 -> 10.24.0.73019 -> 11.12.5

<!-- proposal inputs-hash: d8242847dd5375a9a5f222b2fd227a89aeebdefc5d5e10d8c54e6486677881c8 -->

Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. Every line starting with `- ` is an item; sub-lines are evidence.

## 1. Summary

- From 9.24.2.6130 to 10.24.0.73019 and 11.12.5 (rung 1 9.24.2.6130 -> 10.24.0.73019, rung 2 10.24.0.73019 -> 11.12.5). App size: 26 modules, 84 pages, 394 microflows, 204 actions.
- 2 items the toolkit expects to handle, 2 need your decision, 5 need a person anyway.

## 2. Done by the toolkit

Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no successor are never here; they are in section 3.

- module update DataWidgets 2.8.1 -> 3.11.7 (after the convert)
- module update MendixSSO 4.1.0 -> 10.6.2 (after the convert)

## 3. Needs your decision before we start

Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. Signing section 6 without an answer accepts the recommendation of that item.

- [P-1] module: PushNotifications
  - evidence: RED local edit (data-bearing): ADDED attribute PushNotifications.Device.LastUsed; ADDED attribute PushNotifications.Device.Status; ADDED attribute PushNotifications.MessagingServiceSettings.IsConcept (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: data loss if a RED edit is replaced
  - answer: not yet
- [P-2] theme: PushNotifications themesource edits
  - evidence: localedits.json FILES-EDITED rows of PushNotifications in themesource/
  - options: replay as is (S, repeats the break) | restore the package file and move wanted styling to the app's `theme/web/main.scss` (S) | express it with design properties of the widget (M, best) | hand off
  - recommendation: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md]; effort S; risk: look only
  - answer: not yet

## 4. Needs a person anyway

- release-impact rows a person must judge
  - 258 of 258 rows have no 'handled' entry yet (release-impact.md)
- key-user confirmation of the user processes (status: confirmed is set only by a person)
  - templates/process-interview.md; the number of processes is unknown at this point
- visual sign-off of the changed screens (shotdiff REVIEW pairs)
  - the number of changed screens is known only after the gate
- real test systems for external APIs: unclassified
  - 14 endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)
- go-live actions (deployment, data migration window, rollback decision)
  - outside the toolkit

## 5. Human effort

- decision touchpoints: module 1, theme 1
- person-anyway touchpoints: 5, release rows to judge 258
- range for the decisions alone: 2.5 to 10 hours (toolkit assumption per item: S 0.5-2 h, M 2-8 h, L 8-40 h; not measured). Key-user time, screen review and go-live are not in it.
- unknown at this point:
  - not measured: plan-pre.txt: no module updates are known for that pass (a 10.x source goes through plan-pre.txt, an 11.x or 9.x source has none)
  - not measured: kept.txt: written by the update step; before it runs, kept modules are only predicted by localedits RED rows and stranded.md
  - not measured: stranded.md: steps/triage.md item 3 lists stranded modules and add-on modules built before 10.21 there
  - not measured: replacements.md: steps/triage.md item 10: replacement_check.py --out
  - not measured: dojo-react.md: steps/triage.md item 10: dojo_report.py --out
  - not measured: widgetcover.py: it judges which widget packages the walks render; the walks of the new app exist only at the gate (widgets rung)
  - not measured: theme_clash.py: it compares the app's styling with the NEW Atlas, which exists only after the update
  - not measured: rolecheck.py: it compares the OLD and the NEW model; module roles are checked after each module update
  - not measured: usercode.py: it compares a module's Java user code per module, after the update step (.stepupdate/step<n>-<module>.usercode); Java edits that exist now are the localedits.json FILES-EDITED rows

## 6. Sign-off

A person writes exactly one of these two lines below (an agent never does):

`Signed-off: <name> <yyyy-mm-dd>`   or   `Status: PAUSED <reason>`

Status: open
