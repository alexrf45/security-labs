# Deploy the AWS range

Stand up the cloud range on AWS: shared fabric, ops tier, then a scenario. Each phase is
independent and verifiable, so you can stop after any one of them.

> **Internal document.** Contains real lab values: vault names, item titles, CIDRs.
>
> **Current progress:** [deployment status](aws-range-deployment-status.md) has which
> phases are applied, the gates still open, and the session log.
> **Something broken?** [Troubleshoot the AWS range](aws-range-troubleshooting.md).
>
> **See also:** [ADR-0011](../decisions/0011-aws-provider-and-range-topology.md) (design
> and cost model) · [range reference](../reference/aws-range-reference.md) (variable, tag,
> port, SG and NACL tables) · [`range-safety.md`](../../.claude/rules/range-safety.md)
> (isolation invariants — read before changing networking) · each root's `README.md`
> under `_infra/terraform/aws/`.

## Overview

Three Terraform roots, **local state each**, split by blast radius. Downstream roots find
the shared fabric **by resource tag**, never `terraform_remote_state`; a disposable
scenario must never hold a reader for the shared state file (ADR-0011 §5,
`range-safety.md` §9).

| Phase | Root | Lifetime | Cost |
| --- | --- | --- | --- |
| [0](#phase-0--before-you-start) | — | — | — |
| [1](#phase-1--shared-fabric) | `range-network/` | Long-lived; apply once | ≈ $2.70/mo standing |
| [2](#phase-2--ops-tier) | `ops-tier/` | Per session | ≈ $0.084/hr (~$0.71 / 8h) |
| [3](#phase-3--scenario) | `scenarios/multi-forest/` | Per session | ≈ $2.86 / 8h all-in |

**Apply 1 → 2 → 3.** Each phase discovers what the previous one created. **Tear down
3 → 2**, and leave 1 up.

```mermaid
graph TB
    subgraph P1["Phase 1 · range-network (long-lived)"]
        NET["VPC 10.40.0.0/16 (DNS off) · ops + victim00/victim01 subnets<br/>NACL · 4 SGs · DHCP · Budgets · persistent SIEM volume<br/>tagged: Discovery / SubnetName / SGRole / Project"]
    end
    subgraph P2["Phase 2 · ops-tier (per session)"]
        OPS["router (t4g.micro+EIP) · attacker/SCRT (t3.medium)<br/>collector/Wazuh (t4g.medium, mounts SIEM volume)"]
    end
    subgraph P3["Phase 3 · scenario (per session)"]
        SC["DC-A + WS-A (victim00) · DC-B + WS-B (victim01)<br/>two-way forest trust · Wazuh agents"]
    end
    OPS -. "discovers VPC/subnet/SG/volume by tag" .-> NET
    SC  -. "discovers subnets/SG + collector by tag" .-> NET
    SC  -. "enrolls agents to collector" .-> OPS

    classDef net fill:#1f2a3a,stroke:#4a72a8,color:#dfe8f5
    classDef ops fill:#1f2f22,stroke:#4a8a5c,color:#dff0e4
    classDef sc  fill:#3a1f1f,stroke:#b34747,color:#f2dede
    class NET net
    class OPS ops
    class SC sc
```

### How commands are run

Every `plan`/`apply`/`destroy` is run **by you**, wrapped in the 1Password CLI. Secrets
are injected into the process environment at apply time and never written to disk:

```bash
op run -- env TF_VAR_<name>="op://<vault>/<item>/<field>" terraform apply
```

- Non-secret overrides go in a gitignored `terraform.tfvars`. Most variables have working
  defaults, so in practice you inject only the secrets each phase lists.
- **Local state holds plaintext secrets. Never commit `*.tfstate`** (`secrets.md`).

---

## Phase 0 — Before you start

| Requirement | Check / note |
| --- | --- |
| Tools: `terraform`, `aws`, `op`, `tailscale`, `sops`, `infracost`, `tflint` | Present per `cloud-inventory.md` |
| AWS credentials resolve through `op run` | `op run -- aws sts get-caller-identity` |
| Region `us-east-1`, AZ `us-east-1a` in every root | Defaults; don't diverge: the SIEM volume is AZ-bound |
| Tailnet joined; ACLs allow the `10.40.10.0/24` route | `tailscale status` |
| Kali Marketplace subscription accepted | One-time per account (ADR-0011 §6); without it the attacker AMI lookup fails |
| `Security` listed in `~/.config/1Password/ssh/agent.toml` | The agent only serves keys from listed vaults |
| Account security baseline set (below) | One-time, deliberately **not** Terraform-managed |

### Account baseline (one-time, out of band)

Three account+region settings belong to the AWS account, not to the range. They are set
by hand on purpose:

```bash
aws ec2 enable-ebs-encryption-by-default
aws ec2 enable-snapshot-block-public-access --state block-all-sharing
aws ec2 modify-instance-metadata-defaults --http-tokens required --http-put-response-hop-limit 1
```

Confirm, and re-confirm any time you suspect drift:

```bash
aws ec2 get-ebs-encryption-by-default        # EbsEncryptionByDefault: true
aws ec2 get-snapshot-block-public-access     # State: block-all-sharing
aws ec2 get-instance-metadata-defaults       # HttpTokens: required, HopLimit: 1
```

`range-network` re-checks the first of these on every plan and warns if it has been turned
off. The other two have no Terraform data source, so they stay on this checklist.

### 1Password items

Vault `Security`. Referenced by item name only, never by value.

| Item | Field | Used by | Notes |
| --- | --- | --- | --- |
| `tailscale-range-router` | `authkey` | Phase 2 | Reusable + ephemeral + pre-authorized |
| `security_labs` | `public key` | Phase 2 | SSH Key item; private half never leaves 1Password |
| `scrt-attacker` | `password` | Phase 2 | xrdp login for the `kali` user |
| `range-ad` | `admin-password`, `dsrm-password` | Phase 3 | Domain admin + DSRM, both forests |

To create them from scratch:

```bash
genpw() { local p; while :; do p=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24); [[ $p == *[A-Z]* && $p == *[a-z]* && $p == *[0-9]* ]] && { printf '%s' "$p"; return; }; done; }

# Paste a key generated in the Tailscale admin console:
op item create --category "Secure Note" --vault Security --title "tailscale-range-router" \
  "authkey[password]=tskey-auth-REPLACE-ME"

# Generated inside 1Password, so no private key file is ever created on this machine:
op item create --category ssh --vault Security --title "security_labs"

op item create --category "Secure Note" --vault Security --title "scrt-attacker" \
  "password[password]=$(genpw)"

op item create --category "Secure Note" --vault Security --title "range-ad" \
  "admin-password[password]=$(genpw)" "dsrm-password[password]=$(genpw)"
```

Confirm every reference resolves before applying. Quote the SSH one, whose field name
contains a space:

```bash
op read "op://Security/tailscale-range-router/authkey"
op read "op://Security/scrt-attacker/password"
op read "op://Security/range-ad/admin-password"
op read "op://Security/range-ad/dsrm-password"
op read "op://Security/security_labs/public key" | cut -d' ' -f1   # -> ssh-ed25519
```

To rotate: `op item edit <title> --vault Security "<field>[password]=$(genpw)"`, then
re-apply that root. Regenerate the Tailscale key in the admin console rather than reusing
one across tailnets.

---

## Phase 1 — Shared fabric

The long-lived network fabric, security groups, budget and persistent SIEM volume.

```bash
cd _infra/terraform/aws/range-network
op run -- terraform init

# Required: there is no default, because a budget with no notifications is accepted
# by AWS and looks identical in the console to a working one.
export TF_VAR_budget_alert_emails='["you@example.com"]'

op run -- terraform plan     # ~44 resources; $0 recurring except the volume
op run -- terraform apply
```

**No confirmation email is sent, and none is needed.** The budget subscribes the
addresses directly (`subscriber_email_addresses`, subscription type `EMAIL`), which AWS
delivers without an opt-in handshake — the confirmation flow only exists for SNS-topic
subscribers, which this budget does not use. The first mail you ever receive from it is
a real threshold breach, from `no-reply@budgets.amazonaws.com`. Verify the wiring with
`describe-notifications-for-budget` / `describe-subscribers-for-notification` below, not
by waiting for mail.

Optional: `TF_VAR_enable_agent_package_mirror=true` lets air-gapped victims pull Wazuh installers. Off by default;
needed for Phase 3 telemetry, and must be set in Phase 2 as well.

### Verify

```bash
op run -- terraform output    # vpc_id, victim_subnet_ids, security_group_ids, siem_volume_id

# DNS attributes are NOT part of describe-vpcs output — asking for them there returns
# null, which is not the same as false. Use describe-vpc-attribute, one attribute per call.
VPC=$(op run -- aws ec2 describe-vpcs --filters Name=tag:Discovery,Values=range-vpc \
  --query 'Vpcs[0].VpcId' --output text)

op run -- aws ec2 describe-vpc-attribute --vpc-id "$VPC" \
  --attribute enableDnsSupport   --query 'EnableDnsSupport.Value'     # MUST be false
op run -- aws ec2 describe-vpc-attribute --vpc-id "$VPC" \
  --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value'   # MUST be false

op run -- aws ec2 describe-volumes \
  --filters Name=tag:Discovery,Values=range-siem-volume --query 'Volumes[].State'

# Invariant 1. Route tables carry only a Name tag (no Discovery tag), so filter by
# vpc-id and read all three at once: an over-narrow filter matches nothing and
# flattens to [], which reads exactly like "no default route" but proves nothing.
# Every route table always has the local route, so [] means the filter missed.
op run -- aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" \
  --query 'RouteTables[].{name:Tags[?Key==`Name`]|[0].Value,subnets:Associations[].SubnetId,routes:Routes[].{dst:DestinationCidrBlock,gw:GatewayId}}'
```

The route tables must come out exactly like this — one IGW route in the whole range, on
the ops table:

| Table | Routes | Associations |
| --- | --- | --- |
| `<project>-victim-rt` | only `10.40.0.0/16 → local` | every victim subnet |
| `<project>-ops-rt` | `local` **plus** `0.0.0.0/0 → igw-…` | the ops subnet only |
| `<project>-main-rt-locked` | only `local` | none |

Also confirm the VPC default security group came out empty, and that the budget has
notifications attached:

```bash
op run -- aws ec2 describe-security-groups \
  --filters Name=group-name,Values=default Name=vpc-id,Values=<vpc_id> \
  --query 'SecurityGroups[].{in:IpPermissions,out:IpPermissionsEgress}'   # both [] 

ACCT=$(op run -- aws sts get-caller-identity --query Account --output text)
op run -- aws budgets describe-notifications-for-budget \
  --account-id "$ACCT" \
  --budget-name security-labs-monthly --query 'length(Notifications)'      # expect 4

# And that each notification actually carries your address (a notification with zero
# subscribers is the real alarm-less failure mode):
op run -- aws budgets describe-subscribers-for-notification \
  --account-id "$ACCT" --budget-name security-labs-monthly \
  --notification ComparisonOperator=GREATER_THAN,NotificationType=ACTUAL,Threshold=100,ThresholdType=PERCENTAGE \
  --query 'Subscribers[].{type:SubscriptionType,to:Address}'
```

- Both VPC DNS attributes are `false` (invariant 10).
- Victim route table has **no** `0.0.0.0/0` route; the ops route table has one to the IGW.
- SIEM volume is `available`.
- Default security group has **no** ingress and **no** egress rules (FSBP/CIS EC2.2).
- Budget reports 4 notifications, each with your address as an `EMAIL` subscriber. There
  is no confirmation email to accept.

Leave this root applied between sessions.

---

## Phase 2 — Ops tier

Tailscale subnet router, attacker box (SCRT), and collector (Wazuh). Requires Phase 1.

```bash
cd _infra/terraform/aws/ops-tier
op run -- terraform init
op run -- env \
  TF_VAR_tailscale_auth_key="op://Security/tailscale-range-router/authkey" \
  TF_VAR_attacker_rdp_password="op://Security/scrt-attacker/password" \
  TF_VAR_ssh_public_key="op://Security/security_labs/public key" \
  terraform apply
```

`ssh_public_key` is what gives you a shell on the attacker and collector; the router's
`tailscale up --ssh` covers the router only, and both AMIs refuse password authentication.
Only the public half is passed; the private key stays in 1Password.

Add `TF_VAR_enable_agent_package_mirror=true` if you enabled the mirror in Phase 1.

### Verify

```bash
op run -- terraform output ssh        # ready-made ssh command per host
tailscale status | grep range-router  # advertising 10.40.10.0/24
```

| Host | Check |
| --- | --- |
| Router | Appears in `tailscale status`; `10.40.10.0/24` reachable. Also `tailscale ssh range-router`. First boot needs a minute for `tailscale up` (`/var/log/cloud-init-output.log`). |
| Attacker | `ssh kali@<attacker_private_ip>`. First boot builds SCRT + i3 — **allow several minutes**, watch `/var/log/attacker-bootstrap.log`. Then RDP `:3389` for the desktop. |
| Collector | `ssh ubuntu@<collector_private_ip>`; dashboard at `https://<collector_private_ip>`. `/var/log/collector-bootstrap.log` should open with `SIEM volume vol-… resolved to /dev/…`. |

---

## Phase 3 — Scenario

Two Active Directory forests joined by a two-way trust: four Windows hosts across
`victim00` and `victim01`. Requires Phases 1 and 2 (it discovers the collector by tag).

```bash
cd _infra/terraform/aws/scenarios/multi-forest
op run -- terraform init

# ALWAYS pass the usage file: infracost prices Windows AMIs as Linux (ADR-0011 §2)
infracost breakdown --path . --usage-file infracost-usage.yml   # ~$0.06/hr per Windows host

op run -- env \
  TF_VAR_domain_admin_password="op://Security/range-ad/admin-password" \
  TF_VAR_safe_mode_password="op://Security/range-ad/dsrm-password" \
  terraform apply
```

- `TF_VAR_member_use_spot=true` runs the two workstations on spot (~$2.26 / 8h).
  **Domain controllers never run on spot**: a reclaim destroys the domain.
- Windows telemetry (`enable_wazuh_agents`, default on) needs the package mirror enabled
  in **both** Phase 1 and Phase 2. Without it the forests still come up; agents
  don't install.

### Verify

Promotion and trust creation span multiple reboots: **allow 10–20 minutes.** Check from
the attacker box, or by RDP to a DC:

| Check | How |
| --- | --- |
| Forests up | `nslookup forest-a.lab <DC-A ip>` resolves |
| Trust formed | On DC-B: `Get-ADTrust -Filter *` shows a bidirectional trust to `forest-a.lab` |
| Telemetry | Agents show `Active` in the Wazuh dashboard |

---

## Teardown

Reverse order, and **leave `range-network` applied**: its SIEM volume carries the
detection index and agent registrations between sessions.

```bash
cd _infra/terraform/aws/scenarios/multi-forest && op run -- terraform destroy
cd ../../ops-tier                              && op run -- terraform destroy
```

Then confirm nothing is still running; this is the single biggest budget risk:

```bash
op run -- aws ec2 describe-instances \
  --filters Name=tag:Project,Values=security-labs Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{id:InstanceId,role:Tags[?Key==`Role`]|[0].Value}'
```

---

## Cost

| | |
| --- | --- |
| Standing (Phase 1 only) | ~$2.70/mo |
| Ops tier | ~$0.084/hr (~$0.71 / 8h) |
| Full multi-forest session | ~$2.86 / 8h (~$2.26 with spot members) |
| Ceiling | **$30/mo**, alarms at $15 / $24 / $30 |

That allows roughly 9 multi-forest or 15 single-forest sessions per month. Run `/cost`
before adding anything and after each session. The top budget risk is leaving something
running. Always finish [teardown](#teardown) and confirm the empty instance list.
