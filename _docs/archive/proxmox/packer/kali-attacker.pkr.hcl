# Kali attacker box — built from a Debian 12 netinst, then converted to Kali by
# adding the Kali rolling repo + kali-linux-headless metapackage (per the
# native-IaC decision; no prebuilt image import). Lives on the OPS net when cloned;
# dual-homed into a detonation vnet by the scenario root.
#
#   op run -- packer build -only='proxmox-iso.kali-attacker' .

source "proxmox-iso" "kali-attacker" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  node                     = var.proxmox_node

  vm_name                 = "tpl-kali"
  template_name           = "tpl-kali"
  template_description    = "Kali (Debian 12 netinst + kali-rolling, qemu-guest-agent). Built by packer/. Node-local disk."
  tags                    = "template;security-lab;offensive"
  os                      = "l26"
  cores                   = 2
  memory                  = 4096
  scsi_controller         = "virtio-scsi-single"
  qemu_agent              = true
  cloud_init              = true
  cloud_init_storage_pool = var.node_local_datastore

  boot_iso {
    type             = "scsi"
    iso_url          = var.debian_iso_url
    iso_checksum     = var.debian_iso_checksum
    iso_storage_pool = var.iso_storage_pool
    iso_download_pve = true
    unmount          = true
  }

  disks {
    type         = "scsi"
    storage_pool = var.node_local_datastore
    disk_size    = "40G"
    format       = "raw"
    ssd          = true
    discard      = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.build_bridge
    vlan_tag = var.build_vlan_tag
    firewall = false
  }

  http_directory = "kali-attacker/http"

  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "install <wait>",
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>",
    "debian-installer=en_US.UTF-8 auto locale=en_US.UTF-8 <wait>",
    "keymap=us <wait>",
    "netcfg/get_hostname=kali <wait>",
    "netcfg/get_domain=lab <wait>",
    "fb=false debconf/frontend=noninteractive <wait>",
    "console-setup/ask_detect=false <wait>",
    "<enter>"
  ]

  communicator = "ssh"
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_timeout  = "40m"
}

build {
  name    = "kali-attacker"
  sources = ["source.proxmox-iso.kali-attacker"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S -E bash '{{ .Path }}'"
    script          = "kali-attacker/scripts/install-kali.sh"
  }
}
