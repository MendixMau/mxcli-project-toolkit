# OS 11 XML Blueprint Schema
**Applies to:** migration.
**Requires:** bash and Python 3 — this skill runs toolkit shell scripts. Run `bin/doctor.sh` once on a new machine; it names anything missing and how to get it. Windows: use Git Bash, and see the Prerequisites section of `conversion-runbook.md`.
**Purpose:** Teaches Claude the OutSystems 11 module XML format so extraction prompts
work without pasting raw XML first.
**Examples:** every module name, entity, role and description below is a synthetic
placeholder (`ACME01_…`, `C-0001`, `EXAMPLE…` keys). They illustrate the XML *shape*
only — no real estate uses these names. Never paste identifiers, descriptions or
scale figures from a real source into this file; `bin/check-no-client-data.sh`
blocks the commit if you do.

> **Prerequisite:** OutSystems exports (`.osp` / `.oml`) are encrypted. This schema
> applies to **decrypted module XML** only; obtaining that XML requires a compatible
> OutSystems decryption service and is outside this pipeline's scope.

---

## What a module XML file is

Each `.xml` file in an OS 11 blueprint delivery is one OutSystems **module** —
equivalent to one Mendix module. A large application has 10-100 modules.
The root element is `<ESpace>` with key attributes identifying the module.

```xml
<ESpace
  Version="11"
  Key="ESpace:EXAMPLEeSpaceKey000001"     ← GUID with type prefix
  Name="ACME01_OrderRegist"                  ← module name (= file name without .xml)
  Description="Order & billing registration"           ← developer-authored; any language
  ModuleType="Service|Extension|..."        ← Service = normal app module
>
  <SiteProperties>...</SiteProperties>      ← module-level constants
  <Roles>...</Roles>                        ← security roles
  <Entities>...</Entities>                  ← persistent data entities
  <Structures>...</Structures>             ← non-persistent structures (Dto equivalent)
  <StaticEntities>...</StaticEntities>     ← enumerations
  <WebFlows>...</WebFlows>                 ← page navigation groups
  <WebScreens>...</WebScreens>             ← individual pages/screens
  <WebBlocks>...</WebBlocks>               ← reusable UI components (snippet equivalent)
  <Actions>...</Actions>                   ← server actions (microflow equivalent)
  <References>...</References>             ← imported external actions/entities
  <Timers>...</Timers>                     ← scheduled jobs
  <ServiceActions>...</ServiceActions>     ← REST/SOAP exposed actions
  <UserExceptions>...</UserExceptions>     ← custom exception types
</ESpace>
```

---

## Key identifier pattern

Every OS element has a `Key` attribute in the format `TypeName:Base64GUID`:

```
Entity:abc123==
Attribute:xyz789==
Action:def456==
WebScreen:ghi012==
```

Keys are globally unique across all modules. Cross-module references use these keys
(not names), so a `Reference` node in one module pointing to `Entity:abc123==` in
another means "import this entity from that module".

---

## Entities (persistent data)

OS `Entity` ≈ Mendix persistent entity.

```xml
<Entity
  Key="Entity:Lmh5qP7..."
  Name="ENOrderDetail"                ← EN prefix = External/Normal entity convention
  Description="Order detail"
  IsPersistent="Yes"
  PublicEntityStatus="Internal"       ← Internal = not shared across modules
>
  <Attributes>
    <Attribute
      Key="Attribute:abc..."
      Name="OrderCode"
      Label="Order code"              ← UI label (any language)
      DataType="Text"                 ← Text / Integer / DateTime / Boolean / etc.
      Length="10"
      IsMandatory="Yes"
      DefaultValue=""
      IsPrimaryKey="No"               ← OS has its own Id; domain PKs are attributes
    />
    <Attribute Name="Id" DataType="Long Integer" IsPrimaryKey="Yes" />
    <!-- ... more attributes ... -->
  </Attributes>
  <Indexes>
    <Index Name="IdxOrderCode" IsUnique="Yes">
      <IndexAttributes>
        <IndexAttribute AttributeName="OrderCode" />
      </IndexAttributes>
    </Index>
  </Indexes>
</Entity>
```

**DataType mapping OS → Mendix:**

| OS DataType | Mendix Type |
|-------------|-------------|
| `Text` | `String(n)` where n = Length |
| `Integer` | `Integer` |
| `Long Integer` | `Long` |
| `Decimal` | `Decimal` |
| `Boolean` | `Boolean` |
| `DateTime` | `DateTime` |
| `Date` | `Date` |
| `Currency` | `Decimal` |
| `Binary Data` | `Binary` |
| `Entity Identifier` (Entity:Key) | Foreign key → association in Mendix |
| `<EntityName> Identifier` | Reference attribute → association |

---

## Structures (non-persistent / Dto equivalent)

OS `Structure` ≈ Mendix non-persistent entity (NPE). Used for form data, API payloads,
computed views.

```xml
<Structure
  Key="Structure:xyz..."
  Name="OrderDetailDto"
  Description="Form data for order detail screen"
>
  <RecordType>
    <Attribute Name="SelectedCompanyName" DataType="Text" Length="200" />
    <Attribute Name="CurrencyCode"        DataType="Text" Length="3" />
    <Attribute Name="Deadline"            DataType="DateTime" />
  </RecordType>
</Structure>
```

---

## Static Entities (enumerations)

OS `StaticEntity` ≈ Mendix enumeration.

```xml
<StaticEntity Name="ENApplyCategory" Description="Application category">
  <Attributes>
    <Attribute Name="Label" DataType="Text" />
    <Attribute Name="Order" DataType="Integer" />
  </Attributes>
  <StaticRecords>
    <StaticRecord Name="NewRegistration">
      <StaticRecordAttributeValues>
        <StaticRecordAttributeValue AttributeName="Label" Value="New registration" />
        <StaticRecordAttributeValue AttributeName="Order" Value="1" />
      </StaticRecordAttributeValues>
    </StaticRecord>
    <StaticRecord Name="Expansion">
      <StaticRecordAttributeValues>
        <StaticRecordAttributeValue AttributeName="Label" Value="Account addition" />
      </StaticRecordAttributeValues>
    </StaticRecord>
  </StaticRecords>
</StaticEntity>
```

---

## Actions (server-side logic = microflows)

OS `Action` ≈ Mendix microflow. The logic body is encoded (not readable as text in the
XML — it's a binary/base64 blob). What IS readable:

```xml
<Action
  Key="Action:def456..."
  Name="ACT_OrderDetail_Save"
  Description="Save processing"
  IsPublic="Yes"                     ← Public = callable from other modules
>
  <InputParameters>
    <InputParameter Name="OrderDetailId" DataType="ENOrderDetail Identifier" IsMandatory="Yes" />
  </InputParameters>
  <OutputParameters>
    <OutputParameter Name="Success" DataType="Boolean" />
  </OutputParameters>
</Action>
```

**What you can extract from Actions:** name, description, input/output parameter names
and types, public/private, which module it belongs to.
**What you cannot extract:** the actual logic body (encoded in binary — use C# source
if available for implementation details).

---

## WebScreens (pages)

OS `WebScreen` ≈ Mendix page.

```xml
<WebScreen
  Key="WebScreen:ghi..."
  Name="OrderDetail"
  Description="Order detail"
  IsPublic="Yes"
  HTTPMethod="GET"
>
  <InputParameters>
    <InputParameter Name="OrderDetailId" DataType="ENOrderDetail Identifier" />
    <InputParameter Name="In_WfMode"     DataType="Text" />
  </InputParameters>
  <Layout Name="MainLayoutRW" />
  <!-- Widget tree — can be very deep, includes Tables, Expressions, Buttons, Forms -->
</WebScreen>
```

The widget tree inside WebScreen describes the UI structure. Key widget types:

| OS Widget | Mendix Equivalent |
|-----------|------------------|
| `TableRecords` | ListView / DataGrid |
| `EditRecord` / `Form` | DataView |
| `Expression` | DynamicText |
| `Input` | TextBox |
| `TextArea` | TextArea |
| `Button` | ActionButton |
| `Link` | LinkButton |
| `Container` | LayoutContainer |
| `WebBlockWidget` | SnippetCall |
| `IfWidget` | ConditionalVisibility container |
| `Dropdown` | ComboBox |
| `Checkbox` | CheckBox |
| `DateTimePicker` | DatePicker |

---

## WebBlocks (reusable UI = snippets)

```xml
<WebBlock Name="SNP_PartnerLookup" Description="Company search snippet">
  <InputParameters>
    <InputParameter Name="SearchDto" DataType="PartnerLookupDto" />
  </InputParameters>
  <!-- widget tree -->
</WebBlock>
```

---

## Roles (security)

```xml
<Roles>
  <Role Name="HQUser" Description="Domestic HQ" IsPersistent="Yes" />
  <Role Name="SysAdmin"   Description="System administrator" IsPersistent="Yes" />
</Roles>
```

---

## References (cross-module imports)

When one module uses entities or actions from another, they appear as References:

```xml
<References>
  <Reference Name="AppCommon_Role" ReferenceKey="ESpace:6EeW...">
    <Actions>
      <ActionReference Name="CheckPermission" OriginalKey="Action:abc..." />
    </Actions>
    <Entities>
      <EntityReference Name="ENEmployee" OriginalKey="Entity:xyz..." />
    </Entities>
  </Reference>
</References>
```

This is the cross-module dependency map. Extract it to understand which modules must be
built before others.

---

## Timers (scheduled jobs)

```xml
<Timer Name="JOB_SapSync" Description="SAP sync" Schedule="0 2 * * *">
  <Action Name="ACT_SapSync_Run" />
</Timer>
```

---

## SiteProperties (module constants)

```xml
<SiteProperties>
  <SiteProperty Name="SAP_BaseUrl"    DataType="Text"    DefaultValue="https://sap.example.com" />
  <SiteProperty Name="SAP_ApiKey"     DataType="Text"    DefaultValue="" />
  <SiteProperty Name="Debug_Mode"     DataType="Boolean" DefaultValue="False" />
</SiteProperties>
```

---

## Parsing notes for extractors

1. **Always force arrays** for these tags — OS XML inconsistently uses single vs multiple
   child elements for the same tag type:
   `Entity, Attribute, Structure, RecordType, Reference, WebScreen, WebFlow, WebBlock,
   Action, ScreenAction, StaticRecord, StaticRecordAttributeValue, InputParameter,
   OutputParameter, LocalVariable, Role, SQL, Timer, SiteProperty, ServiceAction,
   UserException, Index, IndexAttribute, ClientAction, Filter, Join, DataAction`

2. **Attribute prefix:** All XML attributes are accessed with `@_` prefix when using
   fast-xml-parser with `attributeNamePrefix: '@_'`.

3. **Key extraction:** `node['@_Key']` — always check this for cross-reference mapping.

4. **HTML entity decoding:** Description fields contain `&amp;`, `&lt;`, `&#xA;` etc.
   Decode before storing.

5. **Action logic is NOT in XML:** The `<Action>` body is binary-encoded. Only
   signature (name, params, types) is readable. For implementation: use C# source if
   available, otherwise infer from screen widget bindings.

6. **Module name from root:** `data.ESpace['@_Name']` is the authoritative module name.
   Use it as the grouping key for all extracted items.

---

## Naming conventions: derive the estate's own map before extracting

**Do not reuse another estate's prefix table.** Every OutSystems estate invents its own
scheme, it is almost never documented, and guessing it wrong mistranslates every name
downstream. Deriving the map is a five-minute job that pays for itself immediately.

**How to derive it:**

1. List every module name (`ESpace/@Name` across all XML files) and sort them. The
   shared leading tokens are the module-level scheme.
2. Within one module, list `Entity/@Name`, `Action/@Name`, `WebBlock/@Name`,
   `Timer/@Name`. Per-item-type prefixes fall out immediately.
3. Look for *suffixes* too — they usually encode a variant (read-only vs read-write) or
   a structure kind, and they are easier to miss than prefixes.
4. Record the result in the project's own KB as a two-column table, and cite it from the
   naming-translation section of the BRD. It is an input to every later mapping decision.

**The shapes you will typically meet** (illustrative only — confirm against the estate):

| Shape | Usually means |
|---|---|
| Two-letter item prefix (`ENOrderDetail`) | Item type — entity, structure, etc. |
| Verb-ish action prefix (`ACT_`, `SVC_`) | Server action / microflow |
| Snippet prefix (`SNP_`, `BLK_`) | WebBlock |
| Job prefix (`JOB_`, `TMR_`) | Timer / scheduled job |
| Alphanumeric module prefix (`ACME01_`, `FIN02_`) | Function or business-area code |
| Dotted or dashed code (`C-0001`) | Entry in a component register maintained outside OS |
| `Dto` / `Rec` / `Str` suffix | Non-persistent structure |
| Single/double-letter suffix (`RW`, `RO`, `CS`) | Screen variant or shared/cross-module marker |

**Ask, don't infer, for the two that matter most:** the module prefix (it maps to your
Mendix module boundaries) and any component-register code (it points at documentation
that lives outside the source entirely).
