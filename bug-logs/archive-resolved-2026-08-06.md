# Archived mxcli Bug Entries — Resolved / Non-Defect / Doc-Gap

Entries moved out of `mxcli-bugs.md` on 2026-08-06. Each was categorized as **RESOLVED**,
**DOC-FEATURE**, or **NOT-MXCLI** in the "Full distinct-defect table" of
[`all-bugs-consolidated-2026-08-06.md`](all-bugs-consolidated-2026-08-06.md) — meaning it is no
longer a live/current defect: already fixed, not actually a defect, or a documentation-only gap.
This file preserves the original write-ups verbatim for historical reference. The master log
(`mxcli-bugs.md`) keeps a one-line stub at each entry's original heading so existing
cross-references still resolve to something.

18 entries archived: 14 RESOLVED, 3 DOC-FEATURE, 1 NOT-MXCLI.

---

## BUG-02: `create association` for cross-module associations corrupts the MPR (CRITICAL)

**Status: FIXED in mxcli v0.13.0** — `CREATE ASSOCIATION` for cross-module associations works correctly. Verified 2026-07-04 on a large-source WMS project (Mendix 11.12.0): 0 CE errors, project loads cleanly in mxbuild. **No Studio Pro handoff required.**

~~**Severity:** Critical — project becomes unopenable in Studio Pro and mxbuild~~  
~~**Reproducible:** Yes, consistently~~  
~~**Mendix version:** 11.10.0~~  
**mxcli version when fixed:** v0.13.0 (codec engine rewrite)

### Fix history
Fixed in the RnD mxcli changelog under: `CE1613 and Studio Pro crash from invalid CrossAssociation BSON (ParentConnection/ChildConnection fields) (#50)`. A follow-up fix landed in v0.9.0: `Cross-module associations preserved on CREATE object actions (#502)`.

### Original root cause (for reference only)
mxcli was embedding `DomainModels$EntityImpl` objects from other modules using internal UUIDs that Studio Pro's unit loader could not resolve, causing `KeyNotFoundException`. This is now handled correctly by the `CrossModuleAssociation` type in the association executor.

### Syntax (confirmed working)
```mdl
CREATE ASSOCIATION ModuleA."EntityA_EntityB"
  FROM ModuleA."EntityA" TO ModuleB."EntityB"
  TYPE Reference
  OWNER Default;
```

---

## BUG-03: MDL `retrieve ... where [AssocName = $Param]` XPath syntax not documented / not obvious

**Severity:** Low — developer friction  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No

### Issue
When writing XPath constraints in MDL `retrieve` statements, attribute names and association
names must be **unquoted**. Quoting them causes CE0161 or silent wrong-result errors.

**Wrong (causes error):**
```
retrieve $Obj from "Module"."Entity" where [Module.Assoc = $OtherObj]
-- attribute access: $Obj/"AttributeName"  ← wrong, causes CE errors
```

**Correct:**
```
retrieve $Obj from "Module"."Entity" where [Module.Assoc = $OtherObj]
-- attribute access: $Obj/AttributeName  ← correct (unquoted)
```

The MDL documentation and error messages do not make this distinction clear.
Generated code (e.g. from AI) tends to quote identifiers everywhere for safety,
which causes subtle bugs specifically in XPath and attribute access expressions.

---

## BUG-05: Parameter names in MDL must NOT include `$` in declaration

**Severity:** Medium — causes cryptic errors if not known  
**Reproducible:** Yes  
**Mendix version:** 11.10.0  
**mxcli version when found:** pre-v0.13.0 (exact unrecorded)  
**Retested on v0.13.0:** No — likely a grammar/parser rule, unlikely to change

### Issue
MDL parameter declarations use bare names, but references in the body use `$` prefix.
This is inconsistent with how variables are declared (`declare $Var`) and confusing
for developers familiar with other languages.

**Wrong:**
```
create microflow "Module"."MyFlow" ("$Name": String)
```

**Correct:**
```
create microflow "Module"."MyFlow" ("Name": String)
-- referenced in body as $Name
```

The error message when `$` is included in the parameter name is not clearly diagnostic.

---

### BUG-15b: ALL `retrieve ... where [...]` XPath constraints silently dropped in BSON

**Severity upgrade: Critical** — affects every `retrieve ... where [...]` written via mxcli. mxcli passes CE checks (0 errors) and `DESCRIBE MICROFLOW` shows the XPath text correctly, but Studio Pro shows the XPath constraint field **empty** on every retrieve activity. The XPath text is stored somewhere mxcli can read it, but NOT in the BSON slot that Studio Pro (and the Mendix runtime) uses as the actual filter.

**Effect:** all filtered retrieves execute as "From database, entity X, Range=First/All" with no XPath — returns an arbitrary record or full table scan. Functionally incorrect at runtime.

**Confirmed on:**
- `retrieve $ExistingOrderDetail from OrderRegistration.OrderDetail where [OrderDetail/CustomerCode = $ExistingCustomerCode]` (simple attribute XPath)
- `retrieve $Base from Customer_Common.OrderCustomerBase where [OrderRegistration.OrderDetail_OrderCustomerBase/.../CustomerCode = $ExistingCustomerCode]` (cross-module association XPath)

**Root cause confirmed (2026-05-26) via `mxcli bson dump` comparison:**

mxcli writes the BSON key as **`XPathConstraint`** (capital P), but Studio Pro writes and reads **`XpathConstraint`** (lowercase p). BSON field lookup is case-sensitive. The XPath value IS stored in the file — just under the wrong key name. Studio Pro cannot find it and renders the constraint field as empty. The runtime executes with no filter.

Evidence from BSON dump:
```
Working (GET_Sequence_NextId — written by Studio Pro):  "Key": "XpathConstraint"
Broken  (ACT_Order_ExpansionApply_* — written by mxcli): "Key": "XPathConstraint"
```

This explains why annotation text writes correctly (its field name is spelled correctly in mxcli's writer) but XPath does not. The fix in mxcli's source (`writer_microflows.go`) is to change `XPathConstraint` → `XpathConstraint`.

**Both simple and complex XPath constraints are dropped** — this is a systemic serialization failure, not specific to cross-module paths.

**Implication:** ALL microflows in this project built via mxcli with `retrieve ... where [...]` should be inspected in Studio Pro. The XPath constraint field will be empty even when the business logic requires filtering.

**STATUS: RESOLVED via binary patch (2026-05-26). Root cause fixed in mxcli v0.13.0** — the codec engine correctly serialises `XpathConstraint` (lowercase p). New projects on v0.13.0 do not need the binary patch. The patch script is preserved below for projects built on older mxcli versions.

**Fix applied:** Binary search-replace of all `XPathConstraint` (capital P) → `XpathConstraint` (lowercase p) bytes across all mxunit files in `mprcontents/`. The fix was applied with mxcli v0.12.0 installed but the bug was NOT fixed in v0.12.0 — the binary patch was applied manually.

**Result:** 265 mxunit files patched, 45,615 occurrences fixed. 0 CE errors after patch. All XPath constraints written by mxcli are now visible in Studio Pro.

**How the patch works:**
- The MPR SQLite file (`.mpr`) is only an index — the actual BSON data lives in the `mprcontents/*.mxunit` files
- `XPathConstraint` and `XpathConstraint` are the same byte length (15 chars) — safe binary replacement, no length prefix changes needed
- Studio Pro writes/reads `XpathConstraint`; after the patch mxcli-written files match

**If the bug reappears after a future mxcli update:** re-run this PowerShell to reapply the patch:
```powershell
cd <project-root>
$search  = [System.Text.Encoding]::ASCII.GetBytes("XPathConstraint")
$replace = [System.Text.Encoding]::ASCII.GetBytes("XpathConstraint")
$totalFiles = 0; $totalOccurrences = 0
Get-ChildItem mprcontents -Recurse -Filter "*.mxunit" | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $count = 0
    for ($i = 0; $i -le $bytes.Length - $search.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $search.Length; $j++) {
            if ($bytes[$i+$j] -ne $search[$j]) { $match = $false; break }
        }
        if ($match) {
            for ($j = 0; $j -lt $replace.Length; $j++) { $bytes[$i+$j] = $replace[$j] }
            $count++; $i += $search.Length - 1
        }
    }
    if ($count -gt 0) { [System.IO.File]::WriteAllBytes($_.FullName, $bytes); $totalFiles++; $totalOccurrences += $count }
}
Write-Host "Patched $totalFiles files, $totalOccurrences occurrences"
```

**Studio Pro action required after any mxcli exec that writes retrieves with XPath:** reload the project in Studio Pro (File → Recent Projects or close/reopen) so it picks up the updated mxunit files. Then open and verify the Constraint fields are populated.

---

## BUG-31: Void/boolean-returning JS actions in nanoflows write malformed BSON

**Status: RESOLVED 2026-08-03** — not reproducible on RnD `504aec67` or Engalar `26f2866`.
Safe to remove from the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-31.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153-161`

A JS action with a `void` or boolean return type, called from a nanoflow, produces BSON that
fails CE0008/CE0109 checks.

---

## BUG-36: Scalar parameter from page button to microflow silently fails to bind

**Status: RESOLVED (at check/exec layer) 2026-08-03** — passes on both RnD `504aec67` and
Engalar `26f2866` at the check/exec layer; the runtime layer was not independently retested
(no live app launch in this pass). Safe to downgrade; re-verify at runtime before fully
closing. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-36.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:154`

A non-entity (scalar) parameter passed from a page action button to a microflow silently
fails to bind — no error at `exec` or `check` time, only discoverable at runtime.

---

## BUG-40: `ALTER WORKFLOW INSERT` does not support USER TASK activities

**Status: RESOLVED 2026-08-03** — passes on both RnD `504aec67` and Engalar `26f2866`; stale.
Safe to remove from the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-40.md`.
**Reproducible:** Reported only
**Discovered:** a PLM parts-flow project, `mdlsource/3c-workflow/archived/09f-tfc-workflow-build.mdl` comment

Only `CALL MICROFLOW` activities can be inserted into a workflow via `ALTER WORKFLOW INSERT`;
USER TASK activities require Studio Pro.

---

## BUG-41: Pluggable DataGrid2 `textfilter.attributes:` binding accepted but not persisted → CE1613

**Status: RESOLVED (RnD) 2026-08-03** — passes on RnD `504aec67`; not directly comparable on
Engalar `26f2866` (divergent filter architecture). Safe to downgrade for RnD purposes.
Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-41.md`.
**Reproducible:** Reported only
**Discovered:** a PLM parts-flow project, `PROJECT.md:140,170`, `done-18-kt-filterbar-dg2.mdl`

Distinct from BUG-10 and BUG-23 (both about the `Attributes` list generally) — this is
specifically the pluggable-widget `textfilter.attributes` binding.

**Re-opened / refined 2026-08-13 on SonnyPOC** (mxcli v0.17.0, Mendix 11.13.0): reproduced the
same CE1613 on a single-attribute `textfilter (attributes: [...])`, ruling out "multi-attribute
list" as the actual trigger. Root cause is narrower: a **quoted** 3-part identifier
(`"Module"."Entity"."Attribute"`) inside a `textfilter.attributes:` list is accepted by
`mxcli check`/`describe page` round-trip but not persisted correctly (CE1613 on native
`mx check`); the **unquoted** dotted form (`Module.Entity.Attribute`, matching
`create-page.md`'s own documented example) persists correctly and checks clean. This directly
conflicts with the general "always quote identifiers, it's always safe" convention used
elsewhere — it is a confirmed exception specific to this one widget property. Not yet filed as
a GitHub issue; see SonnyPOC `docs/BUILD-LOG.md` 2026-08-13 entries and
`mdlsource/01-sharedplumbing/01c-fix2-filter-unquoted.mdl` / `01c-fix3-filter-unquoted2.mdl` for
the fix and verification detail.

---

## BUG-43: `ALTER SETTINGS CONSTANT` corrupts the Settings unit BSON

**Status: RESOLVED 2026-08-03** — passes on both RnD and Engalar; likely mis-attributed to
BUG-22's family originally. Safe to remove from the active list (note: this group's RnD-side
retest substituted the v0.16.0 release binary for a from-source build due to a sandbox
restriction — see `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-43.md` for detail).
**Reproducible:** Reported only
**Discovered:** a large-source WMS project, `handoff/scripts/phase-3-complex-logic/transportation/DONE-17-flip-stubs.mdl:19`

Same corruption family as BUG-22 (`ALTER SETTINGS CONFIGURATION`/`ALTER SETTINGS MODEL`/
`ALTER PROJECT SECURITY LEVEL`), but BUG-22 doesn't list `ALTER SETTINGS CONSTANT` — worth
folding in if confirmed to be the same code path.

---

## BUG-46: CE0066 — security-hash reconciliation failure after a GRANT/security exec

**Status: RESOLVED (RnD) / ENGALAR HAS WORSE BUG 2026-08-03** — passes on RnD `504aec67`.
Engalar `26f2866` doesn't hit this specific CE0066 but instead crashes with the broader
"multiple Security$ModuleSecurity units" defect on the same GRANT-execution path — see the
new consolidated Engalar entry below. Safe to remove from RnD's active list.
**Reproducible:** Reported only, seen independently in both a Java/Angular analysis project and a third, excluded project
**Discovered:** a Java/Angular analysis project, `mdlsource/02-inventory-security.mdl:9`, `architecture/build-plan.md:75,136`, `architecture/open-issues.md:13`

---

## BUG-48: Silent microflow-datasource drop on pluggable datagrids

**Status: RESOLVED 2026-08-03** — passes on both RnD `504aec67` and Engalar `26f2866`; this is
RnD's own historical fix (#795), already shipped and inherited by Engalar. Safe to remove from
the active list. (Note: a related but distinct new defect — parameter-binding loss on a
parameterized DG2 microflow datasource, not datasource-drop — was found adjacent to BUG-51;
see the new entry filed separately below.)
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/12-inventory-history-delete.mdl:6-7`

Workaround: use a `database` datasource via association XPath instead of a microflow
datasource on pluggable datagrids.

---

## BUG-49: `CREATE OR REPLACE PAGE` silently resets/drops existing view-access grants

**Status: RESOLVED 2026-08-03** — passes on both RnD `504aec67` and Engalar `26f2866`. Safe to
remove from the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-49.md`.
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/09-regrant-page-access.mdl:4-6` (references CE0557)

No error at write time; grants must be manually reapplied after any `CREATE OR REPLACE PAGE`.

---

## BUG-51: Quoting a reference-target identifier before a parenthesized param list breaks parsing

**Status: RESOLVED (as described) — NEW BUG FOUND ADJACENT 2026-08-03** — not reproducible as
originally described on RnD `504aec67` or Engalar `26f2866` across 3 tested contexts (show_page
action, microflow action, microflow datasource; quoted and unquoted). Safe to remove this
entry. However, retesting surfaced a genuine new defect: a DataGrid2 whose parameterized
`microflow` datasource silently drops the parameter binding (CE1571), reproducing regardless of
quoting — tracked as its own new issue, not a continuation of this one. Detail:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-51.md`; new draft issue:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/09-NEW-dg2-parameterized-datasource-ce1571.md`.
**Reproducible:** Reported only
**Discovered:** a Java/Angular analysis project, `mdlsource/05-inventory-pages.mdl:9-10`

`"Target"(Param: value)` fails to parse — reference targets must stay unquoted immediately
before a param list, even though attribute names should generally be quoted per this
project's convention.

---

## BUG-52: CHANGE-activity attribute quoting → `StorageLoadException` on Studio Pro open (passes mxbuild/check clean)

**Status: RESOLVED 2026-08-03** — passes on both RnD and Engalar; the original source lines no
longer exist to replay exactly, so treat as stale/unreproducible rather than definitively
fixed. Safe to remove from the active list. (Note: this group's RnD-side retest substituted
the v0.16.0 release binary due to a sandbox restriction — see
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-52.md`.)
**Reproducible:** Reported only
**Discovered:** a WMS reference app, `mdlsource/phase-4/fix-18-actualocation-bug.mdl:6`, `fix-14-trigger-state-change.mdl`

---

## BUG-53: `Visible:` expression on an action button inside a plain DataView corrupts BSON

**Status: RESOLVED (RnD) / ENGALAR HAS DIFFERENT BUG 2026-08-03** — passes on RnD `504aec67`,
which correctly qualifies the bare attribute reference as `$currentObject/Attr`. Engalar
`26f2866` writes it unqualified instead, causing a real CE0117 — report that to Engalar
directly as its own issue, distinct from this one. Safe to remove this entry for RnD.
**Severity:** blank `AttributeIdentifier` written → `StorageLoadException` on Studio Pro open
**Mendix version:** 11.12.0
**mxcli version:** v0.13.0
**Discovered:** 2026-07-16, a WMS reference app, `mdlsource/phase-4/SUPERSEDED-04-state-conditional-buttons.mdl`

Distinct from the already-logged datagrid-customContent `visible:` corruption (BUG-18) — this
one hits a plain DataView, not a grid.

---

## BUG-55: `ALTER PAGE ... DROP ... REPLACE ...` combined in one script → transient duplicate-name collision; and cross-module GRANT EXECUTE/page-view grants silently dropped

**Status: SPLIT AND RETESTED 2026-08-03** — the two findings below were retested separately as
BUG-55a and BUG-55b. **BUG-55a (DROP+REPLACE collision): RESOLVED**, passes on both RnD and
Engalar. **BUG-55b (cross-module GRANT EXECUTE silently no-ops): RESOLVED on RnD** (now
persists correctly); **Engalar instead crashes** on the "multiple Security$ModuleSecurity
units" defect — see the new consolidated Engalar entry below. Safe to remove this entry from
the active list. Detail: `a WMS demo project/bug-logs/mxcli-retest-2026-08-03/BUG-55a.md`,
`BUG-55b.md`.
**Reproducible:** Reported only
**Discovered:** a WMS reference app, `mdlsource/phase-4/DONE-06-mfc-dashboard-new-route-button.mdl` header; session memory `feedback_mdl_patterns.md:36-38`

Two related a WMS reference app findings grouped here:
- `ALTER PAGE` applies a `DROP` + `REPLACE` in one script atomically rather than
  sequentially, causing a transient duplicate-name collision. Workaround: use a full
  `CREATE OR REPLACE PAGE` instead of combining DROP+REPLACE.
- `GRANT EXECUTE ON MICROFLOW` and page-view GRANTs targeting a cross-module role report
  success but are never persisted — unlike entity-access grants, which throw a clear CE
  error for cross-module roles instead of silently no-op'ing.

---

## BUG-57: `assess-quality.md` prescribes `HTMLSanitize()`, a Community Commons function that does not exist

**Class:** documentation defect in an mxcli-bundled skill — **not** a runtime/corruption bug. Logged
here because the target is mxcli's own shipped content and the failure mode is an agent confidently
writing a call to a function that isn't there.

**Severity:** Medium. It sits in the *security* section, so the cost of following it is either a
CE error on a nonexistent Java action, or — worse — an agent that hits the error, can't find the
function, and quietly drops the sanitisation step rather than substituting the right one.

**Where:** `.ai-context/skills/assess-quality.md:167`

```
- Sanitize user input to prevent XSS (use `HTMLSanitize()` from Community Commons)
```

**Verified 2026-08-05** against this project's own vendored Community Commons
(`javasource/communitycommons/actions/`):

| Present | Absent |
|---|---|
| `EscapeHTML.java`, `HTMLEncode.java`, `HTMLToPlainText.java`, **`XSSSanitize.java`** | `HTMLSanitize` — `grep -rl 'HTMLSanitize' javasource/` returns **nothing** |

**Correct action: `XSSSanitize`.**

**Provenance:** surfaced by cross-reading an external Mendix coding-standards corpus (a customer's
internal conventions repo, 2026-08-05), whose security-conventions section names `XSSSanitize`
correctly. The external corpus is right and the bundled skill is wrong — worth noting as a case
where an outside body of standards corrected ours, which is the argument for cross-reading them.

**Cannot be fixed locally in a way that sticks.** `.ai-context/` is regenerated by mxcli upgrades,
so an edit there is silently reverted on the next upgrade — the same class of trap as
`agents/test-agent.md` citing `.ai-context/skills/test-app.md`. **Needs to go upstream**; candidate
for `bug-logs/pending-github-issues/`.

**Not yet checked:** whether the rest of `assess-quality.md`'s named Java actions and function
references resolve against a real Community Commons. One wrong name in a list this size warrants
sweeping the others rather than assuming this was the only one.

---

## BUG-SP01: one pluggable-widget warning with a non-code `code` field kills Studio Pro's entire Errors pane

**Severity:** High for diagnosis — SP shows **no** errors/warnings at all, so the modeller flies blind.
Not a model defect: the app is valid.
**Reproducible:** Yes, every open.
**Mendix version:** 11.13.0 Beta. **Not mxcli-related** — reproduces on a model mxcli never touched.
**Discovered:** 2026-08-05, TFC-TCXGraphPOC.

### Symptom

On opening the project, Studio Pro raises a modal:

```
Error
Application errors could not be retrieved.
Details: The string did not match the expected pattern.
```

The Errors pane then stays empty. Best Practice Recommender still populates normally, which makes it
look like a partial UI glitch rather than a parse failure.

### Root cause

`mx check <mpr> -w -j out.json` shows every warning carries a well-formed `code`
(`CW0114`, `CE0711`, …) — **except two, whose `code` is the literal string `Error`**:

```json
{ "code": "Error",
  "message": "A caption is required if 'Can hide' is Yes or Yes, hidden by default...",
  "locations": [{ "module-name": "TFC", "document-name": "Page 'TFC_NPDGate'",
                  "element-name": "Property 'Columns/7/Can hide' of data grid 2 'dgNPDGate'" }] }
```

The **DataGrid2 pluggable widget** emits its own validation messages without a Mendix `CE####`/
`CW####` code. Studio Pro parses that field against a pattern, throws
(`The string did not match the expected pattern` — the standard .NET format-parse message), and the
**whole list fails**, not just the offending row. 108 well-formed warnings are suppressed by 2 bad ones.

`mx check` tolerates it and reports `0 errors, 110 warnings` — so CLI gates stay green while the GUI
is blind. That divergence is the trap.

### Diagnosis recipe (generalizes to any "SP pane won't load" case)

```bash
mx check <app>.mpr -w -d -j /tmp/w.json
python3 -c "import json;[print(w) for w in json.load(open('/tmp/w.json'))['warnings']
            if not __import__('re').fullmatch(r'C[EW]\d+', w['code'])]"
```

Anything printed is a candidate. Do **not** start by suspecting the model — check whether the CLI
validator and the GUI disagree, then look for a malformed record.

### Workaround

Give the offending column a caption (or set *Can hide* = No) on **every** offending grid — fixing one
leaves the pane broken. In TFC both had to be addressed:
`TFC.TFC_NPDGate` → `dgNPDGate` (own code) and **`WorkflowCommons.WorkflowDefinition_View` →
`dataGrid26` (marketplace module)**. The second means editing vendor code — decide deliberately.

### Where to report

Two candidates, both worth filing: the **DataGrid2 widget** (emit a real code), and **Studio Pro**
(one malformed record should degrade that row, not the whole pane). Not an mxcli bug — logged here
because the CLI-vs-GUI divergence is what makes it expensive to diagnose.
