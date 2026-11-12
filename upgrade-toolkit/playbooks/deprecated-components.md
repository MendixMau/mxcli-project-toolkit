# Deprecated Marketplace components: triage (B6-3)

The brain's module index marks 81 components `Deprecated` (`bin/brain_mine.py`, section 1, run of 2026-10-07).
Each component was promoted into `replacements.tsv` or left out for the reason below. To rerun the triage, run
`brain_mine.py` and diff its section 1 against this list. A component missing from this list is untriaged.

Field check: the 4 local field apps plus customer (`widgets/*.mpk` and widget ids on pages) are the only evidence of use.

## Promoted

| row | components | seen in field apps |
|---|---|---|
| R25 | Language Selector | kanban, fsm, opcenter-ef, customer (mpk); hit on pages in kanban, fsm, opcenter-ef |
| R26 | Microflow Timer, Bootstrap Tooltip, List view controls, Format String, Google Maps, Radiobutton List, Checkbox set selector (Table), Simple Checkbox Set Selector, Label Selector | fsm, pfep, kanban, opcenter-ef |
| R28 | Process Queue, Deprecated - Queue, Microflow Scheduled Event Manager | none |
| R29 | Atlas UI Resources (Atlas 2) | none |
| R3, R4, R10 (already rows) | MendixSSO, Deep link module, AnyChart | MendixSSO in fsm, kanban, pfep; DeepLink in fsm |

## Left out

| reason | components |
|---|---|
| out of scope: hybrid mobile is not supported by this toolkit (decision 2026-10-07; Kanban and Opcenter EF ship MobileFeatures) | Mobile features, Barcode Scanner for Hybrid Mobile, Camera (deprecated), Hybrid Mobile Actions, Mobile Device, Pull to refresh, Tab Swipe, List view swipe |
| starter or demo app, not something an app installs | Approval App, Asset Manager App, Event App, ArcGIS - Demo Project (DEPRECATED), Atlas UI 2 Reference / Custom Styling App, Teamcenter Connector Sample Application |
| successor named, but the module name is unknown and the component was not seen in the field apps (a guessed name would report a false clear) | Amazon SQS Connector (to the Mendix Amazon SQS Connector), GenAI For Mendix (Mx 9) (to GenAI Commons and the Mendix Cloud GenAI connector), OpenIDConnect Single Sign-on Community Support (OIDC, OAuth2, SSO) (to OIDC SSO, R2 covers module OIDC), Siemens UI Resources (Mendix 8) and Siemens UI Resources (Mendix 9 & 10) (to Atlas 3 / the current Siemens design system) |
| name clash, not the component in the field apps | Core Delta 213912 (the field apps hold OpcenterEXFN_Core_Delta, a different module); FileDropper_Widget 201367 (the field apps ship com.mendix.widget.custom.FileDropper 1.3.2, while the deprecated component stops at 1.1.1) |
| partner or community component with no named successor; a hit leaves nothing to tell the user beyond "deprecated" | Aelion - DTAP Environment information, ArcGIS Widget (DEPRECATED), Bizzomate Number Input [deprecated], Bizzomate React Select, Calendar, Database Scrambler, Emixa Redis Connector, EnumClass, Excel Exporter Template Manager, File Type Checker, Fix document names, FontAwesome for Mendix, GSK PDF Viewer, Hellosign Module, Image Crop, IP Range Validation, LDAP Synchronization module, ListenListviewSetter, Locale Switcher, Marketo Connector, Menditect - Microflow Call Hierarchy, Microsoft Sharepoint, MxValidator, Native parallax scroll view, Native Status bar, Number to Vietnamese text, OCR file, Odin - AI assisted Mendix development, PrintClass, QZ.io - Print to popular hardware, Siemens SCD Connector, SignIn microflow for Mx7 / Mx8, Simple CSV Exporter, Split Screen, Spotlight Search For Mendix, Sticky Notes, T-Synch Email, T-Synch ExcelExport, TabSwitcher, TS Audio Video Player, TS MultiFormatScanner (QR & Barcodes), Vibe Transcribe, Yaml - JSON Converter |

A left-out component still shows up in `release_impact.py` when the app's module jump covers its rows. This list only
records why it has no detector of its own. Promote one when a field app holds it: take the module name or widget id
from that app, never guess it.
