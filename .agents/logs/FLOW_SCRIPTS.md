1. RB-026 Company setup
   1. Launch the app in a clean local state.
   2. Create a new company with required identity fields.
   3. Create the first financial year during onboarding.
   4. Confirm the dashboard opens immediately after company creation.
   5. Confirm the company context shows the new company and active FY.
2. RB-026 Company switching
   1. Open the app with at least two companies registered.
   2. Open the second company from the company switcher.
   3. Verify the visible company name updates everywhere in the shell.
   4. Verify the active FY, account tree, and router selection all refresh.
   5. Confirm any sheet or stale route state is cleared after switching.
3. RB-027 Accounts
   1. Open the Accounts screen for an active company.
   2. Create a new account in a valid group.
   3. Edit the account name or code and save.
   4. Disable the account and confirm it no longer appears in active lists.
   5. Filter the list by account type and confirm the filter is respected.
4. RB-028 Voucher list
   1. Open the Voucher list screen.
   2. Switch the type filter across voucher categories.
   3. Search for a known voucher number or narration.
   4. Confirm the list contents update without cross-company leakage.
   5. Confirm keyboard navigation still works while filtering/searching.
5. RB-028 Voucher create
   1. Open the New Voucher flow.
   2. Choose voucher type, date, and narration.
   3. Enter at least one debit line and one credit line.
   4. Confirm the balance check prevents save until totals match.
   5. Save the balanced voucher and confirm it appears in the list.
6. RB-028 Voucher edit
   1. Open an existing voucher from the list.
   2. Change one line amount or narration and keep the voucher balanced.
   3. Save the edit and confirm the updated totals persist.
   4. Reopen the voucher to confirm the saved state matches the edit.
   5. Verify audit/history behavior if exposed in the UI.
7. RB-028 Voucher reverse
   1. Open a posted voucher that can be reversed.
   2. Trigger the reverse action and confirm the reversal sheet opens.
   3. Enter a reversal reason and complete the action.
   4. Confirm the reversal voucher appears in the list.
   5. Confirm reports reflect the reversal as an offsetting entry.
8. RB-029 Settings + FY
   1. Open Settings and go to financial year management.
   2. Create a new FY with valid dates and labels.
   3. Lock the current FY with a reason.
   4. Try to create a new voucher in the locked FY.
   5. Confirm the app rejects the voucher with a typed, visible error.
9. RB-030 Backup
   1. Open the backup flow from the app.
   2. Trigger a backup export for the current company.
   3. Verify a backup file is created at the expected local path.
   4. Confirm the backup completes without network access.
   5. Confirm the app surfaces success or error feedback clearly.
10. RB-030 Restore
   1. Open the restore flow from the app.
   2. Select a previously created backup file.
   3. Complete the restore and wait for the company to reopen.
   4. Verify the restored company dashboard loads successfully.
   5. Confirm the restored company can be used for normal navigation.


### Automated Run:
LLM Connection Error: Is Ollama running? (<urlopen error [Errno 61] Connection refused>)