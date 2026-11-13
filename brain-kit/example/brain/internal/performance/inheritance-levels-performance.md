---
title: Avoid more than two levels of inheritance on large entities (MXP009)
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [inheritance, generalization, specialization, MXP009, complex query, slow query, entity access XPath, one-to-one association, enumeration]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Do not use more than two levels of inheritance.
- Do not overuse specializations on entities with substantial data, especially when using XPath entity access.

**Why**
- Each specialization's access-rule XPath is added to the query.
- This produces complex, slow queries on large datasets.

**How to apply**
- Alternatives:
  - Combine the attributes into one entity and add an enumeration for the type.
  - Use separate entities with a one-to-one association. Depending on UI needs, a plain reference from specialization to generalization can save prefetching time.
  - Use a non-persistable layer with inheritance, populated by business logic.
