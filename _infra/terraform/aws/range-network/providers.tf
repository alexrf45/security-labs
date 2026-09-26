provider "aws" {
  region = var.aws_region

  # Every range resource is tagged so the ops-tier and scenario roots can
  # discover shared plumbing via tag-filtered data sources (aws_vpc, aws_subnet,
  # aws_security_group) rather than terraform_remote_state: a disposable scenario
  # root must never hold a reader for this root's state file, which contains
  # plaintext secrets (range-safety.md §9).
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "range-network"
    }
  }
}
