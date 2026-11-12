---
title: Strict page URL checking covers custom page URLs but not Deep Link module links
topic: security
kind: pitfall
applies_to: general
versions: "any"
keywords: [Strict page URL checking, page URL, deep link, Deep Link module, consistency error, entity access on page, custom URL]
sources:
  - {title: "App Security", url: "https://docs.mendix.com/refguide/app-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
Security problems on a page that is reachable only by URL produce no consistency errors in Studio Pro while **Strict page URL checking** is disabled.

**Root cause**
- With **Strict page URL checking** disabled, page security (such as entity access) is checked only for pages reachable through navigation, pages or microflows.
- With it enabled, pages reachable only via a page URL also produce consistency errors for security problems. This works for pages with custom URLs.
- It cannot be applied to [Deep Link](https://docs.mendix.com/appstore/modules/deep-link/) module links. Those are configured in the Mendix Runtime, so Studio Pro cannot tell which pages they use.

**Fix**
- Keep the setting enabled. It is on by default in new apps and is available only at the Production security level.
- The source does not describe how to check the security of pages opened by deep links.

**Status**
Documented limitation in the App Security reference guide.
