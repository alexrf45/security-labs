terraform {
  required_version = ">= 1.9.0"

  # Local state per .claude/rules/terraform.md — no backend block means the
  # default local backend. State holds plaintext secrets; it is gitignored and
  # handled per .claude/rules/secrets.md. NEVER commit *.tfstate.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0" # pinned exact per terraform.md; keep identical across all three roots
    }
  }
}
