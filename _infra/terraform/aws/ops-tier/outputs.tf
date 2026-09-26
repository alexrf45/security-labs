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

output "ssh" {
  description = "How to get a shell on each ops host once you are on the tailnet and the router is advertising the ops route. The router additionally accepts `tailscale ssh range-router`."
  value = {
    router    = "ssh ubuntu@${aws_instance.router.private_ip}"
    attacker  = "ssh kali@${aws_instance.attacker.private_ip}"
    collector = "ssh ubuntu@${aws_instance.collector.private_ip}"
  }
}

output "ssh_key_name" {
  description = "EC2 key pair attached to the ops hosts, or null when none was configured (no shell on the attacker/collector)."
  value       = local.ssh_key_name
}
