terraform {
  required_version = ">= 1.9.0"

  # Local state. It holds plaintext secrets: gitignored, never committed.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0" # pinned exact per terraform.md; keep identical across all three roots
    }
  }
  backend "local" {

  }
}
