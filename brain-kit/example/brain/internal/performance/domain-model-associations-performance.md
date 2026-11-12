---
title: Reference sets, multiple associations and temporary associations add query load
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [reference set, association, extra queries, temporary association, non-persistable, intermediary entity, enumeration, denormalize, archive data, event handlers]
sources:
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Minimize reference set associations.
- Avoid more than one association between the same two entities.
- Do not put temporary associations on persistable entities.

**Why**
- On every query, Mendix retrieves reference IDs (per row for list retrieves).
- Many references, and reference sets in particular, cause extra queries.

**How to apply**
- Multiple associations between entities:
  - Replace them, for example `Document_Owner`/`Document_Editor`/`Document_Viewer`.
  - Use an intermediary entity (for example `DocumentAccess`) with an enumeration such as `AccessType`.
- Screen/UI logic: use non-persistable entities instead of temporary associations.
- Event handlers fire on every event, such as commit. Minimize their use and their work.
- Slow commits are often caused by before/after-commit events, so check those microflows.
- Consider denormalizing (copying attribute values) for data that rarely changes. You must build the sync logic yourself.
- Consider archiving data you do not need all the time, for example into an identical history entity.
