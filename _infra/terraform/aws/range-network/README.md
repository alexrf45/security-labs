# `range-network` — shared, long-lived range plumbing

## What it creates

| Resource | Cost |
| --- | --- |
| VPC `10.40.0.0/16` with **DNS disabled** + DHCP option set (public resolvers) | $0 |
| Edge subnet `10.40.1.0/28` + IGW route (router only; the one IGW route) | $0 |
| Ops subnet `10.40.10.0/24` — route table with no inline routes; `ops-tier` adds the default route via the router | $0 |
| Victim subnets `10.40.5N.0/24` — no route, no public IP | $0 |
| Victim NACL (stateless) | $0 |
| Security groups: router / attacker / collector / victim | $0 |
| VPC default security group, emptied (FSBP/CIS EC2.2) | $0 |
| AWS Budgets, alarms at 50/80/100% | $0 |
| Persistent SIEM EBS volume, 30 GB gp3, `prevent_destroy` | $2.40/mo |

## Usage

```console
$ op run -- terraform init
$ export TF_VAR_budget_alert_emails='["you@example.com"]'
$ op run -- terraform plan
$ op run -- terraform apply
```

## Inputs and outputs

Full tables: [range reference](../../../../_docs/reference/aws-range-reference.md#range-network).

| Input | Notes |
| --- | --- |
| `budget_alert_emails` | **Required, no default.** Validated non-empty and email-shaped. `validate` does not run variable validation, so the guard fires at `plan`. |
| `victim_subnets` | Map name→CIDR. Keys become the `SubnetName` tag scenarios discover by, so renaming one breaks any scenario pinned to it. |
| `enable_agent_package_mirror` | Opens the one victim→collector port. Off by default; must also be set in `ops-tier`. |

Outputs are for humans and docs only — downstream roots rediscover everything by tag.
