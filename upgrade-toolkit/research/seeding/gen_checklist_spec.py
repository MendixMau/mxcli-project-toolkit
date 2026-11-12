#!/usr/bin/env python3
"""gen_checklist_spec.py: the use-case seed of the Checklist to go template (9.24), as a seed_usecase.py spec.

    python3 gen_checklist_spec.py > checklist-seed.json

Use case: a plant runs safety / quality / housekeeping checklists per department. A department manager defines the
templates (groups of questions of 5 types), inspectors execute instances of them, a manager reviews what was submitted and
reassigns what is overdue. Every page filters on the instance Status, the inspector sees only the instances whose
Employee_Responsible is the employee linked to HIS account, so the data is built around those two facts:
  - 3 departments, 3 checklist types, 6 templates (5 active, 1 retired), 2 groups x 4-5 questions each, one question of each type;
  - 11 instances, at least one in EVERY status of ENUM_InstanceChecklistStatus, instance questions answered to match the status;
  - 6 employees; three of them are linked to the smoke users (lookup of smoke_administrator / smoke_departmentmanager /
    smoke_inspector, so smoke_users.py must have run on the database first).
Names are invented; no customer data. Deterministic (uuid5), so the SQL it leads to is reproducible.
"""
import json, uuid

O = []
NS = uuid.UUID("12345678-1234-5678-1234-567812345678")
U = lambda k: str(uuid.uuid5(NS, k))


def add(ref, entity, attrs=None, links=None, **kw):
    o = {"ref": ref, "entity": entity}
    if attrs: o["attrs"] = attrs
    if links: o["links"] = links
    o.update(kw)
    O.append(o)


# --- identities: smoke users (made by smoke_users.py) ------------------------------------------------------------
for role in ("administrator", "departmentmanager", "inspector"):
    add("acc_" + role, "Administration.Account", lookup={"Name": "smoke_" + role})

# --- employees ----------------------------------------------------------------------------------------------------
EMP = [("e_admin", "Anna", "Visser", "anna.visser@example.com", False, "acc_administrator"),
       ("e_mgr", "Maria", "Jansen", "maria.jansen@example.com", False, "acc_departmentmanager"),
       ("e_tom", "Tom", "Becker", "tom.becker@example.com", True, "acc_inspector"),
       ("e_priya", "Priya", "Nair", "priya.nair@example.com", True, None),
       ("e_lars", "Lars", "Eriksson", "lars.eriksson@example.com", True, None),
       ("e_chen", "Chen", "Wei", "chen.wei@example.com", False, None)]
for ref, f, l, mail, resp, acc in EMP:
    add(ref, "EmployeeManagement.Employee",
        {"UUID": U(ref), "FirstName": f, "LastName": l, "FullName": f + " " + l, "EmailAddress": mail, "PhoneNumber": "+31 20 555 01%02d" % (len(O) % 100), "CanBeResponsible": resp},
        {"Employee_Account": acc} if acc else None)

# --- master data --------------------------------------------------------------------------------------------------
DEP = [("d_asm", "Assembly", ["e_tom", "e_priya"]), ("d_wh", "Warehouse", ["e_tom", "e_lars"]), ("d_lab", "Quality Lab", ["e_priya", "e_chen"])]
for i, (ref, name, emps) in enumerate(DEP, 1):
    add(ref, "Masterdata.Department", {"UUID": U(ref), "TabIndex": i, "DisplayName": name}, {"Department_Employee": emps})
for ref, name in (("t_safety", "Safety"), ("t_quality", "Quality"), ("t_house", "Housekeeping")):
    add(ref, "Masterdata.ChecklistType", {"Name": name})

# --- templates: (ref, name, description, location, department, type, active, repeat) -------------------------------
TPL = [("c_fork", "Daily forklift inspection", "Pre-shift check of every forklift before it leaves the charging bay.", "Hall 2", "Bay 4", "d_wh", "t_safety", True, "Daily"),
       ("c_fire", "Weekly fire extinguisher check", "Seal, pressure gauge, signage and access of each extinguisher.", "Hall 1", "Line A", "d_asm", "t_safety", True, "Weekly"),
       ("c_gate", "Line start-up quality gate", "Release criteria before the first part of a shift is shipped.", "Hall 1", "Line B", "d_asm", "t_quality", True, None),
       ("c_5s", "5S audit goods-in", "Sort, set in order, shine, standardise, sustain.", "Hall 2", "Goods-in", "d_wh", "t_house", True, "Monthly"),
       ("c_cal", "Lab calibration log", "Torque wrench and caliper calibration status.", "Lab", "Room 3", "d_lab", "t_quality", True, "Weekly"),
       ("c_rack", "Pallet racking audit (retired)", "Replaced by the daily forklift inspection.", "Hall 2", "Aisle 7", "d_wh", "t_safety", False, None)]
# 2 groups per template, question kinds: (kind, title)
QS = [[("Checkbox", "Condition checks", ["Tyres undamaged", "Forks free of cracks", "Horn works", "Lights work"]),
       ("Text", "Hour meter reading", None), ("Instruction", "Park on the marked bay with forks lowered", None),
       ("Multiple_choice", "Battery charge level", ["Below 20%", "20-60%", "Above 60%"]), ("Picture", "Photo of any visible damage", None)],
      [("Checkbox", "Safety equipment present", ["Seat belt", "Warning light", "Fire blanket"]), ("Text", "Remarks for the next shift", None),
       ("Multiple_choice", "Overall condition", ["Good", "Needs attention", "Out of service"]), ("Picture", "Photo of the data plate", None)]]
QT = {"Checkbox": "CheckboxQuestion", "Text": "TextQuestion", "Instruction": "InstructionQuestion", "Multiple_choice": "MultipleChoiceQuestion", "Picture": "PictureQuestion"}
CRIT = ["High", "Medium", "Low", "Medium", "High"]
tq = {}   # template ref -> list of (qref, kind, title, [opt refs])
for ci, (cref, name, desc, loc, sub, dep, typ, active, rep) in enumerate(TPL):
    attrs = {"Name": name, "Description": desc, "Location": loc, "SubLocation": sub, "IsActive": active, "IsAllResponsible": False,
             "ExpiresIn": 8 if rep == "Daily" else 3, "ExpiryUnit": "Hours" if rep == "Daily" else "Days", "IsRecurring": bool(rep), "HasPendingReviews": False}
    if rep: attrs["RepeatPeriod"] = rep; attrs["FrequencyInformation"] = rep
    if not active: attrs["RetiredDateTime"] = "-30d 09:00"
    add(cref, "Checklist_Template.Checklist", attrs,
        {"Checklist_Department": dep, "Checklist_ChecklistType": typ, "Checklist_Employee": "e_mgr",
         "Checklist_Employee_Responsible": ["e_tom", "e_priya"] if dep != "d_lab" else ["e_priya", "e_chen"]})
    tq[cref] = []
    for gi, qs in enumerate(QS):
        gref = "g_%s_%d" % (cref, gi)
        add(gref, "Checklist_Template.Group", {"Name": ["Equipment condition", "Handover"][gi] if gi < 2 else "Other", "Description": "Group %d of %s" % (gi + 1, name), "SequenceNumber": gi + 1}, {"Group_Checklist": cref})
        for qi, (kind, title, opts) in enumerate(qs):
            qref = "q_%s_%d_%d" % (cref, gi, qi)
            qa = {"UUID": U(qref), "Title": title if kind != "Checkbox" else title, "Description": "", "QuestionType": kind, "SequenceNumber": qi + 1,
                  "IsMandatory": kind not in ("Instruction",), "Criticality": CRIT[qi % 5], "AllowComment": kind != "Instruction", "AllowImages": kind == "Picture",
                  "PositiveOption": "Yes", "NegativeOption": "No"}
            if kind == "Text": qa["IsNumberValueRequired"] = (title == "Hour meter reading")
            add(qref, "Checklist_Template." + QT[kind], qa, {"Question_Group": gref})
            orefs = []
            for oi, ot in enumerate(opts or []):
                oref = "%s_o%d" % (qref, oi)
                if kind == "Checkbox":
                    add(oref, "Checklist_Template.CheckboxOption", {"Title": ot, "SequenceNumber": oi + 1}, {"CheckboxOption_CheckboxQuestion": qref})
                else:
                    add(oref, "Checklist_Template.MultipleChoiceOption", {"Title": ot, "SequenceNumber": oi + 1, "CorrectAnswer": oi == len(opts) - 1}, {"MultipleChoiceOption_MultipleChoiceQuestion": qref})
                orefs.append((oref, ot))
            tq[cref].append((qref, kind, title, orefs, qa["IsMandatory"], qa["Criticality"]))

# --- instances: (ref, template, status, responsible, start, end, answered fraction, compliant) -----------------------
INS = [("i1", "c_fork", "In_Progress", "e_tom", "-0d 06:00", "+0d 14:00", 0.5),
       ("i2", "c_fork", "Submitted", "e_tom", "-1d 06:00", "-1d 14:00", 1.0),
       ("i3", "c_fork", "Overdue_assigned", "e_tom", "-3d 06:00", "-2d 14:00", 0.0),
       ("i4", "c_fire", "_New", "e_tom", "-0d 08:00", "+4d 17:00", 0.0),
       ("i5", "c_fire", "Overdue_unassigned", None, "-6d 08:00", "-3d 17:00", 0.0),
       ("i6", "c_fire", "Resolved", "e_priya", "-9d 08:00", "-6d 17:00", 1.0),
       ("i7", "c_gate", "Overdue_waiting", "e_priya", "-5d 07:00", "-4d 15:00", 0.5),
       ("i8", "c_gate", "Overdue_done", "e_tom", "-8d 07:00", "-7d 15:00", 1.0),
       ("i9", "c_5s", "_New", "e_tom", "-0d 09:00", "+25d 17:00", 0.0),
       ("i10", "c_5s", "Submitted", "e_lars", "-2d 09:00", "-1d 17:00", 1.0),
       ("i11", "c_cal", "Submitted", "e_chen", "-2d 10:00", "-1d 17:00", 1.0)]
NC = {"i2": [3], "i6": [3, 7], "i8": [], "i10": [], "i11": [1, 3, 7], "i1": []}   # question indexes answered NotCompliant, per instance
for ref, cref, st, resp, start, end, frac in INS:
    nm = next(t[1] for t in TPL if t[0] == cref)
    done = st in ("Submitted", "Resolved", "Overdue_done")
    attrs = {"UUID": U(ref), "Name": nm, "Description": "Scheduled run of " + nm, "StartDateTime": start, "EndDateTime": end, "HasEndDate": True, "Status": st,
             "IsCompliant": done and not NC.get(ref),
             "Location": next(t[3] for t in TPL if t[0] == cref), "SubLocation": next(t[4] for t in TPL if t[0] == cref)}
    if done: attrs["SubmittedDateTIme"] = end
    if st == "Resolved": attrs["ResolvedDateTime"] = "-5d 10:00"
    links = {"InstanceChecklist_Checklist": cref, "InstanceChecklist_ChecklistType": next(t[6] for t in TPL if t[0] == cref)}
    if resp: links["InstanceChecklist_Employee_Responsible"] = resp
    if st == "Resolved": links["InstanceChecklist_Employee_Resolved"] = "e_mgr"
    if done:
        add("h_" + ref, "HistoryManagement.HistoryObject")
        add("hi_" + ref + "a", "HistoryManagement.HistoryItem", {"Subject": "Submitted", "Message": "Checklist submitted by the inspector", "By": "Tom Becker", "currentDate": end}, {"HistoryItem_HistoryObject": "h_" + ref})
        if st == "Resolved":
            add("hi_" + ref + "b", "HistoryManagement.HistoryItem", {"Subject": "Resolved", "Message": "Findings reviewed and closed by the department manager", "By": "Maria Jansen", "currentDate": "-5d 10:00"}, {"HistoryItem_HistoryObject": "h_" + ref})
        links["InstanceChecklist_HistoryObject"] = "h_" + ref
    add(ref, "Checklist_Instance.InstanceChecklist", attrs, links)
    qs = tq[cref]
    nans = round(len(qs) * frac)
    for k, (qref, kind, title, orefs, mand, crit) in enumerate(qs):
        iq = "%s_%s" % (ref, qref)
        answered = k < nans and kind != "Instruction"
        compliant = ("NotCompliant" if k in NC.get(ref, []) else "Compliant") if answered else None
        ia = {"UUID": U(iq), "Title": title, "Description": "", "QuestionType": kind, "SequenceNumber": k + 1, "IsMandatory": mand, "Criticality": crit,
              "AllowComment": kind != "Instruction", "AllowImages": kind == "Picture", "PositiveOption": "Yes", "NegativeOption": "No"}
        if answered:
            ia["AnswerDateTime"] = start
            ia["Compliant"] = compliant
            if compliant == "NotCompliant": ia["Comment"] = "Needs follow-up before next shift"
        if kind == "Text":
            ia["AnswerText"] = ("1243" if title == "Hour meter reading" else "No issues") if answered else None
            ia["IsNumberValueRequired"] = title == "Hour meter reading"
            if answered and title == "Hour meter reading": ia["AnswerTextNumbersOnly"] = 1243
        add(iq, "Checklist_Instance.Instance" + QT[kind], ia, {"InstanceQuestion_InstanceChecklist": ref, "InstanceQuestion_Question": qref})
        for oi, (oref, ot) in enumerate(orefs):
            io = "%s_o%d" % (iq, oi)
            if kind == "Checkbox":
                add(io, "Checklist_Instance.InstanceCheckboxOption", {"UUID": U(io), "Title": ot, "SequenceNumber": oi + 1},
                    {"InstanceCheckboxOption_InstanceCheckboxQuestion": iq, **({"InstanceCheckboxOption_InstanceCheckboxQuestion_Set": iq} if answered else {})})
            else:
                add(io, "Checklist_Instance.InstanceMultipleChoiceOption", {"UUID": U(io), "Title": ot, "SequenceNumber": oi + 1, "CorrectAnswer": oi == len(orefs) - 1},
                    {"InstanceMultipleChoiceOption_InstanceMultipleChoiceQuestion": iq, **({"InstanceMultipleChoiceOption_InstanceMultipleChoiceQuestion_Set": iq} if answered and oi == len(orefs) - 1 else {})})

print(json.dumps({"objects": O}, indent=1))
