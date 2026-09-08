**Repo:** `mendixlabs/mxcli`
**Source:** `bug-logs/mxcli-bugs.md`, `## BUG-119` — found 2026-09-07 when script `88c` of a
Phase-19 conversion project shipped entirely inert (Mendix 11.13.0)
**Status:** DRAFT — not yet filed
**Suggested labels:** bug, alter-page, silent-failure, safety

---

**Title:** `ALTER PAGE … SET Label` prints "Altered page" and discards the value

**Body:**

## Summary

`alter page … { set Label = '…' on <widget> }` reports success, passes `mxbuild`, and **does not
change the model**. `DESCRIBE PAGE` afterwards shows the old label.

This is a silent no-op, not an unsupported property: the setter resolves the widget and knows its
property list — it rejects `Caption` **by name** on the same widget — and it applies `Class` on
that same widget correctly. It accepts `Label`, reports success, and drops the value.

## Repro

One page, one session, four statements on a throwaway copy of the `.mpr`:

```
set Label   = 'Indicator status *' on cb100Ind    (combobox) → "Altered page", model unchanged
set Label   = 'PROBE-TEXTBOX'      on tb010Phase  (textbox)  → "Altered page", model unchanged
set Class   = 'probe-class'        on cb100Ind               → applied correctly
set Caption = 'PROBE-CAPTION'      on cb100Ind               → Error: failed to set:
                                                               failed to set Caption on cb100Ind:
                                                               widget has no Caption property
```

Verified after each statement with
`mxcli -p copy.mpr -c "DESCRIBE PAGE Approval.Approval_StationTask"`.

## Impact

**Every gate in the pipeline passes on an inert script.** `mxcli check --references` passes, `exec`
prints `Altered page`, `mxbuild` returns 0 errors, the commit goes in, and the model is unchanged.
The only way to find out is to open the page in a browser and read it.

On this project the affected script existed *solely* to add a required-field marker to a label. It
was committed, gated and reported as done, and the marker was never there. A reviewer trusting the
exec output — which is the normal thing to do — would not look. This is materially worse than
BUG-115, where the equivalent `ALTER PAGE` property mismatch at least fails loudly.

## Workaround

```
alter page Module.Page {
  replace <widget> with { <widget re-declared with the new label> }
}
```

Applies correctly. Every other property must be re-declared verbatim from `DESCRIBE PAGE` or the
replace quietly drops it — so a one-word label change becomes a hand-transcribed widget block.

## Expected

Apply `Label`, or reject it the way `Caption` is rejected. A write path that reports success
without writing is the one failure mode a validation pipeline cannot catch.

## Related

BUG-115 (`ALTER PAGE … SET PageSize` rejected on a widget `CREATE` accepts). Same underlying theme
— the `ALTER PAGE` property surface disagrees with the `CREATE` one — opposite and much more
dangerous failure mode.
