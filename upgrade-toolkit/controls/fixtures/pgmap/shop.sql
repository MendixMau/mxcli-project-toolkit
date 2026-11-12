-- pgmap.py / pgdata.js controls (E2E-9): a SYNTHETIC app database in the shape the Mendix runtime writes (mapping tables
-- plus entity tables), no customer names. Runs unchanged on SQLite (lib/sqlitepsql.py) and Postgres (lib/pgtmp.sh).
-- Shop.Item specializes Shop.Base (one row per level, same id); Shop.Item_Category is column storage (FK on the owner's
-- table, parent_column_name "id"); Shop.Item_Tag is table storage; Shop.Base_Tag is column storage on the
-- generalization's table; Shop.Bad_Category is an inconsistent row (an entity table with a non-id parent column) and
-- must be refused; the long entity's table name is cut at 63 bytes by Postgres, so the table below is created with the
-- cut name while the mapping keeps the full one; Shop.Remote is an external entity without a table.
CREATE TABLE "mendixsystem$entity"(id varchar(36) primary key, entity_name varchar(200), table_name varchar(200), superentity_id varchar(36), remote boolean);
CREATE TABLE "mendixsystem$attribute"(id varchar(36) primary key, entity_id varchar(36), attribute_name varchar(200), column_name varchar(200), type int, length int);
CREATE TABLE "mendixsystem$association"(id varchar(36) primary key, association_name varchar(200), table_name varchar(200), parent_entity_id varchar(36), child_entity_id varchar(36), parent_column_name varchar(200), child_column_name varchar(200));
CREATE TABLE "shop$base"(id bigint primary key, code varchar(50), "shop$base_tag" bigint);
CREATE TABLE "shop$item"(id bigint primary key, name varchar(200), price decimal(28,8), "shop$item_category" bigint);
CREATE TABLE "shop$category"(id bigint primary key, title varchar(200));
CREATE TABLE "shop$tag"(id bigint primary key, label varchar(200));
CREATE TABLE "shop$item_tag"("shop$itemid" bigint not null, "shop$tagid" bigint not null, primary key("shop$itemid", "shop$tagid"));
CREATE TABLE "shop$averylongentitynamethatmakesthetablenamelongerthansixtythr"(id bigint primary key, note varchar(200));
CREATE TABLE "system$session"(id bigint primary key, sessionid varchar(36));
INSERT INTO "mendixsystem$entity" VALUES
 ('e1', 'Shop.Base', 'shop$base', NULL, false), ('e2', 'Shop.Item', 'shop$item', 'e1', false),
 ('e3', 'Shop.Category', 'shop$category', NULL, false), ('e4', 'Shop.Tag', 'shop$tag', NULL, false),
 ('e5', 'System.Session', 'system$session', NULL, false),
 ('e6', 'Shop.AVeryLongEntityNameThatMakesTheTableNameLongerThanSixtyThreeBytes',
  'shop$averylongentitynamethatmakesthetablenamelongerthansixtythreebytes', NULL, false),
 ('e7', 'Shop.Remote', 'shop$remote', NULL, true);
INSERT INTO "mendixsystem$attribute" VALUES
 ('a1', 'e1', 'Code', 'code', 30, 50), ('a2', 'e2', 'Name', 'name', 30, 200), ('a3', 'e2', 'Price', 'price', 5, 0),
 ('a4', 'e3', 'Title', 'title', 30, 200), ('a5', 'e4', 'Label', 'label', 30, 200), ('a6', 'e6', 'Note', 'note', 30, 200),
 ('a7', 'e5', 'SessionId', 'sessionid', 30, 36);
INSERT INTO "mendixsystem$association" VALUES
 ('s1', 'Shop.Item_Category', 'shop$item', 'e2', 'e3', 'id', 'shop$item_category'),
 ('s2', 'Shop.Item_Tag', 'shop$item_tag', 'e2', 'e4', 'shop$itemid', 'shop$tagid'),
 ('s3', 'Shop.Base_Tag', 'shop$base', 'e1', 'e4', 'id', 'shop$base_tag'),
 ('s4', 'Shop.Bad_Category', 'shop$category', 'e2', 'e3', 'shop$itemid', 'shop$categoryid');
INSERT INTO "shop$base" VALUES (1, 'C1', 20), (2, 'C2', NULL);
INSERT INTO "shop$item" VALUES (1, 'Apple', 1.5, 10), (2, 'Pear', 2.25, NULL);
INSERT INTO "shop$category" VALUES (10, 'Fruit');
INSERT INTO "shop$tag" VALUES (20, 'fresh');
INSERT INTO "shop$item_tag" VALUES (1, 20);
INSERT INTO "shop$averylongentitynamethatmakesthetablenamelongerthansixtythr" VALUES (30, 'long');
INSERT INTO "system$session" VALUES (1, 'live-session');
