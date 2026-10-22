## Goal

Show a Mendix model as a picture, wherever the work happens:

- the domain model (entities, attributes, associations, generalizations);
- microflows and nanoflows, ideally laid out as Studio Pro lays them out;
- the call graph and page → microflow wiring;
- **before/after diffs between two git commits**.

The places that matter are Claude Code (artifacts and local HTML), VS Code / Copilot agent
mode, Cursor and Windsurf, Codex, and GitHub PR review. Everything here stays read-only,
on demand, and never on the exec happy path.

## What exists

**Toolkit**

- `skills/architecture-blueprint.md`: hand-written Mermaid diagrams in `blueprint.md`, plus a generated `blueprint.html`.
- `bin/app-layer-map.sh` → `analysis/app-layer-map.html`: module order and back-edges, built from catalog facts.
- `docs/architecture-views-design-note.md`: rejects a whole-app ERD and a whole-app call graph as hairballs, and allows per-slice views.
- `project-bin/mxunit_bson.py`: an order-preserving BSON codec for `.mxunit` files, already in the repo and reusable as the reader.

**mxcli** (read from source, not run here)

- `describe --format mermaid` produces:
  - an `erDiagram` per module;
  - a `flowchart` per microflow or nanoflow;
  - a widget tree per page.
- `describe --format elk` produces elkjs JSON for a domain model, an entity focus, a microflow or nanoflow, and `systemoverview`.
- The `vscode-mdl` extension has a **Show Diagram** webview that loads Mermaid 11 and elkjs from jsdelivr.
- **Both formats re-lay the diagram out and drop Studio Pro's stored positions.**
- Plain MDL `DESCRIBE` still prints `@Position(x, y)` on entities and `@position(x, y)` on activities.
- `diff-local --ref A..B` gives the *textual* MDL diff between two refs.

## Data sources (ranked)

| # | Source | Lossless | Layout | Cost | Verdict |
|---|---|---|---|---|---|
| 1 | Parse MPR v2 `mprcontents/**/*.mxunit` (BSON), with the `.mpr` SQLite `Unit` table for containment | yes | **kept**: entity `Location`, association connection %, activity `RelativeMiddlePoint`/`Size`, flow connection sides + Bezier vectors | 0.57 s per 370 units, stdlib only, works directly on a git revision (`git cat-file --batch`) | **best for drawing and diffs**; the schema is undocumented and drifts across Mendix versions |
| 2 | `mxcli describe` (MDL) | semantics yes | as `@position` text | one process per document unless batched | best for labels and semantics |
| 3 | `mxcli describe --format mermaid\|elk` | partial | discarded | zero effort | readable, but not Studio Pro-like |
| 4 | `mx dump-mpr` (official, 10.4+) | yes | kept | needs the version-matched mxbuild | official fallback when the BSON schema drifts (untested here) |
| 5 | Catalog (`REFRESH CATALOG FULL`, `CATALOG.REFS`, `graph-report --format json`) | no | none | FULL refresh can take minutes | best for the call graph and wiring at scale |
| 6 | Mendix Model SDK | yes | kept | PAT + cloud working copy | **no**: needs a token and sends client model content off the machine |

## Rendering options

| Option | Fidelity | Effort | Deps | Hosts |
|---|---|---|---|---|
| **Custom inline SVG at the stored coordinates** | high, Studio Pro-like | medium (~300 lines) | none, works offline | any HTML host: artifact, webview, Simple Browser, Codex in-app browser |
| Mermaid `erDiagram` / `flowchart` | low to medium, auto layout | zero (mxcli emits it) | mermaid.js | GitHub, artifacts, VS Code Markdown preview, Cursor, Windsurf |
| ELK JSON + elkjs | medium, clean but not Studio Pro's layout | zero (`vscode-mdl` template exists) | elkjs | VS Code, artifacts |
| Graphviz, React Flow, Cytoscape | low to high | medium to high | WASM or npm bundle | browser; overkill for a report |
| **Visual diff** (the "after" SVG with highlights and ghosts of the "before") | high; Studio Pro's Comparison pane is textual | medium | none | HTML hosts; PRs get the change list + Mermaid |

## Per-host display

| Host | Route | Mermaid | Inline-SVG HTML |
|---|---|---|---|
| Claude Code | a private Artifact (CDN scripts only from cdnjs, jsdelivr, unpkg; 16 MB limit), or a local file / desktop browser pane | yes | yes |
| VS Code / Copilot agent mode | the `vscode-mdl` webview, a custom webview, Simple Browser on localhost, Markdown preview | reported built into Markdown preview from 1.121, otherwise the bierner extension | yes, via webview or localhost |
| Cursor, Windsurf | the same as VS Code (forks); built-in Mermaid renderer reported on an older Mermaid | yes | yes |
| Codex | CLI writes a file; the IDE extension uses the host's preview; the Codex app has an in-app browser for file-backed and localhost previews | via the host | yes |
| GitHub PR / issue comments | native ```mermaid fences (since Feb 2022); inline SVG and scripts are stripped | **yes** | no; upload the HTML as a CI artifact |

## Prototype findings

A throwaway script, kept in a scratch directory and **not committed**, read the public
`mendixlabs/mxcli` test model `testdata/pedapp` (Mendix 11.13, 8 modules, 370 units) and
`testdata/testapp-views`. It wrote one self-contained HTML page with:

- domain models per module at Studio Pro's stored positions (header colour by persistent, non-persistent, view or external; typed attributes; associations at the stored connection points with multiplicities; generalization tags);
- all 37 microflows and nanoflows at their stored coordinates, with Bezier flows from the stored control vectors, decision and merge diamonds, loop containers with children, parameters, annotations, case labels and error flows. The largest, a 29-object validation flow, looks very close to its Studio Pro layout;
- a Mermaid call graph and page → microflow wiring graph (39 edges);
- a Mermaid-vs-positioned fidelity comparison;
- a **two-commit diff**. A scratch git copy of the public model got a second commit that moves an entity, renames an attribute, and moves and recaptions one activity. `git diff` reports only `Bin 10663 -> 10663 bytes`. The page shows a change list, plus the "after" diagrams with highlights and dashed ghosts at the old positions.

Numbers:

- extract ≈ 0.57 s per working tree and ≈ 0.5 s per git revision;
- render 4 ms;
- **whole pipeline 2.3 s**;
- page 117 KB;
- about 35 minutes to write.

Not verified: Mermaid rendering, because the sandbox blocked jsdelivr. The SVG parts need no network.

Rough edges:

- Entity box sizes are estimated, because Studio Pro stores none.
- Captions are derived only for common action types.
- Add and remove in the diff are implemented by `$ID` but were not field-tested.
- Pages and workflows are not drawn.

## Minimal design

- `bin/model-view.sh <project-dir> [--module M | --docs A,B | --diff REF_A..REF_B] [-o out.html] [--mermaid-only]`
  - It reads a model, so it belongs in `bin/` (generic-first).
  - It is a thin wrapper that resolves the `.mpr` through `_common.sh` for both the single-tree and two-tree layouts.
- The core is `bin/lib/model-view.py`, or Node. It reuses `project-bin/mxunit_bson.py`, and its SVG path is stdlib-only.
- Output: `analysis/model-view.html` (gitignored) plus `analysis/model-view.json` (the graph, for agents). `--mermaid-only` prints Mermaid to stdout for PR comments.
- **Scoped by default:** a module, a slice, or the changed documents only. No whole-app ERD, as the design note already decided.
- Hooks, all opt-in with no new gate:
  - a dashboard link card when the file exists;
  - `app-report.sh` findings linking to the microflow's anchor;
  - the Stage 5 LOOK step using `--diff <pre-build snapshot>..HEAD --module M`;
  - later, a CI step that posts the change list + Mermaid to the PR.
- A short skill section says when to look (Stage 0 blast radius, Stage 5 LOOK, PR review) and never to publish without opt-in.
- Field-proof:
  - golden captured `.mxunit` input from the public `pedapp` and `testapp-views` models, with count assertions, plus one Mendix 10.x model;
  - both layouts;
  - both platforms: probe for `python3`/`py`, or use Node; use stdlib `sqlite3`, not the CLI;
  - one cited field run.

## Cost, performance, privacy

- **Never on the exec happy path.** It runs on demand or at report time, needs no mxcli process and no catalog, and can read from a git revision to avoid a mid-save Studio Pro.
- **Scale.**
  - Extraction is linear at ≈1.5 ms per unit.
  - A diagram is ≈2.5 KB of SVG, so a whole 3,000-microflow app would be ≈7.5 MB. That is legal for an artifact, but unreadable. Hence scope by default, and lazy rendering for big modules.
  - Mermaid has its own limits (`maxTextSize` 50k, `maxEdges` 500 by default), so keep it to small graphs.
- **Privacy.**
  - Model content is client data. The default output is a local file under gitignored `analysis/`.
  - A Claude artifact (even a private one) or a PR comment is a publish, and needs explicit opt-in.
  - PR comments carry document names and change kinds, not attribute lists.

## Open questions

1. Handling BSON schema drift across Mendix 9, 10 and 11:
   - fall back to `mx dump-mpr`?
   - or stop with a printed "unsupported unit shape"?
2. Support MPR v1 (BSON inside the SQLite file), or require v2?
3. **Upstream vs toolkit.** A position-preserving `--format svg`, or ELK with fixed positions, in mxcli would give the `vscode-mdl` preview Studio Pro-faithful diagrams for free. Should we prototype in `bin/` first and then offer an upstream PR?
4. Is "recognisable" enough, or are Studio Pro icons and widths a goal?
5. Diff identity: `$ID` vs `GUID`, so that a delete-and-recreate is paired correctly.
6. Confirm the claim that Mermaid is built into VS Code 1.121 Markdown preview on a real install.

## Next steps

1. Decide upstream vs toolkit (Q3).
2. Promote the prototype to `bin/model-view.sh`, starting with module scope only, plus `--diff`, a fixture over the public test models, and a `CHANGELOG.md` line.
3. Field run on one real project; record the unit count, time and page size.
4. Wire the dashboard link and the Stage 5 LOOK `--diff` usage, and add the skill section.
5. Optionally, a GitHub Action for PR model-diff comments.

## Sources

- mxcli source: `mdl/executor/cmd_mermaid.go`, `cmd_microflow_elk.go`, `cmd_domainmodel_elk.go`, `cmd_entities_describe.go`, `cmd_microflows_show_helpers.go`, `cmd/mxcli/cmd_describe.go`, `cmd_diff.go`, `vscode-mdl/src/preview/*`, `testdata/pedapp/README.md`
- Toolkit: `docs/architecture-views-design-note.md`, `skills/architecture-blueprint.md`, `bin/app-layer-map.sh`, `project-bin/mxunit_bson.py`
- MPRv2: https://marketplace.mendix.com/link/studiopro/10.18.0 , https://docs.mendix.com/releasenotes/studio-pro/10.22/
- `mx dump-mpr`: https://docs.mendix.com/refguide/mx-command-line-tool/dump-mpr/
- Platform / Model SDK: https://apidocs.rnd.mendix.com/platformsdk/latest/index.html
- Studio Pro Comparison pane: https://docs.mendix.com/refguide/comparison-pane/ ; visual microflow diff idea: https://community.mendix.com/link/spaces/studio-pro/ideas/3844
- GitHub Mermaid: https://github.com/github/roadmap/issues/372 , https://github.blog/changelog/2022-02-28-gists-now-support-mermaid-diagrams/
- VS Code Markdown / Mermaid: https://code.visualstudio.com/api/extension-guides/markdown-extension , https://www.issoh.co.jp/tech/details/2334/
- VS Code webview: https://www.mintlify.com/microsoft/vscode/api/webview
- Codex: https://developers.openai.com/codex/ide/features , https://developers.openai.com/codex/app/browser
- Libraries: https://mermaid.js.org , https://github.com/kieler/elkjs , https://graphviz.org , https://reactflow.dev , https://js.cytoscape.org

---
_Generated by [Claude Code](https://claude.ai/code)_
