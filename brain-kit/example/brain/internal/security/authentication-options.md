---
title: Authentication options for Mendix apps (local, Mendix SSO, SAML, OIDC, XSUAA)
topic: security
kind: reference
applies_to: general
versions: "any"
keywords: [authentication, SSO, SAML, OIDC SSO, Mendix SSO, XSUAA, ADFS, MFA, Administration module, identity provider, local users]
sources:
  - {title: "Security", url: "https://docs.mendix.com/refguide/security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Approach | Module | Notes |
|---|---|---|
| Local | Administration module (in starter apps by default) | Users and passwords stored in the app. Marketplace modules can add MFA |
| Mendix Identity Provider | Mendix SSO | Users sign in with Mendix credentials. Default for developers deploying to Mendix Cloud |
| SAML 2.0 IdP | SAML (platform-supported) | Works with any SAML 2.0 IdP, for example ADFS for on-premises Active Directory |
| OAuth / OIDC IdP | OIDC SSO (platform-supported) | Also authenticates to APIs. Can grant roles automatically from the corporate IdP |
| SAP BTP | XSUAA connector | SSO with SAP's IdP |

**Not covered by Mendix app security**
- Virus and malware scanning of uploaded or downloaded files. See *Scanning Uploaded Files for Malicious Content* in the security best practices.
- Team (developer) roles. These are managed in Projects and are separate from end-user roles.
