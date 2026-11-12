# Public templates holding the HTML/JavaScript Snippet widgets or the OIDC module (searched 2026-10-23)

How: the Marketplace catalogue of 2026-10 (types Sample, Starter App, Industry Template, Solution; not private; with a download link) gave
138 downloadable apps after the already-used ones were left out; 136 were downloaded one at a time, the `.mpk` unzipped in memory, and the
`.mpr` bytes searched for the widget ids and the module name (2 downloads failed). Every archive was deleted after the look. Byte counts
over-count (a widget id appears more than once per widget); the rows marked **verified** were then opened with `bin/mprmodel.py` and the
counts are widget objects. Apps are named by Marketplace content id.

## HTML / JavaScript Snippet (HTMLSnippet.widget.HTMLSnippet, snippetjs.widget.snippetjs)

| app (content id) | app version | min Mendix | snippet widgets | snippetjs | Template Grid | note |
|---|---|---|---|---|---|---|
| Snowflake Showcase App (225845) | 4.2.0 | 10.24.13 | **28 in 28 pages, verified** | 0 | 6 in 2 documents | all 28 have content type JavaScript, one identical 181-character script (scroll a page container to the top inside `mx.addOnLoad`), 0 jQuery; Atlas Core 3.20.0, Data Widgets 3.10.0. Best candidate: one hop 10.24 to 11.12.5 |
| Time Off Tracker (229185) | 1.1.1 | 9.24.23 | 3 in 2 documents, verified | 1 | 6 in 2 documents | also ships the Dropdown Container and a second JavaScript Snippet package; needs the 9 to 10 hop first |
| CM Demo app, send and receive SMS (104208) | 2.0.0 | 8.17.0 | 44 byte matches, not verified | 0 | not looked at | Mendix 8: out of range for the shared tools |
| Storage Management (226140) | 1.0.0 | 9.24.4 | 8 byte matches, not verified | 2 byte matches | not looked at | |
| Maintenance and Field Service Management (204718) | 1.1.1 | 9.24.2 | 4 byte matches, not verified | 2 byte matches | not looked at | the toolkit's batch-1 worker T8 ran this app |
| AtlasUI Styleguide Boilerplate (113342), Industrial Edge Data Service Development Kit (117932) | 1.0.0 | 8.0.0 / 8.18.2 | 8 byte matches each, not verified | 0 | not looked at | Mendix 8 |
| OPC UA Client example (117392), OrgChart Example (121071), Product Pricing And Promotion Manager (208640), DocDigitizer PowerCapture Connector (222363), Datagrid2 Sticky header (230152) | | 9.6.10 to 10.6.2 | 4 byte matches each, not verified | 0 | | |

DropdownDivConverter is in the package list (not verified as used on a page) of Workplace Manager (118349, 9.24.11), AtlasUI Styleguide
Boilerplate (113342) and DemoStarterApp (257332, 10.18.11). The Dropdown Container (`mendix.DropdownContainer`) is in Checklist to go
(220329), Time Off Tracker (229185), AI Bot Starter App (227926), Agent Registry (202088) and A2A Agent Connector (202543).
jQuery: none of the 28 snippets of the best candidate uses it; no other candidate was read at content level, so a real jQuery-heavy
snippet is not in this list. The jQuery fixtures are synthetic (`controls/fixtures/jquery/README`).

## OIDC module

| app (content id) | app version | min Mendix | OIDC | UserCommons | other | note |
|---|---|---|---|---|---|---|
| Altium 365 Platform Starter App (235403) | 1.0.0 | 10.15.0 | **3.1.0, verified** | 1.0.2 | Administration 4.1.0, Encryption 10.0.3, MxModelReflection 8.0.3, NanoflowCommons 4.0.4 | after-startup is already `OIDC.ASU_OIDC_Startup`; roles Administrator, User, Anonymous; userlib has nimbus-jose-jwt 9.37.3. Crosses 4.0.1/4.1.0, 4.2.0, 4.4.0 and 4.5.0. Best candidate |
| Teamcenter Connector Sample Application (111688) | 2506.0.0 | 10.20.0 | 3.1.0, verified | 1.0.2 | Administration 3.0.0, Atlas Core 3.8.3 | |
| Test Buddy (206473) | 1.0.0 | 9.18.3 | 3.3.1, verified | not in the module list | Administration 2.1.2 | |

No public template holds an OIDC below 3.0.0: the steps "UserCommons from 3.0" and "OIDC.Startup renamed in 3.1" cannot be proven on a
public template, only reasoned from the release notes. Every other app with an `oauth2-oidc-sdk` jar in userlib carries the legacy
MendixSSO module (RA-16, not this entry).

## Widget swaps for the "reconfigure" proof (looked at, not proven)

Template Grid: in the apps read (Snowflake Showcase, Time Off Tracker, Test Buddy) it occurs only inside the Atlas page templates
(`Atlas_Web_Content.SelectWithTemplateGrid_Select` and its tablet twin), never on an app page, so no swap target there. Old Charts (Mendix
charts 1.x to 3.x, widget ids `com.mendix.widget.custom.*`): Time Off Tracker (9.24.23) holds 11 on `UIResources.Charts`. Dropdown
Container: Time Off Tracker, `UIResources.Widgets_Overview` (5). DropdownDivConverter is in the package list of Workplace
Manager (118349) and DemoStarterApp (257332), use on a page not verified. None of these was converted or swapped: the screen comparison needs a
built and running old and new app, and the container had 2 GB free.
