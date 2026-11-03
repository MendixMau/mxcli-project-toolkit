# Increment 6 (Decompose, core services) — new mxcli 0.26.0 defects

**From:** MendixMau — toolkit lab run, Decompose increment 6, core services (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** a public Marketplace template (FSM), monolith 10.24 publishing its core to the 11.13 Assets slice; captures not committed (lab run, #293). Numbered captures and `.mdl` files cited below were not shipped. mxcli v0.26.0.
**Proposed target:** `bug-logs/mxcli-bugs.md`

---

1. **`check --references` ignores attributes added earlier in the same script.** `alter entity M.E add attribute P:
   AutoNumber default 1;`, then a microflow `retrieve $X from M.E where [P = $v] first;`, then `mxcli check s.mdl -p app.mpr
   --references` → `the constraint names "P", which is neither an attribute nor an association of it — mxbuild rejects
   the constraint (CE0161 …)`. exec and `mx check` are fine (captures 01, 02).
2. **`drop entity` silently removes cross-module associations to the entity, and their member rights elsewhere.** Repro:
   entity `B.T`, association `A.X_T from A.X to B.T` (declared in A), `drop entity B.T`. The drop prints only `Dropped
   entity: B.T`, and then `describe association A.X_T` gives `Error: association not found`. The member rights on `A.X`'s
   access rules go too (capture 05; `slice-core-external.mdl` header).
3. **A dropped owner-Both association leaves a hidden MemberAccess on the other entity's access rules.** Repro:
   association `C.S_A from C.S to A.A owner Both`, `drop association C.S_A` → `mx check` `CE1613 "The selected
   association 'C.S_A' no longer exists." at Access rule of entity 'A.A'`. `describe entity A.A` does not show the
   member, and `revoke all on entity A.A from R;` + `grant …` does not remove it. Workaround: create an association
   of that name from a throw-away entity in module C, then drop it (`slice-core-fix2.mdl`, capture 12).
4. **Consumed OData: a headers microflow given as `ConfigurationMicroflow:` is CE6808 on 11.13, and the slot cannot be
   cleared.** `create consumed odata service … ConfigurationMicroflow: microflow M.Headers` (returns `List of
   System.HttpHeader`) passes on 10.24 and gives `CE6808 "The microflow that configures a consumed OData service
   should return a System.ConsumedODataConfiguration"` on 11.13. After that: `alter … set (HeadersMicroflow: …)` adds
   the headers slot and keeps the configuration slot; `create or modify` with only `HeadersMicroflow:` →
   `Unchanged OData client`; a real configuration microflow → `CE1135` (URL in constant and microflow), and
   `ServiceUrl` cannot be removed (CE6825 guard). Only `drop consumed odata service` + create works (capture 12).
5. **`set (ConfigurationMicroflow: none)` stores a microflow named `none`** (also `empty`). `describe` then shows
   `ConfigurationMicroflow: microflow none`, and `mx check` 11.13 crashes with a stack trace ending `at
   Mendix.MxToolset.MxToolset.ProcessArguments(String[] commandLineArgs) in Mendix.MxToolset\MxToolset.cs:line 113`.
6. **`check` passes, exec refuses the same statement (MDL-V1-REBUILD), mid-script.** `create or modify microflow
   AssetManagement.Asset_DeleteRosters` (body `retrieve $RosterList …; delete $RosterList` replaced by a call) → `check`:
   `Check passed!`; exec: `this change cannot be spliced into the stored flow: alter microflow …: replace $RosterList:
   $RosterList is still used by: delete $RosterList refresh`. `check` did flag 5 other flows of the same script for
   the same rule. Earlier statements stay applied (capture 07).
7. **`create external entities` creates navigation associations only within the target module, silently.** Creating
   `Ticket` into module T and `MonoAsset` into module C gives no `Ticket_Asset` and no warning. Creating the same entity
   set into a second module passes mxcli and fails `mx check` `CE6609 "External entity with the same remote source
   already exists."` (captures 05, 08, 09).
8. **`describe consumed odata service` shows an absolute local path:** `MetadataUrl: 'core-metadata.xml'` describes as
   `MetadataUrl: 'file:///<lab>/web-assets/AssetsApp/core-metadata.xml'`. It is unclear whether the model stores it; if
   it does, it leaks a machine path to Team Server.

Confirmed again: increment 5 defect 1 (combo box `Attribute:` on an association passes `check`, exec refuses), capture 07.
