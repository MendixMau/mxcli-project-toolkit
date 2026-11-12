#!/usr/bin/env python3
"""scancover.py: tell "the scanner found nothing" apart from "the scanner checked nothing".

Why (E5 F1, E1 6): the upgrade scanner scan.py exits 0 with "0 finding(s) from 0 applicable catalog entries; 6/6 scans ok"
when no catalog entry applies to the rung. Its catalog (2026.09) holds Mendix 11 blockers only, so every 9 -> 10 and
10.x -> 10.24 scan is vacuous and still reads as clean. scan.py is not part of this toolkit (it is maintained
separately), so this wrapper reads its findings.json and fails loudly instead.

  scancover.py findings.json

Prints COVERED (n applicable entries) or NO COVERAGE plus the manual checks for the rung, which then replace the scan.
Exit: 0 = at least one catalog entry applied, 1 = NO COVERAGE (do the listed manual checks), 2 = input error.
"""
import json, sys

MANUAL = {
    "9->10": [
        "bin/javafinal.py <app>: Java action parameters are final in 10 (javac error; mx check says 0 errors) (E5 F19)",
        "Java 11 -> 21 (runtime image and own Java code); PDFBox 2 -> 3 and other vendorlib jars after module updates",
        "legacy scheduled events are removed in 10: convert them to the new scheduled event type",
        "REST: 9.x serves /rest-doc/<svc>/swagger.json, 10.x openapi.json; snapshot.py reads both, diff.py compares contracts",
        "module updates: mx 9.24 has no module-import, so convert first, then update once on 10.x (playbooks/9-to-10.md)",
    ],
    "10->10": [
        "Java 21 for 10.13+ (runtime image and own Java code)",
        "web service users calling published REST services (authentication changes in 10.x minors)",
        "generated HTML ids of widgets changed: check custom CSS/JS and test selectors",
        "module major versions can change the after-startup contract (ASU deprecated): read release notes for 'ASU'",
    ],
}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        d = json.load(open(sys.argv[1]))
        n = int(d["catalog_entries_applicable"])
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"scancover: {sys.argv[1]}: not a scan.py findings.json ({e})", file=sys.stderr); sys.exit(2)
    p = d.get("project") or {}
    frm, to = str(p.get("from_version", "?")), str(p.get("target_version", "?"))
    if n > 0:
        print(f"COVERED: {n} of {d.get('catalog_entries_total', '?')} catalog entries apply to {frm} -> {to}; "
              f"{len(d.get('findings') or [])} findings")
        sys.exit(0)
    rung = f"{frm.split('.')[0]}->{to.split('.')[0]}"
    print(f"NO COVERAGE: 0 of {d.get('catalog_entries_total', '?')} catalog entries apply to {frm} -> {to}. "
          "'0 findings' means nothing was checked, not clean.")
    for m in MANUAL.get(rung, ["no manual list for this rung: read the Mendix release notes for every minor in between"]):
        print(f"  manual check: {m}")
    sys.exit(1)


if __name__ == "__main__":
    main()
