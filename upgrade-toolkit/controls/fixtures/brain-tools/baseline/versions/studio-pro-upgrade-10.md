# Studio Pro 10 upgrade notes (synthetic control fixture for the T6R-5 rules of release_impact.py --auto)

Row texts are the real 10.x table's wording (T6R run, Checklist 9.24.2 to 10.24.26).

| version | date | type | area | change | affected | source |
|---|---|---|---|---|---|---|
| 10.0.0 | Mar 1 | removal | java-actions | Removed deprecated error constants from AdminException and IMxRuntime. | AdminException, IMxRuntime | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | removal | java-actions | Removed deprecated rollbackTransAction() method from public IContext interface. Use rollbackTransaction instead. | IContext.rollbackTransAction() | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | removal | java-actions | Removed deprecated methods from the Mendix Runtime API and the M2EE API. | Mendix Runtime API, M2EE API | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | removal | java-actions | Removed deprecated IActionRegistrator#bundleComponentLoaded method. | IActionRegistrator#bundleComponentLoaded | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | breaking | java-actions | IDataTable, IDataTableSchema, IDataColumnSchame no longer provide equality; equals() and hashCode() based on object identity. | IDataTable, IDataTableSchema, IDataColumnSchame | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | removal | git-teamserver | All SVN support has been removed. Migrate to Git using provided documentation. | SVN | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.3.0 | Mar 2 | breaking | mxbuild-cli | Removed Build Using Gradle option from Deployment settings. Now always uses Gradle. | Build Using Gradle, Deployment settings | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.3/) |
| 10.7.0 | Mar 3 | requirement | git-teamserver | Studio Pro now blocks Rebase feature when installed Git version is below 2.41. | Rebase feature, Git | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.7/) |
| 10.18.0 | Mar 4 | requirement | mxbuild-cli | We no longer support Gradle versions below 8.5. | Gradle | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.18/) |
| 10.22.0 | Mar 5 | requirement | mxbuild-cli | Command line tools now support arm64 architectures without installing dotnet runtime x64. | command line tools, arm64 | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.22/) |
| 10.22.0 | Mar 5 | removal | git-teamserver | Retracted mx.exe git-merge command to prevent unexpected issues after automatic merge driver configuration in 10.21. | mx.exe git-merge | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.22/) |
