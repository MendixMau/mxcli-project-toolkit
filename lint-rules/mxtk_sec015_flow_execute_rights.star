# mxtk-lint-rule: mxtk_sec015_flow_execute_rights
# Shipped by mxcli-project-toolkit. Toolkit-authored (`mxcli init` never seeds it); configure
# it ONLY in .claude/lint-config.yaml (below). Installed and refreshed by sync-project.sh.
# See skills/lint-that-actually-runs.md.
# --- end mxtk-lint-rule header ---
# MXTK-SEC015: flow execute rights against a declared role matrix
#
# WHAT IT CATCHES. A role that can EXECUTE a microflow or nanoflow it should not. No stock rule
# reads EXECUTE rows at all. Evidence (MTA E2, 2026-11-05): `Employee` added to the execute
# rights of Procurement.ACT_Vendor_Approve (meant for Admin and ProcurementOfficer, no role
# check inside the flow) was invisible to every stock rule, to `mxcli test` and to the security-on
# test executor. Entity rights do not help: a flow runs with the rights of whoever may call it
# unless "apply entity access" is on.
#
# TWO MODES, matrix first.
#   1. MATRIX (default whenever a matrix is declared). You state which user roles may execute
#      which flows; a user role that can execute a matching flow and is not listed is a
#      finding. Precise, zero noise on a correct model, and exactly as good as the matrix.
#   2. HEURISTIC (opt-in, `heuristic: true`, warning). For each ACT_ flow, every user role that
#      can execute it needs WRITE on every entity the flow changes or commits (System.* and
#      delete excluded: CONV006 tells teams to delete through flows). No input, but it
#      over-reports: on the ProcureFlow model it flagged 49 flows, 46 of them workflow user-task
#      flows reached through a shared module role, whose own task-assignee check protects them.
#      Run it behind the lint baseline so the backlog stays quiet and only a new line shows.
#      A flow covered by a matrix line is not also checked by the heuristic (the matrix is the
#      stricter statement).
# NO MATRIX AND NO HEURISTIC: the rule reports nothing. That is the default, on the record.
#
# Configure in .claude/lint-config.yaml (ONE multi-line text, not a YAML list):
#
#   rules:
#     MXTK-SEC015:
#       options:
#         matrix: |
#           Procurement.ACT_Vendor_Approve = Admin, ProcurementOfficer
#           Procurement.ACT_Vendor_* = Admin, ProcurementOfficer
#           Procurement.ACT_ApprovalStep_Decide = Admin, DepartmentManager, ProcurementOfficer, FinanceApprover
#         heuristic: false        # default false; true adds the ACT_ heuristic
#         action_prefix: "ACT_"   # default; the heuristic's entry-point prefix
#
# Matrix syntax: `<flow pattern> = <user role>, <user role>, ...`, one line each; `#` starts a
# comment line. The pattern is a qualified flow name (`Module.Flow`); `*` matches any run of
# characters (`Procurement.ACT_Vendor_*`, `*.ACT_Delete_*`). The roles are USER role names (what
# `SHOW USER ROLES` lists), not module roles. When several lines match one flow, a role must be
# allowed by EVERY matching line. Keep the block in the project's security table (PROJECT.md);
# a new approve / delete / pay flow needs a line.
#
# SELF-CHECKS (a rule that cannot see must say so, never report a clean pass):
#   - an option of the wrong type, a matrix line without `=` or with an unqualified pattern, or
#     a heuristic that is not true / false: one `_rule` finding.
#   - a matrix role that is not a user role of the model (typo, renamed role): `_rule` finding.
#     A misspelt role would otherwise flag every real user as excess.
#   - a matrix pattern that matches no flow (renamed or deleted): `_rule` finding. A stale line
#     is a flow nobody is checking any more.
#   - role_mappings() / user_roles() returns nothing while a matrix is declared: `_rule` finding.
#
# KNOWN LIMITS. Flows only: not pages, not REST / OData exposure of a flow (a published service
# runs a flow regardless of its execute right), not row XPath on create (the MTA E2 result).
# The execute right is the declared one; an app that checks the role inside the flow is safe
# with a wider right and still gets a finding, which is the point (defence in depth).
# The heuristic reads `refs_from()` (one query per ACT_ flow, about 0.5 s on 600 flows).

RULE_ID = "MXTK-SEC015"
RULE_NAME = "FlowExecuteRights"
DESCRIPTION = "A user role can execute a flow outside the declared role matrix (opt-in: or one that changes data the role cannot write)"
CATEGORY = "security"
SEVERITY = "warning"


def _blind(msg, suggestion):
    return violation(
        message=msg,
        location=location(module="_rule", document_type="Microflow", document_name="MXTK-SEC015"),
        suggestion=suggestion,
    )


def _glob(pat, s):
    # `*` = any run of characters; everything else literal.
    parts = pat.split("*")
    if len(parts) == 1:
        return pat == s
    if not s.startswith(parts[0]):
        return False
    pos = len(parts[0])
    for mid in parts[1:-1]:
        i = s.find(mid, pos)
        if i < 0:
            return False
        pos = i + len(mid)
    last = parts[-1]
    return len(s) - pos >= len(last) and s.endswith(last)


def _lines(raw):
    if type(raw) == "string":
        return raw.split("\n")
    if type(raw) == "list":
        return [x for x in raw if type(x) == "string"]
    return None


def _parse(raw):
    """Returns (entries, errors): entries = [(pattern, [roles])]."""
    entries, errors = [], []
    lines = _lines(raw)
    if lines == None:
        return [], ["the matrix option is {} ({}), not one multi-line text".format(repr(raw), type(raw))]
    for line in lines:
        t = line.strip()
        if not t or t.startswith("#"):
            continue
        if "=" not in t:
            errors.append("matrix line has no '=': " + t)
            continue
        pat, _, rest = t.partition("=")
        pat = pat.strip()
        roles = [x.strip() for x in rest.split(",") if x.strip()]
        if "." not in pat:
            errors.append("matrix pattern is not a qualified flow name (Module.Flow): " + pat)
        elif not roles:
            errors.append("matrix line lists no role: " + t)
        else:
            entries.append((pat, roles))
    return entries, errors


def check():
    heuristic = get_option("heuristic", False)
    if type(heuristic) != "bool":
        return [_blind(
            "MXTK-SEC015 option heuristic is {} ({}), not true / false. This rule inspected NOTHING.".format(repr(heuristic), type(heuristic)),
            "Set `heuristic: true` or `false` under `rules: MXTK-SEC015: options:` in .claude/lint-config.yaml.",
        )]
    prefix = get_option("action_prefix", "ACT_")
    if type(prefix) != "string" or not prefix:
        return [_blind(
            "MXTK-SEC015 option action_prefix is {} ({}), not a non-empty text. This rule inspected NOTHING.".format(repr(prefix), type(prefix)),
            "Set `action_prefix: \"ACT_\"` under `rules: MXTK-SEC015: options:` in .claude/lint-config.yaml.",
        )]
    matrix, errors = _parse(get_option("matrix", ""))
    if errors:
        return [_blind(
            "MXTK-SEC015 matrix is unusable: {}. This rule inspected NOTHING.".format("; ".join(errors[:3])),
            "One line per flow: `Procurement.ACT_Vendor_Approve = Admin, ProcurementOfficer`, as ONE multi-line text (`matrix: |`) under `rules: MXTK-SEC015: options:`.",
        )]
    if not matrix and not heuristic:
        return []   # not configured: silent by design

    # module role -> user roles; flow -> user roles that may execute it; entity -> user roles with WRITE
    m2u = {}
    for rm in role_mappings():
        m2u.setdefault(rm.module_role_name, []).append(rm.user_role_name)
    user_names = {}
    for u in user_roles():
        user_names[u.name] = True
    if not m2u or not user_names:
        return [_blind(
            "MXTK-SEC015 sees no user roles or no module-role mappings, so it cannot tell who can execute what. This rule inspected NOTHING.",
            "Check `SHOW USER ROLES` and that this mxcli returns user_roles() / role_mappings().",
        )]
    execs, kinds, writers = {}, {}, {}
    for p in permissions():
        if p.access_type == "EXECUTE" and (p.element_type == "MICROFLOW" or p.element_type == "NANOFLOW"):
            kinds[p.element_name] = "Nanoflow" if p.element_type == "NANOFLOW" else "Microflow"
            for u in m2u.get(p.module_role_name, []):
                execs.setdefault(p.element_name, {})[u] = True
        elif p.element_type == "ENTITY" and p.access_type == "WRITE":
            for u in m2u.get(p.module_role_name, []):
                writers.setdefault(p.element_name, {})[u] = True

    if matrix and not execs:
        return [_blind(
            "MXTK-SEC015 has a role matrix but permissions() returned no EXECUTE row for any microflow or nanoflow, so nobody can be compared against it. This rule inspected NOTHING.",
            "Check that this mxcli returns EXECUTE rows from permissions() (access_type EXECUTE, element_type MICROFLOW / NANOFLOW), or remove the matrix.",
        )]

    known = {}
    flows = microflows()
    for mf in flows:
        known[mf.qualified_name] = True
    for q in execs:
        known[q] = True

    violations = []
    for pat, roles in matrix:
        for r in roles:
            if r not in user_names:
                violations.append(_blind(
                    "MXTK-SEC015 matrix line '{}' names role '{}', which is not a user role of this model. A misspelt role flags every real user as excess.".format(pat, r),
                    "Check the spelling against `SHOW USER ROLES` (user role names, not module roles), or remove the line.",
                ))
        if not [q for q in known if _glob(pat, q)]:
            violations.append(_blind(
                "MXTK-SEC015 matrix pattern '{}' matches no flow in this model (renamed or deleted?). Nobody is checking that flow any more.".format(pat),
                "Update or remove the matrix line.",
            ))
    if violations:
        return violations

    covered = {}
    for q in sorted(execs.keys()):
        users = execs[q]
        mod = q.split(".")[0]
        doc_type = kinds.get(q, "Microflow")
        loc = location(module=mod, document_type=doc_type, document_name=q)
        for pat, roles in matrix:
            if not _glob(pat, q):
                continue
            covered[q] = True
            for u in sorted(users.keys()):
                if u not in roles:
                    violations.append(violation(
                        message="Role '{}' can execute {} but the role matrix allows only: {}".format(u, q, ", ".join(roles)),
                        location=loc,
                        suggestion="Remove execute on {} for the module role(s) mapped to '{}', or update the matrix if the role is meant to run it".format(q, u),
                    ))

    if heuristic:
        for mf in flows:
            q = mf.qualified_name
            if q in covered or not mf.name.startswith(prefix) or q not in execs:
                continue
            changed = {}
            for r in refs_from(q):
                if r.target_type == "ENTITY" and (r.ref_kind == "change" or r.ref_kind == "commit"):
                    changed[r.target_name] = True
            loc = location(module=mf.module_name, document_type="Microflow", document_name=q)
            for e in sorted(changed.keys()):
                if e.startswith("System."):
                    continue
                w = writers.get(e, {})
                for u in sorted(execs[q].keys()):
                    if u not in w:
                        violations.append(violation(
                            message="Role '{}' can execute {} which changes {}, but the role has no WRITE right on {}".format(u, q, e, e),
                            location=loc,
                            suggestion="Remove execute on {} for '{}', or grant the role WRITE on {} deliberately".format(q, u, e),
                        ))
    return violations
