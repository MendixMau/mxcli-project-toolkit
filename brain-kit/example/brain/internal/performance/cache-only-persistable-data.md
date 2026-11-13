---
title: Do not associate non-persistable entities with System.Session or System.User for caching (MXP008)
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [MXP008, cache, caching, non-persistable entity, System.Session, System.User, stale data, persistable]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Caching non-persistable objects through associations to System.Session or System.User is redundant. They already live only in memory.
- To cache, use persistable entities connected to System.Session.

**Why**
- Caching frequently used, rarely changing data avoids database round trips.
- Non-persistable objects gain nothing from it.

**How to apply**
- Cache only if all of these hold:
  - The data changes rarely.
  - The data is read often.
  - The volume is limited, usually under 10 000 records.
  - Stale data is acceptable.
- If an entity meets these conditions and is used frequently in logic, make it persistable.
- Otherwise, remove the association from the non-persistable entity to System.User/System.Session.
