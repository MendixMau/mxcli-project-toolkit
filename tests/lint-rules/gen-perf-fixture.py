#!/usr/bin/env python3
"""gen-perf-fixture.py -- write a synthetic fixture for timing the UX rules.

usage: gen-perf-fixture.py OUT.json [--flows N=3000] [--widgets M=20000] [--seed S=1]

N microflows with 10-14 activities each (2 are ExclusiveSplit), a refs_from chain of
depth 2 for every third flow, and M widgets, 10% of them microflow buttons without
confirmation pointing at random flows. Stdlib only. Synthetic, never captured output.
"""
import argparse, json, random

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--flows", type=int, default=3000)
ap.add_argument("--widgets", type=int, default=20000)
ap.add_argument("--seed", type=int, default=1)
a = ap.parse_args()
rnd = random.Random(a.seed)
MODS = ["Sales", "Orders", "Billing", "Stock", "Support"]

def q(i):
    return "%s.ACT_Flow%05d" % (MODS[i % len(MODS)], i)

flows, acts, refs = [], {}, {}
for i in range(a.flows):
    n = rnd.randint(10, 14)
    qn = q(i)
    flows.append(dict(id="m%d" % i, name=qn.split(".")[1], qualified_name=qn,
                      module_name=MODS[i % len(MODS)], microflow_type="MICROFLOW",
                      description="", activity_count=n))
    items = []
    for k in range(n):
        if k in (2, 5):
            items.append(dict(id="a%d_%d" % (i, k), name="d%d" % k, caption="Decision",
                              activity_type="ExclusiveSplit", auto_generate_caption=True))
        else:
            items.append(dict(id="a%d_%d" % (i, k), name="s%d" % k, caption="Step",
                              activity_type="ActionActivity",
                              action_type="DeleteObjectAction" if rnd.random() < 0.02 else "CommitObjectsAction" if rnd.random() < 0.2 else ""))
    acts[qn] = items
    if i % 3 == 0 and i + 2 < a.flows:
        def r(s, t):
            return dict(source_type="MICROFLOW", source_name=s, target_type="MICROFLOW",
                        target_name=t, ref_kind="CALL", module_name=s.split(".")[0])
        refs[qn] = [r(qn, q(i + 1))]
        refs[q(i + 1)] = [r(q(i + 1), q(i + 2))]

widgets = []
for j in range(a.widgets):
    mod = MODS[j % len(MODS)]
    cont = "%s.Page%04d" % (mod, j // 20)
    d = dict(id="w%d" % j, name="w%d" % j, widget_type="ACTIONBUTTON", container_id="p%d" % (j // 20),
             container_qualified_name=cont, container_type="PAGE", module_name=mod)
    if j % 10 == 0:
        d.update(action_type="Forms$MicroflowClientAction", has_confirmation=False,
                 microflow_ref=q(rnd.randrange(a.flows)))
    elif j % 10 < 6:
        d.update(action_type="Forms$ShowPageClientAction", page_ref="Sales.Order_Edit")
    else:
        d.update(action_type="")
    widgets.append(d)

with open(a.out, "w") as f:
    json.dump(dict(widgets=widgets, microflows=flows, activities=acts, refs_from=refs), f)
print("wrote %s: %d flows, %d widgets" % (a.out, a.flows, a.widgets))
