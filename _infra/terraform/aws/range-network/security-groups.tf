# Security groups are the primary (stateful) isolation control (ADR-0011 §4c layer 1).
# They live in range-network so ops-tier and scenario instances attach them by ID via
# tag-filtered data sources. Directionality that a NACL cannot express (telemetry is
# one-way det -> collector; the collector must never initiate into a detonation net)
# is enforced here by referencing SG IDs rather than CIDRs.

# --- Tailscale subnet router (ops) ---------------------------------------------
resource "aws_security_group" "router" {
  name        = "${var.project}-router"
  description = "Tailscale subnet router: the single human entry path (range-safety.md §3)."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-router"
    SGRole    = "router"
    Discovery = "range-sg"
  }
}

# Tailscale WireGuard direct path. Not SSH/RDP, so this does not violate the
# "no management port open to 0.0.0.0/0" invariant; it is the encrypted tailnet
# underlay and improves NAT traversal (DERP relay works even without it).
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

# --- Attacker box (ops) --------------------------------------------------------
resource "aws_security_group" "attacker" {
  name        = "${var.project}-attacker"
  description = "Kali attacker box; reached over Tailscale via the router, bridges into detonation nets."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-attacker"
    SGRole    = "attacker"
    Discovery = "range-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "attacker_from_ops" {
  security_group_id = aws_security_group.attacker.id
  description       = "Access via the Tailscale subnet router (masqueraded to the ops CIDR)"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ops_subnet_cidr
}

resource "aws_vpc_security_group_egress_rule" "attacker_all" {
  security_group_id = aws_security_group.attacker.id
  description       = "Reach detonation hosts on any port, and pull tooling via the ops route"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Collector / SIEM (ops) ----------------------------------------------------
resource "aws_security_group" "collector" {
  name        = "${var.project}-collector"
  description = "Defensive collector/SIEM. Receives telemetry from detonation hosts; never initiates into them."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-collector"
    SGRole    = "collector"
    Discovery = "range-sg"
  }
}

# Telemetry ingress from the detonation SG only (one-way det -> collector).
resource "aws_vpc_security_group_ingress_rule" "collector_telemetry" {
  for_each = toset([for p in var.telemetry_ports : tostring(p)])

  security_group_id            = aws_security_group.collector.id
  description                  = "Telemetry from detonation hosts"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.detonation.id
}

resource "aws_vpc_security_group_ingress_rule" "collector_dashboard" {
  security_group_id = aws_security_group.collector.id
  description       = "SIEM dashboard reached over Tailscale via the router"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.ops_subnet_cidr
}

# Egress limited to package updates. Deliberately NOT 0.0.0.0/0 and deliberately
# no rule toward the detonation SG: the collector must never open a connection into
# a detonation net (range-safety.md §7).
resource "aws_vpc_security_group_egress_rule" "collector_updates_https" {
  security_group_id = aws_security_group.collector.id
  description       = "Package updates (HTTPS) via the ops route"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "collector_updates_http" {
  security_group_id = aws_security_group.collector.id
  description       = "Package updates (HTTP) via the ops route"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Detonation victims (det subnets) ------------------------------------------
resource "aws_security_group" "detonation" {
  name        = "${var.project}-detonation"
  description = "Victims. Reachable only from the attacker; egress only to the collector (telemetry) and to peer victims (forest trust)."
  vpc_id      = aws_vpc.range.id

  tags = {
    Name      = "${var.project}-detonation"
    SGRole    = "detonation"
    Discovery = "range-sg"
  }
}

# Attacker -> victim on any port.
resource "aws_vpc_security_group_ingress_rule" "detonation_from_attacker" {
  security_group_id            = aws_security_group.detonation.id
  description                  = "Attacker box reaches victims on any port"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.attacker.id
}

# Victim <-> victim (same SG). Enables a cross-subnet forest trust (det00<->det01):
# Kerberos, LDAP, SMB, RPC EPM + dynamic range all ride the VPC local route between
# hosts that share this SG (ADR-0011 §7). Baseline is permit-all intra-SG; a scenario
# wanting inter-forest isolation layers a tighter SG on top.
resource "aws_vpc_security_group_ingress_rule" "detonation_intra" {
  security_group_id            = aws_security_group.detonation.id
  description                  = "Victim-to-victim (forest trust, lateral movement)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.detonation.id
}

# Telemetry egress to the collector only.
resource "aws_vpc_security_group_egress_rule" "detonation_telemetry" {
  for_each = toset([for p in var.telemetry_ports : tostring(p)])

  security_group_id            = aws_security_group.detonation.id
  description                  = "Ship telemetry to the collector"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.collector.id
}

# Victim <-> victim egress (forest trust). No internet egress rule exists, and there
# is no route regardless (range-safety.md §1, §6 egress-deny by default).
resource "aws_vpc_security_group_egress_rule" "detonation_intra" {
  security_group_id            = aws_security_group.detonation.id
  description                  = "Victim-to-victim (forest trust, lateral movement)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.detonation.id
}

# --- Opt-in agent package mirror (default off) ---------------------------------
# Detonation hosts pull agent installers from the collector's local mirror over one
# port. Still det-initiated: the collector never opens a connection into detonation.
resource "aws_vpc_security_group_egress_rule" "detonation_pull_mirror" {
  count = var.enable_agent_package_mirror ? 1 : 0

  security_group_id            = aws_security_group.detonation.id
  description                  = "Pull agent installers from the collector mirror"
  ip_protocol                  = "tcp"
  from_port                    = var.agent_package_mirror_port
  to_port                      = var.agent_package_mirror_port
  referenced_security_group_id = aws_security_group.collector.id
}

resource "aws_vpc_security_group_ingress_rule" "collector_serve_mirror" {
  count = var.enable_agent_package_mirror ? 1 : 0

  security_group_id            = aws_security_group.collector.id
  description                  = "Serve agent installers to detonation hosts"
  ip_protocol                  = "tcp"
  from_port                    = var.agent_package_mirror_port
  to_port                      = var.agent_package_mirror_port
  referenced_security_group_id = aws_security_group.detonation.id
}
