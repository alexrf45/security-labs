# AD detection lab (intentionally attackable): a DC + Win10/Win11 workstations on
# the gateway-less detonation vnet, plus a dual-homed Kali on ops+detonation.
# First-boot PowerShell (cloudbase-init) promotes the forest, seeds Kerberoast /
# AS-REP / weak-ACL misconfigurations, joins the workstations, and installs Sysmon.

locals {
  netbios = upper(element(split(".", var.ad.domain_fqdn), 0))
  cidr    = var.ad.subnet_prefix

  dc_user_data = templatefile("${path.module}/scripts/dc-bootstrap.ps1.tftpl", {
    computer_name      = "DC01"
    domain_fqdn        = var.ad.domain_fqdn
    domain_netbios     = local.netbios
    dsrm_password      = var.domain_admin_password
    seed_user_password = var.seed_user_password
  })

  workstations = {
    ws10 = { name = "WS10", ip = var.ad.ws10_ip, template = var.templates.win10, node = var.placement.ws10 }
    ws11 = { name = "WS11", ip = var.ad.ws11_ip, template = var.templates.win11, node = var.placement.ws11 }
  }
}

module "domain" {
  source = "../../../modules/scenario-vm"

  scenario             = "ad-detection"
  template_node        = var.template_node
  node_local_datastore = var.node_local_datastore
  snippet_datastore    = var.snippet_datastore
  ci_user              = { username = "Administrator", password = var.local_admin_password }
  dns                  = { servers = [var.ad.dc_ip], domain = var.ad.domain_fqdn }
  isolation            = { det_isolation_security_group = var.det_isolation_security_group }

  hosts = merge(
    {
      dc = {
        node        = var.placement.dc
        role        = "dc"
        os_type     = "windows"
        template_id = var.templates.win2022
        cores       = 2
        memory      = 4096
        networks    = [{ bridge = var.det_vnet, address = "${var.ad.dc_ip}/${local.cidr}" }]
        user_data   = local.dc_user_data
      }
    },
    {
      for k, w in local.workstations : k => {
        node        = w.node
        role        = "workstation"
        os_type     = "windows"
        template_id = w.template
        cores       = 2
        memory      = 4096
        networks    = [{ bridge = var.det_vnet, address = "${w.ip}/${local.cidr}" }]
        user_data = templatefile("${path.module}/scripts/workstation-bootstrap.ps1.tftpl", {
          computer_name  = w.name
          domain_fqdn    = var.ad.domain_fqdn
          domain_netbios = local.netbios
          join_user      = "Administrator"
          join_password  = var.local_admin_password
        })
      }
    }
  )
}

# Dual-homed Kali — ops NIC (internet) + detonation NIC (reaches the victims).
# Separate module call so its DNS is a public resolver, not the DC.
module "attacker" {
  source = "../../../modules/scenario-vm"

  scenario             = "ad-detection"
  template_node        = var.template_node
  node_local_datastore = var.node_local_datastore
  snippet_datastore    = var.snippet_datastore
  ci_user              = { username = "kali", password = var.local_admin_password }
  dns                  = { servers = ["1.1.1.1"] }

  hosts = {
    kali = {
      node        = var.placement.kali
      role        = "attacker"
      os_type     = "linux"
      template_id = var.templates.kali
      cores       = 2
      memory      = 4096
      isolate     = false # dual-homed ops box keeps ops connectivity
      networks = [
        { bridge = var.ops_vnet, address = "dhcp" },
        { bridge = var.det_vnet, address = "${var.ad.kali_det_ip}/${local.cidr}" },
      ]
    }
  }
}
