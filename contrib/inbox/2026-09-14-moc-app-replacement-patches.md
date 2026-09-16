**From:** moc-app-replacement
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in moc-app-replacement/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/check-design-portability.sh — STALE: identical to shipped e3ee6fb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin check-design-portability.sh

- bin/exec.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin exec.sh

- bin/snapshot-mpr.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

## bin/page-fidelity.js differs from shipped project-bin/page-fidelity.js — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 43622af (2026-09-09), 43 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/page-fidelity.js
+++ project/bin/page-fidelity.js
@@ -171,29 +171,25 @@
   // miss on a page whose real H1 is correct. Two faithful pages at 9%.
   s = dropBalanced(s, /<(div)[^>]*class="[^"]*\banno\b[^"]*"/i);
   s = dropBalanced(s, /<(table)[^>]*class="[^"]*\bbind\b[^"]*"/i);
-  // `.bound` — THE AUTHOR SAYING "this text is a sample of bound data".
-  //
-  // The scorer already has this concept and applies it structurally: `<td>` is excluded
-  // from the text corpus because a wireframe's table cells are sample rows, and a page that
-  // correctly BINDS them contains none of that literal text. The same is true of any bound
-  // value anywhere else on the screen, and there the structure gives nothing away — an
-  // `<h1>` holding a project's number and name looks exactly like an `<h1>` holding page
-  // copy, and a chip holding a filename looks exactly like a chip holding a label.
-  //
-  // Measured 2026-09-09 on a MOC/PSSR app replacement's project detail page: 54%, with all
-  // three misses being sample values a correctly binding page cannot contain — the record's
-  // own title, and a mocked attachment's filename, twice. The page was right; the
-  // denominator was.
-  //
-  // So this is DECLARED, not guessed. A wireframe marks its bound sample values
-  // `class="bound"` and they leave both the text corpus and the class denominator. Guessing
-  // was the alternative and it does not work: a heading is bound or it is not, and only the
-  // person who drew the screen knows which. Any element may carry it — the drop is on the
-  // tag the class sits on, so `<h1 class="bound">` leaves no heading behind and
-  // `<span class="bound">` inside a chip leaves the chip.
-  for (let i = 0; i < 12; i++) s = dropBalanced(s, /<([a-z][a-z0-9]*)[^>]*class="[^"]*\bbound\b[^"]*"/i);
   // A "this screen is descoped/annotation-only" banner is chrome, not page copy.
   s = dropBalanced(s, /<(div)[^>]*class="[^"]*alert[^"]*"(?=[\s\S]{0,400}?DESCOPED)/i);
+  // `class="bound"` — THE SAMPLE VALUE MARKER. Same reasoning as the <td> exclusion
+  // above: a wireframe's table cells are sample ROWS, so a page that correctly binds
+  // them contains none of the literal text. That is equally true of a bound value
+  // ANYWHERE else, and outside a table the structure gives nothing away — an <h1>
+  // holding a project's number and name looks exactly like an <h1> holding page copy.
+  //
+  // Measured 2026-09-09 on a MOC/PSSR app replacement's project detail page: 54%, and
+  // all three misses were sample values (the record's own title, a mocked filename
+  // twice). The page was right and the denominator was wrong.
+  //
+  // The element is KEPT and only its text is emptied: the marker sits on the smallest
+  // element holding the value, and dropping the subtree would also take the heading or
+  // chip that wraps it out of the structure. The class itself leaves the denominator at
+  // the `classes` filter below — a page cannot declare a marker that means "this is a
+  // sample".
+  s = s.replace(/(<(h[1-6]|span|p|div|li|td|th|label|strong|em)\b[^>]*class="[^"]*\bbound\b[^"]*"[^>]*>)[\s\S]*?(<\/\2>)/gi,
+                (_, open, _tag, close) => open + close);
   return s;
 }
 
@@ -222,7 +218,24 @@
 // The wf- prefix is already the annotation vocabulary elsewhere in this file (see the
 // class-denominator filter in wfFacts), so the rule is the prefix, not a name list.
 // The unprefixed entries are vocabulary, same as .userchip and table.bind in contentOf.
-const SCAFFOLD_CLASSES = ['bind', 'bt', 'section-h', 'anno-wrap', 'rail-note', 'anno'];
+//
+// THE SAME DELETION, A THIRD TIME (measured 2026-09-11, this project). The design
+// system grew a section vocabulary — `.ds-section` + `.ds-sectionhead` — and the
+// project detail wireframe was rebuilt as three of them. Three uses is repetition,
+// so the repetition test above called every section a bound-data mock and
+// dropBalanced deleted all three subtrees: the payload grid, the approval chain and
+// the assessment matrix left the corpus together. The page scored 0% (headings 0/1,
+// everything else 0-of-0) on a wireframe that had just got BETTER. A layout band is
+// repeated by construction — that is what a section is — so repetition cannot be the
+// test for it, and the fix is the same one this file already applies to `.anno` and
+// `.wf-*`: name the structural vocabulary and exempt it.
+//
+// Only LAYOUT classes belong here. A repeated ds-* class that wraps one row of sample
+// data (`.ds-stage`, `.ds-state`, `.usercard`) is a real mock and must keep falling
+// through to the repetition test.
+const SCAFFOLD_CLASSES = ['bind', 'bt', 'section-h', 'anno-wrap', 'rail-note', 'anno',
+                          'ds-section', 'ds-sectionhead', 'ds-card', 'ds-cardhead',
+                          'ds-cardbody', 'ds-pagewrap', 'ds-stepper', 'ds-progress'];
 const isScaffoldClass = c => /^wf-/.test(c) || SCAFFOLD_CLASSES.includes(c);
 
 function localMockClasses(html) {
@@ -313,7 +326,7 @@
                     ...grab(/<div class="muted"[^>]*>([\s\S]*?)<\/div>/gi)];
   const classes = new Set();
   for (const x of main.matchAll(/class="([^"]+)"/g))
-    x[1].split(/\s+/).forEach(c => { if (c && c !== 'bound' && !/^(wf-|ann|crosscheck|alert-ic|x-btn|req)/.test(c)) classes.add(c); });
+    x[1].split(/\s+/).forEach(c => { if (c && !/^(wf-|ann|crosscheck|alert-ic|x-btn|req|bound$)/.test(c)) classes.add(c); });
   // Classes confined to the wireframe's table.grid mock describe markup the
   // DATAGRID widget renders itself (wrapper, filter row, cell emphasis) — a page
   // cannot declare them. Curated: pill/status classes stay scored, because a page
```

4 stale (one line each) · 1 local fix(es) (diffs above)
