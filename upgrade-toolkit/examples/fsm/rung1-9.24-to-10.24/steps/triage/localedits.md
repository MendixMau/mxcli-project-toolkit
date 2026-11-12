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
## Atlas_Core 3.8.1 (content 117187): domain model unchanged
## Atlas_NativeMobile_Content 3.0.2 (content 117175): domain model unchanged
## Atlas_Web_Content 3.1.2 (content 117183): domain model unchanged
## BizzomateScheduler 1.4.0 (content 208890): domain model unchanged | FILES edits 1 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED themesource/bizzomatescheduler/public/css/scheduler-material-theme.css  ADDED  local file, not in the package (the update may remove it)
## CommunityCommons 9.0.2 (content 170): domain model unchanged
## DataWidgets 2.5.6 (content 116540): domain model unchanged | FILES edits 1 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED themesource/datawidgets/.DS_Store  REMOVED  package file deleted locally, comes back on update
## DeepLink 9.0.5 (content 43): domain model unchanged | UI edits 2 (replay after update)
  ui   CHANGED  snippet     DeepLink.Deeplink_BasicDetails  content differs from the package; local: SnippetParameter DeepLink (the update puts the package version back: save with --force-ui and replay)
  ui   CHANGED  snippet     DeepLink.Deeplink_Details  content differs from the package; local: SnippetParameter DeepLink (the update puts the package version back: save with --force-ui and replay)
## DemoUserSwitcher 1.1.0 (content 120303): UNKNOWN (package not readable: no versions available for this content)
## JWT 3.2.2 (content 106447): domain model unchanged
## Logging 1.9.0 (content 159): domain model unchanged | UI edits 1 (replay after update)
  ui   CHANGED  snippet     Logging.Message_View_Content  content differs from the package; local: SnippetParameter Message (the update puts the package version back: save with --force-ui and replay)
## MendixSSO 4.1.0 (content 111349): domain model unchanged
## NanoflowCommons 3.0.0 (content 109515): domain model unchanged | FILES edits 37 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED javascriptsource/nanoflowcommons/actions/Base64Decode.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/Base64Encode.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/CallPhoneNumber.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/ClearCachedSessionData.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/DraftEmail.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/Geocode.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetCurrentLocation.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetCurrentLocationMinimumAccuracy.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetGuid.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetObjectByGuid.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetPlatform.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetStorageItemObject.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetStorageItemObjectList.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/GetStorageItemString.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/HideProgress.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/NavigateTo.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/OpenMap.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/OpenURL.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/RefreshEntity.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/RefreshObject.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/Reload.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/RemoveStorageItem.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/RequestLocationPermission.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/ReverseGeocode.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/SendTextMessage.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/SetStorageItemObject.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/SetStorageItemObjectList.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/SetStorageItemString.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/Share.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/ShowConfirmation.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/ShowProgress.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/SignIn.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/SignOut.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/StorageItemExists.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/TimeBetween.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/ToggleSidebar.js  CHANGED  differs from the installed package
FILES-EDITED javascriptsource/nanoflowcommons/actions/Wait.js  CHANGED  differs from the installed package
## NativeMobileResources 4.0.1 (content 109513): domain model unchanged | FILES edits 1 (themesource / javascriptsource / Java user code: the update replaces them)
FILES-EDITED javascriptsource/nativemobileresources/actions/ChangeStatusBar.js  CHANGED  differs from the installed package
## ObjectHandling 3.2.0 (content 37114): domain model unchanged
## ValidationFeedback 1.2.0 (content 110282): UNKNOWN (package not readable: version "1.2.0" not found; run 'mxcli marketplace versions <id>' to list available versions)

modules: 16, RED data-bearing edits: 2, UNKNOWN (not judged): 2 ['DemoUserSwitcher', 'ValidationFeedback']: use `mxcli marketplace diff` or a Studio Pro compare; UNKNOWN is never 'no edits', NETWORK (not judged, transient): 0
LOGIC edits (documents added or deleted, contents not compared): 5
FILES edits (themesource, javascriptsource, Java user code; exit 1): 40
UI edits (pages, layouts): 6
force-ui: BizzomateScheduler,DataWidgets,DeepLink,Logging,NanoflowCommons,NativeMobileResources  (stepupdate.sh --force-ui: saves the edits under $W/saved-edits and forces the update; replay them after)
RED rule: do not update and replay these edits blindly. Re-creating an element gives it a new GUID
and the runtime drops its column. Keep the module, or migrate the data, then prove it with idcheck.py
and the regression gate.
