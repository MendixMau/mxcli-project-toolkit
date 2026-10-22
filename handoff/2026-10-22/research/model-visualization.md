# Visualizing the Mendix model (domain model, microflows, model diffs) as HTML or Mermaid

**Date:** 2026-10-21. **Scope:** research and a throwaway prototype. Nothing in the toolkit or the mxcli tree was changed.
**Inputs used:** the toolkit clone (read-only), the public mxcli source, and the public test models
`testdata/pedapp` (Mendix 11.13, 8 modules, 370 units) and `testdata/testapp-views` (Mendix 11.14). No client model was used.

## TL;DR

Yes, and at Studio Pro fidelity. An MPR v2 project stores every document as its own BSON file
under `mprcontents/`, and those files keep the layout Studio Pro saved:

- each entity's `Location`;
- each association's connection points, as edge percentages;
- each microflow object's `RelativeMiddlePoint` and `Size`;
- each flow's connection side and Bezier control vectors.

A stdlib-only Python reader turns that into a graph, and inline SVG draws it at the stored
coordinates. The prototype does this in **about 2.3 s end to end** for two models plus a
two-revision diff. It produces a **117 KB** single HTML file. It took about 35 minutes of
agent time to write. The pictures read like Studio Pro: same positions, same curves, the
same decision and merge diamonds, loop containers and annotations.

Two findings change the plan:

1. **mxcli already ships diagram output.** `mxcli describe --format mermaid` covers entity,
   domain model, microflow, nanoflow and page. `--format elk` covers domain model, entity
   focus, microflow, nanoflow and `systemoverview`, and emits JSON for elkjs. The `vscode-mdl`
   extension in the mxcli repo renders both in a VS Code webview through its **Show Diagram**
   command. Both formats **discard Studio Pro's positions and re-lay the diagram out**. The
   stored positions are still printed in plain MDL `DESCRIBE` output, as `@Position(x, y)`
   for entities and `@position(x, y)` for activities.
2. **Model diffs are where a picture earns its place.** `git diff` on two `.mxunit` revisions
   says only `Bin 10663 -> 10663 bytes`. A diff by element `$ID`, drawn over the "after"
   diagram with ghosts of the "before" positions, shows "entity moved, attribute renamed,
   activity moved and recaptioned" at a glance. The Studio Pro Comparison pane is textual,
   and a visual microflow diff is still an open idea on the Mendix forum.

**Recommended first step:** a read-only `bin/model-view.sh` with an on-demand Python or Node core.
It renders one module, or the changed documents between two git refs, to
`analysis/model-view.html`. The core reuses `project-bin/mxunit_bson.py`, the toolkit's existing
BSON codec. Mermaid stays for the auto-laid-out call graph and for PR comments.

---

## 1. What already exists

### Toolkit (`<toolkit clone>`)

| Surface | What it draws | Data source |
|---|---|---|
| `skills/architecture-blueprint.md` | Mermaid layer, wiring, state and journey diagrams inside `blueprint.md`, plus a generated `blueprint.html` (Step 7, `<pre class="mermaid">` or pre-rendered with mermaid-cli) | hand-written from BRDs (target architecture) |
| `bin/app-layer-map.sh` -> `analysis/app-layer-map.html` | module layer order and back-edges (deliberately not a hairball) | `analysis/app-facts/dependencies.json` from `project-bin/app-facts.sh` (catalog) |
| `bin/app-report.sh` -> `analysis/app-report.html` | app dossier, health, severity | catalog facts |
| `docs/pipeline-walks.html` | process flowcharts per entry mode (Mermaid) | static |
| `docs/architecture-views-design-note.md` | **verdicts:** a full ERD is rejected "at app scale (799 entities)" and allowed per slice; a full microflow call graph is rejected (2,686 nodes, no stage asks) | — |
| `project-bin/mxunit_bson.py` | none. It is an order-preserving BSON codec for `.mxunit`, measured byte-identical on 1068 of 1069 units | reusable reader for this work |
| `bin/gate-check.sh` | regenerates the project `index.html` dashboard | register and files |

The design note matters. Any model view must be **scoped** (a module, a slice, or a diff), not
a whole-app dump, or it repeats the rejected hairball.

### mxcli (`<mxcli clone>`)

| Command | Output | Positions? | Notes |
|---|---|---|---|
| `describe [entity\|microflow\|nanoflow\|page] X` (MDL) | MDL text | **yes**: `@Position(x, y)` on entities (`cmd_entities_describe.go:238`), `@position(x, y)` on activities (`cmd_microflows_show_helpers.go:879`) | round-trippable; parsing MDL text for coordinates is possible but fragile |
| `describe --format mermaid entity Mod.X` | `erDiagram` for the module, plus `%% @colors {...}` metadata for webview colouring | no | `mdl/executor/cmd_mermaid.go` |
| `describe --format mermaid microflow\|nanoflow\|page X` | `flowchart LR` (page = widget tree) | no | same file |
| `describe --format elk domainmodel\|entity\|microflow\|nanoflow X`, `systemoverview` | JSON nodes and edges with sizes, loop children as compound nodes, optional `mdlSource` and `sourceMap` | no (elkjs re-lays out) | `cmd_domainmodel_elk.go`, `cmd_microflow_elk.go` |
| `describe --format json ...` | JSON | varies | `exec.SetFormat(FormatJSON)` |
| `REFRESH CATALOG FULL` + `CATALOG.ENTITIES/ASSOCIATIONS/MICROFLOWS/REFS`, `graph-report --format json` | tables | **no** | best for call graph and wiring at scale; FULL refresh is slow on big apps |
| `diff-local --ref A..B --format unified\|side\|struct` | MDL text diff of changed `mxunit` files between git refs (MPR v2 only) | in MDL, yes | the textual counterpart of the visual diff below |
| `serve` | HTTP module treemap | — | not a model diagram |
| `vscode-mdl/` extension | `mendix.previewDiagram`, "Show Diagram" and "Show Diagram with Source": webview with Mermaid 11 and elkjs 0.9.3 from jsdelivr, with renderers for domain model, microflow, module overview, page wireframe and query plan | relayout | `vscode-mdl/src/preview/*` |

No mxcli binary was available in this environment, and none was built (per the rules). The
mxcli rows above come from reading the source and are not runtime-verified.

## 2. Data source comparison (question 1)

| Rank | Source | Cost | Lossless? | Layout | Works on a git revision without checkout? | Dependencies | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | **Parse `mprcontents/**/*.mxunit` (BSON) + `.mpr` SQLite `Unit` table for containment** | **0.57 s for 370 units** (pedapp), linear; `git cat-file --batch` reads a revision in about 0.5 s | **yes**: the raw model | **kept exactly**: entity `Location`, association `ParentConnection`/`ChildConnection` (percent of box), object `RelativeMiddlePoint`/`Size` (loop children relative to the loop's top-left), flow `Origin`/`DestinationConnectionIndex` (0 top, 1 right, 2 bottom, 3 left) + `BezierCurve` control vectors | **yes** | stdlib only (`sqlite3` + a 25-line BSON decoder; the toolkit already has `mxunit_bson.py`) | **Best for drawing and diffing.** Risk: the schema is undocumented and changes across Mendix versions, and entity box sizes are not stored (mxcli's own `sdk/domainmodel/connection.go` says so). MPR v1 keeps unit BSON in the SQLite file instead; it is readable the same way but needs a second code path. |
| 2 | `mxcli describe` (MDL) per document, batched in one `exec` or REPL session | one process per call unless batched; the project is opened each time | yes for semantics | `@position` kept, but as text to re-parse | needs a checkout per revision (or `diff-local`) | mxcli at the project's pinned version | Good for **semantics and labels** (it resolves names, captions and expressions correctly across versions). Use it for text, not for coordinates. |
| 3 | `mxcli describe --format elk\|mermaid` | same as above | partial (labels and details) | **discarded**; elkjs or Mermaid re-lays out | no | mxcli | **Zero-effort** for "a readable picture of one flow", and already wired into VS Code. Not Studio Pro-faithful. |
| 4 | `mx dump-mpr` (official Mendix CLI, 10.4+; `--unit-type`, `--module-names` 10.16+) | JVM/.NET start-up; needs the version-matched mxbuild download (the toolkit's `mxcli setup mxbuild` already does this) | **yes**: official JSON of the raw model | kept | no | mxbuild for that exact Mendix version | The **officially supported** route to the same raw data as option 1. Worth a field probe as a fallback when the BSON schema drifts. Not tested here (no `mx` binary). |
| 5 | Catalog (`REFRESH CATALOG FULL`, `CATALOG.REFS`, `graph-report --format json`) | FULL refresh can be minutes on a large app (`app-facts.sh` measured 178 s end to end on a 107-module app) | no (metadata; top-level activities only, per the toolkit's `app-analysis` notes) | none | no | mxcli | Best for the **call graph, page-to-microflow wiring and counts**. The toolkit already collects it (`app-facts.sh`). |
| 6 | Mendix Model SDK / Platform SDK | network round trip; a working copy per open | yes | kept | only for what is on Team Server | `MENDIX_TOKEN` PAT, cloud access, Node | **No.** It needs a cloud token, sends client model content to Mendix's working-copy service, and does not work offline or on a local uncommitted model. |

## 3. Rendering options (question 2)

| Option | Fidelity to Studio Pro | Effort | Dependencies | Host support |
|---|---|---|---|---|
| **Custom inline SVG at stored coordinates** (prototype) | **High.** Same positions, Bezier curves from stored control vectors, diamonds, loop boxes, annotations, error flows dashed red, entity header colour by kind (persistent, non-persistent, view, external), multiplicities, generalization tag | Medium. About 300 lines of renderer; entity box size must be estimated because it is not stored | none (static SVG, works offline, no CDN) | **every** HTML host: Claude artifact, VS Code webview, Simple Browser, Codex in-app browser, any browser. Not GitHub comments (GitHub sanitises inline SVG in markdown). |
| Mermaid `erDiagram` (mxcli `--format mermaid` or the prototype's `er_mermaid`) | Low to medium. Auto layout, no positions, no generalization arrow style, gets crowded beyond about 15 entities | **Zero** (mxcli emits it) | mermaid.js | GitHub issues, PRs and `.md` files; Claude artifacts; VS Code Markdown preview (Mermaid is reported built in from VS Code 1.121; earlier versions need the `bierner.markdown-mermaid` extension); Cursor and Windsurf (bundled renderer reported on an older Mermaid) |
| Mermaid `flowchart` for a microflow | Low. Dagre layout, no positions; loops flattened; long flows become very wide | zero | mermaid.js | same as above |
| **Mermaid flowchart for the call graph and page-to-microflow wiring** | n/a (Studio Pro has no such view) | low | mermaid.js | same, and the best fit for PR comments |
| ELK JSON + elkjs (mxcli `--format elk`, vscode-mdl `elkTemplate.ts`) | Medium. Orthogonal routing, compound loop nodes, clean but not Studio Pro's layout | zero to use; the webview template already exists in `vscode-mdl` | elkjs (jsdelivr) | VS Code (vscode-mdl), Claude artifact (jsdelivr is allowed) |
| Graphviz (viz.js / `@hpcc-js/wasm`) | Low to medium (`neato -n` can honour positions) | low to medium | WASM about 2 MB, or a `dot` binary (absent here and on most Windows) | any browser; heavy |
| React Flow / Cytoscape.js | Medium to high (positions can be honoured; pan, zoom, interaction) | high (a build step, React) | npm bundle | browser and webview; overkill for a static report |
| **Visual diff** (prototype): "after" SVG with green added, amber moved or changed, a dashed ghost at the old position, removed elements as red ghosts, plus a change list | **High.** Nothing comparable exists in Studio Pro, whose Comparison pane is textual | medium (diff by `$ID` over extracted graphs) | none | every HTML host; for a PR, post the change list + a Mermaid summary and link the HTML |

## 4. Where it shows, per host (question 3)

| Host | How a page or diagram is shown | Mermaid | Self-contained HTML + SVG | Notes |
|---|---|---|---|---|
| **Claude Code**: private Artifact | `Artifact` publish of one `.html`, private by default; scripts only from cdnjs, jsdelivr, unpkg and similar; 16 MB page limit | yes (load mermaid from jsdelivr or cdnjs at a pinned version) | **yes** (inline SVG needs nothing) | Publishing is still a publish, even when private: client model content leaves the machine. **Opt-in only.** |
| Claude Code: terminal / desktop | file card or `open analysis/model-view.html`; the desktop built-in browser pane can open local files | via the CDN script (needs network) | yes | the zero-risk default: a local file |
| **VS Code (incl. Copilot agent mode)** | (a) the `vscode-mdl` "Show Diagram" webview (Mermaid and ELK, relayout); (b) a custom webview panel (`createWebviewPanel`, CSP, `asWebviewUri`); (c) **Simple Browser** (`simpleBrowser.show`) on a localhost URL; (d) Markdown preview with a ```mermaid block | Markdown preview: built in from 1.121 (reported), otherwise the bierner extension | yes, through a webview or a local server (Simple Browser cannot open `file://`; serve it, for example with `python3 -m http.server`) | the agent itself cannot "see" the render without a browser tool; the human can |
| Cursor, Windsurf | VS Code forks: the same webview, Simple Browser and Markdown preview; Cursor has a built-in Mermaid renderer (reported on an older Mermaid) and a built-in browser | yes | yes | the `vscode-mdl` VSIX should install (untested) |
| **Codex** | CLI: none (it writes a file). IDE extension (VS Code, Cursor, Windsurf): the host's webview and preview. **Codex app**: an in-app browser for "file-backed previews" and localhost (since about April 2026) | via the host or the in-app browser | yes, as a file preview | no artifact-style hosting; the HTML file is the deliverable |
| **GitHub PR / issue comments** | Markdown with ```mermaid fences, rendered natively since February 2022 (issues, PRs, discussions, gists, wikis) | **yes** | no (inline SVG and scripts are stripped) | the model-diff surface: a CI step posts the change list + a small Mermaid "changed documents" graph, and attaches the HTML as a build artifact |

## 5. Prototype results

| Item | Value |
|---|---|
| Prototype page | `<scratchpad>/research/model-viz/model-viewer.html` (117 KB) |
| Scripts (scratch only) | `<scratchpad>/research/model-viz/bsonlite.py` (25 lines), `extract.py` (180), `render.py` (315) |
| Screenshots | `<scratchpad>/research/shots/card5.png` (VAL_Feedback, 29 objects), `card10.png` (ChangeMyPassword), `card38.png` (loop + split, testapp-views), `card48.png` and `card49.png` (diff) |
| Inputs | public `testdata/pedapp` and `testdata/testapp-views`; a scratch git repo (`model-viz/gitdemo`) holding a copy of pedapp with a second commit that byte-patches same-length edits: move entity `Feedback`, rename attribute `Subject` -> `Summary`, move and recaption one microflow activity |
| Extract, one working tree (370 units) | 0.57 s |
| Extract, one git revision via `git cat-file --batch` | about 0.5 s |
| Render (2 models, 45 SVGs, 1 diff) | 4 ms |
| **Whole pipeline** (2 working trees + 2 revisions + render) | **2.3 s** |
| Browser load (headless Chromium) | under 1 s for the SVG content |
| Authoring time | about 35 min (BSON exploration 10, extractor 10, renderer 10, polish 5) |

**What it shows.**

- **Domain models:** one SVG per module at the stored positions. The entity header is coloured
  by kind (persistent, non-persistent, view, external), attributes are typed, and associations
  attach at Studio Pro's stored connection percentages with `*`/`1` multiplicities and names.
  A generalization shows as a header tag (for example `▲ System.User`), and cross-module
  associations show as stubs.
- **Microflows and nanoflows:** all 37 (29 + 8) at the stored coordinates.
  - Start (green) and end (red) events, return values under the end events.
  - Action activities with derived captions ("Retrieve AccountPasswordData_Account",
    "Java VerifyPassword", "Show page ChangePasswordForm").
  - Decision and merge diamonds with their expressions.
  - Loops as dashed containers holding their children, and parameters.
  - Annotations as yellow notes.
  - `true`/`false` case labels on the curves; error-handler flows dashed red.
  - `card5.png` (29 objects) is visually very close to Studio Pro's own layout of that flow.
- **Call graph and wiring:** a Mermaid `flowchart LR` with microflow, nanoflow and page node
  shapes and `calls`/`opens`/`uses` edges (39 edges in pedapp).
- **Fidelity comparison:** the largest flow as an auto-laid-out Mermaid flowchart, next to the
  positioned SVG, plus a Mermaid `erDiagram`.
- **Diff:** a change list ("~ entity FeedbackModule.Feedback moved [410, 240] -> [690, 240]",
  "~ attribute ... Subject -> Summary", "~ ... caption 'Save password' -> 'Save new pass'"),
  plus the "after" diagrams with a dashed ghost at the old position and highlighted changes.
  `git diff --stat` on the same commits says only `Bin 10663 -> 10663 bytes`.

**Not verified here.** jsdelivr is blocked by this sandbox's egress proxy, so the six Mermaid
blocks were not seen rendered. The page degrades to showing their source, and the SVG
sections are unaffected. In a Claude artifact or an online browser they load from
`cdn.jsdelivr.net/npm/mermaid@11.4.1`.

**Known rough edges.**

- Entity box sizes are estimated; Studio Pro stores none.
- Long captions are truncated rather than auto-sized.
- Captions are derived for common action types only.
- The diff demo covers move, rename and recaption. Add and remove are implemented by `$ID`
  set difference but were not field-tested, because a byte-patch cannot add elements.
- Pages are drawn only as wiring nodes. mxcli's `pageWireframeRenderer.ts` is the place to
  borrow from.
- Rules and workflows are not drawn.

## 6. Cost, performance, privacy (question 4)

- **Never on the exec happy path.** It is an on-demand or report-time step: run by hand, from
  `bin/app-report.sh` or the dashboard regeneration, or in CI on a PR. Reading `mprcontents`
  needs no mxcli process and no catalog. The only safety rule is to read while Studio Pro is
  not mid-save; read from a git revision when in doubt.
- **Scale.**
  - Extraction is linear: about 1.5 ms per unit. A 10k-unit app takes about 15 s.
  - Each diagram is about 2.5 KB of SVG, so 3,000 microflows would be about 7.5 MB in one
    page. That fits the 16 MB artifact limit but is unreadable, and the toolkit's own design
    note already rejects whole-app views.
  - **Scope by default:** one module, one slice (`--docs`), or only the documents changed
    between two refs.
  - For a large module, embed the JSON and render on expand (`<details>` already does this
    lazily for display).
  - Mermaid has its own ceilings (`maxTextSize` default 50 k, `maxEdges` 500). Keep Mermaid
    for small call graphs and PR summaries.
- **Privacy.**
  - Model content is client data. A local HTML file under the project's gitignored
    `analysis/` is the default.
  - Publishing it as a Claude artifact, even a private one, or posting it as a GitHub comment
    is a publish and needs explicit opt-in. The leak guard (`bin/check-no-client-data.sh`)
    should cover `analysis/model-view*.html` if anyone tries to commit one into the toolkit.
  - PR comments should carry document names and change types, not attribute lists, unless the
    repo is already the client's own private repo.
  - The Model SDK path is out on privacy grounds as well as cost.

## 7. Minimal design for the toolkit (question 5)

**Placement.**

- The instrument reads a model, not a source stack. Per `CLAUDE.md` "Writing in this toolkit"
  it therefore belongs in `bin/`, with judgement left to a skill.
- `bin/model-view.sh <project-dir> [--module M | --docs A,B | --diff REF_A..REF_B] [-o out.html] [--mermaid-only]`
  is a thin bash wrapper. It resolves the `.mpr` through `_common.sh`, using config-derived
  roots for both layouts (single tree and two tree, `.mpr` under `app/`).
- The core is `bin/lib/model-view.py`, or a Node equivalent. It reuses `project-bin/mxunit_bson.py`,
  moved or shared into `bin/lib/`, and uses only the stdlib, with no CDN for the SVG part.
- Output goes to `analysis/model-view.html` (gitignored) plus `analysis/model-view.json`, the
  extracted graph, so agents read numbers instead of the HTML.
- `--mermaid-only` prints Mermaid to stdout for PR comments and Markdown.
- A short skill section, in `skills/existing-app-change.md` or a new
  `skills/model-visualization.md`, says **when** to look: Stage 0 blast radius on the slice's
  documents, the Stage 5 LOOK step after a module build, PR review of model changes. It also
  says what never to do: whole-app ERDs, or publishing without opt-in.

**Hooks.**

- **Dashboard and `gate-check` `index.html`:** a link card "Model view (generated <date>)"
  shown only when the file exists. No new obligation, so there is no new gate.
- **`bin/app-report.sh`:** a per-finding link to the offending microflow's diagram anchor
  (`model-view.html#mf-Module.Name`). This turns a loop-in-loop finding into a picture.
- **Stage 5 module build (LOOK):** `--diff <pre-build snapshot commit>..HEAD --module M` shows
  exactly what the build changed. That doubles as a human review aid at the module gate.
- **PR / CI (optional, later):** a GitHub Action posts the change list + a Mermaid
  changed-documents graph and uploads the HTML as a workflow artifact.

**Field-proof (CLAUDE.md "Shipping an instrument").**

1. **Golden input is captured:** the fixtures are `mxunit` files from the public
   `mendixlabs/mxcli` `testdata/pedapp` and `testapp-views`. The count assertions for pedapp
   are 8 modules; 7 entities across 4 modules; 1 association; 29 microflows and nanoflows
   (16 + 13); 20 pages and snippets; and 39 wiring edges. For testapp-views they are
   1 view entity, and a loop with 1 child. Add one
   Mendix 10.x model so a second schema version is covered.
2. **Both layouts:** probe a single-tree checkout and a two-tree one (`.mpr` under `app/`)
   through `_common.sh`.
3. **Both platforms:**
   - Windows Git Bash: `python3` may be absent and only `py` or `python` present, so probe
     for it, or write the core in Node, which the pipelines already require.
   - `git cat-file --batch` works on both. Use `sqlite3` from Python's stdlib, never the
     `sqlite3` CLI.
   - No mac-only tools are involved.
4. **One field run, cited:** run against one real project (named in the commit, not in the
   toolkit) and record its unit count, time and page size.
5. **Producer for every consumer:** the input is the `.mpr` itself; no upstream artifact is
   needed.

The diff mode's producer is the exec snapshot / git commit that `bin/exec.sh` already makes.

## 8. Risks and open questions

1. **BSON schema drift across Mendix versions (9.x, 10.x, 11.x).** The extractor reads about
   15 field names. Should it fall back to `mx dump-mpr` JSON when a required key is missing?
   Should it stop with a printed "unsupported unit shape" instead of guessing?
2. **MPR v1 apps** (pre-10.18 or not yet converted): their unit BSON lives in the SQLite file.
   Support them, or require v2? Studio Pro 10.22+ converts automatically.
3. **Upstream or toolkit?** mxcli already owns `--format mermaid|elk` and the VS Code preview.
   A `--format svg` that honours stored positions, or an `--keep-positions` ELK option (elkjs
   supports fixed positions through `org.eclipse.elk.fixed`), may belong **upstream**. That
   way the VS Code extension gains Studio Pro-faithful diagrams for free. Should the toolkit
   prototype it in `bin/` first and then offer a PR, as with the marketplace-install precedent?
4. **Studio Pro rendering details** not reproduced: action icons, exact entity widths, the
   colours of event and system entities, page wireframes. Is "recognisable" enough, or is
   pixel-likeness a goal?
5. **Diff semantics:** an element is identified by `$ID`. A delete-and-recreate in Studio Pro
   reads as remove + add. The `GUID` is stable for attributes and entities and could pair them.
6. **Mermaid in VS Code Markdown preview:** "built in from 1.121" comes from secondary
   sources. It needs one check on a real install.
7. **Agents seeing the picture:** to judge a diagram, an agent needs a browser or screenshot
   tool (Claude in Chrome, the built-in browser, Playwright, or the Codex in-app browser).
   The JSON sidecar is what agents should reason over.

## 9. Sources

Local:

- toolkit `skills/architecture-blueprint.md`, `docs/architecture-views-design-note.md`,
  `bin/app-layer-map.sh`, `project-bin/mxunit_bson.py`, `CLAUDE.md`
- mxcli `mdl/executor/cmd_mermaid.go`, `cmd_microflow_elk.go`, `cmd_domainmodel_elk.go`,
  `cmd_entities_describe.go`, `cmd_microflows_show_helpers.go`, `cmd/mxcli/cmd_describe.go`,
  `cmd_diff.go`, `serve.go`, `sdk/domainmodel/connection.go`, `vscode-mdl/src/preview/*`,
  `vscode-mdl/package.json`, `testdata/pedapp/README.md`

Web:

- Mendix 10.18 release notes (MPRv2 beta): https://marketplace.mendix.com/link/studiopro/10.18.0
- Mendix 10.22 release notes (automatic v2 conversion): https://docs.mendix.com/releasenotes/studio-pro/10.22/
- `mx dump-mpr`: https://docs.mendix.com/refguide/mx-command-line-tool/dump-mpr/ ,
  https://support.mendix.com/hc/en-us/articles/27371687271708-How-to-export-the-Mendix-app-model
- Platform SDK / Model SDK (PAT, working copies): https://apidocs.rnd.mendix.com/platformsdk/latest/index.html ,
  https://www.mendix.com/blog/a-mendix-sdk-primer-part-1/
- Studio Pro Comparison pane and history: https://docs.mendix.com/refguide/comparison-pane/ ,
  https://docs.mendix.com/refguide/comparing-revisions/ ,
  forum idea for a visual microflow diff: https://community.mendix.com/link/spaces/studio-pro/ideas/3844
- Community Mendix model readers (MCP, no diagrams):
  https://glama.ai/mcp/servers/EGorsel/mendix-local-mcp ,
  https://glama.ai/mcp/servers/@jordnlvr/onetech-mcp-server/blob/d56cfdc8c82bce29b8882fade86c114252f54883/README.md
- GitHub Mermaid support: https://github.com/github/roadmap/issues/372 ,
  https://github.blog/changelog/2022-02-28-gists-now-support-mermaid-diagrams/
- VS Code Markdown and Mermaid:
  https://code.visualstudio.com/api/extension-guides/markdown-extension ,
  https://www.issoh.co.jp/tech/details/2334/ (reports built-in Mermaid in 1.121) ,
  https://forum.cursor.com/t/built-in-mermaid-renderer-doesnt-support-c4container-diagrams-older-mermaid-version-bundled/162935
- VS Code webview API and CSP: https://www.mintlify.com/microsoft/vscode/api/webview
- Codex IDE extension: https://developers.openai.com/codex/ide/features ;
  Codex app in-app browser: https://developers.openai.com/codex/app/browser
- Libraries: Mermaid https://mermaid.js.org , elkjs https://github.com/kieler/elkjs ,
  Graphviz https://graphviz.org , React Flow https://reactflow.dev , Cytoscape.js https://js.cytoscape.org
- Claude Code Artifacts: the host's Artifact tool contract (private by default; CDN allowlist
  of cdnjs, jsdelivr, unpkg and similar; 16 MB limit).
