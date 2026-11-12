# security: notes

app and module security, user roles, access rules, entity access, anonymous users, password policy, security headers

Generated 2026-11-04 by opus; every note is draft-unreviewed until a person reviews it.

- [[user-role-changes-not-applied-to-signed-in-users]] pitfall, versions any: changed a user's role but they still see old pages or data
- [[user-roles-are-built-from-module-roles]] practice, versions any: how user roles combine module roles; always include System.User
- [[manageable-roles-select-all-auto-grants-new-roles]] pitfall, versions any: "Select all" manageable roles silently grants new roles
- [[manageable-roles-what-can-be-managed]] reference, versions any: who a SubAdministrator can manage and which fields they can edit
- [[user-management-rules-ignored-with-apply-entity-access]] pitfall, versions any: implicit System.User rules ignored when a microflow applies entity access
- [[password-policy-settings]] reference, versions any: minimum length, digit, mixed case, symbol list
- [[page-access-does-not-protect-data]] pitfall, versions any: hidden page still opens via deep link or forced button
- [[microflow-allowed-roles-only-checked-from-client]] pitfall, versions any: sub-microflows skip the role check
- [[module-security-access-tabs]] reference, versions any: page, microflow, nanoflow, entity, OData, REST and dataset access matrices
- [[security-levels-and-cloud-requirement]] reference, versions any: Off, Prototype or Production; licensed cloud needs Production
- [[strict-page-url-checking-skips-deep-links]] pitfall, versions any: URL-only pages are checked, Deep Link module pages are not
- [[strict-mode-restricted-client-apis]] reference, versions any: React strict mode blocks data.create, commit, remove and more
- [[strict-mode-breaks-widgets-and-layout-buttons]] pitfall, versions any: File Uploader delete, Take picture and layout save buttons fail
- [[anonymous-users-setup]] practice, versions any: allow anonymous users safely; name the role Anonymous
- [[administrator-default-credentials]] pitfall, versions any: MxAdmin / 1 defaults; model password applies only locally
- [[admin-role-change-needs-password-change]] pitfall, versions any: admin role change not applied in cloud until password reset
- [[free-app-admin-access]] procedure, versions any: no MxAdmin in a Free App; use a snapshot or a demo admin
- [[demo-users-persist-after-disabling]] pitfall, versions any: demo users can still log in after you disable them
- [[security-overview-review-and-export]] procedure, versions any: review combined access per role; export to Excel or JSON
- [[showhomepage-entity-access-studio-pro-11]] pitfall, versions 11+: ShowHomePage now applies entity access after upgrade
- [[authentication-options]] reference, versions any: local, Mendix SSO, SAML, OIDC, XSUAA; no virus scanning

## Gaps

- **Security headers:** no source covers them (HTTP headers, CSP, HSTS, X-Frame-Options, Runtime custom headers), although they are in the topic.
- **Access rules:** the details of XPath constraints, member access and default rights are not covered in depth. The Access Rules page itself is missing.
- **Password policy:** no default values are given. It is unknown whether changing the policy affects existing passwords.
- **Session revalidation:** no interval or trigger is given for when role changes take effect.
- **Implicit System.User rules:** no recommended explicit rules are given to replace them under Apply entity access.
- **Take picture in strict mode:** no workaround is given.
- **Strict mode versions:** no Studio Pro version is given for when strict mode became available.
- **ShowHomePage change:** the details of the Studio Pro 11 change are referenced but not included.
- **Removing demo users:** there is no procedure for removing demo users that are left in the database.
- **Security Overview export:** the doc announces three Excel sheets but lists four. This could not be resolved from the sources.
- **Security best practices:** the best-practices how-to is referenced but not provided. This covers access control, anonymous roles and file scanning.
