# Per-VM firewall for isolated victims: enable the NIC firewall and attach the
# det_isolation security group (from range-network) which DROPs egress to the mgmt
# LAN + ops net. Redundant with the gateway-less detonation vnet, by design.

resource "proxmox_virtual_environment_firewall_options" "this" {
  for_each = local.isolated_hosts

  node_name = each.value.node
  vm_id     = proxmox_virtual_environment_vm.this[each.key].vm_id

  enabled       = true
  input_policy  = "ACCEPT" # intra-scenario L2 stays open (DC <-> workstation)
  output_policy = "ACCEPT" # explicit DROPs come from the security group below
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  for_each = local.isolated_hosts

  node_name = each.value.node
  vm_id     = proxmox_virtual_environment_vm.this[each.key].vm_id

  rule {
    security_group = var.isolation.det_isolation_security_group
    comment        = "range isolation — no pivot to mgmt LAN / ops net"
  }

  depends_on = [proxmox_virtual_environment_firewall_options.this]
}
