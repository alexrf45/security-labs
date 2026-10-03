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

data "aws_subnet" "ops" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:Discovery"
    values = ["range-subnet"]
  }
  filter {
    name   = "tag:SubnetName"
    values = ["ops"]
  }
}

data "aws_subnet" "edge" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:Discovery"
    values = ["range-subnet"]
  }
  filter {
    name   = "tag:SubnetName"
    values = ["edge"]
  }
}

data "aws_route_table" "ops" {
  subnet_id = data.aws_subnet.ops.id
}

data "aws_security_group" "router" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:SGRole"
    values = ["router"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
}

data "aws_security_group" "attacker" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:SGRole"
    values = ["attacker"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
}

data "aws_security_group" "collector" {
  vpc_id = data.aws_vpc.range.id
  filter {
    name   = "tag:SGRole"
    values = ["collector"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
}

data "aws_ebs_volume" "siem" {
  most_recent = true
  filter {
    name   = "tag:Discovery"
    values = ["range-siem-volume"]
  }
  filter {
    name   = "tag:Project"
    values = [var.project]
  }
  # `in-use` must stay: on a re-apply the volume is still on the outgoing collector.
  filter {
    name   = "status"
    values = ["available", "in-use"]
  }
}

# --- AMIs ---------------------------------------------------------------------
# Router is arm64, collector is x86_64. Each lookup pins its architecture.
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = [var.ubuntu_ami_owner]
  filter {
    name   = "name"
    values = [var.ubuntu_arm_ami_name]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "ubuntu_x86" {
  most_recent = true
  owners      = [var.ubuntu_ami_owner]
  filter {
    name   = "name"
    values = [var.ubuntu_x86_ami_name]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "kali" {
  most_recent = true
  owners      = [var.kali_ami_owner]
  filter {
    name   = "name"
    values = [var.kali_ami_name]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
