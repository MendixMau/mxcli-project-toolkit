# Coverage Ledger — HB_Reporting

Per `skills/coverage-ledger.md`. Covers BRD(s): F007. Each BRD gets its
own BUILDABLE/NONBUILDABLE table pair below — `bin/coverage-check.sh` runs against one
BRD at a time; run it once per BRD section listed here.

Grouping is per top-level BRD key (`/domainEntities/*`, `/useCases/*`, ...) rather than
per leaf-field, because `bin/coverage-check.sh`'s wildcard syntax (`/a/b/*`) is a PREFIX
match — it cannot select "just the `name` field of every array item" while excluding
`module`/`sourceRef` siblings in the same object. A coarser, per-container claim is what
the tool actually supports; the count on each row is real (verified against the BRD via
`jq`, not estimated) and drift (a leaf added or removed under that container) changes the
count and fails the mechanical check, which is what catches drift going forward.

## F007

Total leaves: 66

### Table 1 — Buildable

| pointer | type | title | slice | writeMode | acceptance | status |
|---|---|---|---|---|---|---|
| /actors/* (2) | requirement | F007 `actors` | build-plan rows 4-6 (domain), 34-36 (microflows/pages/prove) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /domainEntities/* (28) | requirement | F007 `domainEntities` | build-plan rows 4-6 (domain), 34-36 (microflows/pages/prove) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /microflows/* (6) | requirement | F007 `microflows` | build-plan rows 4-6 (domain), 34-36 (microflows/pages/prove) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /pages/* (3) | requirement | F007 `pages` | build-plan rows 4-6 (domain), 34-36 (microflows/pages/prove) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /useCases/* (14) | requirement | F007 `useCases` | build-plan rows 4-6 (domain), 34-36 (microflows/pages/prove) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |

### Table 2 — Non-buildable

| pointer | category | reason |
|---|---|---|
| /id | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /modules/* (1) | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /openQuestions/* (6) | open-question | Unresolved or unattended-run-assumed decision, tracked in PROJECT.md's Open questions table and Rulings ledger, not yet a settled buildable requirement. |
| /provenance | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /sourceKB/* (3) | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /title | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
