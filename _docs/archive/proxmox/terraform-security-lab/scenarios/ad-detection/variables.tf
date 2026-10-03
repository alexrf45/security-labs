# ── Proxmox connection (token via op run) ────────────────────────────────────
variable "pve_endpoint" {
  type    = string
  default = "192.168.20.6"
}
variable "pve_password" {
  type      = string
  default   = ""
  sensitive = true
}
variable "pve_api_token" {
  type      = string
  default   = ""
  sensitive = true
}

# ── Placement + templates ────────────────────────────────────────────────────
variable "template_node" {
  description = "PVE node holding the Packer templates (clone source)."
  type        = string
  default     = "pve01"
}
variable "node_local_datastore" {
  type    = string
  default = "local-lvm"
}
variable "snippet_datastore" {
  type    = string
  default = "local"
}
variable "templates" {
  description = "Packer template vmids to clone."
  type = object({
    win2022 = number
    win10   = number
    win11   = number
    kali    = number
  })
}
variable "placement" {
  description = "Which PVE node each scenario VM runs on (cross-node clone is supported; same-node is faster)."
  type = object({
    dc   = optional(string, "pve01")
    ws10 = optional(string, "pve02")
    ws11 = optional(string, "pve03")
    kali = optional(string, "pve01")
  })
  default = {}
}

# ── Network (from range-network: detonation + ops vnets, isolation group) ─────
variable "det_vnet" {
  description = "Detonation vnet bridge (gateway-less L2 island)."
  type        = string
  default     = "vdet00"
}
variable "ops_vnet" {
  description = "Ops vnet bridge (Kali's ops-side NIC)."
  type        = string
  default     = "vlabops"
}
variable "det_isolation_security_group" {
  type    = string
  default = "det_isolation"
}

# ── AD design (intentionally attackable) ─────────────────────────────────────
variable "ad" {
  description = "Domain layout + planted misconfigurations for the detection lab."
  type = object({
    domain_fqdn   = optional(string, "lab.local")
    dc_ip         = optional(string, "10.50.0.10")
    ws10_ip       = optional(string, "10.50.0.20")
    ws11_ip       = optional(string, "10.50.0.21")
    kali_det_ip   = optional(string, "10.50.0.50")
    subnet_prefix = optional(number, 24)
  })
  default = {}
}

variable "local_admin_password" {
  description = "Local Administrator password seeded by cloudbase-init (== the Packer build password unless rotated). Build-time/lab credential."
  type        = string
  sensitive   = true
}
variable "domain_admin_password" {
  description = "Domain Administrator / DSRM password set during DC promotion."
  type        = string
  sensitive   = true
}
variable "seed_user_password" {
  description = "Weak password for the planted domain users (Kerberoast/AS-REP targets) — intentionally crackable for the lab."
  type        = string
  default     = "Summer2026!"
  sensitive   = true
}
# Sysmon is baked into the Windows templates at Packer build time (detonation hosts
# are air-gapped) — it is configured in packer/, not here.
