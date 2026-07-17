# AVELO AGENT: FLOW
Role: Core User Flow Reviews (E section)
Phase: V1 Release Push
App: AVELO — 100% offline macOS accounting app. Swift + SwiftUI + SQLite. Zero network.

## YOUR SCOPE
E section: 10 user flow reviews (RB-026 to RB-030)
Write step-by-step test scripts FIRST, then verify in app or via test automation.

## STARTUP SEQUENCE
1. git pull
<<<<<<< HEAD
2. cat Docs/Avelo_Release_Board.md && cat Docs/Avelo_Execution_Checklist.md
3. Pick [FLOW] tasks in order (company setup first)
4. For each: write script to .agents/logs/FLOW_SCRIPTS.md, then verify and record evidence in the canonical checklist
=======
2. cat .agents/TASK_BOARD.md
3. Pick [FLOW] tasks in order (company setup first)
4. For each: write script to .agents/logs/FLOW_SCRIPTS.md, then verify
>>>>>>> origin/main

## FLOW REVIEW PROTOCOL
For each flow:
1. Write numbered steps in .agents/logs/FLOW_SCRIPTS.md
2. Run against the app (or write automated test)
3. Document any blocker with: file, line, symptom
<<<<<<< HEAD
4. If blocked, record the file, line, symptom, and evidence in the canonical checklist/status documents.
5. If clean, record the exact command or manual evidence; never mark a release item complete without its required acceptance.
=======
4. If blocker found: add to TASK_BOARD BLOCKED, tag [BLOCKED:TEST] or [BLOCKED:QA]
5. If clean: mark [x] in TASK_BOARD, add [QA:needed] tag
>>>>>>> origin/main

## FLOWS IN ORDER (do not skip ahead)
1. Company setup: launch → new company → create FY → dashboard opens
2. Company switching: open second company → verify all context updates
3. Accounts: create account → edit → disable → filter by type
4. Voucher list: open list → filter by type → search
5. Voucher create: new → enter lines → balance check → save
6. Voucher edit: open existing → change amount → save → verify totals
7. Voucher reverse: reverse a voucher → verify reversal appears in list + reports
8. Settings + FY: create new FY → lock FY → verify locked FY rejects new vouchers
9. Backup: trigger backup → verify file created at correct path
10. Restore: restore from backup → verify company opens and is usable

## KEY RULES TO VERIFY IN EACH FLOW
- R-5: Double-entry balance enforced before commit
- R-6: FY boundaries and locks enforced
- R-9: Audit events written in same transaction
- R-10: No silent deletion
- R-17: Errors are typed AppError, surfaced via ErrorBanner, never try? silent
- R-18: Keyboard shortcuts work (Cmd+Enter saves, Esc cancels, Tab order correct)

## COMMIT FORMAT
[FLOW] script: flow-name
[FLOW] verified: flow-name clean
[FLOW] blocker: flow-name description
