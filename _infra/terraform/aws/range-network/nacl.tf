locals {
  victim_cidrs = values(var.victim_subnets)

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
        protocol   = "6"
        cidr_block = var.ops_subnet_cidr
        from_port  = 1024
        to_port    = 65535
        icmp_type  = null
        icmp_code  = null
      },
      {
        rule_no    = 310
        protocol   = "17"
        cidr_block = var.ops_subnet_cidr
        from_port  = 1024
        to_port    = 65535
        icmp_type  = null
        icmp_code  = null
      },
      {
        rule_no    = 320
        protocol   = "1"
        cidr_block = var.ops_subnet_cidr
        from_port  = null
        to_port    = null
        icmp_type  = -1
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
