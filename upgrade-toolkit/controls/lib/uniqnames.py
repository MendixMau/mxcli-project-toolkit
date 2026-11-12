#!/usr/bin/env python3
"""uniqnames.py: read seed_pg.py --dry-run SQL on stdin, list the System.User names it inserts, exit 1 on a duplicate."""
import collections, re, sys

names = re.findall(r'INSERT INTO "system\$user" \([^)]*"name"\) VALUES \(.*, \'([^\']*)\'\);', sys.stdin.read())
dup = sorted(k for k, c in collections.Counter(names).items() if c > 1)
print(f"{len(names)} names, duplicates: {dup}")
sys.exit(1 if dup or not names else 0)
