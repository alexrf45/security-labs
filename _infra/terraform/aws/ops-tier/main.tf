locals {
  # IMDSv2 required + hop limit 1 everywhere (range-safety.md §5). No instance
  # profile is attached to any host in this root.
  imdsv2 = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ssh_public_key = trimspace(var.ssh_public_key)
}

# --- Operator SSH key ---------------------------------------------------------
# What makes `ssh <user>@<private-ip>` work once you are on the tailnet and the
# router is advertising the ops route. Reachability is still Tailscale-only: no SG
# in the range permits 22 from the internet (range-safety.md §3).
#
# Only the PUBLIC half is handled here. The private key stays in the 1Password
# "SSH Key" item and is served to the ssh client by 1Password's SSH agent, so no
# private key file exists on the workstation and none can reach a victim subnet
# (range-safety.md §7). trimspace() because `op read` / `$(...)` round-trips differ
# in whether they keep a trailing newline.
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

# A plan-time warning, not a hard failure: standing the tier up without a key is
# legal but leaves no shell on the attacker or the collector.
check "operator_ssh_key" {
  assert {
    condition     = local.ssh_public_key != "" || var.ssh_key_name != ""
    error_message = "No SSH key pair configured (ssh_public_key / ssh_key_name are both empty). Pass the public half from 1Password: TF_VAR_ssh_public_key=\"op://Security/security_labs/public key\" under `op run --`. The router is still reachable via `tailscale ssh`, but there will be no shell on the attacker or the collector."
  }
}

# --- Tailscale subnet router --------------------------------------------------
resource "aws_instance" "router" {
  ami                    = data.aws_ami.ubuntu_arm.id
  instance_type          = var.router_instance_type
  subnet_id              = data.aws_subnet.ops.id
  vpc_security_group_ids = [data.aws_security_group.router.id]
  key_name               = local.ssh_key_name

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

  # A changed user_data must actually re-run. The provider default is an
  # in-place attribute update, which leaves the OLD bootstrap on the box and
  # makes a "fixed" script a no-op until the instance is tainted by hand.
  user_data_replace_on_change = true

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
}

# --- Attacker (Kali) ----------------------------------------------------------
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

  # Changed user_data re-runs by replacing the host (see the router above).
  user_data_replace_on_change = true

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
  })

  # Changed user_data re-runs by replacing the host (see the router above).
  user_data_replace_on_change = true

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
