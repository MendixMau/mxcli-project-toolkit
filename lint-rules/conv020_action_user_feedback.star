# mxtk-lint-rule: conv020_action_user_feedback
# Shipped by mxcli-project-toolkit. UNLIKE the other rules here this one is MEANT to be
# edited: PROJECT_MODULES must name the modules this project owns, or the rule inspects
# nothing and says so. sync-project.sh therefore installs it once and never refreshes it;
# when the template changes it reports the change and leaves your configured copy alone.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# CONV020: Completing user actions must tell the user what happened
#
# A microflow that is triggered from a page and that COMPLETES WORK -- commits
# created/changed objects, runs an import, deletes -- should give the user
# visible feedback. A log message alone is invisible to the person who clicked.
#
# Deliberately NARROW, to avoid notification spam:
#   flagged   = page-triggered  AND  state actually committed  AND  no feedback
#   ignored   = retrieves / changes without commit  (nothing happened)
#   ignored   = not reachable from a page           (no client to message)
#   ignored   = validation-only paths               (inline feedback, not a toast)
#
# State changes are detected THROUGH sub-microflow calls (bounded depth), because
# the house style delegates logic from ACT_ shells into SUB_ microflows.
#
# Async note: feedback at click time may only claim the work was ACCEPTED
# ("Submitted, syncing to X"), never that a background sync succeeded.
#
# Action type strings below were taken from a live probe of the model, NOT from
# write-lint-rules.md -- that guide names them ShowFormAction / CloseFormAction,
# which match nothing. See CONV010, which is broken for exactly that reason.

# HOUSE NAMING CONVENTION, same as CONV010 -- see the note there. refs_to() cannot tell a
# button click from a datasource (both report ref_kind "action"), so the prefix is the ONLY
# available filter for "a user actually triggered this". A project that names things
# differently gets no findings and no signal, which the self-check at the bottom now catches.
ACTION_PREFIX = "ACT_"

RULE_ID = "CONV020"
RULE_NAME = "ActionUserFeedback"
DESCRIPTION = "Page-triggered microflows that commit, import or delete should show the user a message"
CATEGORY = "quality"
SEVERITY = "warning"

REQUIRES = ["full"]

# CONFIGURE ME. Only lint modules this project owns -- everything else is Marketplace
# or vendor content you do not author and cannot fix. Leaving this empty does not make
# the rule lint everything; it makes the rule refuse to run (see the guard in check()),
# because a rule that silently inspects nothing is worse than no rule.
#
# List them with:
#   ./mxcli -p <project>.mpr -c "SHOW MODULES"
PROJECT_MODULES = ()

# Work was actually completed and persisted.
STATE_CHANGE_ACTIONS = (
    "CommitObjectsAction",
    "ImportXmlAction",
    "DeleteObjectAction",
)

# The user was told something.
FEEDBACK_ACTIONS = (
    "ShowMessageAction",
    "ValidationFeedbackAction",
)

MAX_CALL_DEPTH = 3


def _action_types(qname, cache):
    """Action types directly inside one microflow."""
    if qname in cache:
        return cache[qname]
    found = []
    for act in activities_for(qname):
        if act.action_type:
            found.append(act.action_type)
    cache[qname] = found
    return found


def _callees(qname, cache):
    """Microflows called by this one."""
    if qname in cache:
        return cache[qname]
    found = []
    for ref in refs_from(qname):
        if ref.target_type == "MICROFLOW" and ref.target_name != qname:
            found.append(ref.target_name)
    cache[qname] = found
    return found


def check():
    violations = []
    act_cache = {}
    call_cache = {}
    saw_any_activity = False
    inspected = 0
    in_scope = 0        # microflows in PROJECT_MODULES, before the prefix filter
    prefix_matched = 0  # ...of those, how many carry ACTION_PREFIX

    # UNCONFIGURED GUARD. Ships from the toolkit with an empty module list. Without
    # this, an uncustomised copy inspects zero microflows and reports a clean pass --
    # the exact silent-false-pass shape this rule's self-check exists to prevent.
    if not PROJECT_MODULES:
        return [violation(
            message="CONV020 is unconfigured: PROJECT_MODULES is empty, so this rule inspected NOTHING. It was installed from the toolkit template and never customised for this project.",
            location=location(module="_rule", document_type="Microflow", document_name="CONV020"),
            suggestion="Edit PROJECT_MODULES at the top of this rule to list the modules this project owns (`SHOW MODULES`), excluding Marketplace and vendor modules.",
        )]

    # Which microflows are called directly from a page, and which from a nanoflow.
    # Starlark has no recursion, so the call graph is walked with a bounded frontier.
    for mf in microflows():
        if mf.module_name not in PROJECT_MODULES:
            continue

        in_scope += 1

        # LIMITATION: refs_to() reports ref_kind == "action" for EVERY page
        # reference -- a button click and a datasource look identical. A
        # datasource must not be flagged (nobody clicked it, and a message on
        # every page load is exactly the spam we are avoiding). With no API
        # signal, the ACT_ naming convention is the only available filter.
        # If a real user action is named something else, this rule misses it.
        if not mf.name.startswith(ACTION_PREFIX):
            continue

        prefix_matched += 1

        # NOTE: these source_type values are UPPERCASE in the actual API
        # (verified by probe), NOT lowercase as write-lint-rules.md claims.
        # Getting this wrong makes the rule match nothing and report a clean pass.
        page_triggered = False
        wrapper_nanoflows = []
        for ref in refs_to(mf.qualified_name):
            if ref.source_type == "PAGE" or ref.source_type == "SNIPPET":
                page_triggered = True
            elif ref.source_type == "NANOFLOW":
                wrapper_nanoflows.append(ref.source_name)

        if not page_triggered:
            continue

        inspected += 1
        if _action_types(mf.qualified_name, act_cache):
            saw_any_activity = True

        # Collect action types across this microflow and everything it calls.
        seen = {mf.qualified_name: True}
        frontier = [mf.qualified_name]
        all_actions = []

        for _ in range(MAX_CALL_DEPTH):
            next_frontier = []
            for q in frontier:
                all_actions.extend(_action_types(q, act_cache))
                for callee in _callees(q, call_cache):
                    if callee not in seen:
                        seen[callee] = True
                        next_frontier.append(callee)
            frontier = next_frontier
            if not frontier:
                break

        changed_state = False
        for a in all_actions:
            if a in STATE_CHANGE_ACTIONS:
                changed_state = True
                break

        if not changed_state:
            continue

        # Feedback may live in the microflow itself, or in a nanoflow that wraps it
        # (the CE0720 workaround puts show message in the nanoflow).
        has_feedback = False
        for a in all_actions:
            if a in FEEDBACK_ACTIONS:
                has_feedback = True
                break
        if not has_feedback:
            for nf in wrapper_nanoflows:
                for a in _action_types(nf, act_cache):
                    if a in FEEDBACK_ACTIONS:
                        has_feedback = True
                        break
                if has_feedback:
                    break

        if has_feedback:
            continue

        logs_only = False
        for a in all_actions:
            if a == "LogMessageAction":
                logs_only = True
                break

        detail = "logs the outcome but shows the user nothing" if logs_only else "gives no outcome signal at all"

        violations.append(violation(
            message="'{}' is triggered from a page and commits/imports/deletes data, but {}.".format(
                mf.name, detail
            ),
            location=location(
                module=mf.module_name,
                document_type="Microflow",
                document_name=mf.qualified_name,
            ),
            suggestion="Add a Show Message (type Information -- 'Success' silently degrades to Information) stating what completed. If the work is handed to an async integration, say it was submitted, not that it arrived.",
        ))

    # SELF-CHECK. activities_for() is a stub returning [] in newer mxcli builds
    # (the microflow adapter no longer emits Activity nodes). A rule that reads
    # no activities reports zero violations and looks CLEAN -- a silent false
    # pass. Fail loudly instead: if we inspected page-triggered microflows and
    # not one of them had a single activity, the API is dead, not the model.
    # SELF-CHECK: the naming convention does not match this project.
    # PROJECT_MODULES is configured (checked at the top) and those modules hold microflows,
    # but not one carries the prefix -- so the filter above discarded everything and the rule
    # inspected nothing. Distinct from "matched the prefix but none is page-triggered", which
    # is a legitimate clean result and stays quiet.
    if in_scope > 0 and prefix_matched == 0:
        violations.append(violation(
            message="CONV020 matched no microflows: none of the {} in PROJECT_MODULES start with '{}', so this rule inspected NOTHING. A clean result here means the naming convention does not match, not that every action gives feedback.".format(in_scope, ACTION_PREFIX),
            location=location(module="_rule", document_type="Microflow", document_name="CONV020"),
            suggestion="Set ACTION_PREFIX at the top of this rule to the prefix this project uses for page-action microflows. Without a prefix convention this rule cannot tell a button click from a datasource and should be removed deliberately rather than left inert.",
        ))

    if inspected > 0 and not saw_any_activity:
        violations.append(violation(
            message="CONV020 could not read any microflow activities ({} page-triggered microflows inspected, all reported zero). activities_for() is returning nothing -- this rule checked NOTHING. Do not read a clean result as a pass.".format(inspected),
            location=location(module="_rule", document_type="Microflow", document_name="CONV020"),
            suggestion="Your mxcli build likely postdates the graphcatalog refactor that stubbed activities_for(). Use a build where it is populated, or rewrite this rule against a different API.",
        ))

    return violations
