output "vm_ids" {
  description = "host key => Proxmox vmid (for `qm snapshot <id> clean-baseline`, rollback, etc.)."
  value       = { for k, v in proxmox_virtual_environment_vm.this : k => v.vm_id }
}

output "names" {
  description = "host key => VM name."
  value       = { for k, v in proxmox_virtual_environment_vm.this : k => v.name }
}

output "addresses" {
  description = "host key => configured primary address (as declared; \"dhcp\" if dynamic)."
  value       = { for k, h in var.hosts : k => h.networks[0].address }
}

output "isolated" {
  description = "host keys that have the det_isolation security group attached."
  value       = keys(local.isolated_hosts)
}
