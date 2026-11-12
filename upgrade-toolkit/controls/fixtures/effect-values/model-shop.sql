-- effect values --model controls (quality item 5): a SYNTHETIC database in the shape the Mendix runtime writes, for
-- controls/fixtures/models/effect-values.json. Shop.Account.Secret is a HashString whose column is NOT named like a
-- password (the name heuristic cannot see it; the model can). Code is an AutoNumber (type 0), Qty an Integer (type 3).
CREATE TABLE "mendixsystem$entity"(id varchar(36) primary key, entity_name varchar(200), table_name varchar(200), superentity_id varchar(36), remote boolean);
CREATE TABLE "mendixsystem$attribute"(id varchar(36) primary key, entity_id varchar(36), attribute_name varchar(200), column_name varchar(200), type int, length int);
CREATE TABLE "mendixsystem$association"(id varchar(36) primary key, association_name varchar(200), table_name varchar(200), parent_entity_id varchar(36), child_entity_id varchar(36), parent_column_name varchar(200), child_column_name varchar(200));
CREATE TABLE "shop$account"(id bigint primary key, code bigint, qty bigint, secret varchar(60), label varchar(200));
INSERT INTO "mendixsystem$entity" VALUES ('e1', 'Shop.Account', 'shop$account', NULL, false);
INSERT INTO "mendixsystem$attribute" VALUES ('a1', 'e1', 'Code', 'code', 0, 0), ('a2', 'e1', 'Qty', 'qty', 3, 0),
 ('a3', 'e1', 'Secret', 'secret', 30, 60), ('a4', 'e1', 'Label', 'label', 30, 200);
INSERT INTO "shop$account" VALUES (1, 1001, 42, 'h$2b$12$sekret-AAA', 'alpha');
