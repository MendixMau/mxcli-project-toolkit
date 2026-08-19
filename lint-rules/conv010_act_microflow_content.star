# mxtk-lint-rule: conv010_act_microflow_content
# Shipped by mxcli-project-toolkit. This file REPLACES the same-named rule that
# `mxcli init` seeds into .claude/lint-rules/. Do not hand-edit: `mxcli init`
# silently overwrites it (verified 2026-08-18, mxcli v0.17.0), and sync-project.sh
# restores it only while the marker line above is present and unmodified.
# See skills/lint-that-actually-runs.md.
# --- end mxtk-lint-rule header ---
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
#
# DE-NOISED 2026-08-14 — the un-inverted rule still emitted 399 rows on this project's
# own modules, but those were only 55 distinct microflows: it fired once per *activity*,
# so one fat ACT_ microflow produced 43 identical-looking rows and buried everything
# else in the report. Two changes:
#   1. One violation per microflow, naming the offending action types and the count.
#   2. Four action types moved to the allowlist because flagging them was wrong, not
#      merely noisy (212 of the 399 rows):
#        MicroflowCallAction  - this IS the delegation the rule demands. Activities
#                               recorded as ActionActivity/MicroflowCallAction never
#                               reach the activity_type=="SubMicroflow" branch, so
#                               correctly-delegating microflows were being flagged.
#        LogMessageAction     - logging is not business logic.
#        CreateVariableAction - a local variable is not business logic.
#        ExclusiveMerge       - a control-flow join. ExclusiveSplit was already
#                               allowlisted; its matching merge was overlooked.
# Net on this project: 399 rows -> 51 findings, each a real fat ACT_ microflow.

# HOUSE NAMING CONVENTION. `ACT_` for page actions and `SUB_` for delegated logic come from
# Mendix's own Development Best Practices, so they are a reasonable default -- but they are a
# convention, not a guarantee, and this rule is USELESS on a project that names things
# differently: it matches no microflow, finds no violations, and reports a clean pass.
#
# Change these two strings to match your project rather than deleting the rule. If neither
# prefix matches anything, the self-check at the bottom says so instead of going quiet.
ACTION_PREFIX = "ACT_"
DELEGATE_PREFIX = "SUB_"

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
    "MicroflowCallAction",   # the delegation this rule asks for -- see DE-NOISED note
    "LogMessageAction",      # logging is not business logic
    "CreateVariableAction",  # a local variable is not business logic
)

# Allowed activity types (non-action activities).
# Every string here must be a real ActivityType. Probe before adding:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT ActivityType FROM activities;"
# The complete real set (verified 2026-08-14) is exactly nine values:
#   ActionActivity Annotation EndEvent ErrorEvent ExclusiveMerge
#   ExclusiveSplit InheritanceSplit LoopedActivity StartEvent
#
# "SubMicroflow" was here since the rule was written and is NOT one of them -- zero rows
# in the catalog. It was the ROOT CAUSE of the MicroflowCallAction false positives fixed
# above: a sub-microflow call is recorded as ActionActivity/MicroflowCallAction, so this
# dead entry never matched and the rule flagged the very delegation it demands. Removed.
#
# Deliberately NOT allowlisted: LoopedActivity (a loop is business logic -- 18 occurrences
# in this project's ACT_ microflows, all fair findings).
ALLOWED_ACTIVITY_TYPES = (
    "StartEvent",
    "EndEvent",
    "ErrorEvent",        # control flow
    "ExclusiveSplit",    # control flow
    "ExclusiveMerge",    # control flow
    "InheritanceSplit",  # control flow -- same category as ExclusiveSplit, was overlooked
    "Annotation",
)

def check():
    violations = []
    inspected = 0
    total = 0
    saw_any_activity = False

    for mf in microflows():
        total += 1
        if not mf.name.startswith(ACTION_PREFIX):
            continue

        inspected += 1

        # Collect the offending kinds for THIS microflow, then emit at most one
        # violation for it. Per-activity rows made a single fat microflow look like
        # dozens of separate problems and drowned every other rule in the report.
        offenders = []      # distinct kind names, in first-seen order
        offender_count = 0  # total offending activities

        for act in activities_for(mf.qualified_name):
            saw_any_activity = True
            if act.activity_type in ALLOWED_ACTIVITY_TYPES:
                continue

            if act.activity_type == "ActionActivity":
                if act.action_type in ALLOWED_ACTIONS:
                    continue
                kind = act.action_type
            else:
                kind = act.activity_type

            offender_count += 1
            if kind not in offenders:
                offenders.append(kind)

        if offender_count > 0:
            violations.append(violation(
                message="{} microflow '{}' contains {} business-logic activities ({}). Delegate them to a {} microflow.".format(
                    ACTION_PREFIX, mf.name, offender_count, ", ".join(offenders), DELEGATE_PREFIX
                ),
                location=location(
                    module=mf.module_name,
                    document_type="Microflow",
                    document_name=mf.qualified_name,
                ),
                suggestion="Extract the {} into one or more {} microflows and call them from '{}', leaving only page/message/download actions here.".format(
                    ", ".join(offenders), DELEGATE_PREFIX, mf.name
                ),
            ))

    # SELF-CHECK. activities_for() is a stub returning [] in some mxcli builds (the
    # microflow adapter no longer emits Activity nodes). A rule that reads no
    # activities reports zero violations and looks CLEAN -- a silent false pass.
    # Fail loudly instead. Same guard as CONV020.
    # SELF-CHECK 2: the naming convention does not match this project.
    # The guard below only fires once at least one microflow matched the prefix. A project
    # that does not use ACT_ at all inspects ZERO, skips that guard, and gets a clean pass
    # from a rule that never looked at anything -- the same false pass, arrived at from the
    # other direction. Guarded on total so a project with no microflows yet stays quiet.
    if total > 0 and inspected == 0:
        violations.append(violation(
            message="CONV010 matched no microflows: none of the {} in this project start with '{}', so this rule inspected NOTHING. A clean result here means the naming convention does not match, not that the code is fine.".format(total, ACTION_PREFIX),
            location=location(module="_rule", document_type="Microflow", document_name="CONV010"),
            suggestion="Set ACTION_PREFIX and DELEGATE_PREFIX at the top of this rule to the prefixes this project actually uses for page-action and delegated microflows. If the project has no such convention, remove the rule deliberately rather than leaving it silently inert.",
        ))

    if inspected > 0 and not saw_any_activity:
        violations.append(violation(
            message="CONV010 could not read any microflow activities ({} ACT_ microflows inspected, all reported zero). activities_for() is returning nothing -- this rule checked NOTHING. Do not read a clean result as a pass.".format(inspected),
            location=location(module="_rule", document_type="Microflow", document_name="CONV010"),
            suggestion="Your mxcli build likely postdates the graphcatalog refactor that stubbed activities_for(). Use a build where it is populated, or rewrite this rule against a different API.",
        ))

    return violations
