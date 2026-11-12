# idcheck <run>/original.mpr (mpr) -> <app>/app.mpr (mpr)

elements old: 260 entities, 1241 attributes, 248 associations
elements new: 262 entities, 1253 attributes, 248 associations
findings: 0 total, 0 RED (data-bearing), 0 of them approved, 0 open


warn MODULE_RECREATED Atlas_Core: all 42 unit ids new (48 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED Atlas_NativeMobile_Content: all 70 unit ids new (70 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED Atlas_Web_Content: all 141 unit ids new (144 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED CommunityCommons: all 125 unit ids new (128 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED DeepLink: all 88 unit ids new (86 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED JWT: all 30 unit ids new (31 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED Logging: all 27 unit ids new (39 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED ObjectHandling: all 30 unit ids new (30 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)
warn MODULE_RECREATED ValidationFeedback: all 9 unit ids new (9 units now): the module was deleted and imported again, not updated in place; documents that use it (pages, snippets) were rewritten too: review them, or redo the update with Studio Pro's module update (NS-7)

verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is intended, then add it to the approved list / allow-list)
