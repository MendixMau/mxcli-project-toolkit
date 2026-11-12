# NEEDS JUDGMENT: step baseline, exit 10

run folder: <run>
work: <run>/work
source 9.3.0.22930 -> target 10.24.0.73019
Rule: the items below are pending, not passed: a REGRESSION is fixed, the rest are decided in writing (allow/approved files named in steps/*.md), then rerun:

    <toolkit>/upgrade-toolkit/bin/cloud/upgrade-pipeline.sh --app-zip <dl>/Incentro_Layouts.mpk --source 9.3.0.22930 --target 10.24.0.73019 --target2 11.12.5 --work <run>/work --from baseline

## OLD app does not build (exit 3) (exit 10)

file: <run>/work/logs/baseline.log

```
 * Checking for errors...
ERROR: The project cannot be deployed, because it contains errors.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Container 'container1': Design property Spacing top is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Container 'container1': Design property Spacing bottom is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Container 'container1': Design property Spacing left is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Container 'container1': Design property Spacing right is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Container 'container1': Design property Align content is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Sidebar toggle 'sidebarToggle1': Design property Size is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Sidebar toggle 'sidebarToggle1': Design property Spacing left is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Sidebar toggle 'sidebarToggle1': Design property Full width is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Image 'image2': Design property Center is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_Sidebar', Image 'image2': Design property Spacing right is not supported by your theme. Right-click to see more options.
ERROR at -, Navigation, Default home page of navigation profile 'Responsive': Select a default home page for this profile in the navigation document.
ERROR at IncentroLayouts, Layout 'Phone_BottomBar', Image 'image1': Design property Center is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_BottomBar', Image 'image1': Design property Spacing top is not supported by your theme. Right-click to see more options.
ERROR at IncentroLayouts, Layout 'Phone_BottomBar', Image 'image1': Design property Spacing bottom is not supported by your theme. Right-click to see more options.
```
