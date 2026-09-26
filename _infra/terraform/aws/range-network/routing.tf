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

# Victim route table: NO routes beyond the implicit local route (range-safety.md §1).
# Never add a route here — reach victim hosts from the attacker box instead.
resource "aws_route_table" "victim" {
  vpc_id = aws_vpc.range.id

  tags = {
    Name = "${var.project}-victim-rt"
  }
}

resource "aws_route_table_association" "victim" {
  for_each = var.victim_subnets

  subnet_id      = aws_subnet.victim[each.key].id
  route_table_id = aws_route_table.victim.id
}

# Main route table locked to local-only, so an unassociated subnet fails closed.
resource "aws_default_route_table" "range" {
  default_route_table_id = aws_vpc.range.default_route_table_id

  # no route blocks == local route only
  tags = {
    Name = "${var.project}-main-rt-locked"
  }
}
