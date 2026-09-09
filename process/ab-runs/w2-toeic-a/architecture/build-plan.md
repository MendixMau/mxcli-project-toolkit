# Build Plan: TOEIC Buddy → Mendix

## Executive Summary
- **Total Modules:** 3 (LessonEngine, QuizEngine, ProgressTracking)
- **Total Entities:** 10
- **Estimated Build Effort:** 3–4 weeks (POC, familiar team)
- **Phase:** Incremental, validation after each module

---

## Build Phases

### Phase 1: Foundation (Week 1)
**Goal:** Establish data model and basic navigation

| Module | Tasks | Story Points |
|---|---|---|
| LessonEngine | Create Lesson + LessonContent entities; Seed 200 lessons; Build LessonList page | 8 |
| LessonEngine | Build LessonDetail page; Add navigation flow | 5 |

**Deliverable:** Users can browse and select lessons

---

### Phase 2: Quiz Core (Week 2)
**Goal:** Implement quiz delivery and scoring

| Module | Tasks | Story Points |
|---|---|---|
| QuizEngine | Create Question, Answer, QuizSession entities | 8 |
| QuizEngine | Seed 800+ questions with answers | 5 |
| QuizEngine | Build QuizView page (display Q + answers) | 8 |
| QuizEngine | Implement SubmitAnswer microflow; Validate correctness | 8 |
| QuizEngine | Build ResultsView page; Display score & breakdown | 5 |

**Deliverable:** Users can take quizzes and see results

---

### Phase 3: Progress & Polish (Week 3-4)
**Goal:** Track progress, calculate metrics, gamification

| Module | Tasks | Story Points |
|---|---|---|
| ProgressTracking | Create UserProgress, LessonProgress, PerformanceMetric entities | 8 |
| ProgressTracking | Build Dashboard page; Display overall stats | 8 |
| ProgressTracking | Implement progress update microflow (listen to quiz completion) | 8 |
| ProgressTracking | Implement achievement badge logic | 5 |
| ProgressTracking | Build AchievementsView page | 5 |
| ProgressTracking | Implement metric calculation (accuracy, streaks, trends) | 8 |

**Deliverable:** Full feature parity with original app

---

## Validation Gates

| After Phase | Gate | Condition |
|---|---|---|
| Phase 1 | "Lessons Load" | Lesson list renders; 5 random lessons clickable |
| Phase 2 | "Quiz Works" | User completes 1 quiz start-to-finish; score displays correctly |
| Phase 3 | "Progress Tracks" | User's 3 quiz attempts recorded; dashboard shows 3 x accuracy |

---

## Dependencies & Sequencing

```
LessonEngine (Phase 1)
  ↓ (QuizEngine reads Lesson)
QuizEngine (Phase 2)
  ↓ (ProgressTracking listens to quiz events)
ProgressTracking (Phase 3)
```

No parallelization possible; critical path is linear.

---

## Build Team & Ownership

- **BA/Domain:** Module briefs, entity specs, business rules
- **MDL Developer:** Entity creation, microflow logic, page building
- **QA/Tester:** Validation gate testing, regression checks

---

## Known Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Achievement badge calculation rules underspecified | High | Spike on original app behavior before Phase 3 |
| Performance with 800+ questions | Medium | Implement pagination / on-demand loading if slow |
| User session/login scope | Medium | Clarify login model (anon session vs. account) in Phase 1 |

---

## Acceptance Criteria

**Phase 1 Complete:** User can view all lessons grouped by section, select one, see lesson details
**Phase 2 Complete:** User can take a quiz, answer all questions, see final score and breakdown
**Phase 3 Complete:** User's progress is tracked across sessions; dashboard shows stats; badges unlock

**Build Signoff:** All three phases pass validation gates + QA regression suite

