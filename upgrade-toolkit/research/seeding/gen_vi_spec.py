#!/usr/bin/env python3
"""gen_vi_spec.py: gap fill on top of the Visual Inspection publisher snapshot, as a seed_usecase.py spec.

    python3 gen_vi_spec.py "docker exec -i mig-pg psql -U mendix -d vi_snap_smoke" > vi-gap-seed.json

The snapshot (route a, seed_snapshot.py) already holds products, views, locations, defect types, 25 inspections in all three
statuses and 84 defects. What it does NOT hold, found by reading the pages' needs (page_data_needs.py) and counting
(research/seeding/VISUAL-INSPECTION-data-map.md):
  - an Employee linked to each smoke user (the dashboards show the inspector's name; the link is by Employee_Account),
  - Inspections owned by the smoke inspector, so "my ongoing inspections" is not someone else's list,
  - Tasks (Inspection.Task, 0 rows: the Task pages and the ticket list need one per open defect they follow),
  - a chatbot ConfigurationSelection and an AWS Settings row (the two Settings tabs list them; dummy values, no secret, no call),
It reads existing keys from the database (smoke accounts, a product, its locations, defect types, open defects) and refers to
them by lookup, never by guessing an id.
"""
import json, subprocess, shlex, sys

psql = shlex.split(sys.argv[1])
def q(sql):
    r = subprocess.run(psql + ["-X", "-tA", "-F", "|", "-v", "ON_ERROR_STOP=1"], input=sql, capture_output=True, text=True)
    if r.returncode: sys.exit("psql: " + r.stderr[:300])
    return [l.split("|") for l in r.stdout.splitlines() if l]

O = []
def add(ref, entity, attrs=None, links=None, **kw):
    o = {"ref": ref, "entity": entity}
    if attrs: o["attrs"] = attrs
    if links: o["links"] = links
    o.update(kw); O.append(o)

# identities
people = [("administrator", "Anna", "Visser"), ("qualitymanager", "Maria", "Jansen"), ("inspector", "Tom", "Becker")]
for role, f, l in people:
    add("acc_" + role, "Administration.Account", lookup={"Name": "smoke_" + role})
    add("emp_" + role, "EmployeeManagement.Employee", {"UUID": "smoke-" + role, "FirstName": f, "LastName": l, "FullName": f + " " + l, "EmailAddress": f.lower() + "." + l.lower() + "@example.com"},
        {"Employee_Account": "acc_" + role})

# a product with locations: two ongoing inspections for the smoke inspector, each with defects
prod = q('select p."_id" from "masterdata$product" p where p.name = \'SIMATIC ET 200SP R1\'')[0][0]
locs = [r[0] for r in q('select l.uuid from "masterdata$location" l join "masterdata$location_productview" lp on lp."masterdata$locationid"=l.id '
                        'join "masterdata$productview_product" pv on pv."masterdata$productviewid"=lp."masterdata$productviewid" join "masterdata$product" p on p.id=pv."masterdata$productid" '
                        'where p."_id" = %s order by l.uuid limit 4' % ("'" + prod + "'"))]
dts = [r[0] for r in q('select dt.code from "masterdata$defecttype" dt order by dt.code limit 3')]
add("prod", "MasterData.Product", lookup={"_ID": prod})
for i, l in enumerate(locs): add("loc%d" % i, "MasterData.Location", lookup={"UUID": l})
for i, c in enumerate(dts): add("dt%d" % i, "MasterData.DefectType", lookup={"Code": c})
for k, (sn, status, ndef) in enumerate([("SI-20261013-001", "Open", 2), ("SI-20261013-002", "Open", 1), ("SI-20261012-007", "Inspection_done", 2)]):
    ref = "ins%d" % k
    add(ref, "Inspection.Inspection", {"_ID": "IVSM%04d" % (k + 1), "Status": status, "SerialNumber": sn, "NumberOfTickets": ndef, "NumberOfOpenTickets": ndef if status != "Tickets_done" else 0,
                                      "CreatedOn": "-%dh" % (k * 5 + 1)},
        {"Inspection_Product": "prod", "Inspection_Employee_Inspector": "emp_inspector"})
    for d in range(ndef):
        add("%s_def%d" % (ref, d), "Inspection.Defect", {"_ID": "DVSM%04d" % (k * 10 + d + 1), "Comment": ["Scratch near the connector, about 3 cm", "Label printed off-centre", "Dent on the housing edge"][(k + d) % 3],
                                                       "Status": "Open", "CreatedOn": "-%dh" % (k * 5 + 1)},
            {"Defect_Inspection": ref, "Defect_Location": "loc%d" % ((k + d) % max(1, len(locs))), "Defect_DefectType": "dt%d" % ((k + d) % max(1, len(dts)))})
        add("%s_task%d" % (ref, d), "Inspection.Task", {"Name": ["Re-inspect housing", "Check label printer", "Order replacement part"][(k + d) % 3], "Email": "quality@example.com", "DueDate": "+%dd" % (d + 2)},
            {"Task_Defect": "%s_def%d" % (ref, d)})
# the two settings tabs
add("aws", "AWSAuthentication.Settings", {"Region": "eu_west_1", "UseStaticCredentials": False})
add("bedrock", "AIChatbotBedrock.ConfigurationSelection", {"DisplayName": "Defect assistant (demo, not connected)", "ConfigName": "defect-assistant-demo", "IsActive": False,
                                                           "SystemPrompt": "You help inspectors describe defects.", "AmazonBedrockRegion": "eu_west_1"})
print(json.dumps({"objects": O}, indent=1))
