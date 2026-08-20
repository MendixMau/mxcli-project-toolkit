# mxlabs mxcli v0.18.0 retest — 2026-08-20

Ten logged bugs retested against a freshly built v0.18.0. Investigation only. No GitHub issues
filed. No real project modified — every probe ran in a throwaway sandbox copied from a small
scratch reference app.

## Gate 0 — binary tested

- Repo: `~/Mendix/mxcli` (remote `https://github.com/mendixlabs/mxcli.git`)
- `git fetch --all --tags` → `origin/main` moved `55107169..8b7f1fa2`; HEAD left at tag `v0.18.0`
- **Commit tested: `0dda3a76`**, `git describe --tags` = `v0.18.0` (clean tree, not `-dirty`)
- Built with `make build`; ldflags stamped `-X main.Version=v0.18.0`
- Verified: `mxcli version v0.18.0 (2026-08-19T23:27:58Z)`
- A/B arm: the previously installed `v0.17.0 (2026-08-10T05:12:17Z)` at `~/.local/bin/mxcli`

## Test environment and its limits — read before trusting a verdict

- Baseline: a small scratch reference app, **Mendix 11.12.0**, **MPR v2 split tree** (74 KB
  `.mpr` index + 203 entries / 384 files under `mprcontents/`).
- **The baseline is not clean.** It carries **3 pre-existing, unrelated errors**: one `CE0066`
  on the `RouteShowcase` domain model and two `CE5015` object-mapping errors. Every verdict
  below is stated *relative to that control number*, not against zero.
- **The cached mxbuild binaries under `~/.mxcli/mxbuild/` are Linux ELF** and fail with
  `exec format error` on this macOS host. `mxcli docker check` therefore resolved to the local
  Studio Pro 11.12.0 Beta `mx` — a real Mendix consistency checker, and the layer that emits
  `CE####` codes, but **not** a containerised build and **not** `mxbuild --target=package`.
- One attempted full `docker build` died in the web-UI export on
  `System.IO.FileNotFoundException: Microsoft.macOS 26.4.0.0` — a broken local mxbuild install,
  unrelated to any model.
- **ADR-0008 write-elision trap.** v0.18.0 elides a write that changes nothing, which looks
  identical to the silent-no-op symptom several of these bugs have. Every decisive step was
  re-run under `MXCLI_ALWAYS_WRITE=1`, with state read back from disk in a fresh process. No
  verdict below rests on a success line alone.

## Verdicts

| Bug | Verdict | Fixed in | Build-verified |
|---|---|---|---|
| BUG-33 cross-module assoc nav needs FQ path | **FIXED** | v0.18.0 | yes |
| BUG-38 DropdownFilter association mode | **FIXED** | v0.18.0 | yes (0 errors) |
| BUG-61 CALL JAVA ACTION `Microflow` param | **FIXED** | v0.18.0 | yes |
| BUG-59 GRANT drops association → CE0066 | **FIXED** | **v0.17.0** | yes |
| BUG-60 `docker check` collapses v2→v1 | **FIXED** | **v0.17.0** | yes (+ positive control) |
| BUG-11 DataView datasource retype | PARTIAL | v0.18.0 | yes |
| BUG-62 SNIPPETCALL params | PARTIAL | v0.18.0 | yes |
| BUG-30 `currentDeviceType()` | PARTIAL | v0.18.0 | yes |
| BUG-26 `--mcp exec` ALTER PAGE | PARTIAL | v0.18.0 | no (no `.mpr` mutated) |
| BUG-82 cannot clear a validation rule | **STILL OPEN** | — | yes |
| BUG-63 `write-lint-rules.md` wrong API values | **STILL OPEN** | — | n/a (verified by inspection) |

## Two provenance corrections — the most important result here

**BUG-59 and BUG-60 were both fixed in v0.17.0, the version already installed.** A/B runs show
v0.17.0 behaving identically to v0.18.0 on every probe. Had these been closed off the v0.18.0
changelog's adjacent-sounding entries, both would have credited the wrong release.

- BUG-59: v0.18.0's three access-rule fixes (generalization-inherited `GRANT`, specialization
  `CE0066`, `CE1613` on dropped associations) are a **different code path** and were not
  exercised by this repro.
- BUG-60: the real fix is `88077af1` (#763 / PR #764, 2026-07-17), in tag v0.17.0. v0.18.0's
  `41c2a862` solves a different problem — making the tool's repairs *persist* through the
  restore. **The bug was filed 2026-08-07, three weeks after its own fix commit**, against a
  locally-built `./mxcli` predating it.

**Lesson for the provenance convention:** "mxcli version when found" must record the *exact
binary* — a tag, or `git describe` output for a local build — not a release number. A locally
built `./mxcli` can be arbitrarily far behind or ahead of any tag.

## New defects surfaced by this sweep — none previously logged

Four of the seven are silent-success defects, the class this log exists to catch.

1. **Reverse cross-module association traversal is mis-written.** The qualifier inserts the
   association's *target* entity regardless of direction, leaving a dangling step and a
   four-step path. `check` and `exec` both silent. (from BUG-33)
2. **`SET DataSource = DATABASE Module.Entity` on a DATAVIEW silently wipes the datasource**,
   reports success, and surfaces only later as `CE7007`. Should be an MDL-time rejection like
   the association form already is. (from BUG-11)
3. **`ALTER ENTITY … DROP ATTRIBUTE` never deletes the attribute's validation rule.** With
   other attributes present it orphans the rule → `CE1613`, and re-adding a *plain* attribute of
   the same name silently resurrects the constraint. If the rule-bearing attribute is the
   entity's only one, the drop is a **total silent no-op**. **Present in v0.17.0 too** — not a
   v0.18.0 regression. (from BUG-82)
4. **MDL044's new write barrier is microflow-only.** `validateMicroflowRules` is never called
   from `execCreateNanoflow`, so the same expression in a `create nanoflow` passes `check`, is
   written by `exec`, and fails the build with `CE0117`. `check` does not even lint it. (BUG-30)
5. **`DESCRIBE JAVA ACTION` drops the type-parameter name**, printing `entity <>`. Does not
   round-trip. Present in v0.17.0 too. (from BUG-61)
6. **v0.17.0 `--mcp exec … SET Title` reports success while writing a truncated page body back**
   — silent whole-page destruction against Studio Pro 11.13. Operationally urgent for anyone
   still on v0.17.0 doing MCP page edits. (from BUG-26)
7. **v0.17.0 writes a DropdownFilter in attribute mode when association mode was asked for** —
   silently, with a green build, producing a filter that does not filter. (from BUG-38)

## Notable non-verdict findings

- **BUG-26 root cause identified.** Studio Pro 11.13's `pg_read_page` defaults to `depth: 4`.
  Measured live, read-only: **162 chars at default depth vs 18,356 at `depth: 1000`** on the same
  real page. Because ALTER PAGE is read-modify-replace-whole-page, that truncated body was both
  the tree the anchor lookup searched (symptom 1) and the body written back (symptom 2). One
  defect, both symptoms. `git diff v0.16.0..v0.18.0` shows `findWidget` byte-identical — v0.18.0
  fixes only the *input* those consume, which is why one change covers both.
- **BUG-26 open gap:** the entry was filed against Studio Pro **11.12.1**, and the `depth`
  argument is **11.13-only**. Whether 11.12.x truncates is undetermined. Keep the STOP rule for
  11.12.x; on 11.13, re-enable `--mcp exec ALTER PAGE` only after one supervised write to a
  disposable page.
- **BUG-62's own 2026-08-11 CORRECTION is now obsolete** — a working in-mxcli form exists
  (`REPLACE … WITH { SNIPPETCALL n (Snippet: M.S) }`, no `Params`). Studio Pro's *Refresh snippet
  parameters* step is no longer required.
- **BUG-82 narrowed usefully:** `MODIFY ATTRIBUTE` correctly *adds* a rule and correctly
  *changes* an existing rule's message. Only removal is dropped — the diff-and-apply has no
  delete branch. v0.18.0's new `CREATE VALIDATION RULE` grammar does not help: there is no
  `DROP VALIDATION RULE` (hard parse error), and the topic explicitly routes REQUIRED/UNIQUE back
  to the broken `MODIFY ATTRIBUTE` path.
- **BUG-59 sub-sighting unresolved.** The 2026-08-13 entity-level trigger (new entity +
  `EXTENDS System.FileDocument` + entity-level `GRANT`, zero associations) did **not** reproduce
  in a clean baseline on *either* binary. Neither fixed nor open — needs a retest on a project
  that actually carries it.

## Documentation gaps worth folding into the skills

- **DropdownFilter association mode is entered implicitly**, by giving the filter a `DataSource:`.
  No explicit mode keyword exists. Discoverable only from
  `sdk/widgets/definitions/dropdownfilter.def.json`; `mxcli syntax page widgets` says nothing.
- **`mxcli syntax` contradicts itself on MODIFY ATTRIBUTE.** `syntax validation-rule` documents
  `MODIFY ATTRIBUTE <name> <type> <constraints>` (no colon); `syntax domain-model.entity.alter`
  still lists only `MODIFY ATTRIBUTE AttrName SET DEFAULT val`. Both forms parse identically.
- **A type-parameter-filling java action param declared without `not null`** is accepted silently
  by mxcli and fails the build with `CE0163`.
- **`[%CurrentDeviceType%]` is not a valid substitute inside a nanoflow expression.** BUG-30's
  logged workaround holds for page conditional visibility only; applied in a flow context it
  swaps one `CE0117` for another.

## Not retested

- Page conditional-visibility expressions (BUG-30's other named surface).
- `docker build` / `run` / `reload` and the non-docker `exec` write path (BUG-60's #808 sites).
- A genuine marketplace-imported `.mpk` java action (BUG-61 used an mxcli-declared action).
- BUG-26 symptom 2 end-to-end: no live write was performed.
- The other 57 open entries in `mxcli-bugs.md`. **Nothing in this file licenses closing them.**
