resource "proxmox_virtual_environment_firewall_ipset" "mgmt" {
  name    = "lab-mgmt"
  comment = "Management LAN + TrueNAS — never reachable from a detonation net"

  cidr {
    name = var.lab_firewall.mgmt_cidr
  }
}

resource "proxmox_virtual_environment_firewall_ipset" "ops" {
  name    = "lab-ops"
  comment = "Ops/admin net (Kali, Wazuh, C2)"

  cidr {
    name = var.lab_firewall.ops_cidr
  }
}

resource "proxmox_virtual_environment_firewall_ipset" "detonation" {
  name    = "lab-det"
  comment = "All detonation subnets"

  dynamic "cidr" {
    for_each = var.lab_firewall.det_cidrs
    content {
      name = cidr.value
    }
  }
}

# Belt-and-suspenders: structurally a detonation VM already has no route off its
# gateway-less segment. This group DROPs egress to the mgmt LAN and ops net so an
# accidental SVI/gateway on a detonation VLAN still can't become a pivot path.
# It deliberately does NOT drop the VM's own subnet (same-subnet L2, where the
# dual-homed Wazuh collector and other victims live), so intra-scenario traffic
# and one-way det->collector telemetry keep working.
resource "proxmox_virtual_environment_cluster_firewall_security_group" "det_isolation" {
  name    = "det_isolation"
  comment = "Attach to every detonation VM (scenario-vm module). No pivot to mgmt LAN or ops net."

  rule {
    type    = "out"
    action  = "DROP"
    dest    = var.lab_firewall.mgmt_cidr
    comment = "no pivot to management LAN / TrueNAS"
    log     = "info"
  }

  rule {
    type    = "out"
    action  = "DROP"
    dest    = var.lab_firewall.ops_cidr
    comment = "no pivot to ops net (telemetry targets collector detonation-side IP)"
    log     = "info"
  }
}

# Cluster-wide firewall framework. Policies pinned to ACCEPT so merely enabling it
# cannot drop management/corosync traffic; enforcement is per-VM via the security
# group above. OFF by default — see the module comment and the runbook.
resource "proxmox_virtual_environment_cluster_firewall" "this" {
  count = var.lab_firewall.enable_cluster_firewall ? 1 : 0

  enabled        = true
  ebtables       = true
  input_policy   = "ACCEPT"
  output_policy  = "ACCEPT"
  forward_policy = "ACCEPT"

  log_ratelimit {
    enabled = true
    burst   = 10
    rate    = "5/second"
  }
}
