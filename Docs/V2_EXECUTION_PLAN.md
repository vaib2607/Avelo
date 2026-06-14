# V2_EXECUTION_PLAN.md — ARCH Draft

## Summary
V2 should land in this order: contract rulings, measurement/code-health, performance, restore hardening, encryption, then selected reporting/inventory backlog. This keeps data-format work serialized, preserves offline-only rules, and avoids adding new report families before the report code is split and benchmarked.

Do not edit `Docs/Avelo_Release_Board.md` directly. This draft is additive and must be reviewed by ARCH/human reviewers before Phase 1 begins.

## Freeze Contract First
These contracts must be updated and reviewed before code work starts:

- **STOP — SQLCipher / R-1 dependency ruling**: Phase 5 cannot be estimated or scoped until ARCH/human reviewers decide whether encryption may use vendored C source compiled locally, with no `.package(url:)` and an empty `Package.resolved`, or whether R-1’s “dependency list is exactly zero” forbids that too. If R-1 cannot be clarified, SQLCipher is dead on arrival and Phase 5 must be replanned around a different local encryption design.
- **Backup/restore hardening**: update `Docs/Avelo_Architecture.md` with backup manifest/version validation, restore staging, rollback behavior, and corrupted-backup handling.
- **At-rest encryption**: after the R-1 ruling, update `Docs/Avelo_Rules.md` and `Docs/Avelo_Architecture.md` with local-only key/passphrase policy, encrypted DB open flow, backup/export behavior, and explicit ban on network KMS or cloud recovery.
- **Schema/index changes for performance**: update `Docs/Avelo_Schema.md` before adding any new persistent indexes, triggers, or migration files.
- **PO/SO visibility**: update `Docs/Avelo_Schema.md`, `Docs/Avelo_Naming_Freeze.md`, and business rules before introducing order-tracking tables, statuses, or fulfillment identifiers.
- **Reorder alerts**: update schema/naming first if reorder thresholds are persisted. Stock ageing derived only from existing stock movements does not require a schema change.
- **UUIDv7**: if pulled into V2 despite the recommendation to defer, update `Docs/Avelo_Schema.md`, `Docs/Avelo_Naming_Freeze.md`, and migration rules before implementation.

## Recommended Phase Ordering

### 1. V2 Baseline And Contract Rulings
**Risk**: data-safety-critical / planning  
**Effort**: S, except the encryption dependency ruling may reclassify Phase 5.

**Rationale**: V2 changes file formats and performance assumptions. Locking contracts and baseline numbers first prevents later fixes from being based on moving targets.

**Dependency analysis**
- Blocks backup hardening, encryption, schema-index work, PO/SO, reorder alerts, and any UUIDv7 decision.
- Must resolve the SQLCipher/R-1 ruling before Phase 5 can be planned as SQLCipher-based.
- Must confirm v1.0 tag benchmark baseline before changing performance-sensitive code.

**Entry criteria**
- v1.0 tag is available locally or fetchable by the release owner.
- Frozen docs are treated as authoritative.

**Exit criteria**
- Contract PR reviewed for all “Freeze Contract First” items selected for V2.
- SQLCipher/R-1 ruling recorded explicitly.
- Baseline scorecards captured for current branch and v1.0 tag on the same machine.
- No offline/network exception introduced.

**Required proof**
- `make rule-audit`
- `swift test --filter DatabasePerformanceTests`
- `make benchmark`
- `make benchmark-million`

**Migration / rollback**
- No migration in this phase.
- Rollback is doc-only: revert the contract draft before implementation begins.

### 2. Report Code-Health Split
**Risk**: code-health  
**Effort**: M.

**Rationale**: Split report storage/query code and report UI before adding cash flow, invoice-wise GSTR-1, or stock ageing. This lowers regression risk and keeps later feature diffs reviewable.

**Dependency analysis**
- Blocks cash flow statement, invoice-wise GSTR-1 export, and stock ageing report UI.
- Does not block backup, encryption, or benchmark work.

**Entry criteria**
- Phase 1 contracts accepted.
- Existing report tests pass on unchanged behavior.

**Exit criteria**
- Report behavior unchanged.
- No schema changes.
- No new persisted report totals or rollups, preserving SQLite as the system of record.

**Required proof**
- `swift test --filter "Report|Reconciliation"`
- `swift test --filter "[Gg][Ss][Tt]"`
- `swift test`
- `make rule-audit`

**Migration / rollback**
- No on-disk migration.
- Rollback is source-only because this is structural refactor work.

### 3. Large-Dataset Performance Hardening
**Risk**: performance  
**Effort**: L.

**Rationale**: Performance work should land before data-format encryption, because encryption can change IO characteristics and obscure query regressions.

**Dependency analysis**
- Depends on Phase 1 benchmark baseline.
- Benefits from Phase 2 split for report-specific query tuning.
- Blocks performance-sensitive report backlog.
- If new persistent indexes are needed, requires `Docs/Avelo_Schema.md` update first.
- Backup-scan tuning in this phase must target read-path query shape only; Phase 4 owns restore staging and manifest control flow.

**Planned work**
- Prepared-statement reuse only through the approved SQLite wrapper.
- Query-plan tuning for report, ledger, voucher, and backup read paths.
- Pagination for large report/view surfaces where behavior remains exact.
- Re-baseline 500k voucher stress numbers against v1.0 and current V2 branch.

**Entry criteria**
- Baseline scorecards exist for v1.0 and current branch.
- Any proposed schema/index changes have frozen-doc approval.

**Exit criteria**
- No N+1 query patterns introduced.
- Query-plan tests cover new critical indexes.
- 500k benchmark is equal or better than v1.0 within documented variance, or any regression has an accepted reason.

**Required proof**
- `swift test --filter DatabasePerformanceTests`
- `swift test --filter BenchmarkSuiteTests/testBenchmarkCoreWorkflowSuite`
- `make benchmark`
- `make benchmark-million`
- `swift test`

**Migration / rollback**
- Query-only changes: source rollback.
- New index migrations: forward migration adds indexes; rollback note documents that indexes can be dropped without data loss, but migration files remain append-only.

### 4. Backup/Restore Integrity Hardening
**Risk**: data-safety-critical  
**Effort**: M.

**Rationale**: Restore hardening should precede encryption. Encrypted backup/restore paths need a trusted staging and validation flow before encrypted file handling adds more failure modes.

**Dependency analysis**
- Depends on Phase 1 architecture contract.
- Blocks encryption backup/restore support.
- Does not require report split.

**Planned work**
- Versioned backup manifest validation beyond checksum.
- Restore into staging location before registry mutation.
- Explicit handling for manifest mismatch, schema mismatch, corrupt DB, partial copy, and duplicate company identity.
- Preserve offline-only behavior: no external validation service, no cloud endpoint, no network lookup.

**Entry criteria**
- Backup manifest contract approved.
- Existing backup/restore tests green.

**Exit criteria**
- Failed restore leaves existing companies and registry untouched.
- Successful restore validates DB integrity, schema version, manifest, and company metadata before registration.
- Corrupt and partial backups fail with typed user-facing errors.

**Required proof**
- `swift test --filter Backup`
- `swift test --filter Restore`
- `swift test --filter BenchmarkSuiteTests/testBenchmarkBackupRestoreSuite`
- `make rule-audit`
- `swift test`

**Migration / rollback**
- File-format migration: support old checksum-only backups as readable legacy inputs if the contract permits.
- Rollback note: new manifest fields must be additive; restore must reject unsupported future versions without modifying local state.

### 5. At-Rest Encryption
**Risk**: data-safety-critical  
**Effort**: L if vendored SQLCipher is approved; larger and replanned if R-1 forbids vendored encryption libraries.

**Rationale**: Encryption should land after restore hardening and performance tuning. It must be isolated from UUIDv7 or any other data-layer migration.

**Dependency analysis**
- Depends on Phase 4 restore staging.
- Depends on Phase 1 SQLCipher/R-1 ruling and encryption contract.
- Blocks any claim of encrypted-at-rest V2 readiness.
- Must not start in the same phase as UUIDv7.

**Planned work**
- Use only the approved local integration shape from Phase 1.
- If vendored SQLCipher is approved: no `.package(url:)`, no external SPM dependency, `Package.resolved` remains empty.
- If vendoring is rejected: stop and produce a replacement encryption design before implementation.
- Define local key/passphrase storage policy.
- Encrypt company databases without introducing network, telemetry, cloud sync, or remote key management.
- Update backup/export/restore tests for encrypted stores.

**Entry criteria**
- SQLCipher/R-1 ruling complete.
- Human/ARCH approval on encryption implementation shape and key policy.
- Backup/restore hardening complete.
- Packaging impact known for macOS distribution.

**Exit criteria**
- New company files are encrypted at rest.
- Existing unencrypted company files migrate through an explicit, recoverable flow.
- Wrong key/passphrase and corrupt encrypted DB errors are typed and recoverable.
- Backup/restore works for encrypted stores.
- R-1 remains satisfied under the approved wording.

**Required proof**
- `swift test --filter Database`
- `swift test --filter Backup`
- `swift test --filter Restore`
- `make net-check`
- `make rule-audit`
- `swift test`
- `swift build`

**Migration / rollback**
- Migration path: create encrypted replacement DB in staging, copy validated data transactionally, run integrity checks, then atomically swap.
- Rollback note: keep original unencrypted DB until encrypted DB opens, passes integrity checks, and registry update succeeds.

### 6. Reporting Feature Backlog
**Risk**: feature  
**Effort**: M.

**Included**
- Invoice-wise GSTR-1 export format.
- Cash flow statement.
- Stock ageing report if derived from existing inventory movements.

**Rationale**: These should follow report split and performance work. They are report/query additions, not data-layer migrations, if kept derived from existing schema.

**Dependency analysis**
- Depends on Phase 2 report split.
- Depends on Phase 3 performance baseline.
- Invoice-wise GSTR-1 must remain file export only; GST portal upload/API integration conflicts with offline-only rules and is not allowed.

**Entry criteria**
- Report split merged.
- GST/export naming contract reviewed if new DTO/file names are introduced.

**Exit criteria**
- Reports derive from SQLite source data with no persisted rollups.
- GSTR-1 export is invoice-wise and offline-only.
- Cash flow mapping is tested against voucher/account fixtures.
- Stock ageing handles disabled inventory mode as a no-op.

**Required proof**
- `swift test --filter "[Gg][Ss][Tt]"`
- `swift test --filter "Report|Reconciliation"`
- `swift test --filter Inventory`
- `make net-check`
- `make rule-audit`
- `swift test`

**Migration / rollback**
- No DB migration if derived-only.
- Export format changes must be versioned in tests; rollback is source-only.

### 7. PO/SO Visibility And Reorder Alerts
**Risk**: feature / data-safety if persisted  
**Effort**: L.

**Rationale**: This is later V2 only if the contract review accepts new persisted order/threshold state. It should not be mixed with encryption or UUIDv7.

**Dependency analysis**
- Depends on schema/naming/rule contract updates.
- PO/SO pending visibility blocks delivery/receipt status reporting.
- Reorder alerts depend on persisted thresholds unless explicitly scoped to non-persisted computed warnings.

**Entry criteria**
- Frozen schema and naming updates accepted.
- Inventory disabled-mode behavior specified.
- No concurrent data-layer migration phase active.

**Exit criteria**
- Pending receipts/deliveries reconcile to source PO/SO records.
- Reorder alerts do not fire when inventory is disabled.
- All writes validate foreign keys, company scope, and inactive records.

**Required proof**
- `swift test --filter Inventory`
- `swift test --filter Voucher`
- `swift test --filter Database`
- `make rule-audit`
- `swift test`

**Migration / rollback**
- Migration path: add new tables/columns with nullable-safe defaults, then backfill only where deterministic.
- Rollback note: old app versions must reject newer schema versions cleanly; no destructive down migration.

### 8. V2 Release Candidate Hardening
**Risk**: release / data-safety  
**Effort**: M.

**Rationale**: Final phase proves that security, restore, performance, and selected features work together on one branch.

**Entry criteria**
- All selected V2 phases complete.
- No open Critical/High audit findings.
- Release board remains additive; frozen docs updated only through reviewed contract PRs.

**Exit criteria**
- Full local RC proof passes.
- Benchmark scorecards attached.
- Backup/restore and encryption failure modes documented.
- All new V2 UI surfaces pass the same sidebar/menu/command-palette/keyboard entry-point audit as RB-043.
- No network/offline rule violations.

**Required proof**
- `make rc-local`
- `make benchmark`
- `make benchmark-million`
- `make rule-audit`
- `swift test`

**Migration / rollback**
- RC rollback is branch-level.
- Any shipped file-format migration must include an operator-visible recovery note before release.

## Dependency Graph
```text
Freeze contracts -> blocks -> backup hardening, encryption, schema-index work, PO/SO, reorder alerts, UUIDv7-if-selected
SQLCipher/R-1 ruling -> blocks -> encryption phase estimation and implementation
v1.0 benchmark baseline -> blocks -> performance hardening
ReportRepository/ReportsView split -> blocks -> cash flow, invoice-wise GSTR-1, stock ageing report
Performance hardening -> blocks -> report backlog RC acceptance
Backup/restore hardening -> blocks -> at-rest encryption
At-rest encryption -> blocks -> encrypted backup/restore RC
PO/SO schema contract -> blocks -> PO/SO pending receipts/deliveries
Inventory threshold contract -> blocks -> reorder alerts
UUIDv7 -> conflicts-with-same-phase -> encryption or any other data-layer migration
Cross-company consolidation -> blocks -> V3 architecture/rules review
```

## V3 / Explicitly Out Of Scope For This Cycle
- **UUIDv7 migration**: defer unless a concrete multi-device/offline-merge requirement appears; current single-device offline usage does not justify V2 data-layer migration risk.
- **Cross-company consolidation**: defer because it cuts across company-file isolation, trust boundaries, and reporting semantics.
- **GST portal upload/API integration**: out of scope because it conflicts with offline-only / zero-network rules; V2 may produce local invoice-wise export files only.
- **Materialized report rollups**: defer because R-rules keep SQLite source data authoritative and V2 should first exhaust query/index/pagination tuning.
- **Deep UI virtualization and thermal/hardware-specific UX**: defer unless Phase 3 benchmarks prove they are required for V2 acceptance.
- **Automated VACUUM/ANALYZE scheduling**: defer to V3 unless Phase 3 produces direct evidence that manual query/index tuning is insufficient.

## Assumptions
- V2 prioritizes safety and scale over broad feature count.
- Frozen docs remain authoritative and are updated before code whenever schema, naming, rules, architecture, dependency policy, or file format changes.
- Once a phase passes its exit criteria, move to the next phase. Stop only when all selected V2 bugs, risks, and planned backlog items in this execution plan are resolved or explicitly deferred by ARCH/human review.
