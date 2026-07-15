# MDL Pre-flight Checklist — STOP conditions before writing any script
**Applies to:** any mxcli project.
**Purpose:** Before drafting any MDL script, check every planned operation against this table. Each STOP row was born from a real MPR corruption or silent runtime failure — not theoretical concerns. Skipping this check has caused project-unloadable corruption every time.

**Source:** Generalized from a live Mendix 11.12.0 Beta project, 2026-07-06/07. Incident detail stays in that project's own `bug-logs/` — only the generalizable rule is here.

**Version context:** Rules marked "STOP" were confirmed on specific mxcli/Mendix versions noted per entry. Rules 1b and 10 were retested 2026-07-09 on mxcli v0.13.0 / Mendix 11.12.0 and confirmed resolved. Rule 9 was retested 2026-07-09 via `mxcli --mcp` on v0.13.0 and confirmed resolved (BSON serialization bug only affects the disk write path; `--mcp` bypasses it entirely). If in doubt, retest on your version and stamp the result in `bug-logs/mxcli-bugs.md`.

**Three write modes — choose by operation:**
| Mode | Command | When |
|---|---|---|
| mxcli disk write | `./mxcli exec script.mdl` | Default; SP must be closed; STOP rules apply |
| mxcli via MCP | `./mxcli --mcp http://localhost/mcp --mcp-dial localhost:7782 exec script.mdl` | SP must be open; bypasses BSON serialization bugs; use for rule 9 operations |
| Hand-rolled MCP | `pg_patch_page`, `ped_create_document` | Only when MDL has no syntax for the operation (widget JSON shapes — rules 6, 6b) |

**Companion skills:** `learned-mcp-patterns.md` (MCP alternatives), `bug-logs/mxcli-bugs.md` (bug detail), `iterative-build-loop.md` (exec discipline), `learned-microflow-patterns.md` (annotation + inline assoc rules)

---

## The checklist — run before writing a single line of MDL

| # | If your script will… | Then… | Root cause |
|---|---|---|---|
| 1 | Use `visible:` or `editable:` **conditional expressions** on containers **inside a `datagrid customContent` column** | **STOP → MCP** (`pg_patch_page`) | mxcli writes blank `AttributeIdentifier` → `StorageLoadException` on SP open. **BUG-18, still open on v0.13.0** (found 2026-07-03 after v0.13.0 release). |
| 1b | Use `visible:` or `editable:` conditional expressions on **regular widgets / dataview / page-level containers** | Safe on mxcli v0.13.0 — retested 2026-07-09 on WMS-LargeSource (Mendix 11.12.0), 0 mxbuild errors. Fixed by codec engine (#627). **Use mxcli.** | Was: STOP in pre-v0.13.0; no longer applies to regular widgets. |
| 2 | Call `alter settings configuration`, `alter settings model`, or `alter project security level` | **STOP → Studio Pro GUI only** | Deterministic BSON stream-desync on the Settings unit — confirmed corrupt on every retry (see BUG-LOCAL-05) |
| 3 | Drop an attribute that has security grants applied to it | **STOP → Studio Pro GUI** | mxcli removes the attribute but leaves dead UUID pointers in the entity access rules → `KeyNotFoundException` on load (BUG-01) |
| 4 | Bind a widget to `AutoChangedBy` or `AutoChangedDate` system attributes | **STOP → omit or MCP** | Produces CE1613 dangling reference — these attributes are not bindable via mxcli widget expressions |
| 5 | Pass scalar (non-entity) parameters from a page button to a microflow | **STOP → redesign** | Mendix platform constraint: page buttons can only pass entity objects to microflows, never individual String/Integer/Decimal values. Silently fails to bind (CE1571). The microflow must take the whole object. |
| 6 | Use a COMBOBOX widget in association mode | **STOP → MCP** (`pg_patch_page`) | mxcli rejects the `Entity` property required by SP (MDL-WIDGET01), SP requires it (CE0642) — no working mxcli path exists |
| 6b | Use `DatagridDropdownFilter` in association (ref) mode as a DataGrid2 filter | **STOP → MCP** (`pg_patch_page`) | Confirmed working JSON pattern exists — see `learned-mcp-patterns.md`. `refOptions` microflow must be no-param; use `DomainModels$IndirectEntityRef` for `refEntity`; use `Pages$MicroflowSource` (not `CustomWidgets$CustomWidgetMicroflowSource`) |
| 7 | Use a cross-module association traversal as a widget datasource (`$currentObject/OtherModule.Assoc`) in DataGrid/DataView/ListView | **STOP → MCP** (`pg_patch_page`) | mxcli writes null `DestinationEntityId` on the `EntityRefStep` → `StorageLoadException` on SP open. Same-module traversals are fine. |
| 8 | Create any association — same- or cross-module | **STOP → run `SHOW ASSOCIATIONS` first** | No `IF NOT EXISTS` support — re-running a CREATE silently duplicates the association; mxbuild then flags CE0065/CE0069. Only write `CREATE ASSOCIATION` for names that do not yet appear in `SHOW ASSOCIATIONS` output. |
| 9 | Set an association inline in a CHANGE or CREATE activity: `change $Obj (Module.AssocName = $Other)` or `create Entity (Module.AssocName = $Other)` | **Use `mxcli --mcp exec script.mdl`** (SP must be open). Retested 2026-07-09 on v0.13.0 — `ped_check_errors` 0 errors; BSON bug only affects disk write path. Hand-rolled MCP (`ped_update_document`) still works as fallback. | mxcli disk write path writes the association name as an `AttributeIdentifier` in CHANGE/CREATE BSON — SP rejects on load. `--mcp` path routes through SP's own engine, bypassing mxcli's serializer entirely. **Reading through an association (`$Obj/Module.Assoc/Target/Attr`) is safe on any path.** |
| 10 | Use `count($list)` inside a `declare` expression | Safe on mxcli v0.13.0 — retested 2026-07-09 on WMS-LargeSource (Mendix 11.12.0). Both `$x = count($list)` and `declare $x integer = count($list)` pass mxbuild with 0 errors. **Use mxcli.** | Was: STOP / CE0117 in pre-v0.13.0; no longer applies. |
| 11 | Filter an XPath with an association-traversal as the comparand: `[Assoc_X = $Ctx/Other.Assoc]` | **STOP → retrieve target first, then filter** | XPath constraint right-hand side must be a directly-bound variable, not an association path. Pattern: `retrieve $Target from ... where [...]; retrieve $Result from Module.Entity where [Module.Assoc_X = $Target]` |

**Default to mxcli for:** entities/attributes/enums, associations (after SHOW ASSOCIATIONS check), microflows (without inline assoc-sets), demo users, module roles/grants, navigation.

---

## MDL gotchas (quick reference — common traps)

These don't require a STOP, but will cause silent failures or check errors if missed:

- **Demo user passwords — never touch MxAdmin, never set passwords:** MxAdmin ships in every project with password `1`; do not wipe, reset, or re-create it. Demo users are created by name + role only — no password block. The user switches to a demo account inside the app from MxAdmin; no password is needed. Pattern: `create demo user "firstname.lastname" with roles "Module"."Role";` — nothing more.
- **`System.User` missing from user roles:** every user role must include `System.User` — without it, users cannot log in. mxbuild passes, SP loads clean, no CE errors — silent login failure only. Pattern: `create user role "MyRole" ("System"."User", "Module"."Role", ...)`. Applies to every user role, no exceptions.
- **Keyword collisions:** widget/element names must not match MDL/OQL reserved words (case-insensitive): `MIN`, `MAX`, `IN`, `OUT`, `COUNT`, `SUM`, `AVG`, `ROW`, `COLUMN`, etc. Use descriptive names or double-quote them.
- **`EXTENDS` placement:** goes **before** the opening paren: `CREATE PERSISTENT ENTITY Mod.Photo EXTENDS System.Image (...)` — not after.
- **No `CASE/WHEN`:** use nested `IF/ELSE`. No `TRY/CATCH`: use `ON ERROR { ... }`.
- **Enum in string context:** always `toString($Obj/EnumAttr)` — never use the enum attribute directly where a String is expected.
- **`$Obj/AttrName` not `$Obj/"AttrName"`:** quoting attribute names in path expressions passes `mxcli check` but produces CE0117 at mxbuild. Quotes are correct for identifiers in declarations; wrong for path traversal.
- **Cross-module association expression paths:** for navigation through a cross-module association to a nested attribute, the entity name must be included: `$Item/ModuleA.Item_Other/ModuleB.OtherEntity/Attr` not `$Item/ModuleA.Item_Other/Attr`. The short form silently compiles but SP rejects it (CE0117). A bare `= empty` check does NOT need the long form.
- **`mxcli check` does not catch corruption:** it validates MDL grammar only. Items 1–11 above are all semantically valid MDL that check passes — only mxbuild or SP open will reveal the damage. Always run the real mxbuild gate after exec (see `iterative-build-loop.md`).

---

## Final self-check (mandatory before reporting back)

After drafting a script, re-read it line by line against the table above — not just the mental pre-check you did before writing. Inline assoc-sets, conditional visibility inside datagrid customContent columns, and cross-module association traversals as widget datasources can creep in during drafting without intent. `mxcli check --references` will not catch them. This re-read is the actual corruption-prevention step.
