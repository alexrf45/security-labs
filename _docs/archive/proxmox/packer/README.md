# packer/ — security-lab golden images (Phase 1)

Builds reproducible Proxmox VM **templates** for the range. All templates live on
**node-local** storage (never TrueNAS — safety invariant 3, `.claude/rules/lab-isolation.md`)
and are later cloned + isolated by `terraform/modules/scenario-vm` (Phase 2).

Single directory, multiple sources — shared `variables.pkr.hcl` / `plugins.pkr.hcl`,
asset subdirs per template, built one at a time with `-only`.

| Source | Template | Notes |
| ------ | -------- | ----- |
| `proxmox-iso.ubuntu-base` | `tpl-ubuntu-2404` | Ubuntu 24.04, cloud-init + qemu-ga. Linux victims, ops Linux, Wazuh/web-CVE base. |
| `proxmox-iso.kali-attacker` | `tpl-kali` | Debian 12 netinst → kali-rolling (`kali-linux-headless`). The attacker box. |
| `proxmox-iso.windows-server-2022` | `tpl-win2022` | Server 2022 Desktop Experience. The AD domain controller. |
| `proxmox-iso.windows10` | `tpl-win10` | Win10 Pro workstation. |
| `proxmox-iso.windows11` | `tpl-win11` | Win11 Pro workstation (UEFI + TPM 2.0 + Secure Boot). |

## Prerequisites

1. `terraform/proxmox-base` applied — provides the `terraform@pve` API token. The
   token needs `VM.*`, `Datastore.AllocateSpace`/`Datastore.AllocateTemplate`,
   `Sys.Modify`, and `SDN.Use`.
2. `packer init .` once (installs the proxmox plugin v1.2.x).
3. **ISOs staged on the node-local `local` content store** of `proxmox_node`:
   - Linux: Packer downloads Ubuntu/Debian to PVE automatically (set the SHA256
     checksums in your var-file). Get them from the distro `SHA256SUMS`.
   - Windows: download once to *Datacenter → node → local → ISO Images* and
     reference as `local:iso/<file>`:
     - Windows Server 2022 **eval** ISO (microsoft.com/evalcenter)
     - Windows 10 + Windows 11 ISOs (microsoft.com/software-download)
     - **virtio-win** ISO (fedorapeople.org/groups/virt/virtio-win/)
4. A **build network with egress** (`build_bridge`, default `vmbr0`): the build VM
   needs DHCP + internet for package installs. **Never build on a detonation VLAN**
   (no gateway → the install can't reach the network and never finishes).

## Build

```bash
packer init .
cp build.pkrvars.hcl.example build.pkrvars.hcl     # fill in (SOPS-encrypt if committed)
op run -- packer build -var-file=build.pkrvars.hcl -only='proxmox-iso.ubuntu-base' .
# …repeat -only for kali-attacker, windows-server-2022, windows10, windows11
```

`packer validate .` works offline with dummy `-var` connection values.

## Windows build notes (expect light tuning)

Windows + Packer is environment-sensitive; these are the knobs:

- **Image name** — `windows/answer_files/autounattend.pkrtpl.xml` installs the
  edition named per template (`Windows Server 2022 SERVERSTANDARD`, `Windows 10 Pro`,
  `Windows 11 Pro`). If your ISO names the edition differently, edit the
  `image_name` in that template's `.pkr.hcl`. List names with
  `dism /Get-WimInfo /WimFile:<mount>\sources\install.wim`.
- **Reliability choices** — SATA disk + e1000 NIC use native Windows drivers, so
  Setup sees the disk and WinRM has network without injecting virtio mid-install.
  `windows/scripts/install-guest-tools.ps1` then installs qemu-ga + virtio drivers,
  so virtio devices work once `scenario-vm` clones the template.
- **Admin password** — the local Administrator password is templated from
  `winadmin_password` into the answer file so it always matches `winrm_password`.
  It is build-time only; Phase 2/3 provisioning rotates it.
- **boot_command** — `["<enter>…"]` dismisses "press any key to boot from CD". If a
  build hangs at the firmware screen, lengthen `boot_wait` / add `<enter>` presses.

## Safety

- Template disks + EFI/TPM state are pinned to `node_local_datastore` — keep it a
  node-local store. Vulnerability/scenario data never lands on TrueNAS.
- These templates are clean OS installs, not vulnerable hosts. Vulnerability is
  introduced per-scenario (Phase 2+) on the isolated detonation VLANs.
