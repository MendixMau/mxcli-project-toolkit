# Mendix upgrade toolkit

A scripted Mendix upgrade with gates, run by a coding agent. Scripts do the fixed work: triage, baseline, convert,
Marketplace module updates, build, data diff, smoke walk, page layout compare, journeys and the gate. The agent
repairs build errors, fixes journeys and compares results. Every rung ends in PASS, FAIL or INVALID, with evidence.
A person follows the run on one cockpit page and signs off there.

```
find ──> plan ──> upgrade ──> test ──> go-live
triage    proposal   convert     smoke, layout,    gate verdict,
release   (signed    modules     journeys, data    cockpit page
impact    by you)    repair      old vs new
```

## Start here

| | |
|---|---|
| What to run, in order | [upgrade-toolkit/SKILL.md](upgrade-toolkit/SKILL.md) |
| Set up a machine or a cloud container | [upgrade-toolkit/SETUP.md](upgrade-toolkit/SETUP.md), paste-in prompt [SETUP-PROMPT.md](upgrade-toolkit/SETUP-PROMPT.md) |
| Read a verdict | [upgrade-toolkit/READING-THE-VERDICT.md](upgrade-toolkit/READING-THE-VERDICT.md) |
| See a finished run | [upgrade-toolkit/examples/](upgrade-toolkit/examples/): the cockpit page of an upgrade of a public Marketplace app |
| The toolkit's own tests | `bash upgrade-toolkit/controls/run-controls.sh --fast` (a catch and a pass case for every script) |
| One command for the fixed steps | `upgrade-toolkit/bin/cloud/upgrade-pipeline.sh --app-zip app.mpk --source <old full version> --target <new full version> --work run/work` |

Release-note tables per Mendix version: `company-brain-test/brain/baseline/versions/`.

## Related

- [mxcli-project-toolkit](https://github.com/MendixMau/mxcli-project-toolkit): the toolkit for building Mendix
  apps with a coding agent and [mxcli](https://github.com/mendixlabs/mxcli). Its journey engine is vendored here in
  `upgrade-toolkit/vendor/e2e`.
- [mxcli](https://github.com/mendixlabs/mxcli): the Mendix command line this toolkit drives.

## Licence

Apache License 2.0, see [LICENSE](LICENSE).
