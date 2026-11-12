# RA-20 on a public template: what ran and what was measured (2026-10-23)

App: a public Marketplace starter app (content id 235403, app 1.0.0, Mendix 10.15.0.46408) with OIDC 3.1.0, UserCommons 1.0.2, Administration 4.1.0,
Encryption 10.0.3, MxModelReflection 8.0.3, NanoflowCommons 4.0.4; after-startup already `OIDC.ASU_OIDC_Startup`; roles Administrator, User, Anonymous.
No public template holds an OIDC below 3.0.0 (candidates.md), so the first two steps of the recipe were not tried.

| step | tool | result |
|---|---|---|
| convert to 11.12.5 | `mx convert --in-place` (11.12.5) | refused: "The version '10.15.0.46408' of the mpr file is not supported". The 10.24 rung comes first |
| convert to 10.24.0 | `mx convert --in-place` (10.24.0.73019) | done; `mx check`: 0 errors |
| edits in OIDC 3.1.0 | `bin/localedits.py --module OIDC --mxcli-diff` | domain model unchanged; 11 elements differ from the published 3.1.0: MICROFLOW SUB_CreateOrUpdate_UserProvisioning, SUB_HandlingClaims, handleAuthorizationCode; NANOFLOW ACT_StartWebSignIn; PAGE Claim_Select, OIDC_ClientGrant_NewEdit, OIDC_ClientGrant_View, OIDC_Client_NewEdit, OIDC_Client_View, Scope_Select; SNIPPET Snip_Login_Button; plus 8 JAR_DEPENDENCY rows (package-owned) |
| the same on the 10.15 original | `bin/localedits.py --mxcli-diff` | UNKNOWN: "Comparing across versions reports Mendix's own conversions as local edits, so this is refused". It is therefore not known whether the 11 elements are the template's own customisation or made by the convert |
| step 1: OIDC 3.1.0 to 4.0.1 | `bin/stepupdate.sh` (update command `mxcli marketplace update 120371 --to 4.0.1`) | STOPPED: "OIDC has local LOGIC edits (JAR_DEPENDENCY MICROFLOW NANOFLOW): keep the module at the installed version, or port the edits by hand". Nothing committed, nothing forced |

Stopped at the first step of the path, by the toolkit's own rule (a logic edit is never overwritten unattended). Not run: 4.0.1, 4.1.x, 4.2.0 with its
migration microflow, 4.2.1, 4.4.0, 4.5.0 (PKCE, Anonymous role), UserCommons 2.x, the build, the start, the login page, any journey, any IdP flow.
IdP part: not measured, no IdP reachable. RA-20 stays `idea`.

New facts for the entry: (1) step 1 of the recipe must run `localedits.py --mxcli-diff` and list the edited flows before any update; in this template
three claim-handling microflows and the web sign-in nanoflow differ from the package, which is exactly the code that decides who may log in;
(2) the Marketplace catalogue already lists OIDC SSO 5.0.0 and UserCommons 3.0.0 (min Mendix 10.24.0); the release-note records in the brain stop at 4.7.0 and 2.4.0, so read the newer notes before picking the target;
(3) a 10.x project below 10.24 has to take the 10.24 rung before 11.12.5 will open it.
