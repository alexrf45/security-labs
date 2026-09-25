The "did I leave something running?" check. Read-only. Its job is to catch idle
resources burning the $30/mo budget and to show what's live.

Run these and summarize:

```bash
# 1) Terraform roots that currently hold state (i.e. something may be provisioned)
find _infra/terraform -name terraform.tfstate -printf '%h\n' 2>/dev/null | sort -u \
  | while read -r d; do
      n=$(terraform -chdir="$d" state list 2>/dev/null | wc -l)
      echo "  $d : $n resources in state"
    done

# 2) Live cloud instances (read-only; whichever provider is configured)
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Type:InstanceType,Pub:PublicIpAddress}' \
  --output table 2>/dev/null || echo "AWS describe unavailable (no creds / not this provider)"

# 3) Tailscale — what's on the tailnet right now
tailscale status 2>/dev/null || echo "tailscale not up locally"
```

## Report

- List every root with non-zero state and every running instance.
- **Flag any running instance with a public IP** (violates
  [range-safety.md](../rules/range-safety.md)) and any instance that looks
  always-on but shouldn't be (violates [cost-guardrails.md](../rules/cost-guardrails.md)).
- Remind the user of the teardown command for anything meant to be ephemeral —
  but **do not run destroy yourself** (the guard blocks it; teardown is the user's
  manual `op run -- terraform destroy`).
