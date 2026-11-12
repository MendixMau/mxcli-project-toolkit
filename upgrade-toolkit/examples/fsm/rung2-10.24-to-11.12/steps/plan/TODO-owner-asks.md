# Rung 2 owner asks (2026-11-11)
- Replace Atlas_Core.FeedbackWidget / SprintrFeedbackWidget in layouts Atlas_Default and Atlas_TopBar with the Mendix Feedback module (Marketplace), one commit via appcommit.sh; close release row 235 with that commit.
- Native app test (route pending feasibility).
- 16:40 decision: the feedback swap runs AFTER the rung 2 gate, as its own appcommit.sh commit with an impacted-only check (layout renders, button opens the feedback form), so it does not touch every screenshot pair of the upgrade comparison. Package: Mendix Feedback Module 205506 5.0.0 (min Mendix 10.24.0), downloaded to the session scratchpad feedback-mpk/.
