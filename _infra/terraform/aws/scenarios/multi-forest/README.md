# `scenarios/multi-forest` — two AD forests joined by a two-way trust

Two separate **forest roots** in two victim subnets, joined by a two-way forest trust.
Per-session; destroyed at teardown.

Design rationale: [ADR-0011 §7](../../../../../_docs/decisions/0011-aws-provider-and-range-topology.md).


## Topology

| Forest | Domain | Subnet | Hosts (`.10` / `.20`) |
| --- | --- | --- | --- |
| A (root) | `forest-a.lab` | victim00 `10.40.50.0/24` | DC-A (t3.medium Win), WS-A |
| B (root) | `forest-b.lab` | victim01 `10.40.51.0/24` | DC-B (t3.medium Win), WS-B |

## Cost

**Always pass the usage file** — `infracost` prices Windows AMIs as Linux otherwise:

```console
$ infracost breakdown --path . --usage-file infracost-usage.yml
```

Each t3.medium Windows host is $0.0600/hr.

| | On-demand | Members on spot |
| --- | --- | --- |
| this scenario (4 Win + EBS) | ~0.268/hr | ~0.194/hr |
| **+ ops tier + IPv4** | **0.365/hr → $2.92 / 8h** | **0.290/hr → $2.32 / 8h** |

~9 multi-forest sessions/month under the $30 ceiling. **DCs never run on spot** (a reclaim
tears down the domain and trust); `member_use_spot = true` puts only WS-A/WS-B on spot.

## Prerequisites

- `range-network` applied, with **victim00 and victim01** present.
- `ops-tier` applied — the attacker RDPs to the DCs, and the collector is discovered by tag.

## Usage

```console
$ cat .envrc          # gitignored; 1Password references only, never values
export TF_VAR_domain_admin_password="op://Security/range-ad/admin-password"
export TF_VAR_safe_mode_password="op://Security/range-ad/dsrm-password"
$ direnv allow
$ op plugin run -- terraform init
$ op run -- op plugin run -- terraform apply
```

Promotion and trust creation span multiple reboots — allow **10–20 minutes**. Verify with
`Get-ADTrust -Filter *` on DC-B.


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
