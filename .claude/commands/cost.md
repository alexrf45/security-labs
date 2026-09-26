---
description: Report projected (infracost) and actual (AWS Cost Explorer) range cost against the $30/month ceiling.
---

Report range cost against the **$30/month ceiling** ([.claude/rules/cost-guardrails.md](../rules/cost-guardrails.md)). Read-only.

Two halves: **projected** (from Terraform) and **actual** (from the provider bill).

## Projected — infracost

Estimate monthly cost for **every** Terraform root. Discovery is by any `*.tf` file,
not `main.tf`: `range-network` has no `main.tf` (it is `vpc.tf`, `storage.tf`,
`budgets.tf`, …) and a `main.tf` filter silently skipped it — along with the
`aws_ebs_volume.siem` that is the range's entire standing cost.

A root shipping an `infracost-usage.yml` **must** be priced with it. infracost cannot
infer the OS from an AMI ID and prices Windows as Linux, so a bare total on
`scenarios/multi-forest` is a floor, not an estimate ([terraform.md](../rules/terraform.md)).
Measured 2026-09-26: **$137.47/mo without the usage file vs $191.20/mo with it** — the
bare total under-reports that scenario by ~28%.

(Those are 730-hour figures. The range is ephemeral, so divide by 730 and multiply by
expected session hours — $191.20/mo is $0.26/hr, not the expected bill.)

```bash
while IFS= read -r d; do
  echo "== $d =="
  usage=()
  [ -f "$d/infracost-usage.yml" ] && usage=(--usage-file "$d/infracost-usage.yml")
  infracost breakdown --path "$d" "${usage[@]}" --no-color 2>/dev/null \
    || echo "  (skipped: no priced resources / provider not configured)"
done < <(
  find _infra/terraform -type d -name .terraform -prune \
    -o -name '*.tf' -printf '%h\n' | sort -u
)
```

## Actual — live spend (when cloud creds are available)

`End` is **exclusive** and must be strictly after `Start`, so it is tomorrow, not today:
with `End=$(date +%Y-%m-%d)` the call excluded today's spend and, on the 1st of the
month, failed outright — masked by the `||` fallback into a silent "no spend".

```bash
# AWS month-to-date, grouped by service (read-only Cost Explorer):
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date -d tomorrow +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null || echo "AWS CE unavailable (no creds)"
```

AWS is the sole provider ([ADR-0011](../../_docs/decisions/0011-aws-provider-and-range-topology.md)),
so Cost Explorer is the whole actual-spend picture — there is no second bill to add.

## Report

Sum projected + actual, compare to **$30/mo**, and flag anything from the
prohibited/rationed table (NAT gateway, ALB/NLB, idle EIPs, always-on mid/large
instances). If over 80% of ceiling, say so prominently and recommend cuts. Never
run apply/destroy — this command only reads.
