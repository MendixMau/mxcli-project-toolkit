# Four instruments from the Academy 10.18 -> 11.12 run (backlog #28, #29, #31, #32): designs

Read: BACKLOG #28/#29/#31/#32, FEEDBACK AM-T6, AM-U10, AM-U2, AM-U9, AM-M3; bin/smokewalk.js (clickStep, landed), smokewalk_gen.py (plan steps already carry `url` = page Url), gen_journeys.py
(menu_journey, `nav` verb), impact_map.py (has_navigation, nav_sources, popup_key: TypePointer -> PropertyKey), mprmodel.py (Model.load v1/v2, widgets()), stepupdate.sh (FILES-UNKNOWN,
--accept-unsaved, `step: <Mod> <ver> (stepupdate` subjects), localedits.py/themefiles.py (files layer, compare rules), repair/design_props_guard.sh, repair/pds_oldnames.sh, widgetdiff.py,
controls/run-controls.sh + lib/capture_units.py (captured goldens; note it PRUNES styling keys).

## Ranking (value per effort)
1. #31 git history proof (S). Removes the --accept-unsaved hand step for any package that answers HTTP 500. Reuses themefiles compare rules.
2. #29 update-widgets reset check (M). Only detector for silent behaviour loss (admin options MF, child widget); nothing else sees it.
3. #28 open by URL (M). By the backlog's own rule (apps moved out of INVALID) this is first: 38/51 smoke and 27/41 menu rows.
4. #32 design-property oldName scan (M, diagnostic). Explains CE6087 with no location; pds_oldnames.sh already fixes the common case.

## #31 Theme files unedited, proved by git (S) -> bin/themefiles.py `history` + stepupdate.sh FILES-UNKNOWN branch
Inputs: app dir (git work tree), module M, installed version V (MPR AppStoreVersion, or stepupdate's proven version from the log). Paths P = themesource/<m>/, javascriptsource/<m>/, javasource/<m>/
(user code only, via usercode.py).
Algorithm: (1) Preconditions, else UNKNOWN with reason: not a git repo; `git rev-parse --is-shallow-repository` = true; P has untracked or ignored files (`git ls-files -o -i --exclude-standard -- P`,
`git check-ignore`); P has staged/unstaged changes. (2) Install commit C = newest commit touching P: `git log -1 --full-history --format=%H -- P` (full-history so a merge side branch is not simplified
away). C must change M's version: read M's version at C and C^ (`git show C:<mpr>` for v1, the module unit under mprcontents/ for v2; mprmodel on a temp extract); version(C) == V and version(C^) != V
(or M absent at C^). A merge as C -> UNKNOWN. A newest touching commit that does NOT change the version = an edit commit after install -> not proven (see 4). (3) Content check, not just log emptiness:
for every file in P at C and now, themefiles' compare (CRLF, generated headers, JS action import set + USER/EXTRA CODE blocks) says equal; file sets equal. (4) If a post-install commit touched P, the
diff C..work tree under the same compare rules is the local edit list -> FILES-EDITED rows (history-proved), handled like any edit.
Output: `FILES-UNEDITED-BY-HISTORY <M> since <sha7> <date> "<subject>" (<n> files, provenance: toolkit step | person commit)`, or `FILES-EDITED <path> (by history, since <sha7>)`, or `FILES-UNKNOWN
<M>: <reason>`. Exit 0/1/2 like --files-only.
Plug-in: stepupdate.sh, where `fstate=unknown` is set: run `themefiles.py history`; 0 -> fstate=clean-history (commit allowed, line recorded in overwritten.txt as "proven by git, not by the package"),
1 -> fstate=edited, 2 -> unchanged FILES-UNKNOWN path.
Fails safe: every precondition gap is UNKNOWN, never clean. Residual risk said in the output: a person who edited a file in the SAME commit that installed V is invisible; provenance "toolkit step"
(subject `step: M V (stepupdate`) is strong, "person commit" is labelled weaker and listed in the summary verdict line. Non-vacuous: prints n files compared; n = 0 with P non-empty is UNKNOWN.
Controls (synthetic git repo built in the control, v1 MPR via mkmodel): catch = install commit then a later commit editing themesource/<m>/web/_variables.scss -> FILES-EDITED by history; catch =
shallow clone -> UNKNOWN; catch = untracked file in P -> UNKNOWN; pass = install commit, later commits elsewhere only, Studio Pro regenerated header on a JS action -> UNEDITED, stepupdate commits
without --accept-unsaved. Mutant: drop the version check on C -> an edit-only commit read as the install must be caught. Done when: PDS 42.0.0 on Academy needs no --accept-unsaved (field run, cited).

## #29 update-widgets reset check (M) -> bin/widgetreset.py <before> <after>, wrapped around repair row 5 and stepupdate
Inputs: before and after model (dir/.mpr, or `--rev <commit>` extracted with `git archive` like stepupdate's prevtree), v1 or v2 on either side (update-widgets turns v2 into v1, NR2-14; mprmodel reads
both). widgets/*.mpk versions via widgetdiff.py.
Algorithm: (1) every CustomWidgets$CustomWidget in pages, snippets, layouts (all modules); identity = (doc QN, widget Name), $ID as tie-break; unmatched widgets listed. (2) Resolve each property by
PropertyKey (Object.Properties[].TypePointer -> Type.ObjectType.PropertyTypes[].$ID, as impact_map.popup_key), recursing into object lists (key path `items[3].caption`). (3) Project each Value to
meaning, ids dropped: primitive, expression, attribute/entity path, data source, action (type + target), microflow/nanoflow, TextTemplate/Translatable per LANGUAGE (every language, not en only),
icon/image, child widget list (names + types, recursive). (4) Classify per (widget, key): LOST = before set (non-empty and not equal to the old type's default) and after empty/default/absent;
CHILD-LOST = a child widget name present before and absent from the whole after document (moved is not lost); TRANSLATION-LOST = a language text emptied; KEY-REMOVED = key absent from the new type and
before value set (REVIEW: the package dropped it, name the version pair); CHANGED = both set and different (REVIEW); DEFAULT-CHANGE = before = old default and after = new default (info, not a loss).
Accept file: (widget id, key, version pair, reason).
Output: one line per finding `LOST <doc> <widget> <widgetId> <key>: "<before>" -> empty`, per-widget-id counts, denominator line `D documents, W widgets, P values compared, U unmatched`. Exit 0 PASS /
1 RED (any LOST, CHILD-LOST, TRANSLATION-LOST) / 2 INVALID.
Plug-in: wrap `mx update-widgets` in steps/repair.md row 5 and bin/cloud/upgrade-pipeline.sh try_fix "update-widgets" (snapshot the model first, diff after; RED stops before commit with the before
values to restore by a direct model edit, since mxcli has no MxDock properties, AM-U8); stepupdate runs it after each step whose widgetdiff shows a changed package; gate widgets rung shows the ledger.
Non-vacuous: W = 0 while widgets/ holds packages used by pages -> INVALID; before == after byte-equal -> NO-OP line; U > 0 listed. mx check's REQUIRED-only view is printed beside it so the gap is
visible.
Controls: golden captured, never hand-written: run `mx update-widgets` on a scratch app holding a Marketplace module page with an older package, capture before/after units with capture_units.py
(Marketplace names only). Must-catch: a Link caption emptied in 2 languages (TRANSLATION-LOST x2), a Form Label whose child Date picker is gone (CHILD-LOST), MxDock getAdminOptionsMf and
userProfileProviderMf emptied (LOST x2). Must-pass: same package version both sides; a default that moved with the package (DEFAULT-CHANGE only); a renamed key in the accept file. Field control on the
Academy pair under UPG_LAB (SKIP without), expecting 30 Link captions. Mutant: compare en only -> the second-language loss must be caught.

## #28 Open a page by URL when the menu is not rendered (M) -> smokewalk_gen.py, smokewalk.js, gen_journeys.py, journey-verbs.js
When: decided from the MODEL at plan time, never as a silent runtime fallback. Per role, impact_map.nav_sources over the home page's layouts: no ("profile", <Responsive>) source -> the menu is not
rendered for that role (AM-U10); a pluggable menu (e.g. MxDock) or menu document counts as "another menu". Menu steps for that role are not planned; their slot becomes `via: "url"`.
URL: page `Url` from the model (plan already has `url`) -> `<app>/p/<url>`; microflow URL only where the microflow document carries a Url (read it, never guess a pattern); a URL with `{...}`
parameters needs an object -> SKIPPED "parameter URL, no seed". No URL -> INVALID "no page URL and the menu is not rendered" (counted apart, so the denominator shrinks honestly). Also fix the 4 FAILs:
menu clicks pin the menu widget name from the layout (`.mx-name-<menuWidget>-<path>`), not any `mx-name-*-<path>`; a positional id with two candidates is INVALID, never a click.
Runner: smokewalk.js `via: "url"` -> page.goto, landed() as today (expected page_path, landedOk, errors); verdict PASS/FAIL.
Journeys: gen_journeys emits `open-by-url-<page>-<role>` with `{"do": "url", "path": ...}` and tag `menu-not-proven`; the menu journey for that role becomes a NOT APPLICABLE row "layout renders no
navigation menu (model: <layout>)", not INVALID, not PASS.
Honesty label: every URL step prints `PASS (by URL: page renders for <role>; menu NOT proven)`; summary splits "menu steps judged: 0 of N (not rendered, model)" from "pages by URL: x PASS / y FAIL";
report.md says it in the verdict line. A URL bypasses visibility, not access: only pages the role may open are planned (existing allowed() filter). Old/new compare keys include via, so a menu step on
one side and a URL step on the other is INVALID, never a pair.
Controls: must-catch = fixture model whose layout has a MenuDocumentSource only: the plan has no menu steps for that role and the URL steps are labelled; must-catch = two menus with the same
positional suffix: the click is pinned or INVALID (smokewalk_predicates.js); must-pass = a normal profile-menu app plans menu steps unchanged (no URL steps). Done when Academy smoke 38/51 and menu
27/41 leave INVALID.

## #32 Design-property oldName scan for CE6087 with no location (M) -> bin/designprops.py, run before repair row 6
Inputs: app dir: every themesource/*/web/design-properties.json (and native/), the MPR; optional mx check output.
Algorithm: (1) Index definitions per widget type key ("Widget", "DivContainer", pluggable widget id ...): current property names, options, compound sub-properties, and every oldNames entry at property
and option level, with the declaring module. (2) SHADOW rows: an oldName in module A equal to a CURRENT name in module B for the same type (the Academy case: own theme module lists current Atlas names
as oldNames). (3) Walk every widget of every page/snippet/layout (all modules), read Appearance.DesignProperties (Key; Toggle / Option / Compound Properties[] / Custom, shape as in
impact_map.hidden_on_desktop), map the widget $Type to the json type key (mapping verified on a real model first: field-proof). (4) Per stored value: OLDNAME (matches an oldName; name the declaring
module and current name, flag SHADOWED), UNDEFINED (no current definition: the CE6087 candidates), OK. Output grouped per widget type and per owning module (own vs Marketplace: Marketplace pages are
the ones the headless rename skipped and mxcli cannot write, AM-U6), with counts; `EXPLAINS k of n CE6087` when mx check output is given. Exit 0 none / 1 OLDNAME or UNDEFINED rows (REVIEW) / 2
INVALID.
Plug-in: steps/repair.md row 6 and upgrade-pipeline: scan before design_props_guard, rescan the guard's copy after the rename; rows left = what the rename skipped, with page and widget, for a hand fix
or the pds_oldnames route. Non-vacuous: prints values scanned; 0 values while pages exist -> INVALID; k < n -> "unexplained n-k CE6087" stays REVIEW, never PASS.
Controls: golden captured with capture_units.py extended by `--keep Appearance` (it prunes styling today). Must-catch: an own theme module with oldNames "Spacing" (a current Atlas name) and a
Marketplace page widget storing an Atlas 3 Spacing compound value -> SHADOW + OLDNAME row under the Marketplace module. Must-pass: all stored values current -> 0 rows, values scanned > 0. Mutant: drop
the option-level oldNames index -> the Spacing value must still be caught.

