# Discover shared plumbing by tag (ADR-0011 §5). Two detonation subnets, one per forest.
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

# All four victims share the detonation SG (self-referencing allow-all enables the
# cross-subnet forest trust — ADR-0011 §4c/§7).
data "aws_security_group" "detonation" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:SGRole"
    values = ["detonation"]
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
  # Static private IPs derived from the discovered subnet CIDRs, so DCs can name each
  # other in conditional forwarders and members can point DNS at their DC — without
  # working VPC DNS (which is disabled, §4b). .10 = DC, .20 = workstation.
  dc_a_ip = cidrhost(data.aws_subnet.forest_a.cidr_block, 10)
  ws_a_ip = cidrhost(data.aws_subnet.forest_a.cidr_block, 20)
  dc_b_ip = cidrhost(data.aws_subnet.forest_b.cidr_block, 10)
  ws_b_ip = cidrhost(data.aws_subnet.forest_b.cidr_block, 20)
}

# Discover the collector (created per-session by ops-tier) by tag, to get its
# range-side IP for agent enrollment and the installer mirror. Gated on
# enable_wazuh_agents; requires ops-tier applied first (enforced ordering).
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
