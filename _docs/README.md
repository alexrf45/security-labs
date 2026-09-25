# Th0th — Documentation

Start-here index for the **cloud-native security range**. All docs are Markdown,
organized by [Diátaxis](https://diataxis.fr/) so the future public documentation site
is a build step, not a rewrite (see `.claude/rules/documentation.md`).

## Map

| Area | Path | What |
| --- | --- | --- |
| **Explanation** | `decisions/` | ADRs — design rationale and the record of decisions. |
| **How-to** | `runbooks/` | Task-oriented operational guides (build, detonate, roll back, tear down). |
| **Reference** | `reference/` | Module inputs/outputs, network/subnet tables, variable refs. |
| **Reviews** | `reviews/` | Periodic posture reviews (`/lab-review`) — cost, safety, drift. |
| **Archive** | `archive/proxmox/` | Previous on-prem/k8s eras — historical only, not live. |

## Current decisions (ADRs)

- **ADR-0010 — Cloud-native pivot** (`decisions/0010-cloud-native-pivot.md`): the move
  from the Proxmox range to a cloud-native one; records the six operating constraints.
- **ADR-0011 — Provider & topology** (`decisions/0011-…`, **Accepted**): AWS-only,
  ephemeral, single-AZ. Implemented in `_infra/terraform/aws/` (three roots). To deploy
  it, follow the [AWS range deployment runbook](runbooks/aws-range-deployment.md).
- **ADR-0009 — Proxmox segmentation** (`decisions/0009-…`): Superseded by ADR-0010;
  kept for its air-gap/segmentation reasoning.

## The operating constraints (from ADR-0010)

1. **≤ $30/month, all-in** — the hard ceiling (`.claude/rules/cost-guardrails.md`).
2. **Local Terraform state** everywhere (reduced attack surface).
3. **1Password** as secrets source of truth; SOPS for encrypted-in-repo files.
4. **Windows + Linux** environments.
5. **Tailscale** as the sole entrypoint (no OpenVPN, no public bastion).
6. **Offensive + defensive** coverage.

## Safety

The non-negotiable isolation invariants live in `.claude/rules/range-safety.md`
(no egress route on detonation subnets, no public IP on victims, Tailscale-only
entry, IMDSv2 + no instance role, one-way telemetry). **Read before any range change.**
