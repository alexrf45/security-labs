variable "project" {
  description = "Must match the range-network project tag; used to discover shared plumbing."
  type        = string
  default     = "security-labs"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# --- Tailscale ----------------------------------------------------------------
variable "tailscale_auth_key" {
  description = "Tailscale (ephemeral, pre-authorized, reusable) auth key for the subnet router. Provided at apply time from 1Password via `op run -- ... TF_VAR_tailscale_auth_key=op://...`; never hardcoded (secrets.md). Ends up in local state and in instance user_data, which any principal with ec2:DescribeInstanceAttribute can read; cloud-init writes it to a 0600 tmpfs file rather than the command line so it stays out of the instance logs and the process table. Reusable is required because the router is recreated every session; rotate the key in the Tailscale console if the account is ever shared."
  type        = string
  sensitive   = true
}

variable "tailnet_hostname" {
  description = "Hostname the subnet router registers in the tailnet."
  type        = string
  default     = "range-router"
}

# --- Instance sizing (ADR-0011 §2 per-session table) --------------------------
variable "router_instance_type" {
  type    = string
  default = "t4g.micro"
}

variable "attacker_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "collector_instance_type" {
  # The single-node Wazuh stack (manager + OpenSearch indexer + dashboard) needs
  # ~4 GB; t4g.small (2 GB) OOMs. t4g.medium is the Wazuh-capable default
  # (+$0.0168/hr over t4g.small = +~$0.13 per 8h session).
  type    = string
  default = "t4g.medium"
}

# --- AMI selection (data-source filters; defaults over hardcoded IDs) ----------
variable "ubuntu_arm_ami_owner" {
  description = "Canonical."
  type        = string
  default     = "099720109477"
}

variable "ubuntu_arm_ami_name" {
  description = "Ubuntu 24.04 LTS arm64 name filter (router + collector)."
  type        = string
  default     = "ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*"
}

variable "kali_ami_owner" {
  description = "Owner for the Kali AMI lookup. Default is the `aws-marketplace` owner alias, which is what actually owns a Marketplace product AMI — Kali is not published under an Offensive Security account ID, so the previous numeric default (679593333241) was the aws-marketplace account by another name rather than a publisher. Verify the AMI resolves before first use: aws ec2 describe-images --owners aws-marketplace --filters 'Name=name,Values=kali-last-snapshot-amd64-*'. The Marketplace subscription is the one documented per-account click-ops step (ADR-0011 §6)."
  type        = string
  default     = "aws-marketplace"
}

variable "kali_ami_name" {
  description = "Kali rolling amd64 AMI name filter (attacker)."
  type        = string
  default     = "kali-last-snapshot-amd64-*"
}

variable "router_root_gb" {
  type    = number
  default = 8
}

variable "attacker_root_gb" {
  type    = number
  default = 40
}

variable "collector_root_gb" {
  type    = number
  default = 20
}

variable "siem_mount_point" {
  description = "Where the persistent SIEM volume is mounted on the collector."
  type        = string
  default     = "/data"
}

# --- Wazuh / SIEM provisioning ------------------------------------------------
variable "wazuh_version" {
  description = "Wazuh release branch to install on the collector (manager + indexer + dashboard). Selects the installer at https://packages.wazuh.com/<version>/wazuh-install.sh, which installs that branch's latest patch. Keep wazuh_agent_pkg on the same branch."
  type        = string
  default     = "4.14"
}

variable "wazuh_indexer_heap" {
  description = "JVM heap for the Wazuh indexer, written to /etc/wazuh-indexer/jvm.options as matching -Xms/-Xmx values. Wazuh documents heap = half of system RAM, which is 2g on the t4g.medium default — but the manager and the Node-based dashboard share that RAM, and the documented all-in-one floor (4 vCPU / 8 GiB) is above this instance, so 1g leaves more headroom and is ample for a handful of agents. Raise it alongside collector_instance_type if you add agents."
  type        = string
  default     = "1g"

  validation {
    condition     = can(regex("^[1-9][0-9]*[mg]$", var.wazuh_indexer_heap))
    error_message = "wazuh_indexer_heap must be a JVM size such as \"1g\", \"1536m\" or \"2g\"."
  }
}

variable "enable_agent_package_mirror" {
  description = "Have the collector mirror Wazuh (and Sysmon) installers on a local HTTP port for air-gapped victim hosts to pull. Must match the same-named flag in range-network for the network path to exist."
  type        = bool
  default     = false
}

variable "agent_package_mirror_port" {
  description = "Port the collector serves the installer mirror on. Must match range-network."
  type        = number
  default     = 8080
}

variable "serve_sysmon" {
  description = "Also mirror Sysmon + a sysmon config for Windows victims (needs enable_agent_package_mirror)."
  type        = bool
  default     = true
}

variable "wazuh_agent_pkg" {
  description = "Full Wazuh agent package version the collector mirrors, as it appears in the filename (e.g. 4.14.6-1 for wazuh-agent-4.14.6-1.msi). Must be on the same branch as wazuh_version — an agent from a different branch than the manager is an unsupported pairing, and the mirror would serve it to every victim."
  type        = string
  default     = "4.14.6-1"

  validation {
    condition     = startswith(var.wazuh_agent_pkg, "${var.wazuh_version}.")
    error_message = "wazuh_agent_pkg must start with wazuh_version followed by a dot (e.g. version 4.14 -> package 4.14.6-1). The manager and agent have to move in lockstep."
  }
}

# --- Attacker box (SCRT) ------------------------------------------------------
variable "scrt_repo_url" {
  description = "The user's SCRT daily-driver repo. The attacker box clones it and runs its own build scripts for identical tooling + shell."
  type        = string
  default     = "https://github.com/alexrf45/SCRT.git"
}

variable "attacker_install_bugbounty" {
  description = "Also run SCRT's 2-tools.sh (httpx, subfinder, katana, dnsx, ...). Off by default, matching the SCRT base Dockerfile."
  type        = bool
  default     = false
}

variable "attacker_enable_gui" {
  description = "Install an i3 desktop reachable over xrdp (RDP via Tailscale/router). tmux ships with SCRT regardless."
  type        = bool
  default     = true
}

variable "attacker_rdp_password" {
  description = "Password for the kali user so xrdp/i3 can be logged into. Inject from 1Password at apply time; empty leaves the GUI installed but xrdp login unconfigured. Lands in local state AND in instance user_data. user_data is NOT IMDSv2-protected in any meaningful sense: IMDSv2 only constrains reads from the instance, while any principal holding ec2:DescribeInstanceAttribute can read it from the control plane. The bootstrap script keeps it out of the instance logs; treat the value as compromised if the range is shared, and rotate at teardown."
  type        = string
  sensitive   = true
  default     = ""
}

# --- Operator SSH access ------------------------------------------------------
# `tailscale up --ssh` on the router gives a shell on the ROUTER ONLY. The attacker
# and collector are reached by ordinary SSH to their private IPs over the router's
# advertised ops route, so they need an EC2 key pair: both the Kali and the Ubuntu
# AMI ship `PasswordAuthentication no`, and attacker_rdp_password is xrdp-only.
# No security group anywhere permits 22 from 0.0.0.0/0 — entry stays Tailscale-only
# (range-safety.md §3).
#
# The keypair is GENERATED AND KEPT IN 1PASSWORD (an "SSH Key" item), so no private
# key ever lands on the workstation: 1Password's SSH agent serves the private half to
# the ssh client, and only the public half is passed in here at apply time. See the
# ops-tier README for the item creation and the agent.toml vault scoping.
variable "ssh_public_key" {
  description = "OpenSSH public key installed on all three ops hosts. Supply at apply time from the 1Password SSH Key item, never from a file on disk: `TF_VAR_ssh_public_key=\"op://Security/range-ssh/public key\"` under `op run --`. This is the PUBLIC half, so it is deliberately NOT marked sensitive — you want to see it in plan output to confirm the right key landed. Leave empty and set ssh_key_name to reuse a key pair that already exists in the account."
  type        = string
  default     = ""

  # Catches the failure mode that sourcing from 1Password introduces: if the op://
  # reference does not resolve (unquoted space in `public key`, wrong vault, no
  # session) the literal reference string is passed through, and AWS would reject it
  # mid-apply. Also refuses a PRIVATE key, which would otherwise be written to local
  # state in plaintext (secrets.md).
  validation {
    condition = var.ssh_public_key == "" || can(regex(
      "^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com|sk-ecdsa-sha2-nistp256@openssh\\.com) AAAA[0-9A-Za-z+/=]+( .*)?$",
      trimspace(var.ssh_public_key)
    ))
    error_message = "ssh_public_key must be a single-line OpenSSH PUBLIC key (`ssh-ed25519 AAAA...`). A literal `op://...` string means the reference did not resolve — quote the whole reference, since the SSH Key item's field is named `public key` (with a space). A `-----BEGIN ...` block means the private key was passed by mistake; never do that, it would be written to local state in plaintext."
  }
}

variable "ssh_key_name" {
  description = "Name of an EXISTING EC2 key pair to attach instead of creating one. Ignored when ssh_public_key is set."
  type        = string
  default     = ""
}
