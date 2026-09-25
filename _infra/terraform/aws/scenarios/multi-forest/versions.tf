terraform {
  required_version = ">= 1.9.0"

  # Local state (terraform.md). Disposable scenario root: its own state, separate
  # blast radius from range-network. Never commit *.tfstate.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0" # identical pin across all three roots
    }
  }
}
