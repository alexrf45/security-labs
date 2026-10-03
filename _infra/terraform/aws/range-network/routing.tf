# Edge route table: the one default route to the IGW in the entire range.
moved {
  from = aws_route_table.ops
  to   = aws_route_table.edge
}

resource "aws_route_table" "edge" {
  vpc_id = aws_vpc.range.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.range.id
  }

  tags = {
    Name = "${var.project}-edge-rt"
  }
}

resource "aws_route_table_association" "edge" {
  subnet_id      = aws_subnet.edge.id
  route_table_id = aws_route_table.edge.id
}

# No inline routes, ever: ops-tier owns the default route (via the router ENI) as a
# standalone aws_route, and inline route blocks here would delete it. Not named "ops":
# that address now belongs to the edge table via the moved block above.
resource "aws_route_table" "ops_via_router" {
  vpc_id = aws_vpc.range.id

  tags = {
    Name = "${var.project}-ops-rt"
  }
}

resource "aws_route_table_association" "ops" {
  subnet_id      = aws_subnet.ops.id
  route_table_id = aws_route_table.ops_via_router.id
}

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

resource "aws_default_route_table" "range" {
  default_route_table_id = aws_vpc.range.default_route_table_id

  tags = {
    Name = "${var.project}-main-rt-locked"
  }
}
