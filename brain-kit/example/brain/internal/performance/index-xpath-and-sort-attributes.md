---
title: Index attributes used in XPath constraints, sort orders and OData keys on read-intensive entities (MXP003, MXP007, MXP016)
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [index, MXP003, MXP007, MXP016, XPath, sort order, data grid sort, OData key, read-intensive, slow query, missing index]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- On read-intensive entities, add indexes on the attributes in these three cases:
  - Attributes used in XPath expressions (MXP007).
  - Attributes used as sort items in sort orders (MXP003). This covers data grids, template grids and reference set selectors.
  - The single key attribute of an entity published in OData (MXP016).
- Read-intensive means selects far outnumber create, update and delete operations.

**Why**
- Indexes can significantly speed up retrieval and sorting.
- On write-intensive entities, different practices apply.
- Missing indexes are a listed cause of slow retrieve actions.

**How to apply**
- For MXP007 and MXP016, first check that the entity has a substantial number of records. The BPR threshold is at least 10000.
- Do not index Boolean or enumeration attributes. They have too few distinct values to benefit.
- XPath appears in access rules, page sources/filters, and retrieves in microflows and Java actions. Check all of them.
- Threshold conflict:
  - BPR says at least 10000 records.
  - The community page says to index entities that will get more than 100 records and are searched by anything other than references/IDs.
  - The sources do not say which threshold takes precedence.
- Index design: see [[index-design-rules]].
