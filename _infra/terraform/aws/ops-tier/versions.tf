terraform {
  required_version = ">= 1.9.0"

  # Local state (terraform.md). Per-session root: applied at session start,
  # destroyed at teardown. Never commit *.tfstate.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0" # identical pin across all three roots
    }
  }
}
