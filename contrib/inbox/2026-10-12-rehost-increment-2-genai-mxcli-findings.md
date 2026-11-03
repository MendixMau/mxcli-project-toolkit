# mxcli v0.26.0 defects found regenerating the GenAI Showcase App (Rehost increment 2)

**From:** MendixMau — Rehost increment 2 on mendix/genai-showcase-app (MIT) (split from #293)
**Date:** 2026-10-12
**Kind:** bug
**Field evidence:** captures not committed (lab run, #293); Mendix 11.12.0 source, 36 modules regenerated into `mxcli new --version 11.12.0`; Linux container, no Studio Pro
**Proposed target:** `bug-logs/mxcli-bugs.md` (one BUG-n each); upstream drafts in `bug-logs/pending-github-issues/2026-10-12-mxcli-0.26-round-trip-report.md`; extractor items to `pipelines/mendix-mpr/`

---

Format: defect — verbatim message — repro — workaround.

## mxcli defects

- **`-c describe module … with all` truncates at 10 000 lines, silently**, mid-statement (AgentCommons). Workaround: drop the incomplete statement, describe the missing documents one by one.
- **`with all` leaves document types out**: nanoflows, snippets, JS actions, JSON structures, mappings, task queues, image collections, some pages (10 of 22 in AgentCommons). Workaround: `project-tree` fill-in.
- **`describe java action` puts the parameter separator after the `--` comment**: `Name: String not null  -- This sets the Name…,` → `mismatched input 'Name' expecting ')'`.
- **A microflow created before a Java action of the same name**: `refusing to write unit …: attribute reference not qualified`. Workaround: create the action first.
- **A grant naming an association member before the association exists**: `entity EchoConnector.Credentials has no member(s) Credentials_Configuration`. Workaround: order grants after associations.
- **Message definitions cannot be expressed**: `message definition "GenAICommons.MD_Reference.Reference" not found — this project has no message definitions` → 4 × CE1613 at mxbuild. No workaround.
- **A Mendix 9-built MPK cannot be installed into 11**: `mx module-import failed: exit status 117` / `created with version 9.24.2 … open it in any version in the range from 10.21.0 to 10.24.99 first`. Workaround: regenerate from source.
- **The source's stamped marketplace version is gone**: `version "1.5.1" not found`; oldest listed is 3.0.0.
- **No headless update for a module already present**; `mxcli new --version 11.12.0` ships Administration 4.3.2, source has 4.5.0.
- **#923 (known): merges and decisions** describe with WARNING lines and layout drift.
- **NEW — `import from mapping` result written with a null entity; the `.mpr` no longer loads**: `System.ArgumentNullException … EntityType.set_EntityId`. Seen when the flow ran ahead of its import mapping (cause is a hypothesis). Workaround: `drop microflow` + `create or modify` in one script once the mapping exists.
- **NEW — Java action type parameter described as `MxObject: "Entity"`; exec writes entity `.Entity`**: `The selected entity '.Entity' no longer exists.` (7 build errors). JS actions too.
- **NEW — sort on an inherited attribute written against the specialization**: `CE1613 "The selected attribute '…BookChunk.Similarity' no longer exists."`; describe is identical, so a describe-only check misses it.
- **NEW — rules cannot be described or created**: `describe rule …` → `Unknown type: rule`; `show rules` lists 14. 8 flows deferred.
- **NEW — describe emits MDL its own `check` rejects** (30 documents): MDL-WIDGET24 ContentParams `$ChatContext/Topic`; MDL-FLOW02 `merge shared1: nothing joins it`; MDL081 layout without placeholders; MDL-WIDGET18 `DecimalPrecision … &{-1}`; MDL-PAGEARG01 button outside a data view.
- **NEW — forward references refused inside one script, so mutual recursion cannot be created**: `references microflow X before it is created`. Hypothesis: create-stub-then-modify.
- **NEW — describe output fails validation**: `variable 'SumDuration' is not declared`.
- **Seen, not isolated:** System Java actions unknown to mxcli; mapping `root (Wrapper)` → `extraneous input '('`; `format (decimalPrecision: -1)` → `no viable alternative`.

## Toolkit (extractor) items

- `lib/quarantine-mdl.py` does not map lint-form errors and trusts mxcli's `statement N:`, which differs from `lib/mdlsplit.py` (e.g. 48 vs 49).
- `rehost-extract.sh` `check_exec`: when nothing can be quarantined, the rest is neither executed nor deferred (run 4 lost 7 modules, 1040 statements).
- The deferred comment nests on every retry; the `never executed` count is 7× too high.
- The ledger denominator does not count rules.
