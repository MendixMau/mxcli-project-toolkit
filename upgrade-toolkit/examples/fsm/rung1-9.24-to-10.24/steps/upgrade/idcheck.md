# idcheck <run>/old-9.24.2.6130.mda (mda) -> <run>/new-10.24.28.129343.mda (mda)

elements old: 304 entities, 1423 attributes, 290 associations
elements new: 309 entities, 1470 attributes, 302 associations
findings: 7 total, 4 RED (data-bearing), 4 of them approved, 0 open

info RENAMED      association System.WorkflowActivity_TaskActor  -> System.WorkflowActivity_Actor
info RENAMED      association System.WorkflowUserTask_Assignee  -> System.WorkflowUserTask_Assignees
info RENAMED      attribute   System.WorkflowActivity.Error  -> System.WorkflowActivity.Reason
appr REMOVED      attribute   System.DataBrokerEntityMetadata.EntityId  (column/table dropped; intended?) [entity also gone]  [approved: platform entity dropped by Mendix 10; 0 rows in upg_fsm_steps_base_r2, no user data, not used by the app]
appr REMOVED      attribute   System.DataBrokerEntityMetadata.MemberDetails  (column/table dropped; intended?) [entity also gone]  [approved: platform entity dropped by Mendix 10; 0 rows in upg_fsm_steps_base_r2, no user data, not used by the app]
appr REMOVED      attribute   System.WorkflowActivity.IsMigrationActivity  (column/table dropped; intended?)  [approved: platform attribute removed by Mendix 10 workflows; 0 of 0 WorkflowActivity rows in upg_fsm_steps_base_r2 (app has no workflow data)]
appr REMOVED      entity      System.DataBrokerEntityMetadata  (column/table dropped; intended?)  [approved: platform entity dropped by Mendix 10; 0 rows in upg_fsm_steps_base_r2, no user data, not used by the app]

verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is intended, then add it to the approved list / allow-list)
