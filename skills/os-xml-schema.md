# OS 11 XML Blueprint Schema
**Purpose:** Teaches Claude the OutSystems 11 eSpace XML format so extraction prompts
work without pasting raw XML first.
**Source:** Apex M-0022 — 114 real eSpace XML files processed 2026-05.

---

## What an eSpace XML file is

Each `.xml` file in an BlueprintVendor blueprint delivery is one OutSystems **eSpace** —
equivalent to one Mendix module. A large application has 10-100 eSpaces.
The root element is `<ESpace>` with key attributes identifying the module.

```xml
<ESpace
  Version="11"
  Key="ESpace:EXAMPLEeSpaceKey000001"     ← GUID with type prefix
  Name="M0022_PayerRegist"                  ← module name (= file name without .xml)
  Description="Order & billing registration"           ← Japanese description is common
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

Keys are globally unique across all eSpaces. Cross-eSpace references use these keys
(not names), so a `Reference` node in one eSpace pointing to `Entity:abc123==` in
another means "import this entity from that module".

---

## Entities (persistent data)

OS `Entity` ≈ Mendix persistent entity.

```xml
<Entity
  Key="Entity:Lmh5qP7..."
  Name="ENPayerDetail"                ← EN prefix = External/Normal entity convention
  Description="Order detail"
  IsPersistent="Yes"
  PublicEntityStatus="Internal"       ← Internal = not shared across modules
>
  <Attributes>
    <Attribute
      Key="Attribute:abc..."
      Name="PayerCode"
      Label="Order code"              ← Japanese UI label
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
    <Index Name="IdxPayerCode" IsUnique="Yes">
      <IndexAttributes>
        <IndexAttribute AttributeName="PayerCode" />
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
  Name="PayerDetailDto"
  Description="Form data for payer detail screen"
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
  Name="ACT_PayerDetail_Save"
  Description="Save processing"
  IsPublic="Yes"                     ← Public = callable from other eSpaces
>
  <InputParameters>
    <InputParameter Name="PayerDetailId" DataType="ENPayerDetail Identifier" IsMandatory="Yes" />
  </InputParameters>
  <OutputParameters>
    <OutputParameter Name="Success" DataType="Boolean" />
  </OutputParameters>
</Action>
```

**What you can extract from Actions:** name, description, input/output parameter names
and types, public/private, which eSpace it belongs to.
**What you cannot extract:** the actual logic body (encoded in binary — use C# source
if available for implementation details).

---

## WebScreens (pages)

OS `WebScreen` ≈ Mendix page.

```xml
<WebScreen
  Key="WebScreen:ghi..."
  Name="PayerDetail"
  Description="Order detail"
  IsPublic="Yes"
  HTTPMethod="GET"
>
  <InputParameters>
    <InputParameter Name="PayerDetailId" DataType="ENPayerDetail Identifier" />
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
<WebBlock Name="SNP_CorpSearch" Description="Company search snippet">
  <InputParameters>
    <InputParameter Name="SearchDto" DataType="CorpSearchDto" />
  </InputParameters>
  <!-- widget tree -->
</WebBlock>
```

---

## Roles (security)

```xml
<Roles>
  <Role Name="HQDomestic" Description="Domestic HQ" IsPersistent="Yes" />
  <Role Name="SysAdmin"   Description="System administrator" IsPersistent="Yes" />
</Roles>
```

---

## References (cross-module imports)

When one eSpace uses entities or actions from another, they appear as References:

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

## Common naming conventions in Apex OS code

| Prefix | Meaning |
|--------|---------|
| `EN` | Entity (e.g. `ENPayerDetail`) |
| `ACT_` | Action (microflow) |
| `SNP_` | Snippet/WebBlock |
| `JOB_` | Timer/scheduled job |
| `M0022_` | Function code prefix |
| `C-0031` | Common component code |
| `KB_` | Knowledge base file (extraction output, not OS) |
| `Dto` suffix | Non-persistent structure |
| `RW` suffix | Read-Write screen variant |
| `CS` suffix | Cross-space / shared module |
