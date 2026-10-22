# Propose before build — show a visible change, get one yes, then build

**Applies to:** any `PROJECT.md` project whose register says `Proposals: batch` or `Proposals: each`. Absent or `off` (the default): stop reading.
**Purpose:** a change the user will *see* is drawn into its wireframe and approved before MDL.
**Trigger:** a CR row (`change-intake.md`) that adds, removes or moves a field, column, button, section or navigation step on a screen approved at Stage 3, or a greenfield screen first drawn at Stage 5.

Wrong:
- *"Added the Duplicate button: script 12 applied."* The user first sees it in the running app (#232, #291).
- *"Proposal ready: design/proposals/2026-10-21-dup/proposal.html."* One folder per change; after twenty, nobody knows which is current.

## 1. Ask or stay silent

| The change | `batch` | `each` |
|---|---|---|
| A nit: caption or label text, column order, icon, a `ds.css` colour or spacing | Silent: change-intake receipt only | Silent |
| Not visible: logic, security, an entity with no new field on screen | Silent: receipt only | Silent |
| Visible, S, typed by the user | Propose. **One** question for all pending proposals, before the first page script that builds any | One per CR |
| Visible, M or L | Rides the question change-intake already asks. Never a second one | Same |
| A screen approved at Stage 3, first build | Silent: already approved | Silent |
| A greenfield screen drawn at Stage 5 | Rides the module-start coverage-checklist confirmation | Same |
| More than 5 screens | Not a proposal: L, re-enter Stage 3 | Same |

`Interview mode: auto`: propose, do not stop; record a Ruling, show it at the next attended gate.

## 2. Propose: update, never multiply

1. Edit `design/wireframes/<Screen>.html` **in place** (`design-artifacts.md` Step 3: `ds.css`, page contract, binding table). For an existing app, it is the wireframe `existing-app-change.md` Stage 3 already owes.
2. Put `data-changed` on each new or moved element, with the screen style `[data-changed]{outline:2px dashed #d97706}`. Add one block at the top of the body; its `wf-` prefix keeps it out of `page-fidelity.js` scoring:
   ```html
   <div class="wf-proposal" data-cr="CR-12" data-status="proposed">
     <p>CR-12 · proposed · Before: no Duplicate button. After: "Duplicate" (secondary) in the footer.</p>
   </div>
   ```
3. Run `node project-bin/assemble-prototype.js`. `design/prototype.html` is the one page the user opens.
4. "Before" is what already exists: the last LOOK screenshot, else the wireframe at HEAD. Never start the app or run mxcli for it.
5. Set the CR to `refined`, entry artifact `wireframe <Screen>.html`.

Zero new files. 1–2 screens: the lead edits inline; 3–5: one `architect-agent` pass.

## 3. Show it where the user is

| Situation | Do |
|---|---|
| `Display: artifact` in `PROJECT.md` (set by the user) | Publish `prototype.html` as a private Artifact; republish to the same URL each round |
| Local desktop with an opener, `CLAUDE_CODE_REMOTE` unset | Open it once per session (`open` on macOS, `xdg-open` with `$DISPLAY`, `cmd //c start ""` on Git Bash); later, "reload the tab" |
| Anything else | The path and route: `design/prototype.html#/<route>` |

Never publish without that line.

## 4. Ask once, then stop

Render per `interview-protocol.md` §3:

> **CR-12, Duplicate order button** (`design/prototype.html#/order-newedit`, outlined)
> Before: no button. After: "Duplicate" (secondary) in the footer.
> 1. Approve: build as drawn (recommended)
> 2. Change: tell me what
> 3. Drop it
> 4. Something else

In a batch: one entry per CR, plus "approve all". **End the turn. No MDL this turn.**

## 5. Record, build, verify

- **Approve:** set `data-status="approved"` and the CR to `agreed`. Commit, then put `<Screen>.html@<short sha>` in the entry cell. Build through the normal loop (`change-intake-detail.md` Step 4).
- **Change:** revise the same file and ask again. **Drop:** `git checkout -- <file>`; CR `rejected — <reason>`.
- **Verify:** the `ui-loop.md` look and the `page-fidelity.js` row against that wireframe are the proof. CR `proven`, Closed-by citing both. Then delete the block and the marks; git keeps the history.

## Done when

- N visible CRs → N `wf-proposal` blocks, or a §1 skip reason each.
- 0 new HTML files.
- Questions: ≤1 per CR (≤1 per round under `batch`); 0 for nits and non-visible changes.
- 0 MDL drafted for a CR that is not `agreed`.
