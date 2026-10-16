#!/usr/bin/env python3
"""fix-describe-output.py <in.mdl> <out.mdl> — repair describe output that mxcli's own parser rejects.

Only shapes that are unambiguously an emitter defect (mxcli 0.26.0, GenAI showcase app 2026-10-12):
  1. java action / javascript action parameter lines put the separating `,` AFTER the `-- comment`,
     so the comment swallows it: `    Name: String not null  -- The name.,` → `mismatched input
     'Name' expecting ')'`. Move the comma in front of the comment. 10 of 36 modules failed check on
     this alone, and 25 more failed as a cascade.
Everything else stays byte-identical (CRLF inside literals is load-bearing).
"""
import re, sys
t = open(sys.argv[1], encoding='utf-8', newline='').read()
n = [0]
def comma(m):
    n[0] += 1
    return m.group(1) + ',' + m.group(2).rstrip() + m.group(3)
t = re.sub(r'^(    [A-Za-z0-9_"]+: [^\n]*?)(  -- [^\n]*?),[ \t]*(\r?\n)', comma, t, flags=re.M)
open(sys.argv[2], 'w', encoding='utf-8', newline='').write(t)
sys.stderr.write('fix-describe-output: %d parameter commas moved out of comments\n' % n[0])
