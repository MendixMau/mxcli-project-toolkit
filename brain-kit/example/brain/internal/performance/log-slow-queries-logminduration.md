---
title: Log slow OQL/XPath queries with the LogMinDurationQuery custom setting
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: [LogMinDurationQuery, custom setting, slow query, slow database query, OQL, XPath, query logging, milliseconds, slow commit]
sources:
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- You need to find which database retrieves or commits (OQL and XPath) are slow.

**Steps**
1. Set the custom setting `LogMinDurationQuery` to a threshold in milliseconds. The source's debugging example is `500`.
2. Run the app. Retrieves and commits that take longer than the threshold are logged.

**Checks**
- The logged queries point to the entities and constraints to optimize. See [[index-xpath-and-sort-attributes]] and [[xpath-ordering-and-negation]].

**Watch out**
- The source presents this setting for debugging purposes.
- It does not state the default value.
