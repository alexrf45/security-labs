output "zone_id" {
  description = "SDN VLAN zone id."
  value       = proxmox_sdn_zone_vlan.lab.id
}

output "ops_vnet_bridge" {
  description = "Bridge name for the ops/admin net — set as the scenario-vm/Packer NIC bridge for ops-side interfaces (Kali, Wazuh primary)."
  value       = proxmox_sdn_vnet.ops.id
}

output "detonation_vnet_bridges" {
  description = "scenario short-name => detonation vnet bridge name. Consume from scenario roots (e.g. ad-detection) as the victim/dual-homed NIC bridge."
  value       = { for k, v in proxmox_sdn_vnet.detonation : k => v.id }
}

output "det_isolation_security_group" {
  description = "Cluster firewall security group name the scenario-vm module attaches to every detonation VM."
  value       = proxmox_virtual_environment_cluster_firewall_security_group.det_isolation.name
}
