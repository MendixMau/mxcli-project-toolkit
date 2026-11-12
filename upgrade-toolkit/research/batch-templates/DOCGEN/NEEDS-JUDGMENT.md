# NEEDS JUDGMENT: step baseline, exit 10

run folder: <run>
work: <run>/work
source 10.24.21.108016 -> target 11.12.5
Rule: the items below are pending, not passed: a REGRESSION is fixed, the rest are decided in writing (allow/approved files named in steps/*.md), then rerun:

    <toolkit>/upgrade-toolkit/bin/cloud/upgrade-pipeline.sh --app-zip <dl>/DocGen_Showcase.mpk --source 10.24.21.108016 --target 11.12.5 --work <run>/work --from baseline

## OLD app does not build (exit 3) (exit 10)

file: <run>/work/logs/baseline.log

```
Checking for errors...
ERROR: An error occurred while creating the deployment package.
Checking for errors...
ERROR: An error occurred while creating the deployment package.
```
