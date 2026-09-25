# Ops route table: the one default route to the IGW in the entire range.
resource "aws_route_table" "ops" {
  vpc_id = aws_vpc.range.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.range.id
  }

  tags = {
    Name = "${var.project}-ops-rt"
  }
}

resource "aws_route_table_association" "ops" {
  subnet_id      = aws_subnet.ops.id
  route_table_id = aws_route_table.ops.id
}

# Detonation route table: NO routes beyond the implicit VPC local route. This is
# the structural air-gap toward the internet (range-safety.md §1). Never add a
# route here "to make something reachable" — reach detonation hosts from the ops
# attacker box instead.
resource "aws_route_table" "detonation" {
  vpc_id = aws_vpc.range.id

  tags = {
    Name = "${var.project}-det-rt"
  }
}

resource "aws_route_table_association" "detonation" {
  for_each = var.detonation_subnets

  subnet_id      = aws_subnet.detonation[each.key].id
  route_table_id = aws_route_table.detonation.id
}

# Lock the VPC's main route table down to local-only. Any subnet not explicitly
# associated above would fall back to this; keeping it routeless means an
# accidentally-unassociated subnet fails closed rather than inheriting egress.
resource "aws_default_route_table" "range" {
  default_route_table_id = aws_vpc.range.default_route_table_id

  # no route blocks == local route only
  tags = {
    Name = "${var.project}-main-rt-locked"
  }
}
