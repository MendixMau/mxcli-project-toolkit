import json, re

RUBRIC = "/tmp/abproj/analysis/source-sufficiency.json"

# Per-chapter judgement, built by reading the full cleaned corpus dump
# (analysis/_corpus-dump-clean.txt) chapter by chapter.
CHAPTERS = {
    "01-home.html": (["data_migration"], [],
        "reference-only landing page; footer notes the app 'replaces a spreadsheet-based booking process'"),
    "02-about-the-port-authority.html": (["domain"], ["Terminal"], ""),
    "03-release-notes.html": ([], [], ""),
    "04-vision-and-scope.html": (["actors", "processes"], [],
        "Pilotage and tug scheduling are out of scope and remain in the existing marine operations system."),
    "05-stakeholders-and-roles.html": (["actors", "security_model"],
        ["ShippingAgent", "BerthOfficer", "HarbourMaster", "Inspector"], ""),
    "06-news-and-events.html": ([], [], ""),
    "07-domain-overview.html": (["domain"],
        ["Vessel", "ShippingAgent", "Berth", "BookingRequest", "ApprovalDecision", "Invoice",
         "Inspection", "Terminal", "AuditEntry"], ""),
    "08-booking-lifecycle.html": (["processes", "rules"], ["BookingRequest"], ""),
    "09-booking-request-form.html": (["rules", "ui"], ["BookingRequest", "Vessel"], ""),
    "10-cancellation-and-changes.html": (["processes", "rules"], ["BookingRequest"], ""),
    "11-agent-onboarding.html": (["processes", "rules", "actors"], ["ShippingAgent", "Invoice"], ""),
    "12-berth-master-data.html": (["domain"], ["Berth", "Terminal", "Tariff"], ""),
    "13-berth-allocation-rules.html": (["rules", "security_model"], ["Berth", "Vessel"], ""),
    "14-vessel-registry.html": (["domain", "rules"], ["Vessel"], ""),
    "15-officer-review-process.html": (["processes", "rules"], ["BookingRequest"], ""),
    "16-approval-decisions.html": (["processes", "rules", "security_model"], ["ApprovalDecision"], ""),
    "17-notifications.html": (["processes"], ["BookingRequest"], ""),
    "18-tariff-structure.html": (["rules", "domain"], ["Tariff"], ""),
    "19-tariffs-cancellation-fees.html": (["rules"], ["Tariff", "BookingRequest"], ""),
    "20-invoicing.html": (["processes", "rules"], ["Invoice"], ""),
    "21-officer-review-screen.html": (["ui"], ["BookingRequest", "Berth", "Vessel"], ""),
    "22-inspection-scheduling.html": (["processes", "rules"], ["Inspection", "BookingRequest"], ""),
    "23-inspection-checklist.html": (["domain", "rules"], ["Inspection", "InspectionItem"], ""),
    "24-inspection-outcomes.html": (["rules", "processes"], ["Inspection", "BookingRequest"], ""),
    "25-departure-clearance.html": (["processes", "rules"], ["BookingRequest", "Inspection"], ""),
    "26-audit-and-compliance.html": (["domain", "nfr"], ["AuditEntry"], ""),
    "27-privacy-and-cookies.html": (["nfr"], [], ""),
    "28-navigation-and-screens.html": (["ui"], [], ""),
    "29-booking-board-screen.html": (["ui"], [], ""),
    "30-my-bookings-screen.html": (["ui"], [], ""),
    "31-inspection-calendar-screen.html": (["ui"], [], ""),
    "32-reporting.html": (["processes", "ui"], [], ""),
    "33-integration-ais-feed.html": (["integrations", "rules"], ["BookingRequest"], ""),
    "34-contact-and-support.html": ([], [], ""),
    "35-security-and-access.html": (["security_model"], [], ""),
    "36-appendix-data-dictionary.html": (["domain"],
        ["ApprovalDecision", "Tariff", "Invoice", "Inspection", "InspectionItem", "AuditEntry"], ""),
}

SUPPORT_DOCS = {
    "glossary.md": (["domain"], ["Vessel", "ShippingAgent", "Terminal", "Berth", "BookingRequest",
        "ApprovalDecision", "Tariff", "Invoice", "Inspection", "InspectionItem", "AuditEntry"], ""),
    "roles.md": (["actors", "security_model"],
        ["ShippingAgent", "BerthOfficer", "HarbourMaster", "Inspector"],
        "Every user has exactly one role."),
    "decisions-log.md": (["rules", "processes"], [],
        "ADR-004 booking references never reused; ADR-006 invoice due 30 days after issue, Overdue the day after."),
    "workshop-notes.md": (["rules", "ui"], ["BookingRequest"],
        "Attachment size limit explicitly 'not decided' (Session 2); review screen must show last five bookings of same vessel (Session 3, not yet in any chapter)."),
}

with open(RUBRIC) as f:
    doc = json.load(f)

n_filled = 0
for row in doc["inventory"]:
    rel = row["rel"]
    if rel in CHAPTERS:
        answers, components, scope = CHAPTERS[rel]
        row["kind"] = "docs"
        row["answers"] = answers
        row["statedScope"] = scope
        row["components"] = components
        n_filled += 1
    elif rel in SUPPORT_DOCS:
        answers, components, scope = SUPPORT_DOCS[rel]
        row["kind"] = "docs"
        row["answers"] = answers
        row["statedScope"] = scope
        row["components"] = components
        n_filled += 1
    elif rel.endswith("fig-booking-form-validation.png"):
        row["kind"] = "ui"
        row["answers"] = ["rules", "ui"]
        row["statedScope"] = ""
        row["components"] = ["BookingRequest", "Vessel"]
        n_filled += 1
    elif rel.endswith("img-02.png"):
        row["kind"] = "unknown"
        row["answers"] = []
        row["statedScope"] = "decorative illustration (quay wall and mooring bollards), no functional content"
        row["components"] = []
        n_filled += 1
    elif rel.endswith("img-01.jpg"):
        row["kind"] = "unknown"
        row["answers"] = []
        row["statedScope"] = "decorative stock illustration ('Container terminal at dawn'), reused on every chapter, no functional content"
        row["components"] = []
        n_filled += 1
    elif rel.endswith("site.css") or rel.endswith("print.css") or rel.endswith("app.js") or rel.endswith("font-harbour-sans.woff"):
        row["kind"] = "unknown"
        row["answers"] = []
        row["statedScope"] = "documentation-portal site chrome (stylesheet/script/font), not application content"
        row["components"] = []
        n_filled += 1
    else:
        print("UNHANDLED ROW:", rel)

with open(RUBRIC, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")

print(f"filled {n_filled} of {len(doc['inventory'])} rows")
