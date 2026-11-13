---
title: Module security tabs - what each access matrix controls
topic: security
kind: reference
applies_to: general
versions: "any"
keywords: [module security, page access, microflow access, nanoflow access, entity access, OData access, GraphQL access, REST access, data set access, Show unused pages]
sources:
  - {title: "Module Security", url: "https://docs.mendix.com/refguide/module-security/", author: "unknown", date: "2026-09-25"}
status: draft-unreviewed
---
| Tab | Controls | Also editable in |
|---|---|---|
| Page access | Which pages are visible per module role | Page **Visible for** |
| Microflow access | Which microflows a role may run. The menu bar shows only accessible ones | Microflow **Allowed roles** |
| Nanoflow access | Which nanoflows a role may run | Nanoflow **Allowed roles** |
| Entity access | Create / Read / Write / Delete per role, optionally limited by an XPath constraint | Access rules |
| OData/GraphQL access | Access to each published OData/GraphQL service in the module | Service **Settings** > **Allowed roles** |
| REST access | Access to each published REST service. The tab is shown only when the service requires authentication | — |
| Data set access | Full / Limited / No access to each dataset | — |

**Data set access values**

| Value | Meaning |
|---|---|
| Full access | No parameter constraint applies; all range parameters are allowed |
| Limited access | At least one constraint applies, or at least one range parameter is not allowed |
| No access | No access to the data set |

Constraints and ranges are defined in the parameters of the data set. **Data Set Access** decides whether they apply.
