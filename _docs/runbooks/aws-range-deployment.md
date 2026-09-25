# Runbook — AWS range deployment (Phases 0–3) & progress tracker

Master entry point for standing up the cloud range. Walks the ordered deploy
(Phase 0 → 1 → 2 → 3) with verification gates and troubleshooting, and records status
so you can stop anywhere and pick up cleanly. Internal runbook — uses real lab values.

> **Companion docs:** [ADR-0011](../decisions/0011-aws-provider-and-range-topology.md)
> (design & cost model), the [AWS range reference](../reference/aws-range-reference.md)
> (variable / tag / port / SG / NACL tables), `.claude/rules/range-safety.md` (isolation
> invariants — read first), and each root's README under `_infra/terraform/aws/`.

## How Terraform runs here

Wrapped in the 1Password CLI, **by you, manually**: `op run -- terraform apply`. Bare
`terraform`/`packer` under the `op` plugin fail with `interactive IO not available`.
Claude runs **offline checks only** (`fmt`/`validate`/`tflint`/`infracost breakdown`);
the `guard-mutations.sh` hook blocks anything else. **Local state holds plaintext
secrets — never commit `*.tfstate`** (`.claude/rules/secrets.md`).

Sensitive values are injected at apply time from 1Password and never written to disk:

```
op run -- env TF_VAR_<name>="op://<vault>/<item>/<field>" terraform apply
```

Non-secret overrides go in a (gitignored) `terraform.tfvars`; most vars have working
defaults, so in practice you only inject the secrets listed in each phase.

## Status (update as you go)

| Phase | Deliverable | Root / path | Applied? | Notes |
| --- | --- | --- | --- | --- |
| 0 | Prerequisites (creds, 1Password items, Kali sub, tailnet) | — | ☐ | |
| 1 | Shared fabric (VPC, subnets, NACL, SGs, Budgets, SIEM vol) | `aws/range-network/` | ☐ | apply **once**, leave up |
| 2 | Ops tier (router, attacker/SCRT, collector/Wazuh) | `aws/ops-tier/` | ☐ | per session |
| 3 | Multi-forest scenario (2 forests + trust) | `aws/scenarios/multi-forest/` | ☐ | per session |

**Pick up at the first unchecked phase.** Phase 1 is long-lived; Phases 2–3 are
per-session and destroyed at teardown.

---

## How the modules fit together

Three Terraform roots, **local state each**, split by blast radius. Downstream roots
discover the shared fabric **by tag** (`aws_vpc`/`aws_subnet`/`aws_security_group`/
`aws_instance` data sources) — never `terraform_remote_state`, so a disposable scenario
never holds a reader for the shared state file (ADR-0011 §5, range-safety.md §9).

```mermaid
graph TB
    subgraph P1["Phase 1 · range-network (long-lived)"]
        NET["VPC 10.40.0.0/16 (DNS off) · ops + det00/det01 subnets<br/>NACL · 4 SGs · DHCP · Budgets · persistent SIEM volume<br/>tagged: Discovery / SubnetName / SGRole / Project"]
    end
    subgraph P2["Phase 2 · ops-tier (per session)"]
        OPS["router (t4g.micro+EIP) · attacker/SCRT (t3.medium)<br/>collector/Wazuh (t4g.medium, mounts SIEM volume)"]
    end
    subgraph P3["Phase 3 · scenario (per session)"]
        SC["DC-A + WS-A (det00) · DC-B + WS-B (det01)<br/>two-way forest trust · Wazuh agents"]
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

- **Apply order:** 1 → 2 → 3 (each discovers what the previous created).
- **Teardown order:** 3 → 2, leave 1 up (see [Teardown](#session-teardown)).

---

## Phase 0 — Prerequisites

Check each before touching Terraform.

- [ ] **Local tools:** `terraform`, `aws`, `op`, `tailscale`, `sops`, `infracost`,
  `tflint` (all present per `cloud-inventory.md`).
- [ ] **AWS credentials** reachable through `op run` (an `op://` reference or an `aws`
  profile your `op run` environment resolves). Confirm: `op run -- aws sts
  get-caller-identity` returns your account.
- [ ] **1Password items exist** (reference by item name only):
  | Used in | TF var | Suggested `op://` field |
  | --- | --- | --- |
  | ops-tier | `tailscale_auth_key` | `op://Security/tailscale-range-router/authkey` (ephemeral, pre-authorized, reusable) |
  | ops-tier | `attacker_rdp_password` | `op://Security/scrt-attacker/password` |
  | multi-forest | `domain_admin_password` | `op://Security/range-ad/admin-password` |
  | multi-forest | `safe_mode_password` | `op://Security/range-ad/dsrm-password` |
- [ ] **Kali Marketplace subscription** accepted on the account (one-time, per-account —
  ADR-0011 §6). Without it the attacker AMI lookup fails. Subscribe to the official Kali
  Linux listing in the AWS console once.
- [ ] **Tailscale tailnet** ready and your workstation joined. Generate the router's
  auth key as **reusable + ephemeral + pre-authorized**. Make sure your tailnet ACLs
  allow you to reach the advertised route `10.40.10.0/24`.
- [ ] **Region** is `us-east-1` (all roots default here; the SIEM volume and every
  instance share `us-east-1a`).

### Create the 1Password items (vault `Security`)

Passwords are **letters + digits only, on purpose**: they're templated into PowerShell
and shell `user_data`, where a quote, `$`, or backtick would break the script — or in
PowerShell, `$(...)` in a value would *execute*. This helper guarantees AD complexity
(upper + lower + digit) without symbols:

```bash
genpw() { local p; while :; do p=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24); [[ $p == *[A-Z]* && $p == *[a-z]* && $p == *[0-9]* ]] && { printf '%s' "$p"; return; }; done; }

# 1) Tailscale subnet-router key — paste one generated in the Tailscale admin console
#    (reusable + ephemeral + pre-authorized):
op item create --category "Secure Note" --vault Security \
  --title "tailscale-range-router" \
  "authkey[password]=tskey-auth-REPLACE-ME"

# 2) SCRT attacker (kali) RDP password — generated:
op item create --category "Secure Note" --vault Security \
  --title "scrt-attacker" \
  "password[password]=$(genpw)"

# 3) AD domain-admin + DSRM passwords (both forests) — generated, one item:
op item create --category "Secure Note" --vault Security \
  --title "range-ad" \
  "admin-password[password]=$(genpw)" \
  "dsrm-password[password]=$(genpw)"
```

Verify each resolves (these are the exact refs the apply steps use):

```bash
op read "op://Security/tailscale-range-router/authkey"
op read "op://Security/scrt-attacker/password"
op read "op://Security/range-ad/admin-password"
op read "op://Security/range-ad/dsrm-password"
```

> To rotate later, `op item edit <title> --vault Security "<field>[password]=$(genpw)"`
> and re-apply the affected root. The Tailscale key is single-purpose — regenerate it in
> the admin console and update the item, don't reuse across tailnets.

---

## Phase 1 — `range-network` (apply once, leave up)

The shared, long-lived fabric. Standing cost ≈ **$2.70/mo** (30 GB gp3 SIEM volume +
Cost Explorer). Everything else it creates is free.

```
cd _infra/terraform/aws/range-network
op run -- terraform init
op run -- terraform plan          # expect ~44 resources, $0 recurring except the volume
op run -- terraform apply
```

Set your budget-alarm address first (not a secret, but not committed):

```
op run -- env TF_VAR_budget_alert_emails='["you@example.com"]' terraform apply
```

To turn on the air-gapped **agent package mirror** (needed later for Wazuh agents on
victims — see Phase 3), add `TF_VAR_enable_agent_package_mirror=true`. Off by default.

### ✅ Checkpoint — Phase 1 done when

```
op run -- terraform output          # vpc_id, ops/detonation subnet ids, sg ids, siem_volume_id
op run -- aws ec2 describe-vpcs --filters Name=tag:Discovery,Values=range-vpc \
  --query 'Vpcs[].{id:VpcId,dns:EnableDnsSupport}'   # dns MUST be false
op run -- aws ec2 describe-volumes \
  --filters Name=tag:Discovery,Values=range-siem-volume --query 'Volumes[].State'
```

- VPC exists with **`EnableDnsSupport = false`** (invariant #10).
- Detonation route table has **no** `0.0.0.0/0` route; ops route table has one to the IGW.
- SIEM volume is `available`.

Leave this root applied between sessions. Its state has `prevent_destroy` on the volume.

---

## Phase 2 — `ops-tier` (per session)

Router + attacker (SCRT) + collector (Wazuh). ≈ **$0.084/hr** compute (~$0.71 / 8h).
Requires Phase 1 applied (discovered by tag).

```
cd _infra/terraform/aws/ops-tier
op run -- terraform init
op run -- env \
  TF_VAR_tailscale_auth_key="op://Security/tailscale-range-router/authkey" \
  TF_VAR_attacker_rdp_password="op://Security/scrt-attacker/password" \
  terraform apply
```

If you enabled the package mirror in Phase 1, also pass
`TF_VAR_enable_agent_package_mirror=true` here so the collector serves the installers.

### ✅ Checkpoint — Phase 2 done when

```
op run -- terraform output           # router_public_ip, *_private_ip
tailscale status | grep range-router # the subnet router appears, advertising 10.40.10.0/24
```

- **Router:** shows in `tailscale status`; you can reach `10.40.10.0/24`. First boot
  takes a minute for `tailscale up` (logs: `/var/log/cloud-init-output.log`).
- **Attacker (SCRT):** SSH to its private IP over Tailscale. First boot runs the SCRT
  build + i3 install — **allow several minutes**; watch `/var/log/attacker-bootstrap.log`.
  Then RDP to `:3389` for the i3 desktop (needs `attacker_rdp_password` set).
- **Collector (Wazuh):** browse `https://<collector_private_ip>` over Tailscale for the
  dashboard. Watch `/var/log/collector-bootstrap.log`. The indexer data and
  `/var/ossec/etc` are bind-mounted onto the persistent volume.

---

## Phase 3 — `scenarios/multi-forest` (per session)

Two forests + a two-way trust, four Windows hosts. ≈ **$2.86 / 8h** all-in
(spot members ~$2.26). Requires Phases 1 **and** 2 (it discovers the collector by tag).

**Always run the cost gate with the Windows usage file** — infracost prices Windows as
Linux otherwise (ADR-0011 §2):

```
cd _infra/terraform/aws/scenarios/multi-forest
op run -- terraform init
infracost breakdown --path . --usage-file infracost-usage.yml   # confirm ~$0.06/hr per Win host
op run -- env \
  TF_VAR_domain_admin_password="op://Security/range-ad/admin-password" \
  TF_VAR_safe_mode_password="op://Security/range-ad/dsrm-password" \
  terraform apply
```

- Windows telemetry (`enable_wazuh_agents`, default true) needs the **package mirror on**
  in Phase 1 *and* Phase 2 (victims are air-gapped). Without it the forests still stand
  up; agents just won't install until the mirror (or a baked AMI) is in place.
- To run the two workstations on spot: `TF_VAR_member_use_spot=true`. **DCs never spot.**

### ✅ Checkpoint — Phase 3 done when

```
op run -- terraform output          # forest_a / forest_b host IPs
```

Windows promotion + trust are multi-reboot and take **10–20 min**. From the attacker box
(RDP/SSH over Tailscale), or by RDP to a DC once its password is set:

- **Forests up:** each DC resolves its own domain; `nslookup forest-a.lab <DC-A ip>` works.
- **Trust formed:** on DC-B, `Get-ADTrust -Filter *` shows a bidirectional trust to
  `forest-a.lab`. If not, see [trust troubleshooting](#trust-does-not-form).
- **Telemetry:** agents appear in the Wazuh dashboard (Agents view) as `Active`.

---

## Session teardown

Reverse order. **Leave `range-network` up** — its SIEM volume (`prevent_destroy`) keeps
the detection index and agent registrations across sessions.

```
cd _infra/terraform/aws/scenarios/multi-forest && op run -- terraform destroy
cd ../../ops-tier                              && op run -- terraform destroy
# range-network: leave applied. Only destroy to decommission the whole range.
```

After teardown, confirm nothing is left running (the #1 budget risk):

```
op run -- aws ec2 describe-instances \
  --filters Name=tag:Project,Values=security-labs Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{id:InstanceId,role:Tags[?Key==`Role`]|[0].Value}'
```

Expect an empty list. (`/lab-status` automates this check.)

---

## Where am I? (resuming mid-deploy)

Run these to identify state before continuing:

| Question | Command |
| --- | --- |
| Which roots are applied? | `terraform state list` in each root dir (empty = not applied) |
| Is the shared fabric up? | `aws ec2 describe-vpcs --filters Name=tag:Discovery,Values=range-vpc` |
| What's running right now? | the `describe-instances` query above |
| Is the router on the tailnet? | `tailscale status` |
| Did an instance finish bootstrapping? | SSH/RDP in, read `/var/log/*-bootstrap.log` (or `cloud-init-output.log`) |
| Current spend vs ceiling? | `/cost`, or `aws ce get-cost-and-usage` |

A partially-applied root is safe to resume: re-running `op run -- terraform apply`
converges to the desired state (Terraform is declarative).

---

## Troubleshooting

### `interactive IO not available`
You ran bare `terraform`/`packer`. Always wrap in `op run --`. For offline checks only,
`terraform validate`/`fmt` work without `op`.

### `there is no package for registry.terraform.io/hashicorp/aws … cached`
The `.terraform/` provider cache is missing (it's gitignored). Re-run
`terraform init` in that root.

### Data source returns nothing / "no matching …" (tag discovery fails)
Phase 2/3 can't find Phase 1's resources. Causes:
- Phase 1 not applied, or applied with a different `project` value → the `Project` tag
  won't match. Keep `project` identical across all three roots.
- You're in the wrong region. All roots must share `aws_region`/`availability_zone`.
Confirm the tags exist: `aws ec2 describe-subnets --filters Name=tag:Discovery,Values=range-subnet`.

### Data source finds **multiple** matches
A previous session's resources weren't torn down, so two collectors/subnets match.
The singular `aws_instance`/`aws_subnet` data source errors on >1. Tear down the stale
session (or terminate the orphaned instance) and retry.

### Router doesn't appear in `tailscale status`
- Bad/expired auth key → regenerate a reusable+ephemeral+pre-authorized key, re-apply.
- Advertised route not approved → approve `10.40.10.0/24` in the Tailscale admin console
  (or auto-approve via ACL).
- Check `/var/log/cloud-init-output.log` on the router for the `tailscale up` line.

### Can't reach attacker/collector over Tailscale
The router advertises **only** `10.40.10.0/24` (by design — never a detonation CIDR).
Confirm the route is approved and `source_dest_check=false` on the router (it is, in
`main.tf`). SG ingress on attacker/collector is ops-subnet-only, reached via the router's
masqueraded address.

### Attacker: SCRT tools missing / shell not zsh
First boot is long (clones SCRT, downloads many binaries). Check
`/var/log/attacker-bootstrap.log`. Individual tool download failures are logged as
`WARN` and don't abort the rest. If the whole clone failed, verify the box has egress
(it's on the ops subnet, which routes to the IGW) and that `scrt_repo_url` is reachable.

### Attacker: RDP/i3 won't log in
`attacker_rdp_password` was empty, so xrdp has no password to authenticate the `kali`
user. Re-apply with the password injected, or set it manually and `systemctl start xrdp`.
RDP is on `:3389`, reachable only via the router (no public IP).

### Wazuh dashboard won't load / indexer down
t4g.small (2 GB) OOMs the stack — the collector default is **t4g.medium**; don't shrink
it. Check `systemctl status wazuh-indexer wazuh-manager wazuh-dashboard` and
`/var/log/collector-bootstrap.log`. On a fresh collector reusing an existing volume, the
reinstall-over-existing-index path is the known-fragile bit (validate this).

### Windows victims: no telemetry / agents never enroll
Victims are air-gapped and can't fetch the agent. The install fails **soft** (forests
still come up). Fix: enable the package mirror in **both** Phase 1
(`enable_agent_package_mirror=true`, opens the det→collector port) and Phase 2 (collector
serves the installers), then re-launch the victims. Verify the mirror:
`curl http://<collector_ip>:8080/` from a victim.

### Trust does not form
Trust is created by a self-deleting scheduled task on **DC-B** that waits for DC-A's LDAP.
Give it 10–20 min (both DCs must finish promotion first). Diagnose on DC-B:
`C:\trust-task.log` and `C:\bootstrap-dc.log`. Confirm DC-B can resolve `forest-a.lab`
(conditional forwarder) and reach `<DC-A>:389`. **Fallback:** run the PowerShell snippet
in the [multi-forest README](../../_infra/terraform/aws/scenarios/multi-forest/README.md#the-trust-bootstrap-the-one-hard-part)
manually on DC-B.

### Windows won't activate
It activates against link-local KMS (`169.254.169.250/.251:1688`) with no internet route,
so a no-egress subnet is fine. If activation fails, confirm you used the **license-included**
Windows AMI (`windows_ami_owner=amazon`, Base image) — not a BYOL image.

### No DNS on a detonation host
Expected — VPC DNS is disabled (invariant #10). Victims use their DC as DNS; cross-forest
resolution is via conditional forwarders. Don't "fix" this by adding a route or re-enabling
VPC DNS.

### `infracost` shows a Windows host far too cheap
It priced Windows as Linux. Re-run with `--usage-file infracost-usage.yml`. The bare
number is a floor, not an estimate (ADR-0011 §2).

### Budget alarm didn't fire / no email
`budget_alert_emails` was empty at apply (no address is baked into the repo). Re-apply
with the address. AWS also requires confirming the budget email subscription once.

### `terraform destroy` on range-network refuses (volume)
The SIEM volume has `prevent_destroy` on purpose. To truly decommission the range, remove
that lifecycle block deliberately, then destroy — you will lose the detection index.

---

## Cost checkpoints

- **Standing:** ~$2.70/mo (Phase 1 only).
- **Per session:** ~$0.71/hr Linux-ish ops + scenario; a full multi-forest 8h session
  ≈ $2.86. Budget allows ~10 multi-forest or ~15 single-forest sessions/month.
- Run `/cost` before adding anything and after each session. Alarms fire at $15 / $24 / $30.
- The **top budget risk is "left it running"** — always complete [teardown](#session-teardown)
  and confirm the empty instance list.
