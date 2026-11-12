# Purchase Request: Atlas_TopBar_Customized regression (R19)
Evidence: run1 app git history (b433ad7 original, 19a5fd2 Atlas_Core 4.5.0 step, 697fcc8 replay), compiled CSS in work/run/oldwalk vs newwalk/web/theme.compiled.css, mxcli DESCRIBE on copies of original.mpr and the new .mpr, e2e screenshots (before-picked vs after).

## 1. Root cause: two separate breaks, and the "logo" failure is mislabelled
A. The failing click is NOT the logo. Admin_Homepage has its own `image2` (the hero photo, class `headerhero-backgroundimage`), same name as the layout logo `image2`. The runner (journey-verbs.js `topmost`/`pageWidget`) picks the match nested deepest in `.mx-placeholder`, so it clicks the hero photo. The logo was never clicked, before or after.
- Why the hero photo can't be clicked: Atlas_Core 4.5.0 step brought Image widget 1.4.3 -> 1.5.0 (com.mendix.widget.web.Image.mpk, commit 19a5fd2). 1.5.0 adds `.mx-image-viewer{height:100%}`. The app's own edit to atlas_web_content `_heroheader.scss` (replay patch: `top:-200%`, `>img` nested) was replayed onto AWC 4.4.0 and compiles the same in both builds: `.headerhero-backgroundimage{position:absolute;top:-200%}`.
  Old: wrapper height = the image's height (tall), so -200% still showed the middle of the photo. New: wrapper height = 100% of the 240px hero, at top -480px -> spans -480..-240, fully outside `.headerhero{overflow:hidden}`. Photo invisible (plain blue hero in the after screenshot), Playwright can't click it -> 30s timeout.
B. Top bar layout: the custom layout is a copy of the Atlas 3 top bar (`topbar-content`, `flexcontainer justify-content-between`, `flexcontainer flex-row` + "Align content", `flexcontainer justify-content-end`). Atlas 4's own Atlas_TopBar is now `topbar-wrapper` (grid `1fr auto 1fr`) with no `flexcontainer` helpers. Compiled CSS:
  - old `.flexcontainer{display:flex;overflow:hidden;flex:1;flex-direction:row}` -> new `.flexcontainer{display:flex!important;gap:var(--flex-gap)!important}`: no `flex:1`, so container1/container5 shrink to fit and nothing pushes right.
  - `.justify-content-between` / `.justify-content-end`: in old CSS, absent from new (Atlas 4 names: `.justify-between`, `.justify-end`).
  - `.layout-atlas .region-topbar .mx-navbar` lost `display:inline-flex`. Atlas 4 `ul.nav` now `display:flex;flex-flow:wrap;justify-content:center`.
  - Replay 697fcc8 put back the app's local edit `min-height:500%` on `.region-topbar .mx-navbar` (pristine 4.5.0 says `auto`; in 3.x it was harmless inside an inline-flex, overflow:hidden parent).
  Result (after screenshot): Sign Out, help and avatar sit right after the title (no space-between/flex-end); the menu bar keeps a ~90px slot between title and icons, but "Home" isn't drawn. The most likely cause is the block-level navbar with 500% min-height centring its item outside the 48px bar. Not proven yet: no DOM dump. The confirming check is the bounding box of `.mx-name-menuBar1 li`.
  Not the cause: menu items (navigation Responsive unchanged), topbar colours (--navtopbar-color #fff), design-property classes (row-center/hide-icons/hide-phone the same), logo sizing (`navbar-brand img` height kept, 36px).
  Layout diff old vs new: only "Align content" -> "Align content (deprecated)" and text colour White -> Contrast.

## 2. Repair for this app (smallest first)
R1 (needed for both): drop the two replayed vendor-file edits. Restore atlas_core `_navigation-bar.scss` (`min-height:auto`) and atlas_web_content `_heroheader.scss` to the 4.5.0/4.4.0 package files. Put any styling still wanted in app-owned `theme/web/main.scss`. The hero then uses AWC 4's own absolute/100% rule plus the "Image fit: Cover" design property, so the photo shows and is clickable.
R2 top bar, MDL only: on PurchaseApprovals.Atlas_TopBar_Customized:
  - add `Style: 'flex: 1;'` to container1, container4 and container5 (restores the Atlas 3 grow);
  - rename classes `justify-content-between` -> `justify-between` and `justify-content-end` -> `justify-end`.
  The layout is the app's own (PurchaseApprovals), so no vendor write is needed.
R3 journey: scope the layout widget (`.region-topbar .mx-name-image2`) or name it apart from the page image, so the logo is really tested. The old PASS proved nothing about the logo.
Alternatives:
- Compat stylesheet in theme/web/main.scss: `.justify-content-between{justify-content:space-between!important}`, `.justify-content-end{...flex-end!important}`, `.layout-atlas .region-topbar .topbar-content .flexcontainer{flex:1}`, `.layout-atlas .region-topbar .mx-navbar{display:inline-flex}`.
  Pro: no model change, covers other pages that use the old helpers. Con: keeps Atlas 3 names alive, and the global helper classes can restyle Atlas 4 widgets. It is also the approach D17 took, which is still "to prove".
- Re-derive the layout from Atlas 4 Atlas_TopBar (topbar-wrapper grid: brand | menu | right slot), moving the title, help icon, ProfilePicture and Sign Out into the slots.
  Pro: future-proof, gets Atlas 4 responsive and a11y behaviour. Con: biggest change, the look changes (centred menu), and it needs a visual sign-off.
- Keep Atlas_Core 3.x on 11.12: 3.21.0 is the 10.x line. Running it on 11 is not a supported pairing, so treat it as not allowed unless the user accepts the risk. It also blocks the CE2729 role mapping and the newer DataWidgets/AWC. And hero break A comes from the Image widget, which Atlas_Core 4.5.0 brought; pinning Atlas only hides that.

## 3. Toolkit change that would have caught it before the build (BACKLOG #11 / PR-F20)
theme_clash.py reads only the app's own SCSS. Here the app has none for these names: the classes sit on model widgets and inside replayed vendor patches. Add a `theme_clash.py classes` layer:
- Scan: every `Class:` token and every design-property class on own-module layouts, pages and snippets (mxcli DESCRIBE or mprmodel.py), with the widget path.
  Judge each token against the old and new Atlas+widget CSS: compiled theme.compiled.css if a build exists, else the SCSS `.x` defs plus each widget mpk's css.
  Rows:
  - `GONE <class>`: in old, not in new (justify-content-between, justify-content-end), with an Atlas 4 synonym hint from a table (-> justify-between/justify-end);
  - `CHANGED <class> lost <prop>`: same selector, declarations dropped (.flexcontainer lost flex:1, overflow; region-topbar .mx-navbar lost display).
- Derived-layout check: an own layout whose class string matches an Atlas layout (`layout-atlas-responsive-topbar`) is a DERIVED LAYOUT. Diff its class skeleton (topbar-content) against the new Atlas layout (topbar-wrapper) -> REVIEW row.
- Replay check: each hunk of replay/<Module>.patch is listed with the selectors it touches. Any CSS the new package or widget mpk changed on those elements (Image 1.5.0 `.mx-image-viewer{height:100%}` vs `.headerhero-backgroundimage`) -> REPLAY-RISK, naming the pages that carry the class (Admin_Homepage.image2).
- Journey generator: a widget name present both in a layout and in the page -> AMBIGUOUS, scoped locator.
- Report: one line per row in plan.txt / triage (REVIEW layer, not a stop): "Atlas compat: G gone, C changed, D derived layouts, R replay risks; Atlas <old> -> <new>".
- Control: fixture = this run's old/new theme.compiled.css, the two Image mpk CSS files, the Atlas_TopBar_Customized and Admin_Homepage class lists, and both patches. Expect:
  - GONE justify-content-between, justify-content-end; CHANGED .flexcontainer; DERIVED Atlas_TopBar_Customized; REPLAY-RISK headerhero-backgroundimage; AMBIGUOUS image2.
  - Mutant: add `.justify-content-between{}` to the new CSS -> that row clears. Pass control: row-center/hide-phone never reported.

## 4. User decisions
1. Repair route for the top bar: MDL class/flex fix (R2, recommended), compat stylesheet, or re-derive from Atlas 4.
2. Drop both local vendor-theme edits (navbar 500%, hero -200%) and move what's wanted to theme/web? This needs a visual sign-off of the hero.
3. Accept Atlas_Core 4.5.0 + Image 1.5.0 (recommended) vs an unsupported Atlas 3 pin.
4. Re-baseline the image2 journey: the old PASS clicked the hero photo, not the logo.
