resource "aws_vpc" "range" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = false
  enable_dns_hostnames = false
  instance_tenancy     = "default"

  tags = {
    Name      = "${var.project}-vpc"
    Discovery = "range-vpc"
  }
}

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

resource "aws_internet_gateway" "range" {
  vpc_id = aws_vpc.range.id

  tags = {
    Name = "${var.project}-igw"
  }
}
