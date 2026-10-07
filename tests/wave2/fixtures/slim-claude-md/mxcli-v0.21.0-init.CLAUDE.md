# Mendix Project: SampleApp

This is a Mendix project configured for AI-assisted development using mxcli and MDL (Mendix Definition Language).

## Project Brain — read this first

If `docs/brain/` exists, read `docs/brain/project.md` before doing anything
else. It holds the decisions this project has already made — things no command can
tell you, and that are cheap to contradict by accident.

Then, depending on what you are doing:

- **Building in a module** — also read `docs/brain/modules/<Module>.md` for the
  modules you are about to touch. Not the whole directory; only those.
- **Planning, or picking work up** — run `./mxcli brain plan -p project.mpr`.
  It reports what is built from the model itself, so it cannot be out of date.

Record what you learn with `./mxcli brain capture`. Read
`.ai-context/skills/project-brain/SKILL.md` for what belongs there and what does not —
the short version is that anything mxcli can answer must never be written down.

## Communication Style

When discussing changes with the user:

- **Never show raw MDL scripts in chat.** Instead, describe changes in plain language as a numbered list.
- After the user approves, write the MDL to a script file, validate it, and execute it silently.
- Only show MDL code if the user explicitly asks to see the script.
- When reporting results, summarize what was created/modified in plain language.
- **Always quote identifiers** in MDL scripts with double quotes (`"Name"`). This prevents conflicts with MDL reserved keywords and is always safe — quotes are stripped automatically. Quote entity names, attribute names, parameter names, variable names, and association names.

**Example — instead of showing MDL code, write this:**

> Here's what I'll do:
> 1. Create a new **Customer** entity in MyModule with:
>    - **Name** (text, up to 100 characters)
>    - **Email** (text, up to 200 characters)
>    - **Age** (whole number)
>
> Shall I go ahead?

## Important: mxcli Location

The `mxcli` tool is located in the **root folder of this project**, not in the system PATH. Always use the local path:

```bash
./mxcli -p project.mpr    # Correct - uses local binary
```

**Do NOT use** `mxcli` directly - it will fail with "command not found". Always prefix with `./` to run the local binary.

## Mendix Validation Tool (mx)

The `mx` command validates Mendix projects (same checks as Studio Pro). To set it up:

```bash
./mxcli setup mxbuild -p project.mpr    # Auto-download for project's Mendix version
```

After setup, `mx` is at `~/.mxcli/mxbuild/{version}/modeler/mx`. Usage:

```bash
./mxcli docker check -p project.mpr   # Validate project (resolves the project's Mendix version)
```

To call `mx` directly, name the version — a `*` glob breaks once two are cached:

```bash
~/.mxcli/mxbuild/<version>/modeler/mx check project.mpr
```

## Quick Start

### Execute a Single Command

Use the `-c` flag to run a single MDL command:

```bash
./mxcli -p project.mpr -c "SHOW MODULES"              # List all modules
./mxcli -p project.mpr -c "SHOW STRUCTURE"             # Project overview
./mxcli -p project.mpr -c "SHOW ENTITIES IN MyModule"  # Entities in a module
./mxcli -p project.mpr -c "DESCRIBE ENTITY MyModule.Customer"  # Entity details
```

### Execute an MDL Script File

```bash
./mxcli exec script.mdl -p project.mpr
```

### Start Interactive REPL

```bash
./mxcli
# Then: CONNECT LOCAL 'project.mpr';
```

## IMPORTANT: Before Writing MDL Scripts or Working with Data

**Read the relevant skill files FIRST before writing any MDL, seeding data, or doing database/import work:**

Every skill is a `<name>/SKILL.md` directory with a `description` in its frontmatter (the
[Agent Skills](https://agentskills.io) standard), so a tool that reads them announces the whole set on
its own. The table below is a shortcut to the ones worth reading before you start, **not** the index —
list `.ai-context/skills/` for everything available.

| Skill File | When to Read |
|------------|-------------|
| `.ai-context/skills/write-microflows/SKILL.md` | **Before writing any microflow** - syntax, common mistakes, validation checklist |
| `.ai-context/skills/create-page/SKILL.md` | **Before creating any page** - widget syntax reference |
| `.ai-context/skills/alter-page/SKILL.md` | **Before modifying pages** - ALTER PAGE/SNIPPET SET, INSERT, DROP, REPLACE |
| `.ai-context/skills/overview-pages/SKILL.md` | CRUD page patterns (overview + edit) |
| `.ai-context/skills/master-detail-pages/SKILL.md` | Master-detail page patterns |
| `.ai-context/skills/generate-domain-model/SKILL.md` | Entity, association, enumeration syntax |
| `.ai-context/skills/organize-project/SKILL.md` | Folders, MOVE command, project structure |
| `.ai-context/skills/manage-security/SKILL.md` | Security roles, GRANT/REVOKE, access control |
| `.ai-context/skills/manage-navigation/SKILL.md` | Navigation profiles, menus, home/login pages |
| `.ai-context/skills/check-syntax/SKILL.md` | **Pre-flight** validation checklist |
| `.ai-context/skills/demo-data/SKILL.md` | **READ for any database/import work** - Mendix ID system, demo data |
| `.ai-context/skills/test-microflows/SKILL.md` | **READ for testing** - test annotations, file formats, Docker setup |
| `.ai-context/skills/project-brain/SKILL.md` | **Why was it done this way here?** - the project's recorded decisions in `docs/brain/` |

**Always validate before presenting to user:**

```bash
./mxcli check script.mdl                              # Syntax check
./mxcli check script.mdl -p project.mpr --references  # With reference validation
```

## MDL Commands by Domain

### Exploration & Structure

| Command | Description |
|---------|-------------|
| `SHOW MODULES` | List all modules |
| `SHOW STRUCTURE [DEPTH 1|2|3] [IN Module] [ALL]` | Compact project overview at different detail levels |
| `SHOW CALLERS OF Module.Microflow` | Find what calls a microflow |
| `SHOW CALLEES OF Module.Microflow` | Find what a microflow calls |
| `SHOW REFERENCES OF Module.Entity` | Find all references to an element |
| `SHOW IMPACT OF Module.Entity` | Impact analysis for changes |
| `SHOW CONTEXT OF Module.Microflow` | Show callers + callees + references |
| `SEARCH 'keyword'` | Full-text search across all strings and source |
| `HELP [topic]` | Show all commands or help on a topic |

### Domain Model

| Command | Description |
|---------|-------------|
| `SHOW ENTITIES [IN Module]` | List entities |
| `SHOW ASSOCIATIONS [IN Module]` | List associations |
| `SHOW ENUMERATIONS [IN Module]` | List enumerations |
| `SHOW CONSTANTS [IN Module]` | List constants |
| `DESCRIBE ENTITY Module.Entity` | Show entity definition in MDL |
| `DESCRIBE ASSOCIATION Module.Assoc` | Show association definition |
| `DESCRIBE ENUMERATION Module.Enum` | Show enumeration definition |
| `CREATE MODULE ModuleName` | Create a new module |
| `CREATE PERSISTENT ENTITY ...` | Create a persistent entity with attributes |
| `CREATE NON-PERSISTENT ENTITY ...` | Create a non-persistent (transient) entity |
| `CREATE ASSOCIATION ...` | Create an association between entities |
| `CREATE ENUMERATION ...` | Create an enumeration |
| `ALTER ENTITY Module.Entity ADD ...` | Add/rename/modify/drop attributes, indexes, docs |
| `DROP ENTITY Module.Entity` | Delete an entity |
| `DROP ASSOCIATION Module.Assoc` | Delete an association |
| `DROP ENUMERATION Module.Enum` | Delete an enumeration |

### Microflows & Nanoflows

| Command | Description |
|---------|-------------|
| `SHOW MICROFLOWS [IN Module]` | List microflows |
| `SHOW NANOFLOWS [IN Module]` | List nanoflows |
| `DESCRIBE MICROFLOW Module.Flow` | Show microflow definition in MDL |
| `DESCRIBE NANOFLOW Module.Flow` | Show nanoflow definition in MDL |
| `CREATE MICROFLOW ... BEGIN ... END;` | Create a microflow with activities |
| `CREATE NANOFLOW ... BEGIN ... END;` | Create a nanoflow with activities |
| `DROP MICROFLOW Module.Flow` | Delete a microflow |
| `DROP NANOFLOW Module.Flow` | Delete a nanoflow |

### Pages & Snippets

| Command | Description |
|---------|-------------|
| `SHOW PAGES [IN Module]` | List pages |
| `SHOW SNIPPETS [IN Module]` | List snippets |
| `DESCRIBE PAGE Module.Page` | Show page definition in MDL |
| `DESCRIBE SNIPPET Module.Snippet` | Show snippet definition |
| `CREATE PAGE ... { widgets }` | Create a page with widget syntax |
| `CREATE SNIPPET ... { widgets }` | Create a reusable snippet |
| `ALTER PAGE Module.Page { ops }` | Modify page in-place (SET, INSERT, DROP, REPLACE) |
| `ALTER SNIPPET Module.Snippet { ops }` | Modify snippet in-place |
| `DROP PAGE Module.Page` | Delete a page |
| `DROP SNIPPET Module.Snippet` | Delete a snippet |

### Security

| Command | Description |
|---------|-------------|
| `SHOW PROJECT SECURITY` | Security level, admin, demo users overview |
| `SHOW MODULE ROLES [IN Module]` | Module-level roles |
| `SHOW USER ROLES` | Project-level user roles |
| `SHOW DEMO USERS` | Configured demo users |
| `SHOW ACCESS ON MICROFLOW|PAGE|ENTITY Mod.Name` | Role access on element |
| `SHOW SECURITY MATRIX [IN Module]` | Full access overview |
| `CREATE MODULE ROLE Mod.Role` | Create a module role |
| `CREATE USER ROLE Name (Mod.Role, ...)` | Create a user role aggregating module roles |
| `ALTER USER ROLE Name ADD|REMOVE MODULE ROLES (...)` | Modify user role |
| `GRANT EXECUTE ON MICROFLOW Mod.MF TO Mod.Role` | Grant microflow access |
| `GRANT VIEW ON PAGE Mod.Page TO Mod.Role` | Grant page access |
| `GRANT Mod.Role ON Mod.Entity (CREATE, DELETE, READ *, WRITE *)` | Grant entity access |
| `REVOKE EXECUTE|VIEW|role ON element FROM role` | Revoke access |
| `ALTER PROJECT SECURITY LEVEL OFF|PROTOTYPE|PRODUCTION` | Set security level |
| `ALTER PROJECT SECURITY DEMO USERS ON|OFF` | Toggle demo users |
| `CREATE DEMO USER 'name' PASSWORD 'pass' (UserRole, ...)` | Create demo user |
| `DROP MODULE ROLE|USER ROLE|DEMO USER ...` | Delete roles/users |

### Navigation

| Command | Description |
|---------|-------------|
| `SHOW NAVIGATION` | Summary of all profiles |
| `SHOW NAVIGATION MENU [Profile]` | Menu tree for profile or all |
| `SHOW NAVIGATION HOMES` | Home page assignments across profiles |
| `DESCRIBE NAVIGATION [Profile]` | Full MDL output (round-trippable) |
| `CREATE OR REPLACE NAVIGATION Profile ...` | Full replacement of a navigation profile |

### Project Settings

| Command | Description |
|---------|-------------|
| `SHOW SETTINGS` | Overview of all settings |
| `DESCRIBE SETTINGS` | Full MDL output (round-trippable) |
| `ALTER SETTINGS MODEL Key = Value` | AfterStartupMicroflow, HashAlgorithm, JavaVersion, etc. |
| `ALTER SETTINGS CONFIGURATION 'Name' Key = Value` | DatabaseType, DatabaseUrl, HttpPortNumber, etc. |
| `ALTER SETTINGS CONSTANT 'Name' VALUE 'val' IN CONFIGURATION 'cfg'` | Override constant per configuration |
| `ALTER SETTINGS LANGUAGE Key = Value` | DefaultLanguageCode |
| `ALTER SETTINGS WORKFLOWS Key = Value` | UserEntity, DefaultTaskParallelism |

### Business Events & Java Actions

| Command | Description |
|---------|-------------|
| `SHOW DATABASE CONNECTIONS [IN Module]` | List database connections |
| `DESCRIBE DATABASE CONNECTION Mod.Name` | Show connection definition in MDL |
| `SHOW BUSINESS EVENTS [IN Module]` | List business event services |
| `DESCRIBE BUSINESS EVENT SERVICE Mod.Name` | Full MDL output |
| `CREATE BUSINESS EVENT SERVICE ...` | Create a business event service |
| `DROP BUSINESS EVENT SERVICE Mod.Name` | Delete a service |
| `SHOW JAVA ACTIONS [IN Module]` | List Java actions |
| `DESCRIBE JAVA ACTION Mod.Name` | Full MDL output with signature |
| `CREATE JAVA ACTION ... AS $$ ... $$` | Create with inline Java code |
| `DROP JAVA ACTION Mod.Name` | Delete a Java action |

### OData

| Command | Description |
|---------|-------------|
| `SHOW ODATA CLIENTS [IN Module]` | List consumed OData services |
| `SHOW ODATA SERVICES [IN Module]` | List published OData services |
| `DESCRIBE ODATA CLIENT Mod.Name` | Full consumed OData MDL output |
| `DESCRIBE ODATA SERVICE Mod.Name` | Full published OData MDL output |
| `CREATE ODATA CLIENT ...` | Create a consumed OData service |
| `CREATE ODATA SERVICE ...` | Create a published OData service |
| `ALTER ODATA CLIENT|SERVICE ...` | Modify an OData service |
| `DROP ODATA CLIENT|SERVICE Mod.Name` | Delete an OData service |

### External SQL

| Command | Description |
|---------|-------------|
| `SQL CONNECT <driver> '<dsn>' AS <alias>` | Connect to external database (postgres) |
| `SQL DISCONNECT <alias>` | Close connection |
| `SQL CONNECTIONS` | List active connections (alias + driver only) |
| `SQL <alias> SHOW TABLES` | List tables via information_schema |
| `SQL <alias> DESCRIBE <table>` | Show columns, types, nullability |
| `SQL <alias> <any-sql>` | Raw SQL passthrough to external DB |

### Catalog Queries

| Command | Description |
|---------|-------------|
| `REFRESH CATALOG` | Build catalog (metadata only) |
| `REFRESH CATALOG FULL` | Full catalog with activities, widgets, cross-refs |
| `SHOW CATALOG TABLES` | List available catalog tables |
| `SELECT ... FROM CATALOG.ENTITIES WHERE ...` | SQL queries against project metadata |

Available catalog tables: `CATALOG.MODULES`, `CATALOG.ENTITIES`, `CATALOG.MICROFLOWS`, `CATALOG.PAGES`, `CATALOG.WORKFLOWS`, `CATALOG.ENUMERATIONS`, `CATALOG.ASSOCIATIONS`, `CATALOG.SNIPPETS`, `CATALOG.REFS` (requires FULL mode).

### Project Organization

| Command | Description |
|---------|-------------|
| `MOVE PAGE|MICROFLOW|SNIPPET|... Mod.Name TO FOLDER 'path'` | Move element to folder |
| `MOVE PAGE Mod.Name TO Module` | Move to module root |
| `MOVE ENTITY Old.Name TO NewModule` | Move entity across modules |
| `SHOW WORKFLOWS [IN Module]` | List workflows |
| `DESCRIBE WORKFLOW Module.Workflow` | Show workflow definition |
| `SHOW WIDGETS [IN Module]` | Widget discovery (experimental) |

## Script Validation (mxcli check)

Before executing MDL scripts, validate them for syntax errors:

```bash
./mxcli check script.mdl
```

### Check with Reference Validation

Validate that all referenced modules, entities, and associations exist:

```bash
./mxcli check script.mdl -p project.mpr --references
```

The reference checker is smart - it automatically skips references to objects that are created within the same script.

## Linting

Check your project for common issues:

```bash
# Lint the project
./mxcli lint -p project.mpr

# With colored output
./mxcli lint -p project.mpr --color

# List available rules
./mxcli lint -p project.mpr --list-rules

# Output as SARIF
./mxcli lint -p project.mpr --format sarif > results.sarif
```

### Built-in Rules

| Rule | Category | Description |
|------|----------|-------------|
| MPR001 | quality | PascalCase naming conventions (entities, microflows, pages, enumerations) |
| MPR002 | quality | Empty microflows (no activities) |
| MPR003 | design | Domain model size (>15 persistent entities per module) |
| MPR004 | correctness | Empty validation feedback message (CE0091) |
| MPR005 | correctness | Unconfigured image widget source |
| MPR006 | correctness | Empty containers (runtime crash) |
| MPR007 | security | Navigation page without allowed role (CE0557) |
| SEC001 | security | Persistent entity without access rules |
| SEC002 | security | Weak password policy (minimum length < 8) |
| SEC003 | security | Demo users active at non-development security level |

### Bundled Starlark Rules

27 additional rules in `.claude/lint-rules/*.star`:

| Rule | Category | Description |
|------|----------|-------------|
| SEC004 | security | Guest access enabled - review anonymous entity access |
| SEC005 | security | Strict mode disabled - XPath constraint enforcement off |
| SEC006 | security | PII attributes exposed without access rules |
| SEC007 | security | Anonymous unconstrained READ (DIVD-2022-00019) |
| SEC008 | security | PII entities readable without row scoping |
| SEC009 | security | Large entities missing member-level access restrictions |
| ARCH001 | architecture | Cross-module data access in pages |
| ARCH002 | architecture | Data changes should go through microflows |
| ARCH003 | architecture | Persistent entities need a unique business key |
| QUAL001 | quality | McCabe cyclomatic complexity threshold |
| QUAL002 | quality | Missing documentation on entities/microflows |
| QUAL003 | quality | Long microflows (too many activities) |
| QUAL004 | quality | Orphaned/unreferenced elements |
| DESIGN001 | design | Entity with too many attributes |
| CONV001 | naming | Boolean attributes must start with Is/Has/Can/Should/Was/Will |
| CONV002 | quality | String/numeric attributes should not have default values |
| CONV003 | naming | Pages should follow Entity_NewEdit/View/Overview naming |
| CONV004 | naming | Enumerations should be prefixed with ENUM_ |
| CONV005 | naming | Snippets should be prefixed with SNIPPET_ |
| CONV006 | security | Entity access rules should not grant Create/Delete rights |
| CONV007 | security | All persistent entity access rules need XPath constraints |
| CONV008 | security | Each module role should map to exactly one user role |
| CONV009 | quality | Microflows should have at most 15 objects |
| CONV015 | quality | Entities should not have validation rules |
| CONV016 | performance | Entities should not have event handlers |
| CONV017 | performance | Attributes should not be calculated (virtual) |

Custom Starlark rules in `.claude/lint-rules/*.star` are loaded automatically. See `write-lint-rules` skill for authoring guide.

## Best Practices Report

Generate a scored best practices report:

```bash
# Markdown report (default)
./mxcli report -p project.mpr

# JSON report
./mxcli report -p project.mpr --format json

# HTML report
./mxcli report -p project.mpr --format html
```

The report scores 6 categories (Naming, Security, Quality, Architecture, Performance, Design) on a 0-100 scale. See `assess-quality` skill for the full assessment guide.

## Slash Commands

Use these commands to quickly perform common tasks:

| Command | Description |
|---------|-------------|
| `/create-entity` | Create a new entity with attributes |
| `/create-crud` | Generate entity + overview + edit pages |
| `/refresh-catalog` | Rebuild catalog for queries |
| `/explore` | Explore project structure |
| `/check-script` | Validate MDL script syntax |
| `/validate-project` | Run mx check to validate project |
| `/lint` | Check project for common issues |
| `/test` | Run Playwright tests against the running app |
| `/diff-local` | Show git diff of local MPR v2 changes |
| `/diff-script` | Compare MDL script against project state |

## Skills Reference

Skills are in `.ai-context/skills/<name>/SKILL.md` (and `.claude/skills/` for Claude
Code, which discovers them from there). Each one's frontmatter says what it covers and when to reach
for it. Read the relevant skill before starting work.

### Quick Reference

| Skill | Purpose |
|-------|--------|
| cheatsheet-variables | Variable declaration syntax quick lookup |
| cheatsheet-errors | Common MDL errors and fixes |

### Syntax Reference

| Skill | Purpose |
|-------|--------|
| mdl-entities | Entity, attribute, association syntax |
| write-microflows | **Read first** - Microflow syntax, common mistakes |
| write-oql-queries | OQL query syntax for VIEW entities |
| create-page | Page and widget syntax |
| fragments | Reusable widget group syntax |

### Patterns

| Skill | Purpose |
|-------|--------|
| patterns-crud | Create/Read/Update/Delete patterns |
| patterns-data-processing | Loops, aggregates, batch processing |
| validation-microflows | Validation feedback patterns |

### Pages

| Skill | Purpose |
|-------|--------|
| overview-pages | List/grid overview page patterns |
| master-detail-pages | Master-detail layout patterns |
| alter-page | ALTER PAGE/SNIPPET in-place modifications |
| bulk-widget-updates | Bulk widget property updates across pages |

### Integration

| Skill | Purpose |
|-------|--------|
| database-connections | External database connections (PostgreSQL, Oracle) |
| rest-client | REST API consumption |
| mock-rest-apis | Mocking a REST dependency (Prism, forward proxy, constant swap) |
| java-actions | Custom Java actions |
| odata-data-sharing | OData services and external entities |

### Operations

| Skill | Purpose |
|-------|--------|
| manage-security | Security roles, GRANT/REVOKE, access control |
| manage-navigation | Navigation profiles, menus, home/login pages |
| organize-project | Folders, MOVE command, project structure |
| project-settings | Project configuration (model, runtime, language) |
| business-events | Business event services |

### Infrastructure

| Skill | Purpose |
|-------|--------|
| docker-workflow | Docker build and deployment |
| run-app | Running the Mendix app locally |
| runtime-admin-api | M2EE admin API |
| system-module | System module entities reference |
| verify-with-oql | OQL verification queries |
| demo-data | **Read first for data work** - Demo data insertion |

### Testing & Quality

| Skill | Purpose |
|-------|--------|
| test-app | Playwright UI tests + DB assertions |
| record-narrated-demo | Narrated walkthrough video, after the journey passes |
| test-microflows | Microflow unit testing (.test.mdl files) |
| write-lint-rules | Custom Starlark lint rule authoring |
| assess-quality | **Full project quality assessment** against best practices |

### Domain Model

| Skill | Purpose |
|-------|--------|
| generate-domain-model | Full domain model generation |

### Migration

| Skill | Purpose |
|-------|--------|
| assess-migration | Migration assessment and planning |
| migrate-k2-nintex | K2/Nintex workflow migration |
| migrate-outsystems | OutSystems migration |
| migrate-oracle-forms | Oracle Forms migration |
| graph-studio-app | Reverse-engineer/graph Studio Pro app |

### Debugging & Preflight

| Skill | Purpose |
|-------|--------|
| debug-bson | BSON serialization debugging |
| check-syntax | Pre-flight validation checklist |

## MDL Syntax Quick Reference

### Entity Generalization (EXTENDS)

**CRITICAL: EXTENDS goes BEFORE the opening parenthesis, not after!**

```sql
CREATE PERSISTENT ENTITY Module.ProductPhoto EXTENDS System.Image (
  PhotoCaption: String(200)
);
```

### Microflows - Supported Statements

| Statement | Syntax |
|-----------|--------|
| Variable declaration (primitive only) | `DECLARE $Var Type = value;` |
| Assignment | `SET $Var = expression;` |
| Enum split (CASE) | `CASE $Var/Attr WHEN Value[, Value] THEN ... WHEN (empty) THEN ... END CASE;` (bare enum values, no `ELSE`, no alias) |
| Create object | `$Var = CREATE Module.Entity (Attr = value);` |
| Change object | `CHANGE $Entity (Attr = value);` |
| Commit | `COMMIT $Entity [WITH EVENTS] [REFRESH];` |
| Delete | `DELETE $Entity;` |
| Rollback | `ROLLBACK $Entity [REFRESH];` |
| Retrieve | `RETRIEVE $Var FROM Module.Entity [WHERE condition];` |
| Call microflow | `$Result = CALL MICROFLOW Module.Name (Param = $value);` |
| Call nanoflow | `$Result = CALL NANOFLOW Module.Name (Param = $value);` |
| Call Java action | `$Result = CALL JAVA ACTION Module.Name (Param = value);` |
| Show page | `SHOW PAGE Module.PageName ($Param = $value);` |
| Close page | `CLOSE PAGE;` |
| Validation | `VALIDATION FEEDBACK $Entity/Attribute MESSAGE 'message';` |
| Log | `LOG INFO|WARNING|ERROR [NODE 'name'] 'message';` |
| Annotation | `@annotation 'text'` (before activity) |
| Position | `@position(x, y)` (before activity) |
| Error handling | `... ON ERROR CONTINUE|ROLLBACK|{ handler };` |
| IF | `IF condition THEN ... [ELSE ...] END IF;` |
| LOOP | `LOOP $Item IN $List BEGIN ... END LOOP;` |
| WHILE | `WHILE condition BEGIN ... END WHILE;` |
| Return | `RETURN $value;` |

### Microflows - NOT Supported (Will Cause Parse Errors)

| Unsupported | Use Instead |
|-------------|-------------|
| `DECLARE $Entity Module.Entity;` (MDL043/CE0053) | Get the object from a parameter, a `RETRIEVE`, or `$E = CREATE Module.Entity(...)` |
| `DECLARE $List List of Module.Entity = empty;` (MDL040) | Accept the list as a parameter, or `RETRIEVE` / `$L = CREATE LIST OF Module.Entity` |
| `TRY ... CATCH` | `ON ERROR { ... }` blocks |

**Notes:**
- `RETRIEVE ... LIMIT n` IS supported. `LIMIT 1` returns a single entity.
- `ROLLBACK $Entity [REFRESH];` IS supported. Rolls back uncommitted changes.

### Pages Syntax Summary

| Element | Syntax | Example |
|---------|--------|--------|
| Page properties | `(Key: value, ...)` | `(Title: 'Edit', Layout: Atlas_Core.Atlas_Default)` |
| Widget name | Required after type | `TEXTBOX txtName (...)` |
| Attribute binding | `Attribute: AttrName` | `TEXTBOX txt (Label: 'Name', Attribute: Name)` |
| Microflow action | `Action: MICROFLOW Name(Param: val)` | `Action: MICROFLOW Mod.ACT_Process(Order: $Order)` |
| Database source | `DataSource: DATABASE Entity` | `DATAGRID dg (DataSource: DATABASE Mod.Entity)` |
| Selection source | `DataSource: SELECTION widget` | `DATAVIEW dv (DataSource: SELECTION galleryList)` |

**Supported Widgets:** LAYOUTGRID, ROW, COLUMN, CONTAINER, TEXTBOX, TEXTAREA, CHECKBOX, RADIOBUTTONS, DATEPICKER, COMBOBOX, DYNAMICTEXT, DATAGRID, GALLERY, LISTVIEW, IMAGE, STATICIMAGE, DYNAMICIMAGE, ACTIONBUTTON, LINKBUTTON, DATAVIEW, HEADER, FOOTER, CONTROLBAR, SNIPPETCALL, NAVIGATIONLIST, CUSTOMCONTAINER.

### ALTER PAGE / ALTER SNIPPET

Modify existing pages in-place without full `CREATE OR REPLACE`:

| Operation | Syntax |
|-----------|--------|
| Set property | `SET Caption = 'New' ON widgetName` |
| Set multiple | `SET (Caption = 'Save', ButtonStyle = Success) ON btn` |
| Page-level set | `SET Title = 'New Title'` (no ON clause) |
| Insert after | `INSERT AFTER widgetName { widgets }` |
| Insert before | `INSERT BEFORE widgetName { widgets }` |
| Drop widgets | `DROP WIDGET name1, name2` |
| Replace widget | `REPLACE widgetName WITH { widgets }` |

### Quoted Identifiers

**Always quote all identifiers** (entity names, attribute names, parameter names) with double quotes. This eliminates all reserved keyword conflicts and is always safe — quotes are stripped automatically.

```sql
CREATE PERSISTENT ENTITY Module."Customer" (
  "Name": String(200),
  "Status": String(50),
  "Create": DateTime
);
```

## MDL Script Files

Store MDL scripts in the `mdlsource/` directory:

```
mdlsource/
├── domain-model.mdl      # Entity definitions
├── microflows.mdl        # Business logic
└── setup.mdl             # Initial setup script
```

Execute a script:

```sql
EXECUTE SCRIPT 'mdlsource/domain-model.mdl';
```

## Example: Create an Entity

```sql
/**
 * Customer entity
 *
 * Stores customer information.
 */
@Position(100, 100)
CREATE PERSISTENT ENTITY Sales.Customer (
  /** Customer name */
  Name: String(200) NOT NULL ERROR 'Name is required',
  /** Email address */
  Email: String(200) UNIQUE ERROR 'Email must be unique',
  /** Phone number */
  Phone: String(50),
  /** Active status */
  IsActive: Boolean DEFAULT true
);
```

## Example: Create a Microflow

```sql
/**
 * Validates a customer before saving
 *
 * @param $Customer The customer to validate
 * @returns Boolean indicating validity
 */
CREATE MICROFLOW Sales.VAL_Customer (
  $Customer: Sales.Customer
)
RETURNS Boolean AS $IsValid
BEGIN
  DECLARE $IsValid Boolean = true;

  IF trim($Customer/Name) = '' THEN
    SET $IsValid = false;
    VALIDATION FEEDBACK $Customer/Name MESSAGE 'Name is required';
  END IF;

  RETURN $IsValid;
END;
/
```

## MDL Reference

For detailed MDL syntax, see the skill files in `.ai-context/skills/<name>/SKILL.md`.
