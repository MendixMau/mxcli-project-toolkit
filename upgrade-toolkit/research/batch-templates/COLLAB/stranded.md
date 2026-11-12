# Stranded modules (steps/triage.md item 3)

- DemoUserSwitcher: installed 1.1.0 (content 120303); `mxcli marketplace versions 120303` lists no version at all, so nothing can be planned for 10.24 or 11. Owns Administration association DemoUser_Helper_Account.
- MES_Atlas_Extension: installed 2.0.1 (content 120035); no version listed for that content id.
- (held, not stranded) CommunityCommons 9.0.0, NanoflowCommons 2.3.1, Administration 2.1.0 stay at their versions because the kept DemoUserSwitcher calls their old API (crosscalls.py CAP lines); newer versions exist for 10.24.
