| app part | count | regression test | automated? |
|---|---|---|---|
| Persistent entities | 173 (133 in own modules) | data survival: per-entity row count + per-attribute checksum + association pairs, before vs after on a COPY of the same DB | auto: seed_pg.py, snapshot.py, diff.py |
| Entities with event handlers | 6 | commit/delete through the app (journey or unit test) so before/after-commit logic runs | auto if journeys exist, else human |
| Published REST operations | 6 (1 safe GET probes, 4 flagged: side effect or parameters) | OpenAPI contract diff (auto) + one live call per GET without parameters (auto) + write calls with test payloads | auto contract; payloads human-authored once |
| Consumed REST / web services | 0 clients, 4 call activities | outbound call against a mock or sandbox; check encoding, auth, TLS (PKIX) after the Java/runtime change | human or mock server |
| OData published / consumed | 0 / 0 (built-in client); 0 references into OData connector modules (none): consumed OData if > 0 | $metadata diff + one query per entity set | auto |
| Scheduled events | 9 (5 enabled) | enabled state and interval unchanged (model diff); trigger the microflow once in test (admin API or unit test) and check its side effect | auto diff; trigger semi-auto |
| Java actions | 167 (4 in own modules) | compile is proved by the build; behaviour needs a unit test per own Java action (Unit Testing module or mxcli test) | build auto; unit tests human-authored |
| Role home pages and menu | 9 homes, 42 menu items | per role: log in, land on home, open each menu target, no client error (journey-runner) | auto once journeys are written |
| Pluggable widgets | 27 types | page renders with no console error; visual diff on the pages that use the widget | auto render; visual review human |
| Jar dependencies | 16 userlib + 23 vendorlib files (18 managed in the catalog); 0 duplicated by artifact identity, present BEFORE the upgrade; upgrade-sensitive: bcprov-jdk18on-1.81.jar, commons-codec-1.15.jar, commons-email-1.5.jar, commons-io-2.21.0.jar, commons-lang3-3.20.0.jar, commons-logging-1.3.5.jar, commons-text-1.14.0.jar, guava-33.5.0-jre.jar | userlib/vendorlib diff; duplicate jars by artifact (bin/repair/jardedupe.py); runtime start log has no ClassNotFound/NoSuchMethod | auto |
| Add-on modules (.mxmodule) | 0 | mx check on each rung; a vendor binary cannot be reopened, so one built before 10.21 needs a newer vendor build (playbook 10-to-11, blocker 9); idcheck old vs new | auto check; vendor build human |
| Marketplace modules | 16 | mxcli marketplace diff per module BEFORE updating (local edits get overwritten); after: module version table | auto |
| Workflows / business events | 0 / 0 | in-flight workflow instances survive; event contract unchanged | auto data rung + human |
