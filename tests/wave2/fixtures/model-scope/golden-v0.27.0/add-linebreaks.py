# Put "\n" between the bracket groups of every stored XpathConstraint of the two named microflows,
# through the toolkit's mxpatch library (unit file + ContentsHash row in one step).
import sys, os
sys.path.insert(0, sys.argv[1]); import mxpatch
m = mxpatch.Model(sys.argv[2])
for mod, name in (("MyFirstModule", "ACT_Item_Fetch"), ("Other", "ACT_Thing_Fetch")):
    u = m.find_unit("Microflows$Microflow", name, module=mod)
    for node in mxpatch.walk(u.doc):
        for i, (t, k, v) in enumerate(node):
            if k == "XpathConstraint" and t == 0x02 and "][" in v:
                node[i] = (t, k, v.replace("][", "]\n["))
                print(mod, name, repr(v), "->", repr(node[i][2]))
    print(m.write_unit(u, apply=True))
