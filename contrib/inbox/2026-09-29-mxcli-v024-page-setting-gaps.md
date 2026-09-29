# mxcli v0.24.0: 8 page settings refused/dropped, file property unwritable, DESCRIBE round-trip gap — ledger coverage partial

**From:** benchmark cook-off (mxcli + toolkit arm vs Studio Pro MCP arm, same frozen spec)
**Date:** 2026-09-29
**Kind:** bug
**Field evidence:** toolkit arm's c4-01 script and UI pass (METRICS.md, BUILD-LOG.md in the run repo); ~190 of 301 excluded minutes were mxcli diagnosis and fixes; fixes sit on 9 branches of the MendixMau/mxcli fork plus fix/widget-file-property, no upstream PR found.
**Proposed target:** `bug-logs/mxcli-bugs.md` (BUG-117 is related)

---

Refused or silently dropped on v0.24.0 (3 of the 8 were *false* warnings — value was stored):
linked gallery filters; gallery onClick; date picker DateFormat; group digits; native Required
(MDL-WIDGET07 drop); combobox caption expression / emptyOptionText (MDL-WIDGET06 "recognized
but not persisted"); delete confirmation + role visibility; uploader max files.

Also:
- Pluggable widget `type="file"` property (Document Viewer) unwritable: MDL-WIDGET06, then
  CE0642 "Document is required". The MCP arm hit the same gap and worked around it by
  removing and re-adding the widget.
- `index on createdDate`: "attribute createdDate not found for index" — system attribute not
  addressable.
- `DESCRIBE` prints a bare `FullName` caption attribute; replaying the output passes
  `mxcli check` but fails `mx check` with CE1613 (round-trip not lossless).

Ledger status: only BUG-117, gallery filters and dateFormat are covered. Missing: false
warnings, file property, createdDate index, DESCRIBE round-trip.

All recur on the next run until the fork fixes ship in a release. Proposed: add the missing
ledger entries now; open the upstream PRs; make silent drops hard errors and remove the false
warnings (3 of 8 probes were wasted on them).
