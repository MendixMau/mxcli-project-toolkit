---
title: Web service, XML, OQL and infrastructure performance tips
topic: performance
kind: reference
applies_to: general
versions: "any"
keywords: [SSHA256, BCrypt, schema validation, sub-transactions, OQL security, web server proxy, static content, compression, App Engines, Mendix Cloud]
sources:
  - {title: "Community Best Practices for App Performance", url: "https://docs.mendix.com/refguide/community-best-practices-for-app-performance/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Area | Tip |
|---|---|
| Hashing | Use SSHA256 instead of BCrypt, except for password hashing. |
| XML | Validating against a schema slows processing. |
| Microflows | Sub-transactions slow processing. |
| OQL | XPath best practices largely apply. OQL gets no domain model security, so add tenant/security clauses yourself where needed. |
| Infrastructure | Get better infrastructure, for example more App Engines in Mendix Cloud. |
| On premises | Put a proxying web server in front of Mendix to serve static content and compress data. |
