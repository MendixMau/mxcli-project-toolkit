# Skill: The One-Shot MDL Method

**Applies to:** any mxcli project — migration, requirements-driven or greenfield. Wherever a
single MDL script has to take a Mendix project from *nothing* to a *working vertical slice*
(domain, integration, logic, UI, security) in one execution, and still work next month, on
someone else's project, run by someone who wasn't there.

**Origin:** distilled 2026-07-30 from building one REST-backed vertical slice roughly a dozen
times across two projects. Confirmed on Mendix 11.12.0 / mxcli v0.16.0. Every rule below was
paid for.

**Read first, every time.** This skill is the one-shot *method* — order, idempotency, silent
failures. It does not replace the two preflights, which cover ground this file doesn't:

- `learned-mdl-preflight.md` — before writing **any** MDL, including §0's write-mode choice
  (CLI vs MCP+MDL vs hand-rolled MCP) and its STOP table.
- `ui-preflight-pages.md` — before the first widget of **any** page: wireframe → design tokens →
  gallery reuse, so a one-shot page doesn't reinvent a layout the project's design gallery
  already solved.

A one-shot script that skips those two and goes straight to §2 will still run, but it can ship a
page that ignores the project's own design system, or pick the wrong write mode for a construct
this file doesn't cover. Treat all three as one preflight, not this file alone.

---

## 1. Why one-shot at all

A one-shot script is not a convenience. It is what makes the model **reproducible**, and
reproducibility is what turns "the AI generated some code" into an engineering artifact:

- The script is the spec. If it and the model disagree, the model is wrong and gets regenerated.
- A bug becomes a *diff*, not an archaeology exercise.
- You can hand it to someone else.

The failure mode it prevents is real and cost a full morning: a fix was committed to the script
and never executed, so the live model silently kept the old shape. **A committed fix is not an
applied fix.** Diagnose from `DESCRIBE` against the `.mpr`, never from the script.

## 2. Anatomy — always this order

```
1. module
2. enumerations
3. entities
4. associations
5. JSON structures
6. import/export mappings
7. microflows
8. pages
9. navigation        ← see §5: usually OMIT
10. security         ← module role, entity grants, user-role wiring
```

Dependency order, not taste. mxcli resolves references as it goes.

**Self-containment is the rule.** One module owning everything it needs. Cross-module datasources
corrupt page BSON and mxbuild does not catch it — see `learned-mcp-patterns.md` for the
cross-module datasource cases that must go through MCP instead. A slice that borrows from a
neighbouring module is not shippable.

> Security is step 10 in *execution* order only. It is **not** a later decision — see
> `module-brief.md` for what the module's roles and grants must already say before step 1 runs.

## 3. Non-idempotent on purpose — pair it with a drop

Use plain `create module` / `create enumeration`, not `create or modify`. The script then
**refuses to run against a dirty target**, which is the behaviour you want: it guarantees the
model matches the script exactly, with no residue from a previous shape.

The cost is that iterating means `drop module X` → re-exec. Accept that. It is two commands and
it is always correct.

**Corollary — regenerate, never patch.** Do not fix a generated module with `ALTER PAGE` surgery.
Replacing a datagrid column drops its datasource; inserting a widget into a customContent column
can make the model unloadable. Fix the source, drop, re-exec.

## 4. Write the constraints INTO the script

The script header is the most valuable part of the artifact. It should record, for every
non-obvious construct: what it is, why it is that way, what happens if you "clean it up", and the
date and evidence. Inline `--` comments at the exact widget or statement, not just at the top.

This is not documentation for its own sake. Every rule in this file was violated at least once by
someone who saw a construct that looked wrong and improved it. A header comment that says *"a bulk
rename over this file WILL break these three widgets; it did on 2026-07-29"* is the only thing
that stops the next pass.

## 5. Never ship a navigation REPLACE

`create or replace navigation <Profile>` replaces the recipient's **entire** menu. MDL has no
additive form. In your own project, reproducing the whole profile verbatim is survivable — read
it with `DESCRIBE NAVIGATION` immediately before writing the script, and diff.

In anything shared: **omit navigation entirely.** One documented manual step ("add a menu item
pointing at `Mod.ACT_Open`") beats a script that eats someone's menu.

## 6. Studio Pro must be CLOSED for the exec

Not "should". If SP holds the project open, it can write its stale in-memory state back over your
changes. Observed twice in one day: the module survived, the **navigation was silently reverted**,
because SP had pending edits on that document.

Detection: `pgrep -il studiopro` — **lowercase**, the process is `studiopro`. A case-sensitive
grep reports "closed" for a running SP, and that gates every exec decision.
A stale `<Project>.mpr.lock` names its owning pid; if that pid is dead, the lock is safe to delete.

## 7. The instrument hierarchy — know what each one cannot see

Ranked by what they actually prove. **Never conclude from a weaker instrument than the claim
requires.**

| Instrument | Catches | Blind to |
|---|---|---|
| `mxcli check` | MDL syntax | everything semantic |
| `check --references` | missing modules/entities | anything that exists but is wrong |
| `DESCRIBE` | shape of what was written | microflow datasources (not rendered at all); renders a NORMALISED form, so it cannot distinguish how a widget was authored |
| mxbuild / SP error pane | CE codes, load failures | silent no-ops that are valid models |
| **Running the app** | reality | nothing |

Three whole-morning mistakes came from this table:

- Concluding a page was broken because `DESCRIBE` showed a suspicious shape.
- Concluding a fix was a no-op because `DESCRIBE` read back identically — it renders normalised.
- Repeating a bug-log claim as if it had been observed.

**Corollary:** when a check passes and the thing still does not work, do not theorise. Find an
instrument that can see the layer you are guessing about. `tool-output-is-not-ground-truth.md` is
the general form of this rule; this table is its MDL-authoring instance.

## 8. Silent failures — the ones with no error anywhere

The dangerous class. `check`, `--references`, mxbuild and the runtime **all pass**, and the page
simply renders empty. Keep a list per tool version; these are the mxcli ones as of v0.16.0 —
cross-check `bug-logs/mxcli-bugs.md` for current status before working around any of them:

| Symptom | Cause | Fix |
|---|---|---|
| Grid empty, API returns 200 | **JSON structure root occurrence `0..0`** — root never instantiates, mapping imports nothing | patch to `1..1`, or regenerate the structure in SP |
| CE1613 "attribute no longer exists" | an **expression** inside `ContentParams` | `Attribute: X` shorthand |
| Datagrid renders, no rows, no datasource | microflow datasource parameter named with a reserved word (`Filter`) | rename (`FilterObj`) |
| Model will not load at all | `actionbutton` inserted into a customContent column via ALTER PAGE | full-page create, or MCP |
| Menu items vanished | navigation REPLACE while SP open | §5, §6 |

**Build a measuring instrument for each silent failure.** "Is the root occurrence dead?" is
otherwise invisible. A one-off script that reports a silent-failure condition across the whole
project pays for itself the first time it runs — it turned a day of theorising into one line of
output:

```
JSON_SearchRoutes   0..0   DEAD — maps nothing        ← mxcli wrote this
JSON_...            1..1   OK                          ← everything else
```

Per `skills-over-scripts.md`, that instrument only ever fetches the fact. The verdict on what to
do about it stays here.

## 9. Don't over-generalise a bug from one code path

Twice in one day a real observation was extended past its evidence and cost hours:

- *"Entity names must equal JSON element names"* — derived from one experiment that changed
  **two** things at once (renamed entities **and** added a missing mapping branch), then confirmed
  through a Studio Pro session that independently repaired the actual defect. The real cause was
  the occurrence bug. The naming rule was never demonstrated *by that experiment*.
- *"An actionbutton in a customContent column makes the model unloadable"* — every data point came
  from `alter page ... insert after`. Whether a **full-page create** has the same problem was never
  tested, and a working page in the same project contains the construct.

Before accepting a constraint — your own or a bug log's — ask: **what exactly was observed, on
which code path, and what changed at the same time?** Record the answer next to the rule.
`measured-claims.md` governs when such a claim may be cited as evidence at all.

## 10. Verify by diff against a known-good module

The strongest available check without a build. Generate into a scratch module, then:

```bash
diff <(mxcli -p app.mpr -c "DESCRIBE IMPORT MAPPING Good.IMM_X"  | sed 's/Good\./MOD./g') \
     <(mxcli -p app.mpr -c "DESCRIBE IMPORT MAPPING New.IMM_X"   | sed 's/New\./MOD./g')
```

Identical output against a module known to work at runtime is real evidence. It is how the
generator was proven reproducible.

## 11. Test on a genuinely clean project

`mxcli new <Name> --version <X.Y.Z>` creates a blank project in about a minute, and works on
macOS. Use it for anything intended to be shared — it is the only way to catch dependencies on
your own project: theme CSS classes, a user role that happens to exist, a layout, a home
microflow.

It also isolates variables beautifully. On a clean project, "of 3 JSON structures the 2 stock ones
are `1..1` and the one mxcli wrote is `0..0`" is an airtight result. In a 31-structure project it
is a hypothesis.

Keep the real model out of the blast radius. Byte-patching scripts and unproven experiments go to
the scratch project first, always.

## 12. Ship-readiness checklist

- [ ] Runs against a blank project created by `mxcli new` — no missing module, role, layout or class
- [ ] No `create or replace navigation`
- [ ] No hardcoded environment values — URLs via a Mendix constant
- [ ] Any theme classes either shipped as CSS or replaced with Atlas primitives
- [ ] No assumption that a user role called `User` exists
- [ ] Every known post-exec step scripted, or documented with the symptom it prevents
- [ ] A troubleshooting table mapping each silent failure to its cause
- [ ] Header records every deviation, with dates and evidence

---

**Related:** `learned-mdl-preflight.md` and `ui-preflight-pages.md` (read these two FIRST, see
above) · `oneshot-page-structure-patterns.md` (the layout layer one level down — containers,
spacing, flex/grid orientation) · `learned-mcp-patterns.md` (what to do when the STOP table sends
you to MCP) · `tool-output-is-not-ground-truth.md` (§7 generalised) ·
`mpr-corruption-and-sp-load-errors.md` (when §6 goes wrong anyway) · `measured-claims.md` (§9).
