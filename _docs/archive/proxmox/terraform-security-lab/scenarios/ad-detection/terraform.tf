terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
  }

  # Disposable scenario → LOCAL state (per terraform-buisness-rules.md). A wiped or
  # compromised scenario can never corrupt shared infrastructure state.
  backend "local" {}
}
