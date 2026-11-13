---
title: Set up New Relic APM for a Mendix app (not Mendix Cloud)
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: [New Relic, APM, javaagent, newrelic.yml, m2ee.yaml, javaopts, Extra JVM parameters, Cloud Foundry buildpack, application performance monitoring]
sources:
  - {title: "Manage App Performance with New Relic", url: "https://docs.mendix.com/refguide/manage-app-performance-with-new-relic/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- You want to monitor requests and database queries of an on-premises, Cloud Foundry or local dev app.

**Steps**
1. Create a New Relic account.
2. On-premises:
   - Create a Java application in New Relic.
   - Download the Java agent archive and keep the license key.
   - Put the license key in `newrelic.yml`.
3. Cloud Foundry: follow the cf-mendix-buildpack New Relic instructions.
4. On-premises Linux/Windows service console: add `"-javaagent:<path-to-javaagent>javaagent.jar"` to `javaopts` in `m2ee.yaml`.
5. Studio Pro (development only):
   - Go to **App Explorer** > **Settings**.
   - Open a configuration and go to the **Server** tab.
   - In **Extra JVM parameters**, add `-javaagent:<path-to-javaagent>javaagent.jar`.

**Checks**
- Requests appear under Transactions in New Relic.
- Database calls and queries appear on the Databases page.

**Watch out**
- New Relic is not supported for apps deployed to Mendix Cloud.
