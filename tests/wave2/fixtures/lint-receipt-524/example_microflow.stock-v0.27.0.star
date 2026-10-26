# Example Starlark Lint Rule: Microflow Naming Prefixes
#
# This rule checks that microflows follow naming conventions with prefixes:
#   ACT_ - Action microflows (called from UI)
#   SUB_ - Sub-microflows (called from other microflows)
#   DS_  - Data source microflows
#   VAL_ - Validation microflows
#   SCH_ - Scheduled event microflows
#
# Customize the prefixes and patterns to match your project standards.
#
# Microflow properties:
#   .id              - Document ID
#   .name            - Simple name (e.g., "ACT_ProcessOrder")
#   .qualified_name  - Full name (e.g., "MyModule.ACT_ProcessOrder")
#   .module_name     - Module name
#   .microflow_type  - "MICROFLOW", "NANOFLOW" or "RULE"
#   .description     - Documentation
#   .return_type     - Return type
#   .parameter_count - Number of parameters
#   .activity_count  - Number of activities
#   .document_noun   - "microflow", "nanoflow" or "rule" (microflows() yields all three)
#   .document_noun_title - the same, capitalised: use it for document_type=

RULE_ID = "CUSTOM002"
RULE_NAME = "Microflow Prefix Convention"
DESCRIPTION = "Microflows should have standard naming prefixes (ACT_, SUB_, DS_, VAL_, SCH_)"
CATEGORY = "naming"
SEVERITY = "info"

# Define valid prefixes - customize for your project
VALID_PREFIXES = ["ACT_", "SUB_", "DS_", "VAL_", "SCH_", "IVK_", "OCH_"]

def check():
    """
    Check that microflows use standard naming prefixes.
    """
    violations = []

    for mf in microflows():
        name = mf.name  # Simple name

        # Check if name starts with any valid prefix
        has_valid_prefix = False
        for prefix in VALID_PREFIXES:
            if name.startswith(prefix):
                has_valid_prefix = True
                break

        if not has_valid_prefix:
            loc = location(
                module=mf.module_name,
                document_type=mf.document_noun_title,
                document_name=mf.qualified_name
            )
            v = violation(
                message="{} '{}' should start with a standard prefix ({})".format(
                    mf.document_noun_title,
                    name,
                    ", ".join(VALID_PREFIXES)
                ),
                location=loc
            )
            violations.append(v)

    return violations
