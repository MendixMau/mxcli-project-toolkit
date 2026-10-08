# mxtk-lint-rule: ux001_confirm_before_destructive
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# UX001: A button that destroys or finalises must ask first
#
# A click that deletes, approves, rejects, submits or archives cannot be undone by the
# person who clicked it. Mendix has a confirmation dialog for exactly this ("Ask
# confirmation" on a microflow/nanoflow button), and the house rule is that every such
# button uses it. Three shapes are flagged, one finding per button:
#
#   1. the button uses the DELETE client action directly
#      (Forms$DeleteClientAction). That action has NO confirmation setting at all, so
#      the only fix is to route it through a microflow that deletes, and confirm there.
#   2. the button calls a microflow or nanoflow WITHOUT confirmation, and that flow (or a
#      flow it calls, bounded depth) contains a Delete objects action.
#   3. the button calls a flow WITHOUT confirmation whose NAME says it is irreversible
#      (ACT_Order_Approve, ACT_RejectRequest, SUB_Submit...). Name-based, so it is the
#      weakest leg; the pattern below is deliberately CamelCase-strict ("Approved" in
#      ACT_ShowApprovedOrders does not match, "Approve" at a word end does).
#
# What is deliberately NOT flagged: Save/Cancel, show page, create, datasource
# microflows (they are not buttons and carry no action_type), and buttons that already
# ask. One finding per button, located at the page or snippet holding it.
#
# REQUIRES mxcli >= 0.25.0: widget action_type / has_confirmation / page_ref were added
# to the Starlark widgets() projection there (mendixlabs/mxcli#1268). On an older
# binary the rule does not go quiet: it emits a `_rule` finding saying it saw nothing.
#
# Vocabulary below was read from the mxcli catalog builder source (builder_pages.go
# widgetPrimaryAction stores the action's stored $Type verbatim; builder_microflows.go
# strips the "Microflows$" prefix from an action's type), NOT from write-lint-rules.md.
# Probe it on your model before trusting it:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType FROM widgets ORDER BY 1;"
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActionType FROM activities ORDER BY 1;"

RULE_ID = "UX001"
RULE_NAME = "ConfirmBeforeDestructive"
DESCRIPTION = "Buttons that delete, or call a flow that deletes or finalises, must ask for confirmation"
CATEGORY = "quality"
SEVERITY = "warning"

REQUIRES = ["full"]

# Platform modules are never ours to fix. Marketplace modules are excluded at the
# gate instead (bin/lint-gate.sh reads .claude/lint-vendor-modules.txt), not hardcoded here.
SKIP_MODULES = ("System", "Administration")

# Stored client-action types on a button / on-click action (widgets.ActionType).
DIRECT_DELETE = "Forms$DeleteClientAction"
FLOW_CALLS = ("Forms$MicroflowClientAction", "Forms$CallNanoflowClientAction")

# Microflow action types that destroy data (activities.ActionType, "Microflows$" stripped).
DESTRUCTIVE_ACTIONS = ("DeleteObjectAction",)

# Flow names that announce an irreversible step. Anchored to a name segment start and a
# CamelCase/segment end, so "Approved", "Deleted", "Submitted" never match.
DESTRUCTIVE_NAME_PATTERN = "(^|_)(Delete|Remove|Approve|Reject|Submit|Archive|Finalize|Finalise|Publish|Withdraw|Revoke|Discard|Purge)($|_|[A-Z0-9])"

# Flows walked from the button: the target, what it calls, what that calls (3 flows deep).
# A delete four flows away is not seen; the unit suite pins both sides of that line.
MAX_CALL_DEPTH = 3


def _action_types(qname, cache):
    """Action types directly inside one flow."""
    if qname in cache:
        return cache[qname]
    found = []
    for act in activities_for(qname):
        if act.action_type:
            found.append(act.action_type)
    cache[qname] = found
    return found


def _callees(qname, cache):
    """Flows called by this one (microflows and nanoflows)."""
    if qname in cache:
        return cache[qname]
    found = []
    for ref in refs_from(qname):
        if ref.target_type in ("MICROFLOW", "NANOFLOW") and ref.target_name != qname:
            found.append(ref.target_name)
    cache[qname] = found
    return found


def _destroys(qname, act_cache, call_cache):
    """True when the flow, or anything it calls within MAX_CALL_DEPTH, deletes objects.
    Starlark has no recursion, so the call graph is walked with a bounded frontier."""
    seen = {qname: True}
    frontier = [qname]
    for _ in range(MAX_CALL_DEPTH):
        next_frontier = []
        for q in frontier:
            for a in _action_types(q, act_cache):
                if a in DESTRUCTIVE_ACTIONS:
                    return True
            for callee in _callees(q, call_cache):
                if callee not in seen:
                    seen[callee] = True
                    next_frontier.append(callee)
        frontier = next_frontier
        if not frontier:
            break
    return False


def _doc_type(container_type):
    # container_type is UPPERCASE in the API ("PAGE" / "SNIPPET"), like every other *_type.
    if container_type == "SNIPPET":
        return "Snippet"
    return "Page"


def check():
    violations = []
    act_cache = {}
    call_cache = {}
    widgets_in_scope = 0
    widgets_with_action = 0
    api_missing = False

    for w in widgets():
        if w.module_name in SKIP_MODULES:
            continue
        widgets_in_scope += 1

        # getattr, not w.action_type: on a pre-0.25.0 binary the attribute does not exist
        # and a bare access aborts the rule with "struct has no .action_type attribute",
        # which the gate would then baseline as a crash rather than a finding.
        at = getattr(w, "action_type", None)
        if at == None:
            api_missing = True
            break
        if not at:
            continue
        widgets_with_action += 1

        loc = location(
            module=w.module_name,
            document_type=_doc_type(w.container_type),
            document_name=w.container_qualified_name,
        )

        if at == DIRECT_DELETE:
            violations.append(violation(
                message="Button '{}' on {} deletes directly (Forms$DeleteClientAction), which has no confirmation setting.".format(
                    w.name, w.container_qualified_name
                ),
                location=loc,
                suggestion="Call a microflow that deletes the object instead, and tick 'Ask confirmation' on the button (ACTIONBUTTON ... (Action: MICROFLOW Mod.ACT_X_Delete(...), Confirmation: 'Delete this ...?')).",
            ))
            continue

        if at not in FLOW_CALLS:
            continue
        if getattr(w, "has_confirmation", False):
            continue

        target = w.microflow_ref
        if not target:
            target = getattr(w, "nanoflow_ref", "")
        if not target:
            continue

        why = ""
        if _destroys(target, act_cache, call_cache):
            why = "deletes objects (directly or through a called flow)"
        elif matches(target.split(".")[-1], DESTRUCTIVE_NAME_PATTERN):
            why = "is named as an irreversible step"
        if not why:
            continue

        violations.append(violation(
            message="Button '{}' on {} calls {} without confirmation, and that flow {}.".format(
                w.name, w.container_qualified_name, target, why
            ),
            location=loc,
            suggestion="Add a confirmation to the button (Confirmation: '...?' on the ACTIONBUTTON, or 'Ask confirmation' in Studio Pro) saying what will happen and that it cannot be undone.",
        ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="UX001 cannot run on this mxcli: widgets() has no action_type/has_confirmation (added in mxcli 0.25.0). This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Page", document_name="UX001"),
            suggestion="Upgrade mxcli to 0.25.0 or later, or remove this rule deliberately rather than leaving it inert.",
        ))
    elif widgets_in_scope == 0:
        violations.append(violation(
            message="UX001 saw no widgets outside System/Administration. widgets() needs the FULL catalog; this rule inspected NOTHING.",
            location=location(module="_rule", document_type="Page", document_name="UX001"),
            suggestion="Run `REFRESH CATALOG FULL` (mxcli lint should request it itself from 0.24 on) and lint again.",
        ))
    elif widgets_with_action == 0:
        violations.append(violation(
            message="UX001 saw {} widgets and not one reports an action type, so no button was inspected. The catalog is probably from an older schema.".format(widgets_in_scope),
            location=location(module="_rule", document_type="Page", document_name="UX001"),
            suggestion="Run `REFRESH CATALOG FULL` on mxcli >= 0.25.0 so the widgets table carries ActionType, then lint again.",
        ))

    return violations
