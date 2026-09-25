# Runbook — security lab bring-up (Phases 0-2) & progress tracker

Master entry point for the security research range. Walks the ordered bring-up
(Phase 0 → 1 → 2) with verification gates, and records build status so a new
session can pick up cleanly. Real lab values; internal runbook.

> **Companion docs:** [ADR-0009](../../../decisions/0009-security-lab-segmentation.md)
> (design), `.claude/rules/lab-isolation.md` (safety invariants — read first),
> [scenario-lifecycle runbook](security-lab-scenario-lifecycle.md) (Phase 0 detail +
> scenario loop), [image-builds runbook](security-lab-image-builds.md) (Phase 1).

## Status (as of 2026-06-11)

Phases 0-2 are **built in-repo and `terraform/packer validate` clean, but NOT yet
applied/built** on the cluster. Nothing below has been deployed.

| Phase | Deliverable                                                        | In repo      | Applied?       |
| ----- | ------------------------------------------------------------------ | ------------ | -------------- |
| 0     | VLAN segmentation (`_infra/terraform/security-lab/range-network/`) | ✅ validated | ❌             |
| 1     | Packer templates (`_infra/packer/`)                                | ✅ validated | ❌ (not built) |
| 2     | `scenario-vm` module + `ad-detection` lab                          | ✅ validated | ❌             |
| 3     | Wazuh defensive stack                                              | —            | **next**       |
| 4     | Offensive tooling + C2                                             | —            | pending        |
| 5     | Web/CVE workbench                                                  | —            | pending        |

**Pick up at Phase 3 (Wazuh)** once Phases 0-2 are deployed and the AD lab is live
(detections need a real domain to fire against).

## How Terraform/Packer run here

Wrapped in the 1Password CLI, by you, manually: `op run -- terraform apply`,
`op run -- packer build ...`. Bare `terraform`/`packer` under the op plugin fail
with `interactive IO not available`. `terraform.tfvars` / `remote.tfbackend` /
`build.pkrvars.hcl` are SOPS-encrypted: decrypt → edit → re-encrypt before commit.

---

## Phase 0 — segmentation foundation

Full detail in the [scenario-lifecycle runbook](security-lab-scenario-lifecycle.md).
Summary + gate:

1. **Proxmox:** `vmbr0` VLAN-aware on every node (`vlan_filtering=1`).
2. **UniFi:** trunk VLANs 40/50 to the PVE ports; ops VLAN 40 = firewalled gateway
   (WAN allow-list, **no** route to `192.168.20.0/24`); detonation VLAN 50 = L2-only,
   **no gateway/DHCP/SVI**.
3. **Enable `snippets`** content type on the node-local `local` store (needed in
   Phase 2 for cloud-init user-data).
4. `cd _infra/terraform/security-lab/range-network` → fill + SOPS-encrypt `terraform.tfvars`
   - `remote.tfbackend` → `terraform init -backend-config=remote.tfbackend` →
     `op run -- terraform apply`. Keep `enable_cluster_firewall = false`.

**GATE — air-gap test (must pass before Phase 2):** two throwaway VMs on `vdet00`
on **different** PVE nodes: they reach each other; neither reaches `192.168.20.1`,
`192.168.20.106`, the internet, or `10.40.0.0/24`. Delete them after.

## Phase 1 — golden images

Full detail in the [image-builds runbook](security-lab-image-builds.md). Summary:

1. Stage ISOs on `local`: Windows Server 2022 eval, Win10, Win11, **virtio-win**
   (Linux ISOs are auto-downloaded by Packer — set the checksums).
2. `cd _infra/packer` → `packer init .` → fill `build.pkrvars.hcl` → build each template:
   `op run -- packer build -only='proxmox-iso.<name>' .` (ubuntu-base, kali-attacker,
   windows-server-2022, windows10, windows11).
3. **GATE:** each `tpl-*` exists on the node-local store, `qemu_agent` reports an IP
   when cloned, and Windows templates have Sysmon running + cloudbase-init installed.
   Record the template **vmids** for Phase 2.

## Phase 2 — AD detection lab

Full detail in `_infra/terraform/security-lab/scenarios/ad-detection/README.md`. Summary:

1. `cd _infra/terraform/security-lab/scenarios/ad-detection` → fill `terraform.tfvars`
   (template vmids, placement, passwords) → `terraform init` (local backend) →
   `op run -- terraform apply`.
2. First boot (~15-20 min) promotes the forest, seeds the misconfigs
   (Kerberoast/AS-REP/GenericAll), joins WS10/WS11. Check `C:\ProgramData\lab\*.log`.
3. **Snapshot baselines** for CVE rollback (bpg has no snapshot resource — do it by
   hand on each owning node):

   ```bash
   qm snapshot <vmid> clean-baseline
   ```

4. **GATE:** from Kali (`10.50.0.50`) enumerate the domain and run a Kerberoast;
   confirm Kali reaches the victims but NOT the mgmt LAN / TrueNAS / ops subnet.

---

## Next session — Phase 3 (Wazuh) starting points

- Build a Wazuh manager VM on the **ops** net (clone `tpl-ubuntu-2404`), dual-homed
  with a second NIC on `vdet00` (set `isolate = false` in a `scenario-vm` call, like
  Kali). Its detonation-side IP is the only endpoint victims may reach off-subnet.
- Windows agents already have Sysmon (baked in Phase 1). Add Wazuh agent enrollment
  to the bootstrap user-data, pointing at the collector's **detonation-side IP**.
  Telemetry is one-way det → collector (safety invariant 4).
- Decide enrollment method (pre-shared key vs authd) and dashboards; optionally
  forward to the existing Grafana/Loki.
