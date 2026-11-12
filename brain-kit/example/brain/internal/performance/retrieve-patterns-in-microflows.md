---
title: 'Retrieve efficiently in microflows: before loops, over associations, with aggregate optimization'
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: ["retrieve in loop", "many retrieves", "retrieve over association", "aggregate", "count", "retrieve + aggregate optimization", "nested loops", "find in list", "slow microflow"]
sources:
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Avoid retrieves inside loops.
- Avoid unnecessary retrieves.
- Use the optimizations Mendix provides.

**Why**
- Multiple retrieves, especially in loops, are a common cause of slow microflows.
- Nested loops make execution time escalate quickly.

**How to apply**
- Retrieve all needed data before the loop, then use find operations on that list inside the loop.
- If the loop contains decisions, try to move the decision logic into a query before the loop, to reduce iterations.
- Pass objects or lists as parameters instead of retrieving them again.
- Retrieve + aggregate: retrieving a list and only counting it is optimized into one query.
  - If you need the list later, after some decisions, retrieve it again there.
- Retrieve over association where possible.
  - You get the latest version, including uncommitted changes held in memory.
  - Use a database retrieve only when you need the stored value.
- For nested loops, consider whether an extra entity, attribute or association, or an XPath query, removes the search loop.
- Check retrieved entities for calculated attributes. See [[calculated-attributes-slow-retrieves]].
