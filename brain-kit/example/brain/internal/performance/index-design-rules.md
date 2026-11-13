---
title: How to design Mendix database indexes (community rules)
topic: performance
kind: reference
applies_to: general
versions: "any"
keywords: [index design, composite index, selective attribute, startsWith, contains, endsWith, index scan, full table scan, sort clause, number of index attributes]
sources:
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Rule | Detail |
|---|---|
| Quantity | Create as many indexes as needed. Inserts, updates and deletes get a bit slower, but queries benefit a lot. |
| Purpose | Mendix retrieves full objects, so an index serves two purposes: finding IDs fast and sorting. |
| Coverage | Cover the search and sort clauses, preferably in one index. |
| Duplicates | Do not create multiple indexes that start with the same attributes. |
| Size | Minimize the number of attributes. Stay below 3, maximum 5. |
| Order | Put the most selective attribute first. A search on a single attribute can only use indexes that start with that attribute. |
| Best fit | Equality searches, date/number range searches, and leading `startsWith` string searches. |
| Partial fit | `contains` and `endsWith` can use index scans, which are still faster than full table scans. |

When to index: see [[index-xpath-and-sort-attributes]].
