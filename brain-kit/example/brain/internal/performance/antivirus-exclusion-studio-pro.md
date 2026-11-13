---
title: Exclude the app folder from antivirus scanning to speed up Studio Pro
topic: performance
kind: procedure
applies_to: general
versions: "any"
keywords: [Studio Pro slow, antivirus, Microsoft Defender, exclusion, Exclude Folder, app folder, studiopro.exe, notification, Preferences Advanced]
sources:
  - {title: "Antivirus Exclusion", url: "https://docs.mendix.com/refguide/antivirus-exclusion/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
**When**
- Studio Pro is slow and antivirus software (for example Microsoft Defender) is running.

**Steps**
1. Load the app.
2. Click **Exclude Folder** in the notification. This requires administrator privileges.
3. A confirmation or failure pop-up follows.
4. For other antivirus products, add the app folder (or the folder holding all your apps) as an exclusion, following that product's documentation.

**Checks**
- The confirmation pop-up appears.

**Watch out**
- Exclude only app directories you trust.
- Do not add `studiopro.exe` to ignored processes. Studio Pro uses subprocesses and tools that this would not cover, so exclude the folder instead.
- The notification only means antivirus software is running on the machine. It does not confirm that the folder is actually being scanned.
- To disable the notification: **Edit** > **Preferences** > **Advanced** > **Antivirus exclusion** > **Do not show antivirus exclusion notifications**.
