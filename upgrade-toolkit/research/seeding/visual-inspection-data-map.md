# Visual Inspection 3.0.0 (Mendix 9.24.23): data map

Derived offline from the .mpr with `domain_map.py` (entities, validation, associations, enumerations, access) and
`page_data_needs.py` (which page lists which entity under which XPath). Nothing here is guessed from names.
Regenerate: `python3 -I domain_map.py <app dir>` and `python3 -I page_data_needs.py <app dir>`.

Roles (module roles, mapped to user roles by smoke_users.py): Administrator, QualityManager, Inspector.
Non-persistent entities (InspectionHelperNP, LocationHelperNP, ProductViewHelperNP, DashboardHelperNP, PieChartDataNP,
DefectTypeHelperNP, EmployeeNP, AnyChart*) are never seeded: pages build them from microflows.

| entity | who needs it | state it must be in | notes / constraint found |
|---|---|---|---|
| MasterData.Product (Name, _ID, Prefix, IsFinished) | Inspector (start inspection, SelectProduct), QualityManager (master data) | 2+ products, one `IsFinished=true` | no required rules; `_ID` is the app's own key, not the Mendix id |
| MasterData.ProductView (+ViewIcon, ViewImage files) | Inspector (view of the product with location markers) | each product has 1+ view with an icon and an image | ViewIcon/ViewImage are FileDocuments: the database row alone is not enough, the file must exist under data/files (FileNotFoundInStorageException otherwise) |
| MasterData.Location (PositionX/Y, MarkerColor, ...) | Inspector (marker on view), Defect_Location | 3-5 per view, positions 0-100 | association Location_ProductView must be set or the marker never renders |
| MasterData.LocationType, DefectType (Code) | QualityManager, Defect_DefectType | LocationType_DefectType set: a location type only offers its possible defect types | Code is the key the pages show |
| EmployeeManagement.Employee | every dashboard | one per smoke user, linked by Employee_Account to Administration.Account | Inspection.Inspection_Employee_Inspector points here; XPath `[Employee_Account='[%CurrentUser%]']` limits the Inspector's view |
| Inspection.Inspection | Inspector "ongoing" list, QualityManager "in review"/"closed" | XPath on Status: `Open` = ongoing, `!= Open` = review/closed. One row in each of Open / Inspection_done / Tickets_done, owned by the Inspector's employee | QualityManager access rule is `[Status != 'Open']`: an Open-only seed shows an empty manager overview |
| Inspection.Defect (Comment, Status Open/Assigned/Closed, CreatedOn) | Inspector (confirm), QualityManager (tickets), dashboard | each Inspection has defects; each Defect_Location + Defect_DefectType set; all three statuses present | NumberOfTickets / NumberOfOpenTickets on the inspection are plain integers kept by microflows: seed them consistent with the defects |
| Inspection.Task (Name, Email, DueDate) | QualityManager (ticket list, task page) | one per assigned/open defect, Task_Defect set | empty in the publisher snapshot |
| Inspection.InspectionImage / DefectImage | Inspector (photo of a defect) | optional | image files, same file-storage trap as ViewIcon |
| MasterData.Settings | Administrator | 1 row (useDemoImages) | singleton, created by the app on first open |
| AIChatbotBedrock.ConfigurationSelection, AWSAuthentication.Settings | Administrator (two Settings tabs) | one inactive demo row each, no credential | Marketplace modules, seeded only because a tab lists them |
| Administration.Account (+ roles) | all | one per role, via smoke_users.py | never a hand INSERT: needs bcrypt hash and UserRole links |

Enumerations that pages filter or colour on: ENUM_Inspection_Status {Open, Inspection_done, Tickets_done},
ENUM_Defect_Status {Open, Assigned, Closed}. Every value needs at least one row.

Route (steps/baseline.md): (a) the package ships `data-snapshot.zip` (publisher demo data, HSQLDB): seed_snapshot.py
loads it into Postgres; the snapshot misses what `gen_vi_spec.py` adds (Employee links, Tasks, inspector-owned inspections).
