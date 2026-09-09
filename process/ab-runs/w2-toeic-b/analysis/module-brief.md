# Module Brief — TOEICBuddy

**Scope:** Single Mendix module (monolithic architecture Phase 1)  
**Owner:** Development team  
**Build Status:** Not started  

---

## What's In

- 7 entities (AppShell, Lesson, VocabularyItem, Question, UserProgress, QuizAttempt, [Placeholder])
- 8 pages (Home, Lessons, Vocabulary, Quiz—question, Quiz—results, Progress, Navigation, Placeholder)
- 12 microflows (StartQuiz, LoadQuestion, SelectOption, SubmitQuiz, ResetQuiz, UpdateProgress, etc.)
- 50-500 content items (questions, vocabulary) to seed
- Responsive UI (1-4 columns depending on viewport)

---

## What's Out (Phase 2)

- User authentication
- Data persistence (backend database)
- Audio playback
- Analytics
- Multi-module decomposition

---

## Quality Gates

- Code compiles without error
- Unit tests for quiz scoring microflow
- Responsive design passes on 3 viewport sizes
- All required fields present on entities
- No circular dependencies between microflows

