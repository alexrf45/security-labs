# `_infra/terraform/aws/` — the cloud range

Deploy steps: [runbook](../../../_docs/runbooks/aws-range-deployment.md).

| Root | Holds | Lifecycle | Cost |
| --- | --- | --- | --- |
| [`range-network`](range-network/) | VPC, subnets, NACL, SGs, Budgets, SIEM volume | Long-lived; apply once | ~$2.70/mo |
| [`ops-tier`](ops-tier/) | Router, attacker, collector | Per session | ~$0.104/hr (~$0.83 / 8h) |
| [`scenarios/multi-forest`](scenarios/multi-forest/) | Two AD forests + a two-way trust | Per session | ~$2.92 / 8h |

Budget allows ~15 single-forest or ~9 multi-forest sessions/month under the $30 ceiling.

## Order of operations

1. **Once:** apply `range-network`.
2. **Per session:** apply `ops-tier`, then a scenario.
3. **Teardown:** destroy the scenario and `ops-tier`; leave `range-network` up.

## Conventions

- Provider pinned `hashicorp/aws 6.66.0`, `terraform >= 1.9.0`, identical across roots.
- `project`, `aws_region` and `availability_zone` must match in all three roots.
