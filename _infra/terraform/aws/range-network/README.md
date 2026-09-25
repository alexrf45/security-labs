# `range-network` — shared, long-lived range plumbing

The one **long-lived** Terraform root for the cloud range (ADR-0011 §5). It holds
only the shared network fabric plus the persistent SIEM volume, so its standing cost
is storage-only (**≈ $2.70/mo**: 30 GB gp3 = $2.40 + Cost Explorer API calls). Every
per-session root — [`ops-tier`](../ops-tier/) and each
[`scenarios/<name>`](../scenarios/) — discovers this fabric by **tag** and never reads
this root's state.

> **State:** local backend, holds plaintext secrets, gitignored. Never commit
> `*.tfstate` (`secrets.md`). **Claude runs offline checks only**
> (`validate`/`fmt`/`tflint`/`infracost`); the user runs `apply`/`destroy` under
> `op run --` (`terraform.md`).

## What it creates

| Resource | Purpose | Cost |
| --- | --- | --- |
| VPC `10.40.0.0/16`, **DNS disabled** | Closes the unfilterable AmazonProvidedDNS exfil channel (§4b) | $0 |
| DHCP option set (public resolvers) | DNS works only where an internet route exists (ops) | $0 |
| Ops subnet `10.40.10.0/24` + IGW route | The only routed subnet | $0 |
| Detonation subnets `10.40.5N.0/24` (no route, no public IP) | Structural air-gap toward the internet (§3) | $0 |
| Detonation NACL | Load-bearing ops↔det control (§4c) | $0 |
| Security groups: router / attacker / collector / detonation | Stateful isolation, one-way telemetry | $0 |
| AWS Budgets ($30, alarms 50/80/100%) | Mandatory cost alarm (`cost-guardrails.md`) | $0 |
| Persistent SIEM EBS volume (30 GB gp3, `prevent_destroy`) | Defensive index surviving teardown | $2.40/mo |

## Isolation model (read `.claude/rules/range-safety.md` first)

- **Toward the internet, isolation is structural**: detonation route tables have no
  default route and instances get no public IP.
- **Toward the ops subnet, isolation is rule-based** — the VPC `local` route spans the
  whole CIDR (§4c, an honest degradation from the Proxmox gateway-less VLAN). Two
  layers, both treated as load-bearing:
  1. **Security groups** (stateful, primary): victims reachable only from the attacker
     SG; telemetry one-way to the collector SG; the collector never initiates into a
     detonation net.
  2. **Detonation NACL** (stateless, subnet-level): egress to ops limited to telemetry
     + ephemeral return; **det↔det permitted in full** so a cross-subnet forest trust
     works (§7).
- **VPC DNS is disabled** — in-segment scenarios run their own resolver (an AD DC is
  its domain's DNS server).
- **Opt-in agent package mirror** (`enable_agent_package_mirror`, default off) — the one
  way to add a det→ops path: a single controlled, logged port so air-gapped victims can
  pull Wazuh/Sysmon installers from the collector's mirror (`range-safety.md` §6). Off by
  default so the baseline isolation is unchanged; enable it (here and in `ops-tier`) only
  when installing agents without a baked AMI.

## Inputs (see `variables.tf`)

`project`, `aws_region`, `availability_zone`, `vpc_cidr`, `ops_subnet_cidr`,
`detonation_subnets` (map name→CIDR), `public_dns_resolvers`, `telemetry_ports`,
`siem_volume_size`, `budget_limit`, `budget_alert_emails`.

## Outputs

`vpc_id`, `ops_subnet_id`, `detonation_subnet_ids`, `security_group_ids`,
`siem_volume_id`, `internet_gateway_id` — for humans/docs only; downstream roots use
tag lookups.

## Example

```console
$ cp terraform.tfvars.example terraform.tfvars   # add budget_alert_emails; SOPS-encrypt
$ op run -- terraform init
$ op run -- terraform apply          # user runs apply; Claude never does
```

This root is applied **once** and left up; sessions are the per-session roots.
