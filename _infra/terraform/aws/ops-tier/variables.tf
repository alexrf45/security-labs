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
  description = "Tailscale (ephemeral, pre-authorized) auth key for the subnet router. Provided at apply time from 1Password via `op run -- ... TF_VAR_tailscale_auth_key=op://...`; never hardcoded (secrets.md). Ends up in local state, which is treated as sensitive at rest."
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
  description = "Kali Linux publisher account (Offensive Security). Verify against the Marketplace listing before first use; the Marketplace subscription is the one documented per-account click-ops step (ADR-0011 §6)."
  type        = string
  default     = "679593333241"
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
  description = "Wazuh version to install on the collector (single-node manager + indexer + dashboard)."
  type        = string
  default     = "4.9"
}

variable "enable_agent_package_mirror" {
  description = "Have the collector mirror Wazuh (and Sysmon) installers on a local HTTP port for air-gapped detonation hosts to pull. Must match the same-named flag in range-network for the network path to exist."
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
  description = "Full Wazuh agent package version (filename component) the collector mirrors, e.g. 4.9.0-1."
  type        = string
  default     = "4.9.0-1"
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
  description = "Password for the kali user so xrdp/i3 can be logged into. Inject from 1Password at apply time; empty leaves the GUI installed but xrdp login unconfigured. Lands in local state (sensitive) and instance user_data (IMDSv2-only)."
  type        = string
  sensitive   = true
  default     = ""
}
