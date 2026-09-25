# Outputs are for humans (`terraform output`) and documentation only. The ops-tier
# and scenario roots do NOT consume this state; they rediscover everything below via
# tag-filtered data sources (ADR-0011 §5, range-safety.md §9).
output "vpc_id" {
  description = "Range VPC ID."
  value       = aws_vpc.range.id
}

output "ops_subnet_id" {
  description = "Ops subnet ID (the only routed subnet)."
  value       = aws_subnet.ops.id
}

output "detonation_subnet_ids" {
  description = "Detonation subnet IDs by name."
  value       = { for k, s in aws_subnet.detonation : k => s.id }
}

output "security_group_ids" {
  description = "Range security group IDs by role."
  value = {
    router     = aws_security_group.router.id
    attacker   = aws_security_group.attacker.id
    collector  = aws_security_group.collector.id
    detonation = aws_security_group.detonation.id
  }
}

output "siem_volume_id" {
  description = "Persistent SIEM EBS volume ID."
  value       = aws_ebs_volume.siem.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID (ops route only)."
  value       = aws_internet_gateway.range.id
}
