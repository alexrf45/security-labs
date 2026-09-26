# Reference — AWS range (variables, tags, ports, rules)

Information-oriented reference for the three Terraform roots under
`_infra/terraform/aws/`. Values are taken from the code as built (ADR-0011). For the
*ordered deploy*, see the [deployment runbook](../runbooks/aws-range-deployment.md); for
*why*, see [ADR-0011](../decisions/0011-aws-provider-and-range-topology.md).

Provider pinned `hashicorp/aws = 6.66.0` across all roots; `terraform >= 1.9.0`.

---

## Network

| Subnet | Name/tag | CIDR | Default route | Public IP | Purpose |
| --- | --- | --- | --- | --- | --- |
| VPC | — | `10.40.0.0/16` | — | — | DNS **disabled** (invariant #10); DHCP hands out public resolvers |
| ops | `ops` | `10.40.10.0/24` | → Internet Gateway | router EIP only | router, attacker, collector |
| victim00 | `victim00` | `10.40.50.0/24` | **none** | **none** | forest A victims |
| victim01 | `victim01` | `10.40.51.0/24` | **none** | **none** | forest B victims |
| victimNN | `victimNN` | `10.40.5N.0/24` | none | none | future scenarios (add to `victim_subnets`) |

Mnemonic: **40 = ops, 5N = victim.** Single AZ `us-east-1a` (no cross-AZ transfer).

**Static private IPs (multi-forest scenario)** — derived from the subnet CIDR via
`cidrhost(cidr, N)`; `.10` = DC, `.20` = workstation:

| Host | Subnet | IP |
| --- | --- | --- |
| DC-A | victim00 | `10.40.50.10` |
| WS-A | victim00 | `10.40.50.20` |
| DC-B | victim01 | `10.40.51.10` |
| WS-B | victim01 | `10.40.51.20` |

---

## Tags

**Applied to every resource via `default_tags`:**

| Key | Value | Use |
| --- | --- | --- |
| `Project` | `security-labs` (var `project`) | cross-root discovery filter; teardown/`/lab-status` filter |
| `ManagedBy` | `terraform` | provenance |
| `ADR` | `0011` | provenance |
| `Component` | `range-network` / `ops-tier` / `scenario-multi-forest` | which root owns it |

**Discovery tags** — how downstream roots find shared plumbing (never
`terraform_remote_state`):

| Tag key | Value(s) | On resource | Read by |
| --- | --- | --- | --- |
| `Discovery` | `range-vpc` | VPC | ops-tier, scenarios (`aws_vpc`) |
| `Discovery` | `range-subnet` | ops + victim subnets | ops-tier, scenarios (`aws_subnet`) |
| `Discovery` | `range-sg` | all four SGs | ops-tier, scenarios (`aws_security_group`) |
| `Discovery` | `range-siem-volume` | persistent EBS volume | ops-tier (`aws_ebs_volume`) |
| `SubnetRole` | `ops` / `victim` | subnets | (classification) |
| `SubnetName` | `ops` / `victim00` / `victim01` / … | subnets | ops-tier, scenarios (subnet lookup) |
| `SGRole` | `router` / `attacker` / `collector` / `victim` | SGs | ops-tier, scenarios (SG lookup) |
| `Role` | `router` / `attacker` / `collector` | ops instances | scenarios discover the collector (`Role=collector`) |
| `Tier` | `ops` | ops instances | (classification) |
| `Forest` | `forest-a.lab` / `forest-b.lab` | scenario victims | (classification) |

> Discovery filters also match on `tag:Project`, so keep `project` identical across all
> three roots or the lookups return nothing.

---

## Ports & protocols

What each layer permits. Structural rule: victim subnets have **no internet route**;
the table's "internet" rows apply only to the ops subnet.

| Port(s) | Proto | Direction | Enforced by | Purpose |
| --- | --- | --- | --- | --- |
| 41641 | UDP | internet → router | router SG | Tailscale WireGuard (direct path; DERP works without it) |
| 22 | TCP | ops-subnet → attacker/collector | attacker SG (all from ops CIDR); collector SG (explicit rule) | operator SSH via the router over Tailscale; needs `ssh_public_key` |
| 3389 | TCP | ops-subnet → attacker | attacker SG | i3 desktop over xrdp |
| 443 | TCP | ops-subnet → collector | collector SG | Wazuh dashboard |
| 1514, 1515 | TCP | victim → collector | victim SG egress + collector SG ingress (by SG ref) + NACL egress 200-201 | Wazuh telemetry / enrollment (one-way) |
| 8080 | TCP | victim → collector | **opt-in** mirror SG rules + NACL egress 250 | agent-installer mirror (`enable_agent_package_mirror`) |
| 1024–65535 | TCP/UDP | victim → ops | NACL egress 300/310 | ephemeral return traffic to the attacker |
| any | any | attacker → victim | victim SG (from attacker SG) + NACL ingress 200 | attacker probes victims on any port |
| any | any | victim ↔ victim | victim SG (self-ref) + NACL 100+i | **AD trust & lateral movement** (see below) |
| 80, 443 | TCP | collector → internet | collector SG egress | package updates only (collector never initiates into victim) |
| any | any | router/attacker → internet | router/attacker SG egress | egress via the ops route / tool pulls |
| 1688 | TCP | instance → `169.254.169.250/.251` | link-local (no SG/route) | Windows KMS activation (works in a no-egress subnet) |
| — | — | instance → `169.254.169.254` | link-local, IMDSv2 hop-limit 1 | instance metadata / user-data |

**AD trust ports** ride the victim↔victim allow-all (they are *not* separately enumerated):
Kerberos 88, LDAP 389 / 636, SMB 445, RPC endpoint mapper 135 + dynamic range, DNS 53
(DC-to-DC conditional forwarders). Inter-forest isolation, if a scenario wants it, is a
scenario-level SG layered on top of this baseline.

---

## Security group matrix

Stateful; responses to allowed inbound are auto-permitted. `self` = the SG references
itself; `→SG` = references another SG by ID.

| SG (`SGRole`) | Ingress | Egress |
| --- | --- | --- |
| **router** | UDP 41641 from `0.0.0.0/0`; all from ops CIDR | all to `0.0.0.0/0` |
| **attacker** | all from ops CIDR | all to `0.0.0.0/0` |
| **collector** | TCP 1514/1515 from `victim`; TCP 443 + TCP 22 from ops CIDR; *(opt)* TCP 8080 from `victim` | TCP 80/443 to `0.0.0.0/0` |
| **victim** | all from `attacker`; all from `victim` (self) | TCP 1514/1515 to `collector`; all to `victim` (self); *(opt)* TCP 8080 to `collector` |
| *(VPC default)* | **none** | **none** | emptied deliberately (FSBP/CIS EC2.2); nothing should ever attach to it |

The collector has **no egress rule toward victim** — enforcing one-way telemetry
(range-safety.md §7).

## Victim NACL (stateless, subnet-level)

Load-bearing (ADR-0011 §4c). `i` indexes each victim CIDR; `j` each telemetry port.

| # | Dir | Action | Proto | Source/Dest | Ports |
| --- | --- | --- | --- | --- | --- |
| 100+i | ingress | allow | all | each victim CIDR | all |
| 200 | ingress | allow | all | ops CIDR | all |
| 100+i | egress | allow | all | each victim CIDR | all |
| 200+j | egress | allow | tcp | ops CIDR | telemetry port |
| 250 | egress | allow | tcp | ops CIDR | mirror port *(opt-in)* |
| 300 | egress | allow | tcp | ops CIDR | 1024–65535 |
| 310 | egress | allow | udp | ops CIDR | 1024–65535 |
| 320 | egress | allow | icmp | ops CIDR | type -1 / code -1 |
| * | both | **deny** | — | everything else | — (implicit) |

Ingress from ops is broad (the attacker hits arbitrary victim ports); the meaningful
control is **egress to ops** — telemetry, ephemeral return and ICMP only, so a victim
can't open a new connection to an arbitrary ops service.

Rule 320 exists because the NACL is stateless: without it `ping` and `nmap -PE` from the
attacker fail even though the security groups allow them. It does not widen
victim-initiated reach, because the victim SG has no ICMP egress rule toward the attacker.

Ephemeral egress starts at **1024**, so a probe sourced from a privileged port
(`nmap --source-port 53`) gets no reply. Deliberate: widening it would expose low ops ports.

---

## Variables

Sensitive vars have **no default** (or empty) and are injected at apply from 1Password.

### `range-network`

| Variable | Type | Default | Notes |
| --- | --- | --- | --- |
| `project` | string | `security-labs` | discovery/teardown filter; keep identical across roots |
| `aws_region` | string | `us-east-1` | |
| `availability_zone` | string | `us-east-1a` | SIEM volume + all instances share it |
| `vpc_cidr` | string | `10.40.0.0/16` | |
| `ops_subnet_cidr` | string | `10.40.10.0/24` | only routed subnet |
| `victim_subnets` | map(string) | `{victim00=…50.0/24, victim01=…51.0/24}` | add more for new scenarios |
| `public_dns_resolvers` | list(string) | `["1.1.1.1","1.0.0.1"]` | DHCP resolvers (VPC DNS is off) |
| `telemetry_ports` | list(number) | `[1514, 1515]` | Wazuh events / enrollment |
| `siem_volume_size` | number | `30` | GiB, gp3, `prevent_destroy` |
| `budget_limit` | number | `30` | USD monthly ceiling |
| `budget_alert_emails` | list(string) | **none — required** | validated non-empty and email-shaped; an alarm-less budget is not allowed to exist |
| `enable_agent_package_mirror` | bool | `false` | opens the one victim→collector mirror port |
| `agent_package_mirror_port` | number | `8080` | |

### `ops-tier`

| Variable | Type | Default | Notes |
| --- | --- | --- | --- |
| `project` | string | `security-labs` | must match range-network |
| `aws_region` | string | `us-east-1` | |
| `tailscale_auth_key` | string | **(required)** | **sensitive**; reusable+ephemeral+pre-authorized |
| `tailnet_hostname` | string | `range-router` | |
| `router_instance_type` | string | `t4g.micro` | |
| `attacker_instance_type` | string | `t3.medium` | |
| `collector_instance_type` | string | `t3.medium` | **x86_64** — Wazuh's all-in-one installer is only well-tested there, and $0.008/hr is not worth debugging arm64 packaging. Same 2 vCPU / 4 GiB as `t4g.medium`, so this is not extra capacity: 2 GB still OOMs the stack, don't shrink |
| `ubuntu_ami_owner` | string | `099720109477` | Canonical; shared by both Ubuntu lookups |
| `ubuntu_arm_ami_name` | string | `ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-arm64-server-*` | router only (arm64) |
| `ubuntu_x86_ami_name` | string | `ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*` | collector only (x86_64) |
| `kali_ami_owner` | string | `aws-marketplace` | owner alias; Marketplace AMIs are owned by that account, not by a Kali publisher ID. Verified resolving 2026-09-26; launching also needs the Marketplace subscription |
| `kali_ami_name` | string | `kali-last-snapshot-amd64-*` | |
| `router_root_gb` / `attacker_root_gb` / `collector_root_gb` | number | `8` / `40` / `20` | gp3 encrypted |
| `siem_mount_point` | string | `/data` | collector mount for the SIEM volume |
| `wazuh_version` | string | `4.14` | release branch; installer takes that branch's latest patch |
| `wazuh_agent_pkg` | string | `4.14.6-1` | MSI/deb version the collector mirrors; **validated** to be on the same branch as `wazuh_version` |
| `wazuh_indexer_heap` | string | `1g` | written to `/etc/wazuh-indexer/jvm.options` as matching `-Xms`/`-Xmx` |
| `enable_agent_package_mirror` | bool | `false` | match range-network |
| `agent_package_mirror_port` | number | `8080` | match range-network |
| `serve_sysmon` | bool | `true` | mirror Sysmon + config |
| `scrt_repo_url` | string | `https://github.com/alexrf45/SCRT.git` | attacker clones + builds this |
| `attacker_install_bugbounty` | bool | `false` | also run SCRT `2-tools.sh` |
| `attacker_enable_gui` | bool | `true` | i3 desktop over xrdp |
| `attacker_rdp_password` | string | `""` | **sensitive**; kali unix password for xrdp login |
| `ssh_public_key` | string | `""` | Public half only, so **not** sensitive. Inject from `op://Security/security_labs/public key`; validated as a single-line OpenSSH public key |
| `ssh_key_name` | string | `""` | Reuse an existing EC2 key pair instead of registering one from `ssh_public_key` |

### `scenarios/multi-forest`

| Variable | Type | Default | Notes |
| --- | --- | --- | --- |
| `project` | string | `security-labs` | must match range-network |
| `aws_region` | string | `us-east-1` | |
| `forest_a_domain` / `forest_b_domain` | string | `forest-a.lab` / `forest-b.lab` | forest roots |
| `forest_a_netbios` / `forest_b_netbios` | string | `FORESTA` / `FORESTB` | |
| `forest_a_subnet_name` / `forest_b_subnet_name` | string | `victim00` / `victim01` | which victim subnets |
| `domain_admin_password` | string | **(required)** | **sensitive**; both forests |
| `safe_mode_password` | string | **(required)** | **sensitive**; DSRM |
| `dc_instance_type` | string | `t3.medium` | DCs never spot |
| `member_instance_type` | string | `t3.medium` | |
| `member_use_spot` | bool | `false` | spot for WS-A/WS-B only |
| `member_spot_max_price` | string | `0.03` | |
| `windows_ami_owner` | string | `amazon` | license-included |
| `windows_ami_name` | string | `Windows_Server-2022-English-Full-Base-*` | |
| `windows_root_gb` | number | `50` | gp3 encrypted |
| `enable_wazuh_agents` | bool | `true` | needs the mirror (or a baked AMI) |
| `wazuh_agent_group` | string | `windows` | |
| `wazuh_mirror_port` | number | `8080` | match ops-tier |
| `install_sysmon` | bool | `true` | Sysmon + forward its channel |

---

## Outputs

| Root | Outputs |
| --- | --- |
| `range-network` | `vpc_id`, `ops_subnet_id`, `victim_subnet_ids`, `security_group_ids`, `siem_volume_id`, `internet_gateway_id` |
| `ops-tier` | `router_public_ip`, `router_private_ip`, `attacker_private_ip`, `collector_private_ip` |
| `scenarios/multi-forest` | `forest_a`, `forest_b`, `members_on_spot` |

Outputs are for humans/docs; roots discover each other by tag, not from state.

---

## Secrets → 1Password

Injected at apply as `TF_VAR_<name>` via `op run --`; never written to disk (they do
land in local state, which is treated sensitive at rest — `secrets.md`).

| Variable | Root | Suggested `op://` reference |
| --- | --- | --- |
| `tailscale_auth_key` | ops-tier | `op://Security/tailscale-range-router/authkey` |
| `attacker_rdp_password` | ops-tier | `op://Security/scrt-attacker/password` |
| `domain_admin_password` | multi-forest | `op://Security/range-ad/admin-password` |
| `safe_mode_password` | multi-forest | `op://Security/range-ad/dsrm-password` |

(`budget_alert_emails` is config, not a secret, but isn't committed either.)

---

## Cost quick-reference

Rates `us-east-1`; **infracost monthly totals assume 730 h — divide for the per-hour
rate**, and Windows needs `--usage-file infracost-usage.yml`.

| Instance | Role | Linux $/hr | Windows $/hr |
| --- | --- | --- | --- |
| t4g.micro | router | 0.0084 | — |
| t4g.small | — | 0.0168 | — |
| t4g.medium | (arm64 collector, not used) | 0.0336 | — |
| t3.medium | attacker / collector / DC / WS | 0.0416 | **0.0600** |
| t3.large | DC + ADCS | 0.0832 | 0.1108 |

| Item | Cost |
| --- | --- |
| Standing (range-network) | ≈ $2.70/mo (30 GB gp3 + Cost Explorer) |
| Ops tier | ≈ $0.104/hr (~$0.83 / 8h) |
| Multi-forest session (all-in) | ≈ $2.92 / 8h on-demand · ≈ $2.32 spot members |
| Public IPv4 (router EIP) | $0.005/hr |
| gp3 storage | $0.08/GB-mo (never gp2 = $0.10) |
| Budget alarms | $15 / $24 / $30 (50/80/100%) |
