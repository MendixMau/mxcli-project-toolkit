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
2. **mxcli's `navigation.create` MDL grammar has no menu-item icon token** (confirmed via
   `mxcli syntax navigation.create --json` — the grammar is `MENU ITEM 'Label' PAGE
   Module.Page;`, no icon property at all). Per-item icons for a collapsed state currently
   cannot be scripted through MDL and have to be assigned by hand in Studio Pro, or driven by
   theme-level CSS keyed off page/module name.

## How to apply

Before building any navigation profile with a collapsible/responsive sidebar:

- Confirm every top-level menu item has an icon assigned before assuming a collapsed state
  will be legible.
- Don't assume Atlas's default responsive behavior gives you a real collapse/expand — verify
  the toggle actually changes rendered width and content in a real browser check, not just
  that the MDL/theme compiled.
- If the icon needs to be set via mxcli, expect to do it by hand in Studio Pro (or via
  theme CSS) rather than scripting it — the MDL grammar gap above is current as of this
  writing.

## How to catch this in review

Open the running app, trigger the sidebar's collapse toggle, and check two things: (1) does
the width/content actually change, and (2) is every remaining item still identifiable by its
icon alone. If either fails, the "collapsed" state isn't done — it's clipped text wearing a
collapsed state's name.
