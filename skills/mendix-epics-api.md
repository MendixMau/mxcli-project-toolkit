# Mendix Epics API — Skill & Learnings

**Applies to:** any mxcli project using the Mendix Epics board.

Use this skill whenever working with the Mendix Epics board programmatically: creating/reading stories and epics, updating workflow state, or integrating BRDs with the portal.

---

## Setup

**PAT storage:** `~/Mendix/.env` (outside any git repo, shared across projects)

```bash
# ~/Mendix/.env
MX_PAT=<your-token>
MX_APP_ID=<your-app-uuid>   # e.g. 00000000-0000-0000-0000-000000000000
```

**Load before any API call:**
```bash
source ~/Mendix/.env
```

**Required PAT scopes:** `mx:epics:read`, `mx:epics:write`

**Base URL:** `https://epics-api.mendix.com/v1/projects/{appId}`

**Auth header:** `Authorization: MxToken $MX_PAT`

**SECURITY:** Never echo `MX_PAT` in chat, memory, or git-tracked files. Never use `!` prefix for commands that print the PAT.

---

## Wrapper Script

A wrapper script (e.g. `bin/stories.sh`) that shells out to these endpoints is a straightforward
build if none exists yet:

```bash
source ~/Mendix/.env
bash bin/stories.sh list-stories
bash bin/stories.sh list-epics
bash bin/stories.sh create-story PROJ-EP-1 "Title" "Description" 3
bash bin/stories.sh activate-story PROJ-8
bash bin/stories.sh backlog-story PROJ-8
bash bin/stories.sh delete-story PROJ-7
bash bin/stories.sh get-statuses
```

---

## Endpoints Reference

### Epics

| Method | Path | Description |
|--------|------|-------------|
| GET | `/epics` | List all epics (query: `limit`, `offset`) |
| POST | `/epics` | Create an epic |
| PATCH | `/epics/{epicUUID}` | Update epic (returns 204) |
| DELETE | `/epics/{epicUUID}` | Delete epic (returns 204) |

**Create epic body:**
```json
{
  "name": "Epic title",
  "objective": "What this epic achieves",
  "labels": ["Phase-1"],
  "assigneeId": "uuid-of-user"
}
```

**Epic response fields:** `epicId` (UUID), `readableEpicId` (e.g. `PROJ-EP-001`), `epicUrl`, `name`, `objective`, `numberOfStories`, `numberOfStoryPoints`

> Use `readableEpicId` (e.g. `PROJ-EP-001`) as the `epicId` when creating stories — NOT the UUID.

---

### Stories

| Method | Path | Description |
|--------|------|-------------|
| GET | `/stories` | List all stories (query: `limit`, `offset`) |
| GET | `/stories/{storyId}` | Get single story by readable ID |
| POST | `/stories` | Create stories (MUST be an array) |
| PATCH | `/stories/{storyId}` | Update story fields (returns 204) |
| DELETE | `/stories/{storyId}` | Delete story |

**Create story body — MUST be a JSON array, not an object:**
```json
[
  {
    "title": "Story title",
    "description": "Acceptance criteria...",
    "storyType": "Feature",
    "storyPoints": 3,
    "storyLevel": "Backlog",
    "epicId": "PROJ-EP-001"
  }
]
```

> **Critical gotcha:** Sending an object `{}` instead of an array `[{}]` silently returns `{"items":[]}` with no error. Always use an array.

**PATCH story — writable fields:**
```json
{
  "title": "...",
  "description": "...",
  "storyPoints": 5,
  "storyType": "Feature",
  "storyLevel": "Active"
}
```

**Story field reference:**

| Field | Type | Notes |
|-------|------|-------|
| `uuid` | string | Internal UUID |
| `storyId` | string | Readable ID, e.g. `PROJ-8` — use this in PATCH/DELETE paths |
| `title` | string | Writable |
| `description` | string | Writable (HTML or plain) |
| `storyPoints` | integer | Writable |
| `storyType` | string | `Feature` or `Bug` — writable |
| `storyLevel` | string | `Backlog` or `Active` — writable, controls sprint visibility |
| `storyStatus` | string | **Writable.** Values: `To Do`, `In Progress`, `Testing`, `Done` — use `storyStatus` (NOT `status`) in PATCH body |
| `numberOfTasks` | integer | Read-only |
| `epic` | object | Nested `{name, epicId}` — read-only in response |

---

### Statuses

| Method | Path | Description |
|--------|------|-------------|
| GET | `/statuses` | List configured story statuses for the app |

**Response:**
```json
{
  "statuses": [
    { "name": "Done", "sortId": 0 }
  ]
}
```

This endpoint is **read-only** — it lists the statuses that exist but you cannot set `status` via API.

---

### Labels

| Method | Path | Description |
|--------|------|-------------|
| GET | `/labels` | List all labels for the app |

---

### Tasks

| Method | Path | Description |
|--------|------|-------------|
| GET | `/stories/{storyId}/tasks` | Get tasks for a story |

---

## Key Limitations (Confirmed Against API Docs Jan 2026)

1. **Use `storyStatus`, not `status`.** The GET response field is called `status`, but the PATCH writable field is called `storyStatus`. Using `{"status":"Done"}` returns 400. Using `{"storyStatus":"Done"}` returns 204. Values: `To Do`, `In Progress`, `Testing`, `Done` — match exactly to your project's configured statuses (check GET /statuses).

2. **No sprint assignment via API.** `sprintId` is not a writable field. Sprint membership is managed in the portal.

3. **`storyLevel` is the only workflow-state field.** Use `Backlog` (not in active sprint) vs `Active` (in current sprint).

4. **PATCH returns 204 No Content** — empty body on success. Don't try to parse the response.

5. **POST /stories returns an items array** even for a single story:
   ```json
   { "items": [{ "code": 200, "story": { "uuid": "...", "storyId": "PROJ-8" } }] }
   ```
   A partial failure returns `207` with per-item codes and reasons.

6. **Readable epic ID as `epicId` in story create.** When assigning a story to an epic at creation time, use the readable ID (`PROJ-EP-001`) — not the UUID.

---

## Workflow (Linear-style)

**The intended WOW:**

```
BRDs / build plan          → source of truth for what needs building
Epics API / portal         → work tracker, sprint board
Business users             → add stories directly in the portal
Developer (VS Code/terminal) → picks up stories, activates them, builds
Portal                     → marks stories Done after review
```

**Daily dev loop:**
1. `list-stories` to see what's in backlog
2. `activate-story <id>` to pull a story into the active sprint
3. Do the work (MDL, code, etc.)
4. In the Mendix portal: drag story to Done column
5. Repeat

**Bulk create from BRD/build plan:**
- Write a small script that loops over story definitions and calls `create-story` for each
- Use `storyLevel: Backlog` for all new stories initially
- Assign to the right epic via `epicId` (readable format: `PROJ-EP-001`)

---

## URL Patterns

```
https://epics-api.mendix.com/v1/projects/{appId}/epics
https://epics-api.mendix.com/v1/projects/{appId}/epics/{epicUUID}
https://epics-api.mendix.com/v1/projects/{appId}/stories
https://epics-api.mendix.com/v1/projects/{appId}/stories/{storyId}
https://epics-api.mendix.com/v1/projects/{appId}/statuses
https://epics-api.mendix.com/v1/projects/{appId}/labels
https://epics-api.mendix.com/v1/projects/{appId}/stories/{storyId}/tasks
```

Note: `{storyId}` in URL paths uses the **readable ID** (e.g. `PROJ-8`), not the UUID.

---

## Debugging Tips

- **Silent `{"items":[]}` on create** → body is an object, not an array. Wrap in `[...]`.
- **400 on PATCH** → check field name. Writable: `title`, `description`, `storyPoints`, `storyType`, `storyLevel`, `storyStatus`. Note: GET response uses `status` but PATCH requires `storyStatus`.
- **405 on update** → wrong HTTP method. Stories use PATCH, not PUT.
- **401** → PAT expired or wrong scope. Needs `mx:epics:read` + `mx:epics:write`.
- **404 on story** → using UUID instead of readable ID (`PROJ-8`) in the URL path.
