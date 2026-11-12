# Upgrade proposal: 10.24.0.73019 -> 11.12.5

<!-- proposal inputs-hash: 3e9282bd088d1c0dc21275f3956a6b1948b81a0c67756e9c86a1addf1c4b5354 -->

Written by bin/proposal.py from the triage outputs. Nothing in the app model changes before section 6 is signed. Every line starting with `- ` is an item; sub-lines are evidence.

## 1. Summary

- From 10.24.0.73019 to 11.12.5 (rung 1 10.24.0.73019 -> 11.12.5). App size: 9 modules, 77 pages, 285 microflows, 280 actions.
- 7 items the toolkit expects to handle, 4 need your decision, 5 need a person anyway.

## 2. Done by the toolkit

Module updates and predicted repairs only. A kept module, a stranded module, a RED local edit and a widget with no successor are never here; they are in section 3.

- module update Atlas_Core 3.14.4 -> 3.21.0 (before the convert)
- module update Atlas_Core 3.14.4 -> 4.5.0 (after the convert)
- module update DataWidgets 2.14.0 -> 3.11.7 (before the convert)
- module update FeedbackModule 4.0.0 -> 5.0.0 (before the convert)
- module update NanoflowCommons 6.0.0 -> 7.2.1 (after the convert)
- module update WorkflowCommons 3.12.0 -> 3.12.1 (before the convert)
- module update WorkflowCommons 3.12.0 -> 4.10.0 (after the convert)

## 3. Needs your decision before we start

Answer each item in chat (steps/decide.md options); the toolkit records it in DECISIONS.md as the P-n line. Signing section 6 without an answer accepts the recommendation of that item.

- [P-1] module: Atlas_Web_Content
  - evidence: kept at its version by the update step: UNSAVED: no-baseline route saved 0 of its UI edits (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: behaviour of local edits is lost on update
  - answer: not yet
- [P-2] module: MendixSSO
  - evidence: RED local edit (data-bearing): CHANGED entity MendixSSO.MendixSSOUser (localedits.json / kept.txt)
  - options: keep old version (kept list) | replace with the Marketplace equivalent (replacements.tsv row) | rebuild locally, drop the module | hand to a named person
  - recommendation: keep old version (kept list); the stop rule keeps it unattended; effort M; risk: data loss if a RED edit is replaced
  - answer: not yet
- [P-3] theme: Atlas_Core themesource edits
  - evidence: localedits.json FILES-EDITED rows of Atlas_Core in themesource/
  - options: keep module styling and replay | adopt the package styling | hand to a named person
  - recommendation: replay the edits after the update (UI-only edits are replayed by the pipeline); effort S; risk: look only
  - answer: not yet
- [P-4] theme: Atlas_Web_Content themesource edits
  - evidence: localedits.json FILES-EDITED rows of Atlas_Web_Content in themesource/
  - options: keep module styling and replay | adopt the package styling | hand to a named person
  - recommendation: replay the edits after the update (UI-only edits are replayed by the pipeline); effort S; risk: look only
  - answer: not yet

## 4. Needs a person anyway

- release-impact rows a person must judge
  - 261 of 261 rows have no 'handled' entry yet (release-impact.md)
- key-user confirmation of the user processes (status: confirmed is set only by a person)
  - templates/process-interview.md; the number of processes is unknown at this point
- visual sign-off of the changed screens (shotdiff REVIEW pairs)
  - the number of changed screens is known only after the gate
- real test systems for external APIs: unclassified
  - 6 endpoints in apimock-inventory.json; the stand-in gives at best PASS (on stand-in APIs)
- go-live actions (deployment, data migration window, rollback decision)
  - outside the toolkit

## 5. Human effort

- decision touchpoints: module 2, theme 2
- person-anyway touchpoints: 5, release rows to judge 261
- range for the decisions alone: 5 to 20 hours (toolkit assumption per item: S 0.5-2 h, M 2-8 h, L 8-40 h; not measured). Key-user time, screen review and go-live are not in it.
- unknown at this point:
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
