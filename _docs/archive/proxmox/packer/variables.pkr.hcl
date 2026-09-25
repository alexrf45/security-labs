# Shared variables for every template in this directory. Build with -only:
#   op run -- packer build -only='proxmox-iso.ubuntu-base' .
# Secrets (token, win admin pw) come from `op run` / a SOPS-decrypted var-file —
# never commit real values. Copy build.pkrvars.hcl.example to build.pkrvars.hcl.

# ── Proxmox connection ───────────────────────────────────────────────────────
variable "proxmox_url" {
  type    = string
  default = "" # e.g. "https://192.168.20.6:8006/api2/json"
}
variable "proxmox_node" {
  type    = string
  default = "pve01" # a single build node; templates are node-local to it
}
variable "proxmox_token_id" {
  type      = string
  default   = "" # e.g. "terraform@pve!tf" (an API token id with VM.* + Datastore.*)
  sensitive = true
}
variable "proxmox_token_secret" {
  type      = string
  default   = ""
  sensitive = true
}
variable "insecure_skip_tls_verify" {
  type    = bool
  default = true
}

# ── Storage & build network (SAFETY: node-local disks, egress build net) ──────
variable "iso_storage_pool" {
  type    = string
  default = "local" # node-local content store that holds ISOs
}
variable "node_local_datastore" {
  type    = string
  default = "local-lvm" # template disks land here — NEVER a TrueNAS-backed store
}
variable "build_bridge" {
  type    = string
  default = "vmbr0" # egress-capable network for the build. NEVER a detonation VLAN (no gateway = no install).
}
variable "build_vlan_tag" {
  type    = string
  default = "" # optional 802.1Q tag for the build NIC (e.g. "40" to build on the ops VLAN)
}

# ── Linux ISO sources (Packer has PVE download them) ─────────────────────────
variable "ubuntu_iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
}
variable "ubuntu_iso_checksum" {
  type    = string
  default = "none" # set to "sha256:<hash>" from releases.ubuntu.com/24.04/SHA256SUMS
}
variable "debian_iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso"
}
variable "debian_iso_checksum" {
  type    = string
  default = "none" # set to "sha256:<hash>" from the Debian SHA256SUMS
}

# ── Windows ISOs (pre-staged on the node-local content store) ────────────────
# Windows eval ISO download URLs are unstable + require accepting terms, so stage
# them once: download the eval ISO + virtio-win ISO to the PVE `local` store
# (Datacenter > node > local > ISO Images > Upload/Download URL), then reference
# them as "<store>:iso/<filename>". See packer/README.md.
variable "win2022_iso" {
  type    = string
  default = "local:iso/SERVER_EVAL_x64FRE_en-us.iso"
}
variable "win10_iso" {
  type    = string
  default = "local:iso/Win10_22H2_EnglishInternational_x64.iso"
}
variable "win11_iso" {
  type    = string
  default = "local:iso/Win11_24H2_EnglishInternational_x64.iso"
}
variable "virtio_iso" {
  type    = string
  default = "local:iso/virtio-win.iso"
}

# Build-time local Administrator password. Set via the WinRM communicator and the
# autounattend. Scenario provisioning (Phase 2) rotates/locks this; it is not a
# scenario secret. Override with a real value at build time.
variable "winadmin_password" {
  type      = string
  default   = "Pack3r-Build!"
  sensitive = true
}

# Sysmon config baked into the Windows templates at build time (detonation hosts
# are air-gapped and cannot download it at first boot). Pinned at build, so every
# clone ships with Sysmon already running — feeds the Phase 3 Wazuh pipeline.
variable "sysmon_config_url" {
  type    = string
  default = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"
}
