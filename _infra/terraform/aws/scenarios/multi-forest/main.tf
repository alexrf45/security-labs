locals {
  # IMDSv2 required, hop limit 1, and NO instance profile on every victim host
  # (range-safety.md §5): a compromised victim cannot mint AWS credentials.
  imdsv2 = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
}

# ============================ Forest A (victim00) ==============================
resource "aws_instance" "dc_a" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.dc_instance_type # DCs never spot (§2 spot policy)
  subnet_id                   = data.aws_subnet.forest_a.id
  private_ip                  = local.dc_a_ip
  vpc_security_group_ids      = [data.aws_security_group.victim.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.windows_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/dc.ps1.tftpl", {
    domain                = var.forest_a_domain
    netbios               = var.forest_a_netbios
    domain_admin_password = var.domain_admin_password
    safe_mode_password    = var.safe_mode_password
    peer_domain           = var.forest_b_domain
    peer_dc_ip            = local.dc_b_ip
    create_trust          = false # trust is created from DC-B
    wazuh_manager_ip      = local.wazuh_manager_ip
    wazuh_mirror_port     = var.wazuh_mirror_port
    wazuh_agent_group     = var.wazuh_agent_group
    install_sysmon        = var.install_sysmon
  })

  # A changed user_data must actually re-run. The provider default is an
  # in-place attribute update, which leaves the OLD bootstrap on the box and
  # makes a "fixed" script a no-op. A half-promoted DC cannot be repaired in
  # place anyway, so replacement is the only honest behaviour here.
  user_data_replace_on_change = true

  tags = {
    Name   = "${var.project}-dc-a"
    Role   = "domain-controller"
    Forest = var.forest_a_domain
  }
}

resource "aws_instance" "ws_a" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.member_instance_type
  subnet_id                   = data.aws_subnet.forest_a.id
  private_ip                  = local.ws_a_ip
  vpc_security_group_ids      = [data.aws_security_group.victim.id]
  associate_public_ip_address = false

  dynamic "instance_market_options" {
    for_each = var.member_use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.member_spot_max_price
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.windows_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/member.ps1.tftpl", {
    domain                = var.forest_a_domain
    netbios               = var.forest_a_netbios
    domain_admin_password = var.domain_admin_password
    dc_ip                 = local.dc_a_ip
    wazuh_manager_ip      = local.wazuh_manager_ip
    wazuh_mirror_port     = var.wazuh_mirror_port
    wazuh_agent_group     = var.wazuh_agent_group
    install_sysmon        = var.install_sysmon
  })

  # Changed user_data re-runs by replacing the host (see DC-A above).
  user_data_replace_on_change = true

  tags = {
    Name   = "${var.project}-ws-a"
    Role   = "member-workstation"
    Forest = var.forest_a_domain
  }
}

# ============================ Forest B (victim01) ==============================
resource "aws_instance" "dc_b" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.dc_instance_type
  subnet_id                   = data.aws_subnet.forest_b.id
  private_ip                  = local.dc_b_ip
  vpc_security_group_ids      = [data.aws_security_group.victim.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.windows_root_gb
    encrypted   = true
  }

  # DC-B carries the trust bootstrap (create_trust = true).
  user_data = templatefile("${path.module}/scripts/dc.ps1.tftpl", {
    domain                = var.forest_b_domain
    netbios               = var.forest_b_netbios
    domain_admin_password = var.domain_admin_password
    safe_mode_password    = var.safe_mode_password
    peer_domain           = var.forest_a_domain
    peer_dc_ip            = local.dc_a_ip
    create_trust          = true
    wazuh_manager_ip      = local.wazuh_manager_ip
    wazuh_mirror_port     = var.wazuh_mirror_port
    wazuh_agent_group     = var.wazuh_agent_group
    install_sysmon        = var.install_sysmon
  })

  # Changed user_data re-runs by replacing the host (see DC-A above).
  user_data_replace_on_change = true

  tags = {
    Name   = "${var.project}-dc-b"
    Role   = "domain-controller"
    Forest = var.forest_b_domain
  }
}

resource "aws_instance" "ws_b" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.member_instance_type
  subnet_id                   = data.aws_subnet.forest_b.id
  private_ip                  = local.ws_b_ip
  vpc_security_group_ids      = [data.aws_security_group.victim.id]
  associate_public_ip_address = false

  dynamic "instance_market_options" {
    for_each = var.member_use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price                      = var.member_spot_max_price
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  metadata_options {
    http_endpoint               = local.imdsv2.http_endpoint
    http_tokens                 = local.imdsv2.http_tokens
    http_put_response_hop_limit = local.imdsv2.http_put_response_hop_limit
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.windows_root_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/member.ps1.tftpl", {
    domain                = var.forest_b_domain
    netbios               = var.forest_b_netbios
    domain_admin_password = var.domain_admin_password
    dc_ip                 = local.dc_b_ip
    wazuh_manager_ip      = local.wazuh_manager_ip
    wazuh_mirror_port     = var.wazuh_mirror_port
    wazuh_agent_group     = var.wazuh_agent_group
    install_sysmon        = var.install_sysmon
  })

  # Changed user_data re-runs by replacing the host (see DC-A above).
  user_data_replace_on_change = true

  tags = {
    Name   = "${var.project}-ws-b"
    Role   = "member-workstation"
    Forest = var.forest_b_domain
  }
}
