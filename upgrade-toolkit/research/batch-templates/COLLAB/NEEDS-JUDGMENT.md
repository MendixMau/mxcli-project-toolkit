# NEEDS JUDGMENT: step basewalk, exit 11

run folder: <run>
work: <run>/work
source 9.18.0.53394 -> target 10.24.0.73019
Rule: the items below are pending, not passed: a REGRESSION is fixed, the rest are decided in writing (allow/approved files named in steps/*.md), then rerun:

    <toolkit>/upgrade-toolkit/bin/cloud/upgrade-pipeline.sh --app-zip <dl>/Collaboration_Portal.mpk --source 9.18.0.53394 --target 10.24.0.73019 --target2 11.12.5 --work <run>/work --from basewalk

## Always-on journeys are not all PASS on the OLD app (exit 3): fix the journey, drop it, or write the todo (exit 11)

file: <run>/work/journeys-base.out

```
  role CustomerContact          login INVALID login faulted: "credentials rejected" — not a credential fai
  role SupplierContact          login INVALID login faulted: "credentials rejected" — not a credential fai
  INVALID login-CustomerContact                                   login INVALID: login faulted: "credentials rejected" — not a credential failure. The runtime refused the session (measured cause on 2026-08-18: trial-
  INVALID login-SupplierContact                                   login INVALID: login faulted: "credentials rejected" — not a credential failure. The runtime refused the session (measured cause on 2026-08-18: trial-
  INVALID anonymous-Anonymous                                     anonymous role: no process PASSes as it
  INVALID create-save                                             todo: no --create spec: write one core create-and-save spec per app at baseline (widget names are app-specific)
journeys: 6 PASS, 0 FAIL, 4 INVALID
actions ? found · 8 journeys (todo unknown) · 6 pass on baseline (2 defect) · - pass on new · - regression · coverage ? (no actions.json: coverage unknown)
verdict: INVALID only (exit 3): no REGRESSION, no open REVIEW; 4 journeys INVALID, 0 SCREEN INVALID, 0 failing on the baseline, 0 EFFECT INVALID
```

## Plan items (exit 11)

plan: <run>/work/journeys-base/plan.json (skipped, todo, not_browser). An MFA journey needs a user with an MFA type (users.json `_mfa`); this script cannot create one.
