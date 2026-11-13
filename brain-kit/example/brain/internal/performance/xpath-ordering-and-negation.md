---
title: Order XPath parts cheapest and most specific first; avoid not() and unequal clauses (MXP015)
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: ["XPath", "MXP015", "not()", "contains", "and", "predicate order", "slow XPath", "PostgreSQL query optimizer", "unequal", "!="]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Put the cheapest and most specific parts to the left of each `and`, and first in a predicate sequence `[part 1][part 2]`.
- Avoid `not()` and unequal clauses where possible.

**Why**
- From about 100,000 items, place these to the right of `and`:
  - `not()`
  - `contains(unlimited-string-attribute)`
  - `not(association)`
- With millions of items, putting more specific steps first means less work for the database.
  - "Specific" refers to association steps: a part that uses an association is more specific than a direct attribute part.
- Using indexed attributes early lets the first clause exclude as many rows as possible (MXP007 text).

**How to apply**
- Rearrange the XPath parts or predicates accordingly.
- Rewrite negations as positive statements, for example:
  - `<boolean>=false()`
  - `<enumeration> = valueA`
  - `integer>valueA`
- Combine paths to the same associated entity where the query logic allows.
- Make sure the attributes you use are indexed.

**Conflict**
- The community page says the "attributes first" rule mattered for older PostgreSQL, whose optimizer processed clauses in order.
- It also says this rule is reportedly no longer needed.
- BPR rule MXP015 still recommends ordering.
