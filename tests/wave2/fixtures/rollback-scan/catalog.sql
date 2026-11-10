BEGIN TRANSACTION;
CREATE TABLE activities_data (
			Id TEXT PRIMARY KEY,
			Name TEXT,
			Caption TEXT,
			ActivityType TEXT,
			Sequence INTEGER DEFAULT 0,
			MicroflowId TEXT,
			MicroflowQualifiedName TEXT,
			ModuleName TEXT,
			Folder TEXT,
			EntityRef TEXT,
			ActionType TEXT,
			ServiceRef TEXT,
			ActionRef TEXT,
			UseRequestTimeout INTEGER DEFAULT 0,
			TimeoutExpression TEXT,
			Description TEXT,
			ParentLoopId TEXT DEFAULT '',
			LoopDepth INTEGER DEFAULT 0,
			AutoGenerateCaption INTEGER DEFAULT 0,
			ConditionExpression TEXT DEFAULT '',
			ConditionRule TEXT DEFAULT '',
			ErrorHandlingType TEXT DEFAULT '',
			LogLevel TEXT DEFAULT '',
			LogNodeExpression TEXT DEFAULT '',
			LogMessage TEXT DEFAULT '',
			CommitType TEXT DEFAULT '',
			WithEvents INTEGER DEFAULT 0,
			RetrieveSource TEXT DEFAULT '',
			QueueRef TEXT DEFAULT '',
			ProjectId TEXT,
			SnapshotId TEXT
		);
INSERT INTO "activities_data" VALUES('d5d8c99d-120c-4b71-a43e-7cb6f01ceed0','StartEvent','','StartEvent',1,'3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','Procurement.SUB_User_SetFullName','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('35746111-0eac-4cea-a826-85d1faa308c2','ChangeObjectAction','','ActionActivity',2,'3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','Procurement.SUB_User_SetFullName','Procurement','Procurement','','ChangeObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('1be846b8-056b-434f-b52b-0bd255adc102','EndEvent','','EndEvent',3,'3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','Procurement.SUB_User_SetFullName','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('12668d56-e12b-4bc1-a68d-1c72b749eca9','StartEvent','','StartEvent',1,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('da6b1752-e93b-4fc0-8d0b-e6ed37956cb9','CreateVariableAction','','ActionActivity',2,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('13f5ba3d-9309-4c46-8d86-8884d889b843','MicroflowCallAction','','ActionActivity',3,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','MicroflowCallAction','','Procurement.SUB_User_SetFullName',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c4687f04-bb80-4cb7-9ae7-a572aa8c1500','RetrieveAction','','ActionActivity',4,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'association','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('742cb59f-e2d4-4a43-aab6-f6143ff783dc','ExclusiveSplit','length($Roles) = 0','ExclusiveSplit',5,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','','','',0,'','','',0,0,'length($Roles) = 0','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('480924aa-55a5-410e-85bf-5560054c0fd7','ExclusiveMerge','','ExclusiveMerge',6,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('5f388cef-41ac-463f-b7a4-bf81ac9b2d29','ChangeVariableAction','','ActionActivity',7,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('641000a8-9381-4656-a55f-23b7293fadea','ShowMessageAction','','ActionActivity',8,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','ShowMessageAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c009d8b4-7126-4275-8d77-61e5d1ec1ea7','EndEvent','','EndEvent',9,'cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8ac59b29-075e-4831-a933-90c7f15db463','StartEvent','','StartEvent',1,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c969449f-4fd3-41a0-8fcc-787a682d2b8f','CreateVariableAction','','ActionActivity',2,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8bfcc2d8-8407-4f1b-a4f6-c9bc79c693fa','CreateVariableAction','','ActionActivity',3,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('985bbc65-333b-403a-8f31-7122cc2891f9','ExclusiveSplit','trim($RegistrationForm/FirstName) = ''''','ExclusiveSplit',4,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'trim($RegistrationForm/FirstName) = ''''','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('ab902a5e-9725-4181-846d-778cf373c294','ExclusiveMerge','','ExclusiveMerge',5,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('86559c1a-c328-47ee-97a6-adbb60a062a0','ChangeVariableAction','','ActionActivity',6,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('0a59ea40-de3b-4965-9877-756fa4d65445','ValidationFeedbackAction','','ActionActivity',7,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('54420699-b816-45ce-8cc6-1971a3825c8d','ExclusiveSplit','length($RegistrationForm/FirstName) > 80','ExclusiveSplit',8,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'length($RegistrationForm/FirstName) > 80','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('bfac1682-a1a0-4d96-8026-97ad8205768c','ExclusiveMerge','','ExclusiveMerge',9,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c101500b-f75c-4bac-b564-b5f7c8f16b9d','ChangeVariableAction','','ActionActivity',10,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('2970d6dc-c226-49be-afe6-5ef877d13c11','ValidationFeedbackAction','','ActionActivity',11,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('5641f53d-99db-4188-a232-24aff7d82915','ExclusiveSplit','trim($RegistrationForm/LastName) = ''''','ExclusiveSplit',12,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'trim($RegistrationForm/LastName) = ''''','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('83f0b56f-3949-4053-9eec-9254505a4be6','ExclusiveMerge','','ExclusiveMerge',13,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('58632b23-8388-4461-94c0-64c0cac5bcdc','ChangeVariableAction','','ActionActivity',14,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c19a08ac-feca-4d80-896e-89f4ef9cd703','ValidationFeedbackAction','','ActionActivity',15,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('fbbee1d5-4e43-4c65-aa9d-6d970ae905e3','ExclusiveSplit','length($RegistrationForm/LastName) > 80','ExclusiveSplit',16,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'length($RegistrationForm/LastName) > 80','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('35c6eba7-5a2c-498e-bb7a-1dec5303ac5b','ExclusiveMerge','','ExclusiveMerge',17,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e557c3f1-ce3c-45eb-9cf4-64f39cacdbec','ChangeVariableAction','','ActionActivity',18,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('866c12ca-4010-4d64-9e41-9bf988cdf2d6','ValidationFeedbackAction','','ActionActivity',19,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('0d24e1e1-afa0-48e5-b601-924f6dac0977','ExclusiveSplit','trim($RegistrationForm/Email) = ''''','ExclusiveSplit',20,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'trim($RegistrationForm/Email) = ''''','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('908e5ede-2a27-49ef-98b6-700b61811e43','ExclusiveMerge','','ExclusiveMerge',21,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('bc1d62bc-5a0b-47e1-a4f0-4cfbab73d276','ChangeVariableAction','','ActionActivity',22,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('94b68672-2992-4936-89cd-6a9be3846dec','ValidationFeedbackAction','','ActionActivity',23,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('ab734e2d-0a54-4506-8608-45fe2748610d','ExclusiveSplit','length($RegistrationForm/Email) > 190','ExclusiveSplit',24,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'length($RegistrationForm/Email) > 190','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('2cd423ea-69fb-402b-b1e0-38f7e402cea1','ExclusiveMerge','','ExclusiveMerge',25,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('0570ae30-9230-4fc3-b24b-6e1133efcc23','ChangeVariableAction','','ActionActivity',26,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('12474c3f-fcca-4ce2-a212-9580ece14560','ValidationFeedbackAction','','ActionActivity',27,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('802ede39-4e58-46e9-941a-0c2d7bcd5048','ExclusiveSplit','not(contains($RegistrationForm/Email, ''@''))','ExclusiveSplit',28,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'not(contains($RegistrationForm/Email, ''@''))','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c6d9e83b-4489-4eb4-be6d-ad4e883f6e2b','ExclusiveMerge','','ExclusiveMerge',29,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('7d7a70fd-592f-4b4b-920e-218e78909772','ChangeVariableAction','','ActionActivity',30,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('eb210a85-3061-4b93-89d9-ef6a19216de3','ValidationFeedbackAction','','ActionActivity',31,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('96c9d7c1-c492-4256-86a0-d6e9f9ab98e4','ChangeVariableAction','','ActionActivity',32,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('4e3f969f-6a8b-422b-8806-28fa728b67cd','ExclusiveSplit','trim($RegistrationForm/Password) = ''''','ExclusiveSplit',33,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'trim($RegistrationForm/Password) = ''''','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('dbbe8776-6367-46c9-b39a-2d6cf6d6b76a','ExclusiveMerge','','ExclusiveMerge',34,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('5f00c57f-5b45-4e07-a271-a69faeeea513','ChangeVariableAction','','ActionActivity',35,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('408c63d0-ef9e-43b0-9633-52895600ca12','ValidationFeedbackAction','','ActionActivity',36,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('74fa664f-6882-46a2-a7bd-f32c185a78b9','ExclusiveSplit','length($RegistrationForm/Password) < 8 or length($RegistrationForm/Password) > 100','ExclusiveSplit',37,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'length($RegistrationForm/Password) < 8 or length($RegistrationForm/Password) > 100','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('09efb2f2-c8e6-44ae-9a75-fa7c6068e081','ExclusiveMerge','','ExclusiveMerge',38,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('979dc75e-fc79-45dc-8d59-5dd10b52bdcb','ChangeVariableAction','','ActionActivity',39,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('eecacbaa-c497-469c-a4c7-4b873a129a7b','ValidationFeedbackAction','','ActionActivity',40,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e80ab6b4-7410-4c86-ae35-d66c7399799b','CreateVariableAction','','ActionActivity',41,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a8ddae92-238f-4af4-9283-6ceefbd8a4fe','ExclusiveSplit','$EmailOk','ExclusiveSplit',42,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'$EmailOk','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8ef13b7d-e5b8-4cd3-b2e7-3cde25e80737','ExclusiveMerge','','ExclusiveMerge',43,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b0e712ce-59ac-485f-bf7e-6705c5882068','RetrieveAction','','ActionActivity',44,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','Procurement.User','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'database','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c445d6dc-eb57-4e15-8bbf-402addadfdd2','ExclusiveSplit','$Existing != empty','ExclusiveSplit',45,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'$Existing != empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('90f70139-7b8a-4d56-a97f-de8e40125fc2','ExclusiveMerge','','ExclusiveMerge',46,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c7a07160-72c3-4e34-ba14-0d8b75e709c7','ChangeVariableAction','','ActionActivity',47,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('08d38340-7c93-41f6-823d-0a5ec595b06b','ChangeVariableAction','','ActionActivity',48,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('70c68a7f-23c7-4f3c-992b-818ccb32a4d5','ValidationFeedbackAction','','ActionActivity',49,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ValidationFeedbackAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('f3dd9718-cd9e-40e2-9f6a-20705408fce4','ExclusiveSplit','not($IsValid)','ExclusiveSplit',50,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'not($IsValid)','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('6f234ada-876d-4508-8f58-3a365e56ce18','EndEvent','','EndEvent',51,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8f5b4e1c-6802-429f-8388-184ced04113b','RetrieveAction','','ActionActivity',52,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','System.UserRole','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'database','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('001adde0-9c78-4c39-b937-3c3052566ab7','CreateObjectAction','','ActionActivity',53,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','Procurement.User','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('65d32e86-e0f3-4f0a-9096-d4409f991c8f','ExclusiveSplit','$RegistrationForm/Procurement.User_Registration_Department != empty','ExclusiveSplit',54,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'$RegistrationForm/Procurement.User_Registration_Department != empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('4446ab54-a91a-4608-a1be-37a7ea33b8d6','ExclusiveMerge','','ExclusiveMerge',55,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('3ff9b7d4-6801-4adc-b624-84f0a358374e','ChangeObjectAction','','ActionActivity',56,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a3d497f9-cd17-4d8e-a443-bca6cd98bbbb','ChangeObjectAction','','ActionActivity',57,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ChangeObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('229c27f4-94d7-4407-9b71-036a2a21683a','MicroflowCallAction','','ActionActivity',58,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','MicroflowCallAction','','Procurement.SUB_User_SetFullName',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('39a0f5db-cd7e-412c-aeb7-248a3f385c43','CommitObjectsAction','','ActionActivity',59,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('6b9fc274-f5b4-466d-a100-49425c8d71b5','JavaActionCallAction','','ActionActivity',60,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','JavaActionCallAction','','CommunityCommons.getGUID',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('90025d3a-e16f-43be-90b5-0772ab45f23f','MicroflowCallAction','','ActionActivity',61,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','MicroflowCallAction','','Audit.SUB_AuditLogEntry_Record',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('d8bc91b1-ddf0-4085-a2c9-1abc88d7fac0','ShowMessageAction','','ActionActivity',62,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ShowMessageAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b80b5632-3ab7-4236-8806-b29adf23b69c','ClosePageAction','','ActionActivity',63,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','ClosePageAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('ad1c5719-961a-47d1-8e2b-b7fb378ae3db','EndEvent','','EndEvent',64,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e09258e6-c06e-40a1-89c2-5d0c48f8b474','Annotation','N-S3-wfB1-1 / N-identity-2: source ends on login.html?registered=1&username=<email> with the e-mail pre-filled. MDL has no OPEN URL / EXTERNAL LINK activity (mxcli syntax microflow show-page: only SHOW PAGE to an internal page and CLOSE PAGE exist) -- closest supported option is this confirmation message + CLOSE PAGE. Studio Pro follow-up if the query-string prefill/alert on login.html must fire: wire an explicit navigation to login.html?registered=1&username={email}.','Annotation',65,'68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','Procurement','Procurement','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('db61d955-71a7-47a1-b473-78fcec70f5b8','StartEvent','','StartEvent',1,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('897f2a5c-d208-4562-a0a1-915a600b5872','CreateVariableAction','','ActionActivity',2,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('7276c44b-c069-4869-8c92-29c18733b179','ExclusiveSplit','$currentUser != empty','ExclusiveSplit',3,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','','','',0,'','','',0,0,'$currentUser != empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('3acb0055-f628-4429-84b0-cbfbaa3f8475','ExclusiveMerge','','ExclusiveMerge',4,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('af77bd2c-ec4a-49da-8e7f-384cebe57b74','ChangeVariableAction','','ActionActivity',5,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b76d8e2a-cf67-4150-a3e3-40eac9591035','CreateObjectAction','','ActionActivity',6,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','Audit.AuditLogEntry','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8b6410da-b6c1-463e-9cef-c6689adb0488','CommitObjectsAction','','ActionActivity',7,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('080c3752-e8d7-4229-afc5-63b97108f81c','EndEvent','','EndEvent',8,'36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','Audit','Audit','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('7fc09a93-72e2-499f-9281-f234549e6029','StartEvent','','StartEvent',1,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a6d8e8b8-9c0f-40ce-9455-c13a2bf3b73a','RetrieveAction','','ActionActivity',2,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','Procurement.Vendor','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'database','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('3ea8c7f0-35cc-49d1-86d4-6789c41ba08e','ListOperationAction','','ActionActivity',3,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ListOperationAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8c90880a-1600-4551-aaeb-d9740a405a42','RetrieveAction','','ActionActivity',4,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','Procurement.Vendor','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'database','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('f0700e8e-fd2b-4cc5-918d-6e32177f9d30','ListOperationAction','','ActionActivity',5,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ListOperationAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('568ca092-2890-44c6-bc9b-7cc835830e18','ListOperationAction','','ActionActivity',6,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ListOperationAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b5d101f3-f4b6-474b-8017-fbaff0e8eaed','ExclusiveSplit','$Vendor = empty','ExclusiveSplit',7,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'$Vendor = empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8f41a44c-4868-4d3a-a0bf-153c55aac611','LogMessageAction','','ActionActivity',8,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','LogMessageAction','','',0,'','','',0,1,'','','Rollback','Warning','''InvoiceProcessing''','{1}','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8472f7b8-34ac-46fb-9b26-c87220ca87c7','EndEvent','','EndEvent',9,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('f4de8f86-46bc-4ab2-8957-25fd83663cf0','RetrieveAction','','ActionActivity',10,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','Procurement.PurchaseOrder','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'database','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('da262c20-c069-430b-a204-3adae3507dac','CreateVariableAction','','ActionActivity',11,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('36be0867-4d41-4edc-b42c-181bfa9470d0','ChangeVariableAction','','ActionActivity',12,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8d56c832-e42b-4015-b2ca-6d27ba33f011','CreateVariableAction','','ActionActivity',13,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('98170e33-e06f-4fdd-9704-690ab31d95a5','ExclusiveSplit','$Request/DueDate != empty','ExclusiveSplit',14,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'$Request/DueDate != empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('eabeb102-3fc7-4255-af2f-29a82689fd22','ExclusiveMerge','','ExclusiveMerge',15,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('ff3010fa-b7a4-4960-a099-a218d1f16f9a','ChangeVariableAction','','ActionActivity',16,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ChangeVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('ca9361d8-e158-47d4-8813-54e0ac2b2a72','CreateObjectAction','','ActionActivity',17,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','Procurement.Invoice','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('f45f3f1a-aec5-4341-9d02-34aad66865b5','ExclusiveSplit','$MatchedPo != empty','ExclusiveSplit',18,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'$MatchedPo != empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e83457c6-b930-4831-bf17-49d549859d20','ExclusiveMerge','','ExclusiveMerge',19,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('207ec578-e0b1-4848-84cf-b8514b4c355a','ChangeObjectAction','','ActionActivity',20,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ChangeObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('1df98a06-e7cc-40ce-8123-50d8984dc44e','CommitObjectsAction','','ActionActivity',21,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a9103a58-1676-4078-8390-9e8fea9e490e','RetrieveAction','','ActionActivity',22,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','RetrieveAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'association','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('801cebe0-a6ad-4b06-8035-4a063a98a343','CreateVariableAction','','ActionActivity',23,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e206de0c-b66f-4654-ae36-9a415c31596f','CreateListAction','','ActionActivity',24,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CreateListAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('340e8b9a-57ef-4dbf-bac9-2a2c8a2f0f71','LoopedActivity','','LoopedActivity',25,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('9b929214-a912-4ad5-850d-e43d8cc05d3f','ChangeVariableAction','','ActionActivity',26,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ChangeVariableAction','','',0,'','','340e8b9a-57ef-4dbf-bac9-2a2c8a2f0f71',1,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('79141184-9d1f-4cc2-bfbf-a639fde95748','CreateObjectAction','','ActionActivity',27,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','InvoiceMatching.InvoiceLine','CreateObjectAction','','',0,'','','340e8b9a-57ef-4dbf-bac9-2a2c8a2f0f71',1,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a6baea6b-83fd-4ea5-823d-b84ea8c190f1','ChangeListAction','','ActionActivity',28,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','ChangeListAction','','',0,'','','340e8b9a-57ef-4dbf-bac9-2a2c8a2f0f71',1,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('4dce8706-bdc3-4b67-9839-56ede33e5d10','CommitObjectsAction','','ActionActivity',29,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('5111acb0-b109-4d4b-9137-c6a9f04b235e','CreateObjectAction','','ActionActivity',30,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','InvoiceMatching.InvoiceDocument','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('389a75bb-e2a9-4c71-b166-b7aece6e5537','ExclusiveSplit','$Request/PdfBase64 != empty','ExclusiveSplit',31,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'$Request/PdfBase64 != empty','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b94b4826-43aa-4fac-9daa-f998baec7836','ExclusiveMerge','','ExclusiveMerge',32,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('97ced76e-526f-4ed1-bfce-8fee24bf8b67','JavaActionCallAction','','ActionActivity',33,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','JavaActionCallAction','','CommunityCommons.Base64DecodeToFile',0,'','','',0,1,'','','Continue','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('d8f05044-5f5e-439e-87ca-eb200bf889ab','CommitObjectsAction','','ActionActivity',34,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('ff75102a-4bcd-4eff-a9a9-40ddfd0e171d','JavaActionCallAction','','ActionActivity',35,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','JavaActionCallAction','','CommunityCommons.getGUID',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('3a8d150d-8def-490a-a24f-6533f9ed1065','MicroflowCallAction','','ActionActivity',36,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','MicroflowCallAction','','Audit.SUB_AuditLogEntry_Record',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b18686b5-608a-413b-be49-e059519c3ee8','EndEvent','','EndEvent',37,'4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','InvoiceProcessing','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('744b5507-d2c6-43fe-a49b-fca4714a6763','StartEvent','','StartEvent',1,'97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('6d0be296-52a8-451e-9e49-2ef6ba6bdf88','CreateVariableAction','','ActionActivity',2,'97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('75001827-6ee6-4b80-86f6-534a5039cb63','CreateObjectAction','','ActionActivity',3,'97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','MtaProbe','MtaProbe','MtaProbe.ProbeRow','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('0d677e36-be47-4fb7-8bb3-c1a13b947d59','CommitObjectsAction','','ActionActivity',4,'97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','MtaProbe','MtaProbe','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e094e943-d272-4165-b591-5e7fa40b13fd','EndEvent','','EndEvent',5,'97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('37bcd38e-6e05-4c82-b4fc-9ec5bc363e88','StartEvent','','StartEvent',1,'626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('24d3d7d9-22b9-49c2-8c3b-2fabd7d9341c','CreateVariableAction','','ActionActivity',2,'626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('672642a7-9814-47a0-8e9f-4aaf44a5b16c','CreateObjectAction','','ActionActivity',3,'626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','MtaProbe','MtaProbe','MtaProbe.ProbeRow','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('c0a96f77-0848-4965-b99b-bb3a15896401','CommitObjectsAction','','ActionActivity',4,'626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','MtaProbe','MtaProbe','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('7a4ec9a3-33e4-4c36-b6d7-1045438a4696','EndEvent','','EndEvent',5,'626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('3337ba3f-6469-40fd-a8d0-e521dbe0f2c2','StartEvent','','StartEvent',1,'e9a35976-eb00-45bf-b422-d940a065c2f0','MtaProbe.PRB_Rest','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('077da267-5339-494b-9529-cb212dd2d77f','CreateVariableAction','','ActionActivity',2,'e9a35976-eb00-45bf-b422-d940a065c2f0','MtaProbe.PRB_Rest','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('e7f487d5-15ed-4fb5-b6c7-bffe50d79f3c','RestCallAction','','ActionActivity',3,'e9a35976-eb00-45bf-b422-d940a065c2f0','MtaProbe.PRB_Rest','MtaProbe','MtaProbe','','RestCallAction','','',1,'10','','',0,1,'','','Custom','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('20b7288a-b28a-4dd3-a869-434887dffa25','EndEvent','','EndEvent',4,'e9a35976-eb00-45bf-b422-d940a065c2f0','MtaProbe.PRB_Rest','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('60ec0cdb-ec09-4eee-a543-58e7f6ca8de7','EndEvent','','EndEvent',5,'e9a35976-eb00-45bf-b422-d940a065c2f0','MtaProbe.PRB_Rest','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('4e4fe73a-d5fd-4ee3-9be4-efde41a98fac','StartEvent','','StartEvent',1,'dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('eb6efd98-55d6-40c1-9791-10c9ec06bbef','CreateVariableAction','','ActionActivity',2,'dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('b44cf0e0-98b7-43de-86fc-8e32d4a932a1','CreateObjectAction','','ActionActivity',3,'dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','MtaProbe','MtaProbe','MtaProbe.ProbeDoc','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('28cfdc0a-b1cf-4b2c-a1e4-998cee1c6cd7','JavaActionCallAction','','ActionActivity',4,'dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','MtaProbe','MtaProbe','','JavaActionCallAction','','CommunityCommons.Base64DecodeToFile',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('6e4447e8-e6c1-4591-924b-cc04ab8a4796','EndEvent','','EndEvent',5,'dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('897608bf-71f6-4f31-8ef5-1698900075b3','StartEvent','','StartEvent',1,'2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('cbeadb86-eecb-4ffe-8454-d7ac6572493d','CreateVariableAction','','ActionActivity',2,'2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('f92bc6dc-aec4-41db-a7b4-ea4faf479fd5','CreateObjectAction','','ActionActivity',3,'2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','MtaProbe','MtaProbe','MtaProbe.ProbeRow','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('7ecf48e5-ade1-497b-81f6-a714cd7c79eb','JavaActionCallAction','','ActionActivity',4,'2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','MtaProbe','MtaProbe','','JavaActionCallAction','','CommunityCommons.commitInSeparateDatabaseTransaction',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a41a1a78-533f-422a-a586-138b83ec4592','EndEvent','','EndEvent',5,'2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('f829b666-649c-4627-a94a-794294a69e55','StartEvent','','StartEvent',1,'2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('083f8e0d-503b-468c-b24b-8c962c909c56','CreateVariableAction','','ActionActivity',2,'2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('8cd66e09-1489-4376-a5dd-6793bfa46e4c','CreateObjectAction','','ActionActivity',3,'2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','MtaProbe','MtaProbe','MtaProbe.ProbeRow','CreateObjectAction','','',0,'','','',0,1,'','','Rollback','','','','No',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('44627e54-2261-4a1e-83bb-e0503830933c','CommitObjectsAction','','ActionActivity',4,'2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','MtaProbe','MtaProbe','','CommitObjectsAction','','',0,'','','',0,1,'','','Rollback','','','','',1,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('6f62d14e-46df-485f-8600-3bb2c0ab1148','EndEvent','','EndEvent',5,'2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('5c0074f1-8674-4d84-aff9-b6f48870f744','StartEvent','','StartEvent',1,'6c92a423-c18f-4c37-a521-f2ebd94e5408','MtaProbe.PRB_Queue','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('54212611-5873-4180-9421-22d57ef57ec4','CreateVariableAction','','ActionActivity',2,'6c92a423-c18f-4c37-a521-f2ebd94e5408','MtaProbe.PRB_Queue','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('3aafa51f-7118-4c41-a295-009f4ae0477c','JavaActionCallAction','','ActionActivity',3,'6c92a423-c18f-4c37-a521-f2ebd94e5408','MtaProbe.PRB_Queue','MtaProbe','MtaProbe','','JavaActionCallAction','','CommunityCommons.RunMicroflowAsyncInQueue',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('821e688d-bf66-4ace-8322-315128801344','EndEvent','','EndEvent',4,'6c92a423-c18f-4c37-a521-f2ebd94e5408','MtaProbe.PRB_Queue','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('2d56afc9-4463-4954-ac01-2c4c236f46fb','StartEvent','','StartEvent',1,'6448f74e-6f97-4715-b12f-74e76a771654','MtaProbe.PRB_Log','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('58f8ec18-fc09-4386-96a2-3c5373a532ea','CreateVariableAction','','ActionActivity',2,'6448f74e-6f97-4715-b12f-74e76a771654','MtaProbe.PRB_Log','MtaProbe','MtaProbe','','CreateVariableAction','','',0,'','','',0,1,'','','Rollback','','','','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('a82d8d64-51f8-48c7-a84e-8d9cbeeadd2f','LogMessageAction','','ActionActivity',3,'6448f74e-6f97-4715-b12f-74e76a771654','MtaProbe.PRB_Log','MtaProbe','MtaProbe','','LogMessageAction','','',0,'','','',0,1,'','','Rollback','Info','''MtaProbe''','MTA_PROBE_LOG run=mta','',0,'','','default','snapshot-1');
INSERT INTO "activities_data" VALUES('529c0739-3b64-41d6-9d68-ce30d4a731b7','EndEvent','','EndEvent',4,'6448f74e-6f97-4715-b12f-74e76a771654','MtaProbe.PRB_Log','MtaProbe','MtaProbe','','','','',0,'','','',0,0,'','','','','','','',0,'','','default','snapshot-1');
CREATE TABLE attributes_data (
			Id TEXT PRIMARY KEY,
			Name TEXT,
			EntityId TEXT,
			EntityQualifiedName TEXT,
			ModuleName TEXT,
			DataType TEXT,
			-- DataType is the bare kind ("Enumeration"), so the enum's identity
			-- needs its own column. Kept separate rather than folded into
			-- DataType as "Enumeration:QN" because existing queries and lint
			-- rules match DataType by equality.
			EnumerationQualifiedName TEXT,
			Length INTEGER,
			IsUnique INTEGER DEFAULT 0,
			IsRequired INTEGER DEFAULT 0,
			DefaultValue TEXT,
			IsCalculated INTEGER DEFAULT 0,
			Description TEXT,
			ProjectId TEXT,
			SnapshotId TEXT
		);
INSERT INTO "attributes_data" VALUES('d4f89e6b-e0ed-4c21-90ed-ff897dac3ff8','Seq','b6c28e9f-2357-4983-b453-7a96c2f8647e','MtaProbe.ProbeRow','MtaProbe','AutoNumber','',0,0,0,'1',0,'','default','snapshot-1');
INSERT INTO "attributes_data" VALUES('0ed4bc35-654b-4a01-866c-6af52f7d5555','IntakeId','0e185d50-8c7f-4c88-ba8d-21e9ef65f337','Procurement.Invoice','Procurement','AutoNumber','',0,0,0,'1',0,'','default','snapshot-1');
INSERT INTO "attributes_data" VALUES('db528d2c-a378-4640-9e93-465862d0de26','PoSequence','b19dd7db-088c-4b80-a031-c468aa945f7a','Procurement.PurchaseOrder','Procurement','AutoNumber','',0,0,0,'1',0,'','default','snapshot-1');
INSERT INTO "attributes_data" VALUES('System.FileDocument.FileID','FileID','System.FileDocument','System.FileDocument','System','AutoNumber','',0,0,0,'',0,'','default','snapshot-1');
CREATE TABLE microflows_data (
			Id TEXT PRIMARY KEY,
			Name TEXT,
			QualifiedName TEXT,
			ModuleName TEXT,
			Folder TEXT,
			MicroflowType TEXT,
			Description TEXT,
			ReturnType TEXT,
			ParameterCount INTEGER DEFAULT 0,
			ActivityCount INTEGER DEFAULT 0,
			TotalActivityCount INTEGER DEFAULT 0,
			Complexity INTEGER DEFAULT 1,
			Excluded BOOLEAN DEFAULT 0,
			-- The flow's "Apply entity access" setting; always 0 for a nanoflow,
			-- which has no such setting (ako/mxcli#1453).
			ApplyEntityAccess BOOLEAN DEFAULT 0,
			ProjectId TEXT,
			SnapshotId TEXT
		);
INSERT INTO "microflows_data" VALUES('3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','SUB_User_SetFullName','Procurement.SUB_User_SetFullName','Procurement','Identity/Microflows','MICROFLOW','SUB_User_SetFullName -- sets FullName = FirstName + '' '' + LastName (identity BRD).
@param User The user whose FullName is (re)computed.','Void',1,1,1,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('cb8b21b9-af1c-430b-ae14-69f373caea4a','BCo_User_Validate','Procurement.BCo_User_Validate','Procurement','Identity/Microflows','MICROFLOW','BCo_User_Validate -- before-commit guard on Procurement.User (identity BRD): keeps
FullName in step and refuses a commit where the user holds no role. Wired as an
ON BEFORE COMMIT event handler below, after this microflow exists.
@param User The user object about to be committed.
@returns false to abort the commit (RAISE ERROR), true to allow it.','Boolean',1,6,6,2,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('68395c40-9082-4d1d-8631-79724e32d6ac','ACT_User_Register','Procurement.ACT_User_Register','Procurement','Identity/Microflows','MICROFLOW','ACT_User_Register -- creates a new Employee account from the anonymous
registration form (identity BRD FR-1). Validates, lower-cases the e-mail and
login, refuses a duplicate e-mail (case-insensitive), assigns the Employee
role, and ends on the login page (N-identity-2 / N-S3-wfB1-1 -- see the build
report: MDL has no client action to open an external URL, so this uses the
closest supported option).
@param RegistrationForm The submitted registration form.
@returns The new User, or empty when validation failed.','Object:Procurement.User',1,50,50,14,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('36a22af7-973a-43df-94a3-94a3355d087b','SUB_AuditLogEntry_Record','Audit.SUB_AuditLogEntry_Record','Audit','AuditLog/Microflows','MICROFLOW','Records one audit entry for a workflow action, committed inside the caller''s transaction
(FR-19) -- called from inside another microflow''s own transaction, never separately. The
only write path onto AuditLogEntry (KB-11, append-only).
@param EntityType Audited entity''s name (e.g. ''PurchaseRequisition'', ''PurchaseOrder'', ''Invoice'').
@param EntityId Identifier of the audited object (N-audit-1).
@param Action The lifecycle action recorded (e.g. ''SUBMITTED'', ''STATUS_APPROVED'').
@param Details Free-text context; may be empty (empty for STATUS_* and CANCELLED entries).','Void',4,5,5,2,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('4eddc622-9a41-4879-a417-541239819677','SUB_Invoice_CreateFromIntake','InvoiceProcessing.SUB_Invoice_CreateFromIntake','InvoiceProcessing','Intake/Microflows','MICROFLOW','Creates an Invoice (+ InvoiceLines, + InvoiceDocument from pdfBase64 when present) from an intake
request (F101, upload and API channels). Does NOT start the workflow (N-S3-wf-2): callers call
SUB_Invoice_StartProcessing next. Vendor resolved by exact case-insensitive name, else the vendor of
the PO matching poNumber. Returns empty when the supplier cannot be resolved.
@param Request The intake payload (+ its lines).
@returns The created, committed Invoice (RECEIVED), or empty when the supplier could not be resolved.','Object:Procurement.Invoice',1,28,31,6,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('97eb661b-daeb-4547-8961-9f31d0eaa9ab','PRB_Control','MtaProbe.PRB_Control','MtaProbe','','MICROFLOW','','Boolean',0,3,3,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('626c46ba-2a4b-4159-9e58-ae10be3978c1','PRB_Autonumber','MtaProbe.PRB_Autonumber','MtaProbe','','MICROFLOW','','Boolean',0,3,3,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('e9a35976-eb00-45bf-b422-d940a065c2f0','PRB_Rest','MtaProbe.PRB_Rest','MtaProbe','','MICROFLOW','','Boolean',0,2,2,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('dfd02283-4af0-4bbe-adef-ba1398635de3','PRB_File','MtaProbe.PRB_File','MtaProbe','','MICROFLOW','','Boolean',0,3,3,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('2ef53570-7b12-4c7b-a3a3-cecafffcde77','PRB_SeparateCommit','MtaProbe.PRB_SeparateCommit','MtaProbe','','MICROFLOW','','Boolean',0,3,3,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('2860c830-c6a2-486a-8cce-9d13782d89e3','PRB_QueueTarget','MtaProbe.PRB_QueueTarget','MtaProbe','','MICROFLOW','','Boolean',0,3,3,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('6c92a423-c18f-4c37-a521-f2ebd94e5408','PRB_Queue','MtaProbe.PRB_Queue','MtaProbe','','MICROFLOW','','Boolean',0,2,2,1,0,0,'default','snapshot-1');
INSERT INTO "microflows_data" VALUES('6448f74e-6f97-4715-b12f-74e76a771654','PRB_Log','MtaProbe.PRB_Log','MtaProbe','','MICROFLOW','','Boolean',0,2,2,1,0,0,'default','snapshot-1');
CREATE TABLE refs (
			Id INTEGER PRIMARY KEY AUTOINCREMENT,
			SourceType TEXT NOT NULL,
			SourceId TEXT NOT NULL,
			SourceName TEXT NOT NULL,
			TargetType TEXT NOT NULL,
			TargetId TEXT,
			TargetName TEXT NOT NULL,
			RefKind TEXT NOT NULL,
			ModuleName TEXT,
			ProjectId TEXT,
			SnapshotId TEXT
		);
INSERT INTO "refs" VALUES(66,'MICROFLOW','3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','Procurement.SUB_User_SetFullName','ENTITY','','Procurement.User','parameter','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(67,'MICROFLOW','3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','Procurement.SUB_User_SetFullName','ENTITY','','Procurement.User','change','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(68,'MICROFLOW','cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','ENTITY','','Procurement.User','parameter','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(69,'MICROFLOW','cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','MICROFLOW','','Procurement.SUB_User_SetFullName','call','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(70,'MICROFLOW','cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','ASSOCIATION','','System.UserRoles','retrieve','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(80,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User_Registration','parameter','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(81,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User','return','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(82,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User','retrieve','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(83,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','System.UserRole','retrieve','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(84,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User','create','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(85,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User','change','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(86,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User','change','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(87,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','MICROFLOW','','Procurement.SUB_User_SetFullName','call','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(88,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ENTITY','','Procurement.User','commit','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(89,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','JAVA_ACTION','','CommunityCommons.getGUID','call','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(90,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','MICROFLOW','','Audit.SUB_AuditLogEntry_Record','call','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(389,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ENTITY','','Audit.AuditLogEntry','create','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(390,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ENTITY','','Audit.AuditLogEntry','commit','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(2729,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','InvoiceProcessing.InvoiceIntakeRequest','parameter','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2730,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.Invoice','return','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2731,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.Vendor','retrieve','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2732,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.Vendor','retrieve','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2733,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.PurchaseOrder','retrieve','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2734,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.Invoice','create','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2735,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.Invoice','change','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2736,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','Procurement.Invoice','commit','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2737,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','InvoiceProcessing.InvoiceIntakeLine_InvoiceIntakeRequest','retrieve','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2738,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','InvoiceMatching.InvoiceLine','create','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2739,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','InvoiceMatching.InvoiceDocument','create','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2740,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','JAVA_ACTION','','CommunityCommons.Base64DecodeToFile','call','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2741,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENTITY','','InvoiceMatching.InvoiceDocument','commit','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2742,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','JAVA_ACTION','','CommunityCommons.getGUID','call','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(2743,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','MICROFLOW','','Audit.SUB_AuditLogEntry_Record','call','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(5258,'MICROFLOW','97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','ENTITY','','MtaProbe.ProbeRow','create','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5259,'MICROFLOW','97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','ENTITY','','MtaProbe.ProbeRow','commit','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5260,'MICROFLOW','626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','ENTITY','','MtaProbe.ProbeRow','create','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5261,'MICROFLOW','626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','ENTITY','','MtaProbe.ProbeRow','commit','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5262,'MICROFLOW','dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','ENTITY','','MtaProbe.ProbeDoc','create','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5263,'MICROFLOW','dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','JAVA_ACTION','','CommunityCommons.Base64DecodeToFile','call','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5264,'MICROFLOW','2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','ENTITY','','MtaProbe.ProbeRow','create','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5265,'MICROFLOW','2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','JAVA_ACTION','','CommunityCommons.commitInSeparateDatabaseTransaction','call','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5266,'MICROFLOW','2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','ENTITY','','MtaProbe.ProbeRow','create','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5267,'MICROFLOW','2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','ENTITY','','MtaProbe.ProbeRow','commit','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5268,'MICROFLOW','6c92a423-c18f-4c37-a521-f2ebd94e5408','MtaProbe.PRB_Queue','JAVA_ACTION','','CommunityCommons.RunMicroflowAsyncInQueue','call','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(5615,'ENTITY','084e3bf6-059a-4545-bdb2-5978d9d9a496','Procurement.User','ENTITY','','Administration.Account','generalize','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(5859,'ENTITY','2554a302-3b47-4d97-b3b0-85ced5c39cd1','InvoiceMatching.InvoiceDocument','ENTITY','','System.FileDocument','generalize','InvoiceMatching','default','snapshot-1');
INSERT INTO "refs" VALUES(6080,'ENTITY','9d50f7b3-0433-42a6-a315-db48126e8636','MtaProbe.ProbeDoc','ENTITY','','System.FileDocument','generalize','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(7958,'ENTITY','','Procurement.User','MICROFLOW','','Procurement.BCo_User_Validate','event','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10205,'MICROFLOW','3d4dabf6-a0ba-4259-a1ed-2b0510866d0e','Procurement.SUB_User_SetFullName','ATTRIBUTE','','Administration.Account.FullName','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10206,'MICROFLOW','cb8b21b9-af1c-430b-ae14-69f373caea4a','Procurement.BCo_User_Validate','ASSOCIATION','','System.UserRoles','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10220,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ASSOCIATION','','Procurement.User_Department','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10221,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ASSOCIATION','','Procurement.User_Registration_Department','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10222,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ASSOCIATION','','System.UserRoles','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10223,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Administration.Account.Email','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10224,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Procurement.User.FirstName','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10225,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Procurement.User.LastName','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10226,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Procurement.User_Registration.Email','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10227,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Procurement.User_Registration.FirstName','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10228,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Procurement.User_Registration.LastName','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10229,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Procurement.User_Registration.Password','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10230,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','System.User.Active','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10231,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','System.User.Name','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10232,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','System.User.Password','member','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(10401,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ATTRIBUTE','','Audit.AuditLogEntry.Action','member','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(10402,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ATTRIBUTE','','Audit.AuditLogEntry.Details','member','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(10403,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ATTRIBUTE','','Audit.AuditLogEntry.EntityId','member','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(10404,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ATTRIBUTE','','Audit.AuditLogEntry.EntityType','member','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(10405,'MICROFLOW','36a22af7-973a-43df-94a3-94a3355d087b','Audit.SUB_AuditLogEntry_Record','ATTRIBUTE','','Audit.AuditLogEntry.PerformedBy','member','Audit','default','snapshot-1');
INSERT INTO "refs" VALUES(11523,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','InvoiceMatching.InvoiceDocument_Invoice','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11524,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','InvoiceMatching.InvoiceLine_Invoice','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11525,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','InvoiceProcessing.InvoiceIntakeLine_InvoiceIntakeRequest','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11526,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','Procurement.Invoice_PurchaseOrder','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11527,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','Procurement.Invoice_Vendor','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11528,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','InvoiceMatching.InvoiceLine.Description','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11529,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','InvoiceMatching.InvoiceLine.LineAmount','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11530,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','InvoiceMatching.InvoiceLine.LineNumber','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11531,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','InvoiceMatching.InvoiceLine.Quantity','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11532,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','InvoiceMatching.InvoiceLine.UnitPrice','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11533,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.Amount','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11534,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.Currency','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11535,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.DueDate','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11536,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.Iban','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11537,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.InvoiceDate','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11538,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.InvoiceNumber','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11539,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.NetAmount','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11540,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.PoReference','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11541,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.ReceivedAt','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11542,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.Status','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11543,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.Invoice.VatAmount','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11544,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','System.FileDocument.Name','member','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(11545,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ENUMERATION_VALUE','','Procurement.InvoiceStatus.RECEIVED','value','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(12834,'MICROFLOW','97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','ATTRIBUTE','','MtaProbe.ProbeRow.Label','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12835,'MICROFLOW','97eb661b-daeb-4547-8961-9f31d0eaa9ab','MtaProbe.PRB_Control','ATTRIBUTE','','MtaProbe.ProbeRow.Run','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12836,'MICROFLOW','626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','ATTRIBUTE','','MtaProbe.ProbeRow.Label','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12837,'MICROFLOW','626c46ba-2a4b-4159-9e58-ae10be3978c1','MtaProbe.PRB_Autonumber','ATTRIBUTE','','MtaProbe.ProbeRow.Run','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12838,'MICROFLOW','dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','ATTRIBUTE','','MtaProbe.ProbeDoc.Run','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12839,'MICROFLOW','dfd02283-4af0-4bbe-adef-ba1398635de3','MtaProbe.PRB_File','ATTRIBUTE','','System.FileDocument.Name','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12840,'MICROFLOW','2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','ATTRIBUTE','','MtaProbe.ProbeRow.Label','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12841,'MICROFLOW','2ef53570-7b12-4c7b-a3a3-cecafffcde77','MtaProbe.PRB_SeparateCommit','ATTRIBUTE','','MtaProbe.ProbeRow.Run','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12842,'MICROFLOW','2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','ATTRIBUTE','','MtaProbe.ProbeRow.Label','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(12843,'MICROFLOW','2860c830-c6a2-486a-8cce-9d13782d89e3','MtaProbe.PRB_QueueTarget','ATTRIBUTE','','MtaProbe.ProbeRow.Run','member','MtaProbe','default','snapshot-1');
INSERT INTO "refs" VALUES(13110,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ASSOCIATION','','Procurement.PurchaseOrder_Vendor','xpath','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(13111,'MICROFLOW','4eddc622-9a41-4879-a417-541239819677','InvoiceProcessing.SUB_Invoice_CreateFromIntake','ATTRIBUTE','','Procurement.PurchaseOrder.PoNumber','xpath','InvoiceProcessing','default','snapshot-1');
INSERT INTO "refs" VALUES(13608,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','System.UserRole.Name','xpath','Procurement','default','snapshot-1');
INSERT INTO "refs" VALUES(13876,'MICROFLOW','68395c40-9082-4d1d-8631-79724e32d6ac','Procurement.ACT_User_Register','ATTRIBUTE','','Administration.Account.Email','xpath','Procurement','default','snapshot-1');
CREATE TABLE snapshots (
			SnapshotId TEXT PRIMARY KEY,
			SnapshotName TEXT,
			ProjectId TEXT,
			ProjectName TEXT,
			SnapshotDate TEXT,
			SnapshotSource TEXT,
			SourceId TEXT,
			SourceBranch TEXT,
			SourceRevision TEXT,
			ObjectCount INTEGER DEFAULT 0,
			IsActive INTEGER DEFAULT 0
		);
INSERT INTO "snapshots" VALUES('snapshot-1','','default','Current Project','2026-11-06 12:45:39','UNKNOWN','','','',0,1);
CREATE VIEW activities AS
		SELECT t.*,
			s.ProjectName,
			s.SnapshotDate,
			s.SnapshotSource,
			s.SourceId,
			s.SourceBranch,
			s.SourceRevision
		FROM activities_data t
		LEFT JOIN snapshots s ON s.SnapshotId = t.SnapshotId;
CREATE VIEW attributes AS
		SELECT t.*,
			s.ProjectName,
			s.SnapshotDate,
			s.SnapshotSource,
			s.SourceId,
			s.SourceBranch,
			s.SourceRevision
		FROM attributes_data t
		LEFT JOIN snapshots s ON s.SnapshotId = t.SnapshotId;
CREATE VIEW microflows AS
		SELECT t.*,
			s.ProjectName,
			s.SnapshotDate,
			s.SnapshotSource,
			s.SourceId,
			s.SourceBranch,
			s.SourceRevision
		FROM microflows_data t
		LEFT JOIN snapshots s ON s.SnapshotId = t.SnapshotId;
DELETE FROM "sqlite_sequence";
INSERT INTO "sqlite_sequence" VALUES('refs',13876);
COMMIT;
