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
  description = "Shell on each ops host once you are on the tailnet. The attacker and collector also need the advertised ops route approved."
  value = {
    router    = "tailscale ssh ubuntu@${var.tailnet_hostname}"
    attacker  = "ssh kali@${aws_instance.attacker.private_ip}"
    collector = "ssh ubuntu@${aws_instance.collector.private_ip}"
  }
}

output "ssh_key_name" {
  description = "EC2 key pair attached to the ops hosts, or null when none was configured (no shell on the attacker/collector)."
  value       = local.ssh_key_name
}
