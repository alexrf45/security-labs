# Windows Server 2022 (Desktop Experience) template — the AD domain controller for
# the detection lab. Built for RELIABILITY over performance: SATA disk + e1000 NIC
# use Windows' native drivers, so Setup sees the disk and WinRM has network without
# injecting virtio drivers mid-install. The virtio guest tools (incl. qemu-ga and
# NetKVM) are installed post-setup, so virtio NICs work once cloned. UEFI + TPM for
# Credential Guard / BitLocker detection realism.
#
#   op run -- packer build -only='proxmox-iso.windows-server-2022' .
#
# NOTE: Windows builds commonly need per-ISO tuning — the image NAME in
# answer_files/autounattend.xml (e.g. "Windows Server 2022 SERVERSTANDARD") must
# match your eval ISO, and boot_command timing may need adjusting. See README.

source "proxmox-iso" "windows-server-2022" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  node                     = var.proxmox_node

  vm_name              = "tpl-win2022"
  template_name        = "tpl-win2022"
  template_description = "Windows Server 2022 Desktop Experience (qemu-ga, virtio tools). Built by packer/. Node-local disk."
  tags                 = "template;security-lab;windows"
  os                   = "win11"
  cores                = 2
  memory               = 4096
  machine              = "q35"
  bios                 = "ovmf"
  qemu_agent           = true

  efi_config {
    efi_storage_pool  = var.node_local_datastore
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  tpm_config {
    tpm_storage_pool = var.node_local_datastore
    tpm_version      = "v2.0"
  }

  # Windows install media — IDE so "press any key to boot from CD" works natively.
  boot_iso {
    type             = "ide"
    iso_file         = var.win2022_iso
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # autounattend.xml — rendered from the shared template (image name + admin pw
  # kept in sync with winrm_password) and placed at the CD root, where Windows
  # Setup auto-discovers it.
  additional_iso_files {
    type  = "sata"
    index = "1"
    cd_content = {
      "autounattend.xml" = templatefile("windows/answer_files/autounattend.pkrtpl.xml", {
        image_name     = "Windows Server 2022 SERVERSTANDARD"
        admin_password = var.winadmin_password
      })
    }
    cd_label         = "PROVISION"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # virtio-win drivers + qemu guest agent, installed by the post-setup provisioner.
  additional_iso_files {
    type             = "sata"
    index            = "2"
    iso_file         = var.virtio_iso
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  disks {
    type         = "sata"
    storage_pool = var.node_local_datastore
    disk_size    = "60G"
    format       = "raw"
    ssd          = true
    discard      = true
  }

  network_adapters {
    model    = "e1000"
    bridge   = var.build_bridge
    vlan_tag = var.build_vlan_tag
    firewall = false
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.winadmin_password
  winrm_timeout  = "2h"
  winrm_use_ssl  = false
  winrm_insecure = true

  boot_wait    = "4s"
  boot_command = ["<enter><wait><enter><wait><enter>"] # dismiss "press any key to boot from CD"
}

build {
  name    = "windows-server-2022"
  sources = ["source.proxmox-iso.windows-server-2022"]

  provisioner "powershell" {
    script = "windows/scripts/install-guest-tools.ps1"
  }
  provisioner "windows-restart" {}
  provisioner "powershell" {
    script = "windows/scripts/install-cloudbase-init.ps1"
  }
  provisioner "powershell" {
    script           = "windows/scripts/install-sysmon.ps1"
    environment_vars = ["SYSMON_CONFIG_URL=${var.sysmon_config_url}"]
  }
  provisioner "powershell" {
    inline = [
      "Write-Host 'Clearing event logs for a clean template'",
      "wevtutil el | ForEach-Object { wevtutil cl \"$_\" 2>$null }"
    ]
  }
}
