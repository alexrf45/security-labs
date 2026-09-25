provider "proxmox" {
  endpoint = "https://${var.pve_endpoint}:8006"
  insecure = true
  ssh {
    agent = false
  }

  api_token = var.pve_api_token != "" ? var.pve_api_token : null
  username  = var.pve_api_token == "" ? "root@pam" : null
  password  = var.pve_api_token == "" ? var.pve_password : null
}
