# `_infra/terraform/aws/` — the cloud range (ADR-0011)

The AWS-only, ephemeral-by-default security range. Three Terraform roots split by blast
radius, **local state each**, discovering one another by **tag** (never
`terraform_remote_state`). Built per [ADR-0011](../../../_docs/decisions/0011-aws-provider-and-range-topology.md).

```
aws/
├── range-network/          long-lived shared fabric (~$2.70/mo)   ← apply once, leave up
├── ops-tier/               per-session router + attacker + collector
└── scenarios/
    └── multi-forest/       per-session: 2 AD forests + two-way trust
```

| Root | Lifecycle | Standing / session cost |
| --- | --- | --- |
| [`range-network`](range-network/) | long-lived | ~$2.70/mo (30 GB gp3 SIEM + Cost Explorer) |
| [`ops-tier`](ops-tier/) | per session | ~$0.084/hr compute (~$0.71 / 8h) |
| [`scenarios/multi-forest`](scenarios/multi-forest/) | per session | $0.357/hr all-in → ~$2.86 / 8h (spot members: ~$2.26) |

Budget: ~15 full single-forest or ~10 multi-forest sessions/month under the $30 ceiling.
(Collector is t4g.medium so the Wazuh stack fits — see `ops-tier`.)

## Order of operations

1. **Once:** apply `range-network` (VPC, subnets, NACL, SGs, DHCP, Budgets, SIEM volume).
2. **Per session:** apply `ops-tier`, then a scenario (e.g. `scenarios/multi-forest`).
3. **Teardown:** destroy the scenario and `ops-tier`; leave `range-network` up. The SIEM
   volume has `prevent_destroy` so the defensive index survives.

## Rules that bind this tree

- **`.claude/rules/range-safety.md`** — isolation invariants 1–11 (no egress route / no
  public IP on detonation, VPC DNS off, SG+NACL ops↔det separation, IMDSv2 + no role).
- **`.claude/rules/cost-guardrails.md`** — the $30 ceiling; ephemeral default.
- **`.claude/rules/terraform.md`** — local state, pinned provider (`hashicorp/aws`
  6.66.0 across all roots), offline checks only, infracost gate (Windows usage file).

> **Claude runs offline checks only** (`fmt`/`validate`/`tflint`/`infracost breakdown`).
> The **user** runs `plan`/`apply`/`destroy` manually under `op run --`; the
> `guard-mutations.sh` PreToolUse hook enforces this. Never commit `*.tfstate`.

## Not here (deferred / archived)

- **Packer** is deferred: stock AMIs + `user_data` cover every current need (ADR-0011 §6).
- The **Proxmox era** (`modules/`, `packer/`, `security-lab/`) is archived under
  `_docs/archive/proxmox/`.
