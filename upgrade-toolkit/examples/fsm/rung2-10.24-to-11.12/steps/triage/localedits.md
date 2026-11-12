# localedits <app>/app.mpr

## Administration 2.1.0 (content 23513): RED 2 | UI edits 3 (replay after update) | LOGIC edits 5 (documents added or deleted locally: keep the module or replay)
  info CHANGED  entity      Administration.Account  access rules (security, not data; lost on update)
  info ADDED    entity      Administration.AccountHelper  
  info CHANGED  entity      Administration.AccountPasswordData  access rules (security, not data; lost on update)
  info ADDED    association Administration.AccountHelper_Account  Administration.AccountHelper -> Administration.Account
  RED  ADDED    association Administration.Account_NativeTechnician  Administration.Account -> NativeTechnician.NativeTechnician
  RED  ADDED    association Administration.Account_Technician  Administration.Account -> Technician.Technician
  ui   CHANGED  page        Administration.Account_Overview  layout Atlas_Core.Atlas_Default -> FSM_Specific.LeftMenuLayout (the update resets it: replay)
  ui   ADDED    page        Administration.Account_Select  local document, removed by the update
  ui   CHANGED  page        Administration.ScheduledEvents  layout Atlas_Core.Atlas_Default -> FSM_Specific.LeftMenuLayout (the update resets it: replay)
  logic ADDED    microflow   Administration.ACT_Account_Edit  local document, removed by the update
  logic ADDED    microflow   Administration.ACT_Account_Save  local document, removed by the update
  logic ADDED    microflow   Administration.Account_Commit  local document, removed by the update
  logic ADDED    microflow   Administration.Account_GetOrCreateAccountHelper  local document, removed by the update
  logic ADDED    microflow   Administration.Account_Validate  local document, removed by the update
## Atlas_Core 3.22.0 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid Atlas_Core=<id>)
## Atlas_NativeMobile_Content 3.2.1 (content 117175): domain model unchanged
## Atlas_Web_Content 3.9.0 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid Atlas_Web_Content=<id>)
## BizzomateScheduler 1.4.0 (content 208890): domain model unchanged | FILES edits 1 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED themesource/bizzomatescheduler/public/css/scheduler-material-theme.css  ADDED  local file, not in the package (the update may remove it)
## CommunityCommons 11.5.1 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid CommunityCommons=<id>)
## DataWidgets 2.5.6 (content 116540): domain model unchanged | FILES edits 1 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED themesource/datawidgets/.DS_Store  REMOVED  package file deleted locally, comes back on update
## DeepLink 10.0.10 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid DeepLink=<id>)
## DemoUserSwitcher 1.1.0 (content 120303): UNKNOWN (package not readable: no versions available for this content)
## JWT 3.3.3 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid JWT=<id>)
## Logging 2.3.0 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid Logging=<id>)
## MendixSSO 4.1.0 (content 111349): domain model unchanged
## NanoflowCommons 5.2.1 (content 109515): domain model unchanged | FILES edits 4 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED javascriptsource/nanoflowcommons/actions/Geocode.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetPlatform.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/ReverseGeocode.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/TimeBetween.js  CHANGED  differs from the installed package
## NativeMobileResources 10.1.17 (content 109513): domain model unchanged | FILES edits 1 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED javascriptsource/nativemobileresources/actions/ChangeStatusBar.js  CHANGED  differs from the installed package
## ObjectHandling 5.2.0 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid ObjectHandling=<id>)
## ValidationFeedback 2.4.0 (content 0): UNKNOWN (package not readable: content id 0 in the MPR: give --cid ValidationFeedback=<id>)

modules: 16, RED data-bearing edits: 2, UNKNOWN (not judged): 9 ['Atlas_Core', 'Atlas_Web_Content', 'CommunityCommons', 'DeepLink', 'DemoUserSwitcher', 'JWT', 'Logging', 'ObjectHandling', 'ValidationFeedback']: use `mxcli marketplace diff` or a Studio Pro compare; UNKNOWN is never 'no edits', NETWORK (not judged, transient): 0
LOGIC edits (documents added or deleted, contents not compared): 5
FILES edits (themesource, javascriptsource, Java user code; exit 1): 7
UI edits (pages, layouts): 3
force-ui: BizzomateScheduler,DataWidgets,NanoflowCommons,NativeMobileResources  (stepupdate.sh --force-ui: saves the edits under $W/saved-edits and forces the update; replay them after)
RED rule: do not update and replay these edits blindly. Re-creating an element gives it a new GUID
and the runtime drops its column. Keep the module, or migrate the data, then prove it with idcheck.py
and the regression gate.
