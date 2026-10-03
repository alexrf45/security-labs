# Cost Guardrails — the $30/month ceiling

The cloud range runs on a **hard budget of $30/month, all-in, across every provider.**
Cost is a first-class design constraint, not an afterthought. Every architecture and
every `plan` is evaluated against this ceiling *before* it is proposed. When a design
can't fit, say so and cut scope — do not silently ship something that busts the budget.

## Non-negotiable operating rules

1. **Ephemeral by default — zero always-on compute.** Per ADR-0011 *nothing* runs 24/7,
   the ops tier included: the Tailscale subnet router is brought up for a session and
   destroyed with it. The only standing cost is storage (≈ $2.70/mo, the SIEM EBS
   volume). Scenario hosts are created for a session and **destroyed or stopped** at the
   end of it. "Left it running" is the #1 budget killer — the `/lab-status` command
   exists to catch it.
2. **`infracost breakdown` is mandatory** before proposing any Terraform change that
   adds or resizes billable resources. Quote the monthly delta and the new running
   total against $30. Claude runs `infracost breakdown` itself (read-only); it never
   runs `apply`.
3. **Prefer the cheapest primitive that works.** ARM/Graviton or shared-vCPU over
   dedicated; spot/interruptible over on-demand for victim hosts; scheduled stop
   over always-on; snapshot-and-destroy over keep-warm.
4. **A budget alarm is part of every environment.** AWS Budgets + notifications at
   50% / 80% / 100% of $30, provisioned alongside the first resource, not later
   (`range-network/budgets.tf`). A budget with zero notifications looks configured in
   the console and alerts nobody, so `budget_alert_emails` is required and validated.
5. **Metrics before scale.** `/cost` reports live spend (e.g. `aws ce
   get-cost-and-usage`) vs the ceiling. Check it before adding anything.

## Prohibited / rationed resources (they alone bust the budget)

| Resource | Cost | Rule |
| --- | --- | --- |
| AWS NAT Gateway | ~$0.045/hr ≈ **$32.85/mo** + $0.045/GB | **Forbidden.** Use a Tailscale subnet router on a micro instance for egress instead. |
| AWS public IPv4 | $0.005/hr ≈ **$3.65/mo each**, idle or not | **Ration hard.** Prefer Tailscale-only reachability; count every EIP/auto-assigned IP against budget. |
| AWS ALB/NLB | ~$16+/mo base | **Forbidden** for the lab. Expose via Tailscale, not a load balancer. |
| Always-on mid/large instances | varies | **Forbidden** as a default. Attacker/victim boxes are on-demand. |
| Cross-AZ / egress data | $0.01–0.09/GB | Keep scenarios single-AZ; mind egress on artifact pulls. |

## Cheap building blocks that fit

- Tailscale (free plan) replaces NAT gateway + bastion + most public IPv4 spend — this
  is *why* Tailscale is the mandated entrypoint, not just for ergonomics.
- AWS: smallest ARM/Graviton instances on-demand, launched for a session and destroyed;
  spot for victim hosts; no NAT, no ALB, Tailscale for entry.
- EBS `gp3` for the one volume that must persist between sessions; snapshot-and-destroy
  over keep-warm for everything else.

**Hetzner is not one of these.** ADR-0011 evaluated and rejected it — the CX22 plan is
gone, June 2026 repricing moved plans +38%/+144%/+169%, Windows is console-ISO-only, and
it has no cost API to satisfy rule 4. Do not reach for it
([cloud-inventory.md](cloud-inventory.md)).

See [range-safety.md](range-safety.md) (Tailscale-only entry / no-public-IP invariants
pull in the same direction as cost) and [terraform.md](terraform.md) (the infracost
gate). The provider/topology decision is **ADR-0011** (Accepted): AWS-only, with a
standing cost of ≈ $2.70/mo and everything else per-session.
