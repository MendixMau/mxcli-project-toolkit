# wiring-sweep: no verdict row for "disabled by design", and DOM enumeration misses conditionally visible controls

**From:** card-disbursement requirements-driven build (build-plan row 4.8)
**Date:** 2026-09-26
**Kind:** learning
**Field evidence:** a console page with 3 Data grid 2 grids swept by direct Playwright: 48 elements were enumerated from the DOM, 44 PASS, and 4 FAIL "not interactable". The 4 were previous/next pagers on grids whose rows all fit on one page. The page's Disarm button (`Visible: [Active]`) was not in the enumeration, because no row was armed at sweep time.
**Proposed target:** `skills/wiring-sweep.md` (verdict table, enumeration step)

---

1. **Disabled by design.** Data grid 2 disables previous/next when every row fits on one page. The
   verdict table maps "disabled" → FAIL (not interactable), so 4 elements read FAIL with no defect behind them.
   The sweep report carried them as FAIL with a by-design disposition. A row "disabled, and the widget's
   own state explains it (pager on one page, save on an unchanged form)" → PASS-by-design, or N/A with a stated
   reason, would keep the denominator honest without a hand-written excuse per project.
2. **Conditional visibility.** A control behind a `Visible:` expression is absent from the DOM unless
   its condition holds, so DOM enumeration silently shrinks the denominator. Disarm was swept separately:
   the landing armed a row first (a Timeout scenario, since Success leaves the row inactive), and it went 1 of 1 PASS.
   Proposal: enumerate the widgets from the page script (or `describe page`), not only the DOM, and
   flag any widget with a `Visible:` condition that the sweep did not reach.
