resource "aws_security_group" "router" {
  name        = "${var.project}-router"
  description = "Tailscale subnet router: the single human entry path (range-safety.md)."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-router"
    SGRole    = "router"
    Discovery = "range-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "router_wireguard" {
  security_group_id = aws_security_group.router.id
  description       = "Tailscale WireGuard"
  ip_protocol       = "udp"
  from_port         = 41641
  to_port           = 41641
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "router_from_ops" {
  security_group_id = aws_security_group.router.id
  description       = "Return/forwarded traffic from the ops subnet"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ops_subnet_cidr
}

resource "aws_vpc_security_group_egress_rule" "router_all" {
  security_group_id = aws_security_group.router.id
  description       = "Router is the ops egress path and reaches Tailscale DERP"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "attacker" {
  name        = "${var.project}-attacker"
  description = "Kali attacker box; reached over Tailscale via the router, bridges into victim nets."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-attacker"
    SGRole    = "attacker"
    Discovery = "range-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "attacker_from_ops" {
  security_group_id = aws_security_group.attacker.id
  description       = "From hosts on the ops subnet"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ops_subnet_cidr
}

resource "aws_vpc_security_group_ingress_rule" "attacker_from_router" {
  security_group_id            = aws_security_group.attacker.id
  description                  = "Operator access over Tailscale, masqueraded to the router"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.router.id
}

resource "aws_vpc_security_group_egress_rule" "attacker_all" {
  security_group_id = aws_security_group.attacker.id
  description       = "Reach victim hosts on any port, and pull tooling via the router NAT"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "collector" {
  name        = "${var.project}-collector"
  description = "Defensive collector/SIEM. Receives telemetry from victim hosts; never initiates into them."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-collector"
    SGRole    = "collector"
    Discovery = "range-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "collector_telemetry" {
  for_each = toset([for p in var.telemetry_ports : tostring(p)])

  security_group_id            = aws_security_group.collector.id
  description                  = "Telemetry from victim hosts"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.victim.id
}

resource "aws_vpc_security_group_ingress_rule" "collector_ssh" {
  security_group_id = aws_security_group.collector.id
  description       = "SSH from hosts on the ops subnet"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ops_subnet_cidr
}

resource "aws_vpc_security_group_ingress_rule" "collector_dashboard" {
  security_group_id = aws_security_group.collector.id
  description       = "SIEM dashboard from hosts on the ops subnet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.ops_subnet_cidr
}

resource "aws_vpc_security_group_ingress_rule" "collector_ssh_from_router" {
  security_group_id            = aws_security_group.collector.id
  description                  = "Operator SSH over Tailscale, masqueraded to the router"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.router.id
}

resource "aws_vpc_security_group_ingress_rule" "collector_dashboard_from_router" {
  security_group_id            = aws_security_group.collector.id
  description                  = "SIEM dashboard over Tailscale, masqueraded to the router"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.router.id
}

resource "aws_vpc_security_group_egress_rule" "collector_dns" {
  for_each = {
    for pair in setproduct(var.public_dns_resolvers, ["udp", "tcp"]) :
    "${pair[0]}-${pair[1]}" => { resolver = pair[0], protocol = pair[1] }
  }

  security_group_id = aws_security_group.collector.id
  description       = "DNS to the DHCP-provided public resolvers"
  ip_protocol       = each.value.protocol
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "${each.value.resolver}/32"
}

resource "aws_vpc_security_group_egress_rule" "collector_updates_https" {
  security_group_id = aws_security_group.collector.id
  description       = "Package updates (HTTPS) via the router NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "collector_updates_http" {
  security_group_id = aws_security_group.collector.id
  description       = "Package updates (HTTP) via the router NAT"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "victim" {
  name        = "${var.project}-victim"
  description = "Victims. Reachable only from the attacker; egress only to the collector (telemetry) and to peer victims (forest trust)."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-victim"
    SGRole    = "victim"
    Discovery = "range-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "victim_from_attacker" {
  security_group_id            = aws_security_group.victim.id
  description                  = "Attacker box reaches victims on any port"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.attacker.id
}

resource "aws_vpc_security_group_ingress_rule" "victim_intra" {
  security_group_id            = aws_security_group.victim.id
  description                  = "Victim-to-victim (forest trust, lateral movement)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.victim.id
}

resource "aws_vpc_security_group_egress_rule" "victim_telemetry" {
  for_each = toset([for p in var.telemetry_ports : tostring(p)])

  security_group_id            = aws_security_group.victim.id
  description                  = "Ship telemetry to the collector"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.collector.id
}

resource "aws_vpc_security_group_egress_rule" "victim_intra" {
  security_group_id            = aws_security_group.victim.id
  description                  = "Victim-to-victim (forest trust, lateral movement)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.victim.id
}

resource "aws_vpc_security_group_egress_rule" "victim_pull_mirror" {
  count = var.enable_agent_package_mirror ? 1 : 0

  security_group_id            = aws_security_group.victim.id
  description                  = "Pull agent installers from the collector mirror"
  ip_protocol                  = "tcp"
  from_port                    = var.agent_package_mirror_port
  to_port                      = var.agent_package_mirror_port
  referenced_security_group_id = aws_security_group.collector.id
}

resource "aws_vpc_security_group_ingress_rule" "collector_serve_mirror" {
  count = var.enable_agent_package_mirror ? 1 : 0

  security_group_id            = aws_security_group.collector.id
  description                  = "Serve agent installers to victim hosts"
  ip_protocol                  = "tcp"
  from_port                    = var.agent_package_mirror_port
  to_port                      = var.agent_package_mirror_port
  referenced_security_group_id = aws_security_group.victim.id
}

resource "aws_default_security_group" "range" {
  vpc_id = aws_vpc.range.id


  tags = {
    Name = "${var.project}-default-sg-locked"
  }
}
