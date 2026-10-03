variable "pve" {
  description = "Proxmox VE connection + node inventory. `hosts` are the PVE node names the VLAN zone is deployed to."
  type = object({
    endpoint = string
    password = string
    hosts    = list(string)
  })
  sensitive = true
}

variable "pve_api_token" {
  description = <<-EOT
    Phase-2 cutover token `user@realm!tokenname=secret` (terraform@pve, created by
    _infra/terraform/modules/proxmox-base). Leave empty to bootstrap as root@pam. Inject via
    TF_VAR_pve_api_token / `op run`.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "lab_sdn" {
  description = <<-EOT
    VLAN-zone segmentation for the security range (ADR-0009). A Proxmox SDN VLAN
    zone tags each vnet's traffic onto `bridge` (vmbr0) with a VLAN id; the zone
    provides NO gateway. Air-gap is therefore STRUCTURAL: detonation VLANs simply
    have no SVI on the UniFi side and no Proxmox subnet, so a victim has no L3
    next-hop off its segment. The ops VLAN's gateway lives on the UCG (firewalled,
    WAN allow-list only) — never defined here. EVPN is intentionally NOT used (it
    never worked on this hardware; see ADR-0008/0009).
  EOT
  type = object({
    bridge  = optional(string, "vmbr0")
    zone_id = optional(string, "labvlan") # PVE SDN id, max 8 chars
    nodes   = optional(list(string))      # zone node set; defaults to var.pve.hosts
    mtu     = optional(number, 1500)      # native VLAN, no overlay encap overhead

    ops = object({
      vnet_id = optional(string, "vlabops") # bridge VMs attach to; max 8 chars
      vlan    = number                      # 802.1Q tag, e.g. 40
    })

    # One entry per detonation network (scenario short-name => vnet). Each is a
    # gateway-less L2 island on its own VLAN tag. Add a key to stand up another
    # isolated scenario net.
    detonation = map(object({
      vnet_id = string # bridge VMs attach to; max 8 chars, e.g. "vdet00"
      vlan    = number # 802.1Q tag, e.g. 50
    }))
  })

  validation {
    condition     = length(var.lab_sdn.zone_id) <= 8
    error_message = "lab_sdn.zone_id must be <= 8 chars (Proxmox SDN id limit)."
  }
  validation {
    condition     = length(var.lab_sdn.ops.vnet_id) <= 8 && alltrue([for d in var.lab_sdn.detonation : length(d.vnet_id) <= 8])
    error_message = "Every vnet_id must be <= 8 chars (Proxmox SDN id limit)."
  }
  validation {
    condition     = var.lab_sdn.ops.vlan >= 1 && var.lab_sdn.ops.vlan <= 4094 && alltrue([for d in var.lab_sdn.detonation : d.vlan >= 1 && d.vlan <= 4094])
    error_message = "Every VLAN tag must be in 1-4094."
  }
  validation {
    condition     = !contains([for d in var.lab_sdn.detonation : d.vlan], var.lab_sdn.ops.vlan)
    error_message = "The ops VLAN must not collide with any detonation VLAN."
  }
}

variable "lab_firewall" {
  description = <<-EOT
    Datacenter firewall baseline for the range. IPSets + a reusable `det-isolation`
    security group are always created (inert until a scenario VM references the
    group AND the firewall is enabled). `enable_cluster_firewall` is OFF by default:
    turning on the CLUSTER-WIDE firewall touches every live PVE node (corosync), so
    it is a deliberate, runbook-guarded step — flip it only after verifying mgmt
    connectivity on one node. Policies are pinned to ACCEPT so enabling the
    framework never silently drops traffic; per-VM DROP rules do the enforcement.
  EOT
  type = object({
    enable_cluster_firewall = optional(bool, false)
    mgmt_cidr               = optional(string, "192.168.20.0/24") # management LAN — never reachable from detonation
    ops_cidr                = optional(string, "10.40.0.0/24")    # ops net — not reachable from detonation
    det_cidrs               = list(string)                        # all detonation subnets (for the IPSet record)
  })
}
