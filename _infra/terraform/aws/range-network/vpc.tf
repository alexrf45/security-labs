# VPC DNS support DISABLED (range-safety.md §10): AmazonProvidedDNS is reachable from a
# no-egress subnet and cannot be filtered or logged. Never re-enable it.
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

# Public resolvers, since VPC DNS is off. Usable from ops only; victims have no route.
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

# Reachable only from the ops route table.
resource "aws_internet_gateway" "range" {
  vpc_id = aws_vpc.range.id

  tags = {
    Name = "${var.project}-igw"
  }
}
