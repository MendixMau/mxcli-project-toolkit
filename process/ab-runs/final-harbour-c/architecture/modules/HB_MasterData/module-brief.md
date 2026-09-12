# Module Brief — HB_MasterData

- **Dependency order:** 1 (depends on: none)
- **Build status:** not started
- **Toolkit commit:** 3d66695

## Pointers (source of truth — read these, don't duplicate them)
- Wireframes: none dedicated — master-data screens are generic Data Grid 2 CRUD (see
  `architecture/fit-gap.md`); if a future revision wants a bespoke wireframe, add it under
  `design/wireframes/` and this row.
- Blueprint: `architecture/blueprint.md` (module summary, Step 2 layer diagram)
- BRDs: `analysis/knowledge-base/brd/F002-master-data.brd.json`
- Domain MDL: `mdlsource/1-domain/02-hb_masterdata-domain.mdl` (build-plan row 3)
- Build-plan scripts: rows 1-3 (`architecture/build-plan.md`)

## Business layer (ba-agent)

### Roles & journeys
| Role | What they do in this module | Entry screen |
|---|---|---|
| ShippingAgent | Views own company's registration status | ShippingAgent_Overview (read-only for self) |
| BerthOfficer | Activates a newly registered agent | ShippingAgent_Overview |
| HarbourMaster | Reactivates a suspended agent; maintains Berth/Terminal master data | ShippingAgent_Overview, BerthMasterData_Overview |
| Inspector | Reads Vessel/Berth data for context during inspection | VesselRegistry_Overview (read-only) |

### Screens per role
| Screen (→ wireframe file) | Roles that reach it | Nav wire point |
|---|---|---|
| VesselRegistry_Overview (no wireframe — generic Data Grid 2) | all 4 roles (read); write not exposed via UI (seeded/registered via agent onboarding flow in HB_Booking's booking form, F002 UC002-1/2) | `Config` toolbar (admin-style, not top-level nav — no chapter gives it a primary nav slot) |
| ShippingAgent_Overview (no wireframe) | BerthOfficer (activate), HarbourMaster (reactivate), ShippingAgent (read own) | `Config` toolbar |
| BerthMasterData_Overview (no wireframe) | HarbourMaster (write), all others (read) | `Config` toolbar |

### Access table
| Element | Type | Module role(s) | Access level |
|---|---|---|---|
| Vessel | entity | ShippingAgent, BerthOfficer, Inspector | read `*` |
| Vessel | entity | HarbourMaster | read `*`, write `*` |
| ShippingAgent | entity | ShippingAgent | read `(own record)` |
| ShippingAgent | entity | BerthOfficer | read `*`, write `(IsSuspended → false only, via activate)` |
| ShippingAgent | entity | HarbourMaster | read `*`, write `*` |
| Terminal, Berth | entity | ShippingAgent, BerthOfficer, Inspector | read `*` |
| Terminal, Berth | entity | HarbourMaster | read `*`, write `*` |
| ACT_ShippingAgent_Activate | microflow | BerthOfficer, HarbourMaster | execute |
| ACT_ShippingAgent_Reactivate | microflow | HarbourMaster | execute |
| ACT_ShippingAgent_Suspend | microflow | (system/scheduled, no role) | execute (system) |
| VAL_BerthAllocation_FitCheck | microflow | all 4 (called from HB_Booking's submit flow) | execute |

### Field-level validation & edge cases
| Field / action | Rule | Error path |
|---|---|---|
| Vessel.IMONumber | Exactly 7 numeric digits (F002-Q1, conflict C3 — image-only rule); unique | inline validation message "IMO NUMBER MUST BE EXACTLY 7 DIGITS" per the prototype screenshot |
| ShippingAgent.IsSuspended | Set true automatically when 3+ own Invoices reach Status=Overdue (cross-module read into HB_Finance) | none — system-triggered, no user-facing error |
| ACT_ShippingAgent_Reactivate | Role-gated to HarbourMaster only; no self-service path exists at all | attempting to call from a non-Harbour-Master context is a security violation, not a validation message |
| VAL_BerthAllocation_FitCheck | Vessel.LengthOverall ≤ Berth.MaxLength AND Vessel.Draught ≤ Berth.MaxDraught − 0.5 | booking form (HB_Booking) shows the failure, not this module |

### Golden-path data effects
| Action | Creates/changes | Associations that MUST be set |
|---|---|---|
| ACT_ShippingAgent_Activate | ShippingAgent.IsSuspended → false (initial activation is really "onboarding complete", not a suspend/reactivate transition — see open question below) | none new |
| ACT_ShippingAgent_Suspend (system) | ShippingAgent.IsSuspended → true | none new |
| ACT_ShippingAgent_Reactivate | ShippingAgent.IsSuspended → false | none new |

### Open business questions
- [ ] F002-Q1 (RAISED→ASSUMED, Ruling R5): IMO number modelled as exactly-7-digit — confirmed by
      a returning human before Stage 5 build, not just this unattended run.
- [ ] Does "agent registers" (ch11 §7.1) create the ShippingAgent record directly, or does
      registration create an unactivated record that ACT_ShippingAgent_Activate merely flips a
      flag on? The source describes both as one sentence ("registers... and is activated by a
      Berth Officer") — this brief assumes a single record from registration onward with
      IsSuspended acting as the not-yet-active gate too (no separate "pending" state exists in
      the source's IsSuspended boolean). Flag for confirmation before scripting `02-hb_masterdata-domain.mdl`.

## Test plan

### Declared shape
| Part | This module | Why |
|---|---|---|
| UI (Playwright) | always | — |
| Data (source of truth) | always — OQL count/attribute assertions on Vessel/ShippingAgent/Berth/Terminal | no external source of truth exists for master data in this app |
| Unit (`.test.mdl`) | yes | IMO exact-7-digit validation and the fit-check formula are exactly the kind of "fiddly logic" `testing-shape.md` flags for unit coverage |
| Trace (OTel) | no | this module calls out to nothing external |

### Base set — the trigger
- [ ] `01-hb_masterdata-roles.mdl`
- [ ] `02-hb_masterdata-domain.mdl`

### Journeys
| Journey id | Persona | Trigger → outcome | Steps | Data effect asserted |
|---|---|---|---|---|
| `agent-suspend-reactivate` | HarbourMaster | 3rd overdue invoice → agent suspended → HM reactivates | 1 system suspends · 2 HM opens ShippingAgent_Overview · 3 HM reactivates | ShippingAgent.IsSuspended: false→true (system)→false (HM) |

### Interactive elements
| Known exclusion | Why it cannot be swept |
|---|---|
| _(none)_ | |

### Pages to LOOK at
Derived at review time from `SHOW PAGES IN HB_MasterData` — no wireframe exists for this
module's 3 admin-grid screens (see Screens-per-role table above); reviewer uses the unaided
rubric for those, not a wireframe cross-check.

## Technical layer (architect-agent)

### Domain summary
- Entities: Vessel, ShippingAgent, Terminal, Berth. Key associations: `Berth_Terminal`
  (many-to-one), `Vessel_ShippingAgent` (many-to-many). Exact attribute names/types: see
  `analysis/knowledge-base/brd/F002-master-data.brd.json`.

### Build skills to read first
- `skills/security-is-not-a-later-script.md` — entity + grants land in one script (domain row 3).
- `skills/learned-mdl-preflight.md` — Step 0 write-mode pick before any script.
- No Workflow, no Agent call site, no REST integration in this module — those three build-group
  skills do not apply here (explicitly noted, not silently omitted).

### Write-mode plan
| Element | CLI / MCP+MDL / hand-rolled MCP | Why |
|---|---|---|
| Vessel, ShippingAgent, Terminal, Berth (entities + attrs) | CLI (`mxcli exec`, SP closed) | plain entity/attribute creation, no STOP-table trigger |
| `Vessel_ShippingAgent` (many-to-many) | CLI | standard M:N, no junction entity needed (no extra attributes on the relationship per source) |
| Entity access grants | CLI, co-located with domain script | per `security-is-not-a-later-script.md` |

### Document folder plan
- **Feature groups:** `Vessels/`, `Agents/`, `BerthsAndTerminals/`, plus `Common/` for anything
  module-wide.

| Document | Folder |
|---|---|
| Vessel, VesselRegistry_Overview | `Vessels/` |
| ShippingAgent, ACT_ShippingAgent_*, ShippingAgent_Overview | `Agents/` |
| Terminal, Berth, BerthMasterData_Overview, VAL_BerthAllocation_FitCheck | `BerthsAndTerminals/` |

### Cross-module dependencies & integrations
- Depends on: none (bottom of the graph).
- Integrations: none — this module has no external call.

### Arch constraints that apply here
- Common-layer rule: this module must never own an association pointing into a feature module
  (HB_Booking/HB_Finance/HB_Inspection) — confirmed clean in `architecture/blueprint.md`'s
  Architecture review section.

## Ready-check
- [x] Every screen has a wireframe file that exists — **N/A for this module**: all 3 screens are
      generic admin CRUD grids, explicitly decided not to need a bespoke wireframe (see Screens
      per role table) — a conscious call, not an oversight.
- [x] Access table covers every page, microflow, and entity to be built
- [ ] No open business question blocks the elements in this build phase — **one does**: the
      registration-vs-activation modelling question above must be answered before
      `02-hb_masterdata-domain.mdl` is scripted.
- [x] Write mode chosen for every element that hits a learned-mdl-preflight STOP row (none do)
- [x] Folder plan names the module's feature groups and covers every document to be built
- [x] Test plan complete
- [x] Build skills to read first filled in (with explicit "none apply" for Workflow/Agent/Integration)
