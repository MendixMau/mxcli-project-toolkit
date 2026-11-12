# Upgrade proposal: 9.4.0.24572 -> 10.24.0.73019 -> 11.12.5

<!-- proposal inputs-hash: 2b438485e8512a30206868905c55e9a37a8c3fdc56135bdb85859593de496830 -->

Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. Every line starting with `- ` is an item; sub-lines are evidence.

## 1. Summary

- From 9.4.0.24572 to 10.24.0.73019 and 11.12.5 (rung 1 9.4.0.24572 -> 10.24.0.73019, rung 2 10.24.0.73019 -> 11.12.5). App size: 6 modules, 38 pages, 133 microflows, 106 actions.
- 4 items the toolkit expects to handle, 2 need your decision, 5 need a person anyway.

## 2. Done by the toolkit

Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no successor are never here; they are in section 3.

- module update Atlas_Core 3.0.2 -> 3.21.1 (after the convert)
- module update Atlas_Web_Content 3.0.2 -> 3.9.0 (after the convert)
- module update MendixSSO 2.3.1 -> 10.6.2 (after the convert)
- module update WorkflowCommons 1.2.0 -> 3.12.1 (after the convert)

## 3. Needs your decision before we start

Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. Signing section 6 without an answer accepts the recommendation of that item.

- [P-1] renamed module: DataGrid
  - evidence: RENAMED on the Marketplace: content 116540 is now 'DataWidgets' (installed DataGrid 1.1.3); no version update of DataGrid is planned. install DataWidgets (same content id, mxcli marketplace versions 116540 lists it), move the references, delete the old module only after idcheck; do not plan DataGrid as a version update (MR1, playbooks/module-renames.tsv)
  - options: install the new module and move the references | keep the installed module as is and test it at the gate | hand to a named person
  - recommendation: install the new module; effort M; risk: references and data of the old module are moved by hand
  - answer: not yet
- [P-2] theme: Atlas_Core themesource edits
  - evidence: localedits.json FILES-EDITED rows of Atlas_Core in themesource/
  - options: replay as is (S, repeats the break) | restore the package file and move wanted styling to the app's `theme/web/main.scss` (S) | express it with design properties of the widget (M, best) | hand off
  - recommendation: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md]; effort S; risk: look only
  - answer: not yet

## 4. Needs a person anyway

- release-impact rows a person must judge
  - 433 of 433 rows have no 'handled' entry yet (release-impact.md)
- key-user confirmation of the user processes (status: confirmed is set only by a person)
  - templates/process-interview.md; the number of processes is unknown at this point
- visual sign-off of the changed screens (shotdiff REVIEW pairs)
  - the number of changed screens is known only after the gate
- real test systems for external APIs: unclassified
  - 6 endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)
- go-live actions (deployment, data migration window, rollback decision)
  - outside the toolkit

## 5. Human effort

- decision touchpoints: renamed module 1, theme 1
- person-anyway touchpoints: 5, release rows to judge 433
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
