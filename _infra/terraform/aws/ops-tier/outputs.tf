output "router_public_ip" {
  description = "Router EIP (the only public IPv4). SSH/entry is via Tailscale, not this address."
  value       = aws_eip.router.public_ip
}

output "router_private_ip" {
  value = aws_instance.router.private_ip
}

output "attacker_private_ip" {
  description = "Reach over Tailscale via the router's advertised ops route."
  value       = aws_instance.attacker.private_ip
}

output "collector_private_ip" {
  value = aws_instance.collector.private_ip
}
