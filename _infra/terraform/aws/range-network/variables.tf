variable "project" {
  description = "Project/name prefix and the Project tag used for cross-root resource discovery."
  type        = string
  default     = "security-labs"
}

variable "aws_region" {
  description = "AWS region. us-east-1 chosen for price."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Single AZ for the whole range. The SIEM volume and every instance must share it."
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "VPC supernet. The implicit local route spans this whole range."
  type        = string
  default     = "10.40.0.0/16"
}

variable "ops_subnet_cidr" {
  description = "Ops subnet for the attacker and collector. Its default route goes through the router, added per session by ops-tier."
  type        = string
  default     = "10.40.10.0/24"
}

variable "edge_subnet_cidr" {
  description = "Edge subnet holding only the Tailscale router: the one subnet with a default route to the IGW."
  type        = string
  default     = "10.40.1.0/28"
}

variable "victim_subnets" {
  description = "Victim subnets, name => CIDR. Keys become the SubnetName tag scenarios discover by; renaming one breaks any scenario pinned to it."
  type        = map(string)
  default = {
    victim00 = "10.40.50.0/24"
    victim01 = "10.40.51.0/24"
  }

  validation {
    condition     = length(var.victim_subnets) <= 99
    error_message = "At most 99 victim subnets: nacl.tf numbers them 100+i, which must stay below rule 200."
  }
}

variable "public_dns_resolvers" {
  description = "Public resolvers handed out by the DHCP option set, since VPC DNS is disabled."
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}

variable "telemetry_ports" {
  description = "TCP ports a victim host may use to reach the collector (Wazuh: 1514 events, 1515 enrollment)."
  type        = list(number)
  default     = [1514, 1515]

  validation {
    condition     = length(var.telemetry_ports) <= 49
    error_message = "At most 49 telemetry ports: nacl.tf numbers them 200+j, which must stay below rule 250 (the package mirror)."
  }

  validation {
    condition     = alltrue([for p in var.telemetry_ports : p > 0 && p < 65536])
    error_message = "telemetry_ports must be valid TCP port numbers."
  }
}

variable "siem_volume_size" {
  description = "Size (GiB) of the persistent SIEM index volume — the one deliberately non-ephemeral piece."
  type        = number
  default     = 30
}

variable "budget_limit" {
  description = "Monthly AWS Budgets limit in USD. The hard ceiling is $30 (cost-guardrails.md)."
  type        = number
  default     = 30
}

variable "budget_alert_emails" {
  description = "Email addresses for budget alarms at 50/80/100 percent of budget_limit. Required, with no default. Supply at apply time so no address is committed."
  type        = list(string)

  validation {
    condition     = length(var.budget_alert_emails) > 0
    error_message = "budget_alert_emails must contain at least one address. A budget with no notifications is an alarm-less budget, which violates cost-guardrails.md rule 4 while appearing configured."
  }

  validation {
    condition     = alltrue([for e in var.budget_alert_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[A-Za-z]{2,}$", e))])
    error_message = "Every entry in budget_alert_emails must be an email address. AWS accepts a malformed subscriber without error and then never delivers the alarm."
  }
}

variable "enable_agent_package_mirror" {
  description = "Open one victim->collector port so air-gapped victims can pull agent installers from the collector mirror. Off by default; the range-safety.md §6 allow-list exception."
  type        = bool
  default     = false
}

variable "agent_package_mirror_port" {
  description = "TCP port the collector serves agent installers on when enable_agent_package_mirror is true."
  type        = number
  default     = 8080
}
