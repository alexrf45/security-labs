# `scenarios/multi-forest` — two AD forests joined by a two-way trust

Two separate **forest roots** in two victim subnets, joined by a two-way forest trust.
Per-session; destroyed at teardown.

Design rationale: [ADR-0011 §7](../../../../../_docs/decisions/0011-aws-provider-and-range-topology.md).

> **State:** local, sensitive, gitignored, separate blast radius from `range-network`.
> **Claude runs offline checks only**; the user runs `apply`/`destroy` under `op run --`.

## Topology

| Forest | Domain | Subnet | Hosts (`.10` / `.20`) |
| --- | --- | --- | --- |
| A (root) | `forest-a.lab` | victim00 `10.40.50.0/24` | DC-A (t3.medium Win), WS-A |
| B (root) | `forest-b.lab` | victim01 `10.40.51.0/24` | DC-B (t3.medium Win), WS-B |

Inter-forest traffic rides the VPC `local` route; both subnets stay internet-air-gapped
and **no `range-network` change is needed**. Cross-forest DNS uses DC conditional
forwarders, since VPC DNS is disabled. Every host: IMDSv2 hop-limit-1, no instance
profile, no public IP, gp3 encrypted root.

## Cost

**Always pass the usage file** — `infracost` prices Windows AMIs as Linux otherwise:

```console
$ infracost breakdown --path . --usage-file infracost-usage.yml
```

Each t3.medium Windows host is $0.0600/hr.

| | On-demand | Members on spot |
| --- | --- | --- |
| this scenario (4 Win + EBS) | ~0.268/hr | ~0.194/hr |
| **+ ops tier + IPv4** | **0.357/hr → $2.86 / 8h** | **0.282/hr → $2.26 / 8h** |

~9 multi-forest sessions/month under the $30 ceiling. **DCs never run on spot** (a reclaim
tears down the domain and trust); `member_use_spot = true` puts only WS-A/WS-B on spot.

## Prerequisites

- `range-network` applied, with **victim00 and victim01** present.
- `ops-tier` applied — the attacker RDPs to the DCs, and the collector is discovered by tag.

## Usage

```console
$ op run -- terraform init
$ op run -- env \
    TF_VAR_domain_admin_password="op://Security/range-ad/admin-password" \
    TF_VAR_safe_mode_password="op://Security/range-ad/dsrm-password" \
    terraform apply
```

Promotion and trust creation span multiple reboots — allow **10–20 minutes**. Verify with
`Get-ADTrust -Filter *` on DC-B.

## Trust bootstrap

Each DC self-promotes from `user_data` (`Install-ADDSForest`, `<persist>true</persist>` to
survive the promotion reboots, every step idempotent). The trust is created from **DC-B**
by a self-deleting scheduled task that waits for DC-A's LDAP, creates a bidirectional
forest trust with the peer's admin credentials, then unregisters itself. SSM is unavailable
in a no-egress subnet, so there is no other post-boot command channel.

**Not yet validated against real boot behaviour.** If the task proves flaky, disable it and
run this once on DC-B after both DCs are up:

```powershell
$peer = "forest-a.lab"
$localForest  = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
$ctx = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext(
    "Forest", $peer, "$peer\Administrator", "<domain_admin_password>")
$remoteForest = [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ctx)
$localForest.CreateTrustRelationship($remoteForest, "Bidirectional")
```

## Telemetry

With `enable_wazuh_agents = true` (default) each victim installs the Wazuh agent and Sysmon
and enrolls to the collector, discovered by tag (`Role=collector`). Because victims are
air-gapped the installers come from the collector's mirror, so this needs
`enable_agent_package_mirror = true` on both `ops-tier` and `range-network`. Without it the
download fails softly and the forests still stand up. Set `enable_wazuh_agents = false` to
skip telemetry entirely.

## Inputs and outputs

Full tables: [range reference](../../../../../_docs/reference/aws-range-reference.md#scenariosmulti-forest).
The inputs that carry a decision:

| Input | Notes |
| --- | --- |
| `member_use_spot` | Members on spot; never applies to DCs |
| `forest_a_subnet_name` / `forest_b_subnet_name` | Matched against the `SubnetName` tag; must exist in `range-network` |
| `enable_wazuh_agents` | Off stands the forests up without telemetry |

**Secrets:** `domain_admin_password` and `safe_mode_password` have no defaults. They land
in local state and in instance `user_data` — acceptable for a throwaway victim, but rotate
at teardown.

Outputs: `forest_a`, `forest_b`, `members_on_spot`.
