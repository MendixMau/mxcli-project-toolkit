# Coverage Ledger — HB_Booking

Per `skills/coverage-ledger.md`. Covers BRD(s): F003, F004. Each BRD gets its
own BUILDABLE/NONBUILDABLE table pair below — `bin/coverage-check.sh` runs against one
BRD at a time; run it once per BRD section listed here.

Grouping is per top-level BRD key (`/domainEntities/*`, `/useCases/*`, ...) rather than
per leaf-field, because `bin/coverage-check.sh`'s wildcard syntax (`/a/b/*`) is a PREFIX
match — it cannot select "just the `name` field of every array item" while excluding
`module`/`sourceRef` siblings in the same object. A coarser, per-container claim is what
the tool actually supports; the count on each row is real (verified against the BRD via
`jq`, not estimated) and drift (a leaf added or removed under that container) changes the
count and fails the mechanical check, which is what catches drift going forward.

## F003

Total leaves: 251

### Table 1 — Buildable

| pointer | type | title | slice | writeMode | acceptance | status |
|---|---|---|---|---|---|---|
| /actors/* (2) | requirement | F003 `actors` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /domainEntities/* (53) | requirement | F003 `domainEntities` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /integrations/* (5) | requirement | F003 `integrations` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /microflows/* (11) | requirement | F003 `microflows` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /pages/* (9) | requirement | F003 `pages` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /useCases/* (139) | requirement | F003 `useCases` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |

### Table 2 — Non-buildable

| pointer | category | reason |
|---|---|---|
| /id | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /modules/* (1) | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /openQuestions/* (16) | open-question | Unresolved or unattended-run-assumed decision, tracked in PROJECT.md's Open questions table and Rulings ledger, not yet a settled buildable requirement. |
| /provenance | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /sourceKB/* (12) | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /title | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |

## F004

Total leaves: 126

### Table 1 — Buildable

| pointer | type | title | slice | writeMode | acceptance | status |
|---|---|---|---|---|---|---|
| /actors/* (3) | requirement | F004 `actors` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /domainEntities/* (28) | requirement | F004 `domainEntities` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /microflows/* (5) | requirement | F004 `microflows` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /pages/* (3) | requirement | F004 `pages` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |
| /useCases/* (66) | requirement | F004 `useCases` | build-plan rows 7-9 (domain), 22-27 (microflows/pages/prove/run) | CLI | `mxcli check --references` clean + PROVE row green for this module | PLANNED |

### Table 2 — Non-buildable

| pointer | category | reason |
|---|---|---|
| /id | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /modules/* (1) | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /openQuestions/* (12) | open-question | Unresolved or unattended-run-assumed decision, tracked in PROJECT.md's Open questions table and Rulings ledger, not yet a settled buildable requirement. |
| /provenance | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /sourceKB/* (5) | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
| /title | provenance | Metadata identifying/tracing the requirement (id, title, module assignment, provenance/sourceKB) or per-item traceability fields folded into the same container as buildable content — not itself a buildable element. |
