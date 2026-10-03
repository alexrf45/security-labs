# Cloud Range Safety — Isolation Invariants

The cloud security range runs malware samples, payloads, and vulnerable hosts. These
invariants are the cloud-native successors to the old Proxmox air-gap (see the
archived ADR-0009). They are **non-negotiable**; violating one can let a
compromised victim reach the internet unfiltered, pivot to your accounts, or leak
ops credentials. Check them on every change to range networking, the scenario
module, or a scenario root.

The structural idea carries over unchanged from the hypervisor lab: **a victim has
no path off its segment.** On-prem that meant a gateway-less VLAN. In cloud it means
a subnet with **no route to an internet/NAT gateway** and **no public IP**.

1. **Victim subnets have no egress route.** A victim subnet's route table
   has **no** default route to an Internet Gateway, NAT Gateway/Instance, or peering.
   The air-gap is *structural* — a victim has no next-hop off its segment. Never add
   a route "to make something reachable"; reach it from a dual-homed ops box instead.
   (This also enforces the cost rule: no NAT gateway, ever — see
   [cost-guardrails.md](cost-guardrails.md).)

2. **No public IP on any victim host.** No EIP, no auto-assigned public IPv4/IPv6,
   no public DNS. Victims are reachable only from the ops tier.

3. **Entry is via Tailscale only — never a public bastion.** The single point of
   human entry is a hardened Tailscale node (subnet router) on the ops tier. No
   SSH/RDP port is ever open to `0.0.0.0/0`. Security-group ingress on victims is
   restricted to the ops tier's range-side address(es).

4. **Only hardened ops boxes bridge into a victim net.** The attacker box (Kali)
   and the collector may sit on the ops tier and reach victim subnets. Nothing
   that can reach your cloud control plane or the internet unfiltered is dual-homed
   without the guards below.

5. **No cloud-control-plane reach from victim hosts.** Victim instances run
   with **IMDSv2 required** (hop limit 1) and **no instance profile / no attached
   role** — the cloud analogue of "the victim can't reach the hypervisor." A
   compromised victim must not be able to mint cloud credentials from metadata.

6. **Egress-deny by default.** Where a scenario genuinely needs outbound (e.g. pull a
   CVE payload), it goes through a *controlled, logged* allow-list on the ops tier,
   never a blanket route. Default posture is deny.

7. **Telemetry is victim → collector, one-way.** Scenario hosts ship logs to the
   collector's **range-side IP**. No ops secrets — 1Password tokens, cloud keys,
   SOPS age key, Tailscale auth keys, C2 keys — ever transit into a victim net.

8. **No lab-admin data on scenario hosts.** SIEM index and kept artifacts live on the
   ops/admin tier. Scenario disks are ephemeral and destroyed with the scenario.

9. **State split:** shared range plumbing (VPC/network, ops tier) and each disposable
   scenario use **separate local state** (see [terraform.md](terraform.md)). A
   wiped/compromised scenario must never corrupt shared infrastructure state. Local
   `.tfstate` holds plaintext secrets — see [secrets.md](secrets.md). Downstream roots
   discover shared plumbing via **tag-filtered data sources, never
   `terraform_remote_state`** — a scenario must never hold a reader for the shared
   state file.

10. **VPC DNS is disabled (AWS).** `enable_dns_support = false` +
    `enable_dns_hostnames = false` on the VPC, plus a DHCP option set handing out public
    resolvers. AmazonProvidedDNS (VPC base+2, `169.254.169.253`) is reachable from a
    no-egress subnet, **cannot be filtered by SG or NACL, and is not logged** — a live,
    invisible DNS-exfil channel if left on. Disabling it makes DNS obey the structural
    rule: it works from the routed ops subnet and is dead in victim subnets.
    In-segment scenarios run their own resolver (an AD DC is its domain's DNS server).
    Never re-enable VPC DNS to "make something resolve."

11. **Ops↔victim is rule-based, not structural (AWS) — the NACL is load-bearing.**
    Within one VPC the implicit `local` route spans the whole CIDR, so a victim host
    can address the ops subnet at L3 regardless of its route table. This is an honest
    degradation from the Proxmox gateway-less VLAN (structural in *both* directions);
    AWS is structural only toward the internet. Two layers, both non-negotiable, both
    treated as primary: **security groups** (stateful — victims reachable only from the
    attacker SG; telemetry one-way to the collector SG; the collector never initiates
    into a victim subnet) and a **victim NACL** (stateless — egress to ops limited to
    telemetry + ephemeral return; victim↔victim permitted so a cross-subnet forest trust
    works). Do not treat either as belt-and-braces.

**Before every scenario apply, re-check this file** — no egress route on victim
subnets, no public IP, IMDSv2 + no instance role, Tailscale-only entry, telemetry
one-way, VPC DNS off, SG+NACL ops↔victim separation intact. The topology that implements
these invariants is **ADR-0011 (Accepted)**, built in `_infra/terraform/aws/`. Treat any
design that can't satisfy 1–11 as not ready to apply.
