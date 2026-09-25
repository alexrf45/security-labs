# `ops-tier` — per-session entry, offense, and defense

The **per-session** root (ADR-0011 §5): the Tailscale subnet router, the attacker box,
and the collector/SIEM. Applied at the start of a session and **destroyed at teardown**
— nothing here is meant to run 24/7 (`cost-guardrails.md` rule 1). It discovers the
shared fabric from [`range-network`](../range-network/) **by tag** (never
`terraform_remote_state`).

> **State:** local, sensitive, gitignored. **Claude runs offline checks only.** The
> user runs `apply`/`destroy` under `op run --`.

## Cost — read the ephemeral caveat

`infracost breakdown` reports **≈ $54/mo because it assumes 730 running hours**. This
tier is ephemeral, so the real figure is the **per-hour rate**:

| Host | Type | $/hr |
| --- | --- | --- |
| router | t4g.micro | 0.0084 |
| attacker | t3.medium | 0.0416 |
| collector | t4g.medium | 0.0336 |
| **compute subtotal** | | **0.0836** |

Plus the router's public IPv4 (~$0.005/hr) and prorated gp3 root volumes → **~$0.71 per
8-hour session** for the ops tier. Treat the infracost monthly total as a
run-it-all-month worst case, not the expected bill.

> The collector is **t4g.medium (4 GB)**, not t4g.small: the single-node Wazuh stack
> (manager + OpenSearch indexer + dashboard) OOMs on 2 GB. The +$0.0168/hr is ~$0.13
> per 8h session. Override `collector_instance_type` if you run a lighter collector.

## Hosts

| Host | Image | Isolation-relevant config |
| --- | --- | --- |
| **router** | Ubuntu 24.04 arm64 | `source_dest_check=false`; IP forwarding; `tailscale up --advertise-routes=<ops CIDR> --accept-dns=false`; **advertises the ops subnet ONLY** (§4a); the one EIP |
| **attacker** | Kali amd64 (Marketplace) | no public IP; reached via the router's advertised route; attacker SG (any port into detonation); provisioned as the **SCRT** daily-driver + i3 desktop |
| **collector** | Ubuntu 24.04 arm64 | no public IP; collector SG (one-way telemetry in, never initiates into detonation); runs the **single-node Wazuh stack**; mounts the persistent SIEM volume |

All three: **IMDSv2 required, hop limit 1, no instance profile** (`range-safety.md` §5),
gp3 encrypted root volumes.

## Wazuh / SIEM provisioning

`scripts/collector-wazuh.sh.tftpl` (the collector's `user_data`) mounts the persistent
SIEM volume, installs the Wazuh single-node stack (manager on 1514/1515, dashboard on
443), and **relocates the indexer data and the manager's `/var/ossec/etc` (agent keys,
custom rules) onto the persistent volume** via bind mounts, so the detection index and
agent registrations survive teardown. Re-attaching an existing volume to a fresh
collector is the path to validate in a later sprint.

### Air-gapped agent installers (opt-in)

Detonation victims have no internet route, so they cannot fetch the Wazuh agent
themselves. Set **`enable_agent_package_mirror = true`** (here *and* in `range-network`,
which opens the one controlled det→collector port) and the collector mirrors the agent
installers — Windows `.msi`, Linux `.deb`, and (with `serve_sysmon`) Sysmon + a config —
over `agent_package_mirror_port`. Victims pull from that mirror and enroll. Without the
mirror (or a baked AMI), the manager stands up but no telemetry flows. This is the
`range-safety.md` §6 controlled, logged allow-list — **off by default**.

Key vars: `wazuh_version`, `wazuh_agent_pkg`, `enable_agent_package_mirror`,
`agent_package_mirror_port`, `serve_sysmon`.

## Attacker box — SCRT + i3 + tmux

`scripts/attacker-scrt.sh.tftpl` (the attacker's `user_data`) reproduces the operator's
**SCRT** daily-driver image ([github.com/alexrf45/SCRT](https://github.com/alexrf45/SCRT))
directly on the Kali host — SCRT is itself a Kali build defined by shell scripts, so the
box clones the repo and runs SCRT's own `sources/*.sh`:

- `0-base.sh` — apt tool suite (nmap, netexec, responder, evil-winrm, bloodhound.py, …).
- `1-tools.sh` — binaries into `~/.local/bin` (ffuf, sqlmap, chisel, PEASS, kerbrute via
  resources, nvim, …) + Ghostpack/nishang/powerview.
- `3-home.sh` — the **shell**: oh-my-zsh + `kali` theme, Starship prompt, `tmux.conf`
  (prefix `C-a`, tpm), fzf history, aliases and functions. zsh becomes the login shell.
- `2-tools.sh` (bug-bounty: httpx/subfinder/katana/…) is opt-in via
  `attacker_install_bugbounty`.

On top of SCRT it installs an **i3 desktop over xrdp** (`attacker_enable_gui`, default
true): i3 + i3status + dmenu + kitty + fonts, a minimal `~/.config/i3/config` (Super mod,
`Super+Return` → kitty, `Super+d` → dmenu), launched from `~/.xsession`. **tmux** ships
with SCRT. Reach the GUI by **RDP over Tailscale** (router → attacker:3389); the attacker
has no public IP and its SG accepts ingress only from the ops subnet.

The box has internet (routed ops subnet), so cloning and downloads work — expect a few
minutes of first-boot provisioning. Watch `/var/log/attacker-bootstrap.log`.

## Secrets

- `tailscale_auth_key` (**sensitive**) — never hardcoded; inject at apply time from
  1Password (`op run -- env TF_VAR_tailscale_auth_key="op://<vault>/<item>/authkey" ...`).
- `attacker_rdp_password` (**sensitive**, optional) — password for the `kali` user so
  xrdp/i3 can be logged into; inject the same way. Empty leaves the GUI installed but
  xrdp login unconfigured.

Both land in local state, which is treated as sensitive at rest (`secrets.md`).

## Prerequisites

- [`range-network`](../range-network/) applied (this root looks it up by tag).
- A one-time **Kali Marketplace subscription** on the account (ADR-0011 §6) — the only
  manual step. Verify `kali_ami_owner`/`kali_ami_name` against the current listing.

## Outputs

`router_public_ip` (entry is via Tailscale, not this address), `router_private_ip`,
`attacker_private_ip`, `collector_private_ip`.
