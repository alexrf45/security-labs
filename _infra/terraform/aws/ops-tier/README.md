# `ops-tier`

Tailscale subnet router, attacker box (SCRT + i3), and collector (single-node Wazuh).
Applied at the start of a session and destroyed at teardown. Discovers
[`range-network`](../range-network/) by tag.

## Hosts

| Host | Image | Notes |
| --- | --- | --- |
| **router** | Ubuntu 24.04 arm64 | `source_dest_check=false`, IP forwarding, advertises the **ops subnet only**; carries the range's single EIP |
| **attacker** | Kali amd64 (Marketplace) | No public IP. SCRT daily-driver build + i3 over xrdp (`:3389`) |
| **collector** | Ubuntu 24.04 **x86_64** | No public IP. Wazuh manager (1514/1515) + dashboard (443); mounts the persistent SIEM volume |


## Cost

| Host | Type | $/hr |
| --- | --- | --- |
| router | t4g.micro | 0.0084 |
| attacker | t3.medium | 0.0416 |
| collector | t3.medium | 0.0416 |
| **subtotal** | | **0.0916** |

## Prerequisites

- [`range-network`](../range-network/) applied.
- One-time **Kali Marketplace subscription** on the account.
- SSH key present in 1Password
## Usage

```console
$ cat .envrc          # gitignored; 1Password references only, never values
export TF_VAR_tailscale_auth_key="op://Security/tailscale-range-router/authkey"
export TF_VAR_attacker_rdp_password="op://Security/scrt-attacker/password"
export TF_VAR_ssh_public_key="op://Security/security_labs/public key"
export TF_VAR_wazuh_admin_password="op://Security/wazuh-dashboard/password"
$ direnv allow
$ op plugin run -- terraform init
$ op run -- op plugin run -- terraform apply
$ terraform output ssh
```

Don't put the references in the same command as `op run` (for example,
`op run -- env TF_VAR_x="op://…" terraform apply`). `op run` never sees them, and they
reach Terraform as literal strings.

Add `TF_VAR_enable_agent_package_mirror=true` if it is enabled in `range-network`.

## Operator access

| Host | Access |
| --- | --- |
| router | `tailscale ssh ubuntu@range-router` (edge subnet, not advertised) |
| attacker | `ssh kali@<attacker_private_ip>`; RDP `:3389` for i3 |
| collector | `ssh ubuntu@<collector_private_ip>`; dashboard `https://<collector_private_ip>` |


## Inputs and outputs

Full tables: [range reference](../../../../_docs/reference/aws-range-reference.md#ops-tier).
Outputs: `router_public_ip`, `router_private_ip`, `attacker_private_ip`,
`collector_private_ip`, `ssh`, `ssh_key_name`.

**Secrets** (all injected at apply, all land in local state):
`tailscale_auth_key`, `attacker_rdp_password`, and `ssh_public_key` (public half, not
sensitive). The two secrets also reach instance `user_data`, which any principal with
`ec2:DescribeInstanceAttribute` can read — rotate at teardown.

### Air-gapped agent installers (opt-in)

Victims have no internet route, so they cannot fetch the Wazuh agent. Set
`enable_agent_package_mirror = true` here **and** in `range-network` and the collector mirrors the installers (`.msi`, `.deb`, and Sysmon with `serve_sysmon`) on `agent_package_mirror_port`. Without it the manager starts but no telemetry flows.
