# Discover shared plumbing by tag. Two victim subnets, one per forest.
data "aws_vpc" "range" {
  filter {
    name   = "tag:Discovery"
    values = ["range-vpc"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
}

data "aws_subnet" "forest_a" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:Discovery"
    values = ["range-subnet"]
  }
  filter {
    name   = "tag:SubnetName"
    values = [var.forest_a_subnet_name]
  }
}

data "aws_subnet" "forest_b" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:Discovery"
    values = ["range-subnet"]
  }
  filter {
    name   = "tag:SubnetName"
    values = [var.forest_b_subnet_name]
  }
}

# All four victims share the victim SG, which is what lets the forest trust work.
data "aws_security_group" "victim" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:SGRole"
    values = ["victim"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
}

data "aws_ami" "windows" {
  most_recent = true
  owners      = [var.windows_ami_owner]
  filter {
    name   = "name"
    values = [var.windows_ami_name]
  }
  filter {
    name   = "platform"
    values = ["windows"]
  }
}

locals {
  # Static IPs, since VPC DNS is off. .10 = DC, .20 = workstation.
  dc_a_ip = cidrhost(data.aws_subnet.forest_a.cidr_block, 10)
  ws_a_ip = cidrhost(data.aws_subnet.forest_a.cidr_block, 20)
  dc_b_ip = cidrhost(data.aws_subnet.forest_b.cidr_block, 10)
  ws_b_ip = cidrhost(data.aws_subnet.forest_b.cidr_block, 20)
}

# Collector's range-side IP for agent enrollment. Requires ops-tier applied first.
data "aws_instance" "collector" {
  count = var.enable_wazuh_agents ? 1 : 0

  filter {
    name   = "tag:Role"
    values = ["collector"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

locals {
  wazuh_manager_ip = var.enable_wazuh_agents ? data.aws_instance.collector[0].private_ip : ""
}
