# Seeded fault format (faults.jsonl, one JSON object per line)

(Blind set `blind-2026-10-08.jsonl` was authored by a separate agent that never saw the rules or the layers. Rule authors must not edit it; add a new dated file instead.)

{"id": "F01",
 "app": "forms19",                      # an app dir name under one of the --apps-root folders
 "doc": "Module.DocumentName",          # the model document to change (qualified name)
 "op": "set" | "delete" | "replace_text",
 "path": "Attributes[Name=Qty]/Value/DefaultValue",  # path inside the document's data: keys separated by "/",
                                        # list elements selected by [Key=Value] (e.g. ObjectCollection/Objects[Caption=Save])
 "value": <any JSON>,                   # for "set"
 "find": "text", "replace": "text",     # for "replace_text": exact substring in any string under path
 "symptom": "what a user or the data would show",
 "why_plausible": "how a version upgrade or an automated repair could cause this",
 "unchanged_doc": true|false}           # true when the doc is one an upgrade would NOT normally have touched
