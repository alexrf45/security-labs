# Detonation network ACL — stateless, subnet-level, and LOAD-BEARING (ADR-0011 §4c),
# not belt-and-braces. Within one VPC the implicit local route reaches the ops subnet
# at L3 no matter what the route table says, so ops<->detonation separation is
# rule-based rather than structural (an honest degradation from ADR-0009's gateway-less
# VLAN). Security groups (security-groups.tf) are layer 1; this NACL is layer 2.
#
# The meaningful control here is on EGRESS toward ops: a detonation host may reach the
# ops subnet ONLY on the collector telemetry ports and on ephemeral ports (return
# traffic to the attacker). It cannot open a new connection to an arbitrary ops
# service (router SSH, the Wazuh API, the Tailscale node, etc.). Detonation<->detonation
# is permitted in full so a cross-subnet forest trust works (ADR-0011 §7); inter-forest
# isolation, where a scenario wants it, is a scenario-level SG choice on top of this.

locals {
  det_cidrs = values(var.detonation_subnets)

  # Ingress: allow all from every detonation CIDR (det<->det trust), and allow all
  # from ops (the attacker legitimately probes arbitrary victim ports; which ops HOST
  # may initiate is gated by SGs — only the attacker SG, never the collector).
  det_nacl_ingress = concat(
    [for i, c in local.det_cidrs : {
      rule_no    = 100 + i
      protocol   = "-1"
      cidr_block = c
      from_port  = 0
      to_port    = 0
    }],
    [{
      rule_no    = 200
      protocol   = "-1"
      cidr_block = var.ops_subnet_cidr
      from_port  = 0
      to_port    = 0
    }],
  )

  # Egress: allow all to every detonation CIDR (trust); to ops, allow ONLY the
  # telemetry ports (to the collector) and ephemeral TCP/UDP (replies to the
  # attacker). Everything else toward ops — and toward the internet, which also has
  # no route — falls to the NACL's implicit deny.
  det_nacl_egress = concat(
    [for i, c in local.det_cidrs : {
      rule_no    = 100 + i
      protocol   = "-1"
      cidr_block = c
      from_port  = 0
      to_port    = 0
    }],
    [for j, p in var.telemetry_ports : {
      rule_no    = 200 + j
      protocol   = "6" # tcp
      cidr_block = var.ops_subnet_cidr
      from_port  = p
      to_port    = p
    }],
    [
      {
        rule_no    = 300
        protocol   = "6" # tcp ephemeral (attacker return)
        cidr_block = var.ops_subnet_cidr
        from_port  = 1024
        to_port    = 65535
      },
      {
        rule_no    = 310
        protocol   = "17" # udp ephemeral (attacker return)
        cidr_block = var.ops_subnet_cidr
        from_port  = 1024
        to_port    = 65535
      },
    ],
  )
}

resource "aws_network_acl" "detonation" {
  vpc_id     = aws_vpc.range.id
  subnet_ids = [for k in keys(var.detonation_subnets) : aws_subnet.detonation[k].id]

  tags = {
    Name = "${var.project}-det-nacl"
  }
}

resource "aws_network_acl_rule" "detonation_ingress" {
  for_each = { for r in local.det_nacl_ingress : r.rule_no => r }

  network_acl_id = aws_network_acl.detonation.id
  egress         = false
  rule_number    = each.value.rule_no
  rule_action    = "allow"
  protocol       = each.value.protocol
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}

resource "aws_network_acl_rule" "detonation_egress" {
  for_each = { for r in local.det_nacl_egress : r.rule_no => r }

  network_acl_id = aws_network_acl.detonation.id
  egress         = true
  rule_number    = each.value.rule_no
  rule_action    = "allow"
  protocol       = each.value.protocol
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
}

# Opt-in agent-package-mirror allowance (range-safety.md §6 controlled allow-list).
# Off by default; when on, detonation hosts may reach the ops subnet on exactly one
# additional port to pull agent installers from the collector's local mirror.
resource "aws_network_acl_rule" "detonation_egress_mirror" {
  count = var.enable_agent_package_mirror ? 1 : 0

  network_acl_id = aws_network_acl.detonation.id
  egress         = true
  rule_number    = 250
  rule_action    = "allow"
  protocol       = "6" # tcp
  cidr_block     = var.ops_subnet_cidr
  from_port      = var.agent_package_mirror_port
  to_port        = var.agent_package_mirror_port
}
