terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
  }

  backend "s3" {}
}




module "test-range" {
  source       = "../../modules/range-network"
  lab_firewall = var.lab_firewall
  pve          = var.pve
  lab_sdn      = var.lab_sdn

}
