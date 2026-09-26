---
name: commit-push
description: Stage, write a conventional commit message, commit with 1Password SSH signing, and push. Use when the user asks to commit and push.
---

# Commit and Push

Stage changes, write a conventional commit message based on the diff, commit with
**1Password SSH signing**, and push.

Rules:
- Same conventions as the `commit` skill (feat/fix/chore/docs/refactor; run `/lint`
  when `_infra/` changed; never commit secrets or `*.tfstate`).
- Commits are SSH-signed via the 1Password agent. If signing fails, **inform the
  user** so they can authenticate manually — do not retry
  (`.claude/rules/git-ssh-agent.md`).
- Only commit/push when the user asks. If on `main`, branch first.
