# EVPN SDN — ADR-0008 Option B. Flat-L2 BGP-EVPN mesh (replaces the OpenFabric
# routed underlay, which can't mesh a shared LAN — see below).
#
# Stretched-L2 VXLAN overlay across all PVE hosts so the multi-host HA Talos
# cluster keeps its control-plane VIP + Cilium L2 LoadBalancer design. Every PVE
# host peers BGP-EVPN directly over its management IP (var.sdn.evpn.peers) and
# uses that same IP as its VXLAN VTEP. No IGP / loopback underlay.
#
# Why not the OpenFabric routed underlay: FRR `fabricd` (OpenFabric) is
# point-to-point ONLY — every circuit is `Type: p2p`, capped at one neighbor, with
# no broadcast/DIS election. On the six-node shared `vmbr0` switch it can't form a
# full mesh (each node holds one flapping adjacency, loopbacks don't propagate, the
# EVPN BGP sessions never come up). The management LAN already gives every node
# direct L2/L3 reachability to every other (corosync rides it), so a direct BGP
# peer mesh is the correct, simplest control plane here.
#
# Apply ordering uses the bpg leading-finalizer pattern:
#   1. proxmox_sdn_applier.finalizer  — commits/flushes any PRE-EXISTING pending
#      SDN state before we stage anything (a partial prior apply leaves pending
#      controller/zone objects that otherwise collide on create -> HTTP 500).
#   2. all SDN objects stage as "pending" (rooted after the finalizer).
#   3. proxmox_sdn_applier.this       — terminal commit of the staged objects.

# Leading applier: empty + no depends_on so it runs first and clears pending.
resource "proxmox_sdn_applier" "finalizer" {}

# ── Control plane: EVPN (BGP) peered directly over the management LAN ────────
# peers = every PVE host's mgmt IP. No fabric/loopback underlay.
resource "proxmox_sdn_controller_evpn" "this" {
  id    = var.sdn.evpn.controller_id
  asn   = var.sdn.evpn.asn
  peers = var.sdn.evpn.peers

  depends_on = [proxmox_sdn_applier.finalizer]
}

# ── Overlay: EVPN zone (stretched L2 + anycast L3 + exit-node SNAT) ──────────
# vrf_vxlan is the routing VRF VNI; it MUST differ from the vnet tag below.
# exit_nodes carry L3 egress out of the overlay; list >1 to avoid a routing SPOF.
resource "proxmox_sdn_zone_evpn" "this" {
  id         = var.sdn.zone_id
  nodes      = coalesce(var.sdn.nodes, var.pve.hosts)
  controller = proxmox_sdn_controller_evpn.this.id
  vrf_vxlan  = var.sdn.evpn.vrf_vxlan
  mtu        = var.sdn.mtu

  exit_nodes               = var.sdn.evpn.exit_nodes
  primary_exit_node        = var.sdn.evpn.primary_exit_node
  exit_nodes_local_routing = true
  advertise_subnets        = var.sdn.evpn.advertise_subnets
  ipam                     = "pve"
}

# The VNet — its id becomes the bridge name VMs attach to (network_device.bridge).
# tag is the per-vnet VXLAN VNI and must differ from the zone vrf_vxlan.
resource "proxmox_sdn_vnet" "this" {
  id   = var.sdn.vnet_id
  zone = proxmox_sdn_zone_evpn.this.id
  tag  = var.sdn.evpn.vnet_tag
}

# Anycast gateway (present on every node) + SNAT egress via the exit node(s).
# Static addressing only (Talos/cloud-init sets node IPs) — no DHCP range.
resource "proxmox_sdn_subnet" "this" {
  vnet    = proxmox_sdn_vnet.this.id
  cidr    = var.sdn.subnet_cidr
  gateway = var.sdn.gateway
  snat    = var.sdn.snat
}

# Terminal applier: commits all staged SDN objects in one shot. depends_on the
# whole stack so the commit runs last; replace_triggered_by re-commits whenever
# any SDN object changes on later applies.
resource "proxmox_sdn_applier" "this" {
  depends_on = [
    proxmox_sdn_applier.finalizer,
    proxmox_sdn_controller_evpn.this,
    proxmox_sdn_zone_evpn.this,
    proxmox_sdn_vnet.this,
    proxmox_sdn_subnet.this,
  ]

  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_controller_evpn.this,
      proxmox_sdn_zone_evpn.this,
      proxmox_sdn_vnet.this,
      proxmox_sdn_subnet.this,
    ]
  }
}
