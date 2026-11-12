-- seedname_fix.py control: a SYNTHETIC app database (mapping tables plus two entity tables), no customer names.
-- Cfg.Provisioning holds configuration strings the way seed_pg.py filled them: the SAME synthetic value in every String column.
CREATE TABLE "mendixsystem$entity"(id varchar(36) primary key, entity_name varchar(200), table_name varchar(200), superentity_id varchar(36), remote boolean);
CREATE TABLE "mendixsystem$attribute"(id varchar(36) primary key, entity_id varchar(36), attribute_name varchar(200), column_name varchar(200), type int, length int);
CREATE TABLE "system$user"(id bigint primary key, name varchar(200), password varchar(200));
CREATE TABLE "cfg$provisioning"(id bigint primary key, customentity varchar(200), customentitymember varchar(200), identifier varchar(200), label varchar(200));
INSERT INTO "mendixsystem$entity" VALUES ('e1', 'System.User', 'system$user', NULL, false), ('e2', 'Cfg.Provisioning', 'cfg$provisioning', NULL, false);
INSERT INTO "mendixsystem$attribute" VALUES ('a1', 'e1', 'Name', 'name', 30, 200), ('a2', 'e1', 'Password', 'password', 30, 200),
 ('a3', 'e2', 'CustomEntity', 'customentity', 30, 200), ('a4', 'e2', 'CustomEntityMember', 'customentitymember', 30, 200),
 ('a5', 'e2', 'Identifier', 'identifier', 30, 200), ('a6', 'e2', 'Label', 'label', 30, 200);
INSERT INTO "system$user" VALUES (1, 'admin', NULL);
INSERT INTO "cfg$provisioning" VALUES (1, 's9x2', 's9x2', 's9x2', 's9x2'), (2, 's9x3', 's9x3', 's9x3', 's9x3'), (3, 'Real.Entity', 'RealMember', 'keep', 'keep');
