variable "project" {
  description = "Project/name prefix and the Project tag used for cross-root resource discovery."
  type        = string
  default     = "security-labs"
}

variable "aws_region" {
  description = "AWS region. us-east-1 chosen for price (ADR-0011 §3)."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Single AZ for the whole range, to avoid cross-AZ transfer charges (cost-guardrails.md). The persistent SIEM volume and every instance must share it."
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "VPC supernet. The implicit local route spans this whole range (ADR-0011 §4c)."
  type        = string
  default     = "10.40.0.0/16"
}

variable "ops_subnet_cidr" {
  description = "Ops subnet: the only subnet with a default route to the IGW. Mnemonic 40 = ops (carried from ADR-0009)."
  type        = string
  default     = "10.40.10.0/24"
}

variable "victim_subnets" {
  description = "Victim subnets, name => CIDR. No default route, no public IP. Mnemonic 5N = victim. Multi-forest (ADR-0011 §7) uses victim00 + victim01. Keys become the SubnetName tag that scenarios discover by, so renaming one breaks any scenario pinned to it."
  type        = map(string)
  default = {
    victim00 = "10.40.50.0/24"
    victim01 = "10.40.51.0/24"
  }

  # nacl.tf numbers the per-CIDR rules 100+i. Past 99 subnets that arithmetic would
  # collide with rule 200 (the allow-from-ops rule) and the apply would fail on a
  # duplicate rule number rather than anything legible.
  validation {
    condition     = length(var.victim_subnets) <= 99
    error_message = "At most 99 victim subnets: nacl.tf numbers them 100+i, which must stay below rule 200."
  }
}

variable "public_dns_resolvers" {
  description = "Public resolvers handed out by the custom DHCP option set. VPC DNS is disabled (ADR-0011 §4b) so DNS works only where a route to the internet exists (ops), and is structurally dead in victim subnets."
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}

variable "telemetry_ports" {
  description = "TCP ports a victim host may use to reach the collector (Wazuh: 1514 events, 1515 enrollment). The only ops ports a victim subnet is permitted to initiate to, besides ephemeral return traffic (ADR-0011 §4c)."
  type        = list(number)
  default     = [1514, 1515]

  # nacl.tf numbers these 200+j; rule 250 is the opt-in package mirror, so more than 49
  # telemetry ports would collide.
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
  description = "Size (GiB) of the persistent SIEM index volume — the one deliberately non-ephemeral piece (ADR-0011 §2)."
  type        = number
  default     = 30
}

variable "budget_limit" {
  description = "Monthly AWS Budgets limit in USD. The hard ceiling is $30 (cost-guardrails.md)."
  type        = number
  default     = 30
}

variable "budget_alert_emails" {
  description = "Email addresses for budget alarms at 50/80/100 percent of budget_limit. REQUIRED, deliberately with no default: cost-guardrails.md rule 4 makes a budget alarm mandatory, and AWS Budgets will happily create a budget with zero notifications, which looks identical in the console to a working one. Supply at apply time (TF_VAR_budget_alert_emails='[\"you@example.com\"]') so no address is committed. AWS sends a one-time subscription confirmation per address; until it is accepted, no alarm is delivered."
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
  description = "Opt-in (default OFF): open ONE controlled, logged victim->collector port so victim hosts can pull Wazuh/Sysmon installers from the collector's local mirror. Victim subnets have no internet route, so without this (or a baked AMI) agents cannot be installed. This is the range-safety.md §6 controlled-allow-list exception, deliberately not part of the default isolation baseline."
  type        = bool
  default     = false
}

variable "agent_package_mirror_port" {
  description = "TCP port the collector serves agent installers on when enable_agent_package_mirror is true."
  type        = number
  default     = 8080
}
