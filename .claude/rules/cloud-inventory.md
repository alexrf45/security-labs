# Cloud Inventory & Operating Environment

Replaces the old on-prem `lab_architecture.md` (Proxmox/UniFi/TrueNAS hardware —
archived). This records the cloud-native environment the range now targets.

## Budget envelope

- **Hard ceiling: $30/month, all-in, across all providers.** See
  [cost-guardrails.md](cost-guardrails.md). Every design fits under this or it doesn't ship.

## Provider — AWS only (decided in ADR-0011, Accepted)

**AWS is the sole provider** ([ADR-0011](../../_docs/decisions/0011-aws-provider-and-range-topology.md)):
`us-east-1`, single-AZ, ephemeral by default, **zero always-on compute**. Standing cost
is storage-only (≈ $2.70/mo). Everything else is per-session and destroyed at teardown.

- **AWS** — license-included Windows AMIs (Windows first-class with no click-ops image
  build), `range-safety.md` invariants map 1:1 onto declarative attributes, native AWS
  Budgets, spot (incl. Windows). **No NAT gateway, no ALB, one EIP (router only)**
  ([cost-guardrails.md](cost-guardrails.md)). One provider, one bill, one credential path.
- **Hetzner — evaluated and REJECTED.** The ADR-0010 working assumption (CX22 ≈ €4.49/mo
  + a second provider for Windows) failed on research: the CX22 plan is gone and June
  2026 repricing moved plans +38%/+144%/+169% with no reliable grandfathering; Hetzner
  Windows is manual console ISO install only (no images, Arm can't run Windows); and it
  has no cost API to satisfy the mandatory budget-alarm rule. Do not reach for Hetzner.
- **Azure / GCP** — rejected: same license-included Windows model as AWS with no cost
  advantage and a third credential path for no capability gain.
- **Windows** is solved via license-included AWS AMIs + `user_data` — see ADR-0011 §6.

## Entry & connectivity

- **Tailscale is the mandated entrypoint** (not OpenVPN). A subnet router on the ops
  tier is the single human entry path; it doubles as controlled egress, replacing a
  NAT gateway and a public bastion. No SSH/RDP exposed to the public internet.
- Attacker access: SSH into a Kali/attacker box over Tailscale; RDP/VNC to Windows
  victims via the ops tier. A local **Nix** workstation is also used as an attacker
  environment (`_hack/nix/`).

## Secrets & tooling

- **1Password** is the secrets source of truth ([secrets.md](secrets.md)); SOPS for
  encrypted-in-repo files.
- Local toolchain present: `terraform`, `tflint`, `infracost`, `sops`, `age`, `aws`,
  `tailscale`, `op`, `gh`, `docker`, `jq`, `yamllint`, `direnv`. Absent and not needed
  (AWS-only, Packer deferred — ADR-0011): `packer`, `hcloud`, `az`, `gcloud`.

## What stays local

- The Nix attacker workstation, the age private key, and 1Password desktop/CLI live on
  the user's local machine — never provisioned into or reachable from a victim net
  ([range-safety.md](range-safety.md)).
