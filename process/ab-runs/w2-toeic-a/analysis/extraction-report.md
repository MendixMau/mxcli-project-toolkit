# Extraction Report — TOEIC Buddy

**Source:** HTML/JS self-contained learning application with Markdown technical guide
**Method:** Manual code inspection (no automated extraction)
**Date:** 2026-09-09

## Summary

TOEIC Buddy is a single-file HTML/JS application with no backend services or structured data exports. No extraction pipeline is applicable. Domain model derived from direct source inspection.

## Extracted Entities

### Lesson Navigation & Storage
- **Lesson** (entity, ~20 instances hardcoded)
  - Attributes: lessonId, title, description, section, difficulty, questionCount, estimatedDuration, order
  - Storage: localStorage persistence
  - Status: Ready for BRD

- **LessonContent** (entity)
  - Attributes: contentId, lessonId, content (serialized lesson data)
  - Status: Ready for BRD

### Quiz Engine & Scoring
- **Question** (entity, ~200 instances hardcoded)
  - Attributes: questionId, lessonId, text, questionType, imageUrl, audioUrl, orderInLesson
  - Status: Ready for BRD

- **Answer** (entity, ~800 instances hardcoded)
  - Attributes: answerId, questionId, text, isCorrect, explanation, order
  - Status: Ready for BRD

- **UserAnswer** (entity)
  - Runtime entity, persisted to localStorage
  - Attributes: userAnswerId, sessionId, questionId, selectedAnswerId, isCorrect, timeSpent, timestamp
  - Status: Ready for BRD

- **QuizSession** (entity)
  - Attributes: sessionId, lessonId, startTime, endTime, totalScore, correctCount, totalQuestions, status
  - Status: Ready for BRD

### User Progress Tracking
- **UserProgress** (entity)
  - Attributes: userId, totalLessonsCompleted, totalQuestionsAnswered, overallAccuracy, totalTimeSpent, lastActivityTime, currentStreak
  - Status: Ready for BRD

- **LessonProgress** (entity)
  - Attributes: progressId, userId, lessonId, status, bestScore, attemptCount, lastAttemptDate, currentPosition
  - Status: Ready for BRD

- **PerformanceMetric** (entity)
  - Attributes: metricId, userId, metricType, categoryName, value, timestamp, trend
  - Status: Ready for BRD

- **Achievement** (entity)
  - Attributes: achievementId, userId, achievementType, title, unlockedDate
  - Status: Ready for BRD

## Use Cases Identified

### Lesson Navigation
- Load Lesson List
- Select and Load Lesson
- Persist Lesson State

### Quiz Engine
- Display Question
- Submit Answer
- Calculate Score
- Show Results

### Progress Tracking
- View Dashboard
- View Lesson Progress
- Update Progress After Quiz
- Track Learning Trend

## Data Persistence

All data persisted to **localStorage** — no backend services, no multi-device sync. Session-based or device-local user identity.

## Technical Observations

1. **Frontend-only architecture** — no backend API, no database integration
2. **Static lesson and question content** — all ~250 questions hardcoded in HTML/JS
3. **Client-side scoring** — instant validation, immediate feedback
4. **Single-page app** — no server-side routing or multi-page navigation
5. **No integrations** — fully self-contained learning experience

## Extraction Methodology

Since no structured data export exists, BRDs were derived from:
1. Direct inspection of HTML/JS source structure
2. Reading the Markdown technical guide
3. Analysis of business logic and data flow
4. Mapping to standard Mendix entity/attribute patterns

## Coverage Assessment

| Capability | Extractable? | BRD Status | Risk |
|---|---|---|---|
| Lesson Navigation | N/A — static content | **Ready** | Low — straightforward data model |
| Quiz Engine | N/A — procedural logic | **Ready** | Low — standard MC scoring pattern |
| User Progress | N/A — calculated metrics | **Ready** | Medium — streak/trend calculation rules |

**Overall Verdict:** Three manual BRDs, all Ready. No extraction blockers. No further spikes needed.

---

**Next Step:** Stage 2 — Validate BRDs against requirements, render HTML surfaces.
