import json
import re

ENT_PATH = "/tmp/abproj/analysis/harbour-berth-booking/knowledge-base/share/entities.json"
BRD_DIR = "/tmp/abproj/analysis/harbour-berth-booking/knowledge-base/brd"
KB_MD = "KB_HarbourBerthBooking_Functional.md"

entities = {e["entity"]: e for e in json.load(open(ENT_PATH))["entities"]}
all_rels = json.load(open(ENT_PATH))["relationships"]


def mx_attr(a):
    t = a["type"]
    out = {"name": a["name"], "mandatory": a["required"]}
    if t.startswith("Text, up to"):
        m = re.search(r"(\d+)", t)
        out["type"] = "String"
        out["length"] = int(m.group(1))
    elif t == "Decimal number":
        out["type"] = "Decimal"
    elif t == "Whole number":
        out["type"] = "Integer"
    elif t == "Yes/No":
        out["type"] = "Boolean"
    elif t == "Date and time":
        out["type"] = "DateTime"
    elif t == "Date":
        out["type"] = "Date"
    elif t.startswith("One of:"):
        out["type"] = "Enumeration"
        out["values"] = [v.strip() for v in t[len("One of:"):].split(",")]
    else:
        out["type"] = "String"
    return out


def domain_entities(names, module):
    out = []
    for name in names:
        e = entities[name]
        assocs = []
        for r in all_rels:
            if r["from"] == name:
                assocs.append({"name": r["name"], "target": r["to"],
                                "cardinality": r["cardinality"], "owner": name})
        out.append({
            "name": name,
            "module": module,
            "persistent": True,
            "attributes": [mx_attr(a) for a in e["attributes"]],
            "auditFields": ["CreatedOn", "CreatedBy", "ModifiedOn", "ModifiedBy"],
            "associations": assocs,
        })
    return out


BRDS = [
    {
        "id": "F001", "title": "Master Data: Terminals, Berths, Vessels & Shipping Agents",
        "modules": ["MasterData"], "entityNames": ["Terminal", "Berth", "Vessel", "ShippingAgent"],
        "actors": ["ShippingAgent", "BerthOfficer", "HarbourMaster"],
        "useCases": [
            {"id": "UC001", "title": "Register a shipping agent", "actors": ["BerthOfficer"],
             "preconditions": ["Officer is logged in"],
             "postconditions": ["Agent record exists with IsSuspended = No"],
             "mainFlow": ["1. Officer enters company name, licence number, contact e-mail",
                          "2. System activates the agent (ch11 SS7.1)"],
             "screens": [], "mdlRefs": ["MasterData"]},
            {"id": "UC002", "title": "Auto-suspend an agent with overdue invoices", "actors": ["ShippingAgent"],
             "preconditions": ["Agent has 3 or more Overdue invoices"],
             "postconditions": ["Agent.IsSuspended = Yes; agent cannot submit new requests"],
             "mainFlow": ["1. Scheduled/triggered check counts the agent's Overdue invoices",
                          "2. On reaching 3, system sets IsSuspended = Yes (ch11 SS7.2)",
                          "3. Already-Approved bookings remain valid"],
             "screens": [], "mdlRefs": ["MasterData"]},
            {"id": "UC003", "title": "Reactivate a suspended agent", "actors": ["HarbourMaster"],
             "preconditions": ["Agent.IsSuspended = Yes"],
             "postconditions": ["Agent.IsSuspended = No"],
             "mainFlow": ["1. Harbour Master reactivates the agent — no self-service reactivation exists (ch11 SS7.2)"],
             "screens": [], "mdlRefs": ["MasterData"]},
            {"id": "UC004", "title": "Maintain berth and terminal master data", "actors": ["HarbourMaster"],
             "preconditions": [], "postconditions": ["Berth/Terminal records reflect current capacity"],
             "mainFlow": ["1. Harbour Master records each berth's code, name, max length, max draught, "
                          "shore power flag and status (ch12 SS8.1)"],
             "screens": [], "mdlRefs": ["MasterData"]},
            {"id": "UC005", "title": "Register a vessel", "actors": ["ShippingAgent"],
             "preconditions": [], "postconditions": ["Vessel exists, unique by IMONumber"],
             "mainFlow": ["1. Agent (or officer) records IMO number, name, dimensions, type",
                          "2. IMO number must be unique across the registry (ch14 SS10.1) and exactly 7 "
                          "digits (image-only rule, fig-booking-form-validation.png — not stated in any "
                          "text chapter)"],
             "screens": [], "mdlRefs": ["MasterData"]},
        ],
        "microflows": [
            {"name": "ACT_ShippingAgent_Activate", "module": "MasterData",
             "purpose": "Activates a newly registered agent.", "pattern": "validate-then-save",
             "params": [{"name": "Agent", "type": "ShippingAgent"}], "returns": "ShippingAgent",
             "validations": ["CompanyName not blank", "LicenceNumber not blank"]},
            {"name": "SUB_ShippingAgent_CheckOverdueInvoices", "module": "MasterData",
             "purpose": "Counts an agent's Overdue invoices and suspends at 3+.", "pattern": "validate-then-save",
             "params": [{"name": "Agent", "type": "ShippingAgent"}], "returns": "Boolean",
             "calls": ["ACT_ShippingAgent_Suspend"]},
            {"name": "ACT_ShippingAgent_Reactivate", "module": "MasterData",
             "purpose": "Harbour Master-only reactivation of a suspended agent.", "pattern": "validate-then-save",
             "params": [{"name": "Agent", "type": "ShippingAgent"}], "returns": "ShippingAgent"},
            {"name": "VAL_Vessel_IMONumber", "module": "MasterData",
             "purpose": "Validates IMO number is exactly 7 digits and unique (image-only rule).",
             "pattern": "validate-then-save",
             "params": [{"name": "Vessel", "type": "Vessel"}], "returns": "Boolean",
             "validations": ["IMONumber matches ^[0-9]{7}$", "IMONumber unique across Vessel"]},
        ],
        "pages": [
            {"name": "ShippingAgent_NewEdit", "module": "MasterData", "purpose": "Register/edit an agent",
             "dataContext": "ShippingAgent", "sections": ["AgentDetails"], "actions": ["ACT_ShippingAgent_Activate"]},
            {"name": "Berth_NewEdit", "module": "MasterData", "purpose": "Maintain berth master data",
             "dataContext": "Berth", "sections": ["BerthDetails"], "actions": []},
            {"name": "Vessel_NewEdit", "module": "MasterData", "purpose": "Register/edit a vessel",
             "dataContext": "Vessel", "sections": ["VesselDetails"], "actions": ["VAL_Vessel_IMONumber"]},
        ],
        "integrations": [],
        "openQuestions": [
            {"id": "D4", "question": "Licence/security constraints on storing this source, and SME availability",
             "status": "Open"},
        ],
    },
    {
        "id": "F002", "title": "Booking Lifecycle & Request",
        "modules": ["BookingManagement"], "entityNames": ["BookingRequest"],
        "actors": ["ShippingAgent", "BerthOfficer"],
        "useCases": [
            {"id": "UC101", "title": "Save a booking request as Draft", "actors": ["ShippingAgent"],
             "preconditions": [], "postconditions": ["BookingRequest.Status = Draft; invisible to officers"],
             "mainFlow": ["1. Agent fills vessel, berth, ETA, ETD, cargo class",
                          "2. Agent saves without submitting (ch08 SS4.1)"],
             "screens": ["BookingRequest_NewEdit"], "mdlRefs": ["BookingManagement"]},
            {"id": "UC102", "title": "Submit a booking request", "actors": ["ShippingAgent"],
             "preconditions": ["Agent is not suspended", "48h <= (ETA - now) <= 90 days (ch08 SS4.5)"],
             "postconditions": ["Reference assigned in format HB-YYYY-NNNNN (ch08 SS4.2), Status = Submitted"],
             "mainFlow": ["1. Agent completes mandatory fields (vessel, berth, ETA, ETD, cargo class)",
                          "2. System validates ETD > ETA and stay <= 30 days (ch09 SS5.2)",
                          "3. System validates IMO number is exactly 7 digits (image-only rule)",
                          "4. System assigns a permanent reference (never reused, ADR-004) and sets Status = Submitted"],
             "screens": ["BookingRequest_NewEdit"], "mdlRefs": ["BookingManagement"]},
            {"id": "UC103", "title": "Fast-track auto-approval", "actors": ["ShippingAgent"],
             "preconditions": ["Requested berth free for the whole stay", "Vessel LOA < 120m"],
             "postconditions": ["Status = Approved without officer review (ch08 SS4.4)"],
             "mainFlow": ["1. On submission the system checks the fast-track condition",
                          "2. If met, Status transitions directly to Approved"],
             "screens": [], "mdlRefs": ["BookingManagement"]},
            {"id": "UC104", "title": "Edit a submitted request", "actors": ["ShippingAgent"],
             "preconditions": ["Status = Submitted and not yet opened for review"],
             "postconditions": ["Request updated; locked once an officer opens it (ch10 SS6.1)"],
             "mainFlow": ["1. Agent edits mandatory fields", "2. System re-validates all rules"],
             "screens": ["BookingRequest_NewEdit"], "mdlRefs": ["BookingManagement"]},
            {"id": "UC105", "title": "Cancel a booking request", "actors": ["ShippingAgent"],
             "preconditions": ["Status != Completed"],
             "postconditions": ["Status = Cancelled; reference retained for audit (ADR-004)"],
             "mainFlow": ["1. Agent cancels", "2. Free of charge if >=24h before ETA; 50% berth fee if within 72h of ETA (ch10 SS6.2, ch19 SS15.2)"],
             "screens": ["BookingRequest_NewEdit"], "mdlRefs": ["BookingManagement"]},
        ],
        "microflows": [
            {"name": "ACT_BookingRequest_SaveDraft", "module": "BookingManagement",
             "purpose": "Saves a request as Draft.", "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "BookingRequest"},
            {"name": "ACT_BookingRequest_Submit", "module": "BookingManagement",
             "purpose": "Validates and submits a booking request, assigning its reference.",
             "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "BookingRequest",
             "calls": ["GEN_BookingRequest_Reference", "VAL_BookingRequest_Timing", "SUB_BookingRequest_FastTrackCheck"],
             "validations": ["ETD > ETA", "stay <= 30 days", "48h <= ETA-now <= 90 days",
                              "Vessel.IMONumber matches ^[0-9]{7}$"]},
            {"name": "GEN_BookingRequest_Reference", "module": "BookingManagement",
             "purpose": "Generates the permanent HB-YYYY-NNNNN reference.", "pattern": "sub-routine",
             "params": [], "returns": "String"},
            {"name": "SUB_BookingRequest_FastTrackCheck", "module": "BookingManagement",
             "purpose": "Checks berth-free + vessel<120m fast-track condition.", "pattern": "sub-routine",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "Boolean"},
            {"name": "ACT_BookingRequest_Cancel", "module": "BookingManagement",
             "purpose": "Cancels a request and applies the late-cancellation fee where applicable.",
             "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "BookingRequest",
             "validations": ["Status != Completed"]},
        ],
        "pages": [
            {"name": "BookingRequest_NewEdit", "module": "BookingManagement",
             "purpose": "Booking request form (mandatory fields + validation, incl. IMO digit check)",
             "dataContext": "BookingRequest", "sections": ["VesselAndBerth", "Dates", "CargoAndOptions"],
             "actions": ["ACT_BookingRequest_SaveDraft", "ACT_BookingRequest_Submit"]},
        ],
        "integrations": [],
        "openQuestions": [
            {"id": "D1", "question": "Cargo-manifest PDF attachment size limit", "status": "Open"},
        ],
    },
    {
        "id": "F003", "title": "Officer Review, Approval & Security",
        "modules": ["OfficerReview"], "entityNames": ["ApprovalDecision"],
        "actors": ["BerthOfficer", "HarbourMaster", "ShippingAgent"],
        "useCases": [
            {"id": "UC201", "title": "Work the Booking Board queue", "actors": ["BerthOfficer"],
             "preconditions": [], "postconditions": [],
             "mainFlow": ["1. Officer opens Booking Board", "2. Lists Submitted/Under Review requests ordered by ETA (ch15 SS11.1)",
                          "3. Filterable by terminal, status, ETA date range (ch29 SS24.1)"],
             "screens": ["BookingBoard_Overview"], "mdlRefs": ["OfficerReview"]},
            {"id": "UC202", "title": "Review a booking request", "actors": ["BerthOfficer"],
             "preconditions": ["Status = Submitted"],
             "postconditions": ["Status = UnderReview, reviewing officer recorded (ch15 SS11.2)"],
             "mainFlow": ["1. Officer opens the request for review", "2. Request is locked from agent edits (ch10 SS6.1)",
                          "3. Screen shows vessel dimensions vs berth limits, exceedance highlighted red (ch21 SS17.1)",
                          "4. Screen shows the last 5 bookings of the same vessel (workshop-notes.md Session 3, D2 — not in any numbered chapter)"],
             "screens": ["OfficerReview_Screen"], "mdlRefs": ["OfficerReview"]},
            {"id": "UC203", "title": "Record an approval decision", "actors": ["BerthOfficer"],
             "preconditions": ["Status = UnderReview",
                                "if CargoClass = DangerousGoods, an inspection must already be scheduled (ch22 SS18.2)"],
             "postconditions": ["ApprovalDecision created with outcome"],
             "mainFlow": ["1. Officer records Approved, Rejected, or Returned for Information, with a reason (ch16 SS12.1)",
                          "2. Returned-for-Information goes back to the agent, who may amend and resubmit once (ch16 SS12.2)"],
             "screens": ["OfficerReview_Screen"], "mdlRefs": ["OfficerReview"]},
            {"id": "UC204", "title": "Override a rejected decision", "actors": ["HarbourMaster"],
             "preconditions": ["Latest ApprovalDecision.Outcome = Rejected"],
             "postconditions": ["Override recorded with reason, IsOverride = Yes (ch16 SS12.3)"],
             "mainFlow": ["1. Harbour Master overrides the rejection with a reason"],
             "screens": ["OfficerReview_Screen"], "mdlRefs": ["OfficerReview"]},
            {"id": "UC205", "title": "Scope data access by company", "actors": ["ShippingAgent"],
             "preconditions": [], "postconditions": ["Agent sees only own company's bookings/invoices/inspections (ch35 SS29.1)"],
             "mainFlow": ["1. Every list/detail microflow filters by the current user's ShippingAgent"],
             "screens": [], "mdlRefs": ["OfficerReview"]},
        ],
        "microflows": [
            {"name": "ACT_BookingRequest_OpenForReview", "module": "OfficerReview",
             "purpose": "Locks a Submitted request and moves it to UnderReview.", "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "BookingRequest"},
            {"name": "ACT_ApprovalDecision_Record", "module": "OfficerReview",
             "purpose": "Records an officer's outcome and reason; gates on dangerous-goods inspection.",
             "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}, {"name": "Outcome", "type": "String"},
                        {"name": "Reason", "type": "String"}], "returns": "ApprovalDecision",
             "validations": ["CargoClass != DangerousGoods OR an Inspection exists for this Booking"]},
            {"name": "ACT_ApprovalDecision_Override", "module": "OfficerReview",
             "purpose": "Harbour Master-only override of a Rejected decision.", "pattern": "validate-then-save",
             "params": [{"name": "Decision", "type": "ApprovalDecision"}, {"name": "Reason", "type": "String"}],
             "returns": "ApprovalDecision"},
            {"name": "GET_BookingBoard_Queue", "module": "OfficerReview",
             "purpose": "Retrieves Submitted/UnderReview requests ordered by ETA, filterable.",
             "pattern": "retrieve", "params": [], "returns": "List<BookingRequest>"},
        ],
        "pages": [
            {"name": "BookingBoard_Overview", "module": "OfficerReview",
             "purpose": "Officer queue: Submitted/Under Review by ETA, filter by terminal/status/date",
             "dataContext": "BookingRequest (list)", "sections": ["Filters", "Queue"], "actions": []},
            {"name": "OfficerReview_Screen", "module": "OfficerReview",
             "purpose": "Decision panel: dimensions vs limits (exceedance in red), last 5 vessel bookings, decision",
             "dataContext": "BookingRequest", "sections": ["VesselVsBerth", "RecentBookings", "Decision"],
             "actions": ["ACT_ApprovalDecision_Record", "ACT_ApprovalDecision_Override"]},
        ],
        "integrations": [],
        "openQuestions": [
            {"id": "D2", "question": "Officer review screen must show the last five bookings of the same vessel",
             "status": "Open"},
        ],
    },
    {
        "id": "F004", "title": "Tariffs & Invoicing",
        "modules": ["TariffsInvoicing"], "entityNames": ["Tariff", "Invoice"],
        "actors": ["HarbourMaster", "BerthOfficer", "ShippingAgent"],
        "useCases": [
            {"id": "UC301", "title": "Maintain a tariff rate card", "actors": ["HarbourMaster"],
             "preconditions": [], "postconditions": [],
             "mainFlow": ["1. Harbour Master defines rate per metre per day, currency, validity period, "
                          "surcharge percent, per terminal (ch18 SS14.1)"],
             "screens": ["Tariff_NewEdit"], "mdlRefs": ["TariffsInvoicing"]},
            {"id": "UC302", "title": "Calculate a berth fee", "actors": ["BerthOfficer"],
             "preconditions": ["Booking Completed"],
             "postconditions": ["Fee computed"],
             "mainFlow": ["1. Fee = vessel length x days-alongside x tariff rate; days round up, min 1 (ch18 SS14.2)",
                          "2. VAT 21% added (ch18 SS14.3)",
                          "3. Shore power flat 250/day added if offered and requested (ch18 SS14.4)",
                          "4. Late-arrival surcharge 15% if >2h after ETA (ch19 SS15.1), waivable by officer for vessels <80m (ch24 SS20.3), or by Harbour Master otherwise (ch13 SS9.3)"],
             "screens": [], "mdlRefs": ["TariffsInvoicing"]},
            {"id": "UC303", "title": "Generate an invoice", "actors": ["ShippingAgent"],
             "preconditions": ["BookingRequest.Status = Completed"],
             "postconditions": ["Invoice created automatically (ch20 SS16.1); DueOn = IssuedOn + 30 days (ADR-006)"],
             "mainFlow": ["1. System generates the invoice on Completed", "2. Status becomes Overdue the day after DueOn if unpaid (ADR-006)"],
             "screens": [], "mdlRefs": ["TariffsInvoicing"]},
            {"id": "UC304", "title": "Mark an invoice Paid or Void", "actors": ["HarbourMaster"],
             "preconditions": ["Invoice.Status != Paid"],
             "postconditions": ["Invoice.Status updated; a Paid invoice cannot be edited (ch20 SS16.3)"],
             "mainFlow": ["1. Harbour Master marks the invoice Paid or Void"],
             "screens": ["Invoice_Overview"], "mdlRefs": ["TariffsInvoicing"]},
        ],
        "microflows": [
            {"name": "CAL_BookingRequest_BerthFee", "module": "TariffsInvoicing",
             "purpose": "Computes the berth fee (length x days x rate, VAT, shore power, surcharges).",
             "pattern": "calculation",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "Decimal"},
            {"name": "ACT_Invoice_GenerateOnCompleted", "module": "TariffsInvoicing",
             "purpose": "Auto-creates an invoice when a booking is marked Completed.", "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "Invoice",
             "calls": ["CAL_BookingRequest_BerthFee"]},
            {"name": "ACT_Invoice_SetStatus", "module": "TariffsInvoicing",
             "purpose": "Harbour Master-only Paid/Void transition; blocks edits once Paid.", "pattern": "validate-then-save",
             "params": [{"name": "Invoice", "type": "Invoice"}, {"name": "NewStatus", "type": "String"}],
             "returns": "Invoice", "validations": ["current Status != Paid before editing"]},
            {"name": "SUB_Invoice_MarkOverdue", "module": "TariffsInvoicing",
             "purpose": "Scheduled: flips Issued invoices to Overdue the day after DueOn.", "pattern": "scheduled",
             "params": [], "returns": "Integer"},
        ],
        "pages": [
            {"name": "Tariff_NewEdit", "module": "TariffsInvoicing", "purpose": "Maintain a tariff rate card",
             "dataContext": "Tariff", "sections": ["RateDetails"], "actions": []},
            {"name": "Invoice_Overview", "module": "TariffsInvoicing", "purpose": "List/manage invoices",
             "dataContext": "Invoice (list)", "sections": ["InvoiceList"], "actions": ["ACT_Invoice_SetStatus"]},
        ],
        "integrations": [],
        "openQuestions": [],
    },
    {
        "id": "F005", "title": "Inspections & Departure Clearance",
        "modules": ["Inspections"], "entityNames": ["Inspection", "InspectionItem"],
        "actors": ["Inspector", "BerthOfficer"],
        "useCases": [
            {"id": "UC401", "title": "Schedule an inspection", "actors": ["Inspector"],
             "preconditions": ["BookingRequest.Status = Approved"],
             "postconditions": ["Inspection created; agent notified of the time slot (ch22 SS18.1)"],
             "mainFlow": ["1. Inspector schedules against an Approved booking",
                          "2. If CargoClass = DangerousGoods, this is required before approval can be granted (ch22 SS18.2)"],
             "screens": ["InspectionCalendar_Screen"], "mdlRefs": ["Inspections"]},
            {"id": "UC402", "title": "Record a checklist outcome", "actors": ["Inspector"],
             "preconditions": [], "postconditions": ["Each item has compliant flag, severity, optional note (ch23 SS19.2)"],
             "mainFlow": ["1. Inspector records each checklist item across Safety/Environmental/Documentation/Security (ch23 SS19.1)",
                          "2. Inspection.Outcome = Failed if any High-severity item is non-compliant (ch23 SS19.3)"],
             "screens": [], "mdlRefs": ["Inspections"]},
            {"id": "UC403", "title": "Grant departure clearance", "actors": ["BerthOfficer"],
             "preconditions": ["Every inspection on the booking is Passed or Deferred (ch25 SS21.1)"],
             "postconditions": ["Clearance granted"],
             "mainFlow": ["1. A Failed inspection blocks clearance until a follow-up inspection Passes (ch24 SS20.1)",
                          "2. Officer grants clearance once all inspections are Passed/Deferred"],
             "screens": [], "mdlRefs": ["Inspections"]},
        ],
        "microflows": [
            {"name": "ACT_Inspection_Schedule", "module": "Inspections",
             "purpose": "Schedules an inspection against an Approved booking; notifies the agent.",
             "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "Inspection",
             "validations": ["Booking.Status = Approved"]},
            {"name": "ACT_InspectionItem_Record", "module": "Inspections",
             "purpose": "Records one checklist item's compliance/severity/note.", "pattern": "validate-then-save",
             "params": [{"name": "Item", "type": "InspectionItem"}], "returns": "InspectionItem"},
            {"name": "SUB_Inspection_DeriveOutcome", "module": "Inspections",
             "purpose": "Sets Outcome = Failed if any High-severity item is non-compliant.", "pattern": "sub-routine",
             "params": [{"name": "Inspection", "type": "Inspection"}], "returns": "String"},
            {"name": "ACT_BookingRequest_GrantClearance", "module": "Inspections",
             "purpose": "Grants departure clearance once every inspection is Passed or Deferred.",
             "pattern": "validate-then-save",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "BookingRequest",
             "validations": ["all Inspections for Booking have Outcome in {Passed, Deferred}"]},
        ],
        "pages": [
            {"name": "InspectionCalendar_Screen", "module": "Inspections",
             "purpose": "Inspections per day/inspector, drag-and-drop reschedule (ch31 SS26.1)",
             "dataContext": "Inspection (list)", "sections": ["Calendar"], "actions": ["ACT_Inspection_Schedule"]},
        ],
        "integrations": [],
        "openQuestions": [],
    },
    {
        "id": "F006", "title": "Audit, Notifications, Screens, Reporting & AIS Integration",
        "modules": ["AuditNotifications"], "entityNames": ["AuditEntry"],
        "actors": ["ShippingAgent", "BerthOfficer", "HarbourMaster", "Inspector"],
        "useCases": [
            {"id": "UC501", "title": "Write an audit entry on every status change", "actors": [],
             "preconditions": [], "postconditions": ["AuditEntry created with actor/timestamp/action (ch26 SS22.1)"],
             "mainFlow": ["1. Every status-changing microflow across F002-F005 also creates an AuditEntry, "
                          "co-located with the change rather than a later script"],
             "screens": [], "mdlRefs": ["AuditNotifications"]},
            {"id": "UC502", "title": "Notify an agent of a status change", "actors": ["ShippingAgent"],
             "preconditions": [], "postconditions": ["E-mail sent including the booking reference (ch17 SS13.1, workshop-notes.md)"],
             "mainFlow": ["1. On any BookingRequest.Status change, e-mail the owning agent"],
             "screens": [], "mdlRefs": ["AuditNotifications"]},
            {"id": "UC503", "title": "Send the officer daily digest", "actors": ["BerthOfficer"],
             "preconditions": [], "postconditions": ["Digest sent at 06:00 (ch17 SS13.2)"],
             "mainFlow": ["1. Scheduled event at 06:00 lists requests with ETA within the next 48 hours"],
             "screens": [], "mdlRefs": ["AuditNotifications"]},
            {"id": "UC504", "title": "View My Bookings", "actors": ["ShippingAgent"],
             "preconditions": [], "postconditions": [],
             "mainFlow": ["1. Agent sees own requests only, Drafts listed first (ch30 SS25.1)"],
             "screens": ["MyBookings_Screen"], "mdlRefs": ["AuditNotifications"]},
            {"id": "UC505", "title": "Export the monthly berth-occupancy report", "actors": ["HarbourMaster"],
             "preconditions": [], "postconditions": ["CSV produced per terminal (ch32 SS27.1)"],
             "mainFlow": ["1. Harbour Master exports the report as CSV"],
             "screens": ["Reporting_Screen"], "mdlRefs": ["AuditNotifications"]},
            {"id": "UC506", "title": "Auto-flag a booking Arrived from the AIS feed", "actors": [],
             "preconditions": [], "postconditions": ["BookingRequest flagged Arrived (ch33 SS28.2)"],
             "mainFlow": ["1. AIS feed polled every 5 minutes",
                          "2. Vessel entering the port geofence flags the matching booking Arrived",
                          "3. No endpoint/auth/failure-mode is specified anywhere in the corpus — stub with "
                          "a manual 'mark Arrived' fallback, per triage.md's missing-dependency policy (D3)"],
             "screens": [], "mdlRefs": ["AuditNotifications"]},
        ],
        "microflows": [
            {"name": "SUB_AuditEntry_Write", "module": "AuditNotifications",
             "purpose": "Co-located audit-trail write, called from every status-change microflow.",
             "pattern": "sub-routine",
             "params": [{"name": "Entity", "type": "Object"}, {"name": "Action", "type": "String"}],
             "returns": "AuditEntry"},
            {"name": "ACT_BookingRequest_NotifyAgent", "module": "AuditNotifications",
             "purpose": "Sends the status-change e-mail including the booking reference.", "pattern": "notify",
             "params": [{"name": "Booking", "type": "BookingRequest"}], "returns": "Boolean"},
            {"name": "SUB_BerthOfficer_DailyDigest", "module": "AuditNotifications",
             "purpose": "Scheduled 06:00 digest of requests with ETA within 48h.", "pattern": "scheduled",
             "params": [], "returns": "Integer"},
            {"name": "STUB_AISFeed_PollPositions", "module": "AuditNotifications",
             "purpose": "Stub for the AIS feed poll; real contract unspecified in the corpus (D3).",
             "pattern": "integration-stub",
             "params": [], "returns": "Integer"},
            {"name": "GEN_Reporting_BerthOccupancyCsv", "module": "AuditNotifications",
             "purpose": "Generates the monthly per-terminal berth-occupancy CSV.", "pattern": "retrieve",
             "params": [], "returns": "FileDocument"},
        ],
        "pages": [
            {"name": "MyBookings_Screen", "module": "AuditNotifications",
             "purpose": "Agent's own requests, Draft first (ch30)", "dataContext": "BookingRequest (list)",
             "sections": ["OwnBookings"], "actions": []},
            {"name": "Reporting_Screen", "module": "AuditNotifications",
             "purpose": "Monthly berth-occupancy CSV export (ch32)", "dataContext": "n/a",
             "sections": ["ReportFilters"], "actions": ["GEN_Reporting_BerthOccupancyCsv"]},
        ],
        "integrations": [
            {"name": "AIS position feed", "type": "REST/unspecified", "stubName": "STUB_AISFeed_PollPositions",
             "stubBehaviour": "Poll returns no positions; a manual 'mark Arrived' action on the booking is "
                               "the fallback until the real feed contract is confirmed.",
             "realTarget": "AIS feed (external, port authority infrastructure — endpoint/auth not documented)",
             "apiDoc": KB_MD},
        ],
        "openQuestions": [
            {"id": "D3", "question": "AIS feed integration contract (endpoint, auth, failure/retry behaviour)",
             "status": "Open"},
            {"id": "D5", "question": "Data-migration source (the spreadsheet process being replaced) — no schema/sample/volume given",
             "status": "Open"},
        ],
    },
]

for b in BRDS:
    out = {
        "id": b["id"], "title": b["title"], "modules": b["modules"], "actors": b["actors"],
        "useCases": b["useCases"],
        "domainEntities": domain_entities(b["entityNames"], b["modules"][0]),
        "microflows": b["microflows"],
        "pages": b["pages"],
        "integrations": b["integrations"],
        "openQuestions": b["openQuestions"],
        "sourceKB": [KB_MD],
        "provenance": "documents",
    }
    fname = f"{b['id']}-{re.sub(r'[^a-z0-9]+', '-', b['title'].lower()).strip('-')}.brd.json"
    with open(f"{BRD_DIR}/{fname}", "w") as f:
        json.dump(out, f, indent=2)
    print(fname)

index = {
    "generated": "2026-09-09",
    "brds": [
        {"id": b["id"], "title": b["title"],
         "file": f"{b['id']}-{re.sub(r'[^a-z0-9]+', '-', b['title'].lower()).strip('-')}.brd.json",
         "status": "complete"}
        for b in BRDS
    ],
}
with open(f"{BRD_DIR}/index.json", "w") as f:
    json.dump(index, f, indent=2)
print("index.json")
