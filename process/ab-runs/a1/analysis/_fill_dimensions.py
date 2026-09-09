import json

RUBRIC = "/tmp/abproj/analysis/source-sufficiency.json"

DIMS = {
    "actors": ("specified",
        "roles.md + ch05 stakeholders-and-roles: four fixed roles (Shipping Agent, Berth Officer, "
        "Harbour Master, Inspector), one role per user; ch05 SS2.3 states Harbour Master authority = "
        "Berth Officer's actions plus decision overrides, agent reactivation, tariff maintenance.",
        "none — actor set and authority boundary can be modelled directly."),
    "domain": ("verified",
        "ch07 domain-overview + ch36 appendix data dictionary give full attribute/type/required "
        "tables for all 11 entities (Vessel, ShippingAgent, Terminal, Berth, BookingRequest, "
        "ApprovalDecision, Tariff, Invoice, Inspection, InspectionItem, AuditEntry) plus explicit "
        "relationships (cardinality named per association); cross-checked against glossary.md, "
        "which agrees.",
        "none — domain model can be built directly from the spec."),
    "processes": ("specified",
        "ch08 booking lifecycle status model (Draft to Submitted to UnderReview to "
        "Approved/Rejected/Cancelled to Completed), ch15 officer review queue, ch22-25 "
        "inspection-to-departure-clearance chain, ch20 invoicing trigger, ch33 AIS Arrived trigger "
        "all name concrete state transitions and triggers.",
        "no swimlane/sequence diagrams exist, but the named transitions are unambiguous enough to "
        "build the status microflow directly; Stage 3 can still add a wiring diagram."),
    "rules": ("specified",
        "quantified rules across the corpus: ch08 fast-track (berth free for the whole stay + "
        "vessel < 120m) and timing (submit 48h-90d before ETA); ch09 (ETD>ETA, stay <= 30 days) PLUS "
        "an image-only rule not in any text chapter: fig-booking-form-validation.png shows 'IMO "
        "NUMBER MUST BE EXACTLY 7 DIGITS'; ch13 draught clearance (>=0.5m); ch18-19 fee formula, VAT "
        "21%, shore power flat 250/day, late-arrival surcharge 15%, late-cancellation fee 50%; ch23 "
        "Failed outcome = any High-severity non-compliant item; ch35 agents see only their own "
        "company's records.",
        "the IMO-digit rule (image-only) and the workshop's explicitly undecided attachment-size "
        "limit (workshop-notes.md Session 2) are the two places a text-only read would under-specify "
        "or miss a rule entirely; both are captured in this rubric so they are not lost downstream."),
    "ui": ("specified",
        "ch28-32 name three screens (Booking Board, My Bookings, Inspection Calendar) with concrete "
        "filter/sort/interaction behaviour (e.g. Booking Board filtered by terminal/status/ETA range, "
        "My Bookings lists Drafts first, Inspection Calendar supports drag-and-drop reschedule); ch21 "
        "and ch09 carry real prototype screenshots (officer review decision panel with red exceedance "
        "highlight; booking form including the IMO validation error state).",
        "no full annotated wireframe set exists in the corpus — Stage 3 (design-artifacts.md) still "
        "owes one wireframe per screen, but the screen inventory and behaviour are unambiguous inputs "
        "to it."),
    "integrations": ("named",
        "ch33 integration-ais-feed: the AIS feed is imported every 5 minutes and flags a booking as "
        "Arrived when the vessel enters the port geofence. No endpoint, auth mechanism, payload "
        "schema, or failure/retry behaviour is given anywhere in the corpus.",
        "Stage 3 must treat the AIS integration as a named-but-unspecified contract (stub with a "
        "policy decision, per Stage 0's missing-dependency policy) — failure-mode design (feed down, "
        "late/duplicate data) is invented by the build unless an SME fills it in at the next attended "
        "session."),
    "nfr": ("named",
        "ch26 audit-and-compliance requires an audit trail on every status change to a booking, "
        "decision, invoice or inspection (actor, timestamp, action) — the sole retention/traceability "
        "requirement in the corpus; ch27 privacy-and-cookies covers only the documentation portal's "
        "own cookie use, not the application's. No performance, availability, concurrency, or data "
        "volume figures appear anywhere.",
        "NFR sizing (concurrent users, booking volume, uptime SLA, retention period beyond 'keep an "
        "audit trail') is entirely unstated; Stage 3's NFR sheet will be the build's own assumption "
        "unless it is asked and answered at the next attended session."),
    "tenancy": ("absent",
        "no mention anywhere of multiple port authorities, multiple deployments, or organisation-"
        "level data partitioning; the whole corpus describes one port authority's own instance (ch35 "
        "security-and-access scopes visibility to 'their own company', i.e. per-agent-company, not "
        "per-tenant).",
        "assume single-tenant. If this application is ever meant to serve more than one port "
        "authority from one deployment, that is new scope no source here provides, not a gap in this "
        "reading of it."),
    "security_model": ("specified",
        "roles.md + ch05 define the 4-role model; ch13 (only Harbour Master waives a tariff "
        "surcharge), ch16 (only Harbour Master overrides a Rejected decision), ch11 (only Harbour "
        "Master reactivates a suspended agent, no self-service), ch35 (agents restricted to bookings/"
        "invoices/inspections belonging to their own company).",
        "none — the role-to-permission mapping is complete enough to model Mendix module security "
        "(entity access + microflow grants) directly from the spec."),
    "data_migration": ("named",
        "ch01/34/35 footer text states the application 'replaces a spreadsheet-based booking "
        "process' — no schema, export sample, or volume for that spreadsheet appears anywhere in the "
        "corpus.",
        "no legacy data is characterised for cutover. Stage 7 does not run in this entry mode anyway "
        "(WAIVED per conversion-runbook.md Entry Modes), but if spreadsheet data later needs a real "
        "cutover, that is new information no source here supplies."),
}

with open(RUBRIC) as f:
    doc = json.load(f)

for key, (rating, evidence, consequence) in DIMS.items():
    doc["dimensions"][key]["rating"] = rating
    doc["dimensions"][key]["evidence"] = evidence
    doc["dimensions"][key]["consequence"] = consequence

with open(RUBRIC, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")

print("dimensions filled:", list(DIMS.keys()))
