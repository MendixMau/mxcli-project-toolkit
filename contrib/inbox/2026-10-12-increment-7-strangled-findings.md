# Increment 7 (Decompose, strangled) — new mxcli 0.26.0 findings

**From:** MendixMau — toolkit lab run, Decompose increment 7, strangled (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM), monolith 10.24 copy (MPR v1) with the Assets modules deleted, slice AssetsApp 11.13 (MPR v2); captures not committed (lab run, #293). Tools and captures cited below were not shipped. mxcli v0.26.0.
**Proposed target:** `bug-logs/mxcli-bugs.md`; platform bullets to `skills/mendix-service-seam.md`

---

New defects only; increment 6 #2 and #3 were confirmed again.

1. **`move entity` leaves qualified names inside XPath/expression text unchanged.** By-name references are rewritten
   ("Updated references in 38 document(s)"), but 62 strings in 24 units still named `AssetManagement.Asset…`
   (e.g. `[TicketManagement.Ticket_Asset/AssetManagement.Asset/AssetManagement.Asset_Technician_Preferred/…]`).
   Repro: a flow with `retrieve … where [X.R/M.E/Attr = $v]`; `move entity M.E to N;`; `describe` the flow → still `M.E`;
   `mx check` → CE1613/CE0161 once `M` is dropped. Workaround: BSON string rewrite (`tools/bson-rename.py`).
2. **Published OData: an inherited attribute of a specialization is stored under the specialization.** `publish entity
   Part.UsedPart … expose (PublicID (KEY), SystemID …)` (both on `Part.SelectedPart`) → `[CE1613] "The selected attribute
   'Part.UsedPart.PublicID' no longer exists." at Published attribute PublicID from entity Part.UsedPart`. The qualified
   form `Part.SelectedPart.PublicID as 'PublicID'` is a parse error (`mismatched input '.' expecting {',', ')'}`).
   Workaround: an own AutoNumber key on each specialization.
3. **`alter snippet/page … { drop w; }` cannot find a widget nested inside a legacy widget**, although `describe` lists it:
   `Error: failed to resolve snippet target: widget "referenceSetSelector2" not found`
   (`Technician.Snippet_Technician_DataTabs`). The whole script stops there. Workaround: BSON array-element removal.
4. **`grant read (…) on entity E to R where [xpath]` adds a second access rule when R already has one**; the old rule
   (and the CE1613 it carried) stays. `describe entity` afterwards shows two `grant … to CustomerManagement.ViewMy` lines.
   Expected: replace, or refuse with a hint to `revoke` first.
5. **A consumed OData service's cached `$metadata` cannot be refreshed.** After the metadata file changed,
   `create or modify external entities from S into M entities (…)` → `4 updated`, but no new attribute appears.
   No refresh statement exists. Workaround: `drop consumed odata service` + `create` (external entities survive).
6. **describe → drop + create of an unchanged microflow broke a decision.** `Scheduler.PlannerContext_GetWorkOrders`
   (316 lines): afterwards `[CE0117] "Error(s) in expression." at Decision 'User is SDE?'`; the described decision line is
   byte-identical before and after. Restored the original unit.
7. **describe output not re-executable:** `Synchronization.OfflineTicketAction_Validate` →
   `microflow returns Boolean but not all code paths have a return statement [MDL003]` (case + merges).
8. **`mxcli oql --json` returns numbers as strings** (`[{"Amount":"10"}]`), so `=== 10` fails in journeys.

Platform behaviour worth a learned-* line (not mxcli):
- a local entity's XPath cannot compare its local → external association with an object: `[TicketManagement.Ticket_Asset = $Asset]`
  → CE0161; nor can an external entity be retrieved by its reverse association (`[M.Inventory_Part = $Inventory]` → CE0161);
- an AutoNumber key on a page-created entity fails at commit without read access: `Failed to commit: Value of auto-number
  attribute 'PublicID' not available, could be caused by insufficient access rights to serialize the mendix object to the client`;
- trial licence: a consumer's OData calls got `The OData endpoint returned 402 Payment Required` once machine sessions accumulated;
- an external entity republished in a published OData service passes `mx check` and answers 404 at runtime;
- DataGrid 2 authored by mxcli on 10.24 is CE0463 until `mxcli fix widgets`.
