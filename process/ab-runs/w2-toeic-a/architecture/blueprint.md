# Architecture Blueprint: TOEIC Buddy → Mendix

## 1. Module Definitions

### Module: LessonEngine
**Purpose:** Lesson catalog, storage, and navigation
**Owner:** BA - lessons data model
**Dependencies:** None

### Module: QuizEngine  
**Purpose:** Quiz delivery, answer validation, scoring
**Owner:** BA - quiz domain logic
**Dependencies:** LessonEngine (reads lessons)

### Module: ProgressTracking
**Purpose:** User progress metrics, achievements, dashboards
**Owner:** BA - user state
**Dependencies:** QuizEngine (listens for quiz completion)

---

## 2. Technology Stack

| Component | Technology | Notes |
|---|---|---|
| Frontend | Mendix Modern Client | SPA, single-page navigation |
| Backend | Mendix Microflows | Business logic, scoring rules |
| Storage | Mendix Database | Replace localStorage |
| UI | Mendix Pages & Snippets | Render original wireframes |

---

## 3. Fit-Gap Analysis

| Original Feature | Mendix Support | Gap? | Approach |
|---|---|---|---|
| Question images/audio | Mendix image/media widgets | No gap | Native support |
| localStorage persistence | Mendix database + sessions | No gap | Replace with committed data |
| Client-side scoring | Mendix microflows | No gap | Deterministic server-side logic |
| Progress calculations | Mendix aggregates | No gap | Native queries |
| Achievement badges | Mendix pages + styling | No gap | Custom page elements |

**Verdict:** No material gaps. Direct port feasible.

---

## 4. Integration Points

- None (self-contained app)

---

## 5. Security Model

| Entity | Security | Rules |
|---|---|---|
| Question | Public | Read-only, hardcoded content |
| Answer | Public | Validation rules (no data exposure) |
| UserAnswer | User | Create/read own answers only |
| UserProgress | User | Read/create own progress only |
| Achievement | User | Read own only |

**Verdict:** Single-tenant, session-based identity. No role-based access needed for POC.

---

## 6. Scalability & NFRs

| Requirement | Target | Approach |
|---|---|---|
| Concurrent users | 100+ | Mendix horizontal scaling, pool session db |
| Questions per lesson | 50-100 | Indexed queries, pagination if needed |
| Lessons per app | 200+ | Enumeration or lookup entity, no performance concern |
| Data retention | Permanent | Backup strategy per Mendix ops |

**Verdict:** No special NFR concerns for a learning app at this scale.

