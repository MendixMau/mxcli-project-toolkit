#!/usr/bin/env python3
"""checkdiff.py: compare two `mx check` outputs; did a repair step make the app worse?

  checkdiff.py BEFORE.log AFTER.log [--fixed CE1613[,CE0456]]

Reads lines "[error] [CE1613] ..." / "[warning] [CW...] ..." and the summary "The app contains: N errors.".
WORSE when the error count went up or an error code appears that BEFORE did not have (E5 F16: `fix design-properties`
turned an Atlas 3.13 upgrade into 142 CE6085). Prints counts per code, gone and new.
--fixed names the error codes the fix was FOR. When every one of them is gone and the rise comes only from other codes,
the verdict is CASCADE, exit 0: mx check reports one layer at a time, so removing all 121 CE1613 can reveal 217 CE0463
that were hidden below them (E4-26). Continue with the new class. Without --fixed a rise is always WORSE (a fixer that
swaps one class for another, like the design-properties fixer in E5, also removes a class).
Exit: 0 = not worse (OK or CASCADE), 1 = WORSE, 2 = unreadable.
"""
import collections, re, sys


def read(p):
    t = open(p, errors="replace").read()
    codes = collections.Counter(re.findall(r"^\[error\]\s*\[(C[EW]\d+)\]", t, re.M))
    m = re.search(r"The app contains:\s*(\d+) errors", t)
    if m is None and not codes:
        print(f"checkdiff: {p}: not an mx check output (empty or cut off: if mx exited 139 it CRASHED, retry; see mx10.sh preload)", file=sys.stderr); sys.exit(2)
    return (int(m.group(1)) if m else sum(codes.values())), codes


if __name__ == "__main__":
    args = sys.argv[1:]
    fixed = []
    if "--fixed" in args:
        i = args.index("--fixed"); fixed = [c.strip() for c in args[i + 1].split(",") if c.strip()]; del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    (nb, cb), (na, ca) = read(args[0]), read(args[1])
    new = sorted(set(ca) - set(cb))
    gone = sorted(c for c in cb if cb[c] and not ca[c])
    for c in sorted(set(cb) | set(ca)):
        if cb[c] != ca[c]:
            print(f"{c}: {cb[c]} -> {ca[c]}" + ("  NEW CODE" if c in new else "  GONE" if c in gone else ""))
    worse = na > nb or bool(new)
    if worse and fixed:
        rose = [c for c in set(cb) | set(ca) if ca[c] > cb[c]]
        if all(c in gone for c in fixed) and not set(rose) & set(fixed):
            print(f"CASCADE: errors {nb} -> {na}; the fixed class {', '.join(f'{c} ({cb[c]} -> 0)' for c in fixed)} is gone, "
                  f"new below it: {', '.join(f'{c} {ca[c]}' for c in sorted(rose))}. Not a regression of this fix: continue with the new class")
            sys.exit(0)
        missed = [c for c in fixed if c not in gone]
        print(f"   --fixed {', '.join(missed)} is not gone: this is not a cascade")
    print(f"{'WORSE' if worse else 'OK'}: errors {nb} -> {na}" + (f"; new codes {', '.join(new)}" if new else "")
          + (f"; gone {', '.join(gone)}" if gone else ""))
    if worse and gone and not fixed:
        print(f"   {', '.join(gone)} disappeared completely. If the fix targeted exactly that class, rerun with --fixed "
              f"{','.join(gone)}: a class revealed below it is a CASCADE, not WORSE")
    sys.exit(1 if worse else 0)
