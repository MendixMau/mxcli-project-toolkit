# CAC-4 — Design Checkpoint

**Fires after:** Phase 6 Rearchitect sign-off (.mx-brd.json complete)
**Feeds into:** `design-artifacts.md` (design system + wireframes)
**Template:** See `checkpoint-template.md` for format rules.

---

## What to Surface

Pull from `.mx-brd.json` files and source KB screens:
- Total screens/pages in scope
- Key user flows (group screens by journey: auth, main feature, settings, etc.)
- Source layout patterns detected (sidebar, top nav, card grid, list-detail, modal forms)
- Any screens with no direct Atlas widget equivalent (flag these specifically)

## What's Next

`design-artifacts.md` produces the design system decisions (Atlas layout, spacing tokens, component
naming) andted without design decisions produce
generic Atlas output that will need rework.

---

## Predefined Questions

### Q1 — Atlas layout pattern

**When to ask:** Always.

**How to generate options:** Inspect source screens for navigation pattern:
- Left sidebar + content area → recommend Atlas_Default
- Top navigation bar → recommend Atlas_TopBar
- No persistent nav (auth-only app, wizard-style) → recommend Atlas_Blank or Atlas_Default
- Tabs + content → recommend Atlas_TopBar

> "The source uses [detected pattern]. Which Atlas base layout should we target?"
> - A) Atlas_Default (persistent left sidebar + content area) *(recommended — closest to source)*
> - B) Atlas_TopBar (horizontal navigation)
> - C) Atlas_Blank (no chrome — build from scratch)
> - D) I'll describe a custom layout

**Record as:** `pipeline-state.md` → `## Decisions Made` → `Atlas layout:`

---

### Q2 — Responsive / platform target

**When to ask:** Always.

**How to generate options:** Check if source was a mobile-first app (React Native, Ionic, PWA)
or desktop-first. Use that to set the recommended option.

> "What is the platform target for this Mendix build?"
> - A) Web only — desktop-first, no responsive requirement *(fastest for POC)*
> - B) Responsive web — works on desktop and tablet/mobile via Atlas responsive grid
> - C) Native mobile — Mendix Native profile (separate build pipeline)
> - D) Web + Native — both profiles, more complex

**Record as:** `pipeline-state.md` → `## Decisions Made` → `Platform target:`

---

## Open Question

> "Do you have branding guidelines, a Figma file, or an existing design system?
>
> Drop a link, paste the key details (colors, fonts, logo), or describe the visual direction.
> If none — say 'use Atlas defaults' and we'll proceed with out-of-the-box Atlas styling."

**What to do with the answer:**

| Answer type | Action |
|---|---|
| Figma link | Add to `project-profile.md` → External References. Note which flows are designed vs wireframe-only. |
| Brand doc / PDF | Same as above. Extract: primary color, font family, logo usage rules. |
| Verbal description | Record key decisions (primary color, font, tone) in `design-artifacts.md` inputs. |
| "Atlas defaults" | Note it. No custom tokens needed. Skip Atlas customization in MDL layer. |
| Existing Mendix design system | Identify the theme module. Use its layout + widget naming conventions throughout. |

---

## Decision Recording

```
pipeline-state.md → ## Decisions Made:
  Atlas layout: [chosen layout]
  Platform target: [web / responsive / native / both]
  Design assets: [Figma URL / brand doc link / 'Atlas defaults' / description]
```

```
project-profile.md → ## External References:
  Design: [link or 'Atlas defaults']
```
