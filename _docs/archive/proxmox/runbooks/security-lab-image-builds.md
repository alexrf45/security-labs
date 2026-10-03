# Runbook — security lab image builds (Phase 1, Packer)

Build the node-local golden templates the range clones from. Operational detail
beyond `_infra/packer/README.md`. Internal runbook.

> **Companion:** [bring-up runbook](security-lab-bring-up.md) (ordered Phases 0-2),
> `_infra/packer/README.md` (per-template reference), `.claude/rules/lab-isolation.md`
> (safety invariant 3 — templates are node-local, never TrueNAS).

## Templates

| `-only` source | Template | Base | Notes |
|---|---|---|---|
| `proxmox-iso.ubuntu-base` | `tpl-ubuntu-2404` | Ubuntu 24.04 | cloud-init + qemu-ga; base for ops Linux, Wazuh, web-CVE |
| `proxmox-iso.kali-attacker` | `tpl-kali` | Debian 12 netinst | → kali-rolling (`kali-linux-headless`) |
| `proxmox-iso.windows-server-2022` | `tpl-win2022` | Server 2022 eval | DC; Sysmon + cloudbase-init baked |
| `proxmox-iso.windows10` | `tpl-win10` | Win10 Pro | workstation |
| `proxmox-iso.windows11` | `tpl-win11` | Win11 Pro | workstation; UEFI+TPM+Secure Boot |

## Prerequisites

1. `_infra/terraform/modules/proxmox-base` applied → the `terraform@pve` API token (needs `VM.*`,
   `Datastore.AllocateSpace`/`AllocateTemplate`, `Sys.Modify`, `SDN.Use`).
2. **Build network with egress** (`build_bridge`, default `vmbr0`): the build VM
   needs DHCP + internet. **Never build on a detonation VLAN** (no gateway → the
   install can't finish).
3. **ISOs on the node-local `local` content store** of `proxmox_node`:
   - Windows Server 2022 **eval**, Win10, Win11 (microsoft.com).
   - **virtio-win** ISO (fedorapeople virtio-win).
   - Linux: Packer downloads Ubuntu/Debian to PVE itself — set the SHA256 checksums.

## Build

```bash
cd _infra/packer
packer init .
cp build.pkrvars.hcl.example build.pkrvars.hcl     # fill; SOPS-encrypt if committed
# Linux first (fast, no manual ISO):
op run -- packer build -var-file=build.pkrvars.hcl -only='proxmox-iso.ubuntu-base' .
op run -- packer build -var-file=build.pkrvars.hcl -only='proxmox-iso.kali-attacker' .
# Windows (need staged ISOs):
op run -- packer build -var-file=build.pkrvars.hcl -only='proxmox-iso.windows-server-2022' .
op run -- packer build -var-file=build.pkrvars.hcl -only='proxmox-iso.windows10' .
op run -- packer build -var-file=build.pkrvars.hcl -only='proxmox-iso.windows11' .
```

`packer validate .` works offline with dummy `-var` connection values.

## What each Windows build does

Clean install via the shared `windows/answer_files/autounattend.pkrtpl.xml`, then
provisioners: install qemu-ga + virtio guest tools → reboot → install
**cloudbase-init** (consumes the Proxmox cloud-init drive on a clone's first boot)
→ install **Sysmon** with the config (baked because detonation hosts are
air-gapped) → clear event logs. Result: a generalized template that, when cloned,
sets its hostname/IP/domain config and runs first-boot PowerShell.

## Windows troubleshooting (expect light tuning — inherent to Windows+Packer)

| Symptom | Fix |
|---|---|
| Setup can't find the edition / wrong edition | The image name must match your ISO. Edit `image_name` in the template's `.pkr.hcl` (`windows-server-2022 / windows10 / windows11`). List names: `dism /Get-WimInfo /WimFile:<mnt>\sources\install.wim`. |
| Hangs at firmware / "press any key" | Lengthen `boot_wait` or add `<enter>` presses in `boot_command`. |
| WinRM never connects | Check the VM console: did the autounattend FirstLogonCommands enable WinRM? Confirm `winadmin_password` == the rendered Administrator password. |
| No disk during Setup | We use SATA disk on purpose (native driver). Don't switch to virtio-scsi unless you add the vioscsi `DriverPaths` to the autounattend. |
| qemu-ga not reporting IP after clone | guest tools install failed — check the virtio-win ISO was mounted (`var.virtio_iso`). |

## Verify

- `tpl-ubuntu-2404`, `tpl-kali`, `tpl-win2022`, `tpl-win10`, `tpl-win11` exist as
  templates on the **node-local** store of `proxmox_node`.
- Test-clone one of each: boots, qemu-ga reports an IP. Windows: Sysmon service
  running (`Get-Service Sysmon64`), cloudbase-init present.
- Record the **vmids** → `_infra/terraform/security-lab/scenarios/ad-detection/terraform.tfvars`.
