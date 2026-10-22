# Wireframe-first approval loop: propose, confirm, build, verify

Research for the maintainer of `MendixMau/mxcli-project-toolkit`. Toolkit read at `master` @ `2fcdf5e`
(2026-10-21). Read-only: nothing in the repo was changed.

> The idea, in the maintainer's words: "for every new change ... we first propose a redesign of the
> wireframe, then ask if that's indeed correct. And if they agree, then we submit and let it build.
> But then we have a direct visualization of what's happening."

**Verdict.** Worth doing, as one small **experimental, lead-only skill**. Most of the parts already
exist: per-screen wireframes, the assembled prototype, the ask-then-stop protocol, the drift-sync
"visually observable" filter, the LOOK ledger and `page-fidelity.js`. What is missing is a
**per-change** step that shows the user a before/after **before** the MDL is drafted, records the
answer, and then shows the built page next to the approved design. It adds no mxcli or mxbuild
call: the "before" and "built" images come from outputs the loop already produces.

---

## 1. Gap analysis

| Change kind | What exists today (file) | Gap |
|---|---|---|
| **New screen, Stage 3** (migration, requirements-driven) | One annotated wireframe per screen (`skills/design-artifacts.md` Steps 2–3); clickable `design/prototype.html` (`project-bin/assemble-prototype.js`); scope crosscheck and link check (Steps 3b/3c); CAC-4 (`skills/checkpoints/checkpoint-design.md`); Stage 3 ✋ gate in `skills/conversion-runbook.md` (§ Stage 3). | **Mostly covered.** Approval is per *stage*, not per screen: the gate checks that wireframes exist plus one Stage-3 `CONFIRMED` row. No record says *which* wireframe version the user saw. #291 shows that a faithfully approved wireframe can still carry the defect; that issue covers the interaction-model half. |
| **New screen, greenfield** | `ui-preflight-pages.md` Step 1: no wireframe means ⛔ STOP, produce one first. `bin/lib/artifact-manifest.tsv` row `wireframes` lists `migration,requirements,existing-app-change` and **not greenfield**. | **Missing.** In greenfield the agent draws the wireframe to clear its own STOP and builds straight away. Nobody is asked to approve it. |
| **New or changed screen mid-build** (a new requirement during Stage 5) | Drift-sync: re-render a wireframe only when the change is *visually observable* (`conversion-runbook.md` §3b; `iterative-build-loop.md` "Requirements Drift-Sync Rule"). `ba-agent` flushes, and `gate-check.sh` blocks on `[sync: … UNSYNCED]`. Lightweight-change carve-out (runbook §1). Project wiring adds capture → classify → route → cascade → re-run gate. | **Missing.** The wireframe is re-rendered and the marker flipped, but the user is never shown the new wireframe and asked "is this right?". The gate checks that the sync happened, not that anyone approved it. There is no before/after. |
| **Change to an existing screen on a live `.mpr`** | `skills/existing-app-change.md`: Stage 3 says "wireframes only for screens that change". Ground rule 4: "record the as-is before the to-be" (in BRD text). `docs/existing-app-mode-design.md` §Stage 3: `wireframes/*.html` for every page changed or added, CAC-4 scoped. `ui-preflight-pages.md` Step 0 already runs `DESCRIBE PAGE` / `impact` on the target. | **Partial.** A to-be wireframe is owed, but there is no **as-is visual**. The app has no wireframes, and nothing asks for a screenshot or a describe-derived "before". There is no side-by-side. Approval is again only the stage-level row. |
| **Trivial UI change** (label, column order, one field) | Lightweight carve-out: skip dispatch, keep the `PROJECT.md` row. | **By design.** It should stay out of the loop, or get an inline chat diff. |
| **Non-UI: entities and associations** | Stage 3 Mermaid diagrams in `architecture/blueprint.md` and `blueprint.html` (`architecture-blueprint.md` Step 7, plus the iterative review step "same loop as LOOK but for architecture"); existing app: `bin/app-layer-map.sh`, `app-report.html`. | **Partial.** Covered at Stage 3. A mid-build domain change gets a BRD and decision row but no before/after picture. |
| **Non-UI: microflows** | BRD as-is/to-be text (existing-app mode); `DESCRIBE MICROFLOW`. | **Missing, and mostly fine.** A behaviour table (input → outcome, before/after) is the right visual. A diagram rarely helps. |
| **Non-UI: security** | Role-to-access table (Stage 4 gate); `SHOW SECURITY MATRIX`. | **Partial.** No before/after matrix diff per change. |
| **Verify the build against the approval** | `skills/ui-loop.md` (screenshot, four questions, `page-fidelity.js` score into `docs/PAGE-FIDELITY.tsv`); `project-bin/look-ledger.sh` (`exec.sh` marks the pages it built as owed a look, and the Read hook clears them); `skills/module-review.md` stage 4 (wireframe-vs-live, divergence table); `project-tests/e2e/design-audit.js`; obligations `look`, `fidelity`, `design-reaches-app` in `bin/lib/obligations.tsv`. | **Partial.** Everything compares against *the current* wireframe, approved or not. No single artifact puts **approved design** and **built screenshot** side by side for the user, and nothing ties a fidelity row to an approval. |

**Summary.** For brand-new screens at Stage 3, wireframe-first already exists at stage granularity.
For **every later change** (mid-build, greenfield, existing app) it is missing. The repo already
holds the evidence for why it matters: #232 (LOOK skipped during build) and #291 (defects designed in
and then built faithfully).

---

## 2. The proposed loop

Per change that alters what a user sees, run by the lead session (subagents cannot ask the user):

1. **Classify.** Ask whether the change is visually observable, reusing the drift-sync filter. If
   not, go to step 1b. If it is trivial (one label or one field) and the user has said inline is
   fine, show a 3-line text diff in chat and skip to step 5.
   1b. **Non-UI:** render the matching before/after view: entity/association → a Mermaid `classDiagram`
   pair; microflow → a behaviour table (input → outcome, before | after); security → an access-matrix
   diff. Draw from the `DESCRIBE`/`SHOW` output the change already needed. Then continue at step 3.
2. **Propose.** Write `design/proposals/<YYYY-MM-DD>-<slug>/`:
   - `before.*`: the cheapest existing truth, in order:
     1. the last LOOK screenshot of that page, already on disk from `ui-loop.md`;
     2. the current `design/wireframes/<Screen>.html`;
     3. for an existing app with neither, a rough wireframe drawn from the `DESCRIBE PAGE` output that
        `ui-preflight-pages.md` Step 0 already fetched;
     4. a screenshot the user drops in.
   - `after.html`: the edited wireframe, built from `ds.css` exactly as `design-artifacts.md` Step 3
     requires, with its binding table and `data-bind`/`data-cut`.
   - `proposal.html`: before and after side by side (stacked on mobile), with changed regions outlined
     (`data-changed`), the binding-table diff, and a status strip:
     Proposed → Approved → Building → Built → Verified.
3. **Show.** Open or publish `proposal.html` per §3.
4. **Ask, then stop.** Use one question with numbered options: *Approve · Change (say what) · Drop
   it*, with "something else" always available. Render it per `interview-protocol.md` §3 "Asking on
   a non-Claude agent", then end the turn. On "change", revise `after.html` and ask again.
5. **Record.** Add a `PROJECT.md` Decisions row:
   `| 5 | Wireframe approved: OrderDetail (design/proposals/2026-10-21-order-cancel/) sha256:<8> | CONFIRMED | user, <date>: "<words>" | [sync: F003, OrderDetail.html UNSYNCED] |`
   Copy `after.html` over `design/wireframes/<Screen>.html`, which is the existing source of truth.
   That way every downstream check (`ui-preflight`, `check-page-shell.sh`, `page-fidelity.js`,
   module-review) reads the approved version with no change to them. Re-run `assemble-prototype.js`.
6. **Build.** Run the normal loop unchanged: brief, pack, mdl-agent, `exec.sh` (one mxbuild, as today).
   Update the status strip to "Building" as each script lands. The Live Checklist (§1b) already
   reports progress in chat; the strip mirrors it on the page.
7. **Verify.** Run `ui-loop.md` as today. It takes a screenshot and a `page-fidelity.js` row. Copy that
   screenshot into the proposal folder as `built.png`. `proposal.html` gains a third column
   **approved | built**, and the four LOOK questions are answered against the approved column. A
   divergence is fixed now or recorded. Set the status to "Verified" when the LOOK and the fidelity
   row exist.

**What "direct visualization of what's happening" means in practice.** There are two things to show,
and both fit on one page per change:
- **Before you build:** the before/after the user approves (steps 2–4).
- **During and after:** the status strip, then the built screenshot next to the approved design
  (steps 6–7).

That page is also the natural PROOF-OF-LOOK evidence `module-review.md` asks for. There is no live
streaming of Studio Pro; the build itself stays headless.

---

## 3. Where to show it, per host

What this loop needs from the separate host-detection work is three booleans: **can the user open a
local file in a rendered view**, **can the agent screenshot that view itself**, and **is the session
remote** (no local display, so publish instead).

| Host | Show `proposal.html` | Can the agent see it? | Notes |
|---|---|---|---|
| Claude Code desktop app (local) | Click the path in chat, and it opens in the **Browser pane** (Cmd/Ctrl+Shift+B) | Yes: the pane screenshots, inspects the DOM and clicks | Reported stale render on Reload after a file changes; write a new revision filename (`proposal-r2.html`) or add a query string. Not available in SSH sessions. |
| Claude Code CLI, local terminal | `open` / `xdg-open` / `start` (the same pattern `bin/init-project.sh` uses for the guide), or publish an Artifact | Via a Playwright screenshot only, which the harness already has | |
| Claude Code on the web / cloud / remote-control | **Publish a private Artifact** (claude.ai link, republished to the same URL per revision) | Yes (it can read its own artifact) | The preview pane was reported unavailable in remote-control sessions. The wireframe may name client fields; artifacts are private by default, and sharing them stays the user's call. |
| Claude Code in VS Code / JetBrains | Same as CLI, or the IDE's browser (below) | As CLI | A reported regression: HTML links in chat stopped opening the embedded preview. |
| VS Code + Copilot | **Integrated Browser** (recent VS Code: open local `.html`, right-click → "Open in Integrated Browser"); **Simple Browser** (`simpleBrowser.show <url>`, needs an http URL, so `python3 -m http.server`, which module-review already uses); **Live Preview** extension ("Show Preview") | Agent tools vary; treat as "no" unless a browser MCP is wired | `code -r file.html` opens the source, not a render. |
| Cursor | Built-in browser: right-click the HTML tab → **Open in Browser**; Design Mode lets the user annotate elements | Agent browser tools (CDP) exist | A forum report says an agent asked to open the simple browser opened the system browser instead. |
| Windsurf (docs now under Devin Desktop) | **Browser Previews** of a local server; "Send element" puts a selected element into the Cascade prompt | Partly (elements are sent as context) | Optimised for Chromium browsers; serve the folder over http. |
| Codex | App: **in-app browser** supports file-backed previews and a **comment mode** on elements or areas; the Browser plugin lets Codex screenshot and verify. CLI: OS `open` | App with plugin: yes; CLI: no | No auth or signed-in pages, which is irrelevant for static wireframes. |
| Headless / CI / unattended | Write the files and put the path in the log | No | Approval cannot happen. Under `Interview mode: unattended` (opt-in only), record `ASSUMED`, queue the proposals, and surface them at the next attended gate. Never build an unapproved redesign silently in attended mode. |

The comment and annotation modes (Codex comment mode, Cursor Design Mode, Windsurf "Send element")
fit "Change (say what)" directly: the user points at the region. On Claude Code the user types the
change instead.

---

## 4. Cost and risks

**Agent time and tokens per change** (estimates, not measured):
- Reading the existing wireframe: about 2–4k tokens.
- Writing `after.html` plus the side-by-side page: about 3–8k output tokens per screen. The compare
  page is mostly a fixed template, so after the first one it costs little.
- One ask-and-wait turn. **Human latency dominates.**
- Per non-UI change: a Mermaid pair or table of about 1–2k tokens.
- For comparison, the 2026-07-23 carve-out incident spent about 270k tokens on dispatch overhead. Even
  10 proposals per module stay well under one avoided rework round.

**No added mxcli or mxbuild calls on the happy path.** The "before" comes from:
- an existing screenshot or wireframe, or
- the `DESCRIBE PAGE` that `ui-preflight-pages.md` Step 0 already runs.

The "built" image comes from the screenshot `ui-loop.md` already takes. `page-fidelity.js` is
already run per page. The build still runs one `exec.sh` and one mxbuild per script. (Open issue #444
covers the existing mxbuild cost; this loop must not add to it.)

**When to skip:**
- the change is not visually observable (the drift-sync filter), unless it is a non-UI change that
  alters structure, in which case use 1b;
- the lightweight carve-out applies (label, typo, one field): use an inline chat diff;
- the user says "no visual": record `Proposal mode: off | inline` in `PROJECT.md`, in the same style as
  `Interview mode`, and re-ask only if the user turns it back on;
- a Stage-3 screen the user already approved in the prototype: do not re-ask for the first build.

**Risks:**
- **Approval fatigue.** Mitigations:
  - batch per slice or build phase: one `proposal.html` with N screens and one question, offering
    "approve all" or "go through them one by one";
  - one question per batch, not per screen;
  - skip trivial changes;
  - cap: when more than about 5 screens change at once, that is a Stage 3 redesign, so route it back
    up instead.
- **Wireframe vs. real Atlas rendering.** A wireframe is a spec for a human, not Atlas output
  (`existing-app-assurance.md`: "Do not fix the wireframes"). Mitigations:
  - prefer a real **screenshot** as "before" whenever one exists;
  - label the after column "intent — not pixels";
  - the built-vs-approved column in step 7 is where drift becomes visible, and the LOOK judges it;
  - B0 `check-design-reaches-app.sh` already guards the token gap.
- **Describe-derived "before" is lossy.** It is labelled as such, and a screenshot is always preferred.
- **Rubber-stamping.** An approval proves the user saw it, not that the design is right for 2+ roles
  and 2+ objects. That is #291's interaction-model check; keep them separate.
- **Scope creep into a renderer.** `skills-over-scripts.md` row 4 says "confirm it matches the
  wireframe" is a skill. So v1 has **no script**: the skill carries a 40-line HTML template, and a
  helper is considered only after two hand-run uses show what is tedious, per "Adding a new
  capability" there.
- **Generic-first.** Nothing here reads a source platform. The loop works off wireframes, the model
  and screenshots, so it works for all four entry modes and à-la-carte use.

---

## 5. Smallest viable design

1. **New skill `skills/propose-before-build.md`.** It covers the trigger, the 7 steps above, the skip
   rules, the before-source ladder, a compare-page template, and a host table that defers to the
   host-detection work. It ends on a checkable bound: "N of N changed screens have a proposal folder
   and a CONFIRMED/ASSUMED row; NOT RUN is legal, silence is not".
2. **Routing.** One row in `bin/lib/skill-routing.tsv`:
   `propose-before-build  skills/propose-before-build.md  "Before drafting MDL for any change that alters what a user sees — a new screen outside Stage 3, a changed screen, a mid-build requirement, a greenfield page: show before/after, ask, stop, then build"  lead  3,5  experimental  design`.
   - **lead-only**, so it renders into no agent stub;
   - **experimental**, so it is not baseline and is never the reason a gate fails.
3. **Situational hooks** (non-baseline files only):
   - `design-artifacts.md`: after Step 3, "for any wireframe edited after the Stage-3 approval, see
     propose-before-build";
   - `existing-app-change.md` Stage 3 row: "as-is visual: screenshot or describe-derived";
   - `iterative-build-loop.md` Drift-Sync: "a visually observable re-render is approved before the
     marker flips".
4. **Record.** The `PROJECT.md` Decisions row (CONFIRMED or ASSUMED) names the proposal folder and the
   wireframe hash. **No new obligation in v1.** Verification is already enforced by the `look` and
   `fidelity` obligations against `design/wireframes/<Screen>.html`, which now *is* the approved
   version.
5. **Artifact path.** `design/proposals/<YYYY-MM-DD>-<slug>/{before.*, after.html, proposal.html, built.png}`.
   Add an `artifact-manifest.tsv` row only when the skill leaves experimental.
6. **v2, only after field use.** Add a cheap gate-check join with no mxcli: every
   `design/wireframes/*.html` committed after the Stage-3 approval must be named by a
   `Wireframe approved:` row, or a waiver. That catches the greenfield and mid-build silent edits
   mechanically. Also add the greenfield `wireframes` manifest entry.

**Is a behaviour A/B needed?**
- **Not for v1 as specified.** It touches no baseline-routed text and no agent stub: the routing row is
  lead-only and experimental, and the hooks go into on-demand skills. `render-routing.sh --check`
  still runs. Per CLAUDE.md "Adding new skills" rule 8, do a retrieval check that the trigger fires on
  real phrasings ("change the order page", "add a field to …", "the client wants …").
- **Yes, once it is promoted.** That means moving it to `baseline`, adding a line to
  `conversion-runbook.md` (always loaded), changing `ui-preflight-pages.md` (inlined into every page
  dispatch), or touching any agent stub. That is an M-vs-T run per the behaviour suite. Note: on
  `master` @ `2fcdf5e`, `tests/behaviour/RUNBOOK.md` lives only on the unmerged branch
  `tests/behaviour-suite`.

---

## 6. Open questions

1. Granularity of approval: per screen, per change, or per build phase (batch)? I recommend per change
   with batching, and "approve all" for multi-screen changes.
2. Should a v2 gate-check join (an edited wireframe with no approval row) be `FAIL` or `MANUAL`?
3. Should approval be a CONFIRMED row only, or should the proposal folder also carry the user's
   verbatim answer, for when the register is long?
4. For existing apps with no screenshot on disk: should the "before" be describe-derived (cheap,
   lossy), or should the loop start the app once for a real screenshot? A real screenshot costs an app
   start, not mxbuild, but it is not free.
5. Should non-UI proposals (Mermaid or tables) share the same folder and question, or ride on the
   existing drift-sync decision row only?
6. Unattended runs: queue proposals as `ASSUMED`, or block page scripts for changed screens until an
   attended session approves them?
7. Overlap with #291 (interaction model) and #232 (LOOK cadence): should the proposal page also carry
   #291's "two objects, two roles" walk for the changed screen?
8. Host detection: which module will expose "can render locally / agent can see / remote" for this
   loop to consume?

---

## Sources

Toolkit (read at `2fcdf5e`):
- `skills/design-artifacts.md`, `skills/ui-preflight-pages.md`, `skills/learned-stylegallery.md`,
  `skills/existing-app-change.md`, `docs/existing-app-mode-design.md`, `skills/interview-protocol.md`,
  `skills/conversion-runbook.md` (§1, §3b, Stage 3)
- `skills/iterative-build-loop.md`, `skills/ui-loop.md`, `skills/ui-review-loop.md` (tombstone),
  `skills/module-review.md`, `skills/skills-over-scripts.md`, `skills/existing-app-assurance.md`
- `project-bin/page-fidelity.js`, `project-bin/look-ledger.sh`, `project-bin/exec.sh`,
  `project-tests/e2e/design-audit.js`, `project-bin/assemble-prototype.js`,
  `project-bin/prototype-route.js`
- `bin/lib/obligations.tsv`, `bin/lib/artifact-manifest.tsv`, `bin/lib/skill-routing.tsv`,
  `CLAUDE.md` "Adding new skills", branch `tests/behaviour-suite`:`tests/behaviour/RUNBOOK.md`
- Related issues: #291, #232, #173, #444, #107.

Public docs:
- Claude Code desktop, Preview/Browser pane: https://code.claude.com/docs/en/desktop
- Claude Code issue reports (stale HTML preview on reload, preview unavailable in remote-control,
  VS Code chat HTML links): https://claudeissues.com/issue/65443-desktop-preview-pane-serves-stale-html-doesnt-refresh-on-reload-after-the-file-c ,
  https://claudeissues.com/issue/48466-preview-pane-pdf-image-html-unavailable-in-remote-control-sessions ,
  https://claudeissues.com/issue/59568-vscode-extension-clicking-local-html-file-links-in-chat-no-longer-opens-embedded
- VS Code Integrated Browser: https://code.visualstudio.com/docs/debugtest/integrated-browser
- VS Code CLI (`-r`): https://code.visualstudio.com/docs/configure/command-line
- VS Code Live Preview: https://github.com/microsoft/vscode-livepreview
- VS Code chat tools: https://code.visualstudio.com/docs/copilot/chat/chat-tools
- Cursor browser (forum): https://forum.cursor.com/t/open-html-files-directly-in-the-agent-window/165015 ,
  https://forum.cursor.com/t/using-agent-to-open-simple-browser-in-ide/129518
- Windsurf / Devin Desktop previews: https://docs.windsurf.com/windsurf/previews
- Codex in-app browser: https://developers.openai.com/codex/app/browser ; IDE features:
  https://developers.openai.com/codex/ide/features

Caveat: the VS Code, Codex and Windsurf doc pages could not be fetched directly from this sandbox
(DNS). Their claims come from search-result summaries of those official pages. Cursor claims come
from its forum, not official docs, and that UI changes quickly.
