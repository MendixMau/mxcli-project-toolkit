# Stranded and kept modules (steps/triage.md item 3)

- DemoUserSwitcher: installed 1.1.0 (content 120303); no version listed for the content id, nothing can be planned. Owns Administration association DemoUser_Helper_Account.
- NativeMobileResources: installed 2.0.1 (content 116537); no version listed for the content id.
- TcConnector: installed 3.5.0 (content 111627) is not in the listing; the newest listed (2512.1.x) needs Studio Pro 10.24.8, the toolset here is 10.24.0.
- PushNotifications: installed 5.3.0 (content 3003) has 3 RED data-bearing local edits (localedits.md); 8.0.x fits 10.24 but replacing it would recreate those elements: kept by the SKILL stop rule.
- AmazonRekognitionConnector: installed 1.0.0 with content id 0 in the MPR (Marketplace id 204717, newest 3.0.1); not judged, kept.
- (held, not stranded) Administration 2.1.2, CommunityCommons 9.0.1, Encryption 9.0.1, NanoflowCommons 3.0.0: the kept DemoUserSwitcher / PushNotifications call their old API (crosscalls.py CAP lines).
