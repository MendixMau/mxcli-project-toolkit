# mxtk-lint-rule: ux002_decisions_captioned
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# UX002: Decisions carry a question, long flows carry an annotation
#
# The next reader of a microflow is a reviewer, a tester, or the next session's agent,
# and none of them can run it in their head. Two things make a flow readable on the
# canvas and in DESCRIBE MICROFLOW output, and both are cheap at write time and
# expensive to add later:
#
#   1. every decision (ExclusiveSplit) has its own caption, written as the question it
#      answers ("Order already approved?"), not the auto-generated expression. In MDL:
#         @caption 'Order already approved?'
#         IF $Order/Status = 'Approved' THEN ...
#   2. a flow with ANNOTATE_FROM or more top-level activities has at least one
#      annotation or a documentation text saying what the flow is for. In MDL:
#         @annotation 'Rejects the order, notifies the requester, closes the task.'
#      before an activity, or a /** ... */ doc block before CREATE MICROFLOW.
#
# One finding per microflow per leg (a 30-activity flow with 6 bare decisions is two
# findings, not seven), so the ratchet in bin/lint-gate.sh moves one step per flow.
# Rules (RULE microflow_type) are skipped: they are expressions, not narratives.
#
# REQUIRES mxcli >= 0.25.0: activity caption / auto_generate_caption / description
# (mendixlabs/mxcli#1266, #1267). Before that every activity's caption was the
# placeholder "Activity". On an older binary the rule emits a `_rule` finding instead
# of a silent clean pass.
#
# Vocabulary: activity_type "ExclusiveSplit" / "Annotation" are the names
# getMicroflowObjectType() in mxcli's catalog builder returns (builder_microflows.go);
# microflow_type is UPPERCASE ("MICROFLOW" / "NANOFLOW" / "RULE"), verified on 0.24.0
# (skills/lint-that-actually-runs.md). activities_for() is TOP-LEVEL only: decisions
# inside a loop body are not seen (documented limitation, same as CONV009).

RULE_ID = "UX002"
RULE_NAME = "DecisionsCaptioned"
DESCRIPTION = "Decisions need a caption written as a question; flows of 8+ activities need an annotation or documentation"
CATEGORY = "quality"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")
FLOW_TYPES = ("MICROFLOW", "NANOFLOW")

# Top-level activity count from which a flow owes the reader an annotation.
ANNOTATE_FROM = 8


def check():
    violations = []
    inspected = 0
    saw_any_activity = False
    api_missing = False

    for mf in microflows():
        if mf.module_name in SKIP_MODULES:
            continue
        if mf.microflow_type not in FLOW_TYPES:
            continue
        inspected += 1

        acts = activities_for(mf.qualified_name)
        if not acts:
            continue
        saw_any_activity = True

        bare_decisions = 0
        has_annotation = False
        for act in acts:
            if act.activity_type == "Annotation":
                has_annotation = True
                continue
            if act.activity_type != "ExclusiveSplit":
                continue
            auto = getattr(act, "auto_generate_caption", None)
            if auto == None:
                api_missing = True
                break
            if auto or act.caption.strip() == "":
                bare_decisions += 1
        if api_missing:
            break

        loc = location(
            module=mf.module_name,
            document_type="Microflow",
            document_name=mf.qualified_name,
        )

        if bare_decisions > 0:
            violations.append(violation(
                message="'{}' has {} decision(s) with no caption of their own (auto-generated or empty).".format(
                    mf.name, bare_decisions
                ),
                location=loc,
                suggestion="Give each decision a caption written as the question it answers: `@caption 'Already approved?'` before the IF in MDL, or the Caption field in Studio Pro.",
            ))

        if len(acts) >= ANNOTATE_FROM and not has_annotation and mf.description.strip() == "":
            violations.append(violation(
                message="'{}' has {} top-level activities, no annotation and no documentation.".format(
                    mf.name, len(acts)
                ),
                location=loc,
                suggestion="Add `@annotation '...'` before the first activity saying what the flow does and for whom, or a /** ... */ documentation block before CREATE MICROFLOW.",
            ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="UX002 cannot run on this mxcli: activities have no auto_generate_caption (added in mxcli 0.25.0). This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Microflow", document_name="UX002"),
            suggestion="Upgrade mxcli to 0.25.0 or later, or remove this rule deliberately rather than leaving it inert.",
        ))
    elif inspected > 0 and not saw_any_activity:
        violations.append(violation(
            message="UX002 could not read any microflow activities ({} flows inspected, all reported zero). activities_for() is returning nothing -- this rule checked NOTHING.".format(inspected),
            location=location(module="_rule", document_type="Microflow", document_name="UX002"),
            suggestion="Run `REFRESH CATALOG FULL` and lint again; if it stays empty, this mxcli build does not populate activities_for().",
        ))

    return violations
