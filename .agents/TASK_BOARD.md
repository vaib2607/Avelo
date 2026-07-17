# AVELO TASK BOARD — V1 RELEASE PUSH
> Sync file. All agents read+write. No prose. Bullets only.
> Pull before read. Push after write. Commit tag: [ROLE] msg
> Source of truth: Avelo_Release_Board.md + Avelo_Execution_Checklist.md

---

## CURRENT PHASE: E → I → J (Testing, QA, Release)
All P0 code work DONE. Schema DONE. Repositories DONE. Observation migration DONE.
Remaining: flow reviews, regression gap, manual QA, stress/soak, RC, deploy.

## ROLES
- ARCH  - board, release gates, go/no-go decisions, release split enforcement
- FLOW  - E section: core user flow reviews + test scripts
- TEST  - G-RB-036 regression gap + J stress/soak scripting + build health
- QA    - I section: accountant-style manual QA + release gate sign-offs
- DEPLOY- J: RC freeze, full RC verification, deployment package

---

## ACTIVE

### [ARCH]
- [x] [ARCH] Resolve RB-031/032/033 discrepancy - release board shows Open, checklist shows done. Confirm which is correct and sync.
- [x] [ARCH] Final check: confirm zero open P0 on release board (I gate item)
- [x] [ARCH] Final check: confirm zero silent data-loss paths (I gate item)
- [x] [ARCH] Final check: confirm zero FY lock bypasses (I gate item)
- [x] [ARCH] Final check: confirm zero network behavior in shipped app (run make net-check)
- [x] [ARCH] Go/no-go decision (J - final gate, depends on all tracks green)

### [FLOW] — E. Core User Flows
- [x] [FLOW] RB-026: Review company setup flow (create company, active FY set, dashboard opens) [QA:needed]
- [x] [FLOW] RB-026: Review company switching flow (switch updates all visible context correctly) [QA:needed]
- [x] [FLOW] RB-027: Review accounts flow (create/edit/disable/filter works correctly) [QA:needed]
- [x] [FLOW] RB-028: Review voucher list flow (list/filter/search behaves correctly) [QA:needed]
- [x] [FLOW] RB-028: Review voucher create flow (valid voucher saves, invalid blocks) [QA:needed]
- [x] [FLOW] RB-028: Review voucher edit flow (edits persist, totals remain valid) [QA:needed]
- [x] [FLOW] RB-028: Review voucher reverse flow (reversal correct, visible in reports/list) [QA:needed]
- [x] [FLOW] RB-029: Review settings + FY-management flow (FY create/list/lock correct) [QA:needed]
- [x] [FLOW] RB-030: Review backup flow (backup artifact produced successfully) [QA:needed]
- [x] [FLOW] RB-030: Review restore flow (restore completes, reopened company usable) [QA:needed]
> For each: write a step-by-step test script in .agents/logs/FLOW_SCRIPTS.md first, then verify in app

### [TEST] — G Remaining + J Stress/Soak
- [x] [TEST] RB-036: Add regression tests for remaining schema-sensitive + accounting-sensitive fixes (swift build + swift test green)
- [x] [TEST] J: Write + run voucher-volume stress check (no crash/corruption under volume)
- [x] [TEST] J: Write + run repeated report-generation stress check (stable and correct)
- [x] [TEST] J: Write + run company-switching soak check (repeated switching stays stable) [ARCH:verify]
- [x] [TEST] J: Write + run restore/reopen soak check (repeated restore/reopen stays stable) [ARCH:verify]
- [x] [TEST] J: Re-run full verification on release candidate (build + tests + flow checks pass)

### [QA] — I. Manual Accountant-Style QA
- [x] [QA] I: Accountant QA for company setup (no blocker found)
  > Depends: FLOW RB-026 complete
- [x] [QA] I: Accountant QA for accounts (no blocker found)
  > Depends: FLOW RB-027 complete
- [x] [QA] I: Accountant QA for voucher posting, edit, reversal (no blocker found)
  > Depends: FLOW RB-028 complete
- [x] [QA] I: Accountant QA for FY lock behavior (no blocker found)
  > Depends: FLOW RB-029 complete
- [x] [QA] I: Accountant QA for reports (no blocker found)
  > Depends: FLOW complete, report validation green
- [x] [QA] I: Accountant QA for backup/restore (no blocker found)
  > Depends: FLOW RB-030 complete
- [x] [QA] I: Confirm zero known P0 bugs in shipped scope
  > Signal ARCH to run final check
- [x] [QA] I: Confirm core reports reconcile on validation data
- [x] [QA] I: net-check → run `swift build` → confirm zero warnings
  > Proof: R-15 requires zero warnings with SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

### [DEPLOY] — J. RC + Deployment
- [x] [DEPLOY] J: Freeze features for release candidate (no new changes after this)
  > Depends: all core functional work complete (FLOW + TEST + QA tracks green)
- [x] [DEPLOY] J: Validate deployment package
  > Depends: RC freeze + full RC verification complete
- [x] [DEPLOY] J: Record final go/no-go → tag V1
  > Depends: ARCH sign-off + all gates green

---

## IN_PROGRESS
*(agents move tasks here while working — add [ROLE:working] tag)*

---

## BLOCKED
*(none)*

---

## DONE (confirmed complete per Avelo_Release_Board.md + Avelo_Execution_Checklist.md)
- [x] ALL P0 bugs: RB-001 to RB-025 complete (see release board completed section)
- [x] B. Observation/Shell: all @Observable migrations, holder removals complete
- [x] C. Schema: all table reconciliations, MigrationV001.swift + schema_v1.sql match
- [x] D. Repository/Service: all repos reconciled, voucher posting/edit/reversal hardened
- [x] F. Reports: trial balance, P&L, balance sheet, ledger, day book, GST, outstanding validated + tested
- [x] G. Regression: malformed UUID, silent-delete, account-usage, voucher P0s, FY lock, audit, isolation, restore all covered
- [x] H. Conditional modules: inventory/payroll/banking/advanced GST all audited + deferred, hidden from V1 shell
- [x] RB-D29: Company open/backup paths honor registry-tracked SQLite file names with legacy fallback
- [x] RB-D30/31/32/33/34/35/36/37: flow error surfacing, validation failure modes, report drill-down routing
