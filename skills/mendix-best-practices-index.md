# Mendix Best-Practices Index — Where Each Practice Lives, Before and After the Write
**Applies to:** any mxcli project.

**Purpose:** Answer "is there a Mendix best practice for this, and what enforces it here?" with
one row, not a search. Each row names the Mendix page that states the practice, the section of
the mxcli-bundled `assess-quality` skill that summarises it, the toolkit skill that applies it
**before** the MDL is written, and the `mxcli lint` rule that catches it **after** exec.
This file is an index, never a copy: the practice text stays on the Mendix page and in the
bundled skill (`CLAUDE.md` authoring rule 5). URLs verified 2026-09-25, all HTTP 200.

---

## How to use it

1. **Before writing** — find the row for the thing you are about to build. Open the toolkit
   skill in that row. If the row says "no toolkit skill", read the Mendix page itself.
2. **After exec** — the lint ratchet's BUILD-LOG cell lists the rules that rose. Look each rule
   up here to find the practice behind it and the skill that would have prevented it.
3. **When a question has no row** — say so in chat and read the Mendix page under
   `Development Best Practices`. Do not answer from memory; add the row afterwards.

## The index

Lint IDs are those `mxcli lint --list-rules` prints on v0.24.0. `MXP` numbers are Mendix's
own Best Practice Recommender rules, which Studio Pro also reports.

| Area | Mendix source (states the practice) | Bundled `assess-quality` | Toolkit skill — before the write | `mxcli lint` — after exec |
|---|---|---|---|---|
| Naming: prefixes, entities, pages, enums, booleans | [Development Best Practices](https://docs.mendix.com/refguide/dev-best-practices/) → App Setup Best Practices | §A Naming Conventions | `learned-mdl-preflight.md` (names are fixed before the first line) | MPR001, CONV001, CONV003, CONV004, CONV005, CUSTOM002 |
| Microflow size and single responsibility | [Extracting and Using Sub-Microflows](https://docs.mendix.com/refguide/extracting-and-using-sub-microflows/) | §D Maintainability | `microflow-preflight.md` (tiers, split-first) | CONV009 (15, top-level), QUAL003 (25, top-level), QUAL001 (McCabe 10) |
| Commit and create inside a loop | [Best Practice Recommender](https://docs.mendix.com/refguide/performance-best-practices/) MXP004, MXP005, MXP012 | §E Performance | `microflow-preflight.md`, `mdl-cookbook-microflows.md` (collect-then-commit) | CONV011 |
| Retrieve, REST or Java call inside a loop | [Community Best Practices for App Performance](https://docs.mendix.com/refguide/community-best-practices-for-app-performance/) → Microflow | §E Performance | `microflow-preflight.md`, `microflow-loop-antipatterns.md` | **none** — the preflight checklist is the only check |
| Bounded lists, batching | [Community Best Practices for App Performance](https://docs.mendix.com/refguide/community-best-practices-for-app-performance/) → Microflow | §E Performance | `microflow-preflight.md` | **none** (`mxcli check` MDL068 catches an unbounded `range` only) |
| Writes late in the flow, one commit | [Best Practice Recommender](https://docs.mendix.com/refguide/performance-best-practices/) MXP014 | §E Performance | `microflow-preflight.md` | none |
| Error handling on external calls | [Error Handling in Microflows](https://docs.mendix.com/refguide/error-handling-in-microflows/) | §G Error Handling | `learned-microflow-patterns.md` (no `on error` inside a loop body, CE0644), `rest-integration-first-time-right.md` | CONV013, CONV014 |
| Validation in `VAL_` flows, not entity rules | [Setting Up Data Validation](https://docs.mendix.com/refguide/setting-up-data-validation/), [Validation Rules](https://docs.mendix.com/refguide/validation-rules/) | §D Maintainability | `mdl-cookbook-microflows.md` | CONV015, MPR004 |
| Event handlers and calculated attributes | [Best Practice Recommender](https://docs.mendix.com/refguide/performance-best-practices/) MXP001, MXP002 | §E Performance | `modularize-domain.md` | CONV016, CONV017 |
| Entity access rules and XPath row scoping | [Access Rules](https://docs.mendix.com/refguide/access-rules/), [Implement Best Practices for App Security](https://docs.mendix.com/howto/security/best-practices-security/) | §C Security | `security-is-not-a-later-script.md` | SEC001, SEC004–SEC009, CONV006, CONV007, CONV008 |
| Indexes for sort and XPath attributes | [Indexes](https://docs.mendix.com/refguide/indexes/), Recommender MXP003, MXP007, MXP016 | §E Performance | `modularize-domain.md` | none |
| Module boundaries, cross-module data on pages | [Community Best Practices for App Performance](https://docs.mendix.com/refguide/community-best-practices-for-app-performance/) → Domain Model | §F Architecture | `modularize-domain.md`, `module-dependency-review.md` | ARCH001, ARCH002, ARCH003, MPR003, DESIGN001 |
| Pages: nesting, grids, forms | [Community Best Practices for App Performance](https://docs.mendix.com/refguide/community-best-practices-for-app-performance/) → Pages, Recommender MXP011 | §I UI Best Practices | `ui-preflight-pages.md`, `learned-dg2-patterns.md`, `learned-page-patterns.md` | MPR005, MPR006, MPR009, MPR010, MPR012 |
| Navigation page security | [Access Rules](https://docs.mendix.com/refguide/access-rules/) | §C Security | `security-is-not-a-later-script.md` | MPR007 |
| Documentation on entities and microflows | [Development Best Practices](https://docs.mendix.com/refguide/dev-best-practices/) | §D Maintainability | `learned-microflow-patterns.md` (annotation discipline) | QUAL002 |
| Microflow canvas layout | [Extracting and Using Sub-Microflows](https://docs.mendix.com/refguide/extracting-and-using-sub-microflows/) (readability) | — | `microflow-preflight.md` → Layout | MPR008, MPR011 |
| Testing | [Testing](https://docs.mendix.com/refguide/testing/) | — | `testing-shape.md`, `learned-db-assertions.md` | none |

## What is not here, on purpose

- **The practice text.** Mendix edits these pages; a copy here would be stale within a release.
- **A quality score.** `mxcli report -p app.mpr` scores six categories from the same rules; the
  bundled `assess-quality` skill is the full assessment method (`skills/existing-app-assurance.md`
  routes there).
- **Rules the binary does not ship.** CUSTOM001/CUSTOM002 and the `example_*` rules come from a
  project's `.claude/lint-rules/`; list your own with `mxcli lint -p app.mpr --list-rules`.
- **A knowledge graph of the docs.** The consumer of this file is an agent mid-task; a table
  gives it the same routing at no maintenance cost.

## Keeping it true

A row is wrong the day a URL 404s or a rule ID is renamed. When you find one: fix the row in the
same commit as the change that surfaced it, and re-check the URL with `curl -sI`. A rule that
rises in the ratchet and has no row here gets a row.
