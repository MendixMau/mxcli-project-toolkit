# Resolved mxcli bugs — archived 2026-08-20

Entries retested against a freshly built mxcli **v0.18.0** (commit `0dda3a76`) on Mendix 11.12.0
and confirmed fixed. Full method, environment limits and A/B evidence:
[mxlabs-v0.18.0-retest-2026-08-20.md](mxlabs-v0.18.0-retest-2026-08-20.md).

**Two of these were fixed in v0.17.0, not v0.18.0** — see the provenance-correction section of
the retest report. Do not cite v0.18.0 for BUG-59 or BUG-60.

---

## BUG-33: Cross-module association nav-through requires fully-qualified target-entity path

**Status: CONFIRMED STILL OPEN 2026-08-03** — reproduced byte-for-byte identically on RnD
`504aec67` and Engalar `26f2866` (CE0117 on real mxbuild); short form parses and writes
cleanly on both, only the fully-qualified form compiles. Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/03-BUG-33-cross-module-assoc-nav-unqualified.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:153-161`

`$Item/Module.Assoc/TargetEntity/Attr` (short form) fails for cross-module association
traversal; must fully qualify as `$Item/Module.Assoc/TargetModule.TargetEntity/Attr`.

---

## BUG-38: `DatagridDropdownFilter` in association/ref mode uncreatable via MDL

**Status: CONFIRMED STILL OPEN 2026-08-03** — fails on both RnD `504aec67` and Engalar
`26f2866` (CE1613, association written as a plain attribute path); Engalar additionally
silently drops the nested filter widget entirely, worse than RnD. Draft issue ready:
`a WMS demo project/bug-logs/mxcli-retest-2026-08-03/gh-issues-ready/04-BUG-38-dropdownfilter-association-mode.md`.
**Reproducible:** Reported only
**Discovered:** a WMS conversion project, `CLAUDE.md:156`

Workaround: MCP `pg_patch_page` with an explicit `refOptions`/`refEntity`/
`Pages$MicroflowSource` shape.

---

## BUG-59: `GRANT ... (READ (...), WRITE (...))` silently drops an association name it doesn't already know about — cannot add a new association `MemberAccess` entry to an access rule, so `CE0066` on a bidirectional (`Owner: Both`) association has no mxcli fix

**Severity:** Medium — real mxbuild gate-blocker (`CE0066`), no data-loss risk, workaround is a
single Studio Pro click
**Reproducible:** Yes, consistently
**Confirmed:** Mendix 11.13.0, mxcli v0.16.0, 2026-08-07, TFC-TCXGraphPOC-main
**mxcli version when found:** v0.16.0 (`GRANT`/`REVOKE` write path)

### Symptom

A bidirectional association (`Owner: Both` in the BSON — created between two entities in
different modules, e.g. `TFC.DrawingDocs` ←→ `TFC.FeasibilityDecision`) requires a
`MemberAccess` entry for that association in **both** entities' access rules. If one side's
access rules were authored (or GRANT'd) before the association existed, or the association
was added without updating that side's rules, real `mxbuild`/Studio Pro reports:

```
[error] [CE0066] "Entity access is out of date. Please update security by clicking the
'Update security' button in the domain model editor." at Domain model of module '<Mod>'
```

The error is reported against the whole domain model document, not a specific entity —
`elementId` is empty in `.mpr-snapshots/last-mxbuild-errors.json`. `mxcli check` and `mxcli
check --references` do not catch it (same blind spot as BUG-58: both are silent at the
syntax/reference layer, only real `mxbuild`/SP-load surfaces it — confirmed via
`./mxcli docker check`).

### Root cause (confirmed via direct BSON decode)

Verified by decoding the domain model `.mxunit` with Python's `bson` module (`pymongo`
package) and diffing each entity's `AccessRules[].MemberAccesses[]` against every association
where that entity is `ParentPointer`/`ChildPointer` with `Owner: Both`. One side had the
association's `MemberAccess` row (`Attribute: ''`, `Association: '<Mod>.<AssocName>'`), the
other did not, on every one of that entity's 4 role rules.

### What does NOT fix it

- `GRANT Mod.Role ON Mod.Entity (READ *, WRITE *)` (the `*` shorthand) — regenerates the
  existing member list unchanged; does not enumerate the entity's associations from the
  domain model, so a never-granted association is never added.
- `GRANT Mod.Role ON Mod.Entity (READ ("Attr1", "AssocName"), WRITE (...))` — syntax is
  accepted (`mxcli check` passes, `--references` passes), and `mxcli exec` reports success,
  but the unrecognized association name is **silently dropped** from the written rule — the
  echoed `Result:` line omits it, and a BSON re-decode after exec confirms the `MemberAccess`
  row for that association was never created. No error, no warning — a true silent no-op.
  Confirmed the rule set was otherwise correctly rewritten (attribute-level rights all
  landed as specified).
- Re-running `mxbuild`/`docker check` after the above exec: `CE0066` still present, unchanged.

### Workaround

Click "Update security" in Studio Pro's domain model editor (regenerates all entities'
`MemberAccesses` from the current attribute/association list in one pass) — this is the
message's own literal instruction and is, as far as this investigation could determine, the
only way to add a missing association `MemberAccess` row. No `HELP`-documented mxcli command
performs this refresh, and `GRANT`'s member-list parser only round-trips members it already
recognizes; it does not discover new ones from the domain model.

### Detection

Same technique as BUG-58: `mxcli check`/`--references` are both blind. Confirm via `./mxcli
docker check -p <project>.mpr` (or a same-version `mx check`) in a disposable sandbox copy
before trusting any script that touches an entity access rule on an entity with a bidirectional
association. To find the specific gap ahead of time: decode the domain model `.mxunit` and diff
each `Owner: Both` association against both sides' `AccessRules[].MemberAccesses[]` — a missing
row on either side predicts `CE0066` before you even run `mxbuild`.

### Related

Same "silent at check/exec, only real mxbuild/SP-load catches it" shape as [[BUG-58]] and
[[BUG-21]]. Distinct from either — this is a **gap in `GRANT`'s coverage of association
members**, not a corruption of a written value.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, Batch 4 of the 2026-08-06 audit
remediation (`FeasibilityDecision_FileDocument` association, added earlier the same
remediation pass without a matching `FeasibilityDecision`-side access-rule update).

### RESOLVED in official tag `v0.17.0` (2026-08-10)

Changelog claims "a `GRANT` now covers every entity member, including both-owner associations."
Verified with a controlled A/B, not taken on faith: two fresh sandbox copies of
TFC-TCXGraphPOC-main (rsync to `/tmp`, real `.mpr` untouched), identical minimal probe —
two new entities, a fresh `Owner: Both` `ReferenceSet` association between them, then
`GRANT Mod.Role ON Entity (CREATE, DELETE, READ *, WRITE *)` on both sides, varying only the
binary — gated with the matching `Mendix Studio Pro 11.13.0` `mx check`:

| binary | `mx check` result |
|---|---|
| `v0.16.0` (tagged) | `[error] [CE0115]`-class `CE0066` reproduced on the new association |
| `v0.17.0` (tagged, official) | 0 new errors (only an unrelated, pre-existing `CE0115` on the project remained) |

TFC-TCXGraphPOC-main upgraded to `v0.17.0` on 2026-08-11 on the combined strength of this and the
[[BUG-WF06]] result above. The manual "Update security" click workaround should no longer be
needed on `v0.17.0` for this specific gap — not yet retested on a pre-existing, previously-broken
association (only on a newly-created one), so leave the detection technique above in place as a
guard until that's confirmed too.

### New sighting, 2026-08-12, VB-USI-main, mxcli v0.16.0 — reproduces with ZERO associations

Broader trigger than originally documented: `CE0066` on the whole `Common` domain-model document
after script 51 (`create persistent entity Common.Remark`, `create persistent entity
Common.Attachment extends System.FileDocument`, then two `grant Common.User on ... (create,
delete, read *, write *)` statements) — **no association exists anywhere in this script or in
`Common` at all** (`SHOW ASSOCIATIONS IN Common` → 0 rows). So the trigger isn't limited to a
bidirectional-association `MemberAccess` gap as BUG-59 originally characterized it; a brand-new
entity + an entity-level `GRANT` in the same exec session is enough on its own, at least when the
entity `EXTENDS System.FileDocument` (untested whether a plain new entity without `EXTENDS`
would also trigger it).

`mxcli check`/`--references` and `mxcli exec` were both silent/successful, same blind spot as
before — only real mxbuild (`--target=deploy`) surfaced it. Coverage-checklist verification
(`DESCRIBE ENTITY`, `SHOW SECURITY MATRIX`) confirmed the actual model content was correct and
complete; this is a pure build-gate false positive, not model damage.

VB-USI-main is still pinned to `v0.16.0` (not yet upgraded, unlike TFC-TCXGraphPOC-main above) —
left as-is rather than upgrading mid-build, since an unattended DafNe build session is not the
moment to change the pipeline's tool version. Logged and continuing the build per this project's
"tool bugs get logged, not fought" standing execution mode; the outstanding "Update security"
click (or a `v0.17.0` upgrade + re-verify) needs a human in Studio Pro before Stage 5's final
deploy-readiness gate, not before every intermediate script.

### New sighting, 2026-08-13, VB-USI-main, mxcli v0.17.0 — upgrade does NOT fix this instance

VB-USI-main was upgraded `v0.16.0` → `v0.17.0` mid-build (script 59's fix arc, separately motivated
by BUG-20/BUG-21-class DataView/column defects, which the upgrade did resolve). `CE0066` on the
`Common` domain model from the 2026-08-12 sighting above **persisted unchanged** across every
`docker check`/gate-agent run on the upgraded binary — this contradicts the "should no longer be
needed on `v0.17.0`" expectation logged for TFC-TCXGraphPOC-main's association-level case.

Narrows the scope of the earlier "0 new errors on v0.17.0" result: that test was against a
**newly-created association**'s `MemberAccess` gap. This sighting is the broader, zero-association,
entity-level trigger (new entity + `EXTENDS System.FileDocument` + entity-level `GRANT` in the same
session) — apparently a distinct code path in mxcli's security-metadata regeneration that v0.17.0's
fix didn't cover. Treat "v0.17.0 fixes CE0066" as validated only for the association-`MemberAccess`
case until the entity-level trigger is independently retested elsewhere.

Confirmed non-blocking for VB-USI-main: gate-agent PASS'd script 59 with CE0066 as the sole
(pre-existing, script-51-attributable, out-of-scope) remaining error. The manual Studio Pro
"Update security" click is still the only known fix for this trigger; deferred to the pre-deploy
gate per the same standing note as the original sighting.

---

## BUG-60: `./mxcli docker check` collapses a v2 split-tree `.mpr` back to v1 single-file and deletes `mprcontents/` — on a plain read-only check, no exec involved

### Symptom

Running `./mxcli docker check -p <project>.mpr` against a project already saved in the v2
split-tree format (small `.mpr` index + `mprcontents/*.mxunit` files) silently rewrites the
`.mpr` back into a single monolithic v1 file (all unit content embedded) and deletes the
entire `mprcontents/` directory from disk — even though `docker check` is a read-only
validation command; no `mxcli exec` or model write was involved.

Reproduced twice in a row on the same session, both times immediately after a clean
`git checkout HEAD -- <project>.mpr mprcontents/` restored a known-good v2 state:

```
$ git status --short *.mpr mprcontents/    # clean, 0 diff
$ ./mxcli docker check -p TFC-TCXGraphPOC.mpr
...
The app contains: 0 errors.
Project check passed.
$ git status --short *.mpr mprcontents/
 M TFC-TCXGraphPOC.mpr                      # 352K -> 107M
 D mprcontents/00/09/....mxunit             # x2627 (every unit)
 D mprcontents/00/22/....mxunit
 ...
```

Since git HEAD still describes the v2 tree, this leaves the working tree in exactly the
"disk and git disagree" split-brain state that `bin/exec.sh`'s own gate refuses to
auto-restore from (its snapshot step copies `mprcontents/` alongside the `.mpr`, but a
snapshot taken **after** this flip has already lost the split-tree structure it was meant
to preserve). Studio Pro is expected to crash on open in this state per the project's own
`bin/exec.sh` warning (`WriteBaseFile null ref`) until manually resaved.

### Root cause (not fully isolated)

`docker check` invokes real `mx check`/mxbuild via a Docker mount; something in that
round-trip (likely mxbuild loading the project and writing back a normalized/default-format
copy before or after validation) always produces v1 single-file output regardless of the
input format. Not yet confirmed whether a non-Docker `mx check` (direct binary) does the
same — this project's `mx` is normally invoked exclusively via `./mxcli docker check`, so
that comparison hasn't been run.

### Impact

**Any verification step is destructive to the on-disk split-tree format**, independent of
whether it also mutates model content. A batch-verification workflow that does:
"exec.sh writes → its own gate runs a check → contradicts an earlier known-good check" can
be explained entirely by this — the *earlier* "known-good" check itself already flipped
the format and wiped `mprcontents/`, so the very next mxbuild invocation (exec.sh's
internal gate) is reading a `.mpr` that git still tracks as v2 but which now embeds
mismatched/incomplete content, producing spurious errors (e.g. `CE0066` reappearing on an
association that was independently confirmed present moments earlier via direct BSON
decode).

### Workaround

Never run `./mxcli docker check` (or presumably any real-mxbuild-backed check) directly
against a tracked v2-format project you intend to keep in that format — only run it in a
disposable `/tmp` scratch copy, or immediately follow it with `git checkout HEAD --
<project>.mpr mprcontents/` to discard the flip if you were only verifying (not applying
a real change). If a real change genuinely needs mxbuild verification before commit,
expect the format flip and either accept v1-as-committed (breaks the project's `mprcontents/`-tracking
convention) or open the flipped `.mpr` in Studio Pro afterward and let it re-save as v2
before committing.

### Detection

Compare `git status --short *.mpr mprcontents/` immediately before and after any
`docker check`/`mx check` invocation — a clean-to-2627-deletions transition is the
signature. `ls mprcontents | wc -l` dropping to 0 and `.mpr` file size jumping from
~350K to 100+MB is the fast visual tell.

### Related

Explains, retroactively, an apparent "CE0066 regression" seen in a `bin/exec.sh` internal
gate run on TFC-TCXGraphPOC-main directly after a Batch-4 script exec that did not touch
the affected entity at all — the regression was an artifact of this bug, not a real
defect introduced by that script. Distinct from [[BUG-59]] (a `GRANT` coverage gap) though
discovered while investigating the same CE0066 incident.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, while diagnosing a spurious CE0066
recurrence during Batch 4 of the 2026-08-06 audit remediation.

---

## BUG-61: `CALL JAVA ACTION` on a marketplace action with generic/typed parameters (`MicroflowType`, `EntityTypeParameterType`) writes plain string/expression values instead of the special parameter-value shapes — Studio Pro reports `CE0115`/`CE0126`

**Severity:** High — action executes/checks clean via `mxcli`/`--references` but Studio Pro
rejects the call on open/build; requires a manual Studio Pro rewire to recover
**Reproducible:** Yes, consistently, for this specific marketplace Java action
**Confirmed:** Mendix 11.13.0, mxcli v0.16.0, 2026-08-07, TFC-TCXGraphPOC-main
**mxcli version when found:** v0.16.0 (`CALL JAVA ACTION` write path, `addCallJavaActionAction`)

### Symptom

`AgentCommons.ChatContext_Create_ForAgent` (an AgentCommons/marketplace Java action) has two
special parameters: `ActionMicroflow` (a microflow reference, `MicroflowType`) and
`ContextObject` (a generic entity-type parameter, `EntityTypeParameterType`/`T`). A microflow
written via MDL like:

```
$ChatContext = call java action AgentCommons.ChatContext_Create_ForAgent(
  Agent = $Agent, ActionMicroflow = 'TFCIntegrations.ACT_Agent_ChatAction',
  ContextObject = $SomeEntity, OverwritingDeployedModel = $DeployedModel
) on error rollback;
```

passes `mxcli check --references` and `mxcli exec` cleanly, but opening/building the project
in Studio Pro reports:

```
[error] [CE0115] The arguments that are passed to java action 'AgentCommons.ChatContext_Create_ForAgent' don't match ...
[error] [CE0126] Missing value for parameter 'ActionMicroflow'
```

### Root cause (confirmed via direct BSON decode + mxcli source read)

`mxcli`'s own builder (`~/Mendix/mxcli/mdl/executor/cmd_microflows_builder_calls.go`,
`addCallJavaActionAction`) has dedicated logic to detect `MicroflowType` and
`EntityTypeParameterType` java-action parameters and emit the correct value shapes:

- `MicroflowType` → `microflows.MicroflowParameterValue{Microflow: "..."}`
- `EntityTypeParameterType` (generic `T`) → `microflows.EntityTypeCodeActionParameterValue{Entity: "..."}`
- everything else → the default `microflows.BasicCodeActionParameterValue{Argument: "..."}`

Dumped the actual stored BSON for the call activity (`./mxcli bson dump -p <project>.mpr
--type microflow --object "TFCIntegrations.DS_GraphAgent_ChatContext"`) and confirmed **both**
`ActionMicroflow` and `ContextObject` were written using the plain default
`Microflows$BasicCodeActionParameterValue` — e.g. `ActionMicroflow` holds the literal string
`"'TFCIntegrations.ACT_Agent_ChatAction'"` (a quoted string expression), not a
`MicroflowParameterValue` with a `Microflow` field. There is no `GenericType`/`TypeParameter`
binding anywhere in the dump. This means the parameter-type switch in `addCallJavaActionAction`
fell through to the `default:` branch for both parameters — i.e. `p.ParameterType` was not
recognized as `*javaactions.MicroflowType` / `*javaactions.EntityTypeParameterType` for this
specific Java action, most likely because the Java-action-definition lookup
(`ReadJavaActionByName("AgentCommons.ChatContext_Create_ForAgent")`) either failed/returned nil
for this marketplace-imported action, or returned a definition whose parameter types aren't
being classified correctly by the switch.

### What does NOT fix it

- Quoting/not-quoting the `ActionMicroflow` string literal — the value shape written is wrong
  regardless (`BasicCodeActionParameterValue` vs. the required `MicroflowParameterValue`), no
  MDL-level phrasing change routes around it.
- `--references` and `mxcli check` are both blind to this — same "silent at check/exec, only
  real Studio Pro load catches it" shape as [[BUG-58]] and [[BUG-59]].

### Workaround

Hand-rewire the affected `CALL JAVA ACTION` activities in Studio Pro: open each one, clear and
re-set the `ActionMicroflow` parameter using Studio Pro's own microflow picker (not a typed
string) and confirm `ContextObject`'s generic entity binding. No mxcli/MDL route currently
produces the correct BSON shape for this Java action's typed parameters.

### Detection

Any `CALL JAVA ACTION` against a Java action with a `MicroflowType` or generic
(`EntityTypeParameterType`) parameter should be verified via `mxcli bson dump --type microflow
--object <Module.Microflow>` after exec — grep the `ParameterMappings` for the parameter name
and confirm it landed as `Microflows$MicroflowParameterValue` / an
`EntityTypeCodeActionParameterValue` with an `Entity` field, not
`Microflows$BasicCodeActionParameterValue`. If it's the latter, expect `CE0115`/`CE0126` in
Studio Pro regardless of clean `mxcli check`.

### Related

Same "clean `mxcli check`, real Studio Pro/mxbuild catches it" blind spot as [[BUG-58]] and
[[BUG-59]]. Distinct from either — this is a **parameter-type misclassification in the
`CALL JAVA ACTION` builder**, not an association-grant gap or a bad attribute-expression shape.

**Discovered:** 2026-08-07, TFC-TCXGraphPOC-main, while diagnosing recurring CE0115/CE0126 on
`AgentCommons.ChatContext_Create_ForAgent` calls added in Batch 5 of the audit remediation
(`DS_GraphAgent_ChatContext`, `DS_TCCopilot_ChatContext`, `DS_TFCAssistant_ChatContext`).

---

