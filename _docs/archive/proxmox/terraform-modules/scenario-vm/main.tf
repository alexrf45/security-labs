# Reusable scenario VM: clone a Packer template onto NODE-LOCAL storage, attach to
# the scenario's vnet(s), seed first-boot config via cloud-init/cloudbase-init, and
# (for victims) enforce the det_isolation firewall group. No disk ever lands on
# TrueNAS; isolation is structural (gateway-less vnet) + this belt-and-suspenders.

locals {
  # Effective isolation = master switch AND per-host flag. Dual-homed ops boxes
  # (attacker/collector) set isolate=false so they keep ops connectivity.
  isolated_hosts = {
    for k, h in var.hosts : k => h
    if coalesce(h.isolate, true) && var.isolation.enable_firewall
  }

  user_data_hosts = { for k, h in var.hosts : k => h if h.user_data != null }
}

# Per-host first-boot user-data uploaded as a Proxmox snippet.
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = local.user_data_hosts

  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = each.value.node

  source_raw {
    data      = each.value.user_data
    file_name = "${var.scenario}-${each.key}-userdata.${each.value.os_type == "windows" ? "ps1" : "yaml"}"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.hosts

  name      = "${var.scenario}-${each.key}"
  node_name = each.value.node
  tags      = ["security-lab", var.scenario, each.value.role]

  clone {
    vm_id        = each.value.template_id
    node_name    = var.template_node
    datastore_id = var.node_local_datastore # cloned disks -> node-local
    full         = true
  }

  cpu {
    cores = each.value.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
  }

  # One NIC per declared network. The SDN vnet bridge already carries its VLAN tag,
  # so vlan_id is intentionally NOT set. NIC firewall is on for isolated victims.
  dynamic "network_device" {
    for_each = each.value.networks
    content {
      bridge   = network_device.value.bridge
      model    = "virtio"
      firewall = coalesce(each.value.isolate, true) && var.isolation.enable_firewall
    }
  }

  initialization {
    datastore_id = var.node_local_datastore

    dynamic "ip_config" {
      for_each = each.value.networks
      content {
        ipv4 {
          address = ip_config.value.address
          gateway = try(ip_config.value.gateway, null) # detonation NICs have NO gateway
        }
      }
    }

    dns {
      servers = var.dns.servers
      domain  = var.dns.domain
    }

    user_account {
      username = var.ci_user.username
      password = var.ci_user.password
      keys     = var.ci_user.keys
    }

    user_data_file_id = try(proxmox_virtual_environment_file.user_data[each.key].id, null)
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_account[0].password,
    ]
  }
}
