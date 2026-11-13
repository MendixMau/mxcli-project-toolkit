---
title: Review effective access per user role with the Security Overview and export it
topic: security
kind: procedure
applies_to: general
versions: "any"
keywords: [Security Overview, Show Security Overview, combined access rules, Export to Excel, export-security-overview, mx command line, security audit, effective permissions]
sources:
  - {title: "Security Overview", url: "https://docs.mendix.com/refguide/security-overview/", author: "unknown", date: "2026-09-25"}
  - {title: "Security", url: "https://docs.mendix.com/refguide/security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
You want to review or audit what a user role can actually access at runtime. Requires the **Production** security level.

**Steps**
1. Open **App** menu > **Show Security Overview**.
2. Pick a role in **Show access for user role**. The anonymous and administrator roles are marked `(Anonymous)` and `(Administrator)`.
3. Optionally pick a module in the sidebar. The System module and protected modules are not listed.
4. Review the **Entity access**, **Page access**, **Microflow access** and **Nanoflow access** tabs.
5. Click **Export to Excel**. Sheets: Members Access, Entity Access, Document Access, Module Roles.
6. For automation, use `mx export-security-overview` to export JSON or xlsx.

**Checks**
- **Combined access rules** is the union of all rules for the role. Example: Read+Create plus ReadWrite gives ReadWrite + Create.
- Rules with the same XPath constraint are merged, and each distinct XPath gets its own column.

**Watch out**
- An entity, attribute or association the role cannot access is left out of the table entirely. It is not shown as "None".
- The docs announce three Excel sheets but then list four.
