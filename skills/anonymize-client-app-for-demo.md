# Skill: Anonymize a Client App into a Shareable Demo

**Applies to:** any mxcli project. Use when you have a Mendix app built for/from a client (under
NDA, with their source-derived modules, branding, data, custom widgets) and you want a clean,
shareable version for a public demo / recording / other prospects — with zero client fingerprint.

---

## Core mental model: two separate surgeries

| Front | Comes from | Holds the fingerprint as |
|---|---|---|
| **The model** (`.mpr` + `mprcontents/`) | MPK import | attribute names, page captions, enum values, custom widgets, comments |
| **The folder** (mdlsource, design, analysis, docs) | `cp` from source repo | source-analysis, BRDs, source-column comments, brand tokens |

Treat them differently. The MPK gives you the built model; the folder gives you scaffolding.

---

## Step sequence

### 1. Copy via MPK, never folder-copy the live project
In Studio Pro: **Export Project Package** → import as a **new app** into its own folder + fresh git.
- Why not `cp -r` the folder: opening the original in SP runs an **"Update original app"**
  step that mutates the source project (version upgrade). MPK export is a clean snapshot.
- Exclude Team Server binding + data on export.

### 2. Rename in place (don't rebuild) — keep page structure
Only the *source-derived* module needs de-identifying. Rename it + its attributes in **Studio Pro**
(SP's rename refactor auto-updates every page/microflow reference — safer than MDL `ALTER RENAME`
on a model that has MCP-built pages).
- Module: `<ClientModule>` → generic (`Equipment`, `Asset`, `Catalog`)
- Attributes: client codes → generic (`ItemCode`→`AssetCode`, drop client-specific derived flags)
- **Captions**: any non-English / client screen labels → English (also improves the demo)
- **Comments**: strip source-column citations (`← BS_ITEMINFO`, `BR-1 …`) — these are the biggest tell

### 3. Swap custom widgets by namespace
Client custom widgets carry a `com.<client>.*` package = hard NDA tell (and usually a pre-commit blocker).
- Find them: `find widgets/ -name "*.mpk"` → anything not `com.mendix.*` is suspect.
- Replace with a clean-namespace equivalent (from another of your apps, or a marketplace widget),
  then re-point the widget on each page that used it.
- Standard marketplace widgets (`com.mendix.widget.web.*`) are safe — keep them.

### 4. Drop real data → seed synthetic
You can't "rename" data. Delete client seed files (`testdata/*.xlsx`, sample rows) and seed
fresh synthetic rows. Data is never anonymizable by find-replace.

### 5. Folder: scripted token-replace + VERIFY GREP
Copy pure-infra folders (`bin/`, `theme/`, design tokens), then replace the known client token set
across all text files. **The verification grep is the guarantee — it must return zero hits:**

```bash
grep -rIl -E "BS_[A-Z]+|WebSquare|com\.<client>|<ClientName>|MyBatis|<client-source-tokens>" \
  <new-repo> --exclude-dir={.git,node_modules,deployment} || echo "CLEAN — zero hits"
```

Anything the grep still finds = manual review. Don't trust the replace without the grep.

### 6. Regenerate demo-facing artifacts (don't scrub them)
BRDs, wireframes, arch diagram, presentation — these often have client tells sprinkled in
(agents wrote them with source in context). **Regenerate clean** rather than scrub:
- Clean by construction (no missed tell)
- Matches the renamed model → "here's the BRD, here's the app it produced" is a coherent, honest story
- A scrubbed client-BRD wouldn't match the renamed app anyway

Rule: **regenerate demo-facing; scrub only internal-only docs you must keep; drop the rest.**

---

## What goes where (learnings vs project state)
- **Reusable methodology** (this file) → shared toolkit
- **Project-specific provenance** (which files had tells, which widget, the build plan) → private
  project notes — never promotion-eligible

---

## Worked example (illustrative)

Renaming `ClientApp` → `DemoApp`:
- Client custom widget `com.client.widgets.LabelRenderer.mpk` → swapped for
  `demoapp.widgets.LabelRenderer.mpk` (clean namespace), re-pointed on every page that used it.
- `ClientEntity` (derived from a client source table) → renamed to a generic domain name;
  non-English captions → English.
- Real seed data dropped → fresh synthetic seed generated.
- Standard marketplace widgets kept as-is.
- Docs and BRDs regenerated against the renamed model rather than scrubbed, so the demo's
  narrative artifacts match the app they describe.
