# Ops subnet — the only subnet with a path to the internet. map_public_ip_on_launch
# stays false; the router's single EIP is assigned explicitly in ops-tier.
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

# Victim subnets — no default route, no public IP (range-safety.md §1-2). The local
# route still spans the CIDR, which is what lets a cross-subnet forest trust work.
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
