# Fixture: OutSystems 11 Source Manifest

This file simulates what `source-triage.md` would find after scanning the fixture source.
Feed this to the agent alongside the prompt (or use as a stand-in when no real source is available for the eval run).

---

## Source directory: `/fixtures/outsystems-sample-src/`

### Module inventory (18 modules total)

| Module | Type | Est. size | Classification |
|--------|------|-----------|----------------|
| CustomerPortal_CS | Business | 420 screens/actions | In scope |
| Reporting_CS | Business | 180 screens/actions | In scope |
| Notifications_BL | Business | 65 actions | In scope |
| Billing_CS | Business | 310 screens/actions | Out of scope (deferred) |
| AuthProvider_Lib | Framework/Lib | 40 actions | Framework — skip |
| StyleGuide_Th | Theme | 1 theme | Framework — skip |
| OutSystemsUI | Framework | (system) | Framework — skip |
| RichWidgets | Framework | (system) | Framework — skip |
| ... (10 more framework/system modules) | Framework | — | Framework — skip |

### Capability map

| Capability | Extractable? | Extractor | Notes |
|------------|-------------|-----------|-------|
| Screen definitions | Yes | `pipelines/outsystems/` | OutSystems pipeline covers |
| Server actions / microflows | Yes | `pipelines/outsystems/` | OutSystems pipeline covers |
| Data model (entities + attributes) | Yes | `pipelines/outsystems/` | OutSystems pipeline covers |
| REST integrations | Partial | `pipelines/outsystems/` | Endpoint names only, no auth config |
| Static data / reference tables | Yes | `pipelines/outsystems/` | |
| Theme / CSS overrides | No | — | Manual — capture in BRD |
| Custom JavaScript | No | — | Manual — review per screen |

### Extractor coverage: 85% (≥80% threshold met → Q2 is skip-eligible)

### Business vs framework breakdown
- Business modules: 4 (2 in scope, 1 deferred, 1 in scope)
- Framework/system modules: 14
- Business lines of code (estimated): ~18,000 actions/entities/screens
