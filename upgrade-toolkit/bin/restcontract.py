#!/usr/bin/env python3
"""restcontract.py: compare published REST contracts saved before and after an upgrade (Swagger 2.0 or OpenAPI 3).

  restcontract.py BEFORE AFTER        files, or folders of <service>.json files (same file names on both sides)

Same rules as the http contract check in diff.py (one implementation): an operation, response code or parameter
that is gone, or a parameter that became required, is FAIL; additions are INFO. Mendix 9.24 publishes
/rest-doc/<svc>/swagger.json, Mendix 10+ also openapi.json: compare like with like (swagger to swagger).
Exit: 0 = every contract kept, 1 = a contract lost something, 2 = input error (missing file, not a contract).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from snapshot import contract  # noqa: E402
from diff import contract_diff  # noqa: E402


def load(p):
    try:
        spec = json.load(open(p))
    except Exception as e:
        print(f"restcontract: {p}: {e}", file=sys.stderr); sys.exit(2)
    if "paths" not in spec:
        print(f"restcontract: {p}: no 'paths', not a Swagger/OpenAPI document", file=sys.stderr); sys.exit(2)
    return contract(spec)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    b, a = sys.argv[1:]
    if os.path.isdir(b):
        names = sorted(f for f in os.listdir(b) if f.endswith(".json"))
        pairs = [(n, os.path.join(b, n), os.path.join(a, n)) for n in names]
    else:
        pairs = [(os.path.basename(b), b, a)]
    bad = 0
    for name, pb, pa in pairs:
        if not os.path.exists(pa):
            print(f"FAIL {name}: missing after"); bad += 1; continue
        lost, gained = contract_diff(load(pb), load(pa))
        ops = sum(len(v) for v in load(pb).values())
        if lost:
            bad += 1
            print(f"FAIL {name}: " + "; ".join(lost))
        else:
            print(f"PASS {name}: {ops} operations kept" + (f"; added: {'; '.join(gained)}" if gained else ""))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
