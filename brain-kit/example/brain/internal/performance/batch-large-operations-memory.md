---
title: Process large object volumes in batches to keep memory and runtime low
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: [batch, batching, memory, large commit list, 10k objects, counter variable, Change list Clear, Delete object(s), out of memory, slow big operation]
sources:
  - {title: "Recommendations from Best Practice Recommender", url: "https://docs.mendix.com/refguide/performance-best-practices/", author: "unknown", date: "2026-09-25"}
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
  - {title: "Detect and Resolve Performance Issues", url: "https://docs.mendix.com/refguide/detect-and-resolve-performance-issues/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- A microflow gets slower as the operation gets bigger. Something is probably being kept in memory.
- Example from the source: a commit list grows past 10k objects.
- You commit or delete thousands of rows.

**Steps**
1. Create an Integer/Long variable to use as a counter.
2. In the loop, add each object to `<Entity>_CommitList` (or `<Entity>_DeleteList`) and increment the counter.
3. When the counter hits the batch size, run **Commit object(s)** (or **Delete object(s)**) on the list. The BPR advice uses 1000 objects.
4. After a commit, clear `<Entity>_CommitList` with a **Change list** > **Clear** activity.
5. Retrieves can be batched the same way: retrieve the total count with an optimized aggregate, then retrieve chunks in separate queries. See [[retrieve-patterns-in-microflows]].
6. Consider running the whole task asynchronously. See [[async-work-and-user-feedback]].

**Checks**
- Memory stays flat during the run.
- Commits happen per batch, not per object.

**Watch out**
- Delete object(s) clears `<Entity>_DeleteList` automatically.
- The commit list is not cleared for you.
- Committing one by one frees memory but is slow. Batching gives both good performance and low memory.
