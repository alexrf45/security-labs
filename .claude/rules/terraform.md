---
paths:
  - "_infra/**/*.tf"
  - "_infra/**/*.tfvars"
  - "_infra/**/*.tfvars.enc"
  - "_infra/**/*.hcl"
  - ".tflint.hcl"
---
# Terraform Business Rules

The range is provisioned with Terraform. These rules govern how it is written and run.

## How it runs

- **The user runs `plan`/`apply`/`destroy` manually, wrapped in the 1Password CLI**
  (`op run -- terraform apply`). **Claude never runs apply/destroy/import/state
  mutations or `packer build`** — the `_hack/scripts/guard-mutations.sh` PreToolUse
  hook enforces this mechanically. Claude runs **offline checks only**: `terraform
  validate`, `terraform fmt`, `tflint`, and `infracost breakdown`.
- Bare `terraform`/`packer` under the `op` plugin fail with `interactive IO not
  available` — expected. Use `validate`/`fmt` for offline verification.

## State

- **Local state everywhere.** Per the user's decision, the cloud range uses **local
  Terraform state** across the board — shared range plumbing *and* scenarios — to
  reduce attack surface and simplify ops. (This differs from the archived Proxmox
  design, which split S3 for shared plumbing vs local for scenarios.)
- **State split by blast radius:** shared range/network plumbing is one root; each
  disposable scenario is its own root with its own state. A wiped or compromised
  scenario must never be able to corrupt shared infrastructure state.
- Local `.tfstate` contains **plaintext secrets** (passwords, tokens rendered into
  resources). It is gitignored and handled per [secrets.md](secrets.md).

## Providers & versions

- **Always fetch live, current provider docs before writing config** — use the
  HashiCorp Terraform MCP tools (`get_latest_provider_version`,
  `get_provider_details`, `search_modules`, `get_module_details`). Do **not** rely on
  cached/training-data syntax.
- **Pin exact provider versions** and verify the pinned major before writing resource
  blocks. Keep provider versions compatible across roots in the repo.
- **Do not use the `remote-exec` provisioner.** Prefer cloud-init / user-data /
  image-baked config over in-band provisioners.

## Cost gate (see [cost-guardrails.md](cost-guardrails.md))

- Before proposing any change that adds or resizes billable resources, run
  `infracost breakdown` and quote the monthly delta and new total against the **$30/mo
  ceiling**. Prefer the cheapest primitive that works. No NAT gateway, no ALB/NLB,
  ration public IPv4.
- **infracost's monthly totals assume 730 running hours.** This range is ephemeral, so
  translate to a per-hour rate × expected session hours; a raw monthly total is a
  run-it-all-month worst case, not the expected bill.
- **infracost prices Windows AMIs as Linux** (it can't infer the OS from an AMI ID) —
  a ~44% under-estimate per Windows host. Any root with Windows hosts ships an
  `infracost-usage.yml` setting `operating_system: windows`, and the cost gate is run
  with `--usage-file infracost-usage.yml`. A bare infracost total on a Windows scenario
  is a floor, not an estimate.

## Style

- **Prefer default values over hardcoding.** Only hardcode a value when it is a
  sensitive lab-infra constant that must not vary. Expose the rest as variables with
  sensible defaults.
- `terraform.tfvars` and any backend/var files that carry secrets are
  **SOPS-encrypted** by the user before commit. Never modify or re-encrypt a SOPS
  file without explicit user confirmation ([secrets.md](secrets.md)).
- Every module and scenario root ships a README ([documentation.md](documentation.md)).
- Run `/lint` (fmt + validate + tflint) before handing work back.

## Provider/topology decision

Decided in **ADR-0011** (Accepted): **AWS-only**, `us-east-1`, single-AZ, ephemeral by
default, three roots split by blast radius. Windows-on-cloud drove the decision and is
solved with license-included AMIs plus `user_data`, so Packer stays deferred. Provider
pin is `hashicorp/aws 6.66.0`, identical across all three roots.
