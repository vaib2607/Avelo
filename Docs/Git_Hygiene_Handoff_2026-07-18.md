# Git Hygiene Handoff — 2026-07-18

This note records the Git cleanup performed on 2026-07-18. Read it before
recovering old work or removing additional branches.

## Current topology

- `main` is the canonical integration branch and tracks `origin/main`.
- `v1.1-dev` is retained as an archive. It has no commits absent from `main`;
  `main` contains three newer dashboard commits.
- At cleanup time, the active local branch was
  `codex/reports-voucher-worktree-20260718`. It had not been pushed and already
  contained these scoped commits:
  - `07bbfb1` preserves report and voucher-entry work.
  - `ad5868c` stops tracking generated Claude runtime data and `dist/Avelo.app`.
  - `302da98` stops tracking local Claude settings and ignores `.ua/tmp/`.

## Archived and removed work

- `archive/v1.1-dev-2026-07-18` points to the former `v1.1-dev` tip and is
  published on `origin`.
- `archive/claude-keen-lumiere-2026-07-18` points to the retired
  `claude/keen-lumiere-6f4778` branch and is published on `origin`.
- The retired Claude branch was reviewed before deletion. Its only final code
  difference was an older, weaker GSTIN validator; do not restore or merge it.
- Five reviewed stashes were deleted. They contained Claude runtime churn,
  generated `.ua` artifacts, or a marked obsolete predecessor of `4d4aff0`.

## Recovery

To inspect an archived branch without moving `main`:

```bash
git switch -c recovery/claude-keen archive/claude-keen-lumiere-2026-07-18
```

To recover the archived v1.1 snapshot:

```bash
git switch -c recovery/v1.1-dev archive/v1.1-dev-2026-07-18
```

Do not reset, force-push, or merge an archive tag into `main` without first
comparing it to `main` and opening a focused recovery branch.
