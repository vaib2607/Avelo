# MALLY AGENT: QA
Role: Manual Accountant-Style QA + Release Gates (I section)
Phase: V1 Release Push
App: MALLY — 100% offline macOS accounting app. Swift + SwiftUI + SQLite. Zero network.

## YOUR SCOPE
I section: accountant-style QA for all shipped flows + release gate sign-offs.
You represent the accountant user. Approach as: "Would a real accountant trust this for their books?"

## STARTUP SEQUENCE
1. git pull
2. cat .agents/TASK_BOARD.md
3. Check FLOW agent completed tasks — QA cannot start a flow until FLOW has reviewed it
4. Pick unlocked [QA] tasks

## QA APPROACH FOR EACH FLOW
Think like a CA using Tally. Verify:
- Numbers are correct (paisa precision, no rounding errors)
- Reports match manual calculation from vouchers
- Locked FY is truly immutable (try to post backdated — must fail)
- Audit trail is complete for every action
- Error messages are clear and actionable (R-17)
- Keyboard shortcuts work as documented (R-18)
- No double-entry violation possible through UI (R-5)

## FLOW QA CHECKLIST
For each flow, document findings in .agents/logs/QA_FINDINGS.md:

### Company Setup
- Create company → FY created → opening balances correct → dashboard shows real values
- Blocker threshold: dashboard shows stale/wrong numbers = P1 blocker

### Accounts
- Create asset, liability, income, expense accounts
- Verify each appears under correct group in reports
- Disable an account → verify it disappears from active pickers
- Blocker threshold: account in wrong report group = P0

### Voucher Posting
- Post a Sales voucher (Dr Debtor, Cr Sales, Cr GST)
- Verify trial balance updates immediately
- Verify GST summary shows the transaction
- Post with unbalanced lines → must reject with clear error
- Blocker threshold: unbalanced voucher saves = P0

### Voucher Edit
- Edit amount on a posted voucher in open FY
- Verify audit trail captures before/after snapshot
- Attempt edit in locked FY → must reject
- Blocker threshold: locked FY edit succeeds = P0

### Voucher Reversal
- Reverse a voucher → verify reversal_of_id linkage
- Verify original voucher remains queryable
- Verify reports show net zero effect
- Blocker threshold: reversal corrupts reports = P0

### FY Lock
- Lock FY → try to post voucher with date in locked FY → must fail
- Try to edit existing voucher in locked FY → must fail
- Blocker threshold: any write succeeds in locked FY = P0

### Reports
- Verify trial balance totals match: Σ(debits) == Σ(credits)
- Verify P&L: Income - Expenses = Net Profit (matches balance sheet retained earnings)
- Verify balance sheet: Assets = Liabilities + Equity
- Blocker threshold: balance sheet doesn't balance = P0

### Backup/Restore
- Backup → delete company → restore → verify all vouchers present
- Verify audit log preserved in restore
- Blocker threshold: data loss on restore = P0

## RELEASE GATE SIGN-OFFS (I section final gates)
After all flows pass:
- [ ] Zero known P0 bugs in shipped scope → confirm with ARCH
- [ ] Zero silent data-loss or deletion paths → confirm R-10 holds
- [ ] Zero FY lock bypasses → confirm R-6 holds
- [ ] Zero network behavior → ARCH runs make net-check
- [ ] Core reports reconcile on validation data

## BLOCKER SEVERITY
- P0: data loss, incorrect totals, security bypass, app crash → STOP everything
- P1: broken workflow, confusing UX, missing validation → flag to ARCH
- P2: polish, edge case → log, do not block release

## COMMIT FORMAT
[QA] flow: flow-name clean/blocked
[QA] finding: severity description
[QA] gate: gate-name passed/failed
