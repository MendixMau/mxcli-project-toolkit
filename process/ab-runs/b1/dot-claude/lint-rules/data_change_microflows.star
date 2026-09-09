# mxtk-lint-rule: data_change_microflows
# Shipped by mxcli-project-toolkit. This file REPLACES the same-named rule that
# `mxcli init` seeds into .claude/lint-rules/. Do not hand-edit: `mxcli init`
# silently overwrites it (verified 2026-08-18, mxcli v0.17.0), and sync-project.sh
# restores it only while the marker line above is present and unmodified.
# See skills/lint-that-actually-runs.md.
# --- end mxtk-lint-rule header ---
# Starlark Lint Rule: Data Changes Through Microflows
#
# This rule enforces that data changes (create, update, delete) should go
# through microflows to ensure proper validation. Direct page saves bypass
# validation logic and can lead to data integrity issues.
#
# The rule checks that for each persistent entity, there is at least one
# microflow that creates or changes it. Entities without associated
# data-change microflows may be relying on direct page commits.
#
# This rule requires REFRESH CATALOG FULL to populate the refs table.
#
# Available functions:
#   refs_to(target_name) - Returns list of references to the given target
#
# Reference properties:
#   .source_type  - Type of source (e.g., "MICROFLOW")
#   .source_name  - Qualified name of source
#   .target_type  - Type of target (e.g., "ENTITY")
#   .target_name  - Qualified name of target
#   .ref_kind     - Kind of reference ("create", "change", "retrieve", etc.)
#   .module_name  - Module containing the reference

# Platform modules every Mendix app inherits. Findings here are Mendix's design decisions,
# not this project's, and cannot be fixed by anyone reading this report. Same list as ARCH003.
SKIP_MODULES = ["System", "Administration"]

RULE_ID = "ARCH002"
RULE_NAME = "Data Changes Through Microflows"
DESCRIPTION = "Persistent entities should have microflows that handle data changes (create/update)"
CATEGORY = "architecture"
SEVERITY = "warning"

def check():
    """
    Check that persistent entities have microflows handling their data changes.
    Entities without create/change microflows may rely on direct page commits,
    bypassing validation logic.
    """
    violations = []

    # Check each persistent entity
    for entity in entities():
        # Skip non-persistent and view entities (they don't need data-change microflows)
        if entity.entity_type != "Persistent":
            continue

        # Skip platform modules. ARCH003 has always had this skip and ARCH002 never did,
        # which was invisible while the rule was dead. With the casing fixed it matters: on
        # TestCLIApp every one of the 38 findings was a System entity -- nobody's code, and
        # nothing anyone can act on. Marketplace modules are excluded at the gate instead
        # (bin/lint-gate.sh -e, from .claude/lint-vendor-modules.txt), because which ones a
        # project uses is per-project data and does not belong hardcoded in a shared rule.
        if entity.module_name in SKIP_MODULES:
            continue

        # Get all references to this entity
        refs = refs_to(entity.qualified_name)

        # Check if any reference is a create or change operation from a microflow
        has_data_change_microflow = False
        for ref in refs:
            if ref.ref_kind in ["create", "change", "commit"]:
                has_data_change_microflow = True
                break

        if not has_data_change_microflow:
            loc = location(
                module=entity.module_name,
                document_type="Entity",
                document_name=entity.qualified_name
            )
            v = violation(
                message="Entity '{}' has no microflows handling data changes. Data may be saved directly from pages without validation.".format(
                    entity.name
                ),
                location=loc,
                suggestion="Create microflows (e.g., ACT_Save{}, VAL_{}) to handle create/update operations with proper validation.".format(
                    entity.name,
                    entity.name
                )
            )
            violations.append(v)

    return violations
