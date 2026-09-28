> **Triage note (2026-09-27, hand-checked):** the one LOCAL-FIX (`bin/page-fidelity.js`) is only
> partly a fix that never traveled. Already upstream (85da9d6): ALTER PAGE image bindings and the
> CUT-row skip. NOT upstream yet, worth promoting: `contractRows()` (five-column bind table read
> as the class contract) and `cssCellClasses()` with a `FILE_EXT` set (stops `ds.css` being
> counted as a `.css` class). The shipped copy is ahead on prototype-route support, which the
> project copy lacks — so the promotion is a merge of two functions, not a copy-over. The 11
> STALE rows are ordinary sync lag (`sync-project.sh --upgrade-bin`), no toolkit action.

**From:** a field project
**Date:** 2026-09-27
**Kind:** fix
**Field evidence:** installed toolkit scripts in a field project's bin/ that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/build-plan-status.sh — STALE: identical to shipped 234aa6f (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/check-page-shell.sh — STALE: identical to shipped 43622af (2026-09-09); fix: bin/sync-project.sh <project-root> --upgrade-bin check-page-shell.sh

- bin/close-task.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin close-task.sh

- bin/conformance-check.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

- bin/coverage-preflight.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin coverage-preflight.sh

- bin/fixture-manifest.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin fixture-manifest.sh

- bin/graph-sweep.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin graph-sweep.sh

- bin/page-scope.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin page-scope.sh

- bin/restore-mpr.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin restore-mpr.sh

- bin/review-module.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

- bin/verify-module.sh — STALE: identical to shipped fd60fb8 (2026-09-08); fix: bin/sync-project.sh <project-root> --upgrade-bin verify-module.sh

## bin/page-fidelity.js differs from shipped project-bin/page-fidelity.js — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: aa6ff98 (2026-09-12), 152 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/page-fidelity.js
+++ project/bin/page-fidelity.js
@@ -48,37 +48,18 @@
 // scores as what it is. --no-log suppresses logging entirely (for scoring fixtures or
 // another project's files); an unloggable run says so on stderr rather than logging
 // silently nowhere.
-//
-// A SCREEN IN THE CLICKABLE PROTOTYPE. The wireframe argument may also be a route into the
-// assembled prototype, `design/prototype.html#/order-list` (assemble-prototype.js). The one
-// section is read back out through prototype-route.js, which undoes the only transform that
-// matters to this scorer (scoped screen CSS, where localMockClasses looks), so a screen scores
-// the same as a file and as a route. test-prototype-route.sh pins that. An unknown route exits
-// 2 and names the routes the prototype does have.
 'use strict';
 const fs = require('fs');
 const path = require('path');
-const proto = require(path.join(__dirname, 'prototype-route.js'));
 
 const argv = process.argv.slice(2);
 const NOLOG = argv.includes('--no-log');
 const STUB = argv.includes('--stub');
 const [WF, PAGE, ...MDLS] = argv.filter(a => a !== '--no-log' && a !== '--stub');
 if (!WF || !PAGE || !MDLS.length) {
-  console.error('usage: page-fidelity.js [--no-log] [--stub] <wireframe.html | prototype.html#/route> <page-name> <mdl-file...|->');
+  console.error('usage: page-fidelity.js [--no-log] [--stub] <wireframe.html> <page-name> <mdl-file...|->');
   process.exit(2);
 }
-const WF_REF = proto.parseRef(WF);
-const WF_FILE = WF_REF ? WF_REF.file : WF;
-
-function readWireframe() {
-  if (!fs.existsSync(WF_FILE)) { console.error('page-fidelity: no such wireframe: ' + WF_FILE); process.exit(2); }
-  const html = fs.readFileSync(WF_FILE, 'utf8');
-  if (!WF_REF) return html;
-  const doc = proto.standalone(html, WF_REF.route);
-  if (doc === null) { console.error('page-fidelity: ' + proto.unknownRouteMessage(WF_FILE, WF_REF.route, html)); process.exit(2); }
-  return doc;
-}
 
 // ---- wireframe side -------------------------------------------------------------------
 
@@ -266,11 +247,12 @@
 // in its datasource cell (CamelCase words, Entity.Attr paths) appears in the
 // page MDL. Rows whose cell names no identifier are annotation prose and skip.
 //
-// A row the author struck through (<s>) or whose fifth (Verdict) cell says CUT / NOT
-// BUILDABLE is not owed. bindRows used to skip only header rows, so a wireframe's
-// `<s>Demo chip (curated tiles)</s>` row (verdict "CUT — would be empty on 15 of the 16
-// tiles") was scored as a missed binding on a page that correctly left it out
-// (a field project's catalog page, 2026-09-23).
+// A row the author struck through or marked CUT / NOT BUILDABLE is not owed — the same rule
+// contractRows applies. bindRows used to skip only header rows, so CatalogView-redesign-v2's
+// `<s>Demo chip (curated tiles)</s>` row (verdict "CUT — would be empty on 15 of the 16 tiles")
+// was scored as a missed LastPublishedVersionDemoUrl binding on a page that correctly left it
+// out (field project, 2026-09-23). Two readers of one table disagreeing about which rows count
+// is the defect; notOwed() is the one answer both now use.
 const notOwed = trInner => {
   if (/<s>/i.test(trInner)) return true;
   const raw = [...trInner.matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(c => c[1]);
@@ -293,7 +275,48 @@
   return rows;
 }
 
-function wfFacts(html) {
+// The CONTRACT: a five-column bind table (Component / Widget / Binding / CSS / Verdict) is the
+// author saying which classes the built page must carry. Measured 2026-09-22 on CatalogView_v5
+// against CatalogView-redesign-v2.html: the wireframe defines every class in its own <style>, so
+// the class dimension emptied itself (localMockClasses), the repeated .card left as a "mock", and
+// the page scored 91% on one heading, one paragraph and the identifiers — with none of the card
+// design built. A declared contract is the only reading that survives a wireframe whose whole
+// design is local CSS. Rows the author marked NOT BUILDABLE / CUT / struck through are not owed.
+// The CSS cell is prose as well as selectors — "`.mps-filter-rail` (already a ds.css
+// candidate)" — and the old unanchored /\.([a-z]…)/ harvested `css` out of `ds.css` as a class
+// the page owed (a field project's catalog page, 2026-09-23: `contract: Filter rail (.css)`,
+// 1 of 30 contract items bogus and unfixable by any build). A dot glued to a preceding word is
+// either a FILE NAME (ds.css, main.scss) or a COMPOUND SELECTOR (#mxapp.theme-dark — a real
+// class, and the same table's Dark-mode row owes it). Only the extension is dropped; an
+// anchored lookbehind that dropped both lost .theme-dark on the first re-score.
+const FILE_EXT = new Set(['css', 'scss', 'sass', 'less', 'js', 'mjs', 'ts', 'json', 'html', 'htm',
+  'md', 'mdl', 'csv', 'tsv', 'png', 'jpg', 'jpeg', 'svg', 'gif', 'webp', 'xml', 'txt', 'mpr', 'sh']);
+function cssCellClasses(cell) {
+  const out = [];
+  for (const m of cell.matchAll(/\.([a-z][a-z0-9_-]*\*?)/g)) {
+    const prev = m.index ? cell[m.index - 1] : ' ';
+    if (/[A-Za-z0-9_\/-]/.test(prev) && FILE_EXT.has(m[1].toLowerCase())) continue;
+    out.push(m[1]);
+  }
+  return out;
+}
+
+function contractRows(html) {
+  const t = innerBalanced(html, /<(table)[^>]*class="[^"]*\b(?:bind|bt)\b[^"]*"/i);
+  if (!t) return [];
+  const rows = [];
+  for (const tr of t.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
+    if (/<th/i.test(tr[1]) || notOwed(tr[1])) continue;
+    const raw = [...tr[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(c => c[1]);
+    if (raw.length < 5) continue;
+    const classes = cssCellClasses(strip(raw[3]));
+    if (classes.length) rows.push({ label: strip(raw[0]).slice(0, 40), classes });
+  }
+  return rows;
+}
+
+function wfFacts(file) {
+  const html = fs.readFileSync(file, 'utf8');
   const mock = localMockClasses(html);
   let main = contentOf(html);
   const mockUsed = [];
@@ -355,39 +378,29 @@
   const mockCls = [...classes].filter(c => mockUsed.includes(c) || mock.has(c));
   mockCls.forEach(c => classes.delete(c));
   return { headings, buttons, blocks: blocks.filter(b => b.length > 12), classes: [...classes],
-           gridOnly, mockUsed, structural, mockCls, binds: bindRows(html) };
+           gridOnly, mockUsed, structural, mockCls, binds: bindRows(html), contract: contractRows(html) };
 }
 
 // ---- MDL side -------------------------------------------------------------------------
 
-// MODULE is captured alongside the page body so the run can be RECORDED against a module
```

11 stale (one line each) · 1 local fix(es) (diffs above)
