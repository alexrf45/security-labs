variable "project" {
  description = "Must match the range-network project tag (used for cross-root discovery)."
  type        = string
  default     = "security-labs"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "forest_a_domain" {
  description = "Root domain of forest A, in victim00."
  type        = string
  default     = "forest-a.lab"
}

variable "forest_b_domain" {
  description = "Root domain of forest B (in victim01)."
  type        = string
  default     = "forest-b.lab"
}

variable "forest_a_netbios" {
  type    = string
  default = "FORESTA"
}

variable "forest_b_netbios" {
  type    = string
  default = "FORESTB"
}

variable "forest_a_subnet_name" {
  type    = string
  default = "victim00"
}

variable "forest_b_subnet_name" {
  type    = string
  default = "victim01"
}

variable "domain_admin_password" {
  description = "Domain admin password, applied to both forests. Inject from 1Password at apply time."
  type        = string
  sensitive   = true
}

variable "safe_mode_password" {
  description = "Directory Services Restore Mode (DSRM) password for both DCs."
  type        = string
  sensitive   = true
}

variable "dc_instance_type" {
  description = "Instance type for the domain controllers."
  type        = string
  default     = "t3.medium"
}

variable "member_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "member_use_spot" {
  description = "Run the two member workstations on spot. DCs are never spot: a reclaim tears down the trust."
  type        = bool
  default     = false
}

variable "member_spot_max_price" {
  description = "Max spot price for members when member_use_spot is true. Empty string = on-demand price cap."
  type        = string
  default     = "0.03"
}

variable "windows_ami_owner" {
  description = "AWS-owned license-included Windows Server AMIs."
  type        = string
  default     = "amazon"
}

variable "windows_ami_name" {
  description = "License-included Windows Server 2022 Base AMI name filter."
  type        = string
  default     = "Windows_Server-2022-English-Full-Base-*"
}

variable "windows_root_gb" {
  type    = number
  default = 50
}

variable "enable_wazuh_agents" {
  description = "Install the Wazuh agent + Sysmon on each victim and enroll to the collector. Requires ops-tier applied first."
  type        = bool
  default     = true
}

variable "wazuh_agent_group" {
  description = "Wazuh agent group the victims register into."
  type        = string
  default     = "windows"
}

variable "wazuh_mirror_port" {
  description = "Port the collector serves agent installers on. Must match ops-tier and range-network."
  type        = number
  default     = 8080
}

variable "install_sysmon" {
  description = "Install Sysmon (SwiftOnSecurity config) and forward its channel to Wazuh."
  type        = bool
  default     = true
}
