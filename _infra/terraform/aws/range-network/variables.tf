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

variable "detonation_subnets" {
  description = "Detonation subnets, name => CIDR. No default route, no public IP. Mnemonic 5N = detonation. Multi-forest (ADR-0011 §7) uses det00 + det01."
  type        = map(string)
  default = {
    det00 = "10.40.50.0/24"
    det01 = "10.40.51.0/24"
  }
}

variable "public_dns_resolvers" {
  description = "Public resolvers handed out by the custom DHCP option set. VPC DNS is disabled (ADR-0011 §4b) so DNS works only where a route to the internet exists (ops), and is structurally dead in detonation subnets."
  type        = list(string)
  default     = ["1.1.1.1", "1.0.0.1"]
}

variable "telemetry_ports" {
  description = "TCP ports a detonation host may use to reach the collector (Wazuh: 1514 events, 1515 enrollment). The only ops ports a detonation subnet is permitted to initiate to, besides ephemeral return traffic (ADR-0011 §4c)."
  type        = list(number)
  default     = [1514, 1515]
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
  description = "Email addresses for budget alarms at 50/80/100 percent. Set in your (SOPS-encrypted) terraform.tfvars; left empty here so no address is baked into the repo. With no addresses, the budget is created without notifications."
  type        = list(string)
  default     = []
}

variable "enable_agent_package_mirror" {
  description = "Opt-in (default OFF): open ONE controlled, logged det->collector port so detonation hosts can pull Wazuh/Sysmon installers from the collector's local mirror. Detonation subnets have no internet route, so without this (or a baked AMI) agents cannot be installed. This is the range-safety.md §6 controlled-allow-list exception, deliberately not part of the default isolation baseline."
  type        = bool
  default     = false
}

variable "agent_package_mirror_port" {
  description = "TCP port the collector serves agent installers on when enable_agent_package_mirror is true."
  type        = number
  default     = 8080
}
