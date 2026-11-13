---
title: System.ShowHomePage applies entity access by default from Studio Pro 11 (breaking change)
topic: security
kind: pitfall
applies_to: general
versions: "11+"
keywords: [ShowHomePage, System module, Apply entity access, breaking change, Studio Pro 11 upgrade, upgrading from 10 to 11, secure default]
sources:
  - {title: "Security", url: "https://docs.mendix.com/refguide/security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**Symptom**
After upgrading from Studio Pro 10 to 11, logic that uses **System.ShowHomePage**, for example by calling it from another microflow, now runs with entity access restrictions.

**Root cause**
From Studio Pro 11, the ShowHomePage microflow enforces a secure default. Entity access is applied and restricted by default. This is a documented breaking change.

**Fix**
See the section "Using the ShowHomePage Microflow in the System Module" in *Upgrading from Mendix Studio Pro 10 to 11*. This source gives no fix steps.

**Status**
The Security page documents this as a breaking change introduced in Studio Pro 11. It gives no fix steps.
