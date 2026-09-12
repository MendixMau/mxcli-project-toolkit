# A style change that did nothing — read the computed style before rewriting the rule

**Applies to:** any mxcli project with a ported design system.
**Runs:** the moment a CSS change appears to have had no effect on screen, or the app still looks
unstyled/grey after a design port that every instrument called green.
**Cost:** ninety seconds per read. It is meant to be run before you touch the rule, every time.

---

## The one-line finding

A change-governance app (2026-09-10) went through two UI passes. The first shipped an app the
user called "poor". The second, same person, same day, same design system: "much better." Nothing
about the CSS authoring got better in between. What changed was the closing check:

> **Pass 1 verified that the SCRIPT EXECUTED. Pass 2 verified that THE PIXEL CHANGED.**
> Every green signal in pass 1 was true and irrelevant.

`mx check` clean, `mxcli lint` clean, the MDL suite green, two e2e journeys green, the design port
reporting its tokens correctly landed in the right file — over an app whose grid header was white
on white, whose cards were all one colour, and whose entire table stylesheet had never matched a
single element.

This skill is the rung that was missing. It is not "look at a screenshot" (`ui-loop.md` already
says that, and it is right). A screenshot tells you something is wrong; it does not tell you
whether your rule matched nothing, matched too much, or matched and lost.

---

## The three ways a perfectly correct rule paints nothing

All three were met in one field run. They look identical on screen and have opposite fixes.

| # | Failure | What you see | What is actually true |
|---|---|---|---|
| 1 | **Matches nothing** | the element is unstyled | the selector names a DOM the app does not render |
| 2 | **Matches too much** | something *else* broke | the selector names an ancestor shared with chrome |
| 3 | **Matches, loses the cascade** | the element is unstyled | the framework outranks you and is actively erasing it |

### 1. Matches nothing — three of four misses in one run

`design/ds.css` styled `.ds-tablewrap` and `table.ds-table`. The design system's own showcase page
is HTML, so it really does render a `<table>`. The app renders DataGrid2, whose row is a
`<div class="tr">` and whose cell is a `<div class="td">` — **there is no `<table>` element on any
page**. Not one table rule had ever applied: through the full design port, two build phases,
mxbuild clean, lint clean, both journeys green. That is why the grid header was white on white.

Then, styling the top bar, three selectors were guessed in one sitting — `.navbar`,
`header.navbar`, `.mx-layoutgrid-fluid` — and all three matched zero elements. The bar stayed
flat and the rule looked "ignored". The real carrier was `.mx-scrollcontainer-top.region-topbar`,
and it was found in one read of the live element chain, not by a fourth guess.

> `project-bin/check-design-portability.sh` catches the `table`/`th`/`td` case statically and
> should be run before porting. It cannot catch the guessed-carrier case, because
> `.navbar` is a perfectly plausible class name — it just isn't this app's.

### 2. Matches too much — the widened guess

A page-ground rule `.mx-page { background: var(--bg) }` was added so white cards would stop
sitting on white. The navigation bar lives inside that container, so it was painted too: white
menu text on a now-white bar, an **invisible top nav**. Reverted after a screenshot.

The instinct after failure 1 is to widen the selector until something matches. This is what that
costs. A rule that paints nothing is visible in one screenshot; a rule that paints chrome is
visible in one screenshot *of a different page*, which is how it ships.

### 3. Matches, loses the cascade — and source order never got a say

`.mx-listview-empty` named exactly the right element. It sat roughly **eleven thousand lines
after** Atlas in the compiled sheet. It still lost, because Atlas ships:

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

---

## The diagnostic — two reads, before you touch the rule

Run against the app that is actually running, as a real user role, on the page in question.

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

That printed, verbatim, on the field run:

```
["LABEL.", "LI.mx-listview-empty", "UL.",
 "DIV.mx-listview.mx-name-lvSupportingDocument",
 "DIV.mx-name-cardFileBody.ds-cardbody",
 "DIV.mx-name-cardFile.ds-card.ds-section"]
```

— which names the carrier, names its ancestors (so you can write a `>` chain that outranks the
framework), and shows your own `ds-*` classes are present two levels up, all in one read.

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

On the field run, at the moment the user said the UI was poor, `ds.css` already contained four
complete semantic tint sets, a five-step elevation scale and a styled empty state. Every one of
them was correct. Every one of them was referenced by **zero widgets**. The design system was
finished and the app was grey.

No CSS instrument can see this, because nothing is wrong with the CSS.

> **Measure it as a ratio, not a list: of the M component classes defined in `ds.css`, how many
> have at least one carrier in the model?** Get the M from the stylesheet and the carriers from
> the model (`mxcli` catalog/`DESCRIBE`, or a grep of the executed MDL for `Class:` and
> `DynamicClasses:`). Report "N of M classes have a carrier". A zero-carrier class is a finding,
> and the fix is never to rewrite it — **it is to bind it.**

Three of the five improvements the user reacted to were pure binding of CSS that had been sitting
in the file, unreferenced, the whole time.

---

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
