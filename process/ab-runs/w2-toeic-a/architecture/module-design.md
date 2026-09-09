# Module Design: TOEIC Buddy Mendix

## Modules & Responsibilities

### 1. LessonEngine
- **Files:** Lesson, LessonContent entities
- **Responsibilities:**
  - Lesson catalog (CRUD)
  - Lesson content storage
  - Retrieval for quiz delivery
- **Pages:** LessonList, LessonDetail
- **Microflows:** GetLesson, ListLessons, UpdateProgress

### 2. QuizEngine
- **Files:** Question, Answer, UserAnswer, QuizSession entities
- **Responsibilities:**
  - Question retrieval and delivery
  - Answer validation
  - Score calculation (algorithm: correct/total × 100)
  - Session management
- **Pages:** QuizView, ResultsView
- **Microflows:** StartQuiz, SubmitAnswer, CalculateScore, CompleteQuiz

### 3. ProgressTracking
- **Files:** UserProgress, LessonProgress, PerformanceMetric, Achievement entities
- **Responsibilities:**
  - Progress tracking across lessons
  - Metric aggregation (accuracy, streaks, trends)
  - Achievement badge logic
  - Dashboard rendering
- **Pages:** Dashboard, ProgressDetail, AchievementsView
- **Microflows:** UpdateUserProgress, CalculateMetrics, UnlockAchievement

---

## Entity Placement

| Entity | Module | Type | Notes |
|---|---|---|---|
| Lesson | LessonEngine | System | Immutable; seed data |
| LessonContent | LessonEngine | System | Immutable; reference data |
| Question | QuizEngine | System | Immutable; reference data |
| Answer | QuizEngine | System | Immutable; reference data |
| UserAnswer | QuizEngine | User | User-created per quiz attempt |
| QuizSession | QuizEngine | User | User-created per quiz attempt |
| UserProgress | ProgressTracking | User | User-created; aggregated |
| LessonProgress | ProgressTracking | User | User-created per lesson |
| PerformanceMetric | ProgressTracking | User | Calculated; aggregated |
| Achievement | ProgressTracking | User | User-created on unlock |

---

## Module Dependencies

```
LessonEngine
  ↓ (provides Lesson)
QuizEngine
  ↓ (triggers progress updates)
ProgressTracking
  ↑ (listens to quiz completion)
```

No cyclic dependencies. Unidirectional flow.

