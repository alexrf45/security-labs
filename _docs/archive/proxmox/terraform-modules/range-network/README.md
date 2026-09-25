# range-network — security-lab shared segmentation (Phase 0)

Shared, persistent network foundation for the security research range. Owns the
Proxmox SDN **VLAN zone**, the per-scenario **vnets** (ops + detonation), and the
datacenter **firewall baseline** (IPSets + `det_isolation` security group). S3
remote state. See `_docs/decisions/0009-security-lab-segmentation.md` (ADR) and
`_docs/runbooks/security-lab-scenario-lifecycle.md` (operations).

## Prerequisites (UniFi + Proxmox — manual, documented in the runbook)

1. `vmbr0` is VLAN-aware on every PVE node.
2. UniFi switch ports to the 6 PVE nodes are **trunks** carrying the lab VLANs (40, 50, …).
3. UniFi: create the **ops** VLAN (40) network with a gateway — WAN
   allow-list only, **no** route to `192.168.20.0/24`.
   VLAN (50, …) as an L2-only network with **no gateway/SVI**.
4. `_infra/terraform/modules/proxmox-base` already applied (provides the `terraform@pve` token).

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars        # fill in, then SOPS-encrypt
cp remote.tfbackend.example  remote.tfbackend       # fill in, then SOPS-encrypt
terraform init -backend-config=remote.tfbackend
op run -- terraform plan      # TF_VAR_pve_api_token = terraform@pve!tf=<secret>
op run -- terraform apply
```

`enable_cluster_firewall` stays **false** until you have read the runbook and
verified mgmt connectivity — turning on the cluster-wide firewall touches every
live node (corosync). The IPSets + security group are created either way and are
inert until a scenario VM references them.

## Outputs (consumed by scenario roots)

| Output                         | Use                                                      |
| ------------------------------ | -------------------------------------------------------- |
| `ops_vnet_bridge`              | NIC bridge for ops-side interfaces (Kali/Wazuh primary). |
| `detonation_vnet_bridges`      | `{scenario => bridge}`; victim + dual-homed NICs.        |
| `det_isolation_security_group` | attached to every VM by `scenario-vm`.                   |

## Verification (Phase 0 gate)

Boot two throwaway VMs on `vdet00`, placed on **different** PVE nodes:

- ✅ they reach each other (cross-node L2 over the trunk works)
- ✅ neither can reach `192.168.20.1`, `192.168.20.106` (TrueNAS), the internet, or `10.40.0.0/24`
- ✅ an ops VM reaches the WAN allow-list only, with no route to the mgmt LAN
