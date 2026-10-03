# Ubuntu 24.04 base template — Linux victims, ops-side Linux hosts, and the base
# the Wazuh manager / web-CVE scenario VMs clone from. Cloud-init enabled so the
# scenario-vm module can set hostname/IP/users at clone time.
#
#   op run -- packer build -only='proxmox-iso.ubuntu-base' .

source "proxmox-iso" "ubuntu-base" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = var.insecure_skip_tls_verify
  node                     = var.proxmox_node

  vm_name                 = "tpl-ubuntu-2404"
  template_name           = "tpl-ubuntu-2404"
  template_description    = "Ubuntu 24.04 base (cloud-init + qemu-guest-agent). Built by packer/. Node-local disk."
  tags                    = "template;security-lab;linux"
  os                      = "l26"
  cores                   = 2
  memory                  = 2048
  scsi_controller         = "virtio-scsi-single"
  qemu_agent              = true
  cloud_init              = true
  cloud_init_storage_pool = var.node_local_datastore

  boot_iso {
    type             = "scsi"
    iso_url          = var.ubuntu_iso_url
    iso_checksum     = var.ubuntu_iso_checksum
    iso_storage_pool = var.iso_storage_pool
    iso_download_pve = true
    unmount          = true
  }

  disks {
    type         = "scsi"
    storage_pool = var.node_local_datastore
    disk_size    = "20G"
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

  http_directory = "ubuntu-base/http"

  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  communicator = "ssh"
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_timeout  = "30m"
}

build {
  name    = "ubuntu-base"
  sources = ["source.proxmox-iso.ubuntu-base"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S -E bash '{{ .Path }}'"
    inline = [
      "cloud-init status --wait || true",
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent cloud-init",
      "systemctl enable qemu-guest-agent",
      # Generalize for cloning: clear cloud-init, machine-id, ssh host keys, logs.
      "cloud-init clean --logs --seed",
      "rm -f /etc/netplan/50-cloud-init.yaml",
      "rm -f /etc/ssh/ssh_host_*",
      "truncate -s 0 /etc/machine-id",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*"
    ]
  }
}
