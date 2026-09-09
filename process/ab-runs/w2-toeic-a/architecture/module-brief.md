# Module Brief Template

## Module: LessonEngine

**Owner:** MDL Developer (Phase 1)
**Status:** To Start
**Estimated Effort:** 13 SP (1-2 weeks)

### Entities
1. **Lesson** (2 attributes: lessonId, title, section, difficulty, questionCount)
2. **LessonContent** (2 attributes: contentId, lessonId, content)

### Pages
1. **LessonList** - Grid of lessons by section; click to select
2. **LessonDetail** - Show lesson metadata; button to start quiz

### Microflows
- GetLesson(lessonId) → Lesson
- ListLessons() → Lesson[]
- UpdateProgress(lessonId, status)

### Business Rules
- Lessons are read-only (seed data)
- 200 hardcoded lessons; no CRUD

### Validation Gate
- User can click any lesson and see its detail page
- Next module (QuizEngine) can retrieve Lesson records by ID

---

## Module: QuizEngine

**Owner:** MDL Developer (Phase 2)
**Status:** Blocked by LessonEngine
**Estimated Effort:** 34 SP (2-3 weeks)

### Entities
1. **Question** (text, questionType, imageUrl, audioUrl, orderInLesson)
2. **Answer** (text, isCorrect, explanation, order)
3. **UserAnswer** (selectedAnswerId, isCorrect, timeSpent, timestamp)
4. **QuizSession** (lessonId, startTime, totalScore, status)

### Pages
1. **QuizView** - Display current question + answers; progress bar
2. **ResultsView** - Display score, correct count, question-by-question breakdown

### Microflows
- StartQuiz(lessonId) → QuizSession
- SubmitAnswer(sessionId, questionId, selectedAnswerId) → Boolean (correct?)
- CalculateScore(sessionId) → Integer (0-100)
- CompleteQuiz(sessionId) → void (trigger progress update event)

### Business Rules
- Score = (Correct Answers / Total Questions) × 100
- Pass threshold: ≥70% (configurable per lesson)
- Answers validated immediately on submission
- No answer changes allowed after submission

### Validation Gate
- User completes 1 full quiz (5-10 questions)
- Score calculated correctly
- Results page shows correct breakdown

---

## Module: ProgressTracking

**Owner:** MDL Developer (Phase 3)
**Status:** Blocked by QuizEngine
**Estimated Effort:** 34 SP (2-3 weeks)

### Entities
1. **UserProgress** (totalLessonsCompleted, totalQuestionsAnswered, overallAccuracy, currentStreak, lastActivityTime)
2. **LessonProgress** (lessonId, status, bestScore, attemptCount, currentPosition)
3. **PerformanceMetric** (metricType, categoryName, value, trend)
4. **Achievement** (achievementType, title, unlockedDate)

### Pages
1. **Dashboard** - Overall stats; section-level accuracy; achievements
2. **ProgressDetail** - Detailed metrics for one lesson
3. **AchievementsView** - List of unlocked badges

### Microflows
- UpdateUserProgress(quizSessionCompleted) → void
- CalculateMetrics(userId) → PerformanceMetric[]
- UnlockAchievement(userId, achievementType) → void
- CalculateStreak(userId) → Integer

### Business Rules
- Accuracy = (Total Correct / Total Attempted) × 100
- Streak resets if no activity for >1 day
- Achievements unlocked on thresholds:
  - "Lesson Master": 10 lessons completed
  - "5-Day Streak": 5 consecutive days active
  - "High Accuracy": 80%+ on 5 consecutive lessons

### Validation Gate
- User completes 3+ quizzes across different lessons
- Dashboard accurately displays aggregated stats
- Streak calculation is correct (tested manually)

