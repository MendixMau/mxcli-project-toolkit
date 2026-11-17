# Upgrading a Mendix app: the upgrade toolkit

Moving an existing app to a newer Mendix version is its own job, with its own repo:
**[MendixMau/mendix-upgrade-toolkit](https://github.com/MendixMau/mendix-upgrade-toolkit)**.

It runs the upgrade as a scripted pipeline with gates, driven by a coding agent and mxcli:

| Phase | What happens |
|---|---|
| Find | Triage of the app: versions, Marketplace modules, own edits, release notes that touch it |
| Plan | A proposal you read and sign before anything changes |
| Upgrade | Convert, module updates, build repair |
| Test | Old app and new app side by side: data diff, smoke walk, page layout, journeys |
| Go-live | A gate verdict (PASS, FAIL or INVALID, with evidence) and one cockpit page to follow and sign off the run |

## How the two toolkits relate

- This toolkit builds and changes apps. The upgrade toolkit moves an app from one Mendix version to the next.
- The upgrade toolkit vendors this toolkit's journey engine (`e2e`), so journeys written here also run in its test phase.
- Start with its `upgrade-toolkit/SKILL.md` (what to run, in order) and `upgrade-toolkit/SETUP.md`.
