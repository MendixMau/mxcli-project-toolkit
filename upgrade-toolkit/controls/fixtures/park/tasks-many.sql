-- PR-P1 fixture: the System workflow task tables with several waiting tasks per user.
-- User 1 (smoke_approver) is the sole target of four waiting tasks 21..24; user 2 (smoke_receiver) of one (25);
-- 26 is already assigned (to user 2) and 27 is completed: both are left alone.
CREATE TABLE "system$user" (id bigint PRIMARY KEY, name varchar(100));
CREATE TABLE "system$workflowusertask" (id bigint PRIMARY KEY, name varchar(200), state varchar(20));
CREATE TABLE "system$workflowusertask_targetusers" ("system$workflowusertaskid" bigint, "system$userid" bigint);
CREATE TABLE "system$workflowusertask_assignees" ("system$workflowusertaskid" bigint, "system$userid" bigint);
INSERT INTO "system$user" VALUES (1, 'smoke_approver'), (2, 'smoke_receiver');
INSERT INTO "system$workflowusertask" VALUES (21, 't21', 'InProgress'), (22, 't22', 'InProgress'), (23, 't23', 'InProgress'),
  (24, 't24', 'InProgress'), (25, 't25', 'InProgress'), (26, 't26', 'InProgress'), (27, 't27', 'Completed');
INSERT INTO "system$workflowusertask_targetusers" VALUES (21, 1), (22, 1), (23, 1), (24, 1), (25, 2), (26, 2), (27, 1);
INSERT INTO "system$workflowusertask_assignees" VALUES (26, 2);
