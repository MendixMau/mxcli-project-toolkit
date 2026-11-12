---
title: CORS settings for published REST services
topic: rest-integration
kind: reference
applies_to: general
versions: "any"
keywords: [CORS, Enable CORS, allowed origins, max age, allow credentials, cross-origin, browser blocked, published REST, origin constant]
sources:
  - {title: "CORS Settings for Published REST Services", url: "https://docs.mendix.com/refguide/cors-settings/", author: "unknown", date: "2026-09-25"}
  - {title: "Published REST Service", url: "https://docs.mendix.com/refguide/published-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
Check **Enable CORS** when websites other than your own must call the service. Then open **Settings**:

| Setting | Meaning |
|---|---|
| Allowed origins | A constant holding a comma-separated list of origins: protocol + host + optional port, for example `http://example.com:8080`. Use `*` only for public services without authentication. |
| Max age | How long browsers cache the CORS settings. Longer means fewer requests, but changes reach browsers only after this time has passed. |
| Allow credentials | Lets the browser send cookies, authorization headers and/or client certificates |
