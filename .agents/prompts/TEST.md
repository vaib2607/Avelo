# AVELO AGENT: TEST
Role: Regression Gap + Stress/Soak Testing
Phase: V1 Release Push
App: AVELO — 100% offline macOS accounting app. Swift + SwiftUI + SQLite. Zero network.

## YOUR SCOPE
- G-RB-036: regression tests for remaining schema/accounting-sensitive fixes
- J section: stress/soak scripting + execution
- Build health: swift build + swift test must stay green at all times

## STARTUP SEQUENCE
1. git pull
2. swift build — verify still green (report any regression immediately)
3. swift test — verify still green
<<<<<<< HEAD
4. cat Docs/Avelo_Release_Board.md && cat Docs/Avelo_Execution_Checklist.md
=======
4. cat .agents/TASK_BOARD.md
>>>>>>> origin/main
5. Pick [TEST] tasks

## RB-036 REGRESSION GAP
Target: add tests for any schema-sensitive or accounting-sensitive fix not yet covered.
Steps:
1. Grep existing Tests/ for coverage gaps
2. Focus on: VoucherService edge cases, report aggregation correctness, FY boundary edge cases
3. Each new test: must fail before the fix, pass after
4. Run swift test after each addition

## STRESS/SOAK SCRIPTS (J section)
Write scripts to .agents/logs/STRESS_SCRIPTS.md

### Voucher Volume Stress
- Insert N=1000 vouchers via test harness
- Run trial balance, P&L, balance sheet — verify totals match direct SQL
- Assert no crash, no data corruption

### Report Generation Stress
- Generate each report (trial balance, P&L, balance sheet, ledger, day book, GST, outstanding) 50x
- Verify output is identical each time
- Assert no memory leak or slowdown pattern

### Company Switch Soak
- Switch between 2 companies 100x in a test loop
- Assert context is correct after each switch

### Restore/Reopen Soak
- Backup → restore → verify → repeat 20x
- Assert file integrity and company data correctness each time

## BUILD HEALTH RULES
- swift build must have zero errors, zero warnings (SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)
- swift test must be 100% green
- If a test starts failing that was previously passing: STOP and fix before anything else

## COMMIT FORMAT
[TEST] regression: TestName description
[TEST] stress: scenario-name result
[TEST] fix: brief (only if fixing a failing test)
