variable "scenario" {
  description = "Short scenario name; used in VM tags and cloud-init snippet filenames (e.g. \"ad-detection\")."
  type        = string
}

variable "template_node" {
  description = "PVE node where the Packer templates live (templates are node-local). Used as the clone source node."
  type        = string
}

variable "node_local_datastore" {
  description = "Node-local datastore for cloned disks + cloud-init drive. MUST be node-local — never a TrueNAS-backed store (safety invariant 3)."
  type        = string
  default     = "local-lvm"

  validation {
    condition     = !can(regex("(?i)truenas|iscsi|nfs", var.node_local_datastore))
    error_message = "node_local_datastore must be node-local; a TrueNAS/iSCSI/NFS store would put vulnerability data on the NAS (forbidden)."
  }
}

variable "snippet_datastore" {
  description = "Datastore with the `snippets` content type enabled (node-local), used to upload per-host cloud-init/cloudbase-init user-data."
  type        = string
  default     = "local"
}

variable "cpu_type" {
  description = "vCPU type. `host` passes the physical CPU through (best for nested AD/Windows on the identical Beelink nodes)."
  type        = string
  default     = "host"
}

variable "ci_user" {
  description = "Cloud-init / cloudbase-init account. On Windows this sets the local Administrator password; on Linux it creates the user."
  type = object({
    username = optional(string, "Administrator")
    password = optional(string)
    keys     = optional(list(string), [])
  })
  sensitive = true
}

variable "isolation" {
  description = "Per-VM firewall enforcement. The det_isolation security group (range-network output) DROPs egress to mgmt LAN + ops net — belt-and-suspenders behind the gateway-less detonation VLAN."
  type = object({
    enable_firewall              = optional(bool, true)
    det_isolation_security_group = optional(string, "det_isolation")
  })
  default = {}
}

variable "hosts" {
  description = <<-EOT
    Scenario VMs. Each clones a Packer template onto node-local storage, attaches to
    the given vnet(s), and (optionally) runs first-boot user-data. Put victims on a
    detonation vnet (no gateway). Dual-home an ops box (attacker/collector) by giving
    it two networks — one ops, one detonation.
  EOT
  type = map(object({
    node        = string # target PVE node
    role        = string # dc | workstation | attacker | victim | collector
    os_type     = string # windows | linux
    template_id = number # Packer template vmid to clone
    cores       = optional(number, 2)
    memory      = optional(number, 4096)
    isolate     = optional(bool, true) # attach det_isolation + NIC firewall. Set false for dual-homed ops boxes (attacker/collector).
    networks = list(object({
      bridge  = string           # SDN vnet bridge (carries the VLAN tag itself)
      address = string           # "10.50.0.10/24" or "dhcp"
      gateway = optional(string) # set only on the ops NIC; detonation NICs have NONE
    }))
    user_data = optional(string) # raw cloud-init (Linux) / cloudbase-init #ps1 (Windows)
  }))

  validation {
    condition     = alltrue([for h in var.hosts : contains(["windows", "linux"], h.os_type)])
    error_message = "Every host os_type must be \"windows\" or \"linux\"."
  }
  validation {
    condition     = alltrue([for h in var.hosts : length(h.networks) > 0])
    error_message = "Every host needs at least one network."
  }
}

variable "dns" {
  description = "Cloud-init DNS for scenario hosts. In an isolated AD lab the DC is usually the resolver, so point workstations at the DC's IP and set the AD domain."
  type = object({
    servers = optional(list(string), [])
    domain  = optional(string)
  })
  default = {}
}
