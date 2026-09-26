## Cost Guardrails — the $30/month ceiling

The cloud range runs on a **hard budget of $30/month, all-in, across every provider.**
Cost is a first-class design constraint, not an afterthought. Every architecture and
every `plan` is evaluated against this ceiling *before* it is proposed. When a design
can't fit, say so and cut scope — do not silently ship something that busts the budget.

### Non-negotiable operating rules

1. **Ephemeral by default.** Nothing runs 24/7 except the always-on entry tier (one
   small Tailscale subnet router / bastion). Scenario hosts are created for a session
   and **destroyed or stopped** at the end of it. "Left it running" is the #1 budget
   killer — the `/lab-status` command exists to catch it.
2. **`infracost breakdown` is mandatory** before proposing any Terraform change that
   adds or resizes billable resources. Quote the monthly delta and the new running
   total against $30. Claude runs `infracost breakdown` itself (read-only); it never
   runs `apply`.
3. **Prefer the cheapest primitive that works.** ARM/Graviton or shared-vCPU over
   dedicated; spot/interruptible over on-demand for victim hosts; scheduled stop
   over always-on; snapshot-and-destroy over keep-warm.
4. **A budget alarm is part of every environment.** A provider-native budget + alarm
   (AWS Budgets; Hetzner has no cost API — use its billing alerts / a cron cost check)
   at 50% / 80% / 100% of $30 is provisioned alongside the first resource, not later.
5. **Metrics before scale.** `/cost` reports live spend (e.g. `aws ce
   get-cost-and-usage`) vs the ceiling. Check it before adding anything.

### Prohibited / rationed resources (they alone bust the budget)

| Resource | Cost | Rule |
| --- | --- | --- |
| AWS NAT Gateway | ~$0.045/hr ≈ **$32.85/mo** + $0.045/GB | **Forbidden.** Use a Tailscale subnet router on a micro instance for egress instead. |
| AWS public IPv4 | $0.005/hr ≈ **$3.65/mo each**, idle or not | **Ration hard.** Prefer Tailscale-only reachability; count every EIP/auto-assigned IP against budget. |
| AWS ALB/NLB | ~$16+/mo base | **Forbidden** for the lab. Expose via Tailscale, not a load balancer. |
| Always-on mid/large instances | varies | **Forbidden** as a default. Attacker/victim boxes are on-demand. |
| Cross-AZ / egress data | $0.01–0.09/GB | Keep scenarios single-AZ; mind egress on artifact pulls. |

### Cheap building blocks that fit

- Hetzner CX22 (Helsinki) ≈ **€4.49/mo** — viable always-on Linux/Tailscale tier.
- Tailscale (free plan) replaces NAT gateway + bastion + most public IPv4 spend — this
  is *why* Tailscale is the mandated entrypoint, not just for ergonomics.
- AWS: smallest ARM instances on-demand, launched for a session and destroyed; no NAT,
  no ALB, Tailscale for entry.

See [range-safety.md](range-safety.md) (Tailscale-only entry / no-public-IP invariants
pull in the same direction as cost) and [terraform.md](terraform.md) (the infracost
gate). The provider/topology decision is **ADR-0011** (Accepted): AWS-only, with a
standing cost of ≈ $2.70/mo and everything else per-session.
