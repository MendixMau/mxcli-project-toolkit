---
title: Version published REST services by duplicating, never by changing a live service
topic: rest-integration
kind: practice
applies_to: general
versions: "any"
keywords: [REST versioning, breaking change, semantic versioning, MAJOR.MINOR.PATCH, deprecated, duplicate service, v2, location version, message definition change]
sources:
  - {title: "Version a REST Service", url: "https://docs.mendix.com/refguide/version-rest-service/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Rule**
Do not change a published service that clients use. For incompatible changes, duplicate the service under a new major version.

**Why**
A breaking change makes clients get errors without them doing anything different.

**How to apply**
- Version bumps:
  - MAJOR for incompatible changes, such as removing an operation or changing an attribute type.
  - MINOR for backwards-compatible additions, such as a new operation.
  - PATCH for compatible bug fixes.
- For MINOR and PATCH changes, the source allows either a new version or changing the current one.
- Use one folder per version, named `ServiceName_Version`. Keep that version's microflows, mappings and message definitions in it.
- Duplicate any microflow, mapping or message definition you change, and change the duplicate. Reuse unchanged ones.
- Put the version in the location, for example `rest/myservice/v1.1`. Omit `.0` / `.0.0`.
- Deprecate the old version:
  - Add "(deprecated)" to its name.
  - Explain why and name the new version in the public documentation.
  - Mark the changed operations as deprecated.
  - Tell users, for example in release notes.
- Remove the old version after a sufficiently long time.
