# Commit Skill

Stage relevant changes, write a conventional commit message based on the diff, and commit.

Rules:
- Conventional type: `feat:` / `fix:` / `chore:` / `docs:` / `refactor:`.
- `chore:` for README/version bumps; `docs:` for documentation; `fix:` with the
  root cause in the body.
- Run `/lint` (fmt + validate + tflint) before committing when `_infra/` changed.
- Commits are **SSH-signed via the 1Password agent**. If signing fails, tell the
  user to authenticate — do not retry (see `.claude/rules/git-ssh-agent.md`).
- Never commit secrets or `*.tfstate` (see `.claude/rules/secrets.md`).
- Only commit when the user asks; if on `main`, branch first.
