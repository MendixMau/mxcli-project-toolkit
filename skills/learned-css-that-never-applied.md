# A style change that did nothing — read the computed style before rewriting the rule

**Applies to:** any mxcli project with a ported design system.
**Runs:** the moment a CSS change appears to have had no effect on screen, or the app still looks
unstyled/grey after a design port that every instrument called green.
**Cost:** ninety seconds per read. It is meant to be run before you touch the rule, every time.

---

## The one-line finding

An app went through two UI passes: the first the user called "poor", the second "much better".
Only the closing check changed:

> **Pass 1 verified that the SCRIPT EXECUTED. Pass 2 verified that THE PIXEL CHANGED.**
> Every green signal in pass 1 was true and irrelevant.

`mx check`, `mxcli lint`, the MDL suite and two e2e journeys were all green over an app whose grid
header was white on white and whose table stylesheet had never matched a single element.

This skill is the rung that was missing. It is not "look at a screenshot" (`ui-loop.md` already
says that, and it is right). A screenshot tells you something is wrong; it does not tell you
whether your rule matched nothing, matched too much, or matched and lost.

---

## The four ways a perfectly correct rule paints nothing

They look identical on screen and have opposite fixes.

| # | Failure | What you see | What is actually true |
|---|---|---|---|
| 1 | **Matches nothing** | the element is unstyled | the selector names a DOM the app does not render |
| 2 | **Matches too much** | something *else* broke | the selector names an ancestor shared with chrome |
| 3 | **Matches, loses the cascade** | the element is unstyled | the framework outranks you and is actively erasing it |
| 4 | **Matches, wins, nothing to paint on** | a Data Grid 2 row ignores outline or background | the row is `display: contents`: no box |

### 1. Matches nothing — three of four misses in one run

`design/ds.css` styled `table.ds-table`. The showcase page is HTML, but the app renders DataGrid2:
rows are `<div class="tr">`, cells `<div class="td">`, and **no `<table>` exists on any page**. No
table rule ever applied, through the port, mxbuild, lint and both journeys.

Styling the top bar, three guessed selectors (`.navbar`, `header.navbar`, `.mx-layoutgrid-fluid`)
matched zero elements. The real carrier, `.mx-scrollcontainer-top.region-topbar`, was found in one
read of the live element chain, not by a fourth guess.

> `project-bin/check-design-portability.sh` catches the `table`/`th`/`td` case statically and
> should be run before porting. It cannot catch the guessed-carrier case, because
> `.navbar` is a perfectly plausible class name — it just isn't this app's.

### 2. Matches too much — the widened guess

`.mx-page { background: var(--bg) }`, added so white cards stop sitting on white, also painted the
navigation bar inside that container: white menu text on a white bar, an **invisible top nav**.

The instinct after failure 1 is to widen the selector until something matches. This is what that
costs. A rule that paints nothing is visible in one screenshot; a rule that paints chrome is
visible in one screenshot *of a different page*, which is how it ships.

### 3. Matches, loses the cascade — and source order never got a say

`.mx-listview-empty` named exactly the right element, roughly **eleven thousand lines after**
Atlas in the compiled sheet. It still lost, because Atlas ships:

```css
.mx-listview > ul .mx-listview-empty { border-style: none; background-color: transparent; }
```

That is **0,2,1** against a bare class's **0,1,0**. Specificity is decided before source order is
consulted, so "mine is later" was never relevant. The fix was `.mx-listview > ul > li.mx-listview-empty`
— **0,2,2**, one extra element and one extra class. No `!important`.

**The general fact, which is worse than "the framework also styles this":** Atlas *erases*.
`border-style: none; background-color: transparent` is not a default it forgot to remove — it is
the framework deliberately blanking that element. A rule you add without outranking it is not
"competing", it is being deleted.

**The same erasure hides inside classes a port calls "Atlas-native, styled by the knobs".** Some
Atlas base properties have no custom-variables knob at all: `.btn { font-weight: normal }` and,
above 767px, `.form-group { display: flex; flex-direction: row }`. Field case
(Mendix 11.13.0): every button rendered at 400 against the design system's 500 and hand-written labels sat beside their inputs; the check saw
nothing, because both classes counted as bound. Port each such
property as its own rule, and read it back as a computed value, not as a knob that was set.

---

### 4. `display: contents`: no box to paint on

A Data Grid 2 row has no box, so `outline`, `background`, `box-shadow` or `scrollIntoView` on the
row paints nothing, though the computed-style read shows your value. Target the row's cells
instead. Read-side twin: `offsetParent === null` in `testing-shape.md`.

---

## The diagnostic — two reads, before you touch the rule

Run against the running app, as a real user role, on the page in question.

**Rung A — what is this element's computed value, really?**

```js
const el = page.locator('<selector for the element you meant to style>').first();
console.log(await el.evaluate(e => getComputedStyle(e).backgroundColor
                                 + ' | ' + getComputedStyle(e).borderStyle));
```

**Rung B — only if Rung A found nothing: what IS the element chain?**
Do not guess a second selector. Read the real one.

```js
const chain = await page.evaluate(() => {
  const n = [...document.querySelectorAll('*')]
    .find(e => e.children.length === 0 && e.textContent.trim() === '<visible text on the element>');
  if (!n) return 'not found';
  const out = [];
  for (let e = n; e && out.length < 6; e = e.parentElement)
    out.push(e.tagName + '.' + [...e.classList].join('.'));
  return out;
});
console.log(JSON.stringify(chain, null, 1));
```

Sample: `["LABEL.","LI.mx-listview-empty","UL.","DIV.mx-listview.mx-name-lvDocs","DIV.ds-card"]`
names the carrier and its ancestors, so you can write a `>` chain that outranks the framework.
Your own `ds-*` classes showing up two levels up means the carrier is wrong.

**Then decide from what Rung A returned. The three answers have three different fixes:**

| Rung A returned | Diagnosis | Fix |
|---|---|---|
| **your** value | the rule applied — your value is wrong | a design decision, not a CSS bug. Change the value. |
| the **framework's** value | cascade loss (#3) | find the framework's selector in the compiled sheet, count its specificity, outrank it |
| **element not found** | matches nothing (#1) | Rung B, then rewrite the selector to the real carrier |
| your value, and *something else* also changed | matches too much (#2) | narrow to the content region; never leave it widened |

**Never rewrite a rule that "does nothing" before Rung A.** Three of the four field misses were
guessed selectors and the fourth was a cascade loss — a blind rewrite would have been the wrong
move in all four, and in one case (#2) the rewrite *was* the outage.

---

## Close every claim with a computed-style read

The rule that produced the second pass, stated as a completion criterion with a denominator:

> **Every component class a pass claims to have shipped has at least one computed-style read
> against a named element in the running app, or is reported as unverified. State it as
> "N of M classes verified". "The script exited 0" is not a read, and "it looks right" is not a
> read.**

What that looked like on the field run — each of these is a line in the commit that shipped it,
not a note in a doc:

| Claim | The read that closed it |
|---|---|
| cards carry status tone | `rgb(255,250,240)`, left edge `rgb(184,121,10)`, **10 of 10 cards** |
| card header bands bleed to the card edge | computed `padding: 0px` |
| empty states are no longer white voids | `rgb(241,241,244)`, `dashed` |
| the top bar has the deep-red gradient | `linear-gradient(rgb(212,36,23), rgb(168,20,16))` |
| a rejected row outranks an awaiting one | project 859 `rgb(254,246,245)`, project 861 `rgb(255,250,240)` |

The last row is the one that justifies the discipline. Row tone was implemented, screenshotted,
and *looked* fine — and was wrong: a rejected project was rendering amber, because a row carrying
two status cells matched two rules at equal specificity and the last one written won. The eye
read "coloured rows, good". Two computed-style reads named the defect and the precedence order
that fixed it. **Nothing but a value read would have caught that**, and it is exactly the class of
error a customer notices first.

---

## Before any of this: the class that arrived and nobody used

`project-bin/check-design-reaches-app.sh` counts how many component classes **arrived** in the
built stylesheet. It cannot see a class that arrived perfectly and is bound to no widget.

In the field run `ds.css` held four semantic tint sets, an elevation scale and a styled empty
state, all correct and all referenced by **zero widgets**. The app was grey. No CSS instrument can
see this, because nothing is wrong with the CSS.

> **Measure it as a ratio, not a list: of the M component classes defined in `ds.css`, how many
> have at least one carrier in the model?** Get the M from the stylesheet and the carriers from
> the model (`mxcli` catalog/`DESCRIBE`, or a grep of the executed MDL for `Class:` and
> `DynamicClasses:`). Report "N of M classes have a carrier". A zero-carrier class is a finding,
> and the fix is never to rewrite it — **it is to bind it.**

---

## The opposite case: a focus ring that paints on every page landing

Added 2026-10-12 from a 20-task UX-fix run over three apps. **On page load Mendix focuses the
first navigation item from script, and Chrome counts that as `:focus-visible`.** So a plain
`:focus-visible { outline: … }` ring, added for accessibility, paints on every landing. A mouse
user sees one tab ringed as if selected. Every journey stayed green: each clicked the page body
first, and the count looked at `inset` box-shadows, not outlines.

The fix: draw the ring only after the user has used the keyboard. A small script loaded from
`theme/web/index.html` (or wherever the theme loads its own scripts):

```js
// set html.kbd-nav on the first Tab/arrow key; clear it on any pointer press
(function () {
  var KEYS = { Tab: 1, ArrowUp: 1, ArrowDown: 1, ArrowLeft: 1, ArrowRight: 1 };
  var el = document.documentElement;
  document.addEventListener('keydown', function (e) { if (KEYS[e.key]) el.classList.add('kbd-nav'); }, true);
  document.addEventListener('pointerdown', function () { el.classList.remove('kbd-nav'); }, true);
})();
```

```css
:focus-visible { outline: none; }
html.kbd-nav :focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
```

**Check every focus style twice, in this order, and before any click:** sign in with the mouse
and read the computed `outline-style` of the focused element (expect `none`), then press Tab once
and read it again (expect your ring). A check that clicks first has already cleared the state it
is supposed to see, and a check that counts box-shadows cannot see an outline. Completion line:
"N of N roles: no ring on landing, ring after Tab".

## Atlas carriers that beat a plain descendant rule

Lab observations; confirm with a computed-style read on your Atlas version.

| You write | What happens | Write it as |
|---|---|---|
| `.my-cards li` for a list view with `Class` `my-cards` | `Class` lands on the root `div.mx-listview`; Atlas's `.mx-listview > ul > li` outranks you | `.mx-listview.my-cards > ul > li` |
| `.my-content { display: flex }` in the page body; a top-level button | Body is a flex column (`mx-placeholder`); the button stretches full width | `.region-content .mx-placeholder > .btn { align-self: flex-start; }`; region classes cannot be set by `alter layout`, so put padding on `.<shell> .region-content` |
| `.my-timeline { display: flex }` | Items sit in a child `ul`: strip renders vertical | `.my-timeline > ul { display: flex; }` |
| `.my-step:first-child` | Every step is its own `li`'s first child | `.my-timeline > ul > li:first-child .my-step` |

Fix these in the shared stylesheet. A theme-only change needs an app restart.

## Related

- `ui-loop.md` — the per-script look. Tells you *that* a page is wrong. This skill starts where
  that ends: which of the three failures you have, and what the value actually is.
- `project-bin/check-design-portability.sh` — the static half of failure #1 (`table`/`th`/`td`,
  `rem`, positional `nth-child`). Run before porting. Cannot see a guessed carrier.
- `project-bin/check-design-reaches-app.sh` — did the tokens and classes reach the built sheet.
  Necessary, and blind to the zero-carrier case above.
- `learned-stylegallery.md` § "The Mendix DOM contract" / § "Every class states its carrier" —
  the authoring-time counterpart: state a class's intended carrier when you write it, and this
  whole diagnostic is needed less often.
- `learned-mdl-cannot-express.md` § "When MDL cannot set a class, CSS often can" — the positive
  pattern that came out of the same run.
- `learned-detection-gaps.md` — the register this belongs to: constructs that pass every early
  rung and fail at the last one.
