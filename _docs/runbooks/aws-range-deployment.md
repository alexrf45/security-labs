# Deploy the AWS range

Stand up the cloud range on AWS: shared fabric, ops tier, then a scenario. Each phase is
independent and verifiable; you can stop after any one of them.

> **Internal document.** Contains real lab values: vault names, item titles, CIDRs.
>
> **Current progress:** [deployment status](aws-range-deployment-status.md) — applied
> phases, open gates, session log.
> **Something broken?** [Troubleshoot the AWS range](aws-range-troubleshooting.md).
>
> **See also:** [ADR-0011](../decisions/0011-aws-provider-and-range-topology.md) (design
> and cost model, and the rationale for anything below) · [range
> reference](../reference/aws-range-reference.md) (variable, tag, port, SG and NACL
> tables) · [`range-safety.md`](../../.claude/rules/range-safety.md) (isolation invariants
> — read before changing networking) · each root's `README.md`.

## Overview

Three Terraform roots, local state each, split by blast radius. Downstream roots find the
shared fabric **by resource tag**, never `terraform_remote_state`.

| Phase | Root | Lifetime | Cost |
| --- | --- | --- | --- |
| [0](#phase-0--before-you-start) | — | — | — |
| [1](#phase-1--shared-fabric) | `range-network/` | Long-lived; apply once | ≈ $2.70/mo standing |
| [2](#phase-2--ops-tier) | `ops-tier/` | Per session | ≈ $0.104/hr (~$0.83 / 8h) |
| [3](#phase-3--scenario) | `scenarios/multi-forest/` | Per session | ≈ $2.92 / 8h all-in |

**Apply 1 → 2 → 3. Tear down 3 → 2, and leave 1 up.**

```mermaid
graph TB
    subgraph P1["Phase 1 · range-network (long-lived)"]
        NET["VPC 10.40.0.0/16 (DNS off) · ops + victim00/victim01 subnets<br/>NACL · 4 SGs · DHCP · Budgets · persistent SIEM volume<br/>tagged: Discovery / SubnetName / SGRole / Project"]
    end
    subgraph P2["Phase 2 · ops-tier (per session)"]
        OPS["router (t4g.micro+EIP, arm64) · attacker/SCRT (t3.medium)<br/>collector/Wazuh (t3.medium, mounts SIEM volume)"]
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

Every `plan`/`apply`/`destroy` is run by you, wrapped in the 1Password CLI. Roots that
take secrets carry a gitignored `.envrc` that exports `TF_VAR_*` as **1Password
references, never values**. direnv loads it on `cd`:

```bash
# <root>/.envrc — run `direnv allow` once after creating or editing it
export TF_VAR_<name>="op://<vault>/<item>/<field>"
```

Those roots need two 1Password layers. AWS credentials come from the 1Password **AWS
shell plugin** (`op plugin run`), which injects them but does not resolve `op://`
references. `op run` resolves the references but injects no plugin credentials. Chain them:

```bash
op run -- op plugin run -- terraform apply
```

Roots with no secret variables (`range-network`) need only the plugin layer.

`op run` resolves references only from the environment it starts with. A variable set
after it starts, such as `op run -- env TF_VAR_x="op://…" terraform apply`, reaches
Terraform as the literal `op://…` string. Every secret variable rejects an `op://` value,
so this fails at plan instead of shipping the reference string to a host.

---

## Phase 0 — Before you start

| Requirement | Check |
| --- | --- |
| Tools: `terraform`, `aws`, `op`, `tailscale`, `sops`, `infracost`, `tflint` | Present per `cloud-inventory.md` |
| AWS credentials resolve through `op run`, and are **not** root | `op run -- aws sts get-caller-identity` |
| Region `us-east-1`, AZ `us-east-1a` in every root | Defaults; the SIEM volume is AZ-bound |
| Tailnet joined | `tailscale status` |
| Kali Marketplace subscription accepted | One-time per account; without it the attacker AMI won't launch |
| `Security` listed in `~/.config/1Password/ssh/agent.toml` | The agent only serves keys from listed vaults |
| `tflint --init` run once | Fetches the AWS ruleset |
| Account security baseline set (below) | One-time, deliberately not Terraform-managed |

### Account baseline (one-time, out of band)

```bash
aws ec2 enable-ebs-encryption-by-default
aws ec2 enable-snapshot-block-public-access --state block-all-sharing
aws ec2 modify-instance-metadata-defaults --http-tokens required --http-put-response-hop-limit 1
```

Confirm:

```bash
aws ec2 get-ebs-encryption-by-default        # EbsEncryptionByDefault: true
aws ec2 get-snapshot-block-public-access     # State: block-all-sharing
aws ec2 get-instance-metadata-defaults       # HttpTokens: required, HopLimit: 1
```


### 1Password items


| Item | Field | Used by | Notes |
| --- | --- | --- | --- |
| `tailscale-range-router` | `authkey` | Phase 2 | Reusable + ephemeral + pre-authorized |
| `security_labs` | `public key` | Phase 2 | SSH Key item; private half never leaves 1Password |
| `scrt-attacker` | `password` | Phase 2 | xrdp login for the `kali` user |
| `range-ad` | `admin-password`, `dsrm-password` | Phase 3 | Domain admin + DSRM, both forests |

Create them:

```bash
genpw() { local p; while :; do p=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24); [[ $p == *[A-Z]* && $p == *[a-z]* && $p == *[0-9]* ]] && { printf '%s' "$p"; return; }; done; }

# Paste a key generated in the Tailscale admin console:
op item create --category "Secure Note" --vault Security --title "tailscale-range-router" \
  "authkey[password]=tskey-auth-REPLACE-ME"

# Generated inside 1Password, so no private key file is created on this machine:
op item create --category ssh --vault Security --title "security_labs"

op item create --category "Secure Note" --vault Security --title "scrt-attacker" \
  "password[password]=$(genpw)"

op item create --category "Secure Note" --vault Security --title "range-ad" \
  "admin-password[password]=$(genpw)" "dsrm-password[password]=$(genpw)"
```

Confirm every reference resolves. Quote the SSH one — its field name contains a space:

```bash
op read "op://Security/tailscale-range-router/authkey"
op read "op://Security/scrt-attacker/password"
op read "op://Security/wazuh-dashboard/password"   # 8-64 chars; symbols only from . * + ? -
op read "op://Security/range-ad/admin-password"
op read "op://Security/range-ad/dsrm-password"
op read "op://Security/security_labs/public key" | cut -d' ' -f1   # -> ssh-ed25519
```

Rotate with `op item edit <title> --vault Security "<field>[password]=$(genpw)"`, then
re-apply that root. Regenerate the Tailscale key in the admin console.

---

## Phase 1 — Shared fabric

Network fabric, security groups, budget, persistent SIEM volume.

```bash
cd _infra/terraform/aws/range-network
op run -- terraform init

export TF_VAR_budget_alert_emails='["you@example.com"]'   # required, no default

op run -- terraform plan     # ~44 resources
op run -- terraform apply
```

Optional: `TF_VAR_enable_agent_package_mirror=true` for air-gapped agent installs. Needed
for Phase 3 telemetry, and must match in Phase 2.

### Verify

```bash
op run -- terraform output    # vpc_id, victim_subnet_ids, security_group_ids, siem_volume_id

VPC=$(op run -- aws ec2 describe-vpcs --filters Name=tag:Discovery,Values=range-vpc \
  --query 'Vpcs[0].VpcId' --output text)

# describe-vpcs does not return DNS attributes; use describe-vpc-attribute, one per call.
op run -- aws ec2 describe-vpc-attribute --vpc-id "$VPC" \
  --attribute enableDnsSupport   --query 'EnableDnsSupport.Value'     # MUST be false
op run -- aws ec2 describe-vpc-attribute --vpc-id "$VPC" \
  --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value'   # MUST be false

op run -- aws ec2 describe-volumes \
  --filters Name=tag:Discovery,Values=range-siem-volume --query 'Volumes[].State'

op run -- aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" \
  --query 'RouteTables[].{name:Tags[?Key==`Name`]|[0].Value,subnets:Associations[].SubnetId,routes:Routes[].{dst:DestinationCidrBlock,gw:GatewayId}}'

op run -- aws ec2 describe-security-groups \
  --filters Name=group-name,Values=default Name=vpc-id,Values="$VPC" \
  --query 'SecurityGroups[].{in:IpPermissions,out:IpPermissionsEgress}'   # both []

ACCT=$(op run -- aws sts get-caller-identity --query Account --output text)
op run -- aws budgets describe-notifications-for-budget --account-id "$ACCT" \
  --budget-name security-labs-monthly --query 'length(Notifications)'      # expect 4

op run -- aws budgets describe-subscribers-for-notification --account-id "$ACCT" \
  --budget-name security-labs-monthly \
  --notification ComparisonOperator=GREATER_THAN,NotificationType=ACTUAL,Threshold=100,ThresholdType=PERCENTAGE \
  --query 'Subscribers[].{type:SubscriptionType,to:Address}'
```

Route tables must come out exactly like this — one IGW route in the whole range:

| Table | Routes | Associations |
| --- | --- | --- |
| `<project>-victim-rt` | only `10.40.0.0/16 → local` | every victim subnet |
| `<project>-edge-rt` | `local` **plus** `0.0.0.0/0 → igw-…` | the edge subnet only |
| `<project>-ops-rt` | only `local` (Phase 2 adds `0.0.0.0/0 → eni-…`, the router) | the ops subnet only |
| `<project>-main-rt-locked` | only `local` | none |

Pass conditions:

- Both VPC DNS attributes `false` (invariant 10).
- Victim route table has no `0.0.0.0/0` route.
- SIEM volume `available`.
- Default security group has no ingress and no egress rules.
- Budget reports 4 notifications, each carrying your address as an `EMAIL` subscriber.

Leave this root applied between sessions.

---

## Phase 2 — Ops tier

Tailscale subnet router (arm64), attacker box (SCRT), collector (Wazuh, x86_64). Requires
Phase 1.

```bash
cd _infra/terraform/aws/ops-tier
cat > .envrc <<'EOF'
export TF_VAR_tailscale_auth_key="op://Security/tailscale-range-router/authkey"
export TF_VAR_attacker_rdp_password="op://Security/scrt-attacker/password"
export TF_VAR_ssh_public_key="op://Security/security_labs/public key"
export TF_VAR_wazuh_admin_password="op://Security/wazuh-dashboard/password"
EOF
direnv allow
op plugin run -- terraform init
op run -- op plugin run -- terraform apply
```

Add `export TF_VAR_enable_agent_package_mirror=true` to `.envrc` if you enabled the mirror
in Phase 1.

Pre-flight: the official Kali AMI resolves. The UUID suffix is Kali's Marketplace product,
which filters out third-party Kali images in the same `aws-marketplace` account.

```bash
op run -- aws ec2 describe-images --owners aws-marketplace \
  --filters 'Name=name,Values=debian-kali-last-snapshot-amd64-*-804fcc46-63fc-4eb6-85a1-50e66d6c7215' \
  --query 'length(Images)'
```

### Approve the advertised route

cloud-init runs `tailscale up --advertise-routes=10.40.10.0/24` at boot, but the route is
inert until you approve it:

> Tailscale admin console → **Machines** → `range-router` → **Edit route settings** →
> approve `10.40.10.0/24`.


### Verify

```bash
op run -- terraform output ssh        # ready-made ssh command per host
tailscale status | grep range-router
```

| Host | Check |
| --- | --- |
| Router | In `tailscale status` **and** `10.40.10.0/24` approved and reachable. `tailscale ssh ubuntu@range-router` (it sits in the edge subnet, which is not advertised). First boot needs a minute (`/var/log/cloud-init-output.log`). NAT check: `sudo iptables -t nat -S POSTROUTING` shows the `MASQUERADE` rule for `10.40.10.0/24`; `sudo journalctl -k \| grep ops-egress` lists outbound connections from the ops subnet. |
| Attacker | `ssh kali@<attacker_private_ip>`. First boot builds SCRT + i3 — allow several minutes, watch `/var/log/attacker-bootstrap.log`. Then RDP `:3389`. |
| Collector | `ssh ubuntu@<collector_private_ip>`; dashboard at `https://<collector_private_ip>`, user `admin`, password from `wazuh-dashboard` in 1Password (re-applied every boot). `/var/log/collector-bootstrap.log` should open with `SIEM volume vol-… resolved to /dev/…` and end with `dashboard admin password set from 1Password`. On a `WARN: password sync failed`, read `/root/wazuh-passwords-sync.log` (root-only: it contains passwords). |

### Attacker browser: proxies and Burp CA

The attacker bootstrap configures Firefox and the desktop. Two steps are left to you,
once per deployment.

| What | How it's configured | Your step |
| --- | --- | --- |
| Dark desktop | GTK 3/4 `settings.ini` (`gtk-application-prefer-dark-theme=1`) plus a system dconf `color-scheme='prefer-dark'` | none |
| Firefox dark theme, FoxyProxy | Enterprise policy, merged into `/usr/share/firefox-esr/distribution/policies.json`: FoxyProxy (`foxyproxy@eric.h.jung`) is force-installed from addons.mozilla.org; the built-in dark theme and dark web content are defaults you can change | none |
| FoxyProxy entries | `~/foxyproxy-lab.json` in FoxyProxy's own settings format: **Burp** HTTP `127.0.0.1:8080`, **Tor** SOCKS5 `127.0.0.1:9050`, **SOCKS** SOCKS5 `127.0.0.1:7000` (both SOCKS entries proxy DNS) | FoxyProxy → **Options** tab → **Import** → pick the file, then check the **Proxies** tab lists all three and click **Save**. Import alone only fills the form; nothing is stored until Save succeeds, and a failed Save just outlines the bad field in red |
| Burp CA trusted by Firefox | The policy's `Certificates.Install` points at `~/.config/burp/burp-ca.der`. `/usr/local/bin/burp-trust` saves the running Burp's CA (from `http://127.0.0.1:8080/cert`) there, and i3 runs it at login, polling for up to an hour | Open Burp once and accept its licence, then **restart Firefox** |

Why it's built this way:

- **FoxyProxy entries are imported, not pushed by policy.** FoxyProxy does read
  Firefox-managed settings (`storage.managed`), but in that mode its popup refuses to
  switch proxies (`processSelect` returns early when `pref.managed` is set; FoxyProxy
  9.8 source). A policy-pushed config would pin you to one mode.
- **The Burp CA can't be fetched at boot.** Burp creates its CA for the `kali` user on
  first launch, and headless Burp Community stops at its licence agreement. Accepting that
  for you is not something the bootstrap does. The CA persists in
  `~/.java/.userPrefs/burp/prefs.xml`, so this is once per deployment.
- **Firefox reads policy certificates only at startup**, hence the restart. If Burp was
  opened after the i3 watcher gave up, run `burp-trust` by hand.

---

## Phase 3 — Scenario

Two AD forests joined by a two-way trust: four Windows hosts across `victim00` and
`victim01`. Requires Phases 1 and 2.

```bash
cd _infra/terraform/aws/scenarios/multi-forest
cat > .envrc <<'EOF'
export TF_VAR_domain_admin_password="op://Security/range-ad/admin-password"
export TF_VAR_safe_mode_password="op://Security/range-ad/dsrm-password"
EOF
direnv allow
op plugin run -- terraform init

# Always pass the usage file: infracost prices Windows AMIs as Linux.
infracost breakdown --path . --usage-file infracost-usage.yml

op run -- op plugin run -- terraform apply
```

- `TF_VAR_member_use_spot=true` runs the two workstations on spot (~$2.32 / 8h). DCs never
  run on spot.
- `enable_wazuh_agents` (default on) needs the package mirror in **both** Phase 1 and
  Phase 2; without it the forests come up and agents don't install.

### Verify

Promotion and trust creation span multiple reboots — allow 10–20 minutes.

| Check | How |
| --- | --- |
| Forests up | `nslookup forest-a.lab <DC-A ip>` resolves |
| Trust formed | On DC-B: `Get-ADTrust -Filter *` shows a bidirectional trust to `forest-a.lab` |
| Telemetry | Agents show `Active` in the Wazuh dashboard |

---

## Teardown

Reverse order. **Leave `range-network` applied** — its SIEM volume carries the index
between sessions.

```bash
cd _infra/terraform/aws/scenarios/multi-forest && op run -- op plugin run -- terraform destroy
cd ../../ops-tier                              && op run -- op plugin run -- terraform destroy
```

Destroy needs the chained form too: the secret variables are required, so Terraform
evaluates them on destroy as well.

Then confirm nothing is still running:

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
| Ops tier | ~$0.104/hr (~$0.83 / 8h) |
| Full multi-forest session | ~$2.92 / 8h (~$2.32 with spot members) |
| Ceiling | **$30/mo**, alarms at $15 / $24 / $30 |

Roughly 9 multi-forest or 14 single-forest sessions per month. Run `/cost` before adding
anything and after each session. Leaving something running is the top budget risk — always
finish [teardown](#teardown) and confirm the empty instance list.
