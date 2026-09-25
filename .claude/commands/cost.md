Report range cost against the **$30/month ceiling** ([.claude/rules/cost-guardrails.md](../rules/cost-guardrails.md)). Read-only.

Two halves: **projected** (from Terraform) and **actual** (from the provider bill).

## Projected — infracost

For each Terraform root that has provider config, estimate monthly cost:

```bash
for d in $(find _infra/terraform -name '*.tf' -path '*main.tf' -printf '%h\n' | sort -u); do
  echo "== $d =="
  infracost breakdown --path "$d" --no-color 2>/dev/null || echo "  (skipped: no priced resources / provider not configured)"
done
```

## Actual — live spend (when cloud creds are available)

```bash
# AWS month-to-date, grouped by service (read-only Cost Explorer):
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null || echo "AWS CE unavailable (no creds / not this provider)"
```

Hetzner has no cost API in the local toolchain — note its fixed monthly (e.g. CX22
≈ €4.49) from the inventory instead.

## Report

Sum projected + actual, compare to **$30/mo**, and flag anything from the
prohibited/rationed table (NAT gateway, ALB/NLB, idle EIPs, always-on mid/large
instances). If over 80% of ceiling, say so prominently and recommend cuts. Never
run apply/destroy — this command only reads.
