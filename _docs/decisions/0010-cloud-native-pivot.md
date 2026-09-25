# ADR-0010: Pivot from a self-hosted Proxmox range to a cloud-native range

- **Status:** **Accepted** 2026-09-24
- **Date:** 2026-09-24
- **Deciders:** fr3d (with Claude review)
- **Related:** Supersedes [ADR-0009](0009-security-lab-segmentation.md) (Proxmox SDN
  segmentation). Defers provider & topology to **ADR-0011** (pending). Prior on-prem
  eras archived under `_docs/archive/proxmox/`.

## Context

The repo has been, in sequence, a GitOps Kubernetes home lab (Talos/Flux) and then a
**Proxmox-based security research range** (ADR-0009). The Proxmox range was fully
written and `terraform/packer validate`-clean but **never deployed** — so pivoting
away from it costs no running infrastructure, only a code/docs reshape.

The user is moving the range to a **cloud-native** footing. Motivations: no dependence
on the 6-node Beelink/UniFi/TrueNAS hardware, reproducibility from anywhere, and a
clean base to eventually open-source and document publicly. The move is constrained
hard by cost — a hobby budget, not a corp account.

## Decision

**Rebuild the range as a cloud-native, Infrastructure-as-Code security lab** for
offensive **and** defensive practice on Windows and Linux, under six operating
constraints that are binding on all subsequent design:

1. **Cost ceiling: ≤ $30/month, all-in, across all providers.** A first-class design
   constraint with prohibited/rationed resources (no NAT gateway, no ALB/NLB, ration
   public IPv4), ephemeral-by-default hosts, mandatory `infracost` gating, and budget
   alarms. Encoded in `.claude/rules/cost-guardrails.md`.
2. **Local Terraform state** everywhere — shared plumbing and scenarios — to reduce
   attack surface and simplify ops. Split by blast radius (shared vs per-scenario).
   Local state holds plaintext secrets; handled per `.claude/rules/secrets.md`.
3. **1Password** as the secrets source of truth, integrated as deeply as practical
   (`op run --`, `op://` refs); SOPS for encrypted-in-repo files.
4. **Windows and Linux** environments both first-class.
5. **Tailscale** as the sole entrypoint (replacing OpenVPN and any public bastion) —
   which also serves controlled egress and removes the need for a paid NAT gateway.
6. **Offensive and defensive** scope: an attacker box (SSH/RDP/VNC over Tailscale,
   plus a local Nix attacker env) and a defensive/detection + SIEM side.

The **structural air-gap** principle from ADR-0009 carries over: a victim has no path
off its segment — realized in cloud as detonation subnets with **no egress route and
no public IP**, entry only via Tailscale, and **IMDSv2 + no instance role** so a
compromised victim cannot mint cloud credentials. See `.claude/rules/range-safety.md`.

**Cloud-agnostic by default.** The user works mostly with AWS and Hetzner and is open
to Azure/GCP. The concrete provider(s) and network topology are **not decided here** —
they are ADR-0011, so this pivot does not block on them.

## Alternatives considered

- **Stay on Proxmox** — rejected: the user is moving off the home hardware; the range
  was never deployed, so there is nothing to preserve operationally.
- **Pick the provider now (fold into this ADR)** — rejected: the Hetzner-vs-AWS
  trade-off (cost vs Windows support vs ephemerality) deserves its own decision with
  the cost model worked out. Deferred to ADR-0011.
- **Managed/hosted CTF platforms** — rejected: the point is to build the range as
  reproducible IaC and to develop bespoke tooling/detections, not to consume a SaaS.

## Consequences

- **Positive:** hardware-independent, reproducible, publishable; cost is bounded by
  explicit guardrails; Tailscale-only entry simultaneously satisfies the safety and
  cost constraints.
- **Negative / follow-ups:**
  - **Windows on the cheap tier is the weak point** — Hetzner has no first-party
    Windows images (BYOL via ISO); likely a second provider or on-demand-only Windows.
    A primary input to ADR-0011.
  - `_infra/` (Proxmox modules, `range-network`, `scenario-vm`, Packer templates) must
    be rebuilt for cloud — **not yet started**; this ADR covers the harness + docs
    pivot only.
  - The $30 ceiling forces ephemeral scenarios and disciplined teardown (`/lab-status`,
    `/cost`); "left it running" is the main budget risk.
