# `ops-tier` — per-session entry, offense, and defense

Tailscale subnet router, attacker box (SCRT + i3), and collector (single-node Wazuh).
Applied at the start of a session and destroyed at teardown. Discovers
[`range-network`](../range-network/) by tag.

Design rationale: [ADR-0011 §4–6](../../../../_docs/decisions/0011-aws-provider-and-range-topology.md).

> **State:** local, sensitive, gitignored. **Claude runs offline checks only**; the user
> runs `apply`/`destroy` under `op run --`.

## Hosts

| Host | Image | Notes |
| --- | --- | --- |
| **router** | Ubuntu 24.04 arm64 | `source_dest_check=false`, IP forwarding, advertises the **ops subnet only**; carries the range's single EIP |
| **attacker** | Kali amd64 (Marketplace) | No public IP. SCRT daily-driver build + i3 over xrdp (`:3389`) |
| **collector** | Ubuntu 24.04 **x86_64** | No public IP. Wazuh manager (1514/1515) + dashboard (443); mounts the persistent SIEM volume |

All three: IMDSv2 required, hop limit 1, no instance profile, gp3 encrypted root, and
`user_data_replace_on_change = true` (a changed bootstrap script replaces the host).

## Cost

Ephemeral, so read the per-hour rate — `infracost` reports ~$72/mo because it assumes 730
running hours.

| Host | Type | $/hr |
| --- | --- | --- |
| router | t4g.micro | 0.0084 |
| attacker | t3.medium | 0.0416 |
| collector | t3.medium | 0.0416 |
| **subtotal** | | **0.0916** |

Plus the router's public IPv4 (~$0.005/hr) and prorated root volumes → **~$0.83 per 8-hour
session**.

## Prerequisites

- [`range-network`](../range-network/) applied.
- One-time **Kali Marketplace subscription** on the account.
- `Security` listed in `~/.config/1Password/ssh/agent.toml`, or the agent will not offer
  the range SSH key.

## Usage

```console
$ op run -- terraform init
$ op run -- env \
    TF_VAR_tailscale_auth_key="op://Security/tailscale-range-router/authkey" \
    TF_VAR_attacker_rdp_password="op://Security/scrt-attacker/password" \
    TF_VAR_ssh_public_key="op://Security/security_labs/public key" \
    terraform apply
$ terraform output ssh
```

Add `TF_VAR_enable_agent_package_mirror=true` if it is enabled in `range-network`.

## Operator access

| Host | Access |
| --- | --- |
| router | `ssh ubuntu@<router_private_ip>`, or `tailscale ssh range-router` |
| attacker | `ssh kali@<attacker_private_ip>`; RDP `:3389` for i3 |
| collector | `ssh ubuntu@<collector_private_ip>`; dashboard `https://<collector_private_ip>` |

Reachable only through the Tailscale subnet router — port 22 is permitted from the ops
CIDR only, never `0.0.0.0/0`. The keypair is the `security_labs` SSH Key item in the
`Security` vault; only the public half reaches Terraform.

## Inputs and outputs

Full tables: [range reference](../../../../_docs/reference/aws-range-reference.md#ops-tier).
Outputs: `router_public_ip`, `router_private_ip`, `attacker_private_ip`,
`collector_private_ip`, `ssh`, `ssh_key_name`.

**Secrets** (all injected at apply, all land in local state):
`tailscale_auth_key`, `attacker_rdp_password`, and `ssh_public_key` (public half, not
sensitive). The two secrets also reach instance `user_data`, which any principal with
`ec2:DescribeInstanceAttribute` can read — rotate at teardown.

## What the bootstrap scripts do

- **`scripts/router.cloud-init.yaml.tftpl`** — installs Tailscale, advertises the ops
  CIDR, `--accept-dns=false`. The auth key is written to a `0600` tmpfs file and deleted
  after `tailscale up`, so it never appears in argv or the cloud-init log.
- **`scripts/collector-wazuh.sh.tftpl`** — waits up to 5 minutes for the SIEM volume
  (resolved by NVMe serial), installs the Wazuh all-in-one stack, then bind-mounts the
  indexer data and `/var/ossec/etc` onto the persistent volume so the index and agent
  keys survive teardown.
- **`scripts/attacker-scrt.sh.tftpl`** — clones [SCRT](https://github.com/alexrf45/SCRT)
  and runs its own `sources/*.sh` (tool suite, `~/.local/bin` binaries, zsh + tmux + fzf
  shell), then installs i3 over xrdp. `attacker_install_bugbounty` adds SCRT's
  `2-tools.sh`. Expect several minutes on first boot; watch
  `/var/log/attacker-bootstrap.log`.

### Air-gapped agent installers (opt-in)

Victims have no internet route, so they cannot fetch the Wazuh agent. Set
`enable_agent_package_mirror = true` here **and** in `range-network` and the collector
mirrors the installers (`.msi`, `.deb`, and Sysmon with `serve_sysmon`) on
`agent_package_mirror_port`. Without it the manager starts but no telemetry flows.
