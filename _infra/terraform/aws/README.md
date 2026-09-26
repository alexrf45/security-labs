# `_infra/terraform/aws/` — the cloud range

Three Terraform roots, local state each, split by blast radius. Downstream roots discover
the shared fabric **by tag**, never `terraform_remote_state`.

Design rationale: [ADR-0011](../../../_docs/decisions/0011-aws-provider-and-range-topology.md).
Deploy steps: [runbook](../../../_docs/runbooks/aws-range-deployment.md).

| Root | Holds | Lifecycle | Cost |
| --- | --- | --- | --- |
| [`range-network`](range-network/) | VPC, subnets, NACL, SGs, Budgets, SIEM volume | Long-lived; apply once | ~$2.70/mo |
| [`ops-tier`](ops-tier/) | Router, attacker, collector | Per session | ~$0.084/hr (~$0.71 / 8h) |
| [`scenarios/multi-forest`](scenarios/multi-forest/) | Two AD forests + a two-way trust | Per session | ~$2.86 / 8h |

Budget allows ~15 single-forest or ~9 multi-forest sessions/month under the $30 ceiling.

## Order of operations

1. **Once:** apply `range-network`.
2. **Per session:** apply `ops-tier`, then a scenario.
3. **Teardown:** destroy the scenario and `ops-tier`; leave `range-network` up.

## Conventions

- Provider pinned `hashicorp/aws 6.66.0`, `terraform >= 1.9.0`, identical across roots.
- `project`, `aws_region` and `availability_zone` must match in all three roots.
- Packer is not used; stock AMIs plus `user_data` cover every current need.

> **Claude runs offline checks only** (`fmt`/`validate`/`tflint`/`infracost breakdown`).
> The **user** runs `plan`/`apply`/`destroy` under `op run --`; the `guard-mutations.sh`
> hook enforces this. Never commit `*.tfstate`.

Binding rules: [`range-safety.md`](../../../.claude/rules/range-safety.md) (isolation
invariants), [`cost-guardrails.md`](../../../.claude/rules/cost-guardrails.md) (the $30
ceiling), [`terraform.md`](../../../.claude/rules/terraform.md).
