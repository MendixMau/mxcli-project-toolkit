---
title: 'Flatten and simplify structure" changes the entities created from a REST response'
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: ["Flatten and simplify structure", "Create entity", "response structure", "Consumed REST Service", "fewer entities", "wrapper object", "JSON response entities"]
sources:
  - {title: "Consumed REST Service", url: "https://docs.mendix.com/refguide/consumed-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Setting | Effect |
|---|---|
| Flatten and simplify structure ON (default) | The JSON is simplified where possible. Example: an object with a `Results` list gives 2 entities instead of 3, with all data kept. |
| OFF | The entities mirror the full JSON nesting |

- Clear the checkbox on the **Response structure** tab **before** clicking **Create entity**.
- Entity names are prefilled and can be renamed.
