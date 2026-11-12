# Upgrade impact map

old: `<run>/original.mpr`  
new: `<app>/app.mpr`

This maps changes to journeys to look at. It is not a requirement ledger.

After-startup: `General.ASU_General` -> `General.ASU_General` (tree 236 -> 238 documents)  
Documents: 220 changed, 3 removed, 16 added

## module (11)

- [high] `DeepLink`: 9.0.5 -> 10.0.10
- [medium] `Atlas_Core`: 3.8.1 -> 3.22.0
- [medium] `Atlas_NativeMobile_Content`: 3.0.2 -> 3.2.1
- [medium] `Atlas_Web_Content`: 3.1.2 -> 3.9.0
- [medium] `CommunityCommons`: 9.0.2 -> 11.5.1
- [medium] `JWT`: 3.2.2 -> 3.3.3
- [medium] `Logging`: 1.9.0 -> 2.3.0
- [medium] `NanoflowCommons`: 3.0.0 -> 5.2.1
- [medium] `NativeMobileResources`: 4.0.1 -> 10.1.17
- [medium] `ObjectHandling`: 3.2.0 -> 5.2.0
- [medium] `ValidationFeedback`: 1.2.0 -> 2.4.0

## constant (3)

- [high] `NanoflowCommons.Nanoflow_Commons_Version`: removed (default was '2.1.0')
- [medium] `Logging.EnablePreFilter`: added, default 'True' (Boolean) (read in the startup tree by Logging.SUB_UpdatePreFilter)
- [low] `Logging.CleanupFilter`: added, default '' (String)

## startup (1)

- [high] `General.ASU_General`: after-startup call tree: 2 added, 0 removed, 1 changed (old tree 236, new tree 238)
  - changed in the tree: Logging.AfterStartup

## scheduled (1)

- [low] `Logging.CleanupDataLogging`: OnOverlap DelayNext -> SkipNext; call tree changed (1 documents)

## security (3)

- [medium] `Atlas_Core.$ModuleSecurity`: module roles +['Administrator', 'User'] -[]
- [medium] `Atlas_Web_Content.$ModuleSecurity`: module roles +['Anonymous'] -[]
- [medium] `Logging.$ModuleSecurity`: module security changed (access rules or role details)

## caller (12)

- [medium] `Atlas_Core.PopupLayout`: layout changed; used by 64 own pages (theme/visual impact: smoke walk and screenshots, not one journey per page)
- [medium] `General.ASU_General`: calls Logging.AfterStartup (changed)
- [medium] `ModuleIntegration_DeepLink_Impl.ACT_ShowMicroflowSelect`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.Attribute_Select`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.DeepLink_New`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.Deeplink_New`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.Microflow_Select`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkBasicDetails`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkConfigurationOverview`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkDetails`: uses DeepLink.DeepLink (access rule for DeepLink.User)
- [medium] `NativeMobile.ACT_SignInUser`: calls NanoflowCommons.SignIn (changed)
- [medium] `TEST_NativeLocalLogin.ACT_SignInUser`: calls NanoflowCommons.SignIn (changed)

## document (250)

- [medium] `AppSettings.Snippet_ApplicationSettings_Details`: Snippet changed at Widgets[0].TabPages[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `AppSettings.Snippet_SynchronizationError_Overview`: Snippet changed at Widgets[0].DataSource.$Type
- [medium] `AssetManagement.Asset_AssetPart_AddToBOM`: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `AssetManagement.Asset_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]
- [medium] `AssetManagement.Asset_Select_Multi`: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type
- [medium] `AssetManagement.Asset_Select_Single`: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type
- [medium] `AssetManagement.Asset_View`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `AssetManagement.Snippet_Asset_DataTabs`: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]
- [medium] `AssetManagement.Snippet_Asset_Details`: Snippet changed at Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `AssetManagement.Snippet_Asset_Notes`: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `CustomerManagement.ContactPerson_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.ContactPerson_View`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.Contract_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.Contract_View`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.Customer_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.Customer_View`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.SLA_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.SLA_Select`: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type
- [medium] `CustomerManagement.SLA_Select_Umbrella`: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type
- [medium] `CustomerManagement.SLA_View`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `CustomerManagement.Snippet_Contract_Details`: Snippet changed at Widgets[0].Rows[0].Columns[0].Widgets[4].SelectorSource.$Type
- [medium] `Dashboard.DashboardAll`: Page changed at FormCall.Arguments[0].Widgets[1].Widgets[1].Rows[0].Columns[0].Widgets[1].Widgets[1].Widgets[0].TabPages[1].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `Dashboard.DashboardExternal`: Page changed at FormCall.Arguments[0].Widgets[2].Widgets[0].Rows[0].Columns[0].Widgets[0].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Dashboard.DashboardInternal`: Page changed at FormCall.Arguments[0].Widgets[2].Widgets[0].Rows[0].Columns[0].Widgets[0].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Dashboard.Grids`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].TabPages[0].Widgets[0].DataSource.$Type
- [medium] `Dashboard.SNIPPET_Malfunction_Overview`: Snippet changed at Widgets[0].ControlBar.NewButtons[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `Dashboard.SNIPPET_SLANotifications`: Snippet changed at Widgets[0].ControlBar.NewButtons[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `Dashboard.SNIPPET_TicketsOfToday`: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Dashboard.SNIPPET_Top5Assets`: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `DeepLink.SetUseObjectArgumentToFalse`: Nanoflow removed
- [medium] `DeepLink.SetUseStringArgumentToFalse`: Nanoflow removed
- [medium] `FSM_Specific.LoginLayout`: Layout changed at Content.Widgets[0].Top.Widgets[0].Appearance.DesignProperties[1].Key
- [medium] `FeatureToggle.FeatureToggle_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Widgets[0].DataSource.$Type
- [medium] `Form.FormVersion_NewEdit`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Form.FormVersion_Select_TicketType`: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[0].ControlBar.NewButtons[0].Action.MicroflowSettings.ParameterMappings[len 0->1]
- [medium] `Form.FormVersion_View`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Form.Form_Overview`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Form.InstanceForm_View`: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[1].Key
- [medium] `Form.SNIP_InstanceItemImage`: Snippet changed at Widgets[0].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key
- [medium] `Form.SNIP_ItemImage`: Snippet changed at Widgets[0].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key
- ... 210 more (see the JSON)

## Journey candidates

- **P1 login-per-role**: Login per role lands on the role home with the role menu  
  roles: CallCenterEmployee, FSMAPIConsumer, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because security: Atlas_Web_Content.$ModuleSecurity: module roles +['Anonymous'] -[]  
  because security: Atlas_Core.$ModuleSecurity: module roles +['Administrator', 'User'] -[]  
  because security: Logging.$ModuleSecurity: module security changed (access rules or role details)  
  because module: DeepLink: 9.0.5 -> 10.0.10  
  ... and 9 more reasons  
- **P1 startup**: App starts clean and the startup work is done (log + login per role)  
  roles: CallCenterEmployee, FSMAPIConsumer, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because constant: Logging.EnablePreFilter: added, default 'True' (Boolean)  
  because startup: General.ASU_General: after-startup call tree: 2 added, 0 removed, 1 changed (old tree 236, new tree 238)  
  because caller: General.ASU_General: calls Logging.AfterStartup (changed)  
- **P2 home:Dashboard.NAV_DashboardAll**: Role home page Dashboard.NAV_DashboardAll works  
  roles: ServiceDeskEmployee  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 33 more reasons  
- **P2 home:Dashboard.NAV_DashboardExternal**: Role home page Dashboard.NAV_DashboardExternal works  
  roles: CallCenterEmployee  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  ... and 38 more reasons  
- **P2 home:Dashboard.NAV_DashboardInternal**: Role home page Dashboard.NAV_DashboardInternal works  
  roles: ServiceRegionManager  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 41 more reasons  
- **P2 home:General.Login_Web**: Role home page General.Login_Web works  
  roles: Anonymous  
  because document: FSM_Specific.LoginLayout: Layout changed at Content.Widgets[0].Top.Widgets[0].Appearance.DesignProperties[1].Key  
  because document: General.Login_Web: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[1].Widgets[0].Appearance.DesignProperties[0].Key  
- **P2 home:Technician.NAV_Technician_Home**: Role home page Technician.NAV_Technician_Home works  
  roles: Mechanic  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 33 more reasons  
- **P2 home:TicketManagement.Ticket_Overview_ServiceDesk**: Role home page TicketManagement.Ticket_Overview_ServiceDesk works  
  roles: CallCenterEmployee, FunctionalAdministrator, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 33 more reasons  
- **P2 menu:Administration > Accounts**: Open Administration > Accounts and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: ModuleIntegration_Administration_Impl.Account_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Application settings**: Open Administration > Application settings and use it  
  roles: TechnicalAdministrator  
  because document: AppSettings.Snippet_ApplicationSettings_Details: Snippet changed at Widgets[0].TabPages[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AppSettings.Snippet_SynchronizationError_Overview: Snippet changed at Widgets[0].DataSource.$Type  
- **P2 menu:Administration > Assets**: Open Administration > Assets and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  ... and 35 more reasons  
- **P2 menu:Administration > Business contacts**: Open Administration > Business contacts and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: CustomerManagement.ContactPerson_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: CustomerManagement.ContactPerson_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Contracts**: Open Administration > Contracts and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: CustomerManagement.Contract_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: CustomerManagement.Contract_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: CustomerManagement.SLA_Select: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: CustomerManagement.SLA_Select_Umbrella: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  ... and 1 more reasons  
- **P2 menu:Administration > Customers**: Open Administration > Customers and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: CustomerManagement.Customer_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: CustomerManagement.Customer_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Deeplink**: Open Administration > Deeplink and use it  
  roles: TechnicalAdministrator  
  because document: ModuleIntegration_DeepLink_Impl.Attribute_Select: Page changed at FormCall.Arguments[0].Parameter  
  because document: ModuleIntegration_DeepLink_Impl.Microflow_Select: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[0].DataSource.$Type  
  because document: ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkBasicDetails: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key  
  because document: ModuleIntegration_DeepLink_Impl.Snippet_DeeplinkConfigurationOverview: Snippet changed at Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  ... and 9 more reasons  
- **P2 menu:Administration > Feature toggles**: Open Administration > Feature toggles and use it  
  roles: ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: FeatureToggle.FeatureToggle_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Widgets[0].DataSource.$Type  
- **P2 menu:Administration > Load test**: Open Administration > Load test and use it  
  roles: TechnicalAdministrator  
  because document: LoadTest.LoadTestHelperNP_NewEdit: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
- **P2 menu:Administration > Masterdata views**: Open Administration > Masterdata views and use it  
  roles: TechnicalAdministrator  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_Details: Snippet changed at Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Snippet_Asset_Notes: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key  
  ... and 53 more reasons  
- **P2 menu:Administration > Offline actions**: Open Administration > Offline actions and use it  
  roles: ServiceRegionManager, TechnicalAdministrator  
  because document: Synchronization.OfflineAction_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].TabPages[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: Synchronization.OfflineAction_View: Page changed at FormCall.Arguments[0].Parameter  
- **P2 menu:Administration > Parts**: Open Administration > Parts and use it  
  roles: FunctionalAdministrator  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 22 more reasons  
- **P2 menu:Administration > Priorities**: Open Administration > Priorities and use it  
  roles: FunctionalAdministrator  
  because document: TicketManagement.Priority_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: TicketManagement.Priority_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Reasons**: Open Administration > Reasons and use it  
  roles: FunctionalAdministrator  
  because document: Reason.Reason_NewEdit: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: Reason.Reason_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: Reason.Reason_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: Reason.Snippet_Reason_Details: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key  
- **P2 menu:Administration > Registration codes**: Open Administration > Registration codes and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: TimeRegistration.RegistrationCode_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: TimeRegistration.RegistrationCode_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > SLA's**: Open Administration > SLA's and use it  
  roles: FunctionalAdministrator, ServiceDeskEmployee, TechnicalAdministrator  
  because document: AssetManagement.Asset_Select_Single: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: CustomerManagement.SLA_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: CustomerManagement.SLA_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Scripts**: Open Administration > Scripts and use it  
  roles: TechnicalAdministrator  
  because document: NativeModelCheck.NativeShadowModel_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Widgets[1].DataSource.$Type  
- **P2 menu:Administration > Skills**: Open Administration > Skills and use it  
  roles: FunctionalAdministrator  
  because document: Skill.Skill_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: Skill.Skill_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Systemlogs**: Open Administration > Systemlogs and use it  
  roles: TechnicalAdministrator  
  because document: ModuleIntegration_Logging_Impl.Message_Overview_Content_2: Snippet changed at Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: ModuleIntegration_Logging_Impl.Message_View_2: Page changed at FormCall.Arguments[0].Parameter  
- **P2 menu:Administration > Technician groups**: Open Administration > Technician groups and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: Technician.Snippet_TechnicianGroup_Details: Snippet changed at Widgets[0].Rows[0].Columns[0].Widgets[2].SelectorSource.DataSourceMicroflowSettings.ParameterMappings[len 0->1]  
  because document: Technician.TechnicianGroup_NewEdit: Page changed at FormCall.Arguments[0].Widgets[2].Rows[0].Columns[0].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: Technician.TechnicianGroup_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: Technician.TechnicianGroup_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Technicians**: Open Administration > Technicians and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  because document: Form.FormVersion_View: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: Form.InstanceForm_View: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[1].Key  
  ... and 21 more reasons  
- **P2 menu:Administration > Ticket types**: Open Administration > Ticket types and use it  
  roles: FunctionalAdministrator  
  because document: TicketManagement.TicketType_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: TicketManagement.TicketType_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Tools**: Open Administration > Tools and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: Tool.Tool_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: Tool.Tool_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Units of measurement**: Open Administration > Units of measurement and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager  
  because document: Part.UnitOfMeasure_NewEdit: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: Part.UnitOfMeasure_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: Part.UnitOfMeasure_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.FormSettings.ParameterMappings[len 0->1]  
- **P2 menu:Administration > Warehouses**: Open Administration > Warehouses and use it  
  roles: FunctionalAdministrator  
  because document: WarehouseManagement.Inventory_NewEdit: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Widgets[0].Widgets[0].SelectorSource.$Type  
  because document: WarehouseManagement.Inventory_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: WarehouseManagement.Snippet_Warehouse_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: WarehouseManagement.Warehouse_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  ... and 1 more reasons  
- **P2 menu:Alerts**: Open Alerts and use it  
  roles: ServiceDeskEmployee  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 34 more reasons  
- **P2 menu:Dashboard**: Open Dashboard and use it  
  roles: CallCenterEmployee, ServiceRegionManager  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].ControlBar.NewButtons[1].Action.FormSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  ... and 47 more reasons  
- **P2 menu:Forms**: Open Forms and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: Form.FormVersion_NewEdit: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: Form.FormVersion_Select_TicketType: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[0].ControlBar.NewButtons[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: Form.FormVersion_View: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[1].Widgets[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: Form.Form_Overview: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  ... and 3 more reasons  
- **P2 menu:Grids templates**: Open Grids templates and use it  
  roles: TechnicalAdministrator  
  because document: Dashboard.Grids: Page changed at FormCall.Arguments[0].Widgets[1].Rows[0].Columns[0].Widgets[0].TabPages[0].Widgets[0].DataSource.$Type  
- **P2 menu:Scheduler**: Open Scheduler and use it  
  roles: Mechanic, ServiceDeskEmployee, ServiceRegionManager  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_Details: Snippet changed at Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Snippet_Asset_Notes: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key  
  ... and 26 more reasons  
- **P2 menu:Tickets**: Open Tickets and use it  
  roles: CallCenterEmployee, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because document: AssetManagement.Asset_AssetPart_AddToBOM: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Appearance.DesignProperties[0].Key  
  because document: AssetManagement.Asset_Select_Multi: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: AssetManagement.Asset_View: Page changed at FormCall.Arguments[0].Widgets[0].Widgets[1].Widgets[0].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: AssetManagement.Snippet_Asset_DataTabs: Snippet changed at Widgets[0].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
  ... and 33 more reasons  
- **P2 menu:Work orders**: Open Work orders and use it  
  roles: FunctionalAdministrator, TechnicalAdministrator  
  because document: Form.WorkOrder_FormVersionSelect: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: MasterData.Skill_Select: Page changed at FormCall.Arguments[0].Widgets[0].DataSource.$Type  
  because document: Part.SuggestedPart_NewEdit: Page changed at FormCall.Arguments[0].Widgets[0].Rows[0].Columns[0].Widgets[0].Widgets[0].ControlBar.NewButtons[1].Action.MicroflowSettings.ParameterMappings[len 0->1]  
  because document: TicketManagement.Snippet_WorkOrder_Edit: Snippet changed at Widgets[0].Appearance.DesignProperties[0].Key  
  ... and 5 more reasons  
- **P2 module-pages:DeepLink**: Open the changed DeepLink pages a role can reach and look at them (screenshot old vs new)  
  roles: TechnicalAdministrator  
  because module: DeepLink updated; 1 changed role-gated pages: DeepLink.Attribute_Select  
- **P2 module-pages:Logging**: Open the changed Logging pages a role can reach and look at them (screenshot old vs new)  
  roles: TechnicalAdministrator  
  because module: Logging updated; 1 changed role-gated pages: Logging.Message_View  
- **P2 page:NativeMobile.Home_Native_Mechanic**: Reach NativeMobile.Home_Native_Mechanic (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.Snippet_NativeAppointment_CurrentList: Snippet changed at Widgets[0].Widgets[0].DataSource.ParameterMappings[len 0->1]  
- **P2 page:NativeMobile.Login**: Reach NativeMobile.Login (no menu item; opened from another page)  
  roles: Anonymous  
  because caller: NativeMobile.ACT_SignInUser: calls NanoflowCommons.SignIn (changed)  
- **P2 page:NativeMobile.NativeAppointmentNP_Overview**: Reach NativeMobile.NativeAppointmentNP_Overview (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.NativeWorkOrderAssignment_Overview: Page changed at FormCall.Arguments[1].Widgets[0].OnClickAction.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_Form_ListDisplay: Snippet changed at Widgets[0].OnClickAction.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeAppointment: Snippet changed at Widgets[1].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeAppointment_AssetDetails: Snippet changed at Widgets[0].Widgets[0].DataSource.ParameterMappings[len 0->1]  
  ... and 16 more reasons  
- **P2 page:NativeMobile.NativeAppointment_Details**: Reach NativeMobile.NativeAppointment_Details (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.Snippet_Form_ListDisplay: Snippet changed at Widgets[0].OnClickAction.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeAppointment: Snippet changed at Widgets[1].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeAppointment_AssetDetails: Snippet changed at Widgets[0].Widgets[0].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeAppointment_ProceedButtons: Snippet changed at Widgets[0].Widgets[0].DataSource.ParameterMappings[len 0->1]  
  ... and 10 more reasons  
- **P2 page:NativeMobile.NativeAppointment_NotResolved_InvoiceSummary**: Reach NativeMobile.NativeAppointment_NotResolved_InvoiceSummary (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.Snippet_NativeAppointment_WorkDetails: Snippet changed at Widgets[6].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeInvoiceSummaryHelper_HoursWorked: Snippet changed at Widgets[0].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativePartsInvoice: Snippet changed at Widgets[0].Widgets[1].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobileTimeRegistration.NativeTimeRegistrationNP_NewEdit: Page changed at FormCall.Arguments[0].Widgets[0].CenterRegion.Widgets[0].Widgets[0].Widgets[0].SelectorSource.$Type  
  ... and 1 more reasons  
- **P2 page:NativeMobileRelated.NativeAppointmentNP_Details**: Reach NativeMobileRelated.NativeAppointmentNP_Details (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobileRelated.Snippet_NativeNoteNPList: Snippet changed at Widgets[0].OnClickAction.ParameterMappings[len 0->1]  
  because document: NativeMobileRelated.Snippet_NativeWorkOrderNP_BasicDetails: Snippet changed at Widgets[0].Widgets[1].Widgets[0].FormCall.ParameterMappings[len 0->1]  
- **P2 page:NativeMobileRelated.NativeWorkOrderNP_Load**: Reach NativeMobileRelated.NativeWorkOrderNP_Load (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobileRelated.Snippet_NativeWorkOrderNP_Details: Snippet changed at Widgets[1].TabPages[0].Widgets[0].FormCall.ParameterMappings[len 0->1]  
- **P2 page:NativeMobileRelated.NativeWorkOrderNP_Overview**: Reach NativeMobileRelated.NativeWorkOrderNP_Overview (no menu item; opened from another page)  
  roles: Mechanic  
  because document: NativeMobile.NativeWorkOrderAssignment_Overview: Page changed at FormCall.Arguments[1].Widgets[0].OnClickAction.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeWorkOrder_ProceedButtons: Snippet changed at Widgets[0].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobile.Snippet_NativeWorkorder: Snippet changed at Widgets[1].Widgets[0].Widgets[0].Widgets[0].DataSource.ParameterMappings[len 0->1]  
  because document: NativeMobileRelated.Snippet_NativeNoteNPList: Snippet changed at Widgets[0].OnClickAction.ParameterMappings[len 0->1]  
  ... and 2 more reasons  
- **P2 page:TEST_NativeLocalLogin.Login**: Reach TEST_NativeLocalLogin.Login (no menu item; opened from another page)  
  roles: Anonymous  
  because caller: TEST_NativeLocalLogin.ACT_SignInUser: calls NanoflowCommons.SignIn (changed)  
- **P2 visual-smoke**: Smoke walk with screenshots over pages that use a changed layout  
  roles: CallCenterEmployee, FSMAPIConsumer, FunctionalAdministrator, Mechanic, ServiceDeskEmployee, ServiceRegionManager, TechnicalAdministrator  
  because caller: Atlas_Core.PopupLayout: layout changed; used by 64 own pages (theme/visual impact: smoke walk and screenshots, not one journey per page)  
- **P3 sched:Logging.CleanupDataLogging**: Scheduled event Logging.CleanupDataLogging still runs  
  roles: (system, no role)  
  because constant: Logging.CleanupFilter: added, default '' (String)  
  because scheduled: Logging.CleanupDataLogging: OnOverlap DelayNext -> SkipNext; call tree changed (1 documents)  

## Per role

- **Anonymous** home `General.Login_Web`; candidates: home:General.Login_Web, page:NativeMobile.Login, page:TEST_NativeLocalLogin.Login
- **CallCenterEmployee** home `Dashboard.NAV_DashboardExternal`; candidates: login-per-role, startup, home:Dashboard.NAV_DashboardExternal, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Assets, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Dashboard, menu:Forms, menu:Tickets, visual-smoke
- **FSMAPIConsumer** home `General.Login_Web`; candidates: login-per-role, startup, visual-smoke
- **FunctionalAdministrator** home `TicketManagement.Ticket_Overview_ServiceDesk`; candidates: login-per-role, startup, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Accounts, menu:Administration > Assets, menu:Administration > Business contacts, menu:Administration > Contracts, menu:Administration > Customers, menu:Administration > Parts, menu:Administration > Priorities, menu:Administration > Reasons, menu:Administration > Registration codes, menu:Administration > SLA's, menu:Administration > Skills, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Ticket types, menu:Administration > Tools, menu:Administration > Units of measurement, menu:Administration > Warehouses, menu:Forms, menu:Tickets, menu:Work orders, visual-smoke
- **Mechanic** home `Technician.NAV_Technician_Home`; candidates: login-per-role, startup, home:Technician.NAV_Technician_Home, menu:Administration > Assets, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Scheduler, menu:Tickets, page:NativeMobile.Home_Native_Mechanic, page:NativeMobile.NativeAppointmentNP_Overview, page:NativeMobile.NativeAppointment_Details, page:NativeMobile.NativeAppointment_NotResolved_InvoiceSummary, page:NativeMobileRelated.NativeAppointmentNP_Details, page:NativeMobileRelated.NativeWorkOrderNP_Load, page:NativeMobileRelated.NativeWorkOrderNP_Overview, visual-smoke
- **ServiceDeskEmployee** home `Dashboard.NAV_DashboardAll`; candidates: login-per-role, startup, home:Dashboard.NAV_DashboardAll, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Assets, menu:Administration > Business contacts, menu:Administration > Contracts, menu:Administration > Customers, menu:Administration > Feature toggles, menu:Administration > SLA's, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Alerts, menu:Forms, menu:Scheduler, menu:Tickets, visual-smoke
- **ServiceRegionManager** home `Dashboard.NAV_DashboardInternal`; candidates: login-per-role, startup, home:Dashboard.NAV_DashboardInternal, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Assets, menu:Administration > Feature toggles, menu:Administration > Offline actions, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Units of measurement, menu:Dashboard, menu:Forms, menu:Scheduler, menu:Tickets, visual-smoke
- **TechnicalAdministrator** home `TicketManagement.Ticket_Overview_ServiceDesk`; candidates: login-per-role, startup, home:TicketManagement.Ticket_Overview_ServiceDesk, menu:Administration > Accounts, menu:Administration > Application settings, menu:Administration > Assets, menu:Administration > Business contacts, menu:Administration > Contracts, menu:Administration > Customers, menu:Administration > Deeplink, menu:Administration > Feature toggles, menu:Administration > Load test, menu:Administration > Masterdata views, menu:Administration > Offline actions, menu:Administration > Registration codes, menu:Administration > SLA's, menu:Administration > Scripts, menu:Administration > Systemlogs, menu:Administration > Technician groups, menu:Administration > Technicians, menu:Administration > Tools, menu:Forms, menu:Grids templates, menu:Tickets, menu:Work orders, module-pages:DeepLink, module-pages:Logging, visual-smoke
