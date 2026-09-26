# Security groups are the primary (stateful) isolation control (ADR-0011 §4c layer 1).
# They live in range-network so ops-tier and scenario instances attach them by ID via
# tag-filtered data sources. Directionality that a NACL cannot express (telemetry is
# one-way victim -> collector; the collector must never initiate into a victim subnet)
# is enforced here by referencing SG IDs rather than CIDRs.

# --- Tailscale subnet router (ops) ---------------------------------------------
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
  description       = "Access via the Tailscale subnet router (masqueraded to the ops CIDR)"
  ip_protocol       = "-1"
  cidr_ipv4         = var.ops_subnet_cidr
}

resource "aws_vpc_security_group_egress_rule" "attacker_all" {
  security_group_id = aws_security_group.attacker.id
  description       = "Reach victim hosts on any port, and pull tooling via the ops route"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Collector / SIEM (ops) ----------------------------------------------------
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

# Telemetry ingress from the victim SG only (one-way victim -> collector).
resource "aws_vpc_security_group_ingress_rule" "collector_telemetry" {
  for_each = toset([for p in var.telemetry_ports : tostring(p)])

  security_group_id            = aws_security_group.collector.id
  description                  = "Telemetry from victim hosts"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.victim.id
}

# Operator SSH, reachable only from the ops CIDR — i.e. only via the Tailscale
# subnet router, which masquerades tailnet traffic to an ops address. Nothing here
# is open to 0.0.0.0/0, so range-safety.md §3 holds. Without this rule the collector
# SG admits nothing but telemetry and 443, and there is no way to read
# /var/log/collector-bootstrap.log when Wazuh fails to come up.
resource "aws_vpc_security_group_ingress_rule" "collector_ssh" {
  security_group_id = aws_security_group.collector.id
  description       = "Operator SSH via the Tailscale subnet router"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.ops_subnet_cidr
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
# no rule toward the victim SG: the collector must never open a connection into
# a victim net (range-safety.md §7).
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

# --- Victim hosts (victim subnets) ---------------------------------------------
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

# Attacker -> victim on any port.
resource "aws_vpc_security_group_ingress_rule" "victim_from_attacker" {
  security_group_id            = aws_security_group.victim.id
  description                  = "Attacker box reaches victims on any port"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.attacker.id
}

# Victim <-> victim (same SG). Enables a cross-subnet forest trust (victim00<->victim01):
# Kerberos, LDAP, SMB, RPC EPM + dynamic range all ride the VPC local route between
# hosts that share this SG (ADR-0011 §7). Baseline is permit-all intra-SG; a scenario
# wanting inter-forest isolation layers a tighter SG on top.
resource "aws_vpc_security_group_ingress_rule" "victim_intra" {
  security_group_id            = aws_security_group.victim.id
  description                  = "Victim-to-victim (forest trust, lateral movement)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.victim.id
}

# Telemetry egress to the collector only.
resource "aws_vpc_security_group_egress_rule" "victim_telemetry" {
  for_each = toset([for p in var.telemetry_ports : tostring(p)])

  security_group_id            = aws_security_group.victim.id
  description                  = "Ship telemetry to the collector"
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  referenced_security_group_id = aws_security_group.collector.id
}

# Victim <-> victim egress (forest trust). No internet egress rule exists, and there
# is no route regardless (range-safety.md §1, §6 egress-deny by default).
resource "aws_vpc_security_group_egress_rule" "victim_intra" {
  security_group_id            = aws_security_group.victim.id
  description                  = "Victim-to-victim (forest trust, lateral movement)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.victim.id
}

# --- Opt-in agent package mirror (default off) ---------------------------------
# Victim hosts pull agent installers from the collector's local mirror over one
# port. Still victim-initiated: the collector never opens a connection into victim.
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

# --- VPC default security group: adopted and emptied ---------------------------
# Same fail-closed reasoning as aws_default_route_table in routing.tf. Nothing in the
# range references this group, but AWS creates one per VPC with allow-all-from-self
# ingress and allow-all egress, and an instance launched WITHOUT an explicit
# vpc_security_group_ids lands in it silently. In a victim subnet that would mean
# unrestricted reach across the whole VPC CIDR, bypassing the SG layer of invariant 11.
#
# Omitting every ingress/egress block is what empties it: the provider adopts the
# existing group and immediately revokes all rules. This is FSBP/CIS **EC2.2**, "VPC
# default security groups should not allow inbound or outbound traffic".
#
# Provider caveat: removing this resource later does NOT restore the original rules, it
# only stops managing the (already emptied) group.
resource "aws_default_security_group" "range" {
  vpc_id = aws_vpc.range.id

  # No ingress/egress blocks == every rule revoked.

  tags = {
    Name = "${var.project}-default-sg-locked"
  }
}
