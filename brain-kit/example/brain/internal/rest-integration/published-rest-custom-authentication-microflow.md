---
title: 'Custom authentication microflow for published REST: parameters and outcomes'
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: ["custom authentication microflow", "published REST", "return User", "404 Not Found", "HttpResponse status code", "header parameter", "query parameter", "Authentication microflow arguments", "API key"]
sources:
  - {title: "Published REST Service", url: "https://docs.mendix.com/refguide/published-rest-service/", author: "unknown", date: "2026-09-25"}
  - {title: "Custom Authentication Microflow Parameters", url: "https://docs.mendix.com/refguide/published-rest-authentication-parameter/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Inputs**
- Click **Parameters** next to the microflow and add every microflow parameter there.
- Each parameter comes from **Query** or **Header**. A header parameter takes the first request header with that name.
- Only primitive types are supported. Always select the target microflow parameter.
- The microflow may also take `HttpRequest` (to inspect the request) and `HttpResponse`.

**Outcomes**

| Microflow result | What happens |
|---|---|
| `HttpResponse.StatusCode` set to something other than 200 | That status and any headers set are returned. The operation is not executed. |
| Non-empty User returned | The operation runs in that user's context |
| Empty User returned | The next authentication method is tried. If there is none: **404 Not Found**. |

The microflow is called every time a resource is accessed. Custom authentication is tried before basic and active session.
