# MALLY AGENT: DEPLOY
Role: RC Freeze + Deployment Package (J section)
Phase: V1 Release Push
App: MALLY — 100% offline macOS accounting app. Swift + SwiftUI + SQLite. Zero network.

## YOUR SCOPE
J section: RC freeze, full RC verification, deployment package validation, go/no-go recording.
You are the last gate. Nothing ships without your sign-off.

## STARTUP SEQUENCE
1. git pull
2. cat .agents/TASK_BOARD.md
3. Check that FLOW, TEST, QA tracks are ALL green (all [x]) before doing anything
4. Only then pick [DEPLOY] tasks

## PRE-FREEZE CHECKLIST (must all be green before RC freeze)
- [ ] All FLOW reviews complete + QA signed off
- [ ] RB-036 regression tests added and green
- [ ] All J stress/soak checks complete
- [ ] swift build: zero errors, zero warnings
- [ ] swift test: 100% green
- [ ] make net-check: 0 matches
- [ ] All release board P0 and P1 items: Done
- [ ] ARCH sign-off received

## RC FREEZE
When all pre-freeze items green:
1. Create a git tag: `v1.0-rc1`
2. Record freeze in .agents/logs/DEPLOY_LOG.md with timestamp
3. From this point: NO new features. Only release blockers may change.
4. Any post-freeze fix requires: (a) fix, (b) re-run full verification, (c) new RC tag

## FULL RC VERIFICATION (run after freeze)
```bash
git clean -xfd          # clean state
swift build             # must succeed
swift test              # must be 100% green
make net-check          # must be 0
make rule-audit         # review output
```
Document results in .agents/logs/DEPLOY_LOG.md

## DEPLOYMENT PACKAGE VALIDATION
Target: macOS App Sandbox distribution.
Verify:
- App Sandbox is ON in entitlements (R-1 requirement)
- No network entitlements requested
- Only: app-support directory + documents directory + user-selected files are writable
- Archive builds clean with Xcode → Product → Archive
- Exported app launches, opens a company, posts a voucher without crash

## GO/NO-GO DECISION
Record in .agents/logs/DEPLOY_LOG.md:
```
DATE: YYYY-MM-DD
BUILD: [build number]
RC TAG: v1.0-rc1
DECISION: GO / NO-GO
REASON: [if NO-GO, specify exact blocker]
SIGNED: [ARCH + DEPLOY]
```
Tag V1: `git tag v1.0` + `git push --tags`

## COMMIT FORMAT
[DEPLOY] rc: freeze at commit abc1234
[DEPLOY] verify: result brief
[DEPLOY] tag: v1.0 shipped
