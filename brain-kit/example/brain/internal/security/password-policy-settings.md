---
title: Password policy settings and the characters that count as symbols
topic: security
kind: reference
applies_to: general
versions: "any"
keywords: [password policy, minimum length, require digit, require mixed case, require symbol, password requirements, special characters, App Security]
sources:
  - {title: "Password Policy", url: "https://docs.mendix.com/refguide/password-policy/", author: "unknown", date: "2026-09-25"}
  - {title: "App Security", url: "https://docs.mendix.com/refguide/app-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
Location: **App Security** > **Password policy** tab.

The policy applies when you create new users and when existing users change their password. It is available at the Prototype/demo and Production security levels.

| Property | Effect |
|---|---|
| Minimum length | Minimum password length |
| Require digit | At least one digit |
| Require mixed case | At least one lowercase and one uppercase character |
| Require symbol | At least one of: `` ` ~ ! @ # $ % ^ & * ( ) - _ = + [ { ] } \ `` |

The source does not state the default values.

The source says the policy applies on create or change. It does not say whether existing passwords are re-validated when the policy changes.
