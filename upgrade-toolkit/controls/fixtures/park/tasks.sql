-- PR-F33 fixture: the System workflow task tables (names as on Purchase Request, 10.24 and 11.12), four tasks.
-- t1 waits for one user (assigned by the fixture); t2 may go to two users (left alone); t3 already has an assignee
-- (left alone); t4 is completed (left alone).
CREATE TABLE "system$user" (id bigint PRIMARY KEY, name varchar(100));
CREATE TABLE "system$workflowusertask" (id bigint PRIMARY KEY, name varchar(200), state varchar(20));
CREATE TABLE "system$workflowusertask_targetusers" ("system$workflowusertaskid" bigint, "system$userid" bigint);
CREATE TABLE "system$workflowusertask_assignees" ("system$workflowusertaskid" bigint, "system$userid" bigint);
INSERT INTO "system$user" VALUES (1, 'smoke_approver'), (2, 'smoke_receiver'), (3, 'demo_receiver');
INSERT INTO "system$workflowusertask" VALUES (11, 't1', 'InProgress'), (12, 't2', 'InProgress'), (13, 't3', 'InProgress'),
  (14, 't4', 'Completed');
INSERT INTO "system$workflowusertask_targetusers" VALUES (11, 1), (12, 2), (12, 3), (13, 2), (14, 1);
INSERT INTO "system$workflowusertask_assignees" VALUES (13, 3);
