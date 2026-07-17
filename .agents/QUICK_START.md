# AVELO CODEX QUICK START — V1 RELEASE PUSH

## SETUP (run once from AVELO repo root)
```bash
cp -r .agents_template/.agents .agents   # if not already present
bash .agents/scripts/setup.sh
```

## CURRENT PHASE
E (Flow Reviews) + G-RB-036 (Regression) + I (Manual QA) + J (RC/Deploy)
All P0 code work, schema, repos, observation migration: DONE.

## 5 CODEX SESSIONS

| Tab | Agent  | System Prompt           | First Command                          |
|-----|--------|-------------------------|----------------------------------------|
| 1   | ARCH   | prompts/ARCH.md         | git pull && make count                 |
| 2   | FLOW   | prompts/FLOW.md         | git pull && cat .agents/TASK_BOARD.md  |
| 3   | TEST   | prompts/TEST.md         | git pull && swift build && swift test  |
| 4   | QA     | prompts/QA.md           | git pull && cat .agents/TASK_BOARD.md  |
| 5   | DEPLOY | prompts/DEPLOY.md       | git pull && cat .agents/TASK_BOARD.md  |

## EXECUTION ORDER

```
FLOW (E section) ──────────────────────────────┐
TEST (RB-036 + J stress/soak) ─────────────────┤
                                                ↓
                                         QA (I section)
                                                ↓
                                         ARCH (gate check)
                                                ↓
                                         DEPLOY (RC + ship)
```

FLOW and TEST run in parallel.
QA starts only after FLOW completes each flow.
DEPLOY starts only after ALL tracks green.

## KEY COMMANDS (from repo root)
```bash
make build       # swift build
make test        # swift test
make net-check   # zero network calls (must be 0 for V1)
make r16-check   # no ObservableObject/@Published in shipped code
make r15-check   # no TODOs/fatalError in shipped code
make rule-audit  # all automated rule checks
make board       # full TASK_BOARD.md
make todo        # only open tasks
make count       # how many remain
```

## INTER-AGENT SYNC
- Shared state: .agents/TASK_BOARD.md (git tracked)
- git pull at session start. git push after each task update.
- Commit tags tell the story: [FLOW] [TEST] [QA] [DEPLOY] [ARCH]
- [QA:needed] tag on FLOW/TEST completed tasks = QA pick-up signal
- [BLOCKED:ROLE] tag = that agent is waiting on you

## RELEASE GATE SEQUENCE (I section — ARCH enforces)
1. Zero open P0 on release board
2. Zero silent data-loss paths
3. Zero FY lock bypasses  
4. make net-check = 0
5. swift build: zero warnings (SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)
6. swift test: 100% green
7. All FLOW/TEST/QA tracks: all [x]
→ ARCH gives go-ahead → DEPLOY tags V1

## TOKEN SAVING
- Read TASK_BOARD.md, not full codebase, at session start
- Read only files for your current task
- Log to .agents/logs/, not verbose chat
- Commit messages are inter-agent comms — precise, not wordy
