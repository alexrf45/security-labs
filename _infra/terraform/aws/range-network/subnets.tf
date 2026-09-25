# Ops subnet — the only subnet with a path to the internet. Public IPs are NOT
# auto-assigned; the subnet router gets its single EIP explicitly in the ops-tier
# root (ADR-0011 §4d). map_public_ip_on_launch stays false so nothing accidentally
# acquires a public address.
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

# Detonation subnets — no default route (routing.tf), no public IP. A victim has
# no next-hop off its segment toward the internet (range-safety.md §1-2). The VPC
# local route still spans the whole CIDR, which is what lets two detonation subnets
# host a cross-subnet forest trust while both stay internet-air-gapped (ADR-0011 §7).
resource "aws_subnet" "detonation" {
  for_each = var.detonation_subnets

  vpc_id                  = aws_vpc.range.id
  cidr_block              = each.value
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name       = "${var.project}-${each.key}"
    SubnetRole = "detonation"
    SubnetName = each.key
    Discovery  = "range-subnet"
  }
}
