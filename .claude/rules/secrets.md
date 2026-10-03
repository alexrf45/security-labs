# Secrets Management

Secrets for the range are managed with **1Password** (primary) and **SOPS** (for
files that must live encrypted in the repo). Integrate 1Password as deeply as
practical — it is the source of truth.

## 1Password first

- Reference secrets by `op://<vault>/<item>/<field>`, resolved at runtime with
  `op run -- ...` or `op read`. Prefer this over materializing secrets to disk.
- Terraform/Packer/CLI invocations that need credentials run under `op run --` so
  the values are injected into the process environment, never written to a file or
  the shell history.
- Cloud provider keys, Tailscale auth keys, and lab passwords live in 1Password.
  When discussing them, reference the **item name only**, never the value.

## SOPS (encrypted-in-repo files)

- `terraform.tfvars`, backend config with secrets, and Packer var-files are
  **SOPS-encrypted by the user** before commit. Decrypt → edit → re-encrypt is a
  **user** action.
- **Never modify, re-encrypt, or create SOPS-encrypted files without explicit user
  confirmation.** The user manages secrets themselves.

## Local Terraform state = plaintext secrets

- The range uses **local `.tfstate`** ([terraform.md](terraform.md)). Local state
  stores secret attribute values in **plaintext**. Therefore:
  - `*.tfstate` and `*.tfstate.*` stay gitignored (already are). Never commit state.
  - Do not paste state contents into the conversation, logs, or artifacts.
  - Treat the working copy of state as sensitive at rest.

## Handling rules

- **NEVER** pipe live credentials through ad-hoc `jq`/`sed` redaction filters in
  conversation. If a redaction filter is ever needed, test it against fake data first.
- Never send a secret to an external service, a URL, a request header, or an artifact.
- If a command would print a secret, redirect or suppress that output.
- The user's email (`fonalex45@gmail.com`) is for attribution/identity only — never
  put it in a request header, URL, or payload to an unrelated service.
