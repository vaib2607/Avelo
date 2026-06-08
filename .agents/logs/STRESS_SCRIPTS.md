# AVELO STRESS / SOAK SCRIPTS

- Voucher Volume Stress
  - Seed a fresh in-memory company through the test harness.
  - Insert `N = 1000` balanced vouchers through `VoucherService`.
  - Run `trialBalance`, `profitAndLoss`, and `balanceSheet`.
  - Compare each report total against direct SQL aggregates.
  - Assert no crash, no foreign-key drift, and no mismatched totals.

- Report Generation Stress
  - Seed a representative company with vouchers and reportable accounts.
  - Generate `trial balance`, `P&L`, `balance sheet`, `ledger`, `day book`, `GST`, and `outstanding` `50x` each.
  - Capture a stable hash or serialized snapshot of each result.
  - Verify each repeated run is byte-for-byte identical.
  - Watch for slowdown spikes and repeated allocation growth during the loop.

- Company Switch Soak
  - Create two companies with distinct charts and active FY records.
  - Switch the active context between them `100x`.
  - After each switch, verify the dashboard/report context resolves to the selected company only.
  - Confirm no stale account, voucher, or FY state leaks across switches.

- Restore / Reopen Soak
  - Backup one company, restore it, verify the reopened company, then repeat `20x`.
  - Confirm the restored database opens successfully every time.
  - Verify company identity, FY metadata, voucher counts, and key report totals after each cycle.
  - Assert the restored file contents stay intact and the reopened company remains usable.

## Verification Results
- Company Switch Soak: passed via `swift test --filter AppEnvironmentFlowTests/testCompanySwitchSoakMaintainsCorrectContextAcrossRepeatedOpens`
- Restore / Reopen Soak: passed via `swift test --filter RestoreServiceTests/testRestoreReopenSoakPreservesCompanyDataAcrossRepeatedCycles`
