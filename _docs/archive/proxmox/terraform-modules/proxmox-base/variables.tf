variable "pve" {
  description = "Proxmox VE connection + node inventory. `hosts` are the PVE node names the SDN zone is deployed to."
  type = object({
    endpoint = string
    password = string
    hosts    = list(string)
  })
  sensitive = true
}

variable "pve_api_token" {
  description = <<-EOT
    Phase-2 cutover token in the form `user@realm!tokenname=secret`. Leave empty
    to bootstrap as root@pam (Phase 1). Inject via TF_VAR_pve_api_token / op run
    after the automation token has been created and published to 1Password.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "op_service_account_token" {
  description = "1Password service account token with write access to the vault (same one terraform/dev uses to export kubeconfig)."
  type        = string
  sensitive   = true
}

variable "op_vault_id" {
  description = "1Password vault UUID for infrastructure secrets (where the automation token item is written and the admin password item is read)."
  type        = string
}

variable "admin" {
  description = <<-EOT
    Day-to-day Proxmox admin. granted the built-in PVEAdmin role at /. The
    password is READ from a pre-created 1Password item — never hardcoded — so it
    stays rotatable.
  EOT
  type = object({
    user_id       = optional(string, "admin@pve")
    op_item_title = string # 1P item holding the admin password
    comment       = optional(string, "Day-to-day admin (managed by terraform/proxmox-base)")
  })
}

variable "automation" {
  description = "Least-privilege Terraform automation principal (@pve) + API token that replaces root@pam in the provider blocks."
  type = object({
    user_id       = optional(string, "terraform@pve")
    role_id       = optional(string, "terraform")
    token_name    = optional(string, "tf")
    op_item_title = optional(string, "proxmox-terraform-token") # 1P item the token is written to
    comment       = optional(string, "Terraform automation (managed by terraform/proxmox-base)")
  })
  default = {}
}

variable "sdn" {
  description = <<-EOT
    EVPN SDN zone (ADR-0008 Option B) for the HA Talos cluster. A VXLAN overlay
    stretches L2 across all PVE hosts — restoring the Talos control-plane VIP and
    the Cilium L2 LoadBalancer design — with an anycast gateway + exit-node SNAT
    for egress. The control plane is a flat-L2 BGP-EVPN mesh: every PVE host peers
    directly over its management IP (evpn.peers) and uses that same IP as its VXLAN
    VTEP — no IGP/loopback underlay. (OpenFabric is point-to-point only and cannot
    mesh a shared LAN; see ADR-0008.) Use a subnet that does NOT overlap the LAN
    (192.168.20.0/24).
  EOT
  type = object({
    zone_id     = optional(string, "talos")  # PVE SDN id, max 8 chars
    vnet_id     = optional(string, "vtalos") # PVE SDN id, max 8 chars
    subnet_cidr = string                     # e.g. "10.30.0.0/24"
    gateway     = string                     # anycast gateway, e.g. "10.30.0.1"
    snat        = optional(bool, true)
    nodes       = optional(list(string)) # zone node set; defaults to var.pve.hosts
    mtu         = optional(number, 1450) # VXLAN overlay: 1500 underlay - 50B encap

    evpn = object({
      controller_id     = optional(string, "evpn")
      asn               = number                  # EVPN/underlay ASN (private 64512-65534)
      vrf_vxlan         = optional(number, 4000)  # VRF VNI — MUST differ from vnet_tag
      vnet_tag          = optional(number, 10300) # per-vnet VXLAN VNI
      exit_nodes        = list(string)            # PVE host(s) providing L3 egress + SNAT
      primary_exit_node = optional(string)        # active exit node; others standby
      advertise_subnets = optional(bool, true)

      # Flat-L2 BGP-EVPN: list every PVE host's management IP. Each node peers BGP
      # directly over the LAN and uses that IP as its VXLAN VTEP — no IGP/loopback
      # fabric (OpenFabric is point-to-point only and can't mesh a shared switch).
      peers = list(string) # PVE host mgmt IPs, e.g. ["192.168.20.6", ..., "192.168.20.11"]
    })
  })
  validation {
    condition     = can(cidrnetmask(var.sdn.subnet_cidr))
    error_message = "sdn.subnet_cidr must be a valid CIDR (e.g. 10.30.0.0/24)."
  }
  validation {
    condition     = cidrhost("${var.sdn.gateway}/${split("/", var.sdn.subnet_cidr)[1]}", 0) == cidrhost(var.sdn.subnet_cidr, 0)
    error_message = "sdn.gateway must be inside sdn.subnet_cidr."
  }
  validation {
    condition     = cidrhost(var.sdn.subnet_cidr, 0) != "192.168.20.0"
    error_message = "sdn.subnet_cidr must not reuse the LAN 192.168.20.0/24 — the overlay needs its own isolated subnet."
  }
  validation {
    condition     = var.sdn.evpn.vrf_vxlan != var.sdn.evpn.vnet_tag
    error_message = "sdn.evpn.vrf_vxlan (VRF VNI) must differ from sdn.evpn.vnet_tag (vnet VNI) — Proxmox rejects equal VNIs."
  }
  validation {
    condition     = length(var.sdn.evpn.exit_nodes) > 0
    error_message = "sdn.evpn.exit_nodes must list at least one PVE host for egress/SNAT."
  }
  validation {
    condition     = length(var.sdn.evpn.peers) > 0
    error_message = "sdn.evpn.peers must list at least one PVE host management IP for BGP-EVPN peering."
  }
  validation {
    condition     = alltrue([for p in var.sdn.evpn.peers : can(cidrhost("${p}/32", 0))])
    error_message = "Every sdn.evpn.peers entry must be a valid IPv4 address."
  }
}
