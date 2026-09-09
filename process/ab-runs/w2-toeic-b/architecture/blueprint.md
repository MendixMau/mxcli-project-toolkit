# Architecture Blueprint — TOEIC Buddy

## Technology Stack

| Layer | Technology |
|-------|-----------|
| UI | Mendix Pages (responsive) |
| Business Logic | Mendix Microflows |
| Data | Mendix Entities (in-memory Phase 1, DB Phase 2) |
| Integration | None (Phase 1) |

## Component Diagram

```
┌─────────────────────────────────────┐
│       TOEIC Buddy SPA               │
├──────────┬──────────┬───────────────┤
│ Home     │ Lessons  │ Vocabulary    │
│ Quiz     │Progress  │               │
├──────────────────────────────────────┤
│     Mendix Application Logic         │
├──────────────────────────────────────┤
│ Entities: Lesson, Vocab, Question... │
│ Microflows: Quiz Logic, Navigation   │
└──────────────────────────────────────┘
```

## Data Flow

1. User navigates tabs → AppShell switches context
2. User starts quiz → LoadQuestion microflow displays Q1
3. User selects answer → SelectOption records choice
4. User submits → SubmitQuiz calculates score
5. Results displayed → UpdateProgress (Phase 2 persistence)

## Non-Functional Requirements Met

- Performance: <3s load time (single module, local data)
- Browser support: Chrome 60+, Firefox 55+, Safari 11+, Edge 79+
- Scalability: Phase 1 single-user; Phase 2 adds backend
- Security: No auth Phase 1; public access safe for learning app
