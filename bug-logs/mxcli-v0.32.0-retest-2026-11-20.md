# mxcli v0.32.0-374 retest of the ledger and the learned MDL rules — 2026-11-20

**Binary:** `mxcli version v0.32.0-374-g591bcd73e (2026-11-20)`, built from source.
**Gate:** real MxBuild `mx check` 11.8.0. Every probe ran on a fresh copy of a blank Mendix 11.8.0 app
holding the base model in Appendix A.
**Toolkit read:** commit `ee12a615` (2026-11-06); line numbers below are from that commit.
**Procedure:** `skills/retesting-learned-rules.md`. For each rule: `mxcli check -p <app> --references`
(rung 1), `mxcli exec` (rung 2), `describe` / BSON read-back (rung 3), real `mx check -j` (rung 4).
Every probe document has a unique name, so each `mx check` error is attributed to its probe by
document name. The probe MDL is in Appendix B, under the probe IDs the tables cite.

**Version guard:** `v0.32.0-374` is the build 374 commits after the v0.32.0 release (`mxcli version v0.32.0-374-g591bcd73e`); v0.32.0 itself and every earlier release count as older.

**Caveat:** the gate is **Mendix 11.8.0**; most rules were measured on 11.12–11.13. Where Mendix
itself raises the error (#29 constant, #30 dynamicimage) a non-reproduction may depend on the Mendix
version: those rows are marked "11.8 only" and were kept. Studio Pro's loader (rung 5) and the
runtime (rung 6) were not available, so a rule whose failure lives there was kept.

**What the toolkit did with it:** fixed and changed rules moved, word for word, to
`skills/learned-rules-archive.md` (still valid on an older mxcli); the live rows were rewritten to
the current behaviour; the ledger entries below carry a `Fixed in v0.32.0-374` / `Changed in` /
`Still reproduces on` stamp; BUG-17 is marked a misdiagnosis; six new candidates were added as
`BUG-DRAFT-*` entries (dated 2026-11-20). Three candidates of the run were already ledger entries
and got a stamp instead (rename module, `[Assoc = 'literal']` = BUG-78, constants printing secrets).

## Verdict key

| Verdict | Meaning |
|---|---|
| **STILL** | The repro still fails as the rule says, so the rule is still needed. |
| **FIXED** | The old failure is gone at every rung tested, so the workaround is not needed. |
| **CHANGED** | It fails differently than the rule says. In nearly every case `check`/`exec` now refuses it, where the rule says they pass, so the rule text is out of date. |
| **WORKAROUND-BROKEN** | The prescribed workaround now fails. |
| **NOT-TESTABLE** | Needs Studio Pro, the runtime or an MCP. |

## Most urgent: rule text that is now WRONG

1. **BUG-17 (`mxcli-bugs.md:554`) is a misdiagnosis. Its "Option C" workaround and its claims are wrong.**
   - `[%BeginOfToday%]` and `[%EndOfToday%]` are **not Mendix tokens**.
   - mxcli now says so at `check`: `✗ [%BeginOfToday%] is not a Mendix token (mxbuild: CE0161 …) [MDL-TOKEN01]`.
   - The real tokens `[%BeginOfCurrentDay%]` and `[%EndOfCurrentDay%]` in the same `retrieve … where` give `mx check` **0 errors** (`L17b`).
   - The entry's loop-filter and Java-action workarounds were never needed.
2. **Preflight STOP #12 (`learned-mdl-preflight.md:36`, 95 words) and STOP #1's ContentParams clause (`:33`) are out of date (CHANGED, not FIXED — see the correction below).**
   - The rule bans `toString(Attr)`, `$currentObject/Attr` and `if … then … else` in `ContentParams`.
   - **Corrected by the independent review (re-run 2026-11-20):** only the `$currentObject/` forms build (`PF12b/c`, and `toString($currentObject/Status)` in a data view and a customContent column: `mx check` 0 errors). `PF12a` and `PF12e` — `toString(Status)`, a bare attribute inside a function, in customContent and in the `[ … ]` list spelling — pass `check` and `exec` and fail `mx check` with CE0117 at `Expression of text template parameter {1}`. So the rule CHANGED, not FIXED: on v0.32.0-374 write every attribute in the expression as `$currentObject/Attr`.
   - `describe` stores each one as an expression.
   - The row now forbids working code and pushes agents to add String attributes they do not need. The same claim is in `learned-detection-gaps.md:51`.
3. **STOP #32 (`:50`) is over-broad.**
   - It forbids every widget `show page` argument outside a data view.
   - Passing the **page's own parameter** now builds clean (`PF32`): it is stored as `Forms$PageVariable PageParameter: "Order"`, and `mx check` reports 0 errors.
   - Only the `$currentObject` form is still refused (`PF32b`, MDL-PAGEARG01). The rule tells agents to add a microflow they do not need.
4. **The preflight "Still a STOP: workflow `DECISION`" line (`:9`, BUG-76/108) can be retired.**
   - mxcli now refuses short enum outcomes at `check` with the exact reason: `decision outcome 'Draft' is not fully qualified — Mendix cannot load a project whose EnumerationValueConditionOutcome.Value is not Module.Enumeration.Value`. It also refuses a missing empty outcome (MDL-WF06/CE6686).
   - The form it asks for builds at `mx check` 0 errors (`L76c`). The old StorageLoadException is gone. A boolean decision also builds clean (`L76b`).
   - BUG-141, the runtime `PersistentId` problem, is NOT-TESTABLE here.
5. **The `learned-microflow-patterns.md:264` header rule is wrong.** It says "The `check` errors point at `returns`/`List of`". There is now one precise error: `a microflow header needs its parameter list in parentheses, even when it is empty` (`MP01`).
6. **The DG2-column gotcha (`learned-mdl-preflight.md:62`) and `detection-gaps:44` are wrong about the failure mode.**
   - They say `REPLACE … column` passes `check` and fails mxbuild.
   - It is now **refused at `check`**, and so is `INSERT AFTER <column>`. The message is `the insertion point (`Qty`) is in no data container, so no entity is in scope` (`M04b/d/e`, `M11b/c`), even on a plain `database` grid.
   - The prescribed whole-page re-emit is still the right advice. This refusal looks like a new mxcli bug (see the candidates below).
7. **The BUG-04 guidance (`:50`) is stale.**
   - A new microflow now starts with **no** allowed roles: `No module roles granted execute access on NoRoles.MyFlow`.
   - A grant to a role that does not exist is refused cleanly at `check`: `module role NoRoles.User does not exist`.

## Results table

"Words" counts the always-loaded or preloaded text the rule costs, on its line in the skill file. Each preflight and microflow-patterns row is also copied verbatim into one `skills/generated/rules-<kind>.md`, which the mdl helper preloads. Ledger entries are on-demand (`bug-lookup.sh`), so they cost **0** baseline words.

### `skills/learned-mdl-preflight.md` (baseline for lead/ba/architect, on-demand for mdl; rows copied into `generated/rules-*.md`)

| id | file:line | verdict | probe | words |
|---|---|---|---|---|
| STOP #1: visible expr in DG2 customContent | :33 | **FIXED** at rungs 1–4. BSON `ConditionalVisibilitySettings.Attribute:""` with the expression stored; `mx check` 0 errors. The original BUG-18 symptom was a StorageLoadException *at mx check*, and that is gone. The SP loader is untested. The ContentParams clause in the row is FIXED (see #12). | PF01 (+bson.json), BUG18b | 69 |
| STOP #1b: Editable quoted | :34 | **STILL accurate.** It is version-guarded: on v0.32 the quoted form is stored as an expression, as the row says for ≥v0.28. | PF01b | 71 |
| STOP #4: bind AutoChangedBy | :35 | **STILL.** `CE1613 "The selected attribute 'Shop.Audited.changedBy' no longer exists."`, and `check` passes. | PF04 | 38 |
| STOP #12: ContentParams expressions | :36 | **CHANGED** (corrected on review). `$currentObject/Attr` expressions build (PF12b/c); a bare attribute inside a function, `toString(Status)`, still gives CE0117 (PF12a, PF12e). | PF12a–e | 95 |
| STOP #14: narrowing grant merges | :37 | **STILL.** exec prints `Unchanged entity access: Shop.Secret (Shop.User)`, and the rule keeps `Name, Note: ReadWrite`. There is now at least a visible signal. | PF14a/b | 51 |
| STOP #16: path inside `[%CurrentUser/…%]` | :39 | **CHANGED.** It is now refused at `check`/`exec`: `[%CurrentUser/Administration.Account_Language%] is not a Mendix token (mxbuild: CE0161) [MDL-TOKEN01]`. The prescribed bare-token fix passes. | PF16, PF16b | 121 |
| STOP #18: callee in same script as workflow | :38 | **CHANGED/FIXED.** exec auto-fills `(Order = $WorkflowContext)` and `mx check` reports **0 errors**, not CE0117. If the callee already exists, `check` now *demands* the mapping (`parameter 'Order' is not mapped`). | PF18, L76c | 73 |
| STOP #21: whole-document restatement | :40 | **STILL**, by design. `alter navigation` exists (the parser expects `DROP/MOVE/SET/INSERT/REPLACE`). | M03 | 148 |
| STOP #22: non-idempotent re-run | :41 | **STILL.** Second run: `Error: attribute 'PF22Extra' already exists on entity Shop.Line`, exit 1, and `check` passes it. | PF22-rerun2 | 119 |
| STOP #23: `create or modify` drops members | :42 | **CHANGED.** `check` now warns before exec: `removes 2 member(s) … [MDL087]`. exec warns and writes. The `diff` false `- Attribute` lines (BUG-146) did not reproduce. | PF23, L146-diff | 148 |
| STOP #24: design property not in theme | :43 | **CHANGED.** It is now a `check` **error** and exec refuses: `sets design property "Form orientation", which is not defined … CE6083 [MDL-WIDGET11]`. The row says "check only warns, exec writes". | PF24 | 143 |
| STOP #26: quoted DG2 association path | :45 | **STILL.** `CE1613 … 'Shop.Line."Line_Order/Name"' no longer exists`, and `check` passes. The unquoted fix gives 0 errors. | PF26, PF26b | 62 |
| STOP #29: constant in nanoflow | :47 | **Not reproduced (11.8 only).** `ExposedToClient: false`, `mx check` 0 errors. | PF29 | 26 |
| STOP #30: dynamicimage on React page | :48 | **Not reproduced (11.8 only).** `OptimizedClient: 'Yes'`, `mx check` 0 errors (no CE0582). | PF30 | 29 |
| STOP #31: data-view binding across 2 associations | :49 | **FIXED.** `check` warns MDL-ATTRPATH01 and stores `Shop.Line_Order/Shop.Order_Customer/Name`; `mx check` 0 errors. | PF31 | 37 |
| STOP #32: show page arg outside data view | :50 | **CHANGED.** The page-param form builds clean; only `$currentObject` is refused. | PF32 (+bson), PF32b | 38 |
| STOP #33: return-type change, mxcli caller | :51 | **Consistent** ("mxcli-written: none"). The Studio Pro-authored caller case is NOT-TESTABLE. | PF33a/b | 58 |
| Line 9: workflow DECISION STOP | :9 | **FIXED.** Retire it (top 4). | L76, L76b, L76c | 27 |
| Step 0: association FROM/TO flip is a no-op | :17 | **STILL.** `Modified association: Shop.LOA_LOB`, then describe shows `from Shop.LOA to Shop.LOB`. `owner Both` now persists (`describe`: `owner Both;`). | LD-flip-direction, LD-owner-ignored-b | 154 |
| Gotcha: cross-module short association path | :61 | **CHANGED.** It is now refused at `check`/`exec`: `Order_Customer is an association: an expression names it qualified … CE0117`. | G01, G01b, G01c | 39 |
| Gotcha: DG2 column change | :62 | **CHANGED.** Refused at `check` (top 6). | M04b, M11b/c | 28 |
| Gotcha: enum reserved value names | :63 | **FIXED.** `alter enumeration Shop.G03_Enum modify value Receive caption 'Receive goods'` gives `Altered enumeration` and describe shows the new caption. | G03 | 73 |
| Gotcha: elseif in page expression | :66 | **CHANGED.** It is now a parse error at `check`: `line 5:93 missing ELSE at 'elseif'`. | G04 | 56 |
| Gotcha: v0.25 dialect, never add `mdl 1;` | :68 | **STILL works.** Without a header the skills' spellings still parse (as mdl 0) with deprecation warnings. Under `mdl 1;`, `limit 1` is a list, and that is now **caught at `check`** (`$O was retrieved as a list …`). The row's "check still passes" is wrong. | M01, M02 | 171 |
| Gotcha: exec is not check | :69 | **STILL.** The E004 enum concatenation is flagged by `check` (exit 1), but exec exits 0 and `mx check` gives CE0117. Same for MP09 and LD-looptype. | G05, MP09, LD-looptype | 58 |

### `skills/learned-microflow-patterns.md` (preloaded for microflow scripts via `rules-microflow.md`)

| id | file:line | verdict | probe | words |
|---|---|---|---|---|
| `[%CurrentUser%]` as a String expression | :49 | **STILL** for the unquoted token (`CE0117`, `check` passes). Quoted `'[%CurrentUser%]'` is a literal and builds clean. | MP02b, MP02 | 40 |
| NPE retrieve gives CE0056 | :152 | **STILL**, `check` passes. | MP03 | 63 |
| Module-prefix every association step | :180 | **CHANGED.** Refused at `check` now (not "passes check and exec"). | G01c | 57 |
| Set association from the non-owner side gives CE0854 (same and cross module) | :186, :265 | **STILL.** Both CE0854, `check` passes. | MP04, MP04b | 65+38 |
| Trailing `@annotation` is a parse error | :223 | **STILL** (`missing END at '@'`). A bound annotation persists. | MP05, MP05b | 57 |
| Header needs `()` | :264 | **CHANGED.** The error text is wrong (top 5). | MP01 | 28 |
| validation feedback with no attribute gives CE0091 | :266 | **STILL**, `check` passes. | MP06 | 52 |
| Bare role in GRANT gives MDL-GRANT02 | :368 | **STILL** (`check` refuses). | MP07 | 17 |
| `currentDateTime()` is rejected | :374 | **STILL** (MDL044). In a nanoflow it is now refused too, so BUG-86 is FIXED. | MP08, L86 | 10 |
| Enum in String context | :378 | **CHANGED.** `check` now flags the `change`/`return` forms ("Attribute Note … is a String, but the value assigned to it is an Enumeration"). exec still writes, then CE0117 at `mx check`. | MP09 | 58 |
| Custom error handling in a loop gives CE0644 | :397 | **STILL** (MDL006 warning, CE0644). | MP10 | 14 |
| `delete $X refresh;` is legal | :107 | **Confirmed.** | MP13 | – |

### `skills/learned-detection-gaps.md` register (baseline: gate, review; preloaded via mdl-rules)

| id | line | verdict | probe | words |
|---|---|---|---|---|
| CREATE result discarded gives CE6005 | :33 | **FIXED.** exec auto-names it `$NewOrder`; `mx check` 0 errors. | MP11 | 54 |
| elseif in page expression | :37 | **CHANGED** (check parse error). | G04 | 49 |
| quoted association path / `$Obj/"Attr"` | :38 | **Split.** The DG2 column form is still CE1613. `$Order/"Name"` in change and call args builds at 0 errors (BUG-75/77 FIXED). | PF26, L77 | 77 |
| `calculated by` dropped | :39 | **FIXED.** describe shows `calculated by Shop.L98_Calc`, `show callers` lists the entity, and `mx check` reports 0 errors. Runtime is untested. | L98c | 66 |
| PARALLEL SPLIT terminator | :40 | **FIXED** statically. The unit has 4 `EndOfParallelSplitPath` markers. Runtime is NOT-TESTABLE. | L121 | 115 |
| Workflow branch point PersistentId | :41 | NOT-TESTABLE (needs a restart of a running app). | – | 171 |
| DG2 column REPLACE | :44 | **CHANGED** (refused at `check`). | M04b, M11b | 80 |
| `if` without `else` in an `on error` handler | :45 | **FIXED**, as the row says for ≥v0.29 (0 errors). | MP14 | 58 |
| Reserved names `Case`/`Context`/`New` | :46-47 | **Split.** `Context` and `New` are now refused at `check` (MDL021/MDL010). `Case` as an entity name still passes `check` and gives `mx check` `CE7247 The name 'Case' is a reserved word` (still a gap). | MP15, MP15b | 76+39 |
| ContentParams expression | :51 | **CHANGED** (see #12): the bare-attribute-in-function case is still a gap. | PF12* | 71 |
| `get workflows for` an entity no workflow uses gives CE1870 | :52 | **STILL**, `check` passes. | MP16 | 41 |
| XPath `= null` | :54 | **CHANGED.** Refused at `check`: `the constraint names "null" … CE0161`. | MP12 | 99 |

### `bug-logs/mxcli-bugs.md` (on-demand: 0 baseline words; the ledger is 67,914 words in total)

| id | line | verdict | probe |
|---|---|---|---|
| BUG-04 grant to a missing role | 50 | **CHANGED** (top 7) | L04a/b |
| BUG-07 SET content on dynamictext with ContentParams | 133 | **FIXED.** Content is set. The stale `ContentParams ({1} = Name)` is kept, which is harmless. | L07b |
| BUG-08 REPLACE with the same name, and child-name reuse | 166 | **FIXED** (both `Altered page`, re-runnable) | L08, L08b |
| BUG-10 filter attribute short names | 271 | **FIXED** (`textfilter tf1 (Attributes: [Name])` persists, 0 errors) | M04a |
| BUG-11 SET DataSource = association | 313 | **STILL** as narrowed. Refused with a pointer to `replace`. | L11b |
| BUG-14 DROP + INSERT BEFORE with a microflow action | 415 | **FIXED** (0 errors, no crash) | L14 |
| BUG-16/18 DG2 customContent and visible container | 485/637 | **FIXED** at rung 4 | PF01 |
| BUG-17 BeginOfToday | 554 | **WRONG diagnosis** (top 1) | L17, L17b |
| BUG-19 REPLACE wrapping a widget in a container | 709 | **FIXED** | L19 |
| Status reserved in `where` | 1300 | **FIXED / not reproduced** (0 errors) | L1300 |
| BUG-37 combobox in association mode | 1538 | **FIXED** (`attribute: Assoc` + `datasource:`, 0 errors). Enumeration-mode syntax on an association is refused with guidance. | L37 |
| BUG-67 snippet primitive parameter | 2288 | **CHANGED.** Refused at `check` with the real Mendix reason (CE0046). It is not an mxcli bug. | L67 |
| BUG-68 snippet DG2 on a system attribute | 2350 | **FIXED** | M05 |
| BUG-73 `raise error` in the main flow | 2528 | **CHANGED.** Refused at `check` with the CE0710 explanation. | L73 |
| BUG-76/108 workflow DECISION | 2721/3746 | **FIXED** (top 4) | L76* |
| BUG-75/77 quoted attribute segment | 2600/2864 | **FIXED** (0 errors) | L77 |
| BUG-78 `[Assoc = 'literal']` | 2878 | **STILL** (CE0161). `check` does not catch it. | L78 |
| BUG-82 clear a not-null rule | 2923 | **FIXED** (describe shows no rule, 0 errors) | L82b |
| BUG-84 SET DataSource = DATABASE on a data view | 2956 | **FIXED.** Now an explicit refusal (`a data view cannot take a database datasource`), not a silent wipe. | L84 |
| BUG-86 MDL044 nanoflow barrier | 2990 | **FIXED** | L86 |
| BUG-92 trap 1, wrong anchor | 3108 | **FIXED** (`widget "btnDoesNotExist" not found`, nothing written) | L92 |
| BUG-94 role-scoped Visible | 3250 | **FIXED** (`Visible: roles (Shop.Admin)` persists, 0 errors) | L94 |
| BUG-96 cross-module INSERT into DG2 | 3388 | **CHANGED.** Every DG2 column INSERT is refused (new bug below). | M04e |
| BUG-98 calculated by | 3452 | **FIXED** | L98c |
| BUG-103 log quotes round trip | 3621 | **FIXED** (describe output re-checks clean). Note that the read-back prints `log node …` without a level. | L103 |
| BUG-104 `"$Stub"` parameter | 3625 | **CHANGED.** Refused at `check` (MDL098 undefined `$Stub`). | L104 |
| BUG-107 unquoted WITH segfault | 3687 | **FIXED** (a parse error, no panic) | L107 |
| BUG-109 JUMP TO in a boundary event | 3797 | **FIXED** (0 errors, no CE6680) | L109 |
| BUG-110 describe workflow XPath round trip | 3854 | **FIXED** | L110 (+roundtrip.mdl) |
| BUG-111 `mxcli syntax` drill-down | 3899 | **FIXED** (all three topics exit 0) | L111-syntax |
| BUG-117 unknown property silently dropped | 4381 | **FIXED** (MDL-WIDGET52 error, exec refuses) | L117 |
| BUG-119 show message | 4612 | **FIXED** (0 errors) | L119 |
| BUG-121 parallel split terminator | 5016 | **FIXED** statically | L121 |
| BUG-122 SET PageSize on DG2 | 5144 | **FIXED** (`set (PageSize: 50)` gives `Altered page`) | M04c |
| BUG-123 SHOW CALLERS of a page button | 5183 | **FIXED** (`Shop.M06_Page` listed) | M06 |
| BUG-125 enum in an attribute declaration | 5222 | **FIXED** | L125 |
| BUG-126 SET Label discarded | 5228 | **FIXED** (`Label: 'Order name'` read back) | L126 |
| BUG-128 CREATE MODULE ROLE not idempotent | 5396 | **STILL** for plain `create` (`module role already exists`, exit 1). `create or modify module role` is idempotent. | L128b/c |
| BUG-140 parameterized microflow datasource on a top-level data view | 5267 | **FIXED** (describe shows `microflow Shop.DS_OrderOfLine(Line = $Line)`, 0 errors) | L140 |
| BUG-142 ContentParams | 5699 | **CHANGED**: `$currentObject/` forms build, `toString(Status)` still CE0117 | PF12* |
| BUG-144 user role without CheckSecurity | 5755 | **FIXED** (`CheckSecurity: true`) | L144 |
| BUG-145 narrowing grant | 5784 | **STILL** | PF14 |
| BUG-146 diff false `- Attribute` | 5806 | **Not reproduced** | L146-diff |
| BUG-147 forward call in the same script | 5836 | **FIXED** (both created, 0 errors) | L147 |
| BUG-148 quoted enum literal last gives E007 | 5864 | **FIXED** | L148 |
| BUG-151 rest call body `$Var` | 5954 | **FIXED** statically (`Body: template '{1}' with ({1} = $Body)`). Runtime is untested. | L151 |
| BUG-154 `if exists` drops | 6034 | **FIXED** for microflow, page, entity and association | M08 |
| BUG-155 SET RenderMode on dynamictext | 6054 | **FIXED** (`RenderMode: H2` read back) | L155 |
| DRAFT loop-var typecheck | 6104 | **FIXED** at `check`. exec still writes it, and `mx check` gives CE0117. | LD-looptype |
| DRAFT `COUNT(FILTER())` | 6162 | **FIXED** (refused under mdl 1) | LD-countfilter |
| DRAFT partial revoke association no-op | 6423 | **FIXED** (`Shop.Line_Order: ReadOnly` after revoking write) | LD-revoke-assoc2 |
| DRAFT XPath system member case | 6461 | **FIXED** (refused at `check`) | LD-xpathcase |
| DRAFT association owner ignored | 6488 | **FIXED** (`owner Both` persists). The FROM/TO flip is still a no-op (Step 0). | LD-owner-ignored-b |
| DRAFT rename module leaves XPath | 6547 | **STILL.** `Renamed module: RenMe → Renamed`, then `CE1613 The selected association 'RenMe.Thing_Other' no longer exists` and `entity 'RenMe.Other' no longer exists`. `check` passes. | M09, M09b |
| DRAFT rename page renames folder | 6583 | **FIXED** (`Renamed page: Shop.Twin → Shop.TwinRenamed`) | M10b |
| DRAFT dg2 association path quoted | 6624 | **STILL** (= STOP #26) | PF26 |
| DRAFT index on createdDate | 6912 | **FIXED** (0 errors) | LD-index-createddate |
| DRAFT microflow header grammar | 7036 | **FIXED** | MP01 |
| DRAFT describe/show constants print secrets | 7183 | **STILL** (`DefaultValue: 'hunter2-demo'` in both) | M07 |

**Not probed, out of budget:**

- **NOT-TESTABLE:**
  - Needs Studio Pro: the SP01 and Git-crash entries.
  - Needs runtime or restart: BUG-99, 113, 141, 153, 157, Business-Events.
  - Needs MCP: BUG-26, 32, 34, 54, 72, 88.
  - Needs marketplace or docker: themesource, #879, BUG-100, 132.
  - Needs deploy/PAT: BUG-116.
- **Toolkit-side, not mxcli:** BUG-63, 65, 130, 131, the module-close entries.
- **Not reached in this run:** BUG-06, 09, 50, 62, 70, 87, 89, 93, 105, 106, 114/118, 115, 120, 127, 129, 133, 143, 149, 150, 152, 156, WF01/WF05, and most DRAFT entries after 6624.

## Totals (108 table rows: 25 preflight, 12 microflow-patterns, 12 detection-gaps, 59 ledger)

| Verdict | Rows |
|---|---|
| FIXED: old failure gone through rung 4. 3 of these are static only, because the runtime is untested (BUG-121, BUG-151, calculated by) | 52 (55 before the review moved 3 PF12 rows to CHANGED) |
| CHANGED: now refused at `check`/exec, or fails differently, so the rule text is stale | 22 |
| STILL-REPRODUCES / rule still needed: 22 reproduce, 3 version-guarded rules still accurate | 25 |
| Not reproduced: #29 and #30 on Mendix 11.8 only, BUG-146 | 3 |
| WRONG diagnosis: BUG-17 | 1 |
| Split: half fixed, half still | 2 |
| Consistent/confirmed: no defect claimed | 2 |
| NOT-TESTABLE: workflow PersistentId across a restart | 1 |
| WORKAROUND-BROKEN | 0. Every prescribed workaround tested builds clean: PF12d, PF16b, PF26b, G01b, MP04c, MP05b, `create or modify module role` |

About 45 more ledger entries were not probed (list above).


## Appendix A — base model (applied once to the blank app before any probe)

```mdl
mdl 1;
create module Shop;
create module ModB;

create module role Shop.User;
create module role Shop.Admin;
create module role ModB.User;

create enumeration Shop.OrderStatus (
  Draft 'Draft',
  Closed 'Closed'
);

create persistent entity Shop.Order (
  Name: string(100),
  Note: string(200),
  Status: enum Shop.OrderStatus,
  Total: decimal,
  DueDate: datetime
);

create persistent entity Shop.Line (
  Name: string(100),
  Qty: integer
);

create non-persistent entity Shop.OrderDto (
  Name: string(100)
);

create association Shop.Line_Order
from Shop.Line to Shop.Order
type reference
owner default;

create persistent entity ModB.Customer (
  Name: string(100)
);

create association Shop.Order_Customer
from Shop.Order to ModB.Customer
type reference
owner default;

create page Shop.Order_Edit
(
  title: 'Edit order',
  layout: Atlas_Core.Atlas_Default,
  params: ( $Order: Shop.Order )
)
{
  dataview dv1 (datasource: $Order) {
    textbox tbName (label: 'Name', attribute: Name)
    footer {
      actionbutton btnSave (caption: 'Save', action: save changes, buttonstyle: primary)
    }
  }
};
```

## Appendix B — the probes

Each probe ran as `check`, then `exec`, then the read-back commands listed under it, then `mx check`. Line 2 of each probe quotes the rule it tests.

### BUG18b-snippet-visible-nocontext

```mdl
mdl 1;
-- BUG-18b: snippet with no params, container visible: $currentObject/Attr
create snippet Shop.BUG18b_Snip {
  container ctn (visible: $currentObject/Name = 'x') {
    dynamictext t1 (content: 'hi')
  }
};
```

### G01-crossmod-short-path

```mdl
mdl 1;
-- Gotcha "Cross-module association paths need the module prefix on every step" + learned-microflow-patterns "Module-Prefix Every Step"
create microflow Shop.G01_Short ($Order: Shop.Order) returns string as $s
begin
  declare $s string = $Order/Order_Customer/Name;
  return $s;
end;
```

### G01b-crossmod-full-path

```mdl
mdl 1;
-- control: fully prefixed path
create microflow Shop.G01b_Full ($Order: Shop.Order) returns string as $s
begin
  declare $s string = $Order/Shop.Order_Customer/ModB.Customer/Name;
  return $s;
end;
```

### G01c-samemod-short-path

```mdl
mdl 1;
-- learned-microflow-patterns:180 same-module unprefixed path $Line/Line_Order/Name -> CE0117
create microflow Shop.G01c_Same ($Line: Shop.Line) returns string as $s
begin
  declare $s string = $Line/Line_Order/Name;
  return $s;
end;
```

### G03-enum-reserved-modify

```mdl
mdl 1;
-- Gotcha: alter enumeration modify value on reserved-word value names -> parse error
create enumeration Shop.G03_Enum ( Receive 'Receive', Other 'Other' );
alter enumeration Shop.G03_Enum modify value Receive caption 'Receive goods';
```

### G04-elseif-page-expr

```mdl
mdl 1;
-- Gotcha: elseif in a page expression -> CE0117
create page Shop.G04_Page (title: 'G04', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    container c1 (dynamicclasses: if $currentObject/Status = Shop.OrderStatus.Draft then 'a' elseif $currentObject/Status = Shop.OrderStatus.Closed then 'b' else 'c') {
      dynamictext t (content: 'x')
    }
  }
};
```

### G05-exec-not-check-enumconcat

```mdl
mdl 1;
-- Gotcha "exec is not check": enum concatenation E004 flagged by check, written by exec
create microflow Shop.G05_Concat ($Order: Shop.Order) returns string as $s
begin
  declare $s string = 'S: ' + $Order/Status;
  return $s;
end;
```

### L04a-grant-no-role

```mdl
mdl 1;
-- BUG-04: grant execute to a role in a module with no roles; v0.27 claim: new docs start with no allowed roles
create module NoRoles;
create microflow NoRoles.MyFlow () begin end;
```

Read-back: `show access on microflow NoRoles.MyFlow`

### L04b-grant-no-role

```mdl
mdl 1;
grant execute on microflow NoRoles.MyFlow to NoRoles.User;
```

### L07a-setup

```mdl
mdl 1;
create microflow Shop.L_Act ($Order: Shop.Order) begin end;
create page Shop.L07_Page (title: 'L07', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    dynamictext txtA (content: '{1}', contentparams: ({1} = Name))
    dynamictext txtB (content: 'plain')
    actionbutton btnOne (caption: 'One', action: call microflow Shop.L_Act(Order = $currentObject))
    actionbutton btnTwo (caption: 'Two', action: call microflow Shop.L_Act(Order = $currentObject))
    container ctnOuter {
      dynamictext txtChild (content: 'child')
    }
    textbox tbName (label: 'Name', attribute: Name)
  }
};
```

### L07b-set-content-dyn

```mdl
mdl 1;
-- BUG-07: ALTER PAGE SET content on dynamictext with ContentParams
alter page Shop.L07_Page { set content = 'New Text' on txtA };
```

Read-back: `describe page Shop.L07_Page`

### L08-replace-same-name

```mdl
mdl 1;
-- BUG-08: REPLACE widget WITH same-named widget -> duplicate name
alter page Shop.L07_Page { replace txtB with { dynamictext txtB (content: 'Replaced') } };
```

### L08b-replace-child-name

```mdl
mdl 1;
-- BUG-08 v0.24 widening: replacement reuses a CHILD name of the replaced widget
alter page Shop.L07_Page { replace ctnOuter with { container ctnOuter2 { dynamictext txtChild (content: 'child v2') } } };
```

Read-back: `describe page Shop.L07_Page`

### L103-log-quotes

```mdl
mdl 1;
-- BUG-103: describe microflow emits log strings with doubled quotes that check then rejects
create microflow Shop.L103_Log () begin log info node 'N' 'It''s here'; end;
```

Read-back: `describe microflow Shop.L103_Log`

### L104-quoted-dollar-param

```mdl
mdl 1;
-- BUG-104: quoting a microflow parameter as "$Name" keeps the $ in the name
create microflow Shop.L104_P ("$Stub": Shop.Order) returns string as $s begin declare $s string = $Stub/Name; return $s; end;
```

Read-back: `describe microflow Shop.L104_P`

### L107-wf-unquoted-with

```mdl
-- BUG-107: unquoted value in workflow CALL MICROFLOW WITH segfaults (mdl 0 spelling, as reported)
CREATE MICROFLOW Shop.L107_Noop ($Ctx: Shop.Order) BEGIN END;
CREATE WORKFLOW Shop.L107_WF PARAMETER $Context: Shop.Order
BEGIN
  CALL MICROFLOW Shop.L107_Noop WITH (Ctx = $WorkflowContext);
END WORKFLOW;
```

### L109-jump-in-boundary

```mdl
mdl 1;
-- BUG-109: JUMP TO inside a boundary-event body writes a Jump with no Target
create page Shop.L109_Task (title: 'T', layout: Atlas_Core.Atlas_Default, params: ( $WorkflowUserTask: System.WorkflowUserTask )) { dynamictext t (content: 'x') };
create workflow Shop.L109_WF
  parameter $WorkflowContext: Shop.Order
begin
  user task A 'A' page Shop.L109_Task outcomes 'Done' { }
    boundary event interrupting timer 'addDays([%CurrentDateTime%], 3)' { jump to A; };
end workflow;
```

### L110-describe-wf-xpath

```mdl
mdl 1;
-- BUG-110: DESCRIBE WORKFLOW emits MDL it cannot re-parse when a targeting XPath contains quotes
create page Shop.L110_Task (title: 'T', layout: Atlas_Core.Atlas_Default, params: ( $WorkflowUserTask: System.WorkflowUserTask )) { dynamictext t (content: 'x') };
create workflow Shop.L110_WF
  parameter $WorkflowContext: Shop.Order
begin
  user task A 'A' page Shop.L110_Task targeting users xpath [Name = 'admin'] outcomes 'Done' { };
end workflow;
```

Read-back: `describe workflow Shop.L110_WF`

### L117-unknown-prop

```mdl
mdl 1;
-- BUG-117: unsupported property name silently dropped, no MDL-WIDGET07
create page Shop.L117_Page (title: 'L117', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    textbox tb1 (label: 'N', attribute: Name, Frobnicate: 'yes')
  }
};
```

### L119-show-message

```mdl
mdl 1;
-- BUG-119: show message grammar
create microflow Shop.L119_SM () begin show message 'Hello' type information; end;
```

### L11a-setup

```mdl
mdl 1;
create microflow Shop.DS_Order () returns Shop.Order as $O begin $O = create Shop.Order (Name = 'x'); return $O; end;
create page Shop.L11_Page (title: 'L11', layout: Atlas_Core.Atlas_Default, params: ( $Line: Shop.Line )) {
  dataview dvLine (datasource: $Line) {
    dataview dvOrder (datasource: microflow Shop.DS_Order) {
      textbox tbN (label: 'N', attribute: Name)
    }
  }
  dataview dvDb (datasource: microflow Shop.DS_Order) {
    textbox tbN2 (label: 'N', attribute: Name)
  }
};
```

### L11b-set-ds-assoc

```mdl
mdl 1;
-- BUG-11 (narrower, v0.18): SET DataSource = $currentObject/Assoc on a DataView is refused
alter page Shop.L11_Page { set DataSource = $currentObject/Shop.Line_Order on dvOrder };
```

Read-back: `describe page Shop.L11_Page`

### L121-parallel-split

```mdl
mdl 1;
-- BUG-121: PARALLEL SPLIT paths written without terminator
create microflow Shop.L121_A ($Order: Shop.Order) begin end;
create workflow Shop.L121_WF
  parameter $WorkflowContext: Shop.Order
begin
  parallel split
    path 1 { call microflow Shop.L121_A; }
    path 2 { call microflow Shop.L121_A; };
end workflow;
```

### L125-enum-attr-ref

```mdl
mdl 1;
-- BUG-125: check --references cannot resolve any enumeration in an attribute declaration
create persistent entity Shop.L125 ( S: enum Shop.OrderStatus );
```

### L126-set-label

```mdl
mdl 1;
-- BUG-126: ALTER PAGE ... SET Label reports success and discards the value
alter page Shop.L07_Page { set Label = 'Order name' on tbName2 };
```

Read-back: `describe page Shop.L07_Page`

### L128a-role

```mdl
mdl 1;
create module role Shop.L128Role;
```

### L128b-role-again

```mdl
mdl 1;
-- BUG-128: CREATE MODULE ROLE not idempotent; create or modify form idempotent since v0.25
create module role Shop.L128Role;
create microflow Shop.L128_After () begin end;
```

### L128c-role-com

```mdl
mdl 1;
create or modify module role Shop.L128Role;
create microflow Shop.L128_After2 () begin end;
```

### L1300-status-where

```mdl
mdl 1;
-- ledger:1300 bare Status attribute name in retrieve where -> CE0161 (reserved-word)
create microflow Shop.L1300_Status ()
begin
  retrieve $L from Shop.Order where [Status = 'Draft'];
end;
```

### L14-drop-insert-before-mf

```mdl
mdl 1;
-- BUG-14: DROP + INSERT BEFORE with a MICROFLOW action
alter page Shop.L07_Page {
  drop widget btnOne;
  insert before btnTwo {
    actionbutton btnOne (caption: 'Next', action: call microflow Shop.L_Act(Order = $currentObject))
  }
};
```

Read-back: `describe page Shop.L07_Page`

### L140-mf-ds-param

```mdl
mdl 1;
-- BUG-140: parameterized microflow datasource on a top-level dataview never wired
create microflow Shop.DS_OrderOfLine ($Line: Shop.Line) returns Shop.Order as $O begin $O = create Shop.Order (Name = 'x'); return $O; end;
create page Shop.L140_Page (title: 'L140', layout: Atlas_Core.Atlas_Default, params: ( $Line: Shop.Line )) {
  dataview dvO (datasource: microflow Shop.DS_OrderOfLine (Line = $Line)) {
    textbox tbN (label: 'N', attribute: Name)
  }
};
```

Read-back: `describe page Shop.L140_Page`

### L144-user-role

```mdl
mdl 1;
-- BUG-144: create user role writes role without CheckSecurity/GUID
create user role L144Role (Shop.User);
```

Read-back: `describe user role L144Role`

### L146-diff

```mdl
mdl 1;
/** Line doc
 second line */
create or modify persistent entity Shop.Line (
  Name: string(100),
  Qty: integer
);
```

### L147-forward-call

```mdl
mdl 1;
-- BUG-147: forward call microflow (callee created LATER in same script) passes check, half-applies at exec
create microflow Shop.L147_Caller () begin call microflow Shop.L147_Callee(); end;
create microflow Shop.L147_Callee () begin end;
```

### L148-enum-literal-last

```mdl
mdl 1;
-- BUG-148: quoted enum literal as the LAST member of a create member list draws E007 at check
create microflow Shop.L148_C ()
begin
  $O = create Shop.Order (Name = 'x', Status = Shop.OrderStatus."Draft");
end;
```

### L151-rest-body-var

```mdl
mdl 1;
-- BUG-151: rest call body $Var sends literal text $Var (runtime) -- static part only
create microflow Shop.L151_R () returns string as $Resp
begin
  declare $Body string = '{"a":1}';
  $Resp = rest call post 'https://example.invalid/x' body $Body timeout 10 returns string;
  return $Resp;
end;
```

Read-back: `describe microflow Shop.L151_R`

### L155-rendermode

```mdl
mdl 1;
-- BUG-155: alter page set RenderMode refused on a dynamic text
alter page Shop.L07_Page { set RenderMode = H2 on txtA };
```

Read-back: `describe page Shop.L07_Page`

### L17-beginoftoday-xpath

```mdl
mdl 1;
-- BUG-17: [%BeginOfToday%] / [%EndOfToday%] in retrieve where -> CE0161
create microflow Shop.L17_Today () returns boolean as $R
begin
  retrieve $Items from Shop.Order where [DueDate >= '[%BeginOfToday%]' and DueDate < '[%EndOfToday%]'];
  retrieve $Items2 from Shop.Order where [DueDate >= [%BeginOfToday%]];
  declare $R boolean = true;
  return $R;
end;
```

Read-back: `describe microflow Shop.L17_Today`

### L17b-beginofcurrentday

```mdl
mdl 1;
-- BUG-17 control: the documented Mendix token names [%BeginOfCurrentDay%] / [%EndOfCurrentDay%]
create microflow Shop.L17b_Today ()
begin
  retrieve $Items from Shop.Order where [DueDate >= '[%BeginOfCurrentDay%]' and DueDate < '[%EndOfCurrentDay%]'];
end;
```

### L19-replace-wrap-container

```mdl
mdl 1;
-- BUG-19: REPLACE wrapping an existing widget in a CONTAINER
alter page Shop.L07_Page { replace tbName with { container ctnWrap { textbox tbName2 (label: 'Name', attribute: Name) } } };
```

### L37-combobox-assoc

```mdl
mdl 1;
-- BUG-37: COMBOBOX in association mode
create page Shop.L37_Page (title: 'L37', layout: Atlas_Core.Atlas_Default, params: ( $Line: Shop.Line )) {
  dataview dv1 (datasource: $Line) {
    combobox cb1 (label: 'Order', attribute: Shop.Line_Order, datasource: database Shop.Order, captionattribute: Name)
  }
};
```

Read-back: `describe page Shop.L37_Page`

### L67-snippet-prim-param

```mdl
mdl 1;
-- BUG-67: snippet with a primitive-typed parameter fails at exec "entity not found"
create snippet Shop.L67_Snip (params: ( $X: string )) { dynamictext t (content: 'x') };
```

### L73-raise-error-main

```mdl
mdl 1;
-- BUG-73: raise error; in a microflow's main flow -> CE0710
create microflow Shop.L73_Raise ($Order: Shop.Order)
begin
  if $Order/Name = '' then
    raise error;
  end if;
end;
```

### L76-wf-decision

```mdl
mdl 1;
-- BUG-76/108 (still a STOP, learned-mdl-preflight.md:9): workflow DECISION enum outcomes -> StorageLoadException
create microflow Shop.L76_Act ($Order: Shop.Order) begin end;
create workflow Shop.L76_WF
  parameter $WorkflowContext: Shop.Order
begin
  decision $WorkflowContext/Status
    outcomes 'Draft' -> { call microflow Shop.L76_Act; }
             'Closed' -> { }
             default -> { };
end workflow;
```

Read-back: `describe workflow Shop.L76_WF`

### L76a-act

```mdl
mdl 1;
create microflow Shop.L76_Act ($Order: Shop.Order) begin end;
```

### L76b-wf-decision-bool

```mdl
mdl 1;
-- BUG-76: boolean DECISION in workflow
create workflow Shop.L76b_WF
  parameter $WorkflowContext: Shop.Order
begin
  decision '$WorkflowContext/Name = ''x'''
    outcomes true -> { }
             false -> { };
end workflow;
```

Read-back: `describe workflow Shop.L76b_WF`

### L76c-wf-decision-qualified

```mdl
mdl 1;
-- BUG-76/108 with the form mxcli now asks for: fully qualified enum outcomes + empty outcome
create workflow Shop.L76c_WF
  parameter $WorkflowContext: Shop.Order
begin
  decision $WorkflowContext/Status
    outcomes 'Shop.OrderStatus.Draft' -> { call microflow Shop.L76_Act(Order = $WorkflowContext); }
             'Shop.OrderStatus.Closed' -> { }
             '' -> { };
end workflow;
```

Read-back: `describe workflow Shop.L76c_WF`

### L77-quoted-attr-change

```mdl
mdl 1;
-- BUG-77/75: quoted attribute segment $Var/"Attr" in create/change and call args -> CE0117
create microflow Shop.L77_Sub ($S: string) begin end;
create microflow Shop.L77_Q ($Order: Shop.Order)
begin
  change $Order (Note = $Order/"Name");
  call microflow Shop.L77_Sub(S = $Order/"Name");
end;
```

### L78-assoc-eq-literal

```mdl
mdl 1;
-- BUG-78: where [Assoc = 'Value'] -> CE0161
create microflow Shop.L78_R ()
begin
  retrieve $Users from System.User where [System.UserRoles = 'Engineering'];
end;
```

### L82a-notnull

```mdl
mdl 1;
create persistent entity Shop.L82 ( Code: string(50) not null error 'Code required' );
```

### L82b-clear-notnull

```mdl
mdl 1;
-- BUG-82: create or modify entity cannot clear an existing not-null validation rule
create or modify persistent entity Shop.L82 ( Code: string(50) );
```

Read-back: `describe entity Shop.L82`

### L84-set-ds-database-dv

```mdl
mdl 1;
-- BUG-84: SET DataSource = DATABASE Module.Entity on a DataView silently wipes the datasource
alter page Shop.L11_Page { set DataSource = database Shop.Order on dvDb };
```

Read-back: `describe page Shop.L11_Page`

### L86-nanoflow-barrier

```mdl
mdl 1;
-- BUG-86: MDL044 write barrier microflow-only; same expression in a nanoflow passes check
create nanoflow Shop.L86_NF () returns datetime as $d
begin
  declare $d datetime = currentDateTime();
  return $d;
end;
```

### L92-insert-wrong-anchor

```mdl
mdl 1;
-- BUG-92 trap 1: INSERT against a wrong-but-plausible / missing anchor silently no-ops
alter page Shop.L07_Page { insert after btnDoesNotExist { dynamictext txtNew (content: 'new') } };
```

### L94-visible-roles

```mdl
mdl 1;
-- BUG-94: Visible: roles (...) since v0.27
create page Shop.L94_Page (title: 'L94', layout: Atlas_Core.Atlas_Default) {
  container c1 (visible: roles (Shop.Admin)) { dynamictext t (content: 'admin only') }
};
```

Read-back: `describe page Shop.L94_Page`

### L98-calculated-by

```mdl
mdl 1;
-- BUG-98: calculated by on an attribute silently dropped at write
create persistent entity Shop.L98 ( Name: string(100), Label: string(100) );
```

Read-back: `describe entity Shop.L98`

### L98b-calculated-by

```mdl
mdl 1;
create microflow Shop.L98_Calc ($Obj: Shop.L98) returns string as $s begin declare $s string = 'c'; return $s; end;
```

### L98c-calculated-by

```mdl
mdl 1;
create or modify persistent entity Shop.L98 ( Name: string(100), Label: string(100) calculated by Shop.L98_Calc );
```

Read-back: `describe entity Shop.L98`; `show callers of Shop.L98_Calc`

### LD-countfilter

```mdl
mdl 1;
-- BUG-DRAFT-nested-aggregate-over-filter: COUNT(FILTER(...)) -> CE0012 (fixed v0.23: MDL-LISTOP02)
create microflow Shop.LD_CF ($Orders: list of Shop.Order) returns integer as $n
begin
  $n = count(filter($Orders, Name = 'x'));
  return $n;
end;
```

### LD-create-nocommit

```mdl
mdl 1;
-- BUG-DRAFT-microflow-create-without-commit-silent (fixed v0.28: CONV020 lint)
create microflow Shop.LD_NoCommit () begin $O = create Shop.Order (Name = 'x'); end;
```

### LD-flip-direction

```mdl
mdl 1;
-- learned-mdl-preflight.md:17: flipping FROM/TO with create or modify association is a silent no-op
create or modify association Shop.LOA_LOB from Shop.LOB to Shop.LOA type reference owner default;
```

Read-back: `describe association Shop.LOA_LOB`

### LD-index-createddate

```mdl
mdl 1;
-- BUG-DRAFT-index-on-createddate
create persistent entity Shop.LDI ( Name: string(100), createdDate: autocreateddate ) index (createdDate);
```

### LD-looptype

```mdl
mdl 1;
-- BUG-DRAFT-loop-var-expression-typecheck: type checker skipped inside LOOP
create microflow Shop.LD_Loop ($Orders: list of Shop.Order)
begin
  loop $O in $Orders
  begin
    change $O (Note = $O/Status);
  end loop;
end;
```

### LD-owner-ignored-a

```mdl
mdl 1;
create persistent entity Shop.LOA ( Name: string(10) );
create persistent entity Shop.LOB ( Name: string(10) );
create association Shop.LOA_LOB from Shop.LOA to Shop.LOB type reference owner default;
```

### LD-owner-ignored-b

```mdl
mdl 1;
-- BUG-DRAFT-association-owner-ignored / preflight Step 0: owner Both via create or modify association
create or modify association Shop.LOA_LOB from Shop.LOA to Shop.LOB type reference owner both;
```

Read-back: `describe association Shop.LOA_LOB`

### LD-revoke-assoc

```mdl
mdl 1;
-- BUG-DRAFT-partial-revoke-association-noop
grant Shop.User on Shop.Line (read (Name, Line_Order), write (Name, Line_Order));
```

Read-back: `show access on Shop.Line`

### LD-revoke-assoc2

```mdl
mdl 1;
revoke Shop.User on Shop.Line (write (Line_Order));
```

Read-back: `show access on Shop.Line`

### LD-sysenum

```mdl
mdl 1;
-- placeholder: BUG-DRAFT-system-enumerations-undiscoverable is a describe/show probe (post only)
create microflow Shop.LD_SysEnum () begin end;
```

Read-back: `show enumerations in System`; `describe enumeration System.DeviceType`

### LD-xpathcase

```mdl
mdl 1;
-- BUG-DRAFT-xpath-system-member-case: [CreatedDate >= $Since] wrong case -> CE0161 (fixed v0.25)
create persistent entity Shop.LDA ( Name: string(100), CreatedDate2: autocreateddate );
create microflow Shop.LD_XC ($Since: datetime)
begin
  retrieve $L from Shop.LDA where [CreatedDate >= $Since];
end;
```

### M01-dialect-noheader

```mdl
-- learned-mdl-preflight.md:68 "keep the skills' spellings, never add mdl 1;" -- a header-less script in the skills' spellings
create or replace microflow Shop.M01_Count ($L: list of Shop.Order) returns integer as $n
begin
  $n = count($L);
  call microflow Shop.M01_Sub() on error {
    log warning node 'X' 'failed';
  };
  return $n;
end;
/
create or replace microflow Shop.M01_Sub () begin end;
/
```

### M02-mdl1-limit1

```mdl
mdl 1;
-- learned-mdl-preflight.md:68: under mdl 1, retrieve ... limit 1 returns a list while check passes
create microflow Shop.M02_Limit () returns string as $s
begin
  retrieve $O from Shop.Order limit 1;
  declare $s string = $O/Name;
  return $s;
end;
```

### M03-alter-navigation

```mdl
mdl 1;
-- learned-mdl-preflight.md:40 STOP #21: alter navigation exists v0.28+
alter navigation Responsive { add menu item 'Orders' page Shop.Order_Edit };
```

### M04a-dg2

```mdl
mdl 1;
create page Shop.M04_Page (title: 'M04', layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (datasource: database from Shop.Line sort by Name asc) {
    column colName (attribute: Name, caption: 'Name') { textfilter tf1 (attributes: [Name]) }
    column colQty (attribute: Qty, caption: 'Qty')
    column colOrd (attribute: Line_Order/Name, caption: 'Order') {
      dropdownfilter ddf1 (Association: Shop.Line_Order, datasource: database Shop.Order, CaptionAttribute: Name)
    }
  }
};
```

Read-back: `describe page Shop.M04_Page`

### M04b-replace-col-attr

```mdl
mdl 1;
-- gotcha learned-mdl-preflight.md:62 / BUG-DRAFT-dg2-replace-column-attribute-passes-check: REPLACE DG2 column with new Attribute passes check, fails mxbuild
alter page Shop.M04_Page { replace Qty with { column colQty2 (attribute: Name, caption: 'Name again') } };
```

### M04c-pagesize

```mdl
mdl 1;
-- BUG-122: ALTER PAGE SET PageSize fails on a DG2 that CREATE accepted
alter page Shop.M04_Page { set (PageSize: 50) on dg1 };
```

### M04d-insert-col

```mdl
mdl 1;
-- gotcha: inserting a DG2 column via ALTER PAGE
alter page Shop.M04_Page { insert after Name { column colNew (attribute: Name, caption: 'New') } };
```

Read-back: `describe page Shop.M04_Page`

### M04e-crossmod-insert

```mdl
mdl 1;
-- BUG-96: cross-module ALTER PAGE INSERT AFTER <col> into a DG2 (script lives in ModB context; page in Shop)
create microflow ModB.M04e_Dummy () begin end;
alter page Shop.M04_Page { insert after Qty { column colX (attribute: Line_Order/Shop.Order_Customer/Name, caption: 'Cust') } };
```

### M05-snippet-dg2-system

```mdl
mdl 1;
-- BUG-68: snippet datagrid column on system attribute (createdDate)
create persistent entity Shop.M05E ( Name: string(10), createdDate: autocreateddate );
create snippet Shop.M05_Snip {
  datagrid dg1 (datasource: database from Shop.M05E sort by createdDate desc) {
    column (attribute: createdDate, caption: 'Created')
  }
};
```

### M06-showcallers-button

```mdl
mdl 1;
-- BUG-123: SHOW CALLERS OF indexes neither page button actions nor show page targets
create microflow Shop.M06_Target () begin end;
create page Shop.M06_Page (title: 'M06', layout: Atlas_Core.Atlas_Default) {
  actionbutton b1 (caption: 'Go', action: call microflow Shop.M06_Target())
};
```

Read-back: `refresh catalog`; `show callers of Shop.M06_Target`

### M07-constant-secret

```mdl
mdl 1;
-- BUG-DRAFT-describe-show-constants-print-secrets
create constant Shop.M07_Password ( Type: string, DefaultValue: 'hunter2-demo' );
```

Read-back: `describe constant Shop.M07_Password`; `show constants in Shop`

### M08-if-exists

```mdl
mdl 1;
-- BUG-154: if exists forms on drop
drop microflow if exists Shop.M08_Nope;
drop page if exists Shop.M08_Nope;
drop entity if exists Shop.M08_Nope;
drop association if exists Shop.M08_Nope;
```

### M09-rename-module

```mdl
mdl 1;
-- BUG-DRAFT-rename-module-leaves-xpath: rename module leaves XPath constraints naming old module
create module RenMe;
create persistent entity RenMe.Thing ( Name: string(10) );
create persistent entity RenMe.Other ( Name: string(10) );
create association RenMe.Thing_Other from RenMe.Thing to RenMe.Other type reference owner default;
create microflow RenMe.M09_R () begin retrieve $L from RenMe.Thing where [RenMe.Thing_Other/RenMe.Other/Name = 'x']; end;
```

### M09b-rename

```mdl
mdl 1;
rename module RenMe to Renamed;
```

Read-back: `describe microflow Renamed.M09_R`

### M10-rename-page-folder

```mdl
mdl 1;
-- BUG-DRAFT-rename-page-renames-folder: page and same-named folder
create page Shop.Twin (title: 'Twin', layout: Atlas_Core.Atlas_Default, folder: 'Twin') { dynamictext t (content: 'x') };
```

### M10b-rename

```mdl
mdl 1;
rename page Shop.Twin to TwinRenamed;
```

Read-back: `show pages in Shop`

### M11a-dg2-plain

```mdl
mdl 1;
create page Shop.M11_Page (title: 'M11', layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (datasource: database Shop.Line) {
    column (attribute: Name, caption: 'Name')
    column (attribute: Qty, caption: 'Qty')
  }
};
```

### M11b-replace-col

```mdl
mdl 1;
-- gotcha learned-mdl-preflight.md:62: REPLACE a DG2 column with a new Attribute (plain database source, no sort, no filters)
alter page Shop.M11_Page { replace Qty with { column (attribute: Name, caption: 'Name again') } };
```

### M11c-insert-col

```mdl
mdl 1;
alter page Shop.M11_Page { insert after Name { column (attribute: Qty, caption: 'Qty 2') } };
```

Read-back: `describe page Shop.M11_Page`

### MP01-header-no-parens

```mdl
mdl 1;
-- learned-microflow-patterns:264 header without () -> errors point at returns/List of (fixed v0.28 per upstream note)
create microflow Shop.MP01_NoParens returns boolean as $r
begin
  declare $r boolean = true;
  return $r;
end;
```

### MP02-currentuser-as-string

```mdl
mdl 1;
-- learned-microflow-patterns:49 [%CurrentUser%] as a string expression -> CE0117
create microflow Shop.MP02_CU () returns string as $s
begin
  declare $s string = '[%CurrentUser%]';
  return $s;
end;
```

### MP02b-currentuser-token-unquoted

```mdl
mdl 1;
-- learned-microflow-patterns:49 [%CurrentUser%] token (unquoted) as a String expression value -> CE0117
create microflow Shop.MP02b_CU () returns string as $s
begin
  declare $s string = [%CurrentUser%];
  return $s;
end;
```

### MP03-npe-retrieve

```mdl
mdl 1;
-- learned-microflow-patterns:152 retrieve from NPE -> CE0056
create microflow Shop.MP03_NPE ()
begin
  retrieve $L from Shop.OrderDto;
end;
```

### MP04-nonowner-set-same

```mdl
mdl 1;
-- learned-microflow-patterns:186 set association from non-owner side (same module) -> CE0854
create microflow Shop.MP04_NonOwner ($Order: Shop.Order, $Line: Shop.Line)
begin
  change $Order (Shop.Line_Order = $Line);
end;
```

### MP04b-nonowner-set-cross

```mdl
mdl 1;
-- learned-microflow-patterns:265 cross-module non-owner change -> CE0854
create microflow Shop.MP04b_NonOwnerX ($Order: Shop.Order, $C: ModB.Customer)
begin
  change $C (Shop.Order_Customer = $Order);
end;
```

### MP04c-owner-set-control

```mdl
mdl 1;
create microflow Shop.MP04c_Owner ($Order: Shop.Order, $Line: Shop.Line)
begin
  change $Line (Shop.Line_Order = $Order);
end;
```

### MP05-annotation-trailing

```mdl
mdl 1;
-- learned-microflow-patterns:223 free-floating @annotation before end -> parse error
create microflow Shop.MP05_Ann ()
begin
  log info node 'X' 'hello';
  @annotation 'trailing note'
end;
```

### MP05b-annotation-bound

```mdl
mdl 1;
create microflow Shop.MP05b_Ann ()
begin
  @annotation 'bound note'
  log info node 'X' 'hello';
end;
```

Read-back: `describe microflow Shop.MP05b_Ann`

### MP06-valfb-no-attr

```mdl
mdl 1;
-- learned-microflow-patterns:266 validation feedback with no attribute -> CE0091
create microflow Shop.MP06_VF ($Order: Shop.Order)
begin
  validation feedback $Order message 'bad';
end;
```

### MP07-grant-bare-role

```mdl
mdl 1;
-- learned-microflow-patterns:368 bare module role name -> MDL-GRANT02
create microflow Shop.MP07_G () begin end;
grant execute on microflow Shop.MP07_G to User;
```

### MP08-currentdatetime-fn

```mdl
mdl 1;
-- learned-microflow-patterns:374 currentDateTime() rejected
create microflow Shop.MP08_DT () returns datetime as $d
begin
  declare $d datetime = currentDateTime();
  return $d;
end;
```

### MP09-enum-return-string

```mdl
mdl 1;
-- learned-microflow-patterns:378 enum returned from String microflow / assigned to String attr -> CE0117
create microflow Shop.MP09_Ret ($Order: Shop.Order) returns string as $s
begin
  change $Order (Note = $Order/Status);
  return $Order/Status;
end;
```

### MP10-onerror-in-loop

```mdl
mdl 1;
-- learned-microflow-patterns:397 custom error handling inside loop body -> CE0644, MDL006
create microflow Shop.MP10_Sub ($Order: Shop.Order) begin end;
create microflow Shop.MP10_Loop ($Orders: list of Shop.Order)
begin
  loop $O in $Orders
  begin
    call microflow Shop.MP10_Sub(Order = $O) on error continue;
  end loop;
end;
```

### MP11-create-discarded

```mdl
mdl 1;
-- learned-detection-gaps:33 CREATE ... COMMIT with result discarded -> CE6005
create microflow Shop.MP11_Discard ()
begin
  create Shop.Order (Name = 'x');
end;
```

### MP12-xpath-eq-null

```mdl
mdl 1;
-- learned-detection-gaps:54 XPath = null -> CE0161
create microflow Shop.MP12_Null ()
begin
  retrieve $L from Shop.Order where [Name = null];
end;
```

### MP13-delete-refresh

```mdl
mdl 1;
-- learned-microflow-patterns:107 delete $X refresh; is legal
create microflow Shop.MP13_Del ($Order: Shop.Order)
begin
  delete $Order refresh;
end;
```

### MP14-onerror-if-noelse

```mdl
mdl 1;
-- learned-detection-gaps:45 if without else inside on error handler (fixed v0.29 per row)
create microflow Shop.MP14_Sub ($Order: Shop.Order) begin end;
create microflow Shop.MP14_Handler ($Order: Shop.Order)
begin
  call microflow Shop.MP14_Sub(Order = $Order) on error without rollback {
    if $Order/Name = '' then
      log warning node 'X' 'empty';
    end if;
  };
end;
```

### MP15-reserved-names

```mdl
mdl 1;
-- learned-detection-gaps:46-47 reserved words Case (entity), Context (attribute), enum value New -> CE7247
create persistent entity Shop."Case" ( Name: string(100) );
create persistent entity Shop.Ctx ( "Context": string(100) );
create enumeration Shop.MP15_Enum ( New 'New', Old 'Old' );
```

### MP15b-reserved-case

```mdl
mdl 1;
-- learned-detection-gaps:46 entity named Case -> CE7247
create persistent entity Shop."Case" ( Name: string(100) );
```

### MP16-get-workflows-unused

```mdl
mdl 1;
-- learned-detection-gaps:52 get workflows for $X on an entity no workflow uses -> CE1870
create microflow Shop.MP16_GW ($L: Shop.Line)
begin
  $W = get workflows for $L;
end;
```

### PF01-visible-in-customcontent

```mdl
mdl 1;
-- STOP #1 (learned-mdl-preflight.md:33): visible: expression on container inside DG2 customContent column
create page Shop.PF01_Page (title: 'PF01', layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (datasource: database from Shop.Order sort by Name asc) {
    column (attribute: Name, caption: 'Name')
    column (attribute: Status, caption: 'Status', ShowContentAs: customContent) {
      container cntBadge (visible: [$currentObject/Status = Shop.OrderStatus.Closed]) {
        dynamictext txtS (content: '{1}', contentparams: ({1} = Name))
      }
    }
  }
};
```

Read-back: `describe page Shop.PF01_Page`

### PF01b-editable-quoted

```mdl
mdl 1;
-- STOP #1b: Editable bare expression (prescribed) vs quoted string (dropped <v0.28)
create page Shop.PF01b_Page (title: 'PF01b', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    textbox tbA (label: 'A', attribute: Name, editable: $currentObject/Status != Shop.OrderStatus.Closed)
    textbox tbB (label: 'B', attribute: Note, editable: '$currentObject/Status != Shop.OrderStatus.Closed')
    textbox tbC (label: 'C', attribute: Note, editable: [$currentObject/Status != Shop.OrderStatus.Closed])
  }
};
```

Read-back: `describe page Shop.PF01b_Page`

### PF04-autochangedby

```mdl
mdl 1;
-- STOP #4: bind widget to AutoChangedBy -> check passes, mx check CE1613
create persistent entity Shop.Audited (
  Name: string(100),
  ChangedBy: autochangedby,
  ChangedDate: autochangeddate
);
create page Shop.PF04_Page (title: 'PF04', layout: Atlas_Core.Atlas_Default, params: ( $A: Shop.Audited )) {
  dataview dv1 (datasource: $A) {
    textbox tbA (label: 'By', attribute: ChangedBy)
    datepicker dpB (label: 'Date', attribute: ChangedDate)
  }
};
```

Read-back: `describe entity Shop.Audited`

### PF12a-contentparams-tostring

```mdl
mdl 1;
-- STOP #12 / STOP #1: toString() in ContentParams inside customContent -> claimed CE1613
create page Shop.PF12a_Page (title: 'PF12a', layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (datasource: database from Shop.Order sort by Name asc) {
    column (attribute: Status, caption: 'Status', ShowContentAs: customContent) {
      dynamictext txtS (content: '{1}', contentparams: ({1} = toString(Status)))
    }
  }
};
```

### PF12b-contentparams-ifthen

```mdl
mdl 1;
-- STOP #12 (BUG-142): if..then..else in ContentParams passes check+exec, CE1613 at mxbuild
create page Shop.PF12b_Page (title: 'PF12b', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    dynamictext txtS (content: '{1}', contentparams: ({1} = if $currentObject/Name = '' then 'none' else $currentObject/Name))
  }
};
```

Read-back: `describe page Shop.PF12b_Page`

### PF12c-contentparams-currentobject

```mdl
mdl 1;
-- STOP #12: $currentObject/Attr in ContentParams
create page Shop.PF12c_Page (title: 'PF12c', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    dynamictext txtS (content: '{1}', contentparams: ({1} = $currentObject/Name))
  }
};
```

Read-back: `describe page Shop.PF12c_Page`

### PF12d-contentparams-bare-control

```mdl
mdl 1;
-- STOP #12 control: bare attribute and quoted literal (the prescribed workaround)
create page Shop.PF12d_Page (title: 'PF12d', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    dynamictext txtA (content: '{1}', contentparams: ({1} = Name))
    dynamictext txtB (content: '{1}', contentparams: ({1} = 'literal'))
  }
};
```

### PF12e-contentparams-oldlist-syntax

```mdl
mdl 1;
-- STOP #12 in the toolkit's own spelling ContentParams: [ ... ] with an expression
create page Shop.PF12e_Page (title: 'PF12e', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order) {
    dynamictext txtS (content: '{1}', contentparams: [{1} = toString(Status)])
  }
};
```

### PF14a-grant-wide

```mdl
mdl 1;
-- STOP #14 setup (BUG-145): wide grant
create persistent entity Shop.Secret ( Name: string(100), Note: string(100) );
grant Shop.User on Shop.Secret (read (Name, Note), write (Name, Note));
```

### PF14b-grant-narrow

```mdl
mdl 1;
-- STOP #14 (BUG-145): a narrowing grant merges instead of replacing
grant Shop.User on Shop.Secret (read (Name));
```

Read-back: `show access on Shop.Secret`; `describe entity Shop.Secret`

### PF16-currentuser-path

```mdl
mdl 1;
-- STOP #16: path inside [%CurrentUser/...%] in an access-rule XPath -> CE0161 (Mendix rule)
create persistent entity Shop.Owned ( Name: string(100) );
create association Shop.Owned_Account from Shop.Owned to Administration.Account type reference owner default;
grant Shop.User on Shop.Owned (read *) where '[Shop.Owned_Account = ''[%CurrentUser/Administration.Account_Language%]'']';
```

### PF16b-currentuser-bare

```mdl
mdl 1;
-- STOP #16 prescribed fix: bare CurrentUser token, traversal on the left
create persistent entity Shop.Owned2 ( Name: string(100) );
create association Shop.Owned2_Account from Shop.Owned2 to Administration.Account type reference owner default;
grant Shop.User on Shop.Owned2 (read *) where '[Shop.Owned2_Account = ''[%CurrentUser%]'']';
```

### PF18-workflow-callee-same-script

```mdl
mdl 1;
-- STOP #18: callee microflow created in the SAME script as the workflow that calls it
create microflow Shop.WF18_Callee ($Order: Shop.Order) returns boolean as $r
begin
  declare $r boolean = true;
  return $r;
end;
create workflow Shop.WF18
  parameter $WorkflowContext: Shop.Order
begin
  call microflow Shop.WF18_Callee;
end workflow;
```

Read-back: `describe workflow Shop.WF18`

### PF22-nonidempotent-rerun

```mdl
mdl 1;
-- STOP #22: non-idempotent statement (alter entity add attribute) - run TWICE; claim: 2nd run rolls back everything
create or modify microflow Shop.PF22_Marker () begin end;
alter entity Shop.Line add attribute PF22Extra: string(50);
```

### PF22-rerun

```mdl
mdl 1;
-- STOP #22: non-idempotent statement (alter entity add attribute) - run TWICE; claim: 2nd run rolls back everything
create or modify microflow Shop.PF22_Marker () begin end;
alter entity Shop.Line add attribute PF22Extra: string(50);
```

### PF22-rerun2

```mdl
mdl 1;
-- STOP #22: non-idempotent statement (alter entity add attribute) - run TWICE; claim: 2nd run rolls back everything
create or modify microflow Shop.PF22_Marker () begin end;
alter entity Shop.Line add attribute PF22Extra: string(50);
```

### PF23-create-or-modify-drops

```mdl
mdl 1;
-- STOP #23: create or modify entity with fewer attributes replaces the attribute set (warn only)
create or modify persistent entity Shop.Line (
  Name: string(100)
);
```

Read-back: `describe entity Shop.Line`

### PF24-designprop-not-in-theme

```mdl
mdl 1;
-- STOP #24: Form orientation design property not in mxcli-new theme -> CE6083
create page Shop.PF24_Page (title: 'PF24', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  dataview dv1 (datasource: $Order, designproperties: ('Form orientation': 'Vertical')) {
    textbox tb1 (label: 'N', attribute: Name)
  }
};
```

### PF26-dg2-quoted-assoc-path

```mdl
mdl 1;
-- STOP #26: DG2 column over association, quoted path -> CE1613
create page Shop.PF26_Page (title: 'PF26', layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (datasource: database from Shop.Line sort by Name asc) {
    column (attribute: "Line_Order/Name", caption: 'Order')
  }
};
```

Read-back: `describe page Shop.PF26_Page`

### PF26b-dg2-unquoted-assoc-path

```mdl
mdl 1;
-- STOP #26 prescribed fix: unquoted path
create page Shop.PF26b_Page (title: 'PF26b', layout: Atlas_Core.Atlas_Default) {
  datagrid dg1 (datasource: database from Shop.Line sort by Name asc) {
    column (attribute: Line_Order/Name, caption: 'Order')
  }
};
```

### PF29-constant-in-nanoflow

```mdl
mdl 1;
-- STOP #29: constant in nanoflow without ExposedToClient -> CE0117
create constant Shop.PF29_Const ( Type: string, DefaultValue: 'x' );
create nanoflow Shop.PF29_NF () returns string as $s
begin
  declare $s string = @Shop.PF29_Const;
  return $s;
end;
```

### PF30-dynamicimage

```mdl
mdl 1;
-- STOP #30: dynamicimage on React-client page -> CE0582
create persistent entity Shop.Pic extends System.Image ( Title: string(100) );
create page Shop.PF30_Page (title: 'PF30', layout: Atlas_Core.Atlas_Default, params: ( $Pic: Shop.Pic )) {
  dataview dv1 (datasource: $Pic) {
    dynamicimage img1 ()
  }
};
```

### PF31-two-hop-binding

```mdl
mdl 1;
-- STOP #31: data-view widget attribute across 2 associations -> CE1613
create page Shop.PF31_Page (title: 'PF31', layout: Atlas_Core.Atlas_Default, params: ( $Line: Shop.Line )) {
  dataview dv1 (datasource: $Line) {
    textbox tb1 (label: 'Cust', attribute: Shop.Line_Order/Shop.Order/Shop.Order_Customer/ModB.Customer/Name)
  }
};
```

### PF32-showpage-arg-outside-dv

```mdl
mdl 1;
-- STOP #32: show page with an argument outside a data view -> MDL-PAGEARG01
create page Shop.PF32_Page (title: 'PF32', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  actionbutton btn1 (caption: 'Go', action: show page Shop.Order_Edit (Order = $Order))
};
```

### PF32b-showpage-currentobject-outside-dv

```mdl
mdl 1;
-- STOP #32 variant: $currentObject argument where nothing binds it
create page Shop.PF32b_Page (title: 'PF32b', layout: Atlas_Core.Atlas_Default, params: ( $Order: Shop.Order )) {
  actionbutton btn1 (caption: 'Go', action: show page Shop.Order_Edit (Order = $currentObject))
};
```

### PF33a-callee

```mdl
mdl 1;
create microflow Shop.PF33_Callee () begin end;
create microflow Shop.PF33_Caller () begin call microflow Shop.PF33_Callee(); end;
```

### PF33b-change-return

```mdl
mdl 1;
-- STOP #33: change callee return type in a later script; mxcli-written caller
create or modify microflow Shop.PF33_Callee () returns boolean as $r begin declare $r boolean = true; return $r; end;
```

Read-back: `describe microflow Shop.PF33_Caller`
