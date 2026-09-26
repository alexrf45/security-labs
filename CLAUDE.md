# CLAUDE.md

## What this repo is

A **cloud-native security research lab** (cyber range) built as reproducible
Infrastructure as Code. It exists to practice offensive **and** defensive security,
develop bespoke tooling/payloads/detections for Linux and Windows hosts, and test
CVEs — in cloud network segments isolated so that malware/payloads under test cannot
reach the user's accounts, other segments, or the internet unfiltered.

## Implementation

The range is provisioned with **Terraform** on **AWS** with local terraform state. Secrets are handled with **1Password** (source of truth) and **SOPS** (encrypted-in-repo files). Entrypoint into the lab via **Tailscale**. The lab is **ephemeral by design** and runs under a hard **$30/month** budget. The user runs `terraform plan`/`apply`/`destroy`  wrapped in the 1Password CLI (`op run -- terraform apply`).

## Start here

- **`_docs/README.md`** — documentation index / start-here.
- **`_docs/decisions/0010-cloud-native-pivot.md`** — the pivot and its constraints.
- **`_docs/decisions/0011-*`** — provider & topology - Implemented in `_infra/terraform/aws/`.
- **`_docs/runbooks/aws-range-deployment.md`** — how to stand the range up, plus its
  [status page](_docs/runbooks/aws-range-deployment-status.md) for what is applied.
- **`.claude/rules/range-safety.md`** — non-negotiable isolation. **Read
  before any change to range networking, the scenario module, or a scenario.**
- **`.claude/rules/cost-guardrails.md`** — the $30 cost ceiling.

## Directory layout

```
.
├── .claude
│   ├── agents
│   ├── commands
│   ├── rules
│   └── skills
│       ├── active-directory-attacks
│       ├── aws-cost-operations
│       ├── commit
│       ├── commit-push
│       ├── debuzz
│       ├── documentation
│       ├── malware-analyst
│       └── threat-modeling-expert
├── _docs
│   ├── archive
│   ├── decisions
│   ├── reference
│   ├── reviews
│   └── runbooks
├── _hack
│   ├── nix
│   └── scripts
└── _infra
    └── terraform
        └── aws
            ├── ops-tier
            │   └── scripts
            ├── range-network
            └── scenarios
                └── multi-forest
```

## Business rules — `.claude/rules/`

Read the one(s) relevant to your change; add new insights there as discovered.

- **`range-safety.md`** — isolation requirements (no egress route / no public IP on
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
| `/lab-review` | Periodic posture review → `_docs/reviews/`. Sole owner of the 11-invariant audit. |
| `/adr` | Scaffold the next ADR in house format. |
| `/handoff` | Compact the session into `session-handoff-*` in persistent memory. |

## Agents & skills

- **Agents** (user-invoked): `plan-challenger` — adversarial, read-only plan
  review, with range-specific kill questions (budget, invariants, who-runs-apply).

- Skills: `active-directory-attacks`, `malware-analyst`, `threat-modeling-expert`,
  `aws-cost-operations`, `commit`/`commit-push`.
