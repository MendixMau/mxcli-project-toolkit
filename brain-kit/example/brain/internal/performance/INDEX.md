# performance: notes

slow pages and microflows, query and retrieve performance, best-practice recommender rules, performance tooling

Generated 2026-11-04 by opus; every note is draft-unreviewed until a person reviews it.

- [[calculated-attributes-slow-retrieves]] pitfall, any: page or retrieve slow because calculated attributes run every time (MXP001/MXP002)
- [[commit-lists-outside-loops]] practice, any: commit inside a loop, use a list commit after the loop (MXP004/MXP005)
- [[batch-large-operations-memory]] procedure, any: big operation gets slower, memory grows, batch with a counter and clear the list
- [[commit-once-and-late]] practice, any: repeated commits, locks and long transactions (MXP012/MXP014)
- [[index-xpath-and-sort-attributes]] practice, any: missing index on XPath, sort order or OData key (MXP003/MXP007/MXP016)
- [[index-design-rules]] reference, any: how many index attributes, which order, startsWith vs contains
- [[xpath-ordering-and-negation]] practice, any: slow XPath with not(), contains, and part order (MXP015)
- [[access-rules-performance]] pitfall, any: duplicated or negating access rules make slow SQL (MXP010/MXP013)
- [[inheritance-levels-performance]] practice, any: deep generalization/specialization makes slow queries (MXP009)
- [[domain-model-associations-performance]] practice, any: reference sets, multiple or temporary associations, event handlers
- [[cache-only-persistable-data]] practice, any: non-persistable entity linked to System.Session/User (MXP008)
- [[convert-microflow-to-nanoflow]] procedure, any: avoid server round trip by converting to a nanoflow (MXP006)
- [[nested-views-and-too-many-loads]] pitfall, any: page fires many retrieves, nested list/data views (MXP011)
- [[dropdown-search-filter-constraint]] practice, any: slow data grid drop-down filter on associated attribute
- [[retrieve-patterns-in-microflows]] practice, any: retrieve in loop, count optimization, retrieve over association
- [[refresh-in-client-slows-commits]] pitfall, any: bulk commit slow due to Refresh in client
- [[diagnose-slow-ui-vs-microflow]] procedure, any: slow page triage with browser devtools and the debugger
- [[time-microflows-with-log-messages]] procedure, any: measure microflow duration, TimeMeasureStart/End
- [[log-slow-queries-logminduration]] procedure, any: log queries slower than N ms
- [[async-work-and-user-feedback]] practice, any: user waits on email/integration, use background work or a task queue
- [[misc-runtime-performance-tips]] reference, any: SSHA256 vs BCrypt, schema validation, sub-transactions, proxy server
- [[antivirus-exclusion-studio-pro]] procedure, any: Studio Pro slow due to Defender/antivirus scanning
- [[new-relic-apm-setup]] procedure, any: New Relic javaagent on-premises, Cloud Foundry or Studio Pro
- [[best-practice-recommender-performance-rules]] reference, any: what MXP001 to MXP016 mean

## Gaps

- Index threshold conflict:
  - BPR says index at 10000 or more records.
  - The community page says more than 100 records.
  - Unresolved. Notes state both and treat the BPR figure as the official rule threshold.
- XPath ordering conflict:
  - The community page says clause ordering is reportedly no longer needed on modern PostgreSQL.
  - BPR MXP015 still recommends it.
  - No database- or version-specific evidence is given.
- LogMinDurationQuery: default value and log node name are not given.
- Mendix Cloud: no APM or monitoring alternative is described, since New Relic is unsupported there. Server monitoring graphs are mentioned only in passing.
- Versions: no Studio Pro or runtime version bounds are given for any rule, or for when the BPR rules were introduced.
- The batch retrieve example exists only as an image. The exact activity configuration (offset, amount, sort) is not in the text.
- No guidance on load testing, query plan analysis or database-specific tuning. The community page mentions load testing but scopes it out.
- Write-intensive entities: no concrete guidance, although the source says "totally different best practices apply".
