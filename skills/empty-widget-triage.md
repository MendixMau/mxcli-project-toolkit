# Empty Widget Triage — UI, Data, or Security?

**Applies to:** any Mendix page/grid/combobox that renders "empty" — blank cells, zero rows, zero
dropdown options — found during a UI review or e2e run.

Written 2026-08-19 after a UI-review-loop pass and an e2e journey run flagged the same symptom
("a grid renders blank cells") twice, from two different angles, and each time reached for a
different single-cause explanation without checking the other two. See
`security-is-not-a-later-script.md` (the entity-access half of this) and
`e2e-ui-test-honesty.md` (the "assert on the database, not just the DOM" rule this generalizes).

## The mistake this prevents

"Empty" has exactly three root causes, and they are diagnosed with three different tools. Everyone
reaches for the one they know best and stops there:

| Symptom looks like | The tempting (wrong) conclusion | What it actually was, this cycle |
|---|---|---|
| Blank grid cells | "DataGrid2 binding defect" | Model's security rules were correct; the **compiled runtime** still enforced the old, stricter rules — a build/reload gap, not a binding bug or a permissions bug |
| Empty combobox dropdown | "The seeded value isn't in the list" | The combobox rendered **zero options at all** — not a missing value, a missing enumeration binding — a UI defect, and the persona had full read+write on the field |
| Empty grid, different module | "Same bug as the last one" | Actually an empty backing table — no rows existed at all — a data problem, unrelated to the grid that rendered it perfectly once seeded |

Same visible symptom, three unrelated causes, three unrelated fixes. A review that stops at the
first plausible story fixes nothing or fixes the wrong layer, and the next pass reports the same
symptom again under a new hypothesis — exactly what happened here across two review cycles.

## THE RULE: never diagnose "empty" from the screenshot alone

Before writing up an empty-widget finding, run all three checks below **in this order** — cheapest
first — and report which one(s) actually reproduced the emptiness, not which one seems likeliest.

### 1. Data check — is there anything to show?

```bash
./mxcli oql -p <app>.mpr "SELECT count(x.ID) FROM <Module>.<Entity> AS x"
```

Zero rows → data problem, stop here. This is the cheapest check and rules out the other two
instantly. Don't skip it because "the grid looked structurally fine" — a well-built grid with an
empty table looks identical to a broken grid with data behind it.

### 2. Security check — does *this* persona have access to *these* attributes/rows?

```bash
./mxcli -p <app>.mpr -c "SHOW SECURITY MATRIX IN <Module>"
./mxcli -p <app>.mpr -c "DESCRIBE ENTITY <Module>.<Entity>"
```

Check the grant for the **exact role the failing user holds**, not Administrator. A page that
works for admin and is blank for anyone else is almost always this. Then check whether the model's
answer matches the **running app's** answer — see check 3. A grant that looks complete in
`SHOW SECURITY MATRIX` can still be denied at runtime if the last build didn't actually ship it.

Console-log or DOM-probe the live page for the runtime's own access-denial text (Mendix prints
`No access to attribute "X"` or `insufficient permissions to "X"` directly into the browser
console when a widget's binding is denied) — this is the fastest way to catch case 3 below, because
it tells you the runtime's opinion, not the model's.

### 3. UI/binding check — is the widget even wired to emit options/rows?

Only reach here once 1 and 2 are both clean: real data exists, and the model's own security matrix
grants the field. If the page is still empty, suspect:
- A stale compiled runtime — the `.mpr`'s security/model changed but the running container is still
  serving an older build (`docker inspect <container> --format '{{.Created}}'` vs. the model's last
  edit; `./mxcli docker build --skip-check` + `./mxcli docker reload`, or a full `docker down`/`up
  --fresh` if reload doesn't clear it)
- A missing/misconfigured enumeration binding on the widget itself (combobox with a valid
  attribute but no populated option list)
- A DataGrid2 whole-grid datasource binding pointed at the wrong entity/association

## When all three checks come back clean and it's STILL empty

Example: one grid survived a full `docker build` + `docker down`/`up` recreate (not just
`reload`) with data intact, the model's grants correct, and the failing user's role mapped
correctly to a module role that included read access — and the runtime still denied every
attribute, identically, before and after the rebuild.

This is a 4th, rarer tier: a **genuine compiled-security defect** — the compiled runtime's access
check disagreeing with what the declared MDL grants say, for reasons a rebuild doesn't fix. Once
data, security-in-the-model, role-mapping, and a full container recreate are *all* individually
confirmed clean and the symptom persists, stop assuming "one more rebuild will clear it" — that
hypothesis has been falsified. At that point:

- Check `bug-logs/mxcli-bugs.md` for a matching pattern (a logged bug class of "MDL round-trips
  clean, native compiled structure doesn't" is one example).
- Try forcing a real regeneration by re-applying the identical grant statements via a fresh
  `ALTER ENTITY`/`grant` MDL script and re-executing — sometimes the compiled security XML only
  regenerates on an actual write to the entity, not a rebuild of an unchanged model.
- If that doesn't clear it either, this is now a tool defect worth proving with
  `sandbox-ab-tool-defect-probe.md`, not a fixable app-config problem — don't keep spending rebuild
  cycles on it.

## Reporting checklist

For every "empty X" finding, state explicitly which of the three you tested and what each one
said — even the ones that came back clean. "Data: 12 rows present. Security: model grants full R
to this role. Runtime: browser console shows `insufficient permissions` — compiled build is stale
relative to the model" is a diagnosis. "Grid renders blank cells" is a symptom description someone
else will have to re-diagnose.

If two review passes report what looks like the same empty-widget symptom, don't assume it's the
same root cause without running all three checks again — the symptom is not the diagnosis, and
the same-looking blank grid has already produced two different real causes on at least one
project.
