**From:** DealApp
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in DealApp/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped 491fc02 (2026-08-25); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/check-design-portability.sh — STALE: identical to shipped e3ee6fb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin check-design-portability.sh

- bin/conformance-check.sh — STALE: identical to shipped ea275ea (2026-08-20); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

- bin/exec.sh — STALE: identical to shipped 582c712 (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin exec.sh

- bin/fixture-manifest.sh — STALE: identical to shipped 6e04418 (2026-08-18); fix: bin/sync-project.sh <project-root> --upgrade-bin fixture-manifest.sh

- bin/graph-sweep.sh — STALE: identical to shipped bf938bd (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin graph-sweep.sh

## bin/page-scope.sh differs from shipped project-bin/page-scope.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: a1e27d2 (2026-08-28), 14 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/page-scope.sh
+++ project/bin/page-scope.sh
@@ -84,11 +84,17 @@
 IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
 QNAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$")
 # Column labels that are table furniture, never a page or module name.
+# `SHOW PAGES IN <Module>` gained columns over time and this set did not keep up:
+# "excluded", "folder" and "params" are real column labels, so every module
+# contributed a phantom "<Module>.Excluded" page. Measured on DealIQ 2026-08-28:
+# 6 real pages became 13, and design-audit.js then reported
+# "INSTRUMENT FAULT (94) — this run measured nothing reliable" because 92 of its
+# 132 checks were against pages that do not exist. The 12 genuine findings
+# underneath were invisible. This is F-042's third column-drift instance; the
+# durable fix is to stop hand-listing column labels, so the set below is a
+# backstop and the real guard is that a page must RESOLVE (see is_real_page).
 HEADER_WORDS = {"name", "page", "pages", "module", "modules", "type", "source", "title",
                 "layout", "url", "documents", "count", "excluded", "folder", "params"}
-# F-042 (MarkUseCase, 2026-08-28): SHOW PAGES headers carrying Excluded/Folder/Params
-# columns were parsed as page rows — 6 real pages inflated to 13, so every consumer of
-# page-scope.json measured against a denominator that was half furniture.
 
 def mx(*args, timeout=120):
     """Run one read-only mxcli command. Returns (stdout, error) — error is None on success."""
```

- bin/restore-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restore-mpr.sh

- bin/review-module.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

## bin/snapshot-mpr.sh differs from shipped project-bin/snapshot-mpr.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 43 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/snapshot-mpr.sh
+++ project/bin/snapshot-mpr.sh
@@ -10,81 +10,55 @@
 # to garbage. Ad-hoc `cp Project.mpr Project.mpr.backup` is exactly that mistake
 # and is why this script exists.
 #
-# The model tree is resolved with find_model_dir, NOT $PROJECT_ROOT: on a two-tree
-# checkout (repo at the root, `mxcli new` app under app/) they are different
-# directories, and globbing the repo root matched nothing while still printing
-# "mpr snapshot ok" — see the find_model_dir header in _common.sh for the field
-# incident. The snapshots themselves stay under $PROJECT_ROOT/.mpr-snapshots so
-# they land in one gitignored place regardless of layout.
-#
 # Git commits at phase gates remain the real history — this only covers
 # mid-session corruption between commits.
 set -euo pipefail
 . "$(dirname "$0")/_common.sh"
+cd "$PROJECT_ROOT"
 
-MODEL_DIR="$(find_model_dir)" || exit 1
-
-# A producer guarantees its own output is ignored. This writes a FULL copy of the .mpr and
-# every mprcontents unit, five deep — so a project that does not gitignore it commits the
-# client's whole model several times over, and then reports thousands of phantom deletions
-# the next time the rotation below prunes one.
-#
-# Measured on a MOC/PSSR app replacement, 2026-09-09: 2,089 snapshot files tracked, and
-# `mxcli exec` then REFUSED to run, because exec.sh read the pruned snapshot as uncommitted
-# model changes — this script's output blocking this script's own guard. It is written here
-# rather than in init-project.sh on purpose: here it also reaches every project that already
-# exists, on its next exec, instead of only the ones scaffolded after today.
-if [ -d "$PROJECT_ROOT/.git" ] || [ -f "$PROJECT_ROOT/.git" ]; then
-  GI="$PROJECT_ROOT/.gitignore"
-  if ! { [ -f "$GI" ] && grep -qE '^/?\.mpr-snapshots/?$' "$GI"; }; then
-    # Never fatal: this runs under set -e BEFORE the snapshot, and exec.sh calls it bare — an
-    # unwritable .gitignore must not stop the snapshot (CLAUDE.md guard rule 7).
-    if {
-      if [ -f "$GI" ] && [ -s "$GI" ] && [ -n "$(tail -c 1 "$GI")" ]; then printf '\n'; fi
-      printf '# Pre-exec model snapshots (project-bin/snapshot-mpr.sh). A full .mpr + mprcontents\n'
-      printf '# copy per exec, five kept. Never committed: it is the client model, several times over.\n'
-      printf '/.mpr-snapshots/\n'
-    } >> "$GI" 2>/dev/null; then
-      printf 'snapshot-mpr: added /.mpr-snapshots/ to .gitignore (it was not ignored).\n' >&2
-    else
-      printf 'snapshot-mpr: WARN could not write %s — add /.mpr-snapshots/ to it yourself.\n' "$GI" >&2
-    fi
-  fi
-fi
-
-mkdir -p "$PROJECT_ROOT/.mpr-snapshots"
-DEST="$PROJECT_ROOT/.mpr-snapshots/$(date +%Y%m%d-%H%M%S)"
+mkdir -p .mpr-snapshots
+DEST=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)"
 mkdir -p "$DEST"
 
-MPR_COUNT=0
-for f in "$MODEL_DIR"/*.mpr; do
+# DEREFERENCE, and then PROVE the copy. Measured 2026-09-01, and it cost a full
+# model restore: this project root holds compatibility symlinks
+#   DealIQ.mpr  -> app/DealIQ.mpr
+#   mprcontents -> app/mprcontents
+# `cp` on a symlinked FILE follows it, so the .mpr half was always a real copy.
+# `cp -r` on a symlinked DIRECTORY copies the LINK, not the tree -- so every
+# snapshot contained a real .mpr beside a dangling pointer at app/mprcontents.
+# When that directory later went away, all five snapshots lost their content half
+# at the same instant, having each printed "mpr snapshot ok (.mpr + mprcontents/)".
+#
+# An MPR is a SQLite index plus the BSON units that hold the actual model. A
+# snapshot of either alone restores to garbage, which is what this script's own
+# header has always said -- it just did not check that it had both. So: -L to
+# follow the link, and a count afterwards, because a restore path that fails
+# silently is worse than no restore path at all. You find out it was a placebo
+# at the exact moment you need it.
+for f in *.mpr; do
   [ -e "$f" ] || continue
-  cp "$f" "$DEST/$(basename "$f")"
-  MPR_COUNT=$((MPR_COUNT + 1))
+  cp -L "$f" "$DEST/$f"
 done
-[ -d "$MODEL_DIR/mprcontents" ] && cp -r "$MODEL_DIR/mprcontents" "$DEST/mprcontents"
-
-UNIT_COUNT=$(find "$DEST/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
 
-# An empty snapshot is worse than no snapshot: exec.sh proceeds believing it has a
-# net, and the prune below has already thrown away the older ones. Refuse loudly,
-# and refuse BEFORE pruning, so a bad resolve cannot destroy good history.
-if [ "$MPR_COUNT" -eq 0 ]; then
-  rm -rf "$DEST"
-  echo "✗ snapshot FAILED: no .mpr found in $MODEL_DIR — refusing to record an empty snapshot." >&2
-  echo "  Set MPR_FILE=<path>.mpr (relative to $PROJECT_ROOT) so the model tree resolves." >&2
-  exit 1
-fi
-if [ "$UNIT_COUNT" -eq 0 ]; then
-  rm -rf "$DEST"
-  echo "✗ snapshot FAILED: $MODEL_DIR has no mprcontents/*.mxunit — .mpr alone restores to garbage." >&2
-  echo "  If the model is genuinely v1 single-file, commit it and skip the snapshot net." >&2
-  exit 1
+if [ -e mprcontents ]; then
+  cp -rL mprcontents "$DEST/mprcontents"
+  _src_units=$(find -L mprcontents -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
+  _dst_units=$(find "$DEST/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
+  if [ "$_src_units" -ne "$_dst_units" ]; then
+    echo "ERROR: snapshot copied $_dst_units of $_src_units .mxunit files — this snapshot would NOT restore." >&2
+    echo "       Refusing to leave a snapshot that looks valid and is not: $DEST" >&2
+    rm -rf "$DEST"
+    exit 1
+  fi
+else
+  _src_units=0; _dst_units=0
 fi
 
 # Prune: keep the 5 newest timestamped dirs.
-ls -dt "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
+ls -dt .mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
   rm -rf "$old"
 done
 
-echo "mpr snapshot ok ($MPR_COUNT .mpr + $UNIT_COUNT units) — $(ls -d "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
+# Report what was actually copied, not what was attempted.
+echo "mpr snapshot ok (.mpr + ${_dst_units} mxunit) — $(ls -d .mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
```

- bin/verify-module.sh — STALE: identical to shipped 66c2ceb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin verify-module.sh

## bin/page-fidelity.js differs from shipped project-bin/page-fidelity.js — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: f3d7b49 (2026-09-01), 88 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/page-fidelity.js
+++ project/bin/page-fidelity.js
@@ -1,15 +1,15 @@
 #!/usr/bin/env node
 // page-fidelity.js — score one drafted/built page's MDL against its wireframe, model-side.
 //
-// Promoted from process/prototypes/first-build-fidelity.proto.js after the topbar-portal
+// Promoted from process/prototypes/first-build-fidelity.proto.js after the approval-app-main
 // field run (2026-08-27). The prototype assumed ToeicBuddy's wireframe shape on two axes
 // that do not travel:
 //
-//   * content boundary — ToeicBuddy wireframes wrap page content in <main>; the topbar portal's
+//   * content boundary — ToeicBuddy wireframes wrap page content in <main>; the approval app's
 //     wrap popup content in .dialog and full-page content in bare divs, with annotation
 //     chrome (wf-bar, wf-note, wf-section, the .bind table, DESCOPED banners) as
 //     siblings. Scoring the whole body counts the annotation against the page.
-//   * MDL case — the prototype matched CREATE...PAGE uppercase only; the topbar portal's scripts
+//   * MDL case — the prototype matched CREATE...PAGE uppercase only; the approval app's scripts
 //     write it lowercase (same bug fixed in check-page-shell.sh, commit e0588e3).
 //
 // Usage:
@@ -102,11 +102,11 @@
 function contentOf(html) {
   // Boundary preference, most-specific first:
   //   <main>            ToeicBuddy shape — content-only wireframes
-  //   div.main          the topbar portal full-page shape — the wireframe mocks the WHOLE app
+  //   div.main          the approval app full-page shape — the wireframe mocks the WHOLE app
   //                     shell; the sidebar is layout chrome, but div.main holds the
-  //                     page title (the topbar portal titles pages from the top bar), so it is
+  //                     page title (the approval app titles pages from the top bar), so it is
   //                     the boundary and the user chip is stripped below
-  //   div.wf-screen     a deal-management PoC shape — the wireframe is an annotated DOCUMENT, and the
+  //   div.wf-screen     a deal-management PoC shape — the wireframe is an annotated DOCUMENT, and the
   //   div.wf-shell      screen is one labelled block inside it, with the annotation
   //   div.mockup-frame  apparatus (meta header, binding tables, scope crosschecks) as
   //                     siblings. A wireframe that names its own screen has told us
@@ -128,35 +128,11 @@
     || innerBalanced(html, /<(div)[^>]*class="[^"]*\bcontent\b[^"]*"/i)
     || (html.match(/<body[^>]*>([\s\S]*)<\/body>/i) || [, html])[1];
   s = dropBalanced(s, /<(div)[^>]*class="[^"]*\buserchip\b[^"]*"/i);
-  // The top bar is layout chrome and `chromeSet` below already drops the class `topbar`
-  // itself from the denominator — but only that one NAME, so everything the bar CONTAINS
-  // (brand, logo, right, lang, the signed-in email) stayed in, scored as page content the
-  // page had failed to declare. Field case, 2026-08-31: 4 of 22 classes and 1 of 3 content
-  // blocks marked missing on a correct page, all of them children of a bar the scorer had
-  // already decided not to score.
-  //
-  // GUARDED, because the comment on chromeSet is right that some designs title the page
-  // FROM the top bar (the topbar portal does): the subtree is dropped only when it contains no h1/h2,
-  // so a wireframe whose page title lives in the bar keeps it and keeps being scored on it.
-  {
-    const bar = innerBalanced(s, /<(div|header)[^>]*class="[^"]*\btopbar\b[^"]*"/i);
-    if (bar && !/<h[12][\s>]/i.test(bar))
-      s = dropBalanced(s, /<(div|header)[^>]*class="[^"]*\btopbar\b[^"]*"/i);
-  }
-  // ANY `wf-*` div is annotation chrome, not page content. This used to name three
-  // specific ones (wf-bar, wf-note, wf-section) and missed `wf-bind` — the class a
-  // dashboard-publishing migration's wireframes put their binding tables in. The tables'
-  // own headings and cells then scored as page content the page had failed to reproduce:
-  // "heading: Binding annotations — the build checklist" and "content: Mendix widget"
-  // counted against a page whose job is emphatically NOT to render the build checklist.
-  // Measured 2026-08-31: 39% before, 71% after, on an unchanged page script. A scorer that
-  // marks documentation as missing content does not measure fidelity, it measures how much
-  // annotation the wireframe carries — and the ≥80% target is read off this number.
-  // The prefix rule matches the class convention itself (`wf-` = wireframe annotation),
-  // so a wireframe that invents `wf-legend` tomorrow is handled without another edit.
-  s = dropBalanced(s, /<(div|p)[^>]*class="[^"]*\bwf-[a-z-]*[^"]*"/i);
-  s = dropBalanced(s, /<(div|p)[^>]*class="[^"]*\bwf-[a-z-]*[^"]*"/i);
-  s = dropBalanced(s, /<(div|p)[^>]*class="[^"]*\bwf-[a-z-]*[^"]*"/i);
+  // wf-note is a <p> at least as often as a <div> ("Header binding note: ...", "Six rows,
+  // MEDPIC SortOrder 1-6"). Prose ABOUT the page is not page copy whichever tag carries it;
+  // scoring it as page copy is why an annotation-heavy wireframe reads as a content miss.
+  s = dropBalanced(s, /<(div|p)[^>]*class="[^"]*wf-(?:bar|note|annot|meta|head)[^"]*"/i);
+  s = dropBalanced(s, /<(div)[^>]*class="[^"]*wf-section[^"]*"/i);
   // Annotation apparatus that does not carry the wf- prefix: section captions, the
   // binding/scope-crosscheck table wrappers, and "out of scope for this wireframe"
   // callouts. Vocabulary, like .userchip and table.bind above — extend as shapes arrive.
@@ -164,34 +140,7 @@
   s = dropBalanced(s, /<(div)[^>]*class="[^"]*\banno-wrap\b[^"]*"/i);
   s = dropBalanced(s, /<(div)[^>]*class="[^"]*\brail-note\b[^"]*"/i);
   s = dropBalanced(s, /<(div)[^>]*class="[^"]*\bannot\b[^"]*"/i);
-  // `.anno` — NOT reached by the `annot` pattern above, because \b after "anno" needs a
-  // non-word character and "t" is one. Measured 2026-09-09 on a MOC/PSSR app
-  // replacement, whose annotation block is `div.anno`: every page scored its own
-  // annotation as missing page content, reporting "heading: Annotation" as the first
-  // miss on a page whose real H1 is correct. Two faithful pages at 9%.
-  s = dropBalanced(s, /<(div)[^>]*class="[^"]*\banno\b[^"]*"/i);
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
   return s;
@@ -214,7 +163,7 @@
 // wireframe's outer wrapper as a mock DELETES THE ENTIRE PAGE, and every dimension
 // then reports 0-of-0, which normalizes to a null score rather than to a low one.
 //
-// Measured (a deal-management PoC, 2026-08-28): wireframes shaped .wf-wrap > .wf-screen scored `null%`
+// Measured (DealIQ, 2026-08-28): wireframes shaped .wf-wrap > .wf-screen scored `null%`
 // on all seven pages. Nothing failed and nothing said "unmeasured" — the run printed a
 // clean report over an empty corpus. That is the failure mode worth fixing: the
```

10 stale (one line each) · 3 local fix(es) (diffs above)
