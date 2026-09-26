# CLAUDE.md

## What this repo is

A **cloud-native security research lab** (cyber range) built as reproducible
Infrastructure as Code. It exists to practice offensive **and** defensive security,
develop bespoke tooling/payloads/detections for Linux and Windows hosts, and test
CVEs — in cloud network segments isolated so that malware/payloads under test cannot
reach the user's accounts, other segments, or the internet unfiltered.

The range is provisioned with **Terraform** (cloud-agnostic; AWS/Hetzner primary,
Azure/GCP open). Secrets are handled with **1Password** (source of truth) and **SOPS**
(encrypted-in-repo files). Human entry is via **Tailscale**. The lab is **ephemeral by
design** and runs under a hard **$30/month** budget.

> **History:** this repo was previously a GitOps Kubernetes home lab (Talos/Flux) and
> then a **Proxmox** security range (ADR-0009), built but never deployed. It pivoted to
> cloud-native (**ADR-0010**, 2026-09-24), and the AWS range is now **built but not yet
> deployed** (**ADR-0011**, Accepted). The Proxmox-era Terraform and Packer code is gone
> from `_infra/` and archived under `_docs/archive/proxmox/`.

## Lab goals & constraints (from ADR-0010)

1. **≤ $30/month, all-in, across all providers** — a hard, first-class constraint.
2. **Local Terraform state** everywhere (reduced attack surface, simpler ops).
3. **1Password** for secrets, integrated as deeply as practical.
4. **Windows + Linux** environments, both first-class.
5. **Tailscale** as the sole entrypoint (no OpenVPN, no public bastion).
6. **Offensive + defensive** coverage: attacker box + defensive/SIEM side.

Plus: **cloud-agnostic** by default; **reproducible** (no click-ops for scenarios);
**structural isolation** (victim segments have no egress route and no public IP);
**in-depth Markdown docs** aimed at a future public documentation site.

## Start here

- **`_docs/README.md`** — documentation index / start-here.
- **`_docs/decisions/0010-cloud-native-pivot.md`** — the pivot and its constraints.
- **`_docs/decisions/0011-*`** — provider & topology (**Accepted**): AWS-only, ephemeral,
  three roots. Implemented in `_infra/terraform/aws/`.
- **`_docs/runbooks/aws-range-deployment.md`** — how to stand the range up, plus its
  [status page](_docs/runbooks/aws-range-deployment-status.md) for what is applied.
- **`.claude/rules/range-safety.md`** — non-negotiable isolation invariants. **Read
  before any change to range networking, the scenario module, or a scenario.**
- **`.claude/rules/cost-guardrails.md`** — the $30 ceiling and what it forbids.

## Directory layout

| Directory | Purpose |
| --- | --- |
| `_infra/terraform/aws/` | The range: three roots split by blast radius (`range-network`, `ops-tier`, `scenarios/multi-forest`). The only infra code in the repo. |
| `_docs/` | `decisions/` (ADRs), `runbooks/` (how-to), `reviews/` (posture reviews), `reference/`, `archive/proxmox/` (historical). |
| `_hack/` | One-off scripts & the local Nix attacker env. `scripts/guard-mutations.sh` backs the PreToolUse safety hook. |
| `.claude/rules/` | Business rules (below). |
| `.claude/commands/` | Slash commands (below). |
| `.claude/skills/` | Vendored security skills + commit skills. |
| `.claude/agents/` | A small set of on-topic subagents (used only when the user asks). |

## How infrastructure is run

- **The user runs `terraform plan`/`apply`/`destroy` and any `packer build` manually**,
  wrapped in the 1Password CLI (`op run -- terraform apply`). **Claude does NOT run
  apply/destroy/state-mutations/build** — the `_hack/scripts/guard-mutations.sh`
  PreToolUse hook blocks these mechanically. Claude runs **offline checks only**:
  `terraform validate`/`fmt`, `tflint`, `infracost breakdown`.
- Bare `terraform`/`packer` under the `op` plugin fail with `interactive IO not
  available` — expected; use `validate`/`fmt` offline.
- **State:** local backend everywhere, split by blast radius (shared plumbing vs each
  disposable scenario). Local state holds plaintext secrets — never commit it.
- **Secrets:** `terraform.tfvars` and secret-bearing files are **SOPS-encrypted by the
  user** before commit. Never modify/re-encrypt a SOPS file without explicit
  confirmation.

## Business rules — `.claude/rules/`

Read the one(s) relevant to your change; add new insights there as discovered.

- **`range-safety.md`** — isolation invariants (no egress route / no public IP on
  victim hosts, Tailscale-only entry, IMDSv2 + no instance role, one-way
  telemetry, state split). **Highest priority for any range change.**
- **`cost-guardrails.md`** — the $30 ceiling; prohibited/rationed resources; ephemeral
  default; mandatory `infracost` gate; budget alarms.
- **`terraform.md`** — offline-only for Claude, fetch live provider docs (Terraform
  MCP), local state, pinned versions, no `remote-exec`, defaults over hardcoding, SOPS.
- **`secrets.md`** — 1Password-first, SOPS handling, local-state-is-plaintext.
- **`documentation.md`** — Markdown, Diátaxis, per-module READMEs, Mermaid, ADR format.
- **`cloud-inventory.md`** — providers, budget envelope, tooling, what stays local.
- **`skills-and-plugins.md`** — keep context lean; how to reach more skills on demand.
- **`code.md`** — diagnose-before-fixing discipline; Read before Edit.
- **`git-ssh-agent.md`** — 1Password SSH signing; don't retry signing failures.

## Key commands — `.claude/commands/`

| Command | Purpose |
| --- | --- |
| `/lint` | `terraform fmt`/`validate` + `tflint` across `_infra/` (read-only). |
| `/cost` | Projected (`infracost`) + actual (provider bill) vs the $30 ceiling. |
| `/lab-status` | "Did I leave something running?" — live instances, state, tailnet. |
| `/lab-review` | Periodic posture review → `_docs/reviews/`. |
| `/adr` | Scaffold the next ADR in house format. |

## Agents & skills

- **Agents** (only when the user asks): `plan-challenger`, `security-engineer`,
  `terraform-engineer`, `penetration-tester`.
- **Skills:** vendored `active-directory-attacks`, `malware-analyst`,
  `threat-modeling-expert`, `aws-cost-operations`, plus `commit`/`commit-push`. Two
  narrow bundle plugins (offensive + defensive/IR) are enabled by default; reach the
  wider catalog on demand via `/plugin` (see `skills-and-plugins.md`).
