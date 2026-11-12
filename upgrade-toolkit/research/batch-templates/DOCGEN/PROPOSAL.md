# Upgrade proposal: 10.24.21.108016 -> 11.12.5

<!-- proposal inputs-hash: 55c6d13ba82c67c13e30fdeffa06428b0212684f898660d7b1ebda16989ace94 -->

Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. Every line starting with `- ` is an item; sub-lines are evidence.

## 1. Summary

- From 10.24.21.108016 to 11.12.5 (rung 1 10.24.21.108016 -> 11.12.5). App size: 10 modules, 57 pages, 176 microflows, 136 actions.
- 5 items the toolkit expects to handle, 1 need your decision, 5 need a person anyway.

## 2. Done by the toolkit

Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no successor are never here; they are in section 3.

- module update Atlas_Core 3.19.0 -> 3.21.1 (before the convert)
- module update Atlas_Core 3.19.0 -> 4.5.1 (after the convert)
- module update Atlas_Web_Content 3.9.0 -> 4.4.0 (after the convert)
- module update DataWidgets 3.11.4 -> 3.11.7 (before the convert)
- module update NanoflowCommons 5.2.1 -> 7.4.0 (after the convert)

## 3. Needs your decision before we start

Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. Signing section 6 without an answer accepts the recommendation of that item.

- [P-1] module: ApprontoLicenser
  - evidence: stranded (no version fits the target): installed 7.0.1 (content 1445, min 9.18). The listing's newest, 1.0.0 "Emixa Licenser module" (min 11.12.1), restarts the numbering under a new name, so it is not planned as an update. Whether 7.0.1 runs on 11.12.5 is not known before the gate. (stranded.md)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: hand to a named person (no version fits; port, replace or remove); effort L; risk: behaviour of local edits is lost on update
  - answer: not yet

## 4. Needs a person anyway

- release-impact rows a person must judge
  - 174 of 174 rows have no 'handled' entry yet (release-impact.md)
- key-user confirmation of the user processes (status: confirmed is set only by a person)
  - templates/process-interview.md; the number of processes is unknown at this point
- visual sign-off of the changed screens (shotdiff REVIEW pairs)
  - the number of changed screens is known only after the gate
- real test systems for external APIs: unclassified
  - 1 endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)
- go-live actions (deployment, data migration window, rollback decision)
  - outside the toolkit

## 5. Human effort

- decision touchpoints: module 1
- person-anyway touchpoints: 5, release rows to judge 174
- range for the decisions alone: 8 to 40 hours (toolkit assumption per item: S 0.5-2 h, M 2-8 h, L 8-40 h; not measured). Key-user time, screen review and go-live are not in it.
- unknown at this point:
  - not measured: kept.txt: written by the update step; before it runs, kept modules are only predicted by localedits RED rows and stranded.md
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
