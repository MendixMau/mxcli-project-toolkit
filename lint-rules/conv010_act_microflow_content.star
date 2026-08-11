# CONV010: ACT_ Microflow Content Restriction
#
# Microflows prefixed with ACT_ are page action microflows. They should only
# contain UI-related activities:
#   - ShowPageAction (show page)
#   - ClosePageAction (close page)
#   - ShowMessageAction (show message)
#   - DownloadFileAction (download file)
#   - SubMicroflow (call sub-microflow for logic delegation)
#
# Business logic should be delegated to SUB_ microflows.
# Requires FULL catalog (REFRESH CATALOG FULL).
#
# FIXED 2026-08-11 — this rule was INVERTED for its whole life. Its allowlist was
# copied from .ai-context/skills/write-lint-rules.md:311, which names action types
# that do not exist in the model: ShowFormAction, CloseFormAction, ShowHomeFormAction
# (also CreateChangeAction, CommitAction elsewhere on that line). The real names are
# ShowPageAction / ClosePageAction / CreateObjectAction / ChangeObjectAction /
# CommitObjectsAction — verified against .mxcli/catalog.db, 10,012 activities.
#
# Consequence: showing or closing a page — the single most common thing an ACT_
# microflow does — was NOT allowlisted, so the rule flagged it as undelegated business
# logic. Measured on this project: 138 of 282 ACT_ microflows (49%) were false
# positives. That noise is the likeliest reason lint was made "optional, non-blocking"
# and then stopped running at all.
#
# ShowHomeFormAction has no real counterpart and was dropped rather than guessed at.
# Never take an action-type string from that guide without probing the model first.

RULE_ID = "CONV010"
RULE_NAME = "ACTMicroflowContent"
DESCRIPTION = "ACT_ microflows should only contain UI actions and sub-microflow calls"
CATEGORY = "architecture"
SEVERITY = "warning"

# Allowed action types in ACT_ microflows.
# Every string here must be a value actually present in the model. Probe before adding:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType FROM activities;"
ALLOWED_ACTIONS = (
    "ShowPageAction",
    "ClosePageAction",
    "ShowMessageAction",
    "DownloadFileAction",
)

# Allowed activity types (non-action activities)
ALLOWED_ACTIVITY_TYPES = (
    "SubMicroflow",
    "StartEvent",
    "EndEvent",
    "ExclusiveSplit",
    "Annotation",
)

def check():
    violations = []
    inspected = 0
    saw_any_activity = False

    for mf in microflows():
        if not mf.name.startswith("ACT_"):
            continue

        inspected += 1
        for act in activities_for(mf.qualified_name):
            saw_any_activity = True
            # Skip allowed activity types
            if act.activity_type in ALLOWED_ACTIVITY_TYPES:
                continue

            # For ActionActivity, check the action type
            if act.activity_type == "ActionActivity":
                if act.action_type in ALLOWED_ACTIONS:
                    continue

                violations.append(violation(
                    message="ACT_ microflow '{}' contains '{}' action. Delegate business logic to a SUB_ microflow.".format(
                        mf.name, act.action_type
                    ),
                    location=location(
                        module=mf.module_name,
                        document_type="Microflow",
                        document_name=mf.qualified_name,
                    ),
                    suggestion="Move the '{}' action to a SUB_ microflow and call it from '{}'".format(
                        act.action_type, mf.name
                    ),
                ))
            elif act.activity_type not in ALLOWED_ACTIVITY_TYPES:
                # Any other non-allowed activity type
                violations.append(violation(
                    message="ACT_ microflow '{}' contains '{}' activity. Delegate to a SUB_ microflow.".format(
                        mf.name, act.activity_type
                    ),
                    location=location(
                        module=mf.module_name,
                        document_type="Microflow",
                        document_name=mf.qualified_name,
                    ),
                    suggestion="Move the '{}' to a SUB_ microflow called from '{}'".format(
                        act.activity_type, mf.name
                    ),
                ))

    # SELF-CHECK. activities_for() is a stub returning [] in some mxcli builds (the
    # microflow adapter no longer emits Activity nodes). A rule that reads no
    # activities reports zero violations and looks CLEAN -- a silent false pass.
    # Fail loudly instead. Same guard as CONV020.
    if inspected > 0 and not saw_any_activity:
        violations.append(violation(
            message="CONV010 could not read any microflow activities ({} ACT_ microflows inspected, all reported zero). activities_for() is returning nothing -- this rule checked NOTHING. Do not read a clean result as a pass.".format(inspected),
            location=location(module="_rule", document_type="Microflow", document_name="CONV010"),
            suggestion="Your mxcli build likely postdates the graphcatalog refactor that stubbed activities_for(). Use a build where it is populated, or rewrite this rule against a different API.",
        ))

    return violations
