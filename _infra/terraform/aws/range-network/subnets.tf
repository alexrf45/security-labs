resource "aws_subnet" "ops" {
  vpc_id                  = aws_vpc.range.id
  cidr_block              = var.ops_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name       = "${var.project}-ops"
    SubnetRole = "ops"
    SubnetName = "ops"
    Discovery  = "range-subnet"
  }
}

resource "aws_subnet" "edge" {
  vpc_id                  = aws_vpc.range.id
  cidr_block              = var.edge_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name       = "${var.project}-edge"
    SubnetRole = "edge"
    SubnetName = "edge"
    Discovery  = "range-subnet"
  }
}

resource "aws_subnet" "victim" {
  for_each = var.victim_subnets

  vpc_id                  = aws_vpc.range.id
  cidr_block              = each.value
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name       = "${var.project}-${each.key}"
    SubnetRole = "victim"
    SubnetName = each.key
    Discovery  = "range-subnet"
  }
}
