# idcheck <run>/new-10.24.28.129343.mda (mda) -> <run>/new-11.12.7.mda (mda)

elements old: 309 entities, 1470 attributes, 302 associations
elements new: 318 entities, 1514 attributes, 321 associations
findings: 2 total, 1 RED (data-bearing), 1 of them approved, 0 open

info REMOVED      association System.WorkflowActivityRecord_PreviousActivity  (no data)
appr REMOVED      attribute   System.TokenInformation.ReadOnlyHashKey  (column/table dropped; intended?)  [approved: platform System module attribute removed by Mendix 11; upg_fsm_steps_r2_base (10.24) has 13 TokenInformation rows and 0 ReadOnlyHashKey values, so no data is lost; not used by the app]

verdict: PASS  (FAIL = open data-bearing GUID change; REVIEW = open data-bearing removals or persistence loss only: confirm each is intended, then add it to the approved list / allow-list)
