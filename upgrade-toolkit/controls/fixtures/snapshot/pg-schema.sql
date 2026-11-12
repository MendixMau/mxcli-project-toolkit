-- What the app creates on an empty Postgres for the model behind fixtures/snapshot (written to match Mendix's
-- table naming; the entity GUIDs equal the snapshot's, the short ids differ, MxAdmin and its role exist already).
CREATE TABLE "mendixsystem$entityidentifier"(id varchar(36) primary key, short_id int, object_sequence bigint);
CREATE TABLE "mendixsystem$entity"(id varchar(36) primary key, entity_name varchar(200), table_name varchar(200), superentity_id varchar(36));
CREATE TABLE "mendixsystem$association"(id varchar(36) primary key, association_name varchar(200), table_name varchar(200), parent_entity_id varchar(36), child_entity_id varchar(36), parent_column_name varchar(200), child_column_name varchar(200));
CREATE TABLE "mendixsystem$attribute"(id varchar(36) primary key, entity_id varchar(36), attribute_name varchar(200), column_name varchar(200), type int, length int);
CREATE TABLE "system$user"(id bigint primary key, name varchar(200), password varchar(200), lastlogin timestamp, active boolean, "system$changedby" bigint);
CREATE TABLE "administration$account"(id bigint primary key, fullname varchar(200));
CREATE TABLE "system$userrole"(id bigint primary key, name varchar(200));
CREATE TABLE "system$userroles"("system$userid" bigint not null, "system$userroleid" bigint not null, primary key("system$userid","system$userroleid"));
CREATE TABLE "system$session"(id bigint primary key, sessionid varchar(36));
CREATE TABLE "demo$product"(id bigint primary key, name varchar(100), price decimal(28,8), stock int, createddate timestamp, "system$owner" bigint);
CREATE TABLE "demo$order"(id bigint primary key, orderno int, note varchar(200), "demo$order_customer" bigint);
CREATE TABLE "demo$order_product"("demo$orderid" bigint not null, "demo$productid" bigint not null, primary key("demo$orderid","demo$productid"));
ALTER TABLE "demo$order" ADD FOREIGN KEY ("demo$order_customer") REFERENCES "system$user"(id);
INSERT INTO "mendixsystem$entityidentifier" VALUES
 ('a1111111-0000-4000-8000-000000000001',11,1),('a1111111-0000-4000-8000-000000000002',12,1),
 ('b2222222-0000-4000-8000-000000000001',13,0),('b2222222-0000-4000-8000-000000000002',14,0),('a1111111-0000-4000-8000-000000000003',15,0);
INSERT INTO "mendixsystem$entity" VALUES
 ('a1111111-0000-4000-8000-000000000001','System.User','system$user',NULL),('a1111111-0000-4000-8000-000000000002','System.UserRole','system$userrole',NULL),
 ('b2222222-0000-4000-8000-000000000001','Demo.Product','demo$product',NULL),('b2222222-0000-4000-8000-000000000002','Demo.Order','demo$order',NULL),
 ('a1111111-0000-4000-8000-000000000003','Administration.Account','administration$account','a1111111-0000-4000-8000-000000000001');
INSERT INTO "system$user"(id,name,password,active) VALUES ((11::bigint<<48)|1,'MxAdmin','pg-admin-hash',true);
INSERT INTO "system$userrole" VALUES ((12::bigint<<48)|1,'Administrator');
INSERT INTO "system$userroles" VALUES ((11::bigint<<48)|1,(12::bigint<<48)|1);
INSERT INTO "system$session" VALUES (1,'live-session');
