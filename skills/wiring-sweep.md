# Skill: wiring-sweep — does every clickable thing actually do something

**Applies to:** every module before it is called done. Runs as part of `module-review.md` stage 3
(PROVE), as a rung alongside UI/Data/monkey.
**Instrument:** `mxcli playwright snapshot` + `click`, driven by hand or by an agent — no new
harness file. This is a driving procedure over mxcli's existing Playwright wrapper
(`.ai-context/skills/test-app.md` in the consuming project), not a bespoke script. Per
`skills-over-scripts.md`: run this by hand at least twice before any part of it becomes code, and
even then only the fact-fetching part (snapshot + click + observe) ever could — the verdict on an
ambiguous case stays a judgement call, made here, not automated.
**Runs after** the module's happy-path journey is green — same ordering rule as `monkey-test.md`:
sweeping a broken page reports the breakage as "no effect" and buries the real finding.

---

## What this is for, honestly

The failure this catches: a button, breadcrumb, nav item, or menu action that renders correctly,
is named and styled correctly, and passes every mechanical class/a11y sweep — and does nothing
when clicked, or navigates somewhere with no logic behind it.

Nothing else in the toolkit catches this exhaustively:
- `design-audit.js` reads structure and classes, never interaction — it cannot see a click do
  nothing.
- `journey-proof.md` only exercises the clicks a *declared* journey happens to walk — and by
  definition, a dead affordance is one nobody wrote a journey through, because nobody knew it was
  broken. A journey suite can be green and never once touch the dead button.
- `module-review.md` §4c asks "does every action/View button point at the current page" by eye,
  one page at a time. This pass makes the *enumeration* mechanical and exhaustive, so the eye in
  §4c is spent on judgement (is this the *right* target, not just *a* target), not on making sure
  nothing got skipped.

This is the mirror image of `process-coherence-pass.md`'s originating defect. That skill catches
"a working microflow with nothing wired to call it" from the microflow side, at the per-journey
call-graph grain. This skill catches the same underlying pattern — a wire that was never actually
run — from the page side, at the per-element grain, on every page whether or not a journey ever
visits it.

## Procedure

1. Land on the page under review by real navigation (nav menu or a button click), not a direct
   URL — an overlay or stray toggle that swallows clicks silently is exactly the kind of bug a
   direct-URL load skips past. `mxcli playwright open` / `status` to confirm the session is live.
2. `playwright-cli snapshot` — every interactive element on the page comes back with a ref (`e12`,
   `e15`, ...), role, and accessible name. This is the enumeration, and it is exhaustive by
   construction: nothing is skipped because an eye wandered past it.
3. For each ref that is a clickable affordance — button, link, breadcrumb crumb, nav/menu item,
   tab; **not** a plain text input, that's `monkey-test.md`'s job:
   a. Record the pre-click baseline: current URL, a snapshot (for a DOM diff), and start watching
      `playwright-cli network` / `playwright-cli console`.
   b. `playwright-cli click <ref>`.
   c. Observe: did the URL change, did the DOM change (new snapshot differs — a modal opened, a
      panel expanded, a list refetched), did a network request fire, did a console error or an
      error page appear? Any one of the first three is an observable effect.
   d. Record the verdict (table below).
   e. Return to the pre-click page (back-navigate or re-`goto`) before testing the next ref, so
      each click is judged independently — a modal left open from element N must not become
      element N+1's baseline.
4. Cover every page in `module-review.md` §4a's page set — the one derived from the model, not
   from which pages a journey happens to visit. Same denominator discipline: `14 of 14 elements on
   <Page> swept` is a claim, "checked a few buttons" is not.

## Verdict table

| Observation | Verdict | What it means |
|---|---|---|
| URL changed to the expected/plausible target | PASS | wired |
| DOM changed (modal opened, panel expanded, list refetched) with no URL change | PASS | wired, client-side |
| A network request fired (microflow call, datasource refetch) | PASS | wired, even before confirming the UI reflects it yet |
| Nothing observable at all — no URL/DOM/network/console change | **FAIL** | the exact defect this pass exists to catch |
| An exception or error page appeared | **FAIL** | wired to something that breaks — worse than unwired, don't downgrade it |
| Element present in the snapshot but not actually interactable (disabled, zero-size, covered by an overlay) | **FAIL**, distinct reason | log the reason; an overlay swallowing a click is the direct-URL trap in procedure step 1, caught here mechanically instead of by luck |
| Instrument absent / snapshot didn't return the element / session not live | **FAULT** | absence is never a pass — same discipline as `monkey-test.md`'s fourth row |

**A PASS on "network request fired" is narrower than it looks.** It proves a wire exists, not
that what's on the other end of it is correct — that a request fired is not proof it *succeeded*
or *did the right thing*; that's Data (OQL) or a Trace span's job, the same gap `journey-proof.md`
rung 4 calls out for its own Data claim. This pass answers exactly one question — **is there a
wire at all** — and a PASS here must never be cited as proving more than that.

## The three rules

1. **Every element tested, not a sample.** A denominator claim (`12 of 12 interactive elements on
   <Page> tested`) is evidence; "clicked around" is not.
2. **Diagnostic only.** Same as `monkey-test.md` and `module-review.md`: no unapproved fix from a
   sweep. Findings go to the punch-list.
3. **Independent per element.** Reset to the pre-click baseline between elements — a side effect
   from one click contaminating the next element's starting state produces both a false FAIL (the
   modal from element N blocks element N+1's click) and a false PASS (element N+1 "changes the
   DOM" only because element N's modal is still closing).

## Reporting

Fold into `module-review.md`'s stage-3 PROVE report as a WIRING rung, next to UI/Data/monkey:

```
wiring · <module> · <N> of <N> interactive elements swept, <P> pages
  <F> failed (no observable effect), <E> error-on-click, <P> passed
  Read as: these elements are wired to something. Not that the something is correct.
```

## Related

- `skills/monkey-test.md` — same shape (seeded instrument, diagnostic-only, verdict discipline),
  different target: text-input fuzzing, not affordance clicking.
- `skills/process-coherence-pass.md` — the same defect class, found from the microflow side
  (nothing calls it) at the per-journey grain, rather than the page side (nothing clicks through
  it) at the per-element grain.
- `skills/module-review.md` — stage 3 (PROVE) is where this rung runs; stage 4 (LOOK) §4c is
  where judgement on an ambiguous PASS (right target vs. merely *a* target) gets made.
- `.ai-context/skills/test-app.md` (bundled with mxcli in the consuming project) — the
  `playwright-cli` / `mxcli playwright` command reference, session management, and selector rules
  this pass is built on. Read it first; this skill adds no new tooling on top of it.
- `skills/skills-over-scripts.md` — why the verdict table lives in prose and not in a script
