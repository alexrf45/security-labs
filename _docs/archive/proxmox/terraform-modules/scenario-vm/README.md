# module: scenario-vm

Clones a Packer golden template into an isolated scenario VM: node-local disk,
attached to a detonation/ops vnet, first-boot config via cloud-init (Linux) /
cloudbase-init (Windows), and — for victims — the `det_isolation` firewall group.

Consumed by `_infra/terraform/security-lab/scenarios/<name>/` roots (local state).

## Safety properties enforced

- **Disks node-local**: `clone.datastore_id = node_local_datastore`, validated to
  reject TrueNAS/iSCSI/NFS stores (safety invariant 3).
- **Structural air-gap**: detonation NICs get no `gateway`; the vnet itself has no
  Proxmox/UCG gateway. `det_isolation` is the redundant per-VM layer.
- **Dual-homing**: give an ops box (attacker/collector) two `networks` (ops + det)
  and set `isolate = false` so it keeps ops connectivity.

## Inputs (highlights)

| Input | Purpose |
| ----- | ------- |
| `scenario` | name → VM tags + snippet filenames |
| `template_node` | node where Packer templates live (clone source) |
| `node_local_datastore` | cloned disks (node-local only) |
| `snippet_datastore` | snippets-enabled store for first-boot user-data |
| `hosts` | map of VMs: node, role, os_type, template_id, networks[], `isolate`, `user_data` |
| `ci_user` | Administrator password (Windows) / user (Linux) |
| `dns` | resolver + AD domain (point workstations at the DC) |
| `isolation` | master firewall switch + det_isolation group name |

## Outputs

`vm_ids` (for `qm snapshot <id> clean-baseline`), `names`, `addresses`, `isolated`.

## Prerequisites

- Packer templates built (Phase 1) and their vmids known.
- `snippet_datastore` has the **snippets** content type enabled
  (*Datacenter → Storage → local → Content → Snippets*).
- `range-network` applied (provides the vnets + `det_isolation` group).

## Note on clean-baseline snapshots

bpg has no snapshot resource. After apply, snapshot each VM for CVE rollback:
`qm snapshot <vmid> clean-baseline` (see the scenario-lifecycle runbook).
