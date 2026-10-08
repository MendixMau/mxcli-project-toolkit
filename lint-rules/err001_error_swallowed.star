# mxtk-lint-rule: err001_error_swallowed
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# ERR001: An error that is caught must leave a trace
#
# "Continue" on an activity means: if this fails, carry on as if it worked. "Custom" and
# "Custom without rollback" route the error to a handler branch. All three are fine when the
# flow then logs the error, raises it again, or hands it to a flow that does. All three are a
# silent swallow when nothing in the flow does any of that: the user sees a half-done action,
# the log shows nothing, and the next session's first hour goes to finding out which of forty
# flows ate the exception (the "Continue and pray" pattern, learned-microflow-patterns.md).
#
# What counts as a trace, anywhere in the SAME flow (loop bodies included):
#   1. a Log message activity (action_type LogMessageAction / log_level set)
#   2. an error end event (activity_type ErrorEvent — raise/re-throw)
#   3. a call to a flow whose name says it handles or logs errors
#      (SUB_LogError, ERR_Handle, ..._HandleError — HANDLER_NAME_PATTERN, CamelCase-strict)
#
# Deliberately NOT flagged: Rollback and Abort (the platform surfaces those itself), the
# default "" (no handling set, which Mendix treats as Rollback), flows in System/Administration,
# and RULE-type flows. One finding per flow, naming the swallowing activities.
#
# What CONV013/CONV014 (mxcli stock) do NOT cover: they check that an external call HAS error
# handling. This rule checks that the handling leads somewhere. Different question.
#
# REQUIRES mxcli >= 0.25.0: error_handling_type / log_level / nested activities were added to
# the Starlark activity projection there (mendixlabs/mxcli#1266). On an older binary the rule
# does not go quiet: it emits a `_rule` finding saying it saw nothing.
#
# Vocabulary read from the mxcli source (sdk/microflows/error_handling.go: the action's stored
# ErrorHandlingType verbatim — "Rollback", "Continue", "Custom", "CustomWithoutRollBack" with
# a capital B, "Abort"; builder_microflows.go: activity_type "ErrorEvent", action_type with
# the "Microflows$" prefix stripped). Probe it on your model before trusting it:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ErrorHandlingType FROM activities ORDER BY 1;"
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActivityType, ActionType FROM activities WHERE LogLevel != '' OR ActivityType='ErrorEvent';"

RULE_ID = "ERR001"
RULE_NAME = "ErrorSwallowed"
DESCRIPTION = "An activity that continues or custom-handles on error must be in a flow that logs, raises, or calls an error handler"
CATEGORY = "quality"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")
FLOW_TYPES = ("MICROFLOW", "NANOFLOW")

# Stored error handling values that catch the error (activities.ErrorHandlingType).
SWALLOWING = ("Continue", "Custom", "CustomWithoutRollBack")

# Evidence the error went somewhere.
LOG_ACTION = "LogMessageAction"
RAISE_EVENT = "ErrorEvent"
HANDLER_NAME_PATTERN = "(^|_)(Log|Error|Err|Handle)([A-Z0-9_]|$)"


def _handler_called(qname):
    """True when this flow calls a flow whose name announces error handling or logging."""
    for ref in refs_from(qname):
        if ref.target_type not in ("MICROFLOW", "NANOFLOW"):
            continue
        if ref.target_name == qname:
            continue
        if matches(ref.target_name.split(".")[-1], HANDLER_NAME_PATTERN):
            return True
    return False


def check():
    violations = []
    flows_seen = 0
    activities_seen = 0
    handling_seen = 0
    api_missing = False

    for mf in microflows():
        if mf.module_name in SKIP_MODULES:
            continue
        if mf.microflow_type not in FLOW_TYPES:
            continue
        flows_seen += 1

        swallowing = []
        traced = False
        for act in activities_for(mf.qualified_name, nested=True):
            activities_seen += 1
            # getattr, not act.error_handling_type: on a pre-0.25.0 binary the attribute does
            # not exist and a bare access aborts the rule as a crash, which the gate would
            # baseline. A missing attribute is reported as blindness instead.
            eh = getattr(act, "error_handling_type", None)
            if eh == None:
                api_missing = True
                break
            if eh:
                handling_seen += 1
            if eh in SWALLOWING:
                swallowing.append(act.caption or act.name or act.activity_type)
            if act.activity_type == RAISE_EVENT:
                traced = True
            elif act.action_type == LOG_ACTION or getattr(act, "log_level", ""):
                traced = True
        if api_missing:
            break
        if not swallowing or traced:
            continue
        if _handler_called(mf.qualified_name):
            continue

        violations.append(violation(
            message="{} catches errors on {} activit{} ({}) but never logs, raises, or calls an error handler: the error is swallowed.".format(
                mf.qualified_name, len(swallowing), "y" if len(swallowing) == 1 else "ies",
                ", ".join(["'" + s + "'" for s in swallowing[:4]]) + (", ..." if len(swallowing) > 4 else ""),
            ),
            location=location(module=mf.module_name, document_type="Microflow", document_name=mf.qualified_name),
            suggestion="In the handler branch (or right after a 'Continue' activity) add a Log message at ERROR level with $latestError/Message, or raise the error again; or call the project's SUB_LogError. If the error truly does not matter, say so in an annotation next to the activity.",
        ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="ERR001 cannot run on this mxcli: activities have no error_handling_type (added in mxcli 0.25.0). This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Microflow", document_name="ERR001"),
            suggestion="Upgrade mxcli to 0.25.0 or later, or remove this rule deliberately rather than leaving it inert.",
        ))
    elif flows_seen > 0 and activities_seen == 0:
        violations.append(violation(
            message="ERR001 saw {} flows and not one activity. activities_for() needs the FULL catalog; this rule inspected NOTHING.".format(flows_seen),
            location=location(module="_rule", document_type="Microflow", document_name="ERR001"),
            suggestion="Run `REFRESH CATALOG FULL` (mxcli lint should request it itself from 0.24 on) and lint again.",
        ))
    elif activities_seen >= 20 and handling_seen == 0:
        # Every real action activity stores a handling value (Rollback at minimum). Twenty
        # activities without a single one means the column is empty: a catalog from before
        # the field existed, not a project that never set it.
        violations.append(violation(
            message="ERR001 saw {} activities and none carries an error_handling_type, so no handling was inspected. The catalog is probably from an older schema.".format(activities_seen),
            location=location(module="_rule", document_type="Microflow", document_name="ERR001"),
            suggestion="Run `REFRESH CATALOG FULL` on mxcli >= 0.25.0 so the activities table carries ErrorHandlingType, then lint again.",
        ))

    return violations
