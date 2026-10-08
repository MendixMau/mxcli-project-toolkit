# mxtk-lint-rule: loop001_expensive_action_in_loop
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# LOOP001: A database, REST, or Java call inside a loop runs once per row
#
# A retrieve from database, a delete, a REST call, an external (web service / OData) call
# or a Java action in a loop body is executed once per iteration: N rows, N round trips.
# The fix is almost always the same shape — retrieve the list once before the loop and
# FIND/FILTER in memory, collect the objects and delete the list after the loop, or batch
# the calls (microflow-loop-antipatterns.md; real: a 1,200-row import at 1,200 database
# retrieves, 40 s, rewritten to one retrieve + FIND, under a second).
#
# CONV011 (mxcli stock) flags a COMMIT in a loop. This rule is the rest of that list. It
# looks INSIDE loops at any depth (activities_for(..., nested=True)), so a retrieve two
# loops down is seen. One finding per flow, naming the offending activities.
#
# Deliberately NOT flagged: retrieve over association (in-memory, already loaded), create,
# change, list operations, aggregates, calls to other microflows (the called flow is linted
# on its own), and anything in System/Administration. A retrieve whose source is unknown
# ("") is also left alone rather than guessed at.
#
# REQUIRES mxcli >= 0.25.0: nested activities with loop_depth, and retrieve_source, were
# added to the Starlark activity projection there (mendixlabs/mxcli#1266). On an older
# binary every activity reports loop_depth 0 and the loop bodies are absent, so the rule
# cannot see — it says so with a `_rule` finding instead of passing.
#
# Vocabulary read from the mxcli source (builder_microflows.go: action_type is the stored
# Mendix action type with "Microflows$" stripped; RetrieveSource is "database" or
# "association"). Probe it on your model before trusting it:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType, RetrieveSource FROM activities WHERE LoopDepth > 0;"

RULE_ID = "LOOP001"
RULE_NAME = "ExpensiveActionInLoop"
DESCRIPTION = "Database retrieve, delete, REST, external or Java call inside a loop body"
CATEGORY = "performance"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")
FLOW_TYPES = ("MICROFLOW", "NANOFLOW")

# action_type values that cost a round trip per iteration.
EXPENSIVE = ("DeleteObjectAction", "RestCallAction", "CallExternalAction", "JavaActionCallAction")
RETRIEVE = "RetrieveAction"
RETRIEVE_DATABASE = "database"

LOOP_TYPE = "LoopedActivity"


def _label(act):
    kind = act.action_type
    if kind == RETRIEVE:
        kind = "database retrieve"
    elif kind == "DeleteObjectAction":
        kind = "delete"
    elif kind == "RestCallAction":
        kind = "REST call"
    elif kind == "CallExternalAction":
        kind = "external call"
    elif kind == "JavaActionCallAction":
        kind = "Java action"
    return "'{}' ({})".format(act.caption or act.name or act.activity_type, kind)


def check():
    violations = []
    loops_seen = 0
    body_rows_seen = 0
    api_missing = False

    for mf in microflows():
        if mf.module_name in SKIP_MODULES:
            continue
        if mf.microflow_type not in FLOW_TYPES:
            continue

        offenders = []
        for act in activities_for(mf.qualified_name, nested=True):
            # getattr, not act.loop_depth: on a pre-0.25.0 binary the attribute does not
            # exist and a bare access aborts the rule as a crash, which the gate would
            # baseline. A missing attribute is reported as blindness instead.
            depth = getattr(act, "loop_depth", None)
            if depth == None:
                api_missing = True
                break
            if act.activity_type == LOOP_TYPE:
                loops_seen += 1
                continue
            if depth < 1:
                continue
            body_rows_seen += 1
            if act.action_type in EXPENSIVE:
                offenders.append(_label(act))
            elif act.action_type == RETRIEVE and getattr(act, "retrieve_source", "") == RETRIEVE_DATABASE:
                offenders.append(_label(act))
        if api_missing:
            break
        if not offenders:
            continue

        violations.append(violation(
            message="{} runs {} per-row call{} inside a loop: {}.".format(
                mf.qualified_name, len(offenders), "" if len(offenders) == 1 else "s",
                ", ".join(offenders[:4]) + (", ..." if len(offenders) > 4 else ""),
            ),
            location=location(module=mf.module_name, document_type="Microflow", document_name=mf.qualified_name),
            suggestion="Retrieve the list once before the loop and use FIND/FILTER on it; collect objects to delete into a list and delete it after the loop; batch REST/Java calls or move them to a sub-flow that takes the whole list.",
        ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="LOOP001 cannot run on this mxcli: activities have no loop_depth (added in mxcli 0.25.0). This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Microflow", document_name="LOOP001"),
            suggestion="Upgrade mxcli to 0.25.0 or later, or remove this rule deliberately rather than leaving it inert.",
        ))
    elif loops_seen > 0 and body_rows_seen == 0:
        violations.append(violation(
            message="LOOP001 saw {} loop(s) and not one activity inside any of them, so no loop body was inspected. The catalog is probably from before loop bodies were indexed.".format(loops_seen),
            location=location(module="_rule", document_type="Microflow", document_name="LOOP001"),
            suggestion="Run `REFRESH CATALOG FULL` on mxcli >= 0.25.0 so the activities table carries loop bodies (LoopDepth > 0), then lint again.",
        ))

    return violations
