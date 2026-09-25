output "domain_vm_ids" {
  description = "DC + workstation vmids. Snapshot each for CVE rollback: qm snapshot <id> clean-baseline."
  value       = module.domain.vm_ids
}

output "attacker_vm_id" {
  value = module.attacker.vm_ids
}

output "addresses" {
  description = "Scenario host addresses."
  value = merge(
    module.domain.addresses,
    module.attacker.addresses,
  )
}

output "domain_fqdn" {
  value = var.ad.domain_fqdn
}
