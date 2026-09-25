provider "aws" {
  region = var.aws_region

  # Every range resource is tagged so the ops-tier and scenario roots can
  # discover shared plumbing via tag-filtered data sources (aws_vpc, aws_subnet,
  # aws_security_group) rather than terraform_remote_state — a security decision
  # (ADR-0011 §5): a disposable scenario root must never hold a reader for this
  # root's state file, which contains plaintext secrets.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      ADR       = "0011"
      Component = "range-network"
    }
  }
}
