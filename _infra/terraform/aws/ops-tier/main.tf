locals {
  # IMDSv2 required + hop limit 1 everywhere (range-safety.md §5). No instance
  # profile is attached to any host in this root.
  imdsv2 = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
}

# --- Tailscale subnet router --------------------------------------------------
resource "aws_instance" "router" {
  ami                    = data.aws_ami.ubuntu_arm.id
  instance_type          = var.router_instance_type
  subnet_id              = data.aws_subnet.ops.id
  vpc_security_group_ids = [data.aws_security_group.router.id]

  # Subnet routers must forward traffic for other addresses.
  source_dest_check = false

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3" # never gp2 (ADR-0011 §2)
    volume_size = var.router_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/router.cloud-init.yaml.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    ops_cidr           = data.aws_subnet.ops.cidr_block
    hostname           = var.tailnet_hostname
  })

  tags = {
    Name = "${var.project}-router"
    Tier = "ops"
    Role = "router"
  }
}

# The one public IPv4 in the whole range, present only while a session runs
# (ADR-0011 §4d). $0.005/hr.
resource "aws_eip" "router" {
  instance = aws_instance.router.id
  domain   = "vpc"

  tags = {
    Name = "${var.project}-router-eip"
  }

  depends_on = [aws_instance.router]
}

# --- Attacker (Kali) ----------------------------------------------------------
resource "aws_instance" "attacker" {
  ami                         = data.aws_ami.kali.id
  instance_type               = var.attacker_instance_type
  subnet_id                   = data.aws_subnet.ops.id
  vpc_security_group_ids      = [data.aws_security_group.attacker.id]
  associate_public_ip_address = false

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

  tags = {
    Name = "${var.project}-attacker"
    Tier = "ops"
    Role = "attacker"
  }
}

# --- Collector / SIEM ---------------------------------------------------------
resource "aws_instance" "collector" {
  ami                         = data.aws_ami.ubuntu_arm.id
  instance_type               = var.collector_instance_type
  subnet_id                   = data.aws_subnet.ops.id
  vpc_security_group_ids      = [data.aws_security_group.collector.id]
  associate_public_ip_address = false

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
    mount_point     = var.siem_mount_point
    wazuh_version   = var.wazuh_version
    enable_mirror   = var.enable_agent_package_mirror
    mirror_port     = var.agent_package_mirror_port
    serve_sysmon    = var.serve_sysmon
    wazuh_agent_pkg = var.wazuh_agent_pkg
  })

  tags = {
    Name = "${var.project}-collector"
    Tier = "ops"
    Role = "collector"
  }
}

# Attach the persistent SIEM volume discovered from range-network.
resource "aws_volume_attachment" "siem" {
  device_name = "/dev/sdf"
  volume_id   = data.aws_ebs_volume.siem.id
  instance_id = aws_instance.collector.id

  # On teardown, detach without destroying the volume (prevent_destroy is set on
  # the volume in range-network anyway).
  stop_instance_before_detaching = true
}
