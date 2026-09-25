# `scenarios/multi-forest` — two AD forests joined by a two-way trust

The range's heaviest realistic session and its topology-validation scenario
(ADR-0011 §7): two separate **forest roots** in two detonation subnets, joined by a
**two-way forest trust**. It exercises the cross-forest attack surface — SID-history /
`ExtraSids`, cross-forest Kerberoasting, ADCS ESC over a trust, foreign-group and
inter-realm-TGT paths. If the range hosts this, it hosts every lesser single-domain
scenario.

> **State:** local, sensitive, gitignored, separate blast radius from `range-network`.
> **Claude runs offline checks only**; the user runs `apply`/`destroy` under `op run --`.

## Topology

| Forest | Domain | Subnet | Hosts (private IPs .10 / .20) |
| --- | --- | --- | --- |
| A (root) | `forest-a.lab` | det00 `10.40.50.0/24` | DC-A (t3.medium Win), WS-A |
| B (root) | `forest-b.lab` | det01 `10.40.51.0/24` | DC-B (t3.medium Win), WS-B |

- **Inter-forest reachability** rides the VPC `local` route (both subnets stay
  internet-air-gapped); the detonation SG (self-referencing) and NACL (det↔det) permit
  it. **No `range-network` change is required** — the scenario just consumes two
  detonation subnets discovered by tag.
- **Cross-forest DNS** uses DC **conditional forwarders** (each DC forwards the peer
  domain to the peer DC's IP), so it works with VPC DNS disabled (§4b).
- Every host: **IMDSv2 hop-limit-1, no instance profile**, no public IP, gp3 encrypted
  root (§5). Windows activates via link-local KMS with no internet route.

## Cost (verify with the Windows usage override)

infracost prices Windows AMIs as Linux unless told otherwise, so **always pass the
usage file** (this is the ADR §2 blind-spot fix):

```console
$ infracost breakdown --path . --usage-file infracost-usage.yml
```

With the override, each t3.medium Windows host is $0.0600/hr (confirmed). Ephemeral
per-session cost:

| | On-demand | Members on spot |
| --- | --- | --- |
| this scenario (4 Win + EBS) | ~0.268/hr | ~0.194/hr |
| **+ ops tier + IPv4** (collector t4g.medium) | **0.357/hr → $2.86 / 8h** | **0.282/hr → $2.26 / 8h** |

At ~$2.86/session the $30 ceiling allows ~10 multi-forest sessions/month (spot members:
~12). **DCs never run on spot** (a reclaim tears down the domain and the trust); set
`member_use_spot = true` to put only WS-A/WS-B on spot. (The +$0.14 over the ADR's $2.72
is the collector right-size to t4g.medium so Wazuh fits — see `ops-tier`.)

## The trust bootstrap (the one hard part)

Forest promotion is multi-reboot and order-dependent, and SSM is unavailable in a
no-egress subnet (§6), so there is no post-boot command channel. The design:

1. **Each DC self-promotes** from `user_data` (`Install-ADDSForest`) with
   `<persist>true</persist>` so the script survives the promotion reboots. Idempotent
   guards make every step run once.
2. **The trust is created from DC-B** by a **self-deleting scheduled task** that waits
   for DC-A's LDAP, creates a bidirectional forest trust with the peer's admin
   credentials (this creates both sides), then unregisters itself. This keeps the
   scenario a single apply with no interactive step.

**This automation needs validation against real boot behaviour** (ADR-0011 §7 says so
explicitly). If the task proves flaky, disable it and run this runbook snippet once,
on DC-B, after both DCs are up (RDP in over Tailscale via the ops tier):

```powershell
$peer = "forest-a.lab"
$localForest  = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
$ctx = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext(
    "Forest", $peer, "$peer\Administrator", "<domain_admin_password>")
$remoteForest = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ctx)
$localForest.CreateTrustRelationship($remoteForest, "Bidirectional")
```

## Telemetry (Wazuh agents + Sysmon)

With `enable_wazuh_agents = true` (default), each victim's `user_data` installs the
Wazuh agent and Sysmon (SwiftOnSecurity config, forwarding the Sysmon channel) and
enrolls to the collector, discovered **by tag** (`Role=collector`). Requires `ops-tier`
applied first. Because victims are air-gapped, the installers come from the collector's
mirror — so this needs `enable_agent_package_mirror = true` on `ops-tier` *and*
`range-network` (or a baked AMI). If the mirror is off, the download fails softly and
the forests still stand up; telemetry starts once the package path exists. Set
`enable_wazuh_agents = false` to skip telemetry entirely.

Vars: `enable_wazuh_agents`, `wazuh_agent_group`, `wazuh_mirror_port`, `install_sysmon`.

## Secrets

`domain_admin_password` and `safe_mode_password` have no defaults. Inject at apply time
from 1Password (`op run -- env TF_VAR_domain_admin_password="op://<vault>/<item>/password" ...`);
they land in local state (treated sensitive, `secrets.md`). They also appear in
instance `user_data` — retrievable only from the instance itself via IMDSv2, which is
acceptable for a throwaway detonation host.

## Prerequisites

- `range-network` applied, with **det00 and det01** present (the default two detonation
  subnets).
- `ops-tier` applied (the attacker RDPs to the DCs over Tailscale; the collector
  receives telemetry).

## Inputs / Outputs

See `variables.tf` (`forest_*_domain`, `forest_*_netbios`, `*_subnet_name`,
`member_use_spot`, `member_spot_max_price`, sizing, AMI filters) and `outputs.tf`
(`forest_a`, `forest_b`, `members_on_spot`).
