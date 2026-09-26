output "forest_a" {
  description = "Forest A hosts (victim00)."
  value = {
    domain = var.forest_a_domain
    dc     = { name = "dc-a", private_ip = aws_instance.dc_a.private_ip }
    ws     = { name = "ws-a", private_ip = aws_instance.ws_a.private_ip }
  }
}

output "forest_b" {
  description = "Forest B hosts (victim01)."
  value = {
    domain = var.forest_b_domain
    dc     = { name = "dc-b", private_ip = aws_instance.dc_b.private_ip }
    ws     = { name = "ws-b", private_ip = aws_instance.ws_b.private_ip }
  }
}

output "members_on_spot" {
  value = var.member_use_spot
}
