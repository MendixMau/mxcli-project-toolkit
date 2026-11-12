# Upgrade proposal: 9.18.0.53394 -> 10.24.0.73019 -> 11.12.5

<!-- proposal inputs-hash: 0b1431120a63042f7954865e995ea5549d5f4e4a47fbea9c8d3ef64db0df5d97 -->

Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. Every line starting with `- ` is an item; sub-lines are evidence.

## 1. Summary

- From 9.18.0.53394 to 10.24.0.73019 and 11.12.5 (rung 1 9.18.0.53394 -> 10.24.0.73019, rung 2 10.24.0.73019 -> 11.12.5). App size: 27 modules, 115 pages, 598 microflows, 372 actions.
- 11 items the toolkit expects to handle, 3 need your decision, 5 need a person anyway.

## 2. Done by the toolkit

Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no successor are never here; they are in section 3.

- module update AWSAuthentication 2.1.1 -> 4.1.4 (after the convert)
- module update AmazonTextractConnector 1.0.0 -> 3.0.1 (after the convert)
- module update Atlas_Core 3.2.1 -> 3.21.1 (after the convert)
- module update Atlas_Web_Content 3.1.1 -> 3.9.0 (after the convert)
- module update DataWidgets 2.3.0 -> 3.11.7 (after the convert)
- module update DeepLink 9.0.2 -> 10.0.10 (after the convert)
- module update Email_Connector 1.2.0 -> 6.3.2 (after the convert)
- module update Encryption 8.0.2 -> 11.1.2 (after the convert)
- module update MendixSSO 3.1.1 -> 10.6.2 (after the convert)
- module update MxModelReflection 6.2.0 -> 9.1.0 (after the convert)
- module update WebActions 2.4.0 -> 2.11.2 (after the convert)

## 3. Needs your decision before we start

Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. Signing section 6 without an answer accepts the recommendation of that item.

- [P-1] module: DemoUserSwitcher
  - evidence: stranded (no version fits the target): installed 1.1.0 (content 120303); `mxcli marketplace versions 120303` lists no version at all, so nothing can be planned for 10.24 or 11. Owns Administration association DemoUser_Helper_Account. (stranded.md)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: hand to a named person (no version fits; port, replace or remove); effort L; risk: behaviour of local edits is lost on update
  - answer: not yet
- [P-2] module: MES_Atlas_Extension
  - evidence: stranded (no version fits the target): installed 2.0.1 (content 120035); no version listed for that content id. (stranded.md)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: hand to a named person (no version fits; port, replace or remove); effort L; risk: behaviour of local edits is lost on update
  - answer: not yet
- [P-3] theme: DataWidgets themesource edits
  - evidence: localedits.json FILES-EDITED rows of DataWidgets in themesource/
  - options: replay as is (S, repeats the break) | restore the package file and move wanted styling to the app's `theme/web/main.scss` (S) | express it with design properties of the widget (M, best) | hand off
  - recommendation: drop the replayed vendor edit, use the widget's design property (for the hero: Image fit Cover). [RA-6, tried once, playbooks/rearchitecture.md]; effort S; risk: look only
  - answer: not yet

## 4. Needs a person anyway

- release-impact rows a person must judge
  - 483 of 483 rows have no 'handled' entry yet (release-impact.md)
- key-user confirmation of the user processes (status: confirmed is set only by a person)
  - templates/process-interview.md; the number of processes is unknown at this point
- visual sign-off of the changed screens (shotdiff REVIEW pairs)
  - the number of changed screens is known only after the gate
- real test systems for external APIs: unclassified
  - 12 endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)
- go-live actions (deployment, data migration window, rollback decision)
  - outside the toolkit

## 5. Human effort

- decision touchpoints: module 2, theme 1
- person-anyway touchpoints: 5, release rows to judge 483
- range for the decisions alone: 16.5 to 82 hours (toolkit assumption per item: S 0.5-2 h, M 2-8 h, L 8-40 h; not measured). Key-user time, screen review and go-live are not in it.
- unknown at this point:
  - not measured: plan-pre.txt: no module updates are known for that pass (a 10.x source goes through plan-pre.txt, an 11.x or 9.x source has none)
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
