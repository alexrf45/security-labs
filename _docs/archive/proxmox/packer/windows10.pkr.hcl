# Windows 10 Pro workstation template for the AD detection lab. Same reliable build
# pattern as Server 2022 (SATA disk + e1000 NIC, UEFI + TPM, shared autounattend).
#
#   op run -- packer build -only='proxmox-iso.windows10' .

source "proxmox-iso" "windows10" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  node                     = var.proxmox_node

  vm_name              = "tpl-win10"
  template_name        = "tpl-win10"
  template_description = "Windows 10 Pro workstation (qemu-ga, virtio tools). Built by packer/. Node-local disk."
  tags                 = "template;security-lab;windows"
  os                   = "win10"
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

  boot_iso {
    type             = "ide"
    iso_file         = var.win10_iso
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  additional_iso_files {
    type  = "sata"
    index = "1"
    cd_content = {
      "autounattend.xml" = templatefile("windows/answer_files/autounattend.pkrtpl.xml", {
        image_name     = "Windows 10 Pro"
        admin_password = var.winadmin_password
      })
    }
    cd_label         = "PROVISION"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

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
  boot_command = ["<enter><wait><enter><wait><enter>"]
}

build {
  name    = "windows10"
  sources = ["source.proxmox-iso.windows10"]

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
      "wevtutil el | ForEach-Object { wevtutil cl \"$_\" 2>$null }"
    ]
  }
}
