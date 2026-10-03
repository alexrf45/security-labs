locals {
  imdsv2 = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ssh_public_key = trimspace(var.ssh_public_key)
}

resource "aws_key_pair" "ops" {
  count = local.ssh_public_key != "" ? 1 : 0

  key_name   = "${var.project}-ops"
  public_key = local.ssh_public_key

  tags = {
    Name = "${var.project}-ops-key"
  }
}

locals {
  ssh_key_name = local.ssh_public_key != "" ? aws_key_pair.ops[0].key_name : (
    var.ssh_key_name != "" ? var.ssh_key_name : null
  )
}

check "operator_ssh_key" {
  assert {
    condition     = local.ssh_public_key != "" || var.ssh_key_name != ""
    error_message = "No SSH key pair configured (ssh_public_key / ssh_key_name are both empty). Pass the public half from 1Password: TF_VAR_ssh_public_key=\"op://Security/security_labs/public key\" under `op run --`. The router is still reachable via `tailscale ssh`, but there will be no shell on the attacker or the collector."
  }
}

resource "aws_instance" "router" {
  ami                    = data.aws_ami.ubuntu_arm.id
  instance_type          = var.router_instance_type
  subnet_id              = data.aws_subnet.edge.id
  vpc_security_group_ids = [data.aws_security_group.router.id]
  key_name               = local.ssh_key_name

  source_dest_check = false

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.router_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/router.cloud-init.yaml.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    ops_cidr           = data.aws_subnet.ops.cidr_block
    vpc_cidr           = data.aws_vpc.range.cidr_block
    hostname           = var.tailnet_hostname
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project}-router"
    Tier = "ops"
    Role = "router"
  }
}

resource "aws_eip" "router" {
  instance = aws_instance.router.id
  domain   = "vpc"

  tags = {
    Name = "${var.project}-router-eip"
  }
}

# The ops subnet's only way out: NAT through the router. Lives here, not in
# range-network, so it is destroyed with the router instead of blackholing.
resource "aws_route" "ops_default" {
  route_table_id         = data.aws_route_table.ops.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.router.primary_network_interface_id
}

resource "aws_instance" "attacker" {
  ami                         = data.aws_ami.kali.id
  instance_type               = var.attacker_instance_type
  subnet_id                   = data.aws_subnet.ops.id
  vpc_security_group_ids      = [data.aws_security_group.attacker.id]
  associate_public_ip_address = false
  key_name                    = local.ssh_key_name

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.attacker_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/attacker-scrt.sh.tftpl", {
    scrt_repo_url     = var.scrt_repo_url
    install_bugbounty = var.attacker_install_bugbounty
    enable_gui        = var.attacker_enable_gui
    rdp_password      = var.attacker_rdp_password
  })

  user_data_replace_on_change = true

  # Bootstrap downloads at first boot, so the NAT path must exist before launch.
  depends_on = [aws_route.ops_default, aws_eip.router]

  tags = {
    Name = "${var.project}-attacker"
    Tier = "ops"
    Role = "attacker"
  }
}

resource "aws_instance" "collector" {
  ami                         = data.aws_ami.ubuntu_x86.id
  instance_type               = var.collector_instance_type
  subnet_id                   = data.aws_subnet.ops.id
  vpc_security_group_ids      = [data.aws_security_group.collector.id]
  associate_public_ip_address = false
  key_name                    = local.ssh_key_name

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.collector_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/collector-wazuh.sh.tftpl", {
    device          = "/dev/sdf"
    siem_volume_id  = data.aws_ebs_volume.siem.id
    mount_point     = var.siem_mount_point
    wazuh_version   = var.wazuh_version
    indexer_heap    = var.wazuh_indexer_heap
    enable_mirror   = var.enable_agent_package_mirror
    mirror_port     = var.agent_package_mirror_port
    serve_sysmon    = var.serve_sysmon
    wazuh_agent_pkg = var.wazuh_agent_pkg
    admin_password  = var.wazuh_admin_password
  })

  user_data_replace_on_change = true

  # Bootstrap downloads at first boot, so the NAT path must exist before launch.
  depends_on = [aws_route.ops_default, aws_eip.router]

  tags = {
    Name = "${var.project}-collector"
    Tier = "ops"
    Role = "collector"
  }
}

resource "aws_volume_attachment" "siem" {
  device_name = "/dev/sdf"
  volume_id   = data.aws_ebs_volume.siem.id
  instance_id = aws_instance.collector.id

  stop_instance_before_detaching = true
}
