# Draft findings, synthetic (test fixture: invented names and messages, no real project)

## BUG-DRAFT-rewire-refusal: ALTER MICROFLOW refuses to rewire an activity (2026-01-02)

Version: mxcli v0.27.0, Mendix 10.24.

- Expected: `ALTER MICROFLOW Shop.ACT_Order` moves the Approve activity behind the new decision.
- Actual: `Shop.ACT_Order cannot be rewired: no base activity survives the edit`.
- Workaround: drop the flow and create it again in one script.

## BUG-DRAFT-gallery-lost-ref: a gallery action leaves no catalog edge (2026-01-02)

Version: mxcli v0.27.0.

- Expected: `show references to Shop.DS_Orders` lists the page.
- Actual: `no references found` while `describe page Shop.Order_Overview` prints the datasource.
- Workaround: grep the `describe page` output.
