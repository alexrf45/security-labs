# AWS range — deployment status

Single pane of glass for where the range deployment stands. Update as you go.

> **Working document, not a guide.** The ordered steps live in
> [Deploy the AWS range](aws-range-deployment.md); fixes live in
> [Troubleshoot the AWS range](aws-range-troubleshooting.md). This page records *state*
> only, so it is the one page expected to go stale between sessions; re-derive from
> [live state](#derive-state-from-aws) when in doubt.

**Last updated:** 2026-09-26 · **Branch:** `feat/cloud-native-aws-range` · **Nothing
deployed yet.**

## Phases

| Phase | Root | Applied | Lifetime | Notes |
| --- | --- | --- | --- | --- |
| 0 · Prerequisites | — | ☐ | — | Creds (non-root), 1Password items, Kali subscription, tailnet, SSH agent vault, **account EBS/IMDS baseline** |
| 1 · Shared fabric | `range-network/` | ☐ | Long-lived | Apply **once**, leave up. `budget_alert_emails` is now required, and the AWS confirmation mail must be accepted |
| 2 · Ops tier | `ops-tier/` | ☐ | Per session | Router + attacker + collector |
| 3 · Scenario | `scenarios/multi-forest/` | ☐ | Per session | Two forests + trust |

Pick up at the first unchecked phase. A partially-applied root is safe to resume:
re-running `apply` converges.

## Gates

Hard gates, in order. Each must pass before the next phase.

| # | Gate | Phase | Status |
| --- | --- | --- | --- |
| 1 | VPC `EnableDnsSupport = false` | 1 | ☐ |
| 2 | Victim route table has no `0.0.0.0/0` route | 1 | ☐ |
| 3 | SIEM volume `available` | 1 | ☐ |
| 4 | **Invariant 10 DNS tests**, see below | 1→2 | ☐ |
| 5 | Router advertising `10.40.10.0/24`, shell on all three ops hosts | 2 | ☐ |
| 6 | Collector bootstrap resolved the SIEM volume | 2 | ☐ |
| 7 | Both forests up, trust bidirectional, agents `Active` | 3 | ☐ |

### Gate 4 — invariant 10 (VPC DNS off)

The one isolation claim that security groups and NACLs *cannot* enforce, and which has
never been tested (review finding **S-1**). Run from a victim host before any sample runs.
All four results must hold:

| From a victim host | Required result | Actual |
| --- | --- | --- |
| `nslookup example.com 10.40.0.2` | fails / times out | ☐ |
| `nslookup example.com 169.254.169.253` | fails / times out | ☐ |
| `nslookup example.com 1.1.1.1` | fails / times out | ☐ |
| `nslookup <own domain> <own DC ip>` | **succeeds** | ☐ |

If either link-local query resolves, invariant 10 is not closed; stop and read S-1 in the
[review](../reviews/cloud-range-implementation-review-2026-09-25.md).

## Open items blocking or shaping deployment

From the [pre-deployment review](../reviews/cloud-range-implementation-review-2026-09-25.md)
(17 findings). Blockers are cleared; these are what remain.

| ID | Severity | Item | Status |
| --- | --- | --- | --- |
| B-1…B-4 | High–Med | Shell access, EBS race, `user_data` re-run, AD password abort | **Done** 2026-09-26 |
| H-1, H-2 | High, Low | Mutation guard failing open; no-op format hook | **Done**, verified in force |
| K-1 | Med-High | Tailscale key + RDP password land in world-readable instance logs | **Done** 2026-09-26 |
| K-2 | Medium | Empty `budget_alert_emails` ships an alarm-less budget | **Done** 2026-09-26 |
| S-6 | Low | VPC default security group unmanaged (CIS/FSBP EC2.2) | **Done** 2026-09-26 |
| S-7 | Low | Account-level guardrails unused (IMDS/EBS defaults) | **Done** 2026-09-26 — set out of band, see Phase 0 |
| S-1 | High (verify) | Invariant 10 untested → **gate 4** above | ☐ **Next** (needs Phase 1 applied) |
| S-4 | Medium | Windows KMS 1688 likely blocked; verify on first Windows boot | ☐ Phase 3 |
| S-3 | Low-Med | No ICMP egress on the victim NACL (`ping` fails) | **Done** 2026-09-26 |
| C-1 | Medium | Collector below Wazuh's documented floor; Wazuh pinned 5 minors back | **Done** 2026-09-26 |
| C-2 | Low | Cost-table drift (and an over-ceiling sessions/month claim) | **Done** 2026-09-26 |
| D-1…D-3 | Low | Lint gaps, doc/robustness nits | **Done** 2026-09-26 |
| S-5 | Low-Med | No flow logs, so §6 "logged" exceptions aren't logged | ☐ **Next** |
| S-2 | Medium | Shared victim SG = no inter-scenario isolation | ☐ Design call |

## Derive state from AWS

When this page is stale, these answer it from live state instead:

| Question | Command |
| --- | --- |
| Which roots are applied? | `terraform state list` in each root (empty = not applied) |
| Is the shared fabric up? | `aws ec2 describe-vpcs --filters Name=tag:Discovery,Values=range-vpc` |
| What's running right now? | `/lab-status`, or the `describe-instances` query in the runbook |
| Is the router on the tailnet? | `tailscale status` |
| Did a host finish bootstrapping? | `ssh` in, read `/var/log/*-bootstrap.log` |
| Spend vs the $30 ceiling? | `/cost`, or `aws ce get-cost-and-usage` |

## Session log

| Date | Phases applied | Duration | Est. cost | Notes |
| --- | --- | --- | --- | --- |
| — | — | — | — | No sessions yet |

Running total this month: **$0** of the **$30** ceiling. Budget fits **9** multi-forest or
**15** single-forest sessions; 10 multi-forest would exceed it.
