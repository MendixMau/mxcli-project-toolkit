# Studio Pro 10 upgrade notes (synthetic control fixture for release_impact.py --auto)

Row texts follow the real 10.x table's wording; the newest row is 10.8.0 (the to-above-table controls).

| version | date | type | area | change | affected | source |
|---|---|---|---|---|---|---|
| 10.0.0 | Mar 1 | removal | data-storage | Dropped support for MariaDB 10.3 and MySQL 5.7, no longer supported by the vendor. | MariaDB, MySQL | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | removal | data-storage | Dropped support for PostgreSQL 11, no longer supported by vendor. | PostgreSQL 11 | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | removal | data-storage | Fixture: dropped support for PostgreSQL 16. | PostgreSQL 16 | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | requirement | data-storage | Fixture: PostgreSQL versions below 17 need a setting. | PostgreSQL | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.0.0 | Mar 1 | deprecation | data-storage | Deprecated slashes in Amazon S3 bucket names. | Amazon S3 | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.0/) |
| 10.1.0 | Mar 2 | requirement | studio-pro-ide | Studio Pro now runs on .NET 10 instead of .NET 8. | .NET | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.1/) |
| 10.2.0 | Mar 3 | breaking | odata-rest | Published OData services now give a consistency error when an exposed attribute name matches the entity name. | published OData | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.2/) |
| 10.2.0 | Mar 3 | removal | odata-rest | Fixture: removed the custom reason phrase of HTTP responses. | IMxRuntimeResponse | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.2/) |
| 10.3.0 | Mar 4 | breaking | workflow | Renamed WorkflowUserTask_Assignee to WorkflowUserTask_Assignees. | Workflows | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.3/) |
| 10.4.0 | Mar 5 | removal | native-mobile | Discontinued CodePush support. | CodePush | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.4/) |
| 10.5.0 | Mar 6 | breaking | runtime | Duplicate column names in OQL query no longer allowed. | OQL | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.5/) |
| 10.6.0 | Mar 7 | breaking | runtime | Fixture runtime breaking change without a feature token. | Runtime | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.6/) |
| 10.6.0 | Mar 7 | deprecation | java-actions | Deprecated Core.executeVoid method. Use Core.execute instead. | Core.executeVoid | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.6/) |
| 10.6.0 | Mar 7 | removal | java-actions | Removed Core.retrieveXPathQuery. | Core.retrieveXPathQuery | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.6/) |
| 10.7.0 | Mar 8 | breaking | odata-rest | Fixed XML parser in web service and OData v3 services to reject DTD declarations. | call web service activity, consumed OData services | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.7/) |
| 10.8.0 | Mar 9 | removal | client-web | Removed the legacy document template widget fixture. | document templates | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.8/) |
| 10.8.0 | Mar 9 | breaking | studio-pro-ide | Curly braces in placeholder text must now be escaped (e.g., {{Name}} instead of {Name}). | placeholder text | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.8/) |
| 10.8.0 | Mar 9 | requirement | studio-pro-ide | New projects will now use Java 21 by default. | Java 21 | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.8/) |
| 10.8.0 | Mar 9 | requirement | external-entities | External Database Connector version 2.0.1 or below has compatibility issues in Mendix 10.8. | External Database Connector | [notes](https://docs.mendix.com/releasenotes/studio-pro/10.8/) |
