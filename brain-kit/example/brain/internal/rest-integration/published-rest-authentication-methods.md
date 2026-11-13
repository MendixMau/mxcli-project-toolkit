---
title: Authentication options for published REST services and the order they are tried
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [published REST authentication, basic authentication, active session, X-Csrf-Token, getCSRFToken, custom authentication, anonymous users, web service users, allowed roles, offline-first]
sources:
  - {title: "Published REST Service", url: "https://docs.mendix.com/refguide/published-rest-service/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Services", url: "https://docs.mendix.com/refguide/published-rest-services/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Method | How the client authenticates | Notes |
|---|---|---|
| Username and password | Basic auth in the `Authorization` header | |
| Active session | The current browser session, from JavaScript in the same app | Set `X-Csrf-Token` on every request (`import getCSRFToken from "mx-api/session"`). Not usable by offline-first apps. |
| Custom | A microflow, called on every request | See [[published-rest-custom-authentication-microflow]] |

- When several methods are checked, they are tried in this order: **Custom**, then **Username and password**, then **Active session**.
- Basic and active session are the defaults when the security level is Prototype/demo or Production.
- **Requires authentication = No** turns authentication off per service.
- Anonymous access works when anonymous users are allowed, the anonymous role is in the allowed roles, and Username and password is selected.
- Allowed roles (module roles) are only available when authentication is required.
- **Web service users cannot access REST services.**
