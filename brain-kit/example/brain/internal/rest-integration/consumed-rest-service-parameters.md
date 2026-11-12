---
title: Parameters, query parameters, dynamic base URL and body in Consumed REST Service
topic: rest-integration
kind: reference
applies_to: general
versions: "11.1 and above for query parameters table; otherwise any"
keywords: [Consumed REST Service, curly brackets parameter, query parameters, dynamic base URL, request body, Use JSON Snippet, Send REST request, test value, Required]
sources:
  - {title: "Consumed REST Service", url: "https://docs.mendix.com/refguide/consumed-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Feature | Detail |
|---|---|
| Parameters | `{name}` in the URL path or query, header values, or body. Each is added to the parameters grid automatically. The test value is replaced at runtime by the value set in the Send REST request activity. |
| Base URL | Shared by all requests in the document. Set **Dynamic = Yes** to turn it into a parameter you set in the activity. |
| Query parameters table | Studio Pro 11.1+. New entries default to **Required**. A checkbox includes or excludes each one. `{}` parameters are not supported in this table. |
| Body | POST, PUT and PATCH only. Static text, or text with `{param}`. For JSON, click **Use JSON Snippet**, then **Create Entity**, to build body entities. |
| Response JSON | **Response structure**, then **Create Entity**. See [[consumed-rest-flatten-simplify]]. |

Conflict: the Limitations section says "You cannot configure parameters in the Query Parameters tab". The 11.1 section documents a Query Parameters table in which `{}` parameters are not supported. The likely reading is that the Query Parameters table does not accept `{}` parameters, but the source is unclear.
