# Runbook — security lab: range setup & scenario lifecycle

**Scope:** stand up the segmentation foundation (Phase 0), then build, detonate,
roll back, and tear down scenarios. Real lab values throughout — internal runbook,
not the public guide.

> **Companion docs:** [bring-up runbook](security-lab-bring-up.md) (master Phase
> 0-2 checklist + progress/status — **start there**), [ADR-0009](../../../decisions/0009-security-lab-segmentation.md)
> (why VLAN zones + structural air-gap), `.claude/rules/lab-isolation.md` (the
> non-negotiable safety invariants — read before any change).

## Topology at a glance

| Thing | Value |
|---|---|
| PVE hosts | pve01–pve06, mgmt `192.168.20.6`–`.11` on `vmbr0` |
| Mgmt LAN | `192.168.20.0/24` (UCG-Ultra @ `192.168.20.1`) — **off-limits to detonation** |
| TrueNAS | `192.168.20.106` — admin data only, off-limits to detonation |
| Ops VLAN | 40 → vnet `vlabops` → `10.40.0.0/24`, gateway = UCG SVI (firewalled, WAN allow-list) |
| Detonation VLAN(s) | 50 → vnet `vdet00` → `10.50.0.0/24`, **no gateway (air-gap)** |
| SDN | VLAN zone `labvlan` on `vmbr0` — **no EVPN/overlay** (ADR-0009) |
| State | `range-network/` = S3; each `scenarios/<name>/` = local |

## How Terraform is run here

- Run **by you, manually, wrapped in the 1Password CLI** (`op run -- terraform …`).
  Claude does not run `plan`/`apply`. The op plugin makes bare `terraform` fail
  with `interactive IO not available` — that's expected.
- `terraform.tfvars` + `remote.tfbackend` are **SOPS-encrypted**: decrypt → edit →
  re-encrypt before committing. `pve.password` + tokens live there.
- Phase-2 token: `TF_VAR_pve_api_token = terraform@pve!tf=<secret>` (from
  `_infra/terraform/modules/proxmox-base`, in 1Password).

---

## Phase 0 — segmentation foundation

### 1. Proxmox prerequisite — `vmbr0` VLAN-aware (each node)

On every PVE node, `vmbr0` must be VLAN-aware so SDN VLAN tags pass. In the PVE UI:
*Node → System → Network → vmbr0 → VLAN aware = yes* (or set `bridge-vlan-aware yes`
+ `bridge-vids 2-4094` in `/etc/network/interfaces`, then `ifreload -a`). Verify:

```
# (talosctl/ssh to a node)
cat /sys/class/net/vmbr0/bridge/vlan_filtering   # 1 = VLAN-aware
```

### 2. UniFi — VLANs + trunks (click-ops; UniFi controller)

1. **Trunk** the 6 switch ports feeding pve01–pve06 to carry the lab VLANs (40, 50).
2. **Ops VLAN 40** (`10.40.0.0/24`): create the network **with** a gateway; firewall
   it — allow WAN (tool updates) but **DROP** to `192.168.20.0/24` (mgmt LAN) and to
   all `10.50.0.0/24`+ detonation subnets.
3. **Detonation VLAN 50** (`10.50.0.0/24`): create an **L2-only** network — **no
   gateway / no DHCP / no inter-VLAN routing**. This is what makes it air-gapped.
4. Repeat step 3 per additional detonation VLAN.

### 3. Apply the range network (Terraform)

```
cd _infra/terraform/security-lab/range-network
cp terraform.tfvars.example terraform.tfvars        # fill, SOPS-encrypt
cp remote.tfbackend.example  remote.tfbackend       # fill, SOPS-encrypt
terraform init -backend-config=remote.tfbackend
op run -- terraform plan
op run -- terraform apply
```

Creates the VLAN zone, the ops + detonation vnets, the firewall IPSets, and the
`det_isolation` security group. `enable_cluster_firewall` stays **false** here.

### 4. Verify the air-gap (Phase 0 gate — must pass before building scenarios)

Boot two throwaway Linux VMs on vnet `vdet00`, on **different** PVE nodes, static
IPs `10.50.0.250` / `10.50.0.251`:

```
# from 10.50.0.250
ping 10.50.0.251        # ✅ cross-node L2 over the trunk works
ping 192.168.20.1       # ✅ must FAIL (no gateway off the segment)
ping 192.168.20.106     # ✅ must FAIL (TrueNAS unreachable)
ping 1.1.1.1            # ✅ must FAIL (no internet)
ping 10.40.0.1          # ✅ must FAIL (ops net unreachable)
```

From an ops VM on `vlabops`: WAN allow-list reachable, `192.168.20.0/24` **not**.
Delete the throwaway VMs when done.

### 5. (Optional, guarded) enable the cluster-wide firewall

Only after step 4 passes and you accept the corosync risk:

1. Set `lab_firewall.enable_cluster_firewall = true`, `op run -- terraform apply`.
2. Immediately confirm mgmt + corosync on one node: `pvecm status`, SSH still works.
3. If anything degrades, revert to `false` and re-apply. Policies are pinned to
   ACCEPT, so this enables the framework without changing default forwarding;
   per-VM `det_isolation` rules do the enforcement.

---

## Scenario lifecycle (Phase 2+)

Each scenario is a **local-state** root under `_infra/terraform/security-lab/scenarios/<name>/`
that consumes the `scenario-vm` module and the `range-network` outputs.

| Step | Action |
|---|---|
| **Build** | `terraform init` (local backend) → `op run -- terraform apply`. Clones Packer templates onto **node-local** storage, attaches NICs to the detonation vnet, attaches `det_isolation`, takes a `clean-baseline` snapshot. |
| **Detonate** | Run the offensive technique / CVE from Kali (dual-homed) or deliver a payload. Detections land in Wazuh (Phase 3). |
| **Roll back** | `qm rollback <vmid> clean-baseline` (per VM) to re-run a CVE from a known state. |
| **Tear down** | `op run -- terraform destroy` in the scenario root. Node-local disks are reclaimed; nothing was on TrueNAS. |

**Before every scenario apply, re-check `.claude/rules/lab-isolation.md`** — no
gateway on detonation VLANs, disks node-local, `det_isolation` attached, telemetry
one-way.
