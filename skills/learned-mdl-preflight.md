# MDL Pre-flight Checklist — STOP conditions before writing any script
**Purpose:** Before drafting any MDL script, check every planned operation against this table. Each STOP row was born from a real MPR corruption or silent runtime failure — not theoretical concerns. Skipping this check has caused project-unloadable corruption every time.

**Source:** Generalized from a live Mendix 11.12.0 Beta project, 2026-07-06/07. Incident detail stays in that project's own `bug-logs/` — only the generalizable rule is here.

**Companion skills:** `learned-mcp-patterns.md` (MCP alternatives), `bug-logs/mxcli-bugs.md` (bug detail), `iterative-build-loop.md` (exec discipline), `learned-microflow-patterns.md` (annotation + inline assoc rules)

---

## The checklist — run before writing a single line of MDL

| # | If your script will… | Then… | Root cause |
|---|---|---|---|
| 1 | Use `visible:` or `editable:` **conditional expressions** on any widget | **STOP → MCP** (`pg_patch_page`) | mxcli writes an invalid BSON shape for the visibility expression → `StorageLoadException` on SP open |
| 2 | Call `alter settings configuration`, `alter settings model`, or `alter project security level` | **STOP → Studio Pro GUI only** | Deterministic BSON stream-desync on the Settings unit — confirmed corrupt on every retry (see BUG-LOCAL-05) |
| 3 | Drop an attribute that has security grants applied to it | **STOP → Studio Pro GUI** | mxcli removes the attribute but leaves dead UUID pointers in the entity access rules → `KeyNotFoundException` on load (BUG-01) |
| 4 | Bind a widget to `AutoChangedBy` or `AutoChangedDate` system attributes | **STOP → omit or MCP** | Produces CE1613 dangling reference — these attributes are not bindable via mxcli widget expressions |
| 5 | Pass scalar (non-entity) parameters from a page button to a microflow | **STOP → redesign** | Mendix platform constraint: page buttons can only pass entity objects to microflows, never individual String/Integer/Decimal values. Silently fails to bind (CE1571). The microflow must take the whole object. |
| 6 | Use a COMBOBOX widget in association mode | **STOP → MCP** (`pg_patch_page`) | mxcli rejects the `Entity` property required by SP (MDL-WIDGET01), SP requires it (CE0642) — no working mxcli path exists |
| 6b | Use `DatagridDropdownFilter` in association (ref) mode as a DataGrid2 filter | **STOP → MCP** (`pg_patch_page`) | Confirmed working JSON pattern exists — see `learned-mcp-patterns.md`. `refOptions` microflow must be no-param; use `DomainModels$IndirectEntityRef` for `refEntity`; use `Pages$MicroflowSource` (not `CustomWidgets$CustomWidgetMicroflowSource`) |
| 7 | Use a cross-module association traversal as a widget datasource (`$currentObject/OtherModule.Assoc`) in DataGrid/DataView/ListView | **STOP → MCP** (`pg_patch_page`) | mxcli writes null `DestinationEntityId` on the `EntityRefStep` → `StorageLoadException` on SP open. Same-module traversals are fine. |
| 8 | Create any association — same- or cross-module | **STOP → run `SHOW ASSOCIATIONS` first** | No `IF NOT EXISTS` support — re-running a CREATE silently duplicates the association; mxbuild then flags CE0065/CE0069. Only write `CREATE ASSOCIATION` for names that do not yet appear in `SHOW ASSOCIATIONS` output. |
| 9 | Set an association inline in a CHANGE or CREATE activity: `change $Obj (Module.AssocName = $Other)` or `create Entity (Module.AssocName = $Other)` | **STOP → MCP** (`ped_create_document`/`ped_update_document`) | mxcli writes the association name as an `AttributeIdentifier` in the CHANGE/CREATE BSON — Studio Pro rejects the model on load. **Reading through an association (`$Obj/Module.Assoc/Target/Attr`) is safe; setting one inline in change/create is not.** |
| 10 | Use `count($list)` inside a `declare` expression | **STOP → MCP** (`ped_create_document` with `AggregateListAction`) | mxcli writes a `CreateVariable` with a `count()` expression → CE0117 in SP. Correct pattern: retrieve list → AggregateListAction(Count) → use result integer variable |
| 11 | Filter an XPath with an association-traversal as the comparand: `[Assoc_X = $Ctx/Other.Assoc]` | **STOP → retrieve target first, then filter** | XPath constraint right-hand side must be a directly-bound variable, not an association path. Pattern: `retrieve $Target from ... where [...]; retrieve $Result from Module.Entity where [Module.Assoc_X = $Target]` |

**Default to mxcli for:** entities/attributes/enums, associations (after SHOW ASSOCIATIONS check), microflows (without inline assoc-sets), demo users, module roles/grants, navigation.

---

## MDL gotchas (quick reference — common traps)

These don't require a STOP, but will cause silent failures or check errors if missed:

- **Keyword collisions:** widget/element names must not match MDL/OQL reserved words (case-insensitive): `MIN`, `MAX`, `IN`, `OUT`, `COUNT`, `SUM`, `AVG`, `ROW`, `COLUMN`, etc. Use descriptive names or double-quote them.
- **`EXTENDS` placement:** goes **before** the opening paren: `CREATE PERSISTENT ENTITY Mod.Photo EXTENDS System.Image (...)` — not after.
- **No `CASE/WHEN`:** use nested `IF/ELSE`. No `TRY/CATCH`: use `ON ERROR { ... }`.
- **Enum in string context:** always `toString($Obj/EnumAttr)` — never use the enum attribute directly where a String is expected.
- **`$Obj/AttrName` not `$Obj/"AttrName"`:** quoting attribute names in path expressions passes `mxcli check` but produces CE0117 at mxbuild. Quotes are correct for identifiers in declarations; wrong for path traversal.
- **Cross-module association expression paths:** for navigation through a cross-module association to a nested attribute, the entity name must be included: `$Item/ModuleA.Item_Other/ModuleB.OtherEntity/Attr` not `$Item/ModuleA.Item_Other/Attr`. The short form silently compiles but SP rejects it (CE0117). A bare `= empty` check does NOT need the long form.
- **`mxcli check` does not catch corruption:** it validates MDL grammar only. Items 1–11 above are all semantically valid MDL that check passes — only mxbuild or SP open will reveal the damage. Always run the real mxbuild gate after exec (see `iterative-build-loop.md`).

---

## Final self-check (mandatory before reporting back)

After drafting a script, re-read it line by line against the table above — not just the mental pre-check you did before writing. Inline assoc-sets, count() in declare, and conditional visibility can creep in during drafting without intent. `mxcli check --references` will not catch them. This re-read is the actual corruption-prevention step.
