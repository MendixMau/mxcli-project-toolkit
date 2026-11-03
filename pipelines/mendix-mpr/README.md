# Mendix MPR pipeline — the Rehost extractor

**Source platform:** an existing Mendix app (`.mpr`, Mendix 9 and above, MPR v1 or v2).
**What it does:** read a model with `mxcli describe`, regenerate it as MDL into a fresh target
app, and write a **fidelity ledger** (one row per source document; the denominator in the header)
instead of claiming 100 %.
The judgement around it lives in the skills: `skills/rehost-app.md` (when to rehost, the
check/exec loop, reading the ledger, done) and `skills/decompose-app.md` (splitting an app by MPK).

This is the only pipeline whose extractor reads a Mendix model. Downstream of the ledger nothing
here is Mendix-source-specific: the slice loop of the Decompose track reuses it to move a
module into a new app, and Stages 2–6 of the runbook apply unchanged.

## Run

```
MXCLI=/path/to/mxcli pipelines/mendix-mpr/rehost-extract.sh <source.mpr> <target.mpr> <out-dir> [Module ...]
```

- The target must exist: `mxcli new <App> --version <same as source> --theme none`. The script
  writes model content only; run the mxbuild gate (`project-bin/exec.sh`, or
  `~/.mxcli/mxbuild/<ver>/modeler/mx check`) afterwards.
- Modules default to every own module (empty Source column in `list modules`, System excluded;
  parsed by `lib/own-modules.awk`, fixture `tests/wave2/test-rehost-list-modules.sh` over verbatim
  captures). No own module and no module argument: exit 2. A target that resolves to the source
  file: exit 2, before anything is written.
  Marketplace modules are recorded by name and version on the ledger, never regenerated.
- Output: `captures/` (verbatim mxcli output — the golden fixtures), `mdl/` (describe output,
  the topologically ordered file that was executed, the target's describe for the diff),
  `fidelity-ledger.tsv`.

`lib/topo-order-mdl.py` reorders the flow statements of a `describe module … with all` script so
every callee is created before its caller (a flow and its `grant execute` lines move as one unit).
`lib/compare-mdl.py` normalises two describe outputs for the per-document identical/drift verdict.
Both read and write with `newline=''`: Studio Pro stores annotation text with CRLF inside MDL string
literals, and a tool that normalises it changes the flow and `exec` refuses the splice.

## Field runs

All on public apps, Linux container, mxcli v0.26.0 unless noted. **Not verified:** macOS (the
script avoids bash-4 features and GNU-only `date`, but no run happened there) and the two-tree
layout (`.mpr` under `app/`) — the script takes explicit `.mpr` paths, so layout should not
matter, but no run proved it.

| Date | Source (by app type) | Result |
|---|---|---|
| 2026-10-12 | Banking sample app (Mendix 11.13.0; one own module of 151 documents + MyFirstModule 4) → `mxcli new --version 11.13.0` | 155/155 documents emitted, 154 identical on target describe, 1 doc-comment drift; `mx check` 0 errors, mxbuild BUILD SUCCEEDED, `diff --format struct` empty. 35 s end to end |
| 2026-10-12 | Field-service template (Mendix 9.24.2, MPR v1, 64 MB) — **read probe only** | `list modules` 1.6 s, `graph-report` 18 s |
| 2026-10-12 | GenAI showcase app (Mendix 11.12.0; 48 modules: 32 own + 15 marketplace; 456 entities, 1622 microflows, 180 pages, 204 Java actions) → `mxcli new --version 11.12.0` | **Measured, not build-green.** 36 modules regenerated, 36 min (describes reused). Ledger over 2776 documents: 579 identical, 271 drift, 1993 failed-exec, 43 not-emitted, 4 not-expressible, 2 target-extra. 1520 failures were 7 whole modules dropped because check errors could not be mapped to a statement (fixed since: `lib/exec-each.py`). Target then failed `mx check` (14 × CE1613) and mxbuild |
| 2026-10-13 | Same GenAI showcase app on an mxcli nightly build, with the statement-mapping fixes | **36/36 modules landed, not build-green.** 1537 identical, 858 drift, 482 failed-exec, 4 not-emitted, 9 not-expressible. The target does not load (`ArgumentNullException` on one snippet parameter mxcli stored wrongly); with it replaced, `mx check` 42 × CE1613 in 5 classes. 2 h 36 min with reused describes. Journeys not run (needs live LLM credentials) |
| 2026-10-12 | Field-service template — **MPK route** (`export-module-mpk.py`): three utility/visualisation modules → 10.24 and 11.13 | All installed; every residual `mx check` error a crossing edge to a module the target lacks; one module with its edges satisfied: `mx check` 0, mxbuild BUILD SUCCEEDED on 11.13 after 3 Java edits |
| 2026-10-12 → 13 | Field-service template — **slices moved out of the monolith** (a native notes module; an asset/parts group of 4 modules; a dispatch/workforce group of 5) | Each slice `mx check` 0 and BUILD SUCCEEDED on 11.13; seams over published OData + REST, proven by Playwright journeys across both apps. These runs exercise the whole decompose loop, not this extractor alone |

Not yet exercised: workflows, REST/OData services, and the MDL regenerate step on a Mendix 9/10
source (the read works; the native slice moved into Mendix 11 by MPK, not by regeneration).

## The MPK route — `export-module-mpk.py` (moving a module without regenerating it)

```
python3 -I pipelines/mendix-mpr/export-module-mpk.py <source.mpr> <Module> <out.mpk> [--no-widgets] [--scrub-constant-defaults] [--json]
mxcli marketplace install --file <out.mpk> -p <target.mpr>      # new modules only; no PAT
```

The exporter writes a module package in Mendix's own format: a zip with `package.xml` and a
`project.mpr`. That `project.mpr` holds the source schema and `_MetaData` verbatim, the module's
unit subtree byte for byte, the project root, the conversion unit and
four project documents.

**Module constant defaults travel in the MPK** unless you pass `--scrub-constant-defaults`. A key
or password kept as a constant's default value is in the package as plain text by default.

**What is scrubbed, exactly** (each scrubbed unit gets a recomputed ContentsHash):

| Unit | Emptied | Kept |
|---|---|---|
| Project security | demo users, user roles, admin password, admin and guest role; demo users and guest access switched off; security level set to `CheckNothing` (off) | everything else in the document |
| Project settings | per-configuration constant values, custom settings, database URL / user / password; certificates; after-startup, before-shutdown and health-check microflow names | other settings |
| Navigation | every navigation profile | the document shell |
| The module's own constants | **nothing by default** (the field-proven path). With `--scrub-constant-defaults`: `DefaultValue` of every constant; the run prints how many (`constant defaults emptied: N`). **Unverified in Studio Pro: not yet installed and checked** | everything by default; with the flag, every field but `DefaultValue` |

**Not scrubbed:** module constant defaults (without the flag), string literals inside microflows, pages, Java/JavaScript code, `resources/`
files and REST/OData locations: a secret written there travels in the package. Read the module
before handing the `.mpk` on. With `--scrub-constant-defaults`, an emptied non-String
constant (Integer, Boolean …) will need a value in the target; how `mx check` reports an empty one
is not yet measured.

The script refuses (exit 2), before writing anything, when the output path is the source `.mpr`
and when it is given an option it does not know (a typo such as `--scrub-constants` would
otherwise export with every constant default in it).
The zip also carries the module's `javasource/`,
`javascriptsource/`, `themesource/` and `resources/` folders, the userlib jars that have a
`.<Module>.RequiredLib` marker, and the widget `.mpk` files its pages reference. The script header
lists what it cannot know. It refuses MPR v2 sources and schemas that differ from the reference.

**Version window (Mendix's, not ours).** `mxcli marketplace install` imports through the target's
`mx module-import`:

- 9.24's `mx` has no `module-import`.
- 11.13 refuses packages older than 10.21.
- So a 9.x → 11.x move has two hops: `mx convert` a copy of the source to 10.24, export, then install.

On Mendix 10 and 11, `mx create-module-package <mpr> <Module>` is Mendix's own headless export.
It refuses modules that have errors, and it **regenerates every unit and entity ID**. This
exporter keeps them, and mxcli's install keeps them too: measured from 9.24 through 10.24 to 11.13.

**Field run 2026-10-12, field-service template (Mendix 9.24.2):**

- Three modules (a feature-toggle module, a utilities module, a charts module) each installed
  into 10.24 and into 11.13.
- Every `mx check` error (2 / 7 / 134) was a crossing edge to a module the target lacks. There
  were 0 version-conversion errors and 0 package-format errors.
- The utilities module with its edges satisfied (3 Marketplace modules, 1 constant in MDL) reached `mx check`
  0 errors. After three Java hand-off edits, mxbuild BUILD SUCCEEDED on 11.13.0. The edits:
  `this.context()` is a Mendix 9 API; two orphan action files used `CustomJavaAction`; one jar's
  RequiredLib marker names a former module.
- The Java bodies arrive byte-identical.

Captures of these runs are not committed here (the pipeline ships code only). For Mendix 9 `mx` on Linux, the container needs `libgdiplus` and JDK 17.

## mxcli findings from the first run (mxcli v0.26.0)

The subcommand `mxcli describe module <M>` emits only the module and its roles; the whole-module
emitter is the MDL statement `describe module <M> with all` via `-c`. Describe output is in catalog
order and the tool's own `check` refuses it (MDL-ORDER01). Image collections are omitted by
`with all`. `describe userrole` drops `CheckSecurity: false`. Demo-user passwords describe as
`'***'` and project security level describes as a report, not MDL — both are ledger hand-off rows.
