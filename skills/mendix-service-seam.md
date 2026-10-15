# Mendix Service Seam — OData and REST Between Two Mendix Apps

**Applies to:** any mxcli project where one Mendix app publishes a service another Mendix app
consumes — usually after a split (`decompose-app.md` Stage 5), also any app-to-app seam.
**Purpose:** Patterns that worked, and the concrete failure each one prevents, for publishing
OData/REST from one Mendix app and consuming it as external entities and REST calls in another.
**Evidence:** a public field-service template split on 2026-10-12: its monolith (Mendix 10.24)
publishing its core over OData and REST to a slice app on 11.13 (*core run*), then the slice's
modules deleted from the monolith, which reads the slice back (*strangled run*). Error texts below
are verbatim from those runs; their captures are not committed to the toolkit. Results:
`pipelines/mendix-mpr/README.md` → "Field runs".

**Not this skill:** a third-party REST API with JSON structures and mappings →
`rest-integration-first-time-right.md`. Where to cut an app → `decompose-app.md`.

---

## Patterns

Each: do this → the failure it prevents → where it was captured.

**P1 Key: add `PublicID: AutoNumber default 1`.**
`alter entity M.E add attribute if not exists PublicID: AutoNumber default 1;` — accepted as the
OData key without a unique rule (core run). `default 1` is
mandatory (MDL023/CE7247). **Grant read on `PublicID` to every module role with an access rule on
the entity** — page-created objects fail on commit otherwise: `Failed to commit: Value of
auto-number attribute 'PublicID' not available, could be caused by insufficient access rights …`
(strangled run). A unique rule on an existing attribute only when every create path fills it.
*Anti:* a key with no unique rule passes `check`, then `CE6624`; no key →
`CE6585 "Published entity '…' must have a key defined."` (first web slice run).

**P2 Machine role only, on both services.** One machine user role (here `CoreAPIClient`) with one
read-only module role per published module, granted exactly the published members; create/delete
only where a REST action writes. Measure all three:
```
GET odata/core/v1/Technician (machine role)      HTTP 200
GET odata/core/v1/Technician (no credentials)    HTTP 401
GET odata/core/v1/Technician (human role)        HTTP 404
```
Basic auth with the password in each app's local constant store is the minimal route the field runs
proved; over TLS only. For production prefer token-based service auth via the OIDC SSO module (client
credentials); the Mendix SSO module is deprecated as of 1 May 2026. The publisher picks the method and
the consumer must match it (https://docs.mendix.com/refguide/consumed-odata-services/).
Measured on the core run. 401 = no or bad credentials; 404 = authenticated but the role has no access
to the service. *Anti:* a human role on the service exposes the API to every user login.

**P3 REST action: primitive query params, String result, no mappings.** Behaviour-carrying writes
go to a published REST action backed by an upsert microflow:
`call rest service post '{1}/rest/core/v1/rosters?AssetSystemID={2}&…' … returns String`
(core run). Between Mendix apps no JSON structure or import mapping is
needed. Base URL in a per-environment constant.

**P4 Every REST call has an error handler.** `on error without rollback` + log + user message.
*Anti 1:* the first seam call had none, so a far-side outage rolled back the caller's own commit
(first seam probe, 2026-10-12).
*Anti 2:* **OData-backed widgets have no error path.** With the owner stopped, opening an asset
raised `Exception while retrieving data for 'AssetManagement.Snippet_Asset_DataTabs…'` dialogs and
the page was unusable (core run). Mitigate with lazy tabs, or REST-fed local copies for
pages that must survive an outage — otherwise record an availability-coupling hand-off.

**P5 Cross-app join via a published mirror** — see recipe B.
*Anti:* XPath over local ↔ external: `[CE0161] "Error(s) in XPath constraint."`
(core run); database-grid columns over the same path pass `mx check` silently.

**P6 One consumer module per service where navigations are needed.** `create external entities`
creates navigation associations only inside one target module (`Created 8 navigation
associations`, core run). *Anti:* the same remote set in a second module passes mxcli,
then `[CE6609] "External entity with the same remote source already exists."` (core run).

**P7 Delete through the owner's own delete flow** (a REST action calling e.g. `Roster_Delete`), so
its cascades and side effects still run. *Anti:* a raw delete skips them. Never delete-and-recreate
under the same key; soft-delete instead.

**P8 Enumerations arrive as `Edm.String`.** Consumers compare strings, not enum values.

**P9 DateTime as UTC ISO** (`2026-10-11T22:00:00.000Z`), or an agreed date-only convention.
*Anti:* a zone-less `yyyy-MM-dd` string was shifted by the runtime timezone and landed a day early
(core run).

**P10 Version the path.** A new or changed published member is a contract change: publish
`…/v2/`, keep `v1` until every consumer moved.

**P11 Secrets.** Basic-auth password only in each app's machine-local constant store (one secret,
two stores); model default `__SET_ME__` plus a guard wherever code acts on it; the API account
password meets the Mendix password policy (`learned-constants-and-secrets.md`).
*Anti:* a generated password with no symbol failed inside the after-startup account create —
`This requires the password to contain non-alphanumeric characters` →
`M2EE: Starting Mendix Runtime failed.` (core run).

**P12 Consumer auth on 11.x: `HeadersMicroflow:`, not `ConfigurationMicroflow:`.**
*Anti:* `[CE6808] "The microflow that configures a consumed OData service should return a
System.ConsumedODataConfiguration"` (core run, on 11.13; the same model passed on 10.24). The slot cannot be
cleared afterwards, and `set (ConfigurationMicroflow: none)` stores a microflow named `none` that
crashes `mx check`. Fix: drop the consumed service and recreate it with `HeadersMicroflow:` only —
external entities survive.

**P13 Ownership.** A slice-owned association to an external entity loses the owner's delete
cascade: when the far side deletes, local rows orphan. The same holds from the monolith side: its
own delete cascades into slice rows are lost once those rows move (field-service template:
`AppointmentList_Delete`, `WorkOrderList_Delete`). Fix: a published REST delete-for-parent action on the owner (P7), or an
orphan hand-off row. A local save next to a REST write is a dual write — a hand-off until one side
goes.

---

## External-entity limits

What re-pointing a consumer at an external entity costs — `mx check` will not tell you all of it:

- **Associations:** local → external only with the **local entity as owner**; an external entity
  cannot own one (hand-off). A reference set local → external works, but entity-path widgets over it
  fail `[CE6634] "An association to or from an external entity is not allowed in an entity path
  source."` (strangled run). A slice-owned association to a monolith entity cannot be
  published — publish a key copy (B′). Inherited attributes cannot be published via mxcli: give each
  specialization its own key.
- **XPath:** cannot traverse local ↔ external — retrieves, access rules, pages and nanoflows using
  one break. Also CE0161: comparing the local entity's own local → external association with an
  object (`[TicketManagement.Ticket_Asset = $Asset]`), and retrieving an external entity by reverse
  association. Retrieve over the navigation instead. Access-rule disjuncts that walk such a path
  become `[false()]` or need a local owner entity (recipe B, P5).
- **Writes:** Commit/Change/Delete on an external entity do not work — rewrite to Send External
  Object (Insertable/Updatable/Deletable publish) or a REST action (P3). The consumer cannot create
  an external object: post a non-persistent draft.
- **Aggregates:** count works; sum/avg/min/max run in memory or not at all; no OQL or datasets.
  Totals need a published aggregate or a local copy.
- **Offline:** native offline profiles cannot hold external entities — REST-fed local copies.
  Push chains that ended in the owner's commit flows die when those flows move: rebind each to the
  REST write and add a pull entry (field-service template: `NativeSync_Pull*`).
- **Security:** external entities need read grants to a consumer module role. Granting a module
  role of one module on another module's entity → `[CE0007] "Please re-select module roles."`
  (core run).

Source: https://docs.mendix.com/refguide/external-entities/ and `published-odata-entity/`.

---

## Recipe A — Replace a stub by an external entity

Pages and flows rebind by qualified name, so the external entity takes the stub's name. Order
matters because `drop entity` silently deletes every cross-module association pointing at it
(and their member rights), and navigations exist only within one module (P6):

1. Record every association the stub had (`describe entity`), and which side owned it.
2. Drop the stub's owned associations.
3. Drop the stub entities.
4. `create external entities` for the whole service into **one** consumer module.
5. Re-create the slice-owned associations (local entity as owner).
6. Rewire consumers by name; `mx check` after every exec.


## Recipe B — Cross-app join via a published mirror

The consumer needs "tickets of this asset" but the asset lives in the consumer and the tickets in
the owner.

1. The owner keeps (or upserts) a mirror of the consumer entity keyed by the **consumer's** key —
   `MonoAsset` keyed `SystemID` with a unique rule — and publishes it.
2. The consumer filters on the key, not on an association across apps:
   `[Ticket_Asset/MonoAsset/SystemID = $Asset/SystemID]` (core run, "filtered over the navigation").
3. Consumer writes reach the owner via REST, which upserts the mirror (dual owner — hand-off row).
4. Where an access rule must walk the join, a local owner entity carries it
   (`CoreSeam.TechnicianLink`, names copied from OData at link time).

The mirror is **temporary**: at level 3 it lives in the module being deleted. **B′:** the
owner-side entity carries a copy of the consumer's key, set before commit and published; the
consumer filters on it. Removing the mirror from a published service is a breaking change (P10).

---

## Completion criteria

Bound for a seam: every line below holds, each with its count stated.

- Every published service grants **exactly one** machine role, measured 200 / 401 / 404 per
  service (N of N services captured).
- Every published key is `PublicID` AutoNumber or an attribute with a unique rule filled by every
  create path, readable by every module role with an access rule on its entity (N of N keys named
  with their kind).
- Every `call rest service` has `on error` (0 calls without; grep the MDL).
- Every external entity on a page is listed with its outage behaviour — lazy tab, local copy, or
  availability-coupling hand-off (N of N pages; "not probed" is legal, silence is not).
- Every external entity has a read grant; `mx check` 0 on both apps.
- Every slice-owned association to an external entity has an orphan hand-off row or a reason
  it cannot orphan.
- Every DateTime crossing the seam is UTC ISO or under a written date-only convention.
