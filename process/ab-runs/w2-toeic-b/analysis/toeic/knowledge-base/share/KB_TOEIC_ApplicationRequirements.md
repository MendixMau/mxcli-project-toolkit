# TOEIC Buddy Application Requirements

**Source:** `sources/TOEIC-BUDDY-GUIDE.md` + `sources/toeic-buddy.html`  
**Category:** A (Requirements — complete application specification)  
**Processed:** 2026-09-09  
**Method:** Source code + technical documentation synthesis  
**Application Version:** 1.2.0

---

## 1. Document Structure

This document consolidates two sources:
- **TOEIC-BUDDY-GUIDE.md:** Technical specification, architecture, workflows, performance requirements
- **toeic-buddy.html:** Complete working application source (HTML/CSS/JavaScript) — demonstrates actual UI and logic

The application is a single-page web application (SPA) with no backend persistence (Phase 1) targeting English language learners preparing for TOEIC certification exams.

---

## 2. Business Overview

**Purpose:** Enable English learners to self-study TOEIC test preparation through interactive lessons, vocabulary practice, and adaptive quizzes with progress tracking.

**Target Users:**
- English language learners seeking TOEIC certification (primary)
- Corporate employees preparing for proficiency assessments
- Students preparing for business English communication
- Non-native speakers in professional environments

**Scope:** Complete learning platform for Phase 1 (desktop web, in-session data). Future phases: persistent user accounts, audio playback, mobile apps.

**Out of Scope (Phase 1):**
- User authentication/accounts
- Data persistence across sessions
- Audio pronunciation features
- Mobile native applications
- Instructor/admin panel
- Analytics/reporting backend

---

## 3. Screens/Pages

### Screen 01 — Home / Dashboard

**Purpose:** Landing page with app overview, key statistics, and navigation to all learning modes

**UI Components:**
- Application header (title "TOEIC Buddy", tagline "Master TOEIC English - Your Personal Test Preparation Tool")
- Statistics grid (4 stat boxes):
  - Lessons available (15)
  - Vocabulary items (500+)
  - Practice questions (200+)
  - Quiz modules (8)
- Getting started guide (4-point ordered list)
- Call-to-action button ("Start Learning →")

**Data displayed:**
- Static stats (not user-dependent in Phase 1)
- Navigation tabs to 4 other sections

**Actions:**
- Click lesson/vocabulary/quiz buttons → navigate to respective sections
- Tab navigation (accessible from all screens)

---

### Screen 02 — Lessons

**Purpose:** Structured grammar and business English instruction with worked examples

**Content Structure:**
- Header: "TOEIC Lessons"
- Lesson sections (scrollable, repeating structure):
  - Lesson number + title (e.g., "Lesson 1: Present Perfect Tense")
  - Learning content (prose explanation)
  - Examples (bullet list with highlighted keywords)
  - Key vocabulary/phrases highlighted

**Lessons Included (15 total, 3 shown as samples):**
1. Present Perfect Tense — past-to-present actions, formula, examples
2. Business Communication — professional phrases (requests, offers, references)
3. Email Writing — business email structure (greeting, body, closing, signature)

**Data Model:**
| Attribute | Type | Sample Value |
|-----------|------|--------------|
| LessonNumber | Integer | 1 |
| Title | Text | "Present Perfect Tense" |
| Description | Long Text | "The present perfect tense describes actions that started in the past..." |
| Examples | List[String] | ["I have worked here for 5 years", "She has finished her project"] |
| KeyPhrases | List[String] | Optional; for business lessons |

**Actions:**
- Scrolling (read all lessons)
- Tab navigation (no lesson-specific actions)

---

### Screen 03 — Vocabulary Builder

**Purpose:** Flashcard-style vocabulary learning with context (definition + example sentence)

**Display Format:**
- Vocabulary cards in responsive grid (1 column mobile → 3+ desktop)
- Each card displays:
  - Word (bold, colored accent)
  - English meaning (plain text)
  - Example sentence (italicized)

**Vocabulary Data Model:**

| Attribute | Type | Sample Value |
|-----------|------|--------------|
| Word | Text(50) | "Accommodate" |
| PartOfSpeech | Text | "Verb" |
| Definition | Text(200) | "To provide lodging or sufficient space" |
| ExampleSentence | Text(300) | "The hotel can accommodate up to 500 guests." |
| DifficultyLevel | Enum | Intermediate, Advanced |

**Vocabulary Set (500+ items documented):**
Sample 6 shown in UI; full inventory in backend (implied):
1. Accommodate — verb — to provide lodging
2. Proficient — adjective — competent or skilled
3. Facilitate — verb — to make easier
4. Demonstrate — verb — to show or prove
5. Implement — verb — to put into effect
6. Comprehensive — adjective — complete and including all elements

**Future: Sorting/filtering by difficulty, category, or search.**

**Actions:**
- View card (static)
- Hover/click for flip animation (deferred — not in Phase 1)

---

### Screen 04 — Practice Quiz

**Purpose:** Interactive quiz with immediate scoring, progress bar, and results summary

**Quiz Flow:**
1. User clicks "Start Practice Quiz" button
2. Quiz section displays:
   - Progress bar (% complete based on Q#/Total)
   - Question counter ("Question N of 10")
   - Question text and 4 multiple-choice options
3. User selects an option (highlighted on click)
4. On final question, "Submit" button appears
5. User clicks "Submit"
6. Results screen shows: Score (correct/total), percentage, call-to-action ("Try Again")

**Quiz Data Model:**

| Attribute | Type | Sample Value |
|-----------|------|--------------|
| QuestionID | Integer | 1 |
| QuestionText | Text(500) | "What is the past participle of 'go'?" |
| OptionA | Text(200) | "gone" |
| OptionB | Text(200) | "went" |
| OptionC | Text(200) | "going" |
| OptionD | Text(200) | "goes" |
| CorrectOptionIndex | Integer (0-3) | 0 |
| Category | Enum | Grammar, Vocabulary, Listening, Reading, Mixed |
| DifficultyLevel | Enum | Easy, Medium, Hard |

**Sample Quiz (10 questions embedded in app):**
1. Past participle question (answer: "gone")
2. Present perfect grammar (answer: "He has worked here")
3. Email professional phrasing (answer: "formal and concise")
4. Vocabulary synonym (answer: "facilitate")
5. Present perfect use case (answer: "actions that started in past and continue now")

**Scoring Logic:**
- For each question: user.answer == correctAnswer ? points++ : 0
- Final score = (points / totalQuestions) * 100%
- Display: "N/10" and "M%"

**Quiz Categories (8 modules — future expansion):**
1. Grammar
2. Vocabulary
3. Listening (reading comprehension format in Phase 1)
4. Reading
5. Mixed questions
6. Timed practice
7. Full-length simulation
8. Weak area drills

**Actions:**
- Select option (visual highlight)
- Submit quiz (when all answered or on last question)
- View results
- Restart quiz

---

### Screen 05 — Progress Tracking Dashboard

**Purpose:** Display learner progress metrics, study streak, weak areas, and performance trends

**Metrics Displayed:**

| Metric | Data Type | Sample | Calculation |
|--------|-----------|--------|------------|
| Study Hours | Integer | 42 | Sum of all session durations |
| Questions Answered | Integer | 285 | Cumulative count per session |
| Average Score | Percentage | 76% | Sum(scores) / count(quizzes) |
| Current Streak | Integer | 15 | Days with ≥1 session; breaks on gap |

**Weak Areas Breakdown:**
- Listening Comprehension — 68%
- Idioms and Phrases — 71%
- Reading Comprehension — 78%
- Grammar — 82% ✓

**Weak Area Identification Rule:**
- Any category scoring <75% is flagged as weak
- Sorted by score ascending

**Business Rules for Progress:**
1. Study Hours increment: +1 hour per 60 minutes of active session time
2. Questions count: every quiz submission increments by number of questions in that quiz
3. Average score: running mean of all quiz attempts
4. Streak calculation:
   - Increments if session date = previous date + 1 day
   - Resets to 1 if date gap > 1 day
   - Preserved within same day (multiple sessions = 1 day credit)

**Data Model:**

| Attribute | Type | Sample |
|-----------|------|--------|
| UserID | GUID | (future: authenticated user) |
| StudyHours | Decimal | 42.5 |
| TotalQuestionsAnswered | Integer | 285 |
| AverageScorePercent | Decimal | 76.3 |
| CurrentDayStreak | Integer | 15 |
| LastSessionDate | Date | 2026-09-09 |
| PerformanceByCategory | Map[Category → Score%] | {"Grammar": 82, "Listening": 68} |

**Actions:**
- View stats (static — no edit)
- Review weak areas to identify study priorities
- (Future: click weak area to filter quiz questions)

---

## 4. Business Rules

1. **Quiz Answer Validation:**
   - Each question must have exactly 1 correct answer (0-3 index)
   - User may select only 1 option per question
   - Selection is recorded on click (no confirmation needed)
   - Rule violation: Silently ignore double-clicks (no double-scoring)

2. **Quiz Submission:**
   - Quiz may only be submitted after all questions answered
   - Submit button hidden until final question answered
   - Submission triggers scoring calculation immediately
   - No edit after submit (results final)

3. **Scoring Calculation:**
   - Score = (correct answers count ÷ total questions) × 100%
   - Displayed as both fraction (e.g., "5/10") and percentage (e.g., "50%")
   - No partial credit for partially-correct answers
   - Rule violation: Impossible given UI constraints

4. **Progress Metric Calculation (Phase 2 with persistence):**
   - Average score: mean of all completed quizzes (not per-question average)
   - Study streak: consecutive calendar days with ≥1 quiz attempt
   - Hours: derive from session duration (Phase 1: simulated as hardcoded "42 hours")
   - Weak areas: any category mean < 75% flagged for review

5. **Weak Area Identification:**
   - Threshold: 75% (scores ≥75% = strong, <75% = weak)
   - Scope: by quiz category if available; otherwise overall score
   - Trigger: after each quiz completion, recalculate overall average

6. **Data Persistence (Phase 1):**
   - No data persisted beyond current browser session
   - Page refresh → all progress lost
   - Phase 2 improvement: add browser localStorage or backend persistence

7. **Navigation Rules:**
   - Tab navigation available from any screen
   - Active tab highlighted visually (color change)
   - No forced flow (user can jump between sections in any order)
   - Back button navigates within browser history (no app control)

8. **Browser Compatibility:**
   - Support: Chrome 60+, Firefox 55+, Safari 11+, Edge 79+
   - Responsive: viewport scales for mobile (320px) → desktop (1200px+)
   - Layout: CSS Grid/Flexbox; cards auto-fit columns

9. **Content Versioning:**
   - Lessons: 15 total; only 3 shown (mockup — production has 15)
   - Vocabulary: 500+ total; only 6 shown (mockup — production has 500+)
   - Questions: 200+ total per specification; 10 in sample quiz (mockup)
   - All content hardcoded in Phase 1 (no dynamic loading)

---

## 5. User Roles and Permissions

**Phase 1: No role-based access control**

Single role: **Learner** (everyone has same permissions)

| Action | Learner | Instructor | Admin |
|--------|---------|-----------|-------|
| View lessons | ✓ | ✓ | ✓ |
| Take quiz | ✓ | ✓ | ✓ |
| View own progress | ✓ | ✓ | ✓ |
| View other progress | ✗ | ✓ | ✓ |
| Edit lessons | ✗ | ✗ | ✓ |
| Manage users | ✗ | ✗ | ✓ |

**Phase 2:** Add authentication + instructor/admin roles (deferred decision)

---

## 6. Integration Points

**External Integrations (Phase 1):** None

| System | Action | Stub-able |
|--------|--------|-----------|
| (None) | N/A | N/A |

**Phase 2 (Future):**
- Analytics backend (session tracking, performance reporting)
- User identity provider (authentication)
- Content management system (lesson/vocabulary updates)
- Audio CDN (pronunciation playback)

---

## 7. Entities and Data Model

### Entity 1: Lesson

| Attribute | Type | Length | Mandatory | Notes |
|-----------|------|--------|-----------|-------|
| LessonID | Integer | — | Yes | Auto-increment, primary key |
| LessonNumber | Integer | — | Yes | Display order (1-15) |
| Title | Text | 100 | Yes | "Present Perfect Tense" |
| Description | Long Text | 5000 | Yes | Full lesson content |
| Category | Text | 50 | Yes | "Grammar", "Business", etc. |
| DifficultyLevel | Enum | — | No | "Beginner", "Intermediate", "Advanced" |
| LastUpdated | DateTime | — | No | Version tracking |

### Entity 2: VocabularyItem

| Attribute | Type | Length | Mandatory | Notes |
|-----------|------|--------|-----------|-------|
| VocabID | Integer | — | Yes | Auto-increment, PK |
| Word | Text | 50 | Yes | English word |
| PartOfSpeech | Text | 20 | No | "Noun", "Verb", "Adjective" |
| Definition | Text | 200 | Yes | English meaning |
| ExampleSentence | Text | 300 | Yes | Context usage |
| DifficultyLevel | Enum | — | Yes | Beginner, Intermediate, Advanced |
| Category | Text | 50 | No | "Business", "Academic", "Daily" |
| MemoryAid | Text | 200 | No | Mnemonic or explanation |

### Entity 3: Question

| Attribute | Type | Length | Mandatory | Notes |
|-----------|------|--------|-----------|-------|
| QuestionID | Integer | — | Yes | Auto-increment, PK |
| QuestionText | Text | 500 | Yes | The question prompt |
| OptionA | Text | 200 | Yes | First choice |
| OptionB | Text | 200 | Yes | Second choice |
| OptionC | Text | 200 | Yes | Third choice |
| OptionD | Text | 200 | Yes | Fourth choice |
| CorrectOptionIndex | Integer | — | Yes | 0-3 (which is correct) |
| Explanation | Text | 300 | No | Why correct answer is right |
| Category | Enum | — | Yes | Grammar, Vocabulary, Listening, Reading, Mixed |
| DifficultyLevel | Enum | — | Yes | Easy, Medium, Hard |
| QuizModuleID | Integer | — | No | FK to quiz module (for organization) |

### Entity 4: UserProgress (Phase 2 — not in Phase 1)

| Attribute | Type | Length | Mandatory | Notes |
|-----------|------|--------|-----------|-------|
| ProgressID | GUID | — | Yes | Primary key |
| UserID | GUID | — | Yes | FK to User |
| StudyHours | Decimal | — | Yes | Default 0 |
| TotalQuestionsAnswered | Integer | — | Yes | Default 0 |
| AverageScore | Decimal | — | Yes | 0-100%, default 0 |
| CurrentStreak | Integer | — | Yes | Days, default 0 |
| LastActivityDate | DateTime | — | No | Latest quiz/lesson/vocab session |
| WeakAreasJSON | Long Text | 5000 | No | {"Grammar": 68, "Listening": 71} |
| SessionStartTime | DateTime | — | No | When user opened app |
| SessionEndTime | DateTime | — | No | When user closed app |

### Entity 5: QuizAttempt (Phase 2 — not in Phase 1)

| Attribute | Type | Length | Mandatory | Notes |
|-----------|------|--------|-----------|-------|
| AttemptID | GUID | — | Yes | PK |
| UserID | GUID | — | Yes | FK User |
| QuizModuleID | Integer | — | Yes | Which quiz taken |
| Score | Decimal | — | Yes | 0-100 |
| QuestionsCorrect | Integer | — | Yes | Count |
| TotalQuestions | Integer | — | Yes | Count |
| AttemptDate | DateTime | — | Yes | When taken |
| AnswersJSON | Long Text | — | No | [{"Q": 1, "Selected": 0, "Correct": true}] |

---

## 8. Workflows / Processes

### Workflow 1: Quiz Practice

**Actors:** Learner

**Steps:**
1. Learner clicks "Start Practice Quiz" button (Quiz screen)
2. App loads quiz module (hardcoded quizData array in Phase 1)
3. App displays Question 1, Progress bar shows 0% (0/10)
4. Learner reads question text and 4 options
5. Learner clicks an option → option highlights (visual feedback)
6. Learner may click another option → deselect previous, highlight new
7. Repeat 5-6 for questions 2-9
8. On Question 10: after selecting option, "Submit Quiz" button appears
9. Learner clicks "Submit Quiz"
10. App calculates score = correct answers / 10
11. App displays results: "N/10" and "M%" with "Try Again" button
12. Learner clicks "Try Again" → reset quiz, return to step 2

**State Changes:**
- currentQuestion: 0 → 10
- selectedAnswers: [] → [index, index, ...]
- isQuizActive: false → true → false
- quizScore: null → { correct: 5, total: 10, percent: 50 }

**Data Validation:**
- Cannot submit without answering Q10
- Cannot change answer after submit
- Cannot retake during active attempt (new attempt = reset + restart)

---

### Workflow 2: View Lesson

**Actors:** Learner

**Steps:**
1. Learner clicks "Lessons" tab
2. App displays Lessons section (static content, scroll)
3. Learner scrolls through lesson list
4. Learner reads lesson content (text + examples)
5. Learner navigates away (tab click or page refresh)

**State Changes:** None (read-only workflow)

---

### Workflow 3: Study Vocabulary

**Actors:** Learner

**Steps:**
1. Learner clicks "Vocabulary" tab
2. App displays grid of vocabulary cards
3. Learner views card: word, definition, example (responsive layout)
4. Learner scrolls to view more cards
5. Learner navigates away

**State Changes:** None (read-only in Phase 1; future: track "learned" status)

---

### Workflow 4: Check Progress

**Actors:** Learner

**Steps:**
1. Learner clicks "My Progress" tab
2. App displays 4 metric boxes (hours, questions, score %, streak)
3. App lists weak areas (<75%) sorted by score ascending
4. Learner reviews metrics
5. (Future: click weak area to filter quiz questions by category)
6. Learner navigates away

**State Changes:** None (derived from quiz history; future recalc on quiz submit)

---

## 9. Performance & Non-Functional Requirements

| Requirement | Value | Notes |
|-------------|-------|-------|
| Page Load Time | < 3 seconds | Total HTML/CSS/JS in one file (~100KB) |
| Question Display | < 100ms | Instant (no server calls) |
| Quiz Submit Response | < 500ms | Client-side calculation only |
| Supported Browsers | Chrome 60+, Firefox 55+, Safari 11+, Edge 79+ | Evergreen + 2-3 year support |
| Mobile Support | 320px+ (responsive CSS Grid) | No native apps in Phase 1 |
| Data Volumes | 200 questions, 500 vocab items, 15 lessons | All in-memory |
| User Capacity | Single user (in-session); no concurrency | No backend connection |
| Availability | 99.9% (static files) | No runtime dependencies |
| Security | No authentication, no PII | Safe to host publicly |
| Accessibility | Basic (WCAG 2.1 AA target for Phase 2) | Color contrast, tab navigation, semantic HTML |

---

## 10. Open Questions / Decisions

| # | Question | Status | Impact |
|---|----------|--------|--------|
| D1 | Should progress data persist across browser sessions (localStorage vs. backend)? | **Deferred** — Phase 2 decision. Phase 1: session-only. | Medium — UX improvement needed; users lose progress on refresh |
| D2 | How many vocabulary items and questions should Phase 1 ship with? | **Resolved:** Minimum viable: 15 lessons, 100 vocabulary items, 50 questions. Mockup shows samples. | Low — content volume configurable |
| D3 | Should weak areas trigger adaptive quiz filtering (only show hard topics)? | **Deferred** — Phase 2 feature. Phase 1: static feedback only. | Medium — improves learning efficiency |
| D4 | How to handle audio pronunciation (TOEIC listening section)? | **Deferred** — Phase 2. Phase 1: text-only, audio noted as limitation. | High — impacts credibility for listening prep |
| D5 | What authentication model for multi-user deployment (Phase 2)? | **Open** — Options: OAuth, LDAP, local user database. Deferred. | High — affects architecture |

---

## 11. Success Criteria (Phase 1 MVP)

- ✓ All 5 screens functional and responsive
- ✓ Quiz scoring algorithm correct (100% accuracy on samples)
- ✓ Progress tracking metrics calculated correctly
- ✓ Load time < 3 seconds on target browsers
- ✓ No external API calls (standalone app)
- ✓ Content at least as comprehensive as mockup (15 lessons, 100+ vocab, 50+ questions)

---

## Appendix A: Color Palette

| Element | Color | Hex | Usage |
|---------|-------|-----|-------|
| Primary | Purple | #667eea | Buttons, headings, accents |
| Secondary | Dark Purple | #764ba2 | Hover states, gradient |
| Background Gradient | Purple → Dark Purple | — | Page background |
| Card Background | White | #FFFFFF | Content containers |
| Card Alt Background | Light Gray | #f8f9fa | Secondary containers |
| Text Primary | Dark Gray | #333333 | Body text |
| Text Secondary | Medium Gray | #666666 | Labels, hints |
| Border | Light Gray | #dddddd | Card borders |
| Success | Green | #4caf50 | Correct answers |
| Error | Red | #f44336 | Incorrect answers |

---

## Appendix B: Typography

| Element | Font | Size | Weight |
|---------|------|------|--------|
| Body | Segoe UI, Tahoma, Geneva, Verdana, sans-serif | 14px | 400 |
| Heading 1 | Same | 28px | 600 |
| Heading 2 | Same | 20px | 600 |
| Heading 3 | Same | 16px | 600 |
| Label | Same | 12px | 400 |
| Code/Mono | Monospace | 12px | 400 |

---

## Appendix C: Responsive Breakpoints

| Breakpoint | Min Width | Max Width | Columns |
|------------|-----------|-----------|---------|
| Mobile | 320px | 767px | 1 |
| Tablet | 768px | 1023px | 2 |
| Desktop | 1024px | 1200px | 3-4 |
| Wide | 1200px+ | — | 4+ |

---

**Document Complete**
