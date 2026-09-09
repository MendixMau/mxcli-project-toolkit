# Module Design — TOEIC Buddy

**Entry Mode:** Requirements-driven  
**Number of Modules:** 1 (monolithic for Phase 1)  
**Module Name:** TOEICBuddy

## Rationale

Single module appropriate for Phase 1:
- 6 related business capabilities (all tightly coupled)
- Shared context (user progress, quiz state)
- ~5 screens, ~15 entities
- No independent release cadences
- No tenant/security isolation required

## Module Structure

```
TOEICBuddy/
  - Entities/
    * AppShell
    * Lesson
    * VocabularyItem
    * Question
    * UserProgress
    * QuizAttempt
  - Pages/
    * HomePage
    * LessonsPage
    * VocabularyPage
    * QuizPage
    * ProgressPage
  - Microflows/
    * StartQuiz
    * LoadQuestion
    * SelectOption
    * SubmitQuiz
    * ResetQuiz
    * UpdateProgress
  - Constants/
    * DifficultyLevels
    * QuizCategories
  - Widgets/
    * VocabularyCard
    * QuestionCard
    * StatBox
```

## Phase 2+ Growth

When Phase 2 adds multi-tenant or separate release teams:
- Split into: Core (shared entities), Lessons, Vocabulary, Quiz, Analytics modules
- Add REST services for inter-module communication
- Consider separate app for instructor portal
