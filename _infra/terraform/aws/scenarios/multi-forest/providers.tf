provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      ADR       = "0011"
      Component = "scenario-multi-forest"
    }
  }
}
