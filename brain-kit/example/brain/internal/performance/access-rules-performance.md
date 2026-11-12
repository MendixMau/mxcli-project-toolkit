---
title: Duplicated, negating or exclusive XPath access rules slow queries (MXP010, MXP013)
topic: performance
kind: pitfall
applies_to: general
versions: "any"
keywords: [entity access, access rules, XPath constraint, MXP010, MXP013, duplicated access rules, negating rule, not(), = false(), user roles, slow query, security]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
- Slow retrieves on large entities that have XPath access rules.
- Worse for users with several roles that each have complex security.

**Root cause**
- Every access rule's XPath is added to the generated query.
- Duplicated rules (MXP010) and rules that differ only by negation (MXP013) produce complex SQL.

**Fix**
- MXP013:
  - Remove the negating rule, meaning the one with `not()` or `= false()`.
  - Otherwise, the app may need database tuning at large volumes.
- Read-only vs read/write rules:
  - Make the read-only rule include the read/write case. Example: read-only with no constraint, read/write with `[Editable = true()]`.
  - Do not add `[Editable = false()]` to the read-only rule.
- MXP010:
  - Do not let security rules drive process rules. The security engine is not optimized for task assignment.
  - Consolidate rule variations and validate state changes in microflows instead.
  - Or split the entity into one-to-one associated entities, each with a simple access profile.
- Minimize the number of roles per user and the number of rules per entity.

**Status**
- Documented guidance.
- BPR flags MXP010 and MXP013.
