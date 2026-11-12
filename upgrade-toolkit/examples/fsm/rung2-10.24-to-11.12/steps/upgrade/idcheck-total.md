# idcheck <run>/original.mpr (mpr) -> <app>/app.mpr (mpr)

elements old: 262 entities, 1253 attributes, 248 associations
elements new: 263 entities, 1255 attributes, 248 associations
findings: 0 total, 0 RED (data-bearing), 0 of them approved, 0 open


warn MODULE_RECREATED Atlas_Core: all 48 unit ids new (55 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED Atlas_Web_Content: all 144 unit ids new (148 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED Logging: all 39 unit ids new (39 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED NanoflowCommons: all 58 unit ids new (59 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED NativeMobileResources: all 51 unit ids new (51 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED ValidationFeedback: all 9 unit ids new (9 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)

verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is intended, then add it to the approved list / allow-list)
