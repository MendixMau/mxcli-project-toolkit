---
title: Commit lists after the loop, not objects inside it (MXP004, MXP005)
topic: performance
kind: practice
applies_to: general
versions: "any"
keywords: [commit in loop, MXP004, MXP005, batch commit, Create object, Change object, Commit object(s), list commit, slow microflow, CommitList]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
- Do not commit objects inside a loop, whether through Create object, Change object or Commit.
- Collect the objects in a list and commit the list once after the loop.
- Apply the same approach to deletes.

**Why**
- A list commit reuses the JDBC prepared statement. The execution plan is cached and network overhead stays minimal.
- Each separate data-changing action adds overhead:
  - A savepoint is created and released.
  - Autocommitted objects are retrieved from the database.
  - Autocommitted objects are stored, if relevant.

**How to apply**
- MXP004: on the Create/Change object activity in the loop, set **Commit** to No, and add the object to a list.
- MXP005: move the Commit activity out of the loop and commit the list.
- Commit the list in two cases:
  - When the loop finishes.
  - When the list reaches 1000 objects, to avoid excessive memory use.
- Community naming convention: create `<Entity>_CommitList` or `<Entity>_DeleteList` before the loop.
- For large volumes, see [[batch-large-operations-memory]].
