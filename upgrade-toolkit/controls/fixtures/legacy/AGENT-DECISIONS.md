# Agent decisions, shopfront run (unattended, nothing signed)

Decided by the agent as the developer would. The pipeline records them as ASSUMED (unattended).

| # | Decision | Choice | Why |
|---|---|---|---|
| D1 | Gridmod 1.4.0 -> 2.0.0 -> 2.3.0 | UPDATE in two steps | Version 1 does not load on the new client. |
| D2 | Themepack: 4 deleted style files | UPDATE, then delete the 4 files again (replay commit) | Keeps today's look. |
| D3 (agent) | jQuery scripts moved into JavaScript actions | Every script now runs from a JavaScript action that starts when the page loads, instead of being rewritten as widgets | Same behaviour as today at the lowest cost. Rewriting 12 scripts as widgets takes days. |
| D3a (agent) | Last 2 snippets that the check did not flag | Moved by the same method | Found by scanning every page. |
| D4 (agent) | OPEN: cart page carousel swapped | Options: (1) swap for the new carousel, same buttons (recommended), (2) keep the old carousel | Choice still needs the app owner's OK. |
| D5 (agent) | Two stale script tags in index.html | Removed (app commit c18ecc3) | The files do not exist and gave a 404 on the old app too. |
| D6 (agent) | mx check is 0 errors, but mxbuild fails on Java compile: 19 errors in Cart_Util.java | Retried twice, same result | Tool output only, nothing was decided. |
| D7 (agent) | Cart_Util.java calls the removed cart API | Options: (1) update Cartkit to 3.0.0 (recommended), (2) patch Cart_Util.java by hand | The shop owner pays for a hand patch on every upgrade. |
