# `range-network` — shared, long-lived range plumbing

The one long-lived root: shared network fabric plus the persistent SIEM volume. Standing
cost is storage-only (**≈ $2.70/mo**). Applied **once** and left up; per-session roots
discover it by tag.

Design rationale: [ADR-0011 §4–5](../../../../_docs/decisions/0011-aws-provider-and-range-topology.md).
Isolation invariants: [`range-safety.md`](../../../../.claude/rules/range-safety.md).

> **State:** local, holds plaintext secrets, gitignored. **Claude runs offline checks
> only**; the user runs `apply`/`destroy` under `op run --`.

## What it creates

| Resource | Cost |
| --- | --- |
| VPC `10.40.0.0/16` with **DNS disabled** + DHCP option set (public resolvers) | $0 |
| Ops subnet `10.40.10.0/24` + IGW route (the only routed subnet) | $0 |
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
`variables.tf` is the source of truth. The inputs that carry a decision:

| Input | Notes |
| --- | --- |
| `budget_alert_emails` | **Required, no default.** Validated non-empty and email-shaped. `validate` does not run variable validation, so the guard fires at `plan`. |
| `victim_subnets` | Map name→CIDR. Keys become the `SubnetName` tag scenarios discover by, so renaming one breaks any scenario pinned to it. |
| `enable_agent_package_mirror` | Opens the one victim→collector port. Off by default; must also be set in `ops-tier`. |

Outputs are for humans and docs only — downstream roots rediscover everything by tag.

## Operating notes

- `destroy` refuses while the SIEM volume has `prevent_destroy`. That is the decommission
  gate, not a bug.
- The account baseline (default EBS encryption, snapshot block-public-access, regional
  IMDSv2 defaults) is **not** managed here. It is set out of band per the runbook's
  Phase 0; `account-baseline-check.tf` only warns if EBS encryption drifts off.
- Adding a victim subnet is a `victim_subnets` key. Never add a route to one.
