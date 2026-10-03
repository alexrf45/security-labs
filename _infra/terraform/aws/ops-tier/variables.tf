variable "project" {
  description = "Must match the range-network project tag; used to discover shared plumbing."
  type        = string
  default     = "security-labs"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key the subnet router joins the tailnet with. Must be reusable, ephemeral and pre-authorized."
  type        = string
  sensitive   = true

  validation {
    condition     = !startswith(var.tailscale_auth_key, "op://")
    error_message = "tailscale_auth_key is an unresolved 1Password reference. Run under `op run --`."
  }
}

variable "tailnet_hostname" {
  description = "Hostname the subnet router registers in the tailnet."
  type        = string
  default     = "range-router"
}

variable "router_instance_type" {
  description = "Instance type for the Tailscale subnet router (arm64)."
  type        = string
  default     = "t4g.micro"
}

variable "attacker_instance_type" {
  description = "Instance type for the Kali attacker box (x86_64)."
  type        = string
  default     = "t3.medium"
}

variable "collector_instance_type" {
  description = "Instance type for the Wazuh collector. Must be x86_64 to match the collector AMI."
  type        = string
  default     = "t3.medium"
}

variable "ubuntu_ami_owner" {
  description = "AMI owner account for both Ubuntu lookups (Canonical)."
  type        = string
  default     = "099720109477"
}

variable "ubuntu_arm_ami_name" {
  description = "Name filter for the router's Ubuntu 24.04 arm64 AMI."
  type        = string
  default     = "ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*"
}

variable "ubuntu_x86_ami_name" {
  description = "Name filter for the collector's Ubuntu 24.04 amd64 AMI."
  type        = string
  default     = "ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"
}

variable "kali_ami_owner" {
  description = "AMI owner for the Kali lookup."
  type        = string
  default     = "aws-marketplace"
}

variable "kali_ami_name" {
  description = "Name filter for the attacker's Kali rolling amd64 AMI. The UUID suffix pins the official Kali Marketplace product."
  type        = string
  default     = "debian-kali-last-snapshot-amd64-*-804fcc46-63fc-4eb6-85a1-50e66d6c7215"
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
  description = "Collector root volume (GiB). Holds the Wazuh packages and the vulnerability feed, which the manager downloads at first start."
  type        = number
  default     = 40
}

variable "siem_mount_point" {
  description = "Where the persistent SIEM volume is mounted on the collector."
  type        = string
  default     = "/data"
}

# --- Wazuh / SIEM provisioning ------------------------------------------------
variable "wazuh_version" {
  description = "Wazuh release branch installed on the collector (manager + indexer + dashboard)."
  type        = string
  default     = "4.14"
}

variable "wazuh_admin_password" {
  description = "Password for the Wazuh dashboard/indexer `admin` user, re-applied at every collector boot."
  type        = string
  sensitive   = true

  validation {
    condition     = !startswith(var.wazuh_admin_password, "op://")
    error_message = "wazuh_admin_password is an unresolved 1Password reference. Run under `op run --`."
  }

  validation {
    condition = (
      can(regex("^[A-Za-z0-9.*+?-]{8,64}$", var.wazuh_admin_password)) &&
      can(regex("[A-Z]", var.wazuh_admin_password)) &&
      can(regex("[a-z]", var.wazuh_admin_password)) &&
      can(regex("[0-9]", var.wazuh_admin_password)) &&
      can(regex("[.*+?-]", var.wazuh_admin_password))
    )
    error_message = "wazuh_admin_password must be 8-64 characters with an upper, a lower, a digit and a symbol, and the only symbols Wazuh accepts are . * + ? -"
  }
}

variable "wazuh_indexer_heap" {
  description = "JVM heap for the Wazuh indexer, written to /etc/wazuh-indexer/jvm.options as -Xms/-Xmx."
  type        = string
  default     = "1g"

  validation {
    condition     = can(regex("^[1-9][0-9]*[mg]$", var.wazuh_indexer_heap))
    error_message = "wazuh_indexer_heap must be a JVM size such as \"1g\", \"1536m\" or \"2g\"."
  }
}

variable "enable_agent_package_mirror" {
  description = "Have the collector mirror Wazuh (and Sysmon) installers on a local HTTP port for air-gapped victims. Must match the same-named flag in range-network."
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
  description = "Wazuh agent package version the collector mirrors, as it appears in the filename (e.g. 4.14.6-1)."
  type        = string
  default     = "4.14.6-1"

  validation {
    condition     = startswith(var.wazuh_agent_pkg, "${var.wazuh_version}.")
    error_message = "wazuh_agent_pkg must start with wazuh_version followed by a dot (e.g. version 4.14 -> package 4.14.6-1). The manager and agent have to move in lockstep."
  }
}

# --- Attacker box (SCRT) ------------------------------------------------------
variable "scrt_repo_url" {
  description = "SCRT repo the attacker box clones and builds for tooling + shell."
  type        = string
  default     = "https://github.com/alexrf45/SCRT.git"
}

variable "attacker_install_bugbounty" {
  description = "Also run SCRT's 2-tools.sh (httpx, subfinder, katana, dnsx, ...)."
  type        = bool
  default     = false
}

variable "attacker_enable_gui" {
  description = "Install an i3 desktop reachable over xrdp."
  type        = bool
  default     = true
}

variable "attacker_rdp_password" {
  description = "Password for the kali user, so xrdp/i3 can be logged into. Empty leaves the GUI installed but xrdp login unconfigured."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !startswith(var.attacker_rdp_password, "op://")
    error_message = "attacker_rdp_password is an unresolved 1Password reference. Run under `op run --`."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed on all three ops hosts. Public half only, so deliberately not sensitive."
  type        = string
  default     = ""

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
