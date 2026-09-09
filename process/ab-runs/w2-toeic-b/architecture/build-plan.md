# Build Plan — TOEIC Buddy Phase 1

**Target:** MVP feature parity with original HTML/JS app  
**Phases:** Phase 1 (Mendix port), Phase 2 (persistence/auth), Phase 3+ (enhancement)  
**Timeline:** Phase 1 = 80-100 hours estimated

---

## Phase 1: Mendix Port (MVP)

### Slice 1: Foundation (Weeks 1-2, ~30 hours)

1. **Create Module TOEICBuddy**
   - Entity: AppShell (navigation state)
   - Create 5 pages (Home, Lessons, Vocabulary, Quiz, Progress)
   - Tab navigation between pages

2. **Home Dashboard**
   - Static statistics display (hardcoded: 15, 500+, 200+, 8)
   - "Start Learning" button → navigate to Lessons

**Gate:** All 5 pages render, navigation works

---

### Slice 2: Content Pages (Weeks 2-3, ~20 hours)

3. **Lessons Page**
   - Entity: Lesson (lessonNumber, title, description, category)
   - Seed data: 15 lessons (copy from KB)
   - List view: scrollable lesson display

4. **Vocabulary Page**
   - Entity: VocabularyItem (word, definition, example, difficulty)
   - Seed data: 100-500 vocabulary items
   - Responsive grid view (1 col mobile → 3+ desktop)

**Gate:** Content renders, layout responsive

---

### Slice 3: Quiz Engine (Weeks 3-4, ~20 hours)

5. **Quiz Core**
   - Entity: Question (questionText, optionA/B/C/D, correctIndex, category)
   - Seed data: 50-200 questions (from KB)
   - Microflow: StartQuiz → LoadQuestion → loop

6. **Quiz UI**
   - Progress bar: question N of 10
   - Question display + 4 radio button options
   - Submit button (hidden until Q10 answered)
   - Results screen: score display + retry button

7. **Scoring Microflow**
   - SubmitQuiz: calculate correct answers / total × 100%
   - Display results immediately

**Gate:** Quiz completes, score calculated correctly

---

### Slice 4: Progress Tracking (Week 4, ~10 hours)

8. **Progress Page**
   - Entity: UserProgress (studyHours, questionsAnswered, averageScore, streak)
   - Display 4 metrics (hardcoded Phase 1 values)
   - List weak areas (<75% score)
   - Read-only (no persistence Phase 1)

**Gate:** Metrics display, weak area logic correct

---

## Estimated Effort by Module

| Module | Pages | Entities | Microflows | Hours |
|--------|-------|----------|-----------|-------|
| App Shell | 1 | 1 | 1 | 10 |
| Home | 1 | 1 | 0 | 5 |
| Lessons | 1 | 1 | 2 | 8 |
| Vocabulary | 1 | 1 | 2 | 8 |
| Quiz | 3 | 2 | 5 | 35 |
| Progress | 1 | 1 | 2 | 8 |
| **Total** | **8** | **7** | **12** | **74** |

Add ~10-15% buffer for testing, refinement, deployment = **85-90 hours**

---

## Phase 2: Persistence & Auth (Future)

- Add User entity + authentication
- Add database persistence for UserProgress & QuizAttempt
- Implement progress recalculation on quiz submit
- Session tracking + streak logic

---

## Phase 3+: Enhancement

- Audio playback for pronunciation
- Adaptive quiz filtering by weak area
- Instructor panel
- Analytics dashboard
- Mobile app

---

## Build Order Rationale

1. **Foundation first:** Navigation must work before any content loads
2. **Content next:** Users need material to review before testing
3. **Quiz engine critical:** Core value proposition (active practice)
4. **Progress tracking last:** Nice-to-have for MVP (nice-to-have in Phase 1)

This order allows each slice to be independently testable.

---

## Dependency Graph

```
Foundation (App Shell, Pages)
   ↓
Content (Lessons, Vocabulary)
   ↓
Quiz Engine (Questions, Scoring)
   ↓
Progress Tracking (User Progress Display)
```

No circular dependencies. Linear progression.

---

## Phase 1 Success Criteria

- ✅ All 5 pages load and navigate correctly
- ✅ Quiz scoring 100% accurate on 10 test questions
- ✅ Vocabulary grid responsive (tested on mobile, tablet, desktop)
- ✅ Progress metrics calculated correctly
- ✅ Load time <3 seconds
- ✅ All content seeds load without error
- ✅ No external API calls

