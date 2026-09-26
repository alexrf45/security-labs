terraform {
  required_version = ">= 1.9.0"

  # Local state. Per-session root; never commit *.tfstate.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0" # identical pin across all three roots
    }
  }
}
