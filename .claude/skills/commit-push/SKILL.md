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
- No post-push reconcile step (the old Flux/k8s `flux reconcile` step is retired —
  this is an IaC repo the user applies manually via `op run -- terraform apply`).
