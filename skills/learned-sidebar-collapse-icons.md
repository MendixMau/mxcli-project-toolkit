# Collapsible sidebar navigation — icon-only when collapsed, never truncated text

**Applies to:** any navigation profile with a collapsible/responsive sidebar menu.

## The rule

**A collapsed sidebar must show icon-only (no text) per menu item. Never truncated text**
("Produc", "Packag", "Config") as a stand-in for a real collapsed state. Expanded state shows
icon + full label; collapsed state shows icon alone.

## Why

Confirmed on a project's nav layer: the sidebar's "collapsed" state was just the default Atlas Core nav
clipping label text at a fixed narrow width — there was no real collapse/expand mechanism,
and no icon assigned per menu item to fall back to. The result read as broken UI ("Produc",
"Packag") rather than an intentional compact state, and the toggle control didn't visibly
change anything because there was nothing to toggle between.

Two things have to both be true for a collapsed sidebar to make sense, and it's easy to build
neither without noticing:

1. **Each top-level menu item needs an assigned icon** (glyph or custom SVG) *before* you rely
   on a collapsed state — otherwise collapsing just removes the only identifying content.
2. **Menu-item icons ARE scriptable — probe your binary, do not trust this paragraph's history.**
   The grammar token is `ICON`, and it takes a qualified name into an icon collection, not a
   string:

   ```
   MENU ITEM 'Approval queue' PAGE ProcurementCore.Approval_Queue ICON Atlas_Core.Atlas."check-circle";
   MENU 'Reports' ICON Atlas_Core.Atlas_Filled.chart ( ... );
   ```

   Hyphenated Atlas names must be double-quoted. List what you actually have with
   `SHOW ICON COLLECTION` and `DESCRIBE ICON COLLECTION Atlas_Core.Atlas` — a stock Atlas Core
   4.1.3 ships three collections, two of them with 366 icons each.

   > **Correction, 2026-09-21.** This bullet previously said the grammar had *no* icon token and
   > that per-item icons "have to be assigned by hand in Studio Pro". That was wrong for mxcli
   > **v0.22.0** (`mxcli syntax navigation.create` lists `ICON` and documents the quoting rule),
   > and it cost a real project: the PRD benchmark's Arm A shipped five text-only menu items
   > through an entire build and two UI sweeps, because the skill said icons were not scriptable
   > so nobody re-probed. The user's verdict on the result was "lots of text ugly stuff".
   >
   > This is the toolkit's own **capability-probe rule** (`CLAUDE.local.md`, added 2026-07-21)
   > failing in the place it was meant to protect: *"a general prior is NOT evidence about this
   > binary"* — and a prior written into a skill file is the most convincing general prior there
   > is. **Before acting on any capability claim in this file, run
   > `mxcli syntax navigation.create` against the binary in front of you.**

## How to apply

Before building any navigation profile with a collapsible/responsive sidebar:

- Confirm every top-level menu item has an icon assigned before assuming a collapsed state
  will be legible.
- Don't assume Atlas's default responsive behavior gives you a real collapse/expand — verify
  the toggle actually changes rendered width and content in a real browser check, not just
  that the MDL/theme compiled.
- Assign the icons in MDL with the `ICON` clause above, in the same
  `CREATE OR REPLACE NAVIGATION` that defines the menu — the block replaces the stored list
  wholesale, so round-trip it: `DESCRIBE NAVIGATION` → add icons → re-apply. There is no
  Studio Pro step.
- **Icon-only-when-collapsed is CSS, not MDL.** The `ICON` clause puts the glyph there; nothing
  in the navigation grammar controls what a collapse hides. Inspect the Atlas Core version in
  *your* `themesource/atlas_core/` for the real sidebar class names before writing the rules —
  do not copy class names from another project's theme, and never edit inside the
  `mxcli:theme:begin signal v1` generated block (a `mxcli theme apply` will overwrite it).

## How to catch this in review

Open the running app, trigger the sidebar's collapse toggle, and check two things: (1) does
the width/content actually change, and (2) is every remaining item still identifiable by its
icon alone. If either fails, the "collapsed" state isn't done — it's clipped text wearing a
collapsed state's name.
