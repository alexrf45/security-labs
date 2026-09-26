# Victim network ACL — stateless, subnet-level, and LOAD-BEARING (ADR-0011 §4c),
# not belt-and-braces. Within one VPC the implicit local route reaches the ops subnet
# at L3 no matter what the route table says, so ops<->victim separation is
# rule-based rather than structural (an honest degradation from ADR-0009's gateway-less
# VLAN). Security groups (security-groups.tf) are layer 1; this NACL is layer 2.
#
# The meaningful control here is on EGRESS toward ops: a victim host may reach the
# ops subnet ONLY on the collector telemetry ports, on ephemeral ports, and with ICMP
# (all three being return traffic to the attacker). It cannot open a new connection to
# an arbitrary ops service (router SSH, the Wazuh API, the Tailscale node). Note that
# ephemeral egress starts at 1024, so a probe sourced from a privileged port — e.g.
# `nmap --source-port 53` — gets no reply. That is deliberate, not a defect: widening it
# would let a victim reach low ops ports. Victim<->victim
# is permitted in full so a cross-subnet forest trust works (ADR-0011 §7); inter-forest
# isolation, where a scenario wants it, is a scenario-level SG choice on top of this.

locals {
  victim_cidrs = values(var.victim_subnets)

  # Ingress: allow all from every victim CIDR (victim<->victim trust), and allow all
  # from ops (the attacker legitimately probes arbitrary victim ports; which ops HOST
  # may initiate is gated by SGs — only the attacker SG, never the collector).
  victim_nacl_ingress = concat(
    [for i, c in local.victim_cidrs : {
      rule_no    = 100 + i
      protocol   = "-1"
      cidr_block = c
      from_port  = 0
      to_port    = 0
      icmp_type  = null
      icmp_code  = null
    }],
    [{
      rule_no    = 200
      protocol   = "-1"
      cidr_block = var.ops_subnet_cidr
      from_port  = 0
      to_port    = 0
      icmp_type  = null
      icmp_code  = null
    }],
  )

  # Egress: allow all to every victim CIDR (trust); to ops, allow ONLY the
  # telemetry ports (to the collector) and ephemeral TCP/UDP (replies to the
  # attacker). Everything else toward ops — and toward the internet, which also has
  # no route — falls to the NACL's implicit deny.
  victim_nacl_egress = concat(
    [for i, c in local.victim_cidrs : {
      rule_no    = 100 + i
      protocol   = "-1"
      cidr_block = c
      from_port  = 0
      to_port    = 0
      icmp_type  = null
      icmp_code  = null
    }],
    [for j, p in var.telemetry_ports : {
      rule_no    = 200 + j
      protocol   = "6" # tcp
      cidr_block = var.ops_subnet_cidr
      from_port  = p
      to_port    = p
      icmp_type  = null
      icmp_code  = null
    }],
    [
      {
        rule_no    = 300
        protocol   = "6" # tcp ephemeral (attacker return)
        cidr_block = var.ops_subnet_cidr
        from_port  = 1024
        to_port    = 65535
        icmp_type  = null
        icmp_code  = null
      },
      {
        rule_no    = 310
        protocol   = "17" # udp ephemeral (attacker return)
        cidr_block = var.ops_subnet_cidr
        from_port  = 1024
        to_port    = 65535
        icmp_type  = null
        icmp_code  = null
      },
      # ICMP echo replies back to the attacker. The NACL is stateless, so a reply needs
      # its own rule: rules 300/310 cover TCP/UDP return traffic but nothing covered
      # ICMP, which silently broke `ping` and `nmap -PE` from the attacker even though
      # the security groups permitted them.
      #
      # This does not widen victim-initiated reach. Being stateless, the NACL cannot tell
      # a reply from a fresh packet, but the victim SG has no egress rule permitting ICMP
      # to the attacker — echo replies ride SG statefulness instead. The SG therefore
      # remains the control, exactly as invariant 11 intends.
      {
        rule_no    = 320
        protocol   = "1" # icmp
        cidr_block = var.ops_subnet_cidr
        from_port  = null
        to_port    = null
        icmp_type  = -1 # wildcard type; code must also be -1
        icmp_code  = -1
      },
    ],
  )
}

resource "aws_network_acl" "victim" {
  vpc_id     = aws_vpc.range.id
  subnet_ids = [for k in keys(var.victim_subnets) : aws_subnet.victim[k].id]

  tags = {
    Name = "${var.project}-victim-nacl"
  }
}

resource "aws_network_acl_rule" "victim_ingress" {
  for_each = { for r in local.victim_nacl_ingress : r.rule_no => r }

  network_acl_id = aws_network_acl.victim.id
  egress         = false
  rule_number    = each.value.rule_no
  rule_action    = "allow"
  protocol       = each.value.protocol
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
  icmp_type      = each.value.icmp_type
  icmp_code      = each.value.icmp_code
}

resource "aws_network_acl_rule" "victim_egress" {
  for_each = { for r in local.victim_nacl_egress : r.rule_no => r }

  network_acl_id = aws_network_acl.victim.id
  egress         = true
  rule_number    = each.value.rule_no
  rule_action    = "allow"
  protocol       = each.value.protocol
  cidr_block     = each.value.cidr_block
  from_port      = each.value.from_port
  to_port        = each.value.to_port
  icmp_type      = each.value.icmp_type
  icmp_code      = each.value.icmp_code
}

# Opt-in agent-package-mirror allowance (range-safety.md §6 controlled allow-list).
# Off by default; when on, victim hosts may reach the ops subnet on exactly one
# additional port to pull agent installers from the collector's local mirror.
resource "aws_network_acl_rule" "victim_egress_mirror" {
  count = var.enable_agent_package_mirror ? 1 : 0

  network_acl_id = aws_network_acl.victim.id
  egress         = true
  rule_number    = 250
  rule_action    = "allow"
  protocol       = "6" # tcp
  cidr_block     = var.ops_subnet_cidr
  from_port      = var.agent_package_mirror_port
  to_port        = var.agent_package_mirror_port
}
