# Studio Pro 11 upgrade notes (synthetic control fixture for release_impact.py --auto, N1-9)

Row texts follow the real 11.x table's wording; rows marked Fixture are invented to hit one rule edge. Newest row 11.12.3.

| version | date | type | area | change | affected | source |
|---|---|---|---|---|---|---|
| 11.6.5 | Jan 1 | requirement | runtime | Updated .NET runtime version installed with Studio Pro to .NET 10.0.3. | .NET, Studio Pro | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.6.6 | Jan 1 | deprecation | data-storage | From July 6, 2026, support for PostgreSQL 13 and MariaDB 10.6 will be dropped. | PostgreSQL 13, MariaDB 10.6 | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.6.7 | Jan 1 | requirement | runtime | .NET Runtime updated to version 10.0.7. | .NET Runtime | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.6.8 | Jan 1 | breaking | studio-pro-ide | Studio Pro on macOS now runs natively on Apple Silicon (arm64). Intel-based Macs are no longer supported. | Studio Pro, macOS, Apple Silicon, arm64, Intel Mac | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.7.0 | Jan 1 | deprecation | data-storage | From July 6, 2026, support for PostgreSQL 16 will be dropped (fixture: your own version). | PostgreSQL 16 | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.8.0 | Jan 1 | deprecation | runtime | Hebrew language code changed from iw_IL (deprecated) to he_IL (current ISO 639 standard). | Hebrew language code, iw_IL | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.8.0 | Jan 1 | deprecation | runtime | Indonesian language code changed from in_ID (deprecated) to id_ID (current ISO 639 standard). | Indonesian language code, in_ID | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.8.1 | Jan 1 | deprecation | studio-pro-ide | Deprecated Serbian (Serbia and Montenegro) language code sr_CS, replaced by sr_RS and sr_ME. | Serbian (Serbia and Montenegro), sr_CS, sr_RS, sr_ME | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.9.0 | Jan 1 | requirement | data-storage | Upgraded JDBC driver for Microsoft SQL Server to version 13.4.0. Integrated security users may need to update userlib JDBC driver. | Microsoft SQL Server JDBC driver, Database Connector | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.9.1 | Jan 1 | requirement | data-storage | Fixture: upgraded PostgreSQL JDBC driver to version 42.7.8. | PostgreSQL JDBC driver | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.9.2 | Jan 1 | requirement | data-storage | Fixture: upgraded JDBC driver; the Database Connector module may need a driver update in userlib. | JDBC driver, Database Connector | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
| 11.12.3 | Jan 1 | breaking | security | Requests to servlets registered via Core.addDevelopmentServlet now require authentication with M2EE admin password in X-M2EE-Authentication header (Base64-encoded). | Core.addDevelopmentServlet, X-M2EE-Authentication | [notes](https://docs.mendix.com/releasenotes/studio-pro/11.0/) |
