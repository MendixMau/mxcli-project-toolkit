---
title: Published REST service location, reserved prefixes, OpenAPI export and logging
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [published REST location, rest/ prefix, reserved prefixes, api-doc, xas, rest-doc, openapi.json, swagger.json, REST Publish log node, version 1.0.0]
sources:
  - {title: "Published REST Service", url: "https://docs.mendix.com/refguide/published-rest-service/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Services", url: "https://docs.mendix.com/refguide/published-rest-services/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Item | Detail |
|---|---|
| Default location | `rest/<service_name>/v1`. Spaces and special characters become `_`. |
| Reserved prefixes | `api-doc/`, `xas/`, `p/`, `reload/` cannot start a location |
| Version field | Any string. Default `1.0.0`. Semantic versioning is recommended. |
| Interactive docs | `/rest-doc/` in the running app (Swagger UI) |
| Machine-readable files | `/rest-doc/{location}/openapi.json` (OpenAPI 3.0) and `/rest-doc/{location}/swagger.json` (OpenAPI 2.0) |
| Export from Studio Pro | Right-click the service in the App Explorer, then **Export openapi.json** or **Export swagger.json** (the UI varies by version) |
| Logging | Set the **REST Publish** log node to **Trace** |

Resource and operation paths are appended to the location.

Status: documented in the Mendix reference guide; not verified in a running app.
