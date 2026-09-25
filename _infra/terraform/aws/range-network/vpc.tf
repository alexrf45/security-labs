# VPC with DNS support DISABLED (ADR-0011 §4b). AmazonProvidedDNS (VPC base+2 and
# 169.254.169.253) is reachable from a subnet with no IGW route, cannot be filtered
# by SG/NACL, and is not logged — a live, invisible DNS-exfil channel. Turning VPC
# DNS off makes DNS obey the same structural rule as everything else: it works from
# ops (which has a route to the public resolvers below) and is dead in detonation
# subnets (which do not). Scenarios that need in-segment DNS run their own resolver
# (an AD DC *is* its domain's DNS server — ADR-0011 §7).
resource "aws_vpc" "range" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = false
  enable_dns_hostnames = false
  instance_tenancy     = "default"

  tags = {
    Name      = "${var.project}-vpc"
    Discovery = "range-vpc" # ops-tier / scenarios look this up by tag
  }
}

# Custom DHCP option set handing out public resolvers. This is what gives ops
# instances working DNS once VPC DNS is off; detonation instances receive it too
# but cannot use it, having no route to reach it.
resource "aws_vpc_dhcp_options" "range" {
  domain_name_servers = var.public_dns_resolvers

  tags = {
    Name = "${var.project}-dhcp"
  }
}

resource "aws_vpc_dhcp_options_association" "range" {
  vpc_id          = aws_vpc.range.id
  dhcp_options_id = aws_vpc_dhcp_options.range.id
}

# Internet Gateway is free (only NAT Gateways bill). Reachable only from the ops
# route table; detonation route tables never point a default route at it.
resource "aws_internet_gateway" "range" {
  vpc_id = aws_vpc.range.id

  tags = {
    Name = "${var.project}-igw"
  }
}
