# Multi-App Release — shared modules, contract-ordered rollout, run-once migrations

**Applies to:** any mxcli project in a system of two or more Mendix apps (`multi-app-system.md`)
when a change **crosses apps**: a published contract changes, a shared module gets a new version,
or seed/reference data must change in more than one app.
**Purpose:** ship that change in an order where no consumer is ever pointed at something its
publisher no longer serves, every app ends on the same shared-module content, and every data change
runs once per database.

**Not this skill:** keeping the system register itself → `multi-app-system.md`. Designing one
REST contract and its test ladder → `rest-between-mendix-apps.md`. One OData/REST seam →
`mendix-service-seam.md`. Where approved MPKs are catalogued → `company-brain.md` → "Components".
A change inside one app with no crossing → `existing-app-change.md`.

---

## When this fires

Before the **first** app is changed, and before anyone writes the release order — when the change
touches a contract, a module, a seed or a persona list that more than one app in `SYSTEM.md` uses.

---

## 1. Shared modules ship as approved MPKs, with a version per app

A module more than one app uses is **one package, not N copies**.

1. **One source app owns it.** Package it from there (probe `./mxcli marketplace --help` on your
   binary for the package/install subcommands), and put the `.mpk` plus its manifest in the company
   brain's `components/` (`company-brain.md` → "Components"). A component without a manifest is not
   approved.
2. **Record, per app, the version installed and a content hash** in `SYSTEM.md` → Shared assets.
   Internal (non-Marketplace) modules carry **no version number in the model**
   (https://community.mendix.com/link/spaces/studio-pro/ideas/5395), so the manifest version is
   the name and the hash is the proof: hash the module's MDL as the CLI prints it in each app, and
   compare (not yet field-run across apps; record the command you used beside the hash). Same
   version, different hash = a local edit; record it or remove it.
3. **No edits inside a shared module in a consumer app.** Extend through its extension points or a
   separate module. Studio Pro's Marketplace update merges three-way and keeps local edits, but
   replaces the module when mapping fails (https://docs.mendix.com/refguide/updating-marketplace-modules/)
   — a local edit is a bet on that merge.
4. **Check the Mendix range** in the manifest against **every** consumer's Mendix version before
   the first install. A module that exists only for a newer Mendix forces an app upgrade or a second
   package line.

*Failure it prevents:* a shared look was "reused" by slicing one app's stylesheet into another; the
planned shared shell module was proposed and never packaged. Five apps later a design change had to
be applied by hand five times, and two apps had drifted from the others.

---

## 2. Release order comes from the contract links — expand, switch, contract

Read the order off `SYSTEM.md` → Contracts, not from memory: for the contract that changes, list
its publisher and **every** consumer row.

| Step | Who | What | Done when |
|---|---|---|---|
| **1. Expand** | publisher | Publish `v2` **beside** `v1` (new path, new version). `v1` unchanged. | `v2` at rung 4 (`rest-between-mendix-apps.md` §3); register row `v2: built` |
| **2. Switch** | each consumer, one at a time | Point at `v2` behind a **toggle constant** (e.g. `Source = V1 \| V2`), default `V1`; flip per environment. | consumer's own tests green on `V2`; register shows that consumer on `v2` |
| **3. Contract** | publisher | Remove `v1` **only when the register shows 0 consumers on `v1`**. | `v1` consumers: 0; removal is its own release |

- **Additive changes stay inside a version; breaking changes never do** — removing a member or
  adding a required input is a new version (https://docs.mendix.com/refguide9/consumed-odata-service/).
- **The Catalog keeps one definition per version.** It keys a contract on the version number and
  keeps only the last definition it received for that version, so a breaking change deployed under
  an unchanged version **overwrites the contract every environment sees**. Fix: bump the version
  and redeploy (Mendix support article https://support.mendix.com/hc/en-us/articles/28518124661532,
  behind a Mendix login).
- **`check` and `impact` will not stop a breaking change.** Observed once, not field-run (mxcli v0.28, a research experiment on copies of mxcli's
  public `testdata/testapp-views` model, 2026-11-05): renaming a
  published REST resource under an unchanged `Version: '1.0.0'` passed `check` and `exec`; removing
  an attribute exposed by a published OData service passed both and `mxcli impact` reported it
  unreferenced. Grep the published services yourself before removing or renaming.
- **The toggle is a non-secret constant** (`learned-constants-and-secrets.md`). Keep the local or
  `v1` path working until step 3: it is the rollback.

*Failure it prevents:* the order "publisher first, then readers, then the consumer switches base
URL, then the cross-app journey" was right, but written once by hand for one contract; the next
contract had none, and a consumer was built and journey-tested against a mock of an API its
publisher's model did not reference at all.

---

## 3. Data migrations run once per database

Mendix has no platform feature for versioned data migrations
(https://community.mendix.com/link/spaces/databases/ideas/2866). The convention:

- **A named, ordered, run-once microflow called from the after-startup flow**, recording its id in
  a migration-log entity so a second start skips it (the pattern of Act_Migrate,
  https://marketplace.mendix.com/link/component/120423).
- **Idempotent**: re-running it on a database where it already ran changes nothing. Prove it with a
  test that runs it twice.
- **Per app, in that app's order.** Shared seed rows belong to their owner app (`SYSTEM.md` →
  Shared assets); a consumer reads them over the contract or receives a copy, never a second
  hand-maintained seed.
- **Ships with the release that needs it**, after the expand step and before the switch that
  depends on the new data.

---

## Pre-release checklist

Post it in chat (`conversion-runbook.md` §1b) and fill each count from the register and the apps.

- [ ] **Apps touched:** N of N affected apps named, each with its owning session (`multi-app-system.md` §2).
- [ ] **Shared module:** N of N consumer apps show the target version **and** the same content hash
      in `SYSTEM.md` — or a waiver line per app with a reason.
- [ ] **Mendix range:** N of N consumer apps' Mendix versions inside the package's manifest range.
- [ ] **Contracts:** C of C changed contracts have a version bump; 0 breaking changes under an
      unchanged version.
- [ ] **Order:** every changed contract has its expand → switch → contract rows written, with the
      consumers listed from the register (K of K consumers).
- [ ] **Toggles:** every switching consumer has its toggle constant and its default stated per
      environment.
- [ ] **Removal:** every contract version being removed shows **0** consumers in the register.
- [ ] **Migrations:** M of M run-once migrations named, ordered, idempotence-tested, and logged per app.
- [ ] **Cross-app proof:** rungs per `rest-between-mendix-apps.md` → "Cadence" (release row) —
      `NOT RUN` is legal with a reason, silence is not.
- [ ] **Register mirrored:** the release decision is a `SYS-D` row with a pointer row in each
      affected app's `PROJECT.md`.
