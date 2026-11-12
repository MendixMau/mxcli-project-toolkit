# Checklist to go 1.0.0 (Mendix 9.24.2): data map

Derived offline with `domain_map.py` and `page_data_needs.py` (regenerate: `python3 -I <script> <app dir>`). The package
ships no data snapshot, so route (a) is not available; route (b) `seed_pg.py`/`seed_usecase.py` is used, route (c) (UI) for
state SQL cannot build validly (signature images, report files). Roles: Administrator, DepartmentManager, Inspector.
Non-persistent entities (all `*HelperNP`, `*NP`) are never seeded.

| entity | who needs it | state it must be in | constraint found |
|---|---|---|---|
| EmployeeManagement.Employee | everyone | one per smoke user, `Employee_Account` set; `CanBeResponsible=true` for inspectors | the assignment drop-down is `Employee [CanBeResponsible]`; the Inspector's list is `InstanceChecklist_Employee_Responsible/Employee/Employee_Account = [%CurrentUser%]` |
| Masterdata.Department (DisplayName, TabIndex) + Department_Employee | Inspector dashboard tabs, Manager | 3 departments, inspectors in 2 each | an inspector sees only departments he belongs to |
| Masterdata.ChecklistType | Manager (template edit), filters | 3 types | |
| Checklist_Template.Checklist | Manager (templates), instance creation | active (`IsActive`) and one retired (`RetiredDateTime`); recurring ones with RepeatPeriod/ExpiresIn/ExpiryUnit; links Department, ChecklistType, Employee (owner), Employee_Responsible | IsAllResponsible=false needs the responsible list |
| Checklist_Template.Group -> Question (5 subtypes: Text, Checkbox, Instruction, MultipleChoice, Picture) + CheckboxOption / MultipleChoiceOption | template editor, execution page | each template: 2 groups; one question of each QuestionType; options for Checkbox and MultipleChoice; `SequenceNumber` set | question subtype entities extend Question: the row exists in both tables |
| Checklist_Instance.InstanceChecklist | Inspector "my checklists", Manager review / overdue | ONE ROW IN EVERY STATUS of ENUM_InstanceChecklistStatus: _New, In_Progress, Submitted, Resolved, Overdue_unassigned, Overdue_assigned, Overdue_waiting, Overdue_done | page XPaths: review = `Submitted or Resolved or Overdue_done`; overdue = `Overdue_unassigned/assigned/waiting`; unassigned rows have no Employee_Responsible on purpose |
| Checklist_Instance.InstanceQuestion (+5 subtypes, InstanceOption) | execution page | copies of the template questions; answers (Compliancy, AnswerDateTime) filled to match the status (none for _New, half for In_Progress, all for Submitted+) | |
| HistoryManagement.HistoryObject / HistoryItem | history list on submitted instances (`HistoryItem_HistoryObject = $currentObject`) | 1-2 items per submitted/resolved instance | |
| Checklist_Recurring.RepeatInterval | recurring settings | optional | |
| Checklist_Reporting.Mitigation, Report | report page | optional (Report is a FileDocument: needs the file) | file-storage trap as in Visual Inspection |
| Mobile_Inspector.Settings | mobile app | singleton | created by the app |
| Administration.Account | all | smoke_users.py | never a hand INSERT |

`gen_checklist_spec.py` writes exactly this as a `seed_usecase.py` spec.
