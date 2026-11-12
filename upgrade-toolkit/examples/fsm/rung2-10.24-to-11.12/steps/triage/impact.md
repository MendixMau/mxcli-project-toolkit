# Upgrade impact map

old: `<run>/original.mpr`  
new: `<app>/app.mpr`

This maps changes to journeys to look at. It is not a requirement ledger.

After-startup: `General.ASU_General` -> `General.ASU_General` (tree 238 -> 238 documents)  
Documents: 106 changed, 0 removed, 52 added

## module (8)

- [medium] `Atlas_Core`: 3.22.0 -> 4.6.0
- [medium] `Atlas_Web_Content`: 3.9.0 -> 4.4.0
- [medium] `DataWidgets`: 2.5.6 -> 3.11.8
- [medium] `FeedbackModule`: added (own)
- [medium] `Logging`: 2.3.0 -> 2.4.0
- [medium] `NanoflowCommons`: 5.2.1 -> 7.4.0
- [medium] `NativeMobileResources`: 10.1.17 -> 12.6.0
- [medium] `ValidationFeedback`: 2.4.0 -> 3.4.0

## constant (1)

- [low] `FeedbackModule.LocalStorageKey`: added, default 'mxfeedback-form-data' (String)

## startup (1)

- [high] `General.ASU_General`: after-startup call tree: 0 added, 0 removed, 18 changed (old tree 238, new tree 238)
  - changed in the tree: General.ASU_General, MendixSSO.MendixSSO_AfterStartup, MendixSSO.MendixSSO_CreateUser, MendixSSO.MendixSSO_UpdateUser, MendixSSO.ValidateTokenEncryptionKey, NativeMobile.Private_NativeTicket_CalculateDates, Reason.ASU_CreateStandardReason, Synchronization.Appointment_UpdateNativeAppointment, Synchronization.TicketList_ProcessUpdatingNativeTickets, Synchronization.WorkOrderAssignment_UpdateNativeWorkOrderAssignment, Synchronization.WorkOrder_UpdateNativeWorkOrders, TicketManagement.Private_Appointment_CalculateDates

## scheduled (2)

- [low] `Logging.CleanupDataLogging`: call tree changed (1 documents)
- [low] `TicketManagement.SE_DeleteExpiredAppointments`: call tree changed (10 documents)

## security (1)

- [medium] `Atlas_Web_Content.$ModuleSecurity`: module roles +['Administrator', 'User'] -[]

## service (1)

- [medium] `MendixSSO.NotifyRolesChangedAPI`: operation microflows changed: ['MendixSSO.RS_NotifyUserRolesChanged']

## caller (7)

- [medium] `AppSettings.ApplicationSettings_Validate_Navigation`: calls DeepLink.DeepLinkHome (changed)
- [medium] `Dashboard.NAV_DashboardAll`: calls DeepLink.DeepLinkHome (changed)
- [medium] `Dashboard.NAV_DashboardExternal`: calls DeepLink.DeepLinkHome (changed)
- [medium] `Dashboard.NAV_DashboardInternal`: calls DeepLink.DeepLinkHome (changed)
- [medium] `General.ASU_General`: calls MendixSSO.MendixSSO_AfterStartup (changed)
- [medium] `ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkDetails`: calls DeepLink.DeepLinkHome (changed)
- [medium] `Technician.NAV_Technician_Home`: calls DeepLink.DeepLinkHome (changed)

## document (149)

- [medium] `AssetManagement.ACT_AssetPart_Save`: Microflow changed at Flows[7].OriginConnectionIndex
- [medium] `FSMPublishedAPI.AssetResponse_ValidateRequestParameters`: Microflow changed at Flows[22].OriginConnectionIndex
- [medium] `Form.ACT_WorkOrder_Add_FormVersion`: Microflow changed at Flows[4].OriginConnectionIndex
- [medium] `General.ASU_General`: Microflow changed at Flows[2].OriginConnectionIndex
- [medium] `ModuleIntegration_Administration_Impl.Account_ChangePasswordForm`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[0].Validation.Expression
- [medium] `ModuleIntegration_Administration_Impl.Account_New`: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Widgets[1].Validation.Expression
- [medium] `ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_FunctionalAdmin`: Rule changed at Flows[3].OriginConnectionIndex
- [medium] `ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM`: Rule changed at Flows[6].OriginConnectionIndex
- [medium] `ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_TechnicalAdmin`: Rule changed at Flows[3].OriginConnectionIndex
- [medium] `ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician`: Rule changed at Flows[6].OriginConnectionIndex
- [medium] `NativeMobile.ACT_NativeAppointment_WorkFinished`: Nanoflow changed at Flows[8].OriginConnectionIndex
- [medium] `NativeMobile.ACT_NativeAttachment_Download`: Nanoflow changed at Flows[9].OriginConnectionIndex
- [medium] `NativeMobile.ACT_NativeWorkOrderAssignment_SelectNativeReason`: Nanoflow changed at Flows[2].OriginConnectionIndex
- [medium] `NativeMobile.NativeAppointment_FinishedThisAppointment`: Nanoflow changed at Flows[6].OriginConnectionIndex
- [medium] `NativeMobile.NativeAppointment_GenerateNativeTimeRegistration`: Nanoflow changed at Flows[11].OriginConnectionIndex
- [medium] `NativeMobile.NativeAttachment_GenerateRestURL`: Microflow changed at Flows[6].OriginConnectionIndex
- [medium] `NativeMobile.Private_NativeTicket_CalculateDates`: Nanoflow changed at Flows[18].OriginConnectionIndex
- [medium] `NativeMobilePart.ACT_PartHelper_SavePart`: Nanoflow changed at Flows[7].OriginConnectionIndex
- [medium] `NativeMobileRelated.ACT_NativeAttachmentNP_Download`: Nanoflow changed at Flows[8].OriginConnectionIndex
- [medium] `NativeMobileTimeRegistration.NativeTimeRegistrationNPList_Delete`: Nanoflow changed at Flows[1].OriginConnectionIndex
- [medium] `Reason.ASU_CreateStandardReason`: Microflow changed at Flows[6].OriginConnectionIndex
- [medium] `Reason.Reason_Validate`: Microflow changed at Flows[13].OriginConnectionIndex
- [medium] `RosterManagement.RosterCreateHelper_ChangeStartAndEndTime`: Microflow changed at Flows[4].OriginConnectionIndex
- [medium] `RosterManagement.RosterCreateHelper_CreateAndCommitTechnicianRosterList`: Microflow changed at Flows[16].OriginConnectionIndex
- [medium] `Scheduler.ACT_AvailableTimeslot_PlanAppointment`: Microflow changed at Flows[7].OriginConnectionIndex
- [medium] `Scheduler.ACT_WorkOrder_SetPlannerContext_Wrapper`: Nanoflow changed at Flows[11].OriginConnectionIndex
- [medium] `Scheduler.PlannerContext_Reset`: Microflow changed at Flows[4].OriginConnectionIndex
- [medium] `Synchronization.Appointment_UpdateNativeAppointment`: Microflow changed at Flows[8].OriginConnectionIndex
- [medium] `Synchronization.InstanceForm_ProcessUpdatingNativeInstanceForm`: Microflow changed at Flows[8].OriginConnectionIndex
- [medium] `Synchronization.NativeInstanceItem_SetupOfflinePictureActions`: Nanoflow changed at Flows[13].OriginConnectionIndex
- [medium] `Synchronization.Private_Synchronize`: Nanoflow changed at Flows[4].OriginConnectionIndex
- [medium] `Synchronization.Private_Synchronize_InitialDownload_Execute`: Nanoflow changed at Flows[29].OriginConnectionIndex
- [medium] `Synchronization.SuggestedPart_ProcessUpdatingNativeSuggestedPart`: Microflow changed at Flows[6].OriginConnectionIndex
- [medium] `Synchronization.Technician_ProcessUpdatingNativeTechnician`: Microflow changed at Flows[14].OriginConnectionIndex
- [medium] `Synchronization.TicketList_ProcessUpdatingNativeTickets`: Microflow changed at Flows[7].OriginConnectionIndex
- [medium] `Synchronization.UsedPart_ProcessUpdatingNativeUsedPart`: Microflow changed at Flows[5].OriginConnectionIndex
- [medium] `Synchronization.WorkBreak_UpdateNativeWorkBreak`: Microflow changed at Flows[7].OriginConnectionIndex
- [medium] `Synchronization.WorkOrderAssignment_UpdateNativeWorkOrderAssignment`: Microflow changed at Flows[15].OriginConnectionIndex
- [medium] `Synchronization.WorkOrder_UpdateNativeWorkOrders`: Microflow changed at Flows[5].OriginConnectionIndex
- [medium] `TicketManagement.ACT_TicketNP_Malfunction_SaveAndRemoveDraftStatus`: Microflow changed at Flows[5].OriginConnectionIndex
- ... 109 more (see the JSON)

## Journey candidates

- **P1 login-per-role**: Login per role lands on the role home with the role menu  
  roles: CallCenterEmployee, FSMAPIConsumer, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because security: Atlas_Web_Content.$ModuleSecurity: module roles +['Administrator', 'User'] -[]  
  because caller: ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkDetails: calls DeepLink.DeepLinkHome (changed)  
  because service: MendixSSO.NotifyRolesChangedAPI: operation microflows changed: ['MendixSSO.RS_NotifyUserRolesChanged']  
- **P1 startup**: App starts clean and the startup work is done (log + login per role)  
  roles: CallCenterEmployee, FSMAPIConsumer, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because startup: General.ASU_General: after-startup call tree: 0 added, 0 removed, 18 changed (old tree 238, new tree 238)  
  because document: General.ASU_General: Microflow changed at Flows[2].OriginConnectionIndex  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: Reason.ASU_CreateStandardReason: Microflow changed at Flows[6].OriginConnectionIndex  
  ... and 12 more reasons  
- **P2 client_microflow:MasterData.ACT_WorkBreak_Save_MxAdmin**: Reach MasterData.ACT_WorkBreak_Save_MxAdmin (no menu item; opened from another page)  
  roles: TechnicalAdministrator  
  because document: Synchronization.WorkBreak_UpdateNativeWorkBreak: Microflow changed at Flows[7].OriginConnectionIndex  
- **P2 client_microflow:NativeMobile.NativeAttachment_GenerateRestURL**: Reach NativeMobile.NativeAttachment_GenerateRestURL (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.NativeAttachment_GenerateRestURL: Microflow changed at Flows[6].OriginConnectionIndex  
- **P2 client_microflow:Synchronization.OfflineAction_ProcessList**: Reach Synchronization.OfflineAction_ProcessList (no menu item; opened from another page)  
  roles: Mechanic  
  because document: TicketManagement.Appointment_SetExpectedDurationForResolvedWorkOrder: Microflow changed at Flows[8].OriginConnectionIndex  
  because document: TicketManagement.WorkOrderAssignment_AcceptUrgentWorkOrder: Microflow changed at Flows[9].OriginConnectionIndex  
  because document: TicketManagement.WorkOrderAssignment_PickUpUnplanned: Microflow changed at Flows[7].OriginConnectionIndex  
- **P2 home:Dashboard.NAV_DashboardAll**: Role home page Dashboard.NAV_DashboardAll works  
  roles: ServiceDeskEmployee  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: TicketManagement.ACT_TicketNP_Malfunction_SaveAndRemoveDraftStatus: Microflow changed at Flows[5].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_BulkSave: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_Delete: Microflow changed at Flows[4].OriginConnectionIndex  
  ... and 6 more reasons  
- **P2 home:Dashboard.NAV_DashboardExternal**: Role home page Dashboard.NAV_DashboardExternal works  
  roles: CallCenterEmployee  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: TicketManagement.ACT_TicketNP_Malfunction_SaveAndRemoveDraftStatus: Microflow changed at Flows[5].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_BulkSave: Microflow changed at Flows[7].OriginConnectionIndex  
  ... and 13 more reasons  
- **P2 home:Dashboard.NAV_DashboardInternal**: Role home page Dashboard.NAV_DashboardInternal works  
  roles: ServiceRegionManager  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: RosterManagement.RosterCreateHelper_ChangeStartAndEndTime: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: RosterManagement.RosterCreateHelper_CreateAndCommitTechnicianRosterList: Microflow changed at Flows[16].OriginConnectionIndex  
  ... and 15 more reasons  
- **P2 home:Technician.NAV_Technician_Home**: Role home page Technician.NAV_Technician_Home works  
  roles: Mechanic  
  because document: Form.ACT_WorkOrder_Add_FormVersion: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: Synchronization.TicketList_ProcessUpdatingNativeTickets: Microflow changed at Flows[7].OriginConnectionIndex  
  ... and 16 more reasons  
- **P2 home:TicketManagement.Ticket_Overview_ServiceDesk**: Role home page TicketManagement.Ticket_Overview_ServiceDesk works  
  roles: CallCenterEmployee, FunctionalAdministrator, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.ACT_AssetPart_Save: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: Form.ACT_WorkOrder_Add_FormVersion: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  ... and 19 more reasons  
- **P2 menu:Administration > Accounts**: Open Administration > Accounts and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: ModuleIntegration_Administration_Impl.Account_ChangePasswordForm: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[0].Validation.Expression  
  because document: ModuleIntegration_Administration_Impl.Account_New: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Widgets[1].Validation.Expression  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_FunctionalAdmin: Rule changed at Flows[3].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  ... and 2 more reasons  
- **P2 menu:Administration > Application settings**: Open Administration > Application settings and use it  
  roles: TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
  because caller: AppSettings.ApplicationSettings_Validate_Navigation: calls DeepLink.DeepLinkHome (changed)  
- **P2 menu:Administration > Assets**: Open Administration > Assets and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.ACT_AssetPart_Save: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: TicketManagement.ACT_TicketNP_Malfunction_SaveAndRemoveDraftStatus: Microflow changed at Flows[5].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_BulkSave: Microflow changed at Flows[7].OriginConnectionIndex  
  ... and 6 more reasons  
- **P2 menu:Administration > Business contacts**: Open Administration > Business contacts and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Contracts**: Open Administration > Contracts and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Customers**: Open Administration > Customers and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Deeplink**: Open Administration > Deeplink and use it  
  roles: TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
  because caller: ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkDetails: calls DeepLink.DeepLinkHome (changed)  
- **P2 menu:Administration > Feature toggles**: Open Administration > Feature toggles and use it  
  roles: ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Load test**: Open Administration > Load test and use it  
  roles: TechnicalAdministrator  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: Synchronization.TicketList_ProcessUpdatingNativeTickets: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: TicketManagement.Private_Appointment_CalculateDates: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: TicketManagement.Private_Ticket_CalculateDates: Microflow changed at Flows[20].OriginConnectionIndex  
  ... and 4 more reasons  
- **P2 menu:Administration > Masterdata views**: Open Administration > Masterdata views and use it  
  roles: TechnicalAdministrator  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: RosterManagement.RosterCreateHelper_ChangeStartAndEndTime: Microflow changed at Flows[4].OriginConnectionIndex  
  ... and 19 more reasons  
- **P2 menu:Administration > Offline actions**: Open Administration > Offline actions and use it  
  roles: ServiceRegionManager, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Parts**: Open Administration > Parts and use it  
  roles: FunctionalAdministrator  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: TicketManagement.ACT_TicketNP_Malfunction_SaveAndRemoveDraftStatus: Microflow changed at Flows[5].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_BulkSave: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_Delete: Microflow changed at Flows[4].OriginConnectionIndex  
  ... and 3 more reasons  
- **P2 menu:Administration > Priorities**: Open Administration > Priorities and use it  
  roles: FunctionalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Reasons**: Open Administration > Reasons and use it  
  roles: FunctionalAdministrator  
  because document: Reason.Reason_Validate: Microflow changed at Flows[13].OriginConnectionIndex  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Registration codes**: Open Administration > Registration codes and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > SLA's**: Open Administration > SLA's and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Scheduled Events**: Open Administration > Scheduled Events and use it  
  roles: TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Scripts**: Open Administration > Scripts and use it  
  roles: TechnicalAdministrator  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: Synchronization.SuggestedPart_ProcessUpdatingNativeSuggestedPart: Microflow changed at Flows[6].OriginConnectionIndex  
  because document: Synchronization.Technician_ProcessUpdatingNativeTechnician: Microflow changed at Flows[14].OriginConnectionIndex  
  because document: Synchronization.TicketList_ProcessUpdatingNativeTickets: Microflow changed at Flows[7].OriginConnectionIndex  
  ... and 13 more reasons  
- **P2 menu:Administration > Skills**: Open Administration > Skills and use it  
  roles: FunctionalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Snap settings**: Open Administration > Snap settings and use it  
  roles: FunctionalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Systemlogs**: Open Administration > Systemlogs and use it  
  roles: TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Technician groups**: Open Administration > Technician groups and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Technicians**: Open Administration > Technicians and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: RosterManagement.RosterCreateHelper_ChangeStartAndEndTime: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: RosterManagement.RosterCreateHelper_CreateAndCommitTechnicianRosterList: Microflow changed at Flows[16].OriginConnectionIndex  
  because document: Synchronization.Technician_ProcessUpdatingNativeTechnician: Microflow changed at Flows[14].OriginConnectionIndex  
  ... and 4 more reasons  
- **P2 menu:Administration > Ticket types**: Open Administration > Ticket types and use it  
  roles: FunctionalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Tools**: Open Administration > Tools and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Units of measurement**: Open Administration > Units of measurement and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Administration > Warehouses**: Open Administration > Warehouses and use it  
  roles: FunctionalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Alerts**: Open Alerts and use it  
  roles: ServiceDeskEmployee  
  because document: Form.ACT_WorkOrder_Add_FormVersion: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: Synchronization.TicketList_ProcessUpdatingNativeTickets: Microflow changed at Flows[7].OriginConnectionIndex  
  ... and 14 more reasons  
- **P2 menu:Dashboard**: Open Dashboard and use it  
  roles: CallCenterEmployee, ServiceRegionManager  
  because document: AssetManagement.ACT_AssetPart_Save: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: Form.ACT_WorkOrder_Add_FormVersion: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  ... and 19 more reasons  
- **P2 menu:Forms**: Open Forms and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Grids templates**: Open Grids templates and use it  
  roles: TechnicalAdministrator  
  because document: Visualizations.AlertStatistics_GetUnresolvedAppointments: Microflow changed at Flows[3].OriginConnectionIndex  
- **P2 menu:Scheduler**: Open Scheduler and use it  
  roles: Mechanic, ServiceDeskEmployee, ServiceRegionManager  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  because document: Scheduler.ACT_AvailableTimeslot_PlanAppointment: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: Scheduler.ACT_WorkOrder_SetPlannerContext_Wrapper: Nanoflow changed at Flows[11].OriginConnectionIndex  
  ... and 10 more reasons  
- **P2 menu:Tickets**: Open Tickets and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.ACT_AssetPart_Save: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: Form.ACT_WorkOrder_Add_FormVersion: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_SRM: Rule changed at Flows[6].OriginConnectionIndex  
  because document: ModuleIntegration_Administration_Impl.Rule_User_HasUserRole_Technician: Rule changed at Flows[6].OriginConnectionIndex  
  ... and 19 more reasons  
- **P2 menu:Work orders**: Open Work orders and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: Form.ACT_WorkOrder_Add_FormVersion: Microflow changed at Flows[4].OriginConnectionIndex  
  because document: Synchronization.SuggestedPart_ProcessUpdatingNativeSuggestedPart: Microflow changed at Flows[6].OriginConnectionIndex  
  because document: TicketManagement.ACT_WorkOrder_Save: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: TicketManagement.Private_Ticket_CalculateDates: Microflow changed at Flows[20].OriginConnectionIndex  
  ... and 3 more reasons  
- **P2 module-pages:Logging**: Open the changed Logging pages a role can reach and look at them (screenshot old vs new)  
  roles: TechnicalAdministrator  
  because module: Logging updated; 1 changed role-gated pages: Logging.PreFilterRule_NewEdit  
- **P2 page:MasterData.WorkBreak_NewEdit_MxAdmin**: Reach MasterData.WorkBreak_NewEdit_MxAdmin (no menu item; opened from another page)  
  roles: TechnicalAdministrator  
  because document: Synchronization.WorkBreak_UpdateNativeWorkBreak: Microflow changed at Flows[7].OriginConnectionIndex  
- **P2 page:NativeMobile.Home_Native_Mechanic**: Reach NativeMobile.Home_Native_Mechanic (no menu item; opened from another page)  
  roles: Mechanic  
  because document: Synchronization.Private_Synchronize_InitialDownload_Execute: Nanoflow changed at Flows[29].OriginConnectionIndex  
- **P2 page:NativeMobile.Login**: Reach NativeMobile.Login (no menu item; opened from another page)  
  roles: Anonymous  
  because document: Synchronization.Private_Synchronize: Nanoflow changed at Flows[4].OriginConnectionIndex  
- **P2 page:NativeMobile.NativeAppointmentNP_Overview**: Reach NativeMobile.NativeAppointmentNP_Overview (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.ACT_NativeAppointment_WorkFinished: Nanoflow changed at Flows[8].OriginConnectionIndex  
  because document: NativeMobile.ACT_NativeAttachment_Download: Nanoflow changed at Flows[9].OriginConnectionIndex  
  because document: NativeMobile.NativeAppointment_FinishedThisAppointment: Nanoflow changed at Flows[6].OriginConnectionIndex  
  because document: NativeMobile.NativeAppointment_GenerateNativeTimeRegistration: Nanoflow changed at Flows[11].OriginConnectionIndex  
  ... and 5 more reasons  
- **P2 page:NativeMobile.NativeAppointment_Details**: Reach NativeMobile.NativeAppointment_Details (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.ACT_NativeAppointment_WorkFinished: Nanoflow changed at Flows[8].OriginConnectionIndex  
  because document: NativeMobile.ACT_NativeAttachment_Download: Nanoflow changed at Flows[9].OriginConnectionIndex  
  because document: NativeMobile.NativeAppointment_FinishedThisAppointment: Nanoflow changed at Flows[6].OriginConnectionIndex  
  because document: NativeMobile.NativeAppointment_GenerateNativeTimeRegistration: Nanoflow changed at Flows[11].OriginConnectionIndex  
  ... and 2 more reasons  
- **P2 page:NativeMobileRelated.NativeAppointmentNP_Details**: Reach NativeMobileRelated.NativeAppointmentNP_Details (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.NativeAttachment_GenerateRestURL: Microflow changed at Flows[6].OriginConnectionIndex  
  because document: NativeMobileRelated.ACT_NativeAttachmentNP_Download: Nanoflow changed at Flows[8].OriginConnectionIndex  
- **P2 page:NativeMobileRelated.NativeWorkOrderNP_Load**: Reach NativeMobileRelated.NativeWorkOrderNP_Load (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.ACT_NativeWorkOrderAssignment_SelectNativeReason: Nanoflow changed at Flows[2].OriginConnectionIndex  
- **P2 page:NativeMobileRelated.NativeWorkOrderNP_Overview**: Reach NativeMobileRelated.NativeWorkOrderNP_Overview (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.ACT_NativeWorkOrderAssignment_SelectNativeReason: Nanoflow changed at Flows[2].OriginConnectionIndex  
- **P2 sched:TicketManagement.SE_DeleteExpiredAppointments**: Scheduled event TicketManagement.SE_DeleteExpiredAppointments still runs and does its work  
  roles: (system, no role)  
  because scheduled: TicketManagement.SE_DeleteExpiredAppointments: call tree changed (10 documents)  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: Synchronization.TicketList_ProcessUpdatingNativeTickets: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: Synchronization.WorkOrderAssignment_UpdateNativeWorkOrderAssignment: Microflow changed at Flows[15].OriginConnectionIndex  
  ... and 7 more reasons  
- **P2 svc:FSMPublishedAPI.PRS_FSM**: Published service FSMPublishedAPI.PRS_FSM answers as before  
  roles: FSMAPIConsumer  
  because document: FSMPublishedAPI.AssetResponse_ValidateRequestParameters: Microflow changed at Flows[22].OriginConnectionIndex  
  because document: NativeMobile.Private_NativeTicket_CalculateDates: Nanoflow changed at Flows[18].OriginConnectionIndex  
  because document: Synchronization.TicketList_ProcessUpdatingNativeTickets: Microflow changed at Flows[7].OriginConnectionIndex  
  because document: Synchronization.WorkOrderAssignment_UpdateNativeWorkOrderAssignment: Microflow changed at Flows[15].OriginConnectionIndex  
  ... and 12 more reasons  
- **P2 svc:MendixSSO.NotifyRolesChangedAPI**: Published service MendixSSO.NotifyRolesChangedAPI answers as before (REST gate)  
  roles: (system, no role)  
  because service: MendixSSO.NotifyRolesChangedAPI: operation microflows changed: ['MendixSSO.RS_NotifyUserRolesChanged']  
- **P3 page:Administration.ActiveSessions**: Reach Administration.ActiveSessions (no menu item; opened from another page)  
  roles: TechnicalAdministrator  
  because constant: FeedbackModule.LocalStorageKey: added, default 'mxfeedback-form-data' (String)  
- **P3 page:Administration.RuntimeInstances**: Reach Administration.RuntimeInstances (no menu item; opened from another page)  
  roles: TechnicalAdministrator  
  because constant: FeedbackModule.LocalStorageKey: added, default 'mxfeedback-form-data' (String)  
- **P3 sched:Logging.CleanupDataLogging**: Scheduled event Logging.CleanupDataLogging still runs and does its work  
  roles: (system, no role)  
  because scheduled: Logging.CleanupDataLogging: call tree changed (1 documents)  

## Per role

- **Anonymous** home `General.Login_Web`; candidates: page:NativeMobile.Login
- **CallCenterEmployee** home `Dashboard.NAV_DashboardExternal`; candidates: login-per-role, startup, home:Dashboard.NAV_DashboardExternal, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Assets, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Dashboard, menu:Forms, menu:Tickets
- **FSMAPIConsumer** home `General.Login_Web`; candidates: login-per-role, startup, svc:FSMPublishedAPI.PRS_FSM
- **FunctionalAdministrator** home `TicketManagement.Ticket_Overview_ServiceDesk`; candidates: login-per-role, startup, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Accounts, menu:Administration > Assets, menu:Administration > Business contacts, menu:Administration > Contracts, menu:Administration > Customers, menu:Administration > Parts, menu:Administration > Priorities, menu:Administration > Reasons, menu:Administration > Registration codes, menu:Administration > SLA's, menu:Administration > Skills, menu:Administration > Snap settings, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Ticket types, menu:Administration > Tools, menu:Administration > Units of measurement, menu:Administration > Warehouses, menu:Forms, menu:Tickets, menu:Work orders
- **Mechanic** home `Technician.NAV_Technician_Home`; candidates: login-per-role, startup, client_microflow:NativeMobile.NativeAttachment_GenerateRestURL, client_microflow:Synchronization.OfflineAction_ProcessList, home:Technician.NAV_Technician_Home, menu:Administration > Assets, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Scheduler, menu:Tickets, page:NativeMobile.Home_Native_Mechanic, page:NativeMobile.NativeAppointmentNP_Overview, page:NativeMobile.NativeAppointment_Details, page:NativeMobileRelated.NativeAppointmentNP_Details, page:NativeMobileRelated.NativeWorkOrderNP_Load, page:NativeMobileRelated.NativeWorkOrderNP_Overview
- **ServiceDeskEmployee** home `Dashboard.NAV_DashboardAll`; candidates: login-per-role, startup, home:Dashboard.NAV_DashboardAll, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Assets, menu:Administration > Business contacts, menu:Administration > Contracts, menu:Administration > Customers, menu:Administration > Feature toggles, menu:Administration > SLA's, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Alerts, menu:Forms, menu:Scheduler, menu:Tickets
- **ServiceRegionManager** home `Dashboard.NAV_DashboardInternal`; candidates: login-per-role, startup, home:Dashboard.NAV_DashboardInternal, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Assets, menu:Administration > Feature toggles, menu:Administration > Offline actions, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Dashboard, menu:Forms, menu:Scheduler, menu:Tickets
- **TechnicalAdministrator** home `TicketManagement.Ticket_Overview_ServiceDesk`; candidates: login-per-role, startup, client_microflow:MasterData.ACT_WorkBreak_Save_MxAdmin, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Accounts, menu:Administration > Application settings, menu:Administration > Assets, menu:Administration > Business contacts, menu:Administration > Contracts, menu:Administration > Customers, menu:Administration > Deeplink, menu:Administration > Feature toggles, menu:Administration > Load test, menu:Administration > Masterdata views, menu:Administration > Offline actions, menu:Administration > Registration codes, menu:Administration > SLA's, menu:Administration > Scheduled Events, menu:Administration > Scripts, menu:Administration > Systemlogs, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Tools, menu:Forms, menu:Grids templates, menu:Tickets, menu:Work orders, module-pages:Logging, page:MasterData.WorkBreak_NewEdit_MxAdmin, page:Administration.ActiveSessions, page:Administration.RuntimeInstances
