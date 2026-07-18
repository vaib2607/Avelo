# Avelo Git Workflow

Use this workflow for Codex, Claude, and human changes. It keeps financial-app
work reviewable and makes branch recovery predictable.

## Before changing files

```bash
git status --short --branch
git fetch --prune
git log --graph --decorate --oneline --all -n 30
```

- Treat an existing dirty worktree as someone else's work until its owner and
  purpose are known.
- Start focused work from up-to-date `main` on a named feature branch. Do not
  use `main` or a release/archive branch for active edits.
- Use a separate worktree when two tasks need independent dirty states.

## During work

- Keep one user-facing or infrastructure concern per commit.
- Commit product changes separately from generated-file or Git-hygiene changes.
- Run `git diff --check` before committing and use the repository-supported
  build/test commands appropriate to the changed layer.
- Do not commit `.claude-flow/`, `.claude/settings.local.json`, `dist/`, or
  disposable `.ua` working data. These paths are intentionally ignored.
- Never add secrets, local permissions, logs, process IDs, caches, or built
  binaries to a commit.

## Merging and recovery

- `main` is the integration branch. Merge reviewed feature branches into it;
  do not maintain a long-lived development branch without an explicit role.
- Before rebasing or deleting a branch, verify ancestry with:

```bash
git merge-base --is-ancestor <branch> main
git rev-list --left-right --count main...<branch>
```

- Before deleting an unmerged or uncertain ref, create and publish an annotated
  archive tag, then verify the tag resolves to the intended commit.
- Do not force-push `main`, release branches, or another person's branch.
- Never clear stashes until each stash has been inspected by file list and
  compared with the intended commits. A stash is not proof that work is junk.

## End of task

```bash
git status --short --branch
git diff --check
git fsck --connectivity-only --no-dangling
```

Report the branch, commit IDs, commands run, any unpushed refs, skipped tests,
and any manual recovery or release work still required.
