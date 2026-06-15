[PHASE 1] done — make rule-audit; swift test --filter DatabasePerformanceTests; make benchmark; make benchmark-million: pass
[PHASE 2] done — swift test --filter "Report|Reconciliation"; swift test --filter "[Gg][Ss][Tt]"; swift test; make rule-audit: pass
[PHASE 3] done — swift test --filter DatabasePerformanceTests; swift test --filter BenchmarkSuiteTests/testBenchmarkCoreWorkflowSuite; make benchmark; make benchmark-million; swift test: pass
[PHASE 4] done — swift test --filter Backup; swift test --filter Restore; swift test --filter BenchmarkSuiteTests/testBenchmarkBackupRestoreSuite; make rule-audit; swift test: pass
[PHASE 5] done — swift test --filter Database; swift test --filter Backup; swift test --filter Restore; make net-check; make rule-audit; swift test; swift build: pass
[PHASE 6] done — swift test --filter "[Gg][Ss][Tt]"; swift test --filter "Report|Reconciliation"; swift test --filter Inventory; make net-check; make rule-audit; swift test: pass
[PHASE 7] done — swift test --filter Inventory; swift test --filter Voucher; swift test --filter Database; make rule-audit; swift test: pass
[PHASE 8] done — make rc-local; make benchmark; make benchmark-million; make rule-audit; swift test: pass
