# Developer Experience and Release Evidence

Use repo-owned commands so local, CI, and release evidence mean the same thing. Raw `swift` commands are diagnostic only unless the release board explicitly accepts them.

## Documentation ownership

| Document | Owns | Does not own |
|---|---|---|
| `Avelo_Master_PRD.md` | required user-visible behavior and scope | current readiness |
| `Avelo_Rules.md` | non-negotiable invariants | implementation status |
| `Avelo_Naming_Freeze.md` | explicitly listed compatibility names | every internal symbol |
| `Avelo_Architecture.md` | dependencies, lifecycle, transaction boundaries | exact schema DDL |
| `Avelo_Schema.md` | readable current persistence contract | executable migration truth |
| `Avelo_Status_Checklist.md` | human-readable current state | issue-level canonical verdict |
| `Avelo_Execution_Checklist.md` | next actions and evidence log | product behavior |
| `Avelo_Release_Board.md` | canonical readiness verdict and backlog | low-level implementation design |
| `DX.md` | supported commands and evidence format | release approval by itself |

The product roadmap is `Avelo_Master_Product_Execution_Plan.md`. It coordinates the normative documents and release board; it does not replace them.

Roadmap verification uses repository-owned commands: `make build`, `make test`, `make net-check`, `make rule-audit`, `make verify` or `make rc-local`, `make benchmark`, `make benchmark-million`, and `make launch-smoke` as applicable. Historical agent instructions are not an active source of commands or release status.

When documents conflict, fix the owner instead of duplicating a second rule elsewhere.

## First run

```bash
make setup
```

This verifies the local toolchain, builds, tests, assembles `dist/Avelo.app`, and prints the next step.

## Daily loop

```bash
make build
make test
make dev
```

- `make build` builds through the repo-local Swift wrapper.
- `make test` runs the full `AveloTests` suite.
- `make dev` builds and launches the debug executable. It is not distribution proof.

For a focused test:

```bash
./Scripts/swiftw.sh test --filter TestType/testBehavior
```

Run the focused test while iterating, then `make test` before claiming regression proof. A skipped test is not a pass; record every skip.

## Repo-local SwiftPM state

`Scripts/swiftw.sh` keeps SwiftPM and Clang state in repo-local paths such as `.swift-dev/` and `.build/swiftpm-scratch/`. If a raw command reports `Operation not permitted`, `ModuleCache`, or `org.swift.swiftpm` errors, rerun through `make` or the wrapper.

Do not treat a sandbox/tooling failure as an application failure or silently retry until output looks green. Record the environment issue and use the supported path.

## Rule and release-candidate proof

```bash
make rule-audit
make test
./Scripts/swiftw.sh build -c release -Xswiftc -warnings-as-errors
make rc-local
make benchmark
make launch-smoke
open dist/Avelo.app
```

`make rc-local` is currently an alias for `make verify`, which runs:

1. `make rule-audit`
2. `make test`
3. `make bundle`
4. `make validate-bundle`
5. `make bundle-selftest`

What it proves:

- automated offline/style/money heuristics passed;
- the full test suite completed in that environment;
- a release bundle was assembled;
- bundle structure and its current signature validated; and
- the bundled executable completed the self-test flow.

What it does not prove:

- accountant correctness or complete audit coverage;
- keyboard, VoiceOver, resizing, dark mode, PDF/print, or recovery UX;
- the GUI launched; `Scripts/launch_smoke.sh` currently validates and self-tests but does not call `open`;
- Developer ID signing, hardened-runtime policy, notarization, stapling, Gatekeeper, clean-Mac installation, or upgrade/rollback; or
- that historical evidence still applies to the current worktree/artifact.

Run `open dist/Avelo.app` separately in a normal GUI session and record the manual result.

## Benchmarks

```bash
make benchmark
make benchmark-million
```

Compare like with like: same machine, power/thermal state, build configuration, encryption state, dataset generator/seed, schema version, command, and threshold. Record median or the metric required by the board, not the fastest run. A threshold change needs an explanation and review.

## Evidence record

Every release claim records:

```text
Date/time and timezone:
Commit:
Worktree status/diff identity:
macOS, Xcode, Swift:
Machine and architecture:
Schema version and fixture/dataset:
Command or manual script:
Result and duration:
Skipped tests/warnings:
Artifact path, version, build, SHA-256, signing identity:
Evidence owner:
Related AVL-* row:
```

Evidence is valid only for the identified worktree and artifact. A source, migration, seed, build script, entitlement, or release-setting change invalidates affected proof. Historical logs stay useful context but never silently close a current row.

## Public-production distribution runbook

`ReleaseVersion.env` is the single source for `CFBundleShortVersionString` and `CFBundleVersion`. The current candidate is v1.1 build 3. `Scripts/bundle.sh` still produces an ad-hoc signed local RC until a Developer ID identity is provisioned.

Before public production, choose and document one path:

### Developer ID distribution

1. Build from a clean, identified commit with warnings as errors.
2. Sign nested code and the app with the approved Developer ID Application identity and hardened runtime.
3. Review entitlements and ensure SQLCipher/resources are inside the signed seal.
4. Submit for notarization, wait for acceptance, staple the ticket, and run `spctl` plus `codesign --verify --deep --strict`.
5. Test first install, launch, company create/open, backup/restore/recovery, upgrade, and uninstall expectations on a clean supported Mac with Gatekeeper enabled.

### Mac App Store distribution

Document sandbox/container migration, App Store entitlements, review constraints, receipt behavior, and how existing local company files move safely. Treat this as a separate approved release plan, not a flag on the ad-hoc bundle script.

For either path, record certificate ownership/expiry/rotation, notarization credentials, artifact checksum and retention, release notes/privacy/support contacts, rollback artifact and rollback limits, schema downgrade policy, crash/incident intake that preserves the offline rule, and who can declare or revoke release readiness.

Capture the exact Phase 0 candidate before human testing:

```bash
./Scripts/phase0_evidence.sh dist/Avelo.app
```

Copy its output into `Docs/Avelo_Phase0_Manual_Acceptance.md`. A changed executable checksum invalidates prior acceptance and requires a new record.

## Documentation release check

Before tagging:

- `SchemaVersion.current`, migrations, naming freeze, and schema doc agree.
- PRD behavior is either proved or mapped to an open release-board item.
- Release Board, Status Checklist, and Execution Checklist agree on IDs and state.
- All relative Markdown links resolve.
- Commands shown here still exist and their described behavior matches the scripts.
- The board says **READY** only after every P0 and the chosen distribution gate close.
