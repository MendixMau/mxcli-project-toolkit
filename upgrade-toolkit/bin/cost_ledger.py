#!/usr/bin/env python3
"""cost_ledger.py: record and report what each judgement layer cost (wall minutes, tokens, human review minutes).

Why: quality-judgement-plan.md section 1 point 4 asks for a per-layer cost baseline before any cost target is set.
Without a line per layer, a layer that was never costed reads as zero, which is the same silent-absence failure the
obligation check exists to prevent. So the report names every layer with no cost line as "no cost line", and the
denominator is stated: "layers with a cost line: N of 9".

  cost_ledger.py add    --layer L2 --step "bar impact walk" --wall 14.5 [--tokens 52000|-] [--review 6|-] [--note "..."]
  cost_ledger.py report

  --work DIR   the work folder; default $W, then $WORK. The ledger is DIR/cost-ledger.tsv (one line per add).

Layers (fixed; these are the nine rows of quality-judgement-plan.md section 2): L0 L1 L1b L2 L3 L4 L5 L6 C.
A phase such as triage or repair is not a layer and is refused (exit 2): cost it under the layer it served, or leave it
out of the baseline and say so in the register. --wall is required, --tokens and --review take '-' when not known.
Measurement only: gate.sh prints this report and never reads it for a verdict.

Ledger format: a header line, then one TAB-separated line per add:
  layer  step  wall_min  tokens  review_min  note

Exit codes: 0 ok; 1 the ledger has a malformed line (report names it); 2 usage or input error (unknown layer, bad number,
no work folder given).
"""
import argparse, os, sys

LAYERS = ["L0", "L1", "L1b", "L2", "L3", "L4", "L5", "L6", "C"]
HEADER = "layer\tstep\twall_min\ttokens\treview_min\tnote"
LEDGER = "cost-ledger.tsv"


def die(msg, code=2):
    print(f"cost_ledger: {msg}", file=sys.stderr)
    sys.exit(code)


def clean(text):
    """A field cannot carry a tab or a newline: they would split the line."""
    return " ".join(str(text).replace("\t", " ").split())


def number(value, name, integer=False):
    if value == "-":
        return "-"
    try:
        x = int(value) if integer else float(value)
    except ValueError:
        die(f"--{name} {value!r}: a number, or '-' when not known")
    if x < 0:
        die(f"--{name} {value!r}: must not be negative")
    return str(x) if integer else f"{x:.2f}"


def work_dir(arg):
    d = arg or os.environ.get("W") or os.environ.get("WORK")
    if not d:
        die("no work folder: give --work DIR, or set W (or WORK)")
    return d


def cmd_add(a):
    if a.layer not in LAYERS:
        die(f"unknown layer {a.layer!r}; known layers: {' '.join(LAYERS)} (a phase such as triage is not a layer)")
    step = clean(a.step)
    if not step:
        die("--step is empty")
    wall = number(a.wall, "wall")
    if wall == "-":
        die("--wall is required (wall minutes of the layer's step)")
    tokens = number(a.tokens, "tokens", integer=True)
    review = number(a.review, "review")
    folder = work_dir(a.work)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, LEDGER)
    new = not os.path.isfile(path) or os.path.getsize(path) == 0
    with open(path, "a", encoding="utf-8") as f:
        if new:
            f.write(HEADER + "\n")
        f.write("\t".join([a.layer, step, wall, tokens, review, clean(a.note or "")]) + "\n")
    print(f"cost_ledger: {a.layer} {step!r} wall {wall} min, tokens {tokens}, review {review} min -> {path}")


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if n == 1 and line == HEADER:
                continue
            parts = line.split("\t")
            if len(parts) < 5 or parts[0] not in LAYERS:
                die(f"{path}: line {n} is malformed or names an unknown layer: {line!r}", code=1)
            rows.append(parts)
    return rows


def cmd_report(a):
    folder = work_dir(a.work)
    path = os.path.join(folder, LEDGER)
    rows = read_rows(path) if os.path.isfile(path) else []
    by = {L: [] for L in LAYERS}
    for r in rows:
        by[r[0]].append(r)
    print(f"cost ledger: {path}" if rows else f"cost ledger: {path} (no lines yet)")
    print(f"{'layer':<6} {'lines':>5} {'wall_min':>9} {'tokens':>10} {'review_min':>11}  steps")
    tot_w = tot_r = 0.0
    tot_t = 0
    n_t = n_r = 0  # lines that gave a number: a total over none is '-', never 0
    for L in LAYERS:
        rs = by[L]
        if not rs:
            print(f"{L:<6} no cost line")
            continue
        w = sum(float(r[2]) for r in rs)
        tk = [int(r[3]) for r in rs if r[3] != "-"]
        rv = [float(r[4]) for r in rs if r[4] != "-"]
        tot_w += w
        tot_t += sum(tk)
        tot_r += sum(rv)
        n_t += len(tk)
        n_r += len(rv)
        tok = ("-" if not tk else f"{sum(tk)}") + ("" if len(tk) == len(rs) else f" ({len(rs) - len(tk)} not given)")
        rev = ("-" if not rv else f"{sum(rv):.2f}") + ("" if len(rv) == len(rs) else f" ({len(rs) - len(rv)} not given)")
        steps = "; ".join(r[1] for r in rs)
        print(f"{L:<6} {len(rs):>5} {w:>9.2f} {tok:>10} {rev:>11}  {steps}")
    t_tok = f"{tot_t}" if n_t else "-"
    t_rev = f"{tot_r:.2f}" if n_r else "-"
    print(f"{'total':<6} {len(rows):>5} {tot_w:>9.2f} {t_tok:>10} {t_rev:>11}  (sums over the lines that gave a number)")
    have = sum(1 for L in LAYERS if by[L])
    print(f"layers with a cost line: {have} of {len(LAYERS)}")


def main():
    ap = argparse.ArgumentParser(description="Per-layer cost ledger (measurement only).")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("add", help="append one cost line for a layer")
    p.add_argument("--layer", required=True)
    p.add_argument("--step", required=True, help="what was run, e.g. 'bar impact walk'")
    p.add_argument("--wall", required=True, help="wall minutes")
    p.add_argument("--tokens", default="-", help="tokens used, or '-'")
    p.add_argument("--review", default="-", help="human review minutes, or '-'")
    p.add_argument("--note", default="")
    p.add_argument("--work", default=None)
    p.set_defaults(fn=cmd_add)
    r = sub.add_parser("report", help="per-layer totals, and the layers with no cost line")
    r.add_argument("--work", default=None)
    r.set_defaults(fn=cmd_report)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
