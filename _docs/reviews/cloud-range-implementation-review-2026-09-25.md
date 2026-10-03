# Implementation review — AWS range (ADR-0011), pre-deployment

> **Date:** 2026-09-25
> **Trigger:** requested review before verifying Phase 0 / starting Phase 1.
> **Scope:** the three Terraform roots under `_infra/terraform/aws/` as built on branch
> `feat/cloud-native-aws-range` (`7891c75`), their bootstrap templates, and ADR-0011 /
> runbook / reference docs. Read-only: no `apply`, no state, no mutations.
> **Not** a periodic posture review (`/lab-review` series) — nothing is deployed yet.
> **Method:** code read + claim-by-claim verification against current AWS, Wazuh, and
> PowerShell documentation (sources at the end). Provider pin `hashicorp/aws = 6.66.0`
> confirmed as the current latest.

## Executive summary

The design is sound and the implementation is unusually disciplined for a lab: the
isolation invariants really are declarative attributes, the tag-discovery decision is
right and correctly implemented on both sides, and the cost reasoning is honest about its
own blind spots. The two load-bearing AWS-specific claims in ADR-0011 hold up: AWS
documents that the Amazon DNS resolver **cannot** be filtered by security groups or
NACLs, which justifies §4(b); and Amazon Time Sync at `169.254.169.123` needs no SG/NACL
rules, so Kerberos clock skew across the forest trust is a non-issue.

Three things stand between this and a successful Phase 2/3:

1. **You cannot get a shell on the collector or the attacker.** No `key_name` on any
   instance, and only the router runs Tailscale. The runbook's own verification steps
   ("SSH to its private IP", "watch `/var/log/collector-bootstrap.log`") are not
   executable as built.
2. **The collector's bootstrap probably aborts before installing Wazuh**, because it
   races the EBS attachment and fails hard instead of waiting — and per (1) you won't be
   able to see why.
3. **Edited bootstrap scripts silently do nothing on re-apply** (`user_data_replace_on_change`
   is unset), which is the worst possible property for a range whose *entire*
   configuration mechanism is user data, and which you've already flagged as
   needing first-boot debugging.

Everything else is hardening, secrets hygiene, one genuine isolation gap at scale, and
doc drift. Findings are tiered below with severity, evidence, and a fix. Nothing here
requires re-architecting; the highest-value items are one-line to one-block changes.

| Tier | ID | Severity | Summary |
| --- | --- | --- | --- |
| Blocker | B-1 | **High** | No SSH key / tailnet presence → no shell on attacker or collector — **fixed 2026-09-26** |
| Blocker | B-2 | **High** | Collector `user_data` races the volume attachment and aborts — **fixed 2026-09-26** |
| Blocker | B-3 | Med-High | `user_data` edits never re-run (no `user_data_replace_on_change`) — **fixed 2026-09-26** |
| Blocker | B-4 | Medium | DC/member scripts can abort on the password reset, before trust/join — **fixed 2026-09-26** |
| Safety | S-1 | **High** (verify) | Invariant 10 (VPC DNS off) is asserted, never tested |
| Safety | S-2 | Medium | Shared victim SG + victim↔victim allow-all = no inter-scenario isolation |
| Safety | S-3 | Low-Med | Victim→attacker ICMP blocked by the NACL (ping/`-PE` fail) — **fixed 2026-09-26** |
| Safety | S-4 | Medium | Windows KMS activation likely blocked; "no SG needed" claim unsupported |
| Safety | S-5 | Low-Med | §6 requires *logged* egress exceptions; no flow logs anywhere |
| Safety | S-6 | Low | VPC default security group unmanaged and permissive (CIS/FSBP EC2.2) — **fixed 2026-09-26** |
| Safety | S-7 | Low | Free account-level guardrails not used (IMDS defaults, EBS defaults) — **fixed 2026-09-26**, out of band by design |
| Secrets | K-1 | Med-High | Tailscale key + RDP password land in world-readable instance logs — **fixed 2026-09-26** |
| Secrets | K-2 | Medium | Empty `budget_alert_emails` silently ships an alarm-less budget — **fixed 2026-09-26** |
| Cost | C-1 | Medium | Collector below Wazuh's documented floor; Wazuh pinned 5 minors back — **fixed 2026-09-26** |
| Cost | C-2 | Low | ADR cost tables still pre-`t4g.medium`; three different session totals — **fixed 2026-09-26** |
| Docs | D-1 | Low | "Offline-clean" overstates it: no `init`, no tflint AWS ruleset — **fixed 2026-09-26** |
| Docs | D-2 | Low | Runbook instructs steps the code can't support — **fixed 2026-09-26** |
| Docs | D-3 | Low | Assorted robustness nits (AMI owner, NACL numbering, quoting, …) — **fixed 2026-09-26** |
| Harness | H-1 | **High** | `guard-mutations.sh` PreToolUse hook fails open whenever cwd drifts — **patched 2026-09-25; verified in force 2026-09-26** |
| Harness | H-2 | Low | PostToolUse `fmt`/`yamllint` hook is a silent no-op (bad env var) — **patched 2026-09-25; live 2026-09-26** |

---

## Status — what has changed since this review was written

**2026-09-26.** Acting on the operator's decisions, the four blockers and both secrets
findings are fixed, and a repo-wide terminology change was made. Everything not listed
here is unchanged and still open.

| Item | Decision | State |
| --- | --- | --- |
| B-1 | Add an SSH key rather than putting Tailscale on every host; keypair sourced from 1Password | **Fixed** |
| B-2 | Wait for the attach (the alternatives are discussed in the finding) | **Fixed** |
| B-3 | Apply as proposed | **Fixed** |
| B-4 | Apply as proposed | **Fixed** |
| K-1 | Keep `set -x`, guard the secret regions; key to a 0600 tmpfs file | **Fixed** |
| K-2 | Make `budget_alert_emails` required and validated | **Fixed** |
| S-6 | Adopt and empty the VPC default SG | **Fixed** |
| S-7 | Account baseline set out of band, NOT Terraform-owned; range verifies only | **Fixed** |
| S-3 | NACL egress rule 320 for ICMP; ephemeral floor left at 1024 by choice | **Fixed** |
| C-1 | Wazuh 4.14, heap pinned, swapfile; t4g.medium kept | **Fixed** |
| C-2 | ADR cost tables recomputed; a real over-ceiling claim corrected | **Fixed** |
| D-1 | `.tflint.hcl` + AWS ruleset; lint no longer reports a skip as a pass | **Fixed** |
| D-2 | Phase 1 checkpoint gained default-SG, budget and AMI checks | **Fixed** |
| D-3 | Quoting, depends_on, volume status filter, NACL guards, AMI owner alias | **Fixed** |
| Terminology | "detonation" → "victim" across code and docs | **Done** |

### Terminology change

`detonation` is gone from the live tree: the operator is not detonating samples, so the
segments are **victim** subnets and the hosts are **victim hosts**. This renamed Terraform
identifiers as well as prose, including three cross-root discovery contracts:

| Was | Now |
| --- | --- |
| `var.detonation_subnets`, keys `det00`/`det01` | `var.victim_subnets`, keys `victim00`/`victim01` |
| `aws_subnet.detonation`, `aws_route_table.detonation`, `aws_network_acl.detonation`, `aws_security_group.detonation` | same names with `victim` |
| tag `SubnetRole = "detonation"` | tag `SubnetRole = "victim"` |
| tag `SGRole = "detonation"` | tag `SGRole = "victim"` |
| tag `SubnetName = "det00"/"det01"` | tag `SubnetName = "victim00"/"victim01"` |
| output `detonation_subnet_ids`, `security_group_ids.detonation` | `victim_subnet_ids`, `security_group_ids.victim` |

The three tag changes are the ones that matter: `SGRole` and `SubnetName` are read by
`ops-tier/data.tf` and `scenarios/multi-forest/data.tf`, and both sides were changed
together. Nothing is deployed, so no `terraform state mv` was needed — **if any root had
already been applied, these renames would destroy and recreate the VPC, subnets, route
table, NACL and SGs**, so re-check before applying if that assumption is ever wrong.

`_docs/decisions/0009-security-lab-segmentation.md` was deliberately **not** touched: it
is the superseded Proxmox-era ADR and a historical record, and its `det_isolation` is a
real identifier in archived code.

### Verification run after the changes

| Check | Result |
| --- | --- |
| `terraform fmt -recursive` (3 roots) | clean |
| `terraform init -backend=false` + `validate` (3 roots) | **Success** — first time `validate` has run against the real provider schema (closes the D-1 gap for this change set) |
| `tflint` (3 roots) | clean |
| `templatefile()` render of all four bootstrap templates | renders; no missing template vars |
| `bash -n` on the rendered collector script | clean |
| Volume wait loop against a stubbed `lsblk` | resolves `/dev/nvme1n1` by serial; exits 1 after the timeout when absent |
| `set -x` leak test, old vs new attacker script | old traced the password 3×; new traces it 0× |
| Rendered router cloud-config | no key material in any `runcmd`; key file `0600 root:root`, removed after `tailscale up` |
| `budget_alert_emails` validation, 4 cases | empty and both malformed inputs rejected; valid accepted |
| Live `op://Security/security_labs/public key` through `op run` | resolves; passes the `ssh_public_key` validation |

Not verified: anything requiring a real boot. `infracost` was not re-run — no billable
resource changed (a key pair and an SG rule are free; `user_data_replace_on_change`
changes replacement behaviour, not the bill).

---

## Blockers — will bite during Phase 2/3

### B-1 · No shell access to the attacker or the collector — **High**

**Evidence.** `grep -rn key_name _infra/terraform/aws` returns nothing: no `key_name` on
any of the seven instances, and no `aws_key_pair` resource. Only the router joins the
tailnet (`router.cloud-init.yaml.tftpl:16`, `tailscale up … --ssh`); the attacker and
collector are reached *through* the router's advertised subnet route, so they are not
tailnet nodes and have no `tailscale ssh`. Both AMIs (Kali, Ubuntu cloud) ship with
`PasswordAuthentication no` and no user password. `attacker_rdp_password` sets the `kali`
unix password for **xrdp only** (`attacker-scrt.sh.tftpl:106-113`).

**Failure scenario.** Phase 2 completes, the Wazuh dashboard doesn't load. The runbook
says "Watch `/var/log/collector-bootstrap.log`" — there is no way in. The collector has
no GUI, no password, no key, no SSM (deliberately, ADR §6), and no instance profile
(deliberately, invariant 5). It is a black box. Same for the attacker if `xrdp` fails to
start or the SCRT build leaves the box in a bad state.

**Fix (pick one).**
- *Minimal:* add a `key_name` variable to `ops-tier` and an `aws_key_pair` fed from a
  public key (private half in 1Password). $0.
- *Better, and more faithful to invariant 3:* install Tailscale on the attacker and
  collector too, with their own ephemeral keys. They're on the routed ops subnet so they
  can reach the coordination server. This makes "entry is via Tailscale" literal rather
  than dependent on subnet-route masquerading, gives each host `tailscale ssh`, and
  removes the attacker/collector SG's reliance on `ingress from ops CIDR`. Still $0 (free
  plan), still no public IP.

**Resolved 2026-09-26** — operator chose the SSH key over installing Tailscale everywhere.
`aws_key_pair.ops` in `ops-tier/main.tf`, driven by a new `ssh_public_key` variable (or
`ssh_key_name` to reuse an existing pair), with `key_name` on the router, attacker and
collector. The collector SG had **no** port-22 ingress at all, so a key alone would not
have been enough: `range-network/security-groups.tf` gains `collector_ssh`, TCP 22 from
the **ops CIDR only** — reachable solely through the subnet router, so `range-safety.md`
§3 is untouched and nothing is exposed to `0.0.0.0/0`. A `check` block warns at plan time
when no key is configured. `terraform output ssh` now prints the three ready-made commands
(`ssh ubuntu@…` / `ssh kali@…` / `ssh ubuntu@…`); the runbook checkpoint and the ops-tier
README were corrected to match.

**Revised the same day — the keypair is sourced from 1Password, no key material on the
host.** Item `security_labs` (category *SSH Key*) in the `Security` vault; the private
half never leaves 1Password and is served to `ssh` by its agent, and Terraform receives
only the public half via `TF_VAR_ssh_public_key="op://Security/security_labs/public key"`
under `op run --`. Deliberately **not** marked `sensitive` — it is a public key, and you
want it visible in plan output to confirm the right key landed.

Sourcing from 1Password introduces one new failure mode, so `ssh_public_key` gained a
`validation` block. Verified against the live item: the real reference resolves through
`op run` (`ssh-ed25519`, no comment field) and passes; a literal unresolved `op://…`
string, a `-----BEGIN OPENSSH PRIVATE KEY-----` block, and arbitrary text are all
rejected at plan time. The private-key case matters beyond ergonomics — passing it by
mistake would write a private key into local state in plaintext (`secrets.md`).

One host-side prerequisite, found while verifying and **not** changed automatically:
`~/.config/1Password/ssh/agent.toml` scopes the agent to the `Private` and `HomeLab`
vaults, so the `Security` key is not offered until a `[[ssh-keys]] vault = "Security"`
block is added. Without it the key is installed on the instances and `ssh` still fails —
documented in the runbook prerequisites and the ops-tier README.

### B-2 · Collector `user_data` races the EBS attachment and aborts — **High**

**Evidence.** `ops-tier/main.tf:131-139` creates `aws_volume_attachment.siem` *after*
`aws_instance.collector` (Terraform dependency). `collector-wazuh.sh.tftpl:24-28` probes
`/dev/sdf`, `/dev/nvme1n1`, `/dev/xvdf` **once** and then:

```sh
if [ -z "$DEV" ]; then echo "SIEM volume not found; aborting"; exit 1; fi
```

with `set -euxo pipefail` at the top.

**Failure scenario.** cloud-init runs user data within seconds of the instance reaching
`running`; the `AttachVolume` call is a separate API round-trip that Terraform only makes
after that. The probe finds no block device, the script exits 1, and **Wazuh is never
installed** — no manager, no indexer, no dashboard, no mirror. Combined with B-1 you
cannot diagnose it, and because of B-3 re-applying won't re-run the script either. Three
findings compound into "Phase 2 appears to succeed and the SIEM is simply absent".

**Fix.** Wait for the device instead of aborting, and resolve it by identity rather than
name — on Nitro (`t4g.*`) `/dev/sdf` is renamed and `nvme1n1` ordering is not guaranteed:

```sh
for i in $(seq 1 60); do
  DEV=$(lsblk -dno NAME,SERIAL | awk '$2 ~ /^vol/ && $2 != "'"$ROOT_SERIAL"'" {print "/dev/"$1; exit}')
  [ -n "$DEV" ] && break
  sleep 5
done
```

(or keep the candidate list but loop it with a 5-minute ceiling). Also worth adding
`aws_volume_attachment` to a `depends_on` narrative in the README so the ordering is
explicit to the next reader.

**Resolved 2026-09-26** — the probe is now a 5-minute wait loop that resolves the device
by **NVMe serial** (`lsblk -dno NAME,SERIAL`, matching the volume ID with dashes stripped)
and keeps path probing as the non-Nitro fallback; `siem_volume_id` is passed into the
template for that comparison. Unit-tested against a stubbed `lsblk`: picks `/dev/nvme1n1`
by serial, and still exits 1 with a clear message when the volume never appears.

**On the operator's question — is there another way to attach the volume?** Four
alternatives, none better here:

1. **`ebs_block_device` on the instance** — attaches at launch, so no race. But it
   *creates* a volume; it cannot adopt the existing `prevent_destroy`-protected one, and
   the persistent SIEM index is the whole point.
2. **Restore from a snapshot into a launch-time block device** — also race-free, but it
   turns "one durable volume" into "snapshot at teardown, restore at setup": more moving
   parts, snapshot storage cost, and a lost session if teardown skips the snapshot.
3. **Reverse the dependency** so the attachment exists before the instance — not
   expressible: `aws_volume_attachment` needs an `instance_id`, so the instance is always
   created first. The gap is inherent to attaching an existing volume.
4. **A systemd unit or cloud-init `bootcmd` that waits** — the same wait, just relocated.
   Worth doing if the mount ever needs to survive reboots independently of `user_data`;
   `nofail` in `/etc/fstab` already covers the common case.

So the wait loop is the right primitive. What made the original a blocker was not the
race but failing **hard and silently** on it: `exit 1` under `set -e`, with no shell to
see it (B-1) and no re-run on fix (B-3).

### B-3 · `user_data` changes never take effect — Med-High

**Evidence.** `user_data_replace_on_change` appears nowhere. The AWS provider default is
`false`, which means a changed `user_data` is an **in-place attribute update**: the
instance is not replaced and the script is not re-executed.

**Failure scenario.** You fix B-2 in `collector-wazuh.sh.tftpl`, run `apply`, Terraform
reports `1 to change`, and nothing on the box changes. You then debug the script instead
of the lifecycle. This is guaranteed to happen: the handoff notes explicitly list the
Wazuh install, the volume-state migration, the trust bootstrap, and the SCRT/i3 build as
"validate against real boot", i.e. you *will* be iterating on these files.

**Fix.** `user_data_replace_on_change = true` on all seven instances. These hosts are
ephemeral by design, so forced replacement is the correct semantic, not a cost.

**Resolved 2026-09-26** — `user_data_replace_on_change = true` on all seven instances
(three in `ops-tier`, four in `scenarios/multi-forest`).

### B-4 · DC/member scripts can abort on the password reset, before the trust or join — Medium

**Evidence.** `dc.ps1.tftpl:12-18` sets `$ErrorActionPreference = "Stop"` and then resets
the built-in Administrator password **unconditionally, outside** the promotion guard.
With `<persist>true</persist>` the whole script re-runs on every boot, and after promotion
`[ADSI]"WinNT://./Administrator"` resolves to the *domain* Administrator, now subject to
domain password policy. `member.ps1.tftpl:7-9` has the same shape, ahead of the domain
join.

**Failure scenario.** Any throw from `SetInfo()` — policy evaluation, or AD still settling
immediately after promotion — aborts the script *before* `Add-DnsServerConditionalForwarderZone`
and before the `BootstrapForestTrust` task is registered. Symptom: the trust silently
never forms, and `C:\bootstrap-dc.log` shows a password error, pointing you away from the
actual problem. On a member, it aborts before `Add-Computer`.

**Fix.** Run the password block only pre-promotion (`if (-not $adds.Installed)`) and wrap
it in `try/catch`. The runbook's Phase 0 password generator already avoids symbols for
templating safety — good — but complexity/policy rejection is a different failure and
still needs the guard.

---

## Safety / isolation

**Resolved 2026-09-26** — on the DC the password block moved inside
`if (-not $adds.Installed)`, so it runs only on the pre-promotion boot (the local account
becomes the domain Administrator at promotion and keeps the password), wrapped in
`try`/`catch`. On the member it stays early — you want a console password before the join
lands — but is likewise wrapped, so a throw can no longer abort the DNS configuration or
the domain join. Both log the failure via `Write-Output` into the transcript.

### S-1 · Invariant 10 is asserted but never tested — **High (verification gap)**

The premise is confirmed. AWS states plainly: *"You cannot filter traffic to or from the
Amazon DNS server using network ACLs or security groups"*, and the Route 53 Resolver
*"does not use the Internet Gateway, Security Groups, or network ACLs … DNS queries will
be resolved even if the VPC does not have an Internet Gateway"*. ADR §Context claim 2 is
correct, and disabling VPC DNS is the right structural answer on this budget.

**What is not established** is that `enable_dns_support = false` closes the channel at
*both* addresses. AWS's own description of the attribute says only that *"the Route 53
Resolver cannot resolve Amazon-provided **private** DNS hostnames"* — it does not state
that recursive resolution of public names at `169.254.169.253` is refused. Separately, the
docs note that `169.254.169.253` reachability is tied to AmazonProvidedDNS being the name
server in the DHCP option set (which you have replaced). The behaviour is very likely what
the ADR assumes, but this is the one exfiltration path that SG and NACL provably cannot
close, so assumption is not good enough.

**Fix — make it a Phase 1 gate.** After Phase 1 and the first victim-subnet host, before
any sample is run, from a victim host:

| Test | Required result |
| --- | --- |
| `nslookup example.com 10.40.0.2` | fail / timeout |
| `nslookup example.com 169.254.169.253` | fail / timeout |
| `nslookup example.com 1.1.1.1` | fail / timeout (no route) |
| `nslookup forest-b.lab <peer DC IP>` | **succeeds** (in-segment resolver) |

If either link-local query resolves, invariant 10 is not closed and the range is not
ready to run samples — the fallback is Route 53 Resolver DNS Firewall (billed per query) or
accepting the channel with query logging on.

**Also:** the "not logged" half of the rationale is overstated in both ADR §Context and
`range-safety.md` §10. Route 53 Resolver **query logging** exists and would log exactly
these queries, and DNS Firewall can filter them; both cost money, which is a fine reason
to reject them. Restate the argument as *"cannot be filtered by SG/NACL, and logging it
costs money we don't have"* — that's the true and stronger claim.

### S-2 · Concurrent scenarios are not isolated from each other — Medium

**Evidence.** One shared `victim` SG with self-referencing allow-all ingress *and*
egress (`security-groups.tf:153-179`), plus NACL rules `100+i` permitting **every**
victim CIDR to reach every other in full (`nacl.tf:20-48`). The scenario root attaches
that shared SG to all four victims (`scenarios/multi-forest/main.tf`, four occurrences of
`data.aws_security_group.victim.id`). `victim_subnets` is documented as growing to
`victimNN` for future scenarios.

**Failure scenario.** You run a live sample in a future `victim02` scenario while the AD
forests are still up in `victim00`/`victim01`. The sample has unrestricted L3/L4 access to both
domain controllers — it cross-contaminates a scenario you meant to keep clean, and poisons
the defensive baseline on the persistent SIEM volume (the one thing that *survives*
teardown). The blast radius of a victim is currently "every victim subnet in the
VPC", not "this scenario".

This is a design consequence of the ADR §4(c)/§7 trade-off, made deliberately to let a
cross-subnet forest trust work — but §7's reasoning only needs victim00↔victim01, not
all-to-all.

**Fix.** Treat the shared SG as the *trust* SG and scope it: have each scenario root
create its own SG for hosts that shouldn't be cross-scenario reachable, attaching the
shared one only where a trust requires it. Cheaper interim step: parameterise the NACL's
victim↔victim allowance to a variable list rather than `values(var.victim_subnets)`, and add
a rule to the runbook + `/lab-status` that two scenario roots being up simultaneously is a
flagged condition, not a normal one.

### S-3 · Victim→attacker ICMP is blocked by the NACL — Low-Medium

**Evidence.** NACLs are stateless. Victim egress toward ops permits only TCP telemetry
ports (rules 200+j), the optional mirror port (250), and TCP/UDP **1024–65535** (300/310).
There is no ICMP egress rule. The victim *SG* does allow it (allow-all to/from the
attacker SG), so this is a NACL-only asymmetry.

**Failure scenario.** Day one on the attacker box: `ping 10.40.50.10` times out even
though the host is up and RDP works. `nmap -PE` and default `nmap -sn` host discovery
report nothing alive. Second, subtler case: any tool using a **source port below 1024** —
`nmap --source-port 53`, a standard firewall-evasion drill you'd actually want to practise
here — gets no replies, because rule 300 starts at 1024. Both look like host problems, not
NACL problems.

**Fix.** Add an ICMP egress rule toward the ops CIDR (`protocol = "1"`, `from_port = -1`,
`to_port = -1`). For the source-port case, decide deliberately: widening rule 300 to
`0-65535` restores the drill but weakens the "a victim can't open a new connection to an
arbitrary ops service" property that is the whole point of the egress restriction — I'd
keep the 1024 floor and document the caveat in the reference doc's NACL table instead.

**Resolved 2026-09-26.** Victim NACL egress rule **320** permits ICMP to the ops CIDR
(`protocol = "1"`, `icmp_type = -1`, `icmp_code = -1`; the provider requires code `-1`
whenever type is `-1`). The rule locals gained `icmp_type`/`icmp_code` keys — `null` on
every non-ICMP entry, because a `concat` of objects must have a consistent type.

This does not widen victim-initiated reach. The NACL is stateless and cannot tell a reply
from a fresh packet, but the victim **SG** has no ICMP egress rule toward the attacker, so
echo replies ride SG statefulness and the SG stays the control — which is what invariant 11
asks for.

The finding's second half (ephemeral egress starting at 1024, so `nmap --source-port 53`
gets no reply) was **not** changed: lowering the floor would let a victim reach privileged
ops ports, which is a worse trade than losing one nmap flag. Documented instead, in the
NACL header comment, the reference doc, and troubleshooting.

Verified by evaluating `local.victim_nacl_egress`: seven rules, `320/1 icmp -1/-1` present.

### S-4 · Windows KMS activation is likely blocked, and the reference doc's claim is unsupported — Medium

**Evidence.** `_docs/reference/aws-range-reference.md` states for port 1688:
`instance → 169.254.169.250/.251 | **link-local (no SG/route)**`, and ADR §Context claim 1
says activation works "unmodified" in a no-egress subnet. The AWS statement that traffic
"cannot be filtered by SG or NACL" is made **specifically and only about the Amazon DNS
server** — it does not generalise to the other link-local services. AWS's activation-failure
guidance and the WorkSpaces port requirements both state that **outbound TCP 1688 to
`169.254.169.250` and `169.254.169.251` must be allowed**, and EC2Launch/EC2Config adds a
*route* for those addresses to the primary adapter. The victim SG has no egress rule
covering them; the victim NACL egress doesn't either.

Contrast — and this is the useful half: Amazon Time Sync at `169.254.169.123` **is**
documented as requiring no security group or network ACL changes. So the "AD clock skew in
a no-egress subnet" worry is genuinely a non-issue. The two link-local services behave
differently, and the docs treat them differently.

**Failure scenario.** DC-A/DC-B/WS-A/WS-B come up unactivated → activation-failure
notifications and the "Windows is not activated" watermark, then reduced functionality
after the grace period. For 8-hour sessions this is cosmetic-to-annoying rather than fatal
— but it falsifies the ADR's claim as an *unconditional* one, and the claim is load-bearing
for "Windows is first-class on AWS and not on Hetzner".

**Fix.** Verify on the first Windows boot (add to the Phase 3 checkpoint):
`Test-NetConnection 169.254.169.250 -Port 1688` → `TcpTestSucceeded : True`, and
`slmgr /dlv`. If it fails, add victim SG egress and NACL egress for
`tcp/1688 → 169.254.169.250/31`. Either way, correct the reference-doc row to *"requires
outbound 1688 permitted; link-local, so no IGW/NAT/off-VPC route"* — the interesting
property is "no internet needed", not "no rules needed".

### S-5 · The §6 egress exception is controlled but not logged — Low-Medium

**Evidence.** `range-safety.md` §6 requires a *"controlled, logged allow-list"*. The mirror
path is `python3 -m http.server` (`collector-wazuh.sh.tftpl:89`) — request lines go to the
collector's journal only. `grep -rn flow_log _infra/` returns nothing: there is no VPC Flow
Log anywhere, so there is no record of what a victim host *attempted*. FSBP/CIS
**EC2.6** expects flow logging on every VPC.

**Fix.** Flow logs on the two victim subnets with `traffic_type = "REJECT"` and short
retention. Vended-log delivery to CloudWatch Logs is $0.50/GB (tiered down above 10 TB);
REJECT-only records from a handful of hosts over an 8-hour session are a few MB — cents per
month, comfortably inside the ceiling. This pays twice over: a REJECT toward `0.0.0.0/0`
is *positive evidence* that the structural air-gap held (useful for `/lab-review`), and
network telemetry is exactly what the defensive half of the lab wants next to Sysmon.

### S-6 · The VPC default security group is unmanaged and permissive — Low (CIS/FSBP EC2.2)

**Evidence.** `grep -rn aws_default_security_group _infra/` → nothing. FSBP/CIS control
**EC2.2** requires the VPC default security group to allow no inbound *or outbound*
traffic; AWS's default permits all egress and intra-group ingress.

**Failure scenario.** Anything that lands in this VPC without an explicit SG — a
console-launched box for a quick test, a future scenario root that forgets
`vpc_security_group_ids` — inherits all-egress. In the ops subnet that is real, unfiltered
internet egress; in a victim subnet it is all-egress within the VPC.

**Fix.** An `aws_default_security_group` resource with **no** rule blocks locks it to
deny-all. This is the identical "fail closed" reasoning already applied to
`aws_default_route_table` in `routing.tf:42-49` — the default SG is the missing half.
`aws_default_network_acl` for the ops subnet is worth the same treatment. $0.

**Resolved 2026-09-26.** `aws_default_security_group.range` in `security-groups.tf`, with
no `ingress`/`egress` blocks, which is what makes the provider adopt the existing group and
revoke every rule. Placed beside the other SGs to mirror `aws_default_route_table` in
`routing.tf`, the same fail-closed pattern the finding pointed at.

Two caveats taken from the provider docs rather than assumed: Terraform *adopts* this group
rather than creating it, and **removing the resource later does not restore the original
rules** — it only stops managing an already-empty group. Both are noted in the code.

### S-7 · Free account-level guardrails not used — Low

The code gets these right per-resource; these make them un-forgettable for resources
Terraform didn't create. All free:

| Resource | Why here |
| --- | --- |
| `aws_ec2_instance_metadata_defaults` (`http_tokens = "required"`, `http_put_response_hop_limit = 1`) | Makes invariant 5 the account default so a hand-launched instance can't opt out |
| `aws_ebs_encryption_by_default` | The code sets `encrypted = true` on all 8 volumes; this makes it structural |
| `aws_ebs_snapshot_block_public_access` (`block-all-sharing`) | A lab that snapshots victim disks should be unable to publish one |

Also: **no IAM is defined anywhere in the repo.** Local state + `op run` is the entire
credential story, so the ADR or `secrets.md` should state explicitly that the apply
identity is a dedicated least-privilege IAM principal with MFA — not root access keys.
Worth a Phase 0 checkbox alongside `sts get-caller-identity` (check the ARN is not root).

---

**Resolved 2026-09-26, but not the way this finding proposed — the proposal was wrong.**

The first implementation put all three settings in `range-network` as Terraform resources.
The operator rejected it on the right grounds: the provider documents that removing
`aws_ebs_encryption_by_default` *disables* default encryption and removing
`aws_ebs_snapshot_block_public_access` *unblocks* public sharing. Owning them from a range
root therefore means a range teardown **weakens the account security baseline** — an
unacceptable trade for a security lab, and a lifetime error on my part: an account-lifetime
concern was placed inside the range's lifecycle.

"Verify instead of own" only partly rescues it, because only one of the three is
observable from Terraform:

| Setting | Reverts on destroy | Data source | Importable |
| --- | --- | --- | --- |
| `aws_ebs_encryption_by_default` | Yes (documented) | **Yes** | Yes |
| `aws_ebs_snapshot_block_public_access` | Yes (documented) | No | Yes |
| `aws_ec2_instance_metadata_defaults` | Undocumented; delete resets | No | **No** |

**What was actually done.** Terraform owns none of them. All three are set once out of
band and are Phase 0 prerequisites in the runbook, with verified commands:

```bash
aws ec2 enable-ebs-encryption-by-default
aws ec2 enable-snapshot-block-public-access --state block-all-sharing
aws ec2 modify-instance-metadata-defaults --http-tokens required --http-put-response-hop-limit 1
```

`range-network/account-baseline-check.tf` holds a `check` block with a scoped
`data "aws_ebs_encryption_by_default"`, so the range **reports** baseline drift on every
plan and has no power to cause it. A `check` warns rather than fails, which is right here:
the range is still safe without the account default, since every volume sets
`encrypted = true` and every instance sets its own `metadata_options` explicitly. The
other two settings have no data source and stay on the Phase 0 checklist.

Net effect: the account baseline can no longer be weakened by any `terraform destroy` in
this repo, at the cost of the two unobservable settings not being reproducible from the
repo. That trade was the operator's call and is the correct one — a lab must not compromise
the account it runs in.

**S-6 was left owned by Terraform**, and that asymmetry is deliberate: the VPC default
security group is VPC-scoped, and removing `aws_default_security_group` leaves the rules
*stripped* rather than restoring them. It fails safe, so the objection does not apply.

The finding's IAM half is a prerequisite, not code: these roots define no IAM, so the apply
identity *is* the range's privilege boundary. The runbook's Phase 0 table now requires
checking that `sts get-caller-identity` does not return a `:root` ARN.

Cost gate: `infracost breakdown` on `range-network` reports **$2.40/mo**, unchanged. The
default-SG adoption and the check block are both free.

## Secrets handling

### K-1 · Secrets land in world-readable instance logs; user data is not a secret store — Med-High

**Two concrete leaks:**

1. `attacker-scrt.sh.tftpl` sets `set -uxo pipefail` (line 9, `-x` trace on) and line 107
   is `echo "$KALI_USER:$RDP_PASSWORD" | chpasswd`. The trace **expands the password** into
   `/var/log/attacker-bootstrap.log` *and* `/var/log/cloud-init-output.log`, both mode
   0644. `secrets.md` is explicit: *"If a command would print a secret, redirect or suppress
   that output."*
2. `router.cloud-init.yaml.tftpl:16` passes `--authkey=${tailscale_auth_key}` in `runcmd`;
   cloud-init echoes runcmd lines to `cloud-init-output.log`, and the key is also visible in
   the process table while `tailscale up` runs.

**The broader point.** AWS is unambiguous: *"Although you can only access instance metadata
and user data from within the instance itself, the data is not protected by authentication
or cryptographic methods. Anyone who has direct access to the instance, and potentially any
software running on the instance, can view its metadata. Therefore, you should not store
sensitive data, such as passwords or long-lived encryption keys, as user data."* That covers
`domain_admin_password` and `safe_mode_password` in the Windows scripts. Note also that user
data is readable **from outside** the instance via `ec2:DescribeInstanceAttribute` — so the
`attacker_rdp_password` variable description ("lands in instance user_data (IMDSv2-only)")
overstates the protection: IMDSv2 + hop limit 1 does nothing about the API path.

**Fixes, in order of value-per-effort:**

1. **One line:** `set +x` around the `chpasswd` block (or write the password to a 0600 file,
   `chpasswd < file`, `shred -u file`). Removes a plaintext password from a world-readable
   log on a box you intend to hand to attacker tooling.
2. **Router:** write the key via `write_files` to `/run/ts.key` (0600) and use
   `tailscale up --auth-key=file:/run/ts.key`, then delete it. Keeps it out of the log and
   the process table. The key still sits in user data — which is acceptable *because* the
   runbook already generates it ephemeral + pre-authorized; make **short expiry** explicit
   in that Phase 0 step so the user-data copy is worthless by the next session.
3. **AD passwords:** with no instance profile and no SSM (both deliberate and correct),
   user data is genuinely the only channel. Keep it — but make it a *stated* property
   rather than an accident: add to ADR §6 that a compromised victim can read the domain
   admin password out of its own user data, and add "rotate `op://Security/range-ad` after
   any session where a victim was actually compromised" to the teardown checklist. In an
   attack lab that's usually the point; it just shouldn't be a surprise.

**Resolved 2026-09-26, and the finding understated the leak.** The review flagged only the
`chpasswd` line, but with `set -x` active the password reached the log **three times**:
the `RDP_PASSWORD=` assignment, the `[ -n "$RDP_PASSWORD" ]` test, and the `echo`.
Demonstrated by running both forms under `set -uxo pipefail` with a stubbed `chpasswd`:

```
OLD:  + RDP_PASSWORD=SUPERSECRET123
      + '[' -n SUPERSECRET123 ']'
      + echo kali:SUPERSECRET123          -> 3 occurrences
NEW:  + set +x
      + '[' yes = yes ']'
      + echo 'xrdp enabled; password set (value not traced).'   -> 0 occurrences
```

`set -x` is kept (first-boot debugging depends on it) and disabled only around the
assignment and the use region, with `unset RDP_PASSWORD` after. `echo` is a bash builtin,
so the value never reaches the process table either.

For the router, the Tailscale key moved out of `runcmd` into a `write_files` entry at
`/run/tailscale-authkey` (`0600`, `root:root`, tmpfs), consumed as
`tailscale up --auth-key=file:/run/tailscale-authkey` and deleted immediately after.
Verified from `tailscale up --help` on 1.102.3 rather than from memory: *"node
authorization key; if it begins with `file:`, then it's a path to a file containing the
authkey"*. The rendered cloud-config contains zero key material in any `runcmd` line.

**What this does NOT fix, and the docs now say so.** Both values still sit in the EC2
`user_data`, which is readable by any principal holding `ec2:DescribeInstanceAttribute` —
not merely "IMDSv2-only", as the `attacker_rdp_password` description claimed. Both
variable descriptions were corrected to state that plainly and to prescribe rotation.
Moving to a pre-hashed password (`chpasswd -e`) would remove the plaintext from user data
and state entirely; it changes the operator workflow, so it is left as a decision rather
than done unasked.

### K-2 · Empty `budget_alert_emails` silently ships an alarm-less budget — Medium

**Evidence.** `budgets.tf:22-31` — the `dynamic "notification"` block iterates an empty list
when `budget_alert_emails = []` (the default), producing a budget with **zero
notifications**. `cost-guardrails.md` rule 4 makes a budget *plus alarm* mandatory
"alongside the first resource, not later". The runbook's own troubleshooting entry
("*Budget alarm didn't fire / no email — `budget_alert_emails` was empty at apply*") is
evidence this is a live foot-gun, not a hypothetical.

**Fix.** Make it fail loudly rather than silently:

```hcl
variable "budget_alert_emails" {
  # …
  validation {
    condition     = length(var.budget_alert_emails) > 0
    error_message = "cost-guardrails.md rule 4: a budget alarm is mandatory. Pass TF_VAR_budget_alert_emails."
  }
}
```

Two additions worth making at the same time: AWS Budgets email subscriptions require a
one-time confirmation click, so add that as an explicit Phase 1 checkpoint line; and **AWS
Cost Anomaly Detection is free** — a second, independent signal for a $30 ceiling, at no
cost.

---

**Resolved 2026-09-26.** `budget_alert_emails` is now a **required** variable with no
default, carrying two `validation` blocks: non-empty, and every entry email-shaped. The
`dynamic "notification"` guard in `budgets.tf` is gone, so the alarm-less budget is no
longer expressible rather than merely discouraged.

Verified by evaluating the variable, since **`terraform validate` does not run variable
validation at all** (Terraform 1.15.3) — worth knowing, because it means `/lint` will never
catch this class of error and the guard fires at `plan`:

| Value | Result |
| --- | --- |
| `[]` | rejected, non-empty rule |
| `["notanemail"]` | rejected, email rule |
| `["good@example.com","bad@@example.com"]` | rejected, email rule catches the second |
| `["ops@example.com"]` | accepted |

Dropping the default means Phase 1 now needs the variable for `plan` as well as `apply`;
the runbook was updated to export it once. The runbook also now warns that AWS sends a
one-time subscription confirmation per address and **delivers no alarm until it is
accepted**, which is the remaining way to end up with a healthy-looking budget and no
notifications. Free AWS Cost Anomaly Detection remains unconfigured and is still worth
adding as a second signal.

## Cost

### C-1 · Collector is below Wazuh's documented floor, and Wazuh is pinned ~5 minors back — Medium

**Evidence.** `collector_instance_type = "t4g.medium"` (2 vCPU / 4 GiB). Wazuh's own
all-in-one sizing table starts at **4 vCPU / 8 GiB for 1–25 agents**. The install runs
`wazuh-install.sh -a -i` — `-i` is `--ignore-check`, i.e. precisely the flag that suppresses
the resource check that would object. `wazuh_version = "4.9"` while the current release is
**4.14**; `wazuh_agent_pkg = "4.9.0-1"` must move in lockstep, and the
`packages.wazuh.com/4.9/wazuh-install.sh` path is not guaranteed to persist indefinitely.
(ARM64 is fine — current Wazuh documents aarch64 support for server, indexer, *and*
dashboard, so t4g is not the problem.)

**Failure scenario.** The indexer's JVM heap defaults to roughly half of RAM; manager +
OpenSearch indexer + Node dashboard on 4 GiB, on a burstable instance with a 20% CPU
baseline, is an OOM and credit-starvation candidate. It fails in the one place you can't
reach (B-1), during the one path already flagged as fragile (volume-state reattach).

**Fix — cost-aware, in order.**
1. **$0:** pin the indexer heap explicitly (`-Xms1g -Xmx1g` in
   `/etc/wazuh-indexer/jvm.options`) and add 1–2 GiB of swap on the persistent volume. Do
   this regardless; the default heap sizing is the actual problem, not the instance.
2. **If it still OOMs:** `t4g.large` (8 GiB) is $0.0672/hr — **+$0.0336/hr over t4g.medium
   = +$0.27 per 8-hour session**, about $2.70 across ten sessions. That fits the ceiling
   with room, so it should not be treated as out of budget. Say so in the README, because
   the current note ("don't shrink it") implies t4g.medium is the ceiling when it's the
   floor.
3. Bump `wazuh_version` to a current 4.x and keep `wazuh_agent_pkg` consistent with it.

**Related, same file.** `serve_sysmon` fetches `Sysmon.zip` from `download.sysinternals.com`
and the config from `raw.githubusercontent.com` with `|| true` (lines 77-80). A silent
failure there means victims get no Sysmon *and* the victim-side Wazuh block is skipped by
its `try/catch` — the most valuable AD telemetry vanishes with no error anywhere. Log these
failures loudly (they're on the routed ops subnet, so a failure is a real signal, not an
expected air-gap artefact).

**Resolved 2026-09-26.** Checked against live Wazuh docs rather than the finding's
figures: current branch is **4.14** and the documented all-in-one floor for 1–25 agents is
**4 vCPU / 8 GiB / 50 GB**, so `t4g.medium` (2 vCPU / 4 GiB) is under on both counts.

| Change | Value |
| --- | --- |
| `wazuh_version` | `4.9` → `4.14` |
| `wazuh_agent_pkg` | `4.9.0-1` → `4.14.6-1`, with a `validation` enforcing the same branch as `wazuh_version` |
| `wazuh_indexer_heap` (new) | `1g`, written to `/etc/wazuh-indexer/jvm.options` as matching `-Xms`/`-Xmx` |
| Swapfile | 2 GB, created before the install |

Wazuh documents heap = half of system RAM, which would be `2g` here; `1g` is a deliberate
deviation because the manager and the Node-based dashboard share the same 4 GiB, and this
lab runs four agents rather than 25. The swapfile is the other deviation: OpenSearch
normally wants swap **off** for latency, which is right on real hardware and wrong on an
undersized box — a slow dashboard beats an OOM-killed indexer.

Both mitigations are $0. `t4g.large` (8 GiB) remains the escape hatch at **+$0.0336/hr,
+$0.27 per 8h session**, which would put a multi-forest session at ~$3.13 and still leave
~8 sessions/month inside the ceiling.

Verified: every package URL probed before pinning — `wazuh-agent-4.14.6-1.msi` returns 200
with a 5.9 MB body while `4.14.99-1` returns 403, so the pin is real and the 200s are
meaningful. The lockstep validation accepts `4.14`/`4.14.6-1`, rejects `4.14`/`4.9.0-1`,
`4.9`/`4.14.6-1`, and the near-miss `4.14`/`4.140.1-1`. Heap `sed` tested against a
realistic `jvm.options`; rendered script passes `bash -n`.

### C-2 · Cost figures have drifted between ADR, code, and runbook — Low

| Where | Says | Should be |
| --- | --- | --- |
| ADR §2 per-session table (line 136) | Collector `t4g.small` @ 0.0168 | `t4g.medium` @ 0.0336 |
| ADR §2 totals | $0.2091/hr, "$1.67 per 8h", "16 full sessions/month" | recompute at 0.0836/hr ops |
| ADR §3 Mermaid diagram (line 218) | "Collector / SIEM t4g.small" | t4g.medium |
| ADR §7 multi-forest total | $0.3401/hr → $2.72/8h | runbook + `aws/README.md` say $2.86/8h |
| `aws-range-reference.md:242` | lists t4g.small as "(lean collector)" | note it can't run the stack |
| runbook "Cost checkpoints" | "~$0.71/**hr** Linux-ish ops" | ~$0.71 per **8 h** (it's 0.084/hr) |

Pick the post-bump numbers and propagate them; the ops-tier README already has them right.
Everything else in the cost model checks out: gp3 vs gp2 at $0.08/$0.10, the $0.005/hr
public IPv4, the 730-hour infracost caveat, and the Windows-as-Linux blind spot with its
`infracost-usage.yml` remedy are all correct and well documented.

---

**Resolved 2026-09-26.** The drift was entirely in ADR-0011, which still priced the
collector as `t4g.small`. Recomputing from the right-size rather than patching numbers by
hand made the ADR agree with what the runbook and module READMEs already said:

| Figure | Was | Now |
| --- | --- | --- |
| §2 single-forest | 0.2091/hr → $1.67/8h | **0.2259/hr → $1.81/8h** |
| §7 multi-forest | 0.3401/hr → $2.72/8h | **0.3569/hr → $2.86/8h** |
| §7 multi-forest, spot members | 0.2653/hr → $2.12/8h | **0.2821/hr → $2.26/8h** |
| §3 diagram, §2 price table | collector `t4g.small` | `t4g.medium` (row added to the price table) |

**This surfaced a real budget error the finding did not mention.** Three documents claimed
**~10** multi-forest sessions/month, but 10 × $2.86 + $2.70 standing = **$31.30, over the
$30 ceiling**. Corrected to **9** (9 × $2.86 + $2.70 = $28.44) in the runbook, `aws/README`
and the scenario README. The single-forest figure moved 16 → **15** for the same reason
(16 would be $31.66). Spot-member sessions max at 12.

ADR-0011 is Accepted, so rather than silently rewriting it I added a dated **Amended**
line to its status block recording the right-size and its effect, and left the decision
itself untouched.

## Docs & process

### D-1 · "Offline-clean" is a weaker signal than it reads — Low

`terraform fmt -check -recursive _infra/` passes, and `tflint` returns clean on all three
roots. But:

- **No root is initialised** (`.terraform/` absent in all three), so `terraform validate`
  has not actually run against the provider schema in this working tree. The runbook's own
  troubleshooting anticipates this ("*no package for … hashicorp/aws … cached*").
- There is **no `.tflint.hcl`** and no `tflint-ruleset-aws` plugin — tflint 0.61.0 is
  running with only the bundled `terraform` ruleset. None of the AWS-specific checks ran:
  invalid instance types, invalid AMI/instance-type architecture pairings, deprecated
  arguments, missing required attributes.

For a repo whose safety thesis is *"every invariant becomes a declarative attribute that
tflint and review can check"* (ADR Consequences), the AWS ruleset is the checking half and
it isn't installed.

**Fix.** Add `.tflint.hcl` with `plugin "aws" { enabled = true, deep_check = false }`
(offline-safe, no API calls), and have `/lint` run `terraform init -backend=false` before
`validate` in each root.

**Resolved 2026-09-26, and the script defect was worse than the finding described.**
`iac-lint.sh` already ran `terraform init -backend=false` + `validate`; the roots simply
weren't initialised at review time, so every root hit the `• skip` branch. But a skip
printed a bullet and **never set `fail=1`**, so a run that validated nothing exited 0 and
printed the same "✅ IaC lint passed" as a run that validated everything. That is what made
"offline-clean" overstated, not the missing init.

Fixes:
- `.tflint.hcl` at the repo root: `terraform` recommended preset plus the **AWS ruleset
  pinned to 0.49.0** (current release, confirmed via the GitHub releases API), with
  `deep_check = false` since it would call the AWS API.
- The script passes `--config` explicitly, because tflint only reads `.tflint.hcl` from its
  working directory and the script lints each root from inside it.
- Skips are counted and reported: the result line now distinguishes
  `✅ passed (fmt + validate + tflint, incl. the AWS ruleset)` from
  `⚠️ passed what it could, but SKIPPED n check(s) — a skip is not a pass`, with the
  commands to fix it. Exit code still 0 for a skip, so CI ergonomics are unchanged.

Verified: the AWS ruleset installed and ran clean across all three roots — the first time
any AWS-specific rule has executed on this code. Skip reporting tested with a stub tflint
that fails with a plugin error: 3 skips, warning emitted, exit 0.

### D-2 · The runbook instructs steps the code can't support — Low

- Phase 2 checkpoint: "**SSH** to its private IP over Tailscale" and "watch
  `/var/log/collector-bootstrap.log`" — blocked by B-1.
- `aws-range-reference.md` ports table claims SSH/RDP on 22/3389 to attacker **and
  collector** — the collector has neither an SSH key nor a GUI.
- Phase 3 says "≈ $2.86 / 8h" against ADR §7's $2.72 (C-2).

**Additions worth making to Phase 1's checkpoint** while you're there: the S-1 DNS tests
(the single most important pre-victim gate), a default-SG check (S-6), and "confirm the
AWS Budgets email subscription" (K-2).

**Resolved 2026-09-26.** Most of this finding was already closed as a side effect of the
blockers: SSH to the attacker and collector works (B-1, plus the collector's missing port-22
rule), and the $2.86-vs-$2.72 split was reconciled in C-2. What remained was the Phase 1
checkpoint, which now also verifies:

- the VPC default security group has empty ingress **and** egress (FSBP/CIS EC2.2);
- the budget reports 4 notifications, with a reminder that the AWS confirmation email must
  be accepted or no alarm is delivered;
- the Kali AMI actually resolves, via a `describe-images` one-liner.

The invariant-10 DNS tests are referenced rather than duplicated: they need a victim host,
so they live on the status page as the Phase 1→2 gate.

### D-3 · Robustness nits — Low

- **`kali_ami_owner = "679593333241"`** is the generic **AWS Marketplace** owner account,
  not a Kali-specific publisher account (Kali's own AWS docs publish no owner ID; they just
  say "search for kali in Marketplace AMIs"). It works because the
  `kali-last-snapshot-amd64-*` name filter disambiguates, but `owners = ["aws-marketplace"]`
  plus a `product-code` filter is the more honest form. The variable description already
  says "verify against the Marketplace listing" — do that as part of Phase 0, since you're
  subscribing anyway.
- **NACL rule numbers are derived arithmetic with no guard:** `100 + i` per victim CIDR,
  `200 + j` per telemetry port, then hard-coded 250 (mirror), 300/310 (ephemeral). Two
  subnets and two ports is fine, but 50 telemetry ports would collide with 250 and 100
  victim subnets with the 200 block, and `for_each` keyed on `rule_no` would then throw
  a duplicate-key error rather than anything legible. Add `validation` blocks bounding
  `length(var.victim_subnets)` and `length(var.telemetry_ports)`.
- **Unquoted IP interpolation in PowerShell:**
  `Add-DnsServerConditionalForwarderZone … -MasterServers ${peer_dc_ip}`,
  `Set-DnsClientServerAddress … -ServerAddresses ${dc_ip}`,
  `Test-NetConnection -ComputerName ${dc_ip}`. PowerShell coerces these bare tokens
  correctly today, but quoting (`"${dc_ip}"`) costs nothing and removes a parser dependency
  from the only configuration channel you have. (`Test-NetConnection` itself is correct —
  `NetTCPIP` module, `-InformationLevel Quiet` returns a boolean, so both wait loops are
  sound.)
- **`data "aws_ebs_volume" "siem"`** has `most_recent = true` but no `status` filter. If a
  previous collector wasn't destroyed, the volume is `in-use` and the attachment fails with
  a runtime error; a `filter { name = "status", values = ["available"] }` turns it into a
  clear plan-time failure instead.
- **`aws_eip.router`** has a redundant `depends_on = [aws_instance.router]`; the `instance`
  argument already establishes it.
- **The Wazuh reattach fragility has a specific cause worth naming** in the ops-tier README
  so the eventual fix is scoped rather than rediscovered: the bind-mount restore lays the
  *old* `/var/ossec/etc` (including SSL material) over a *fresh* install's, while
  `/etc/wazuh-indexer/certs` and the indexer's cluster UUID are **not** on the persistent
  volume. That mismatch — not the data itself — is what will break the "existing volume,
  fresh collector" path. Persist the indexer certs too, or generate them deterministically.
- **`enable_wazuh_agents = true`** makes `data.aws_instance.collector` a hard plan-time
  dependency on ops-tier being up; the failure is an opaque "no matching EC2 Instance
  found". Add a `precondition` whose message names Phase 2, or flip the default to false.

---

**Resolved 2026-09-26.** Applied:

| Nit | Change |
| --- | --- |
| Unquoted PowerShell IP interpolation | `-ServerAddresses`, `-ComputerName`, `-MasterServers` now quoted. Worked by coercion before; quoting removes the coercion dependency. |
| Redundant `depends_on` on `aws_eip.router` | Removed — `instance = aws_instance.router.id` already creates the edge. |
| `data "aws_ebs_volume" "siem"` had no status filter | Added `status = ["available", "in-use"]`. **`in-use` has to stay**: on a re-apply the volume is still attached to the outgoing collector, so filtering `available` alone would break exactly the path B-3 makes common. Excludes `creating`/`deleting`/`error`, which `most_recent` could otherwise pick. |
| Unguarded NACL rule arithmetic | `validation` on `victim_subnets` (≤ 99, so `100+i` stays below rule 200) and on `telemetry_ports` (≤ 49, so `200+j` stays below the mirror's 250), plus a port-range check. Both tested: they fire, and the defaults pass. |
| `kali_ami_owner = "679593333241"` | Now the `aws-marketplace` **owner alias**. The finding was right that this is not an Offensive Security account, but incomplete: Marketplace product AMIs *are* owned by that account, so the numeric value was probably correct — just opaque. The alias is self-documenting and the description says so. |

**Not verified, and flagged rather than asserted:** no AWS credentials are available in this
environment (`op run -- aws ec2 describe-images` returns `NoCredentials`), so I could not
confirm which account actually owns the Kali AMI. That is why the fix is a readable alias
plus a Phase 0 `describe-images` check, instead of a claim about the owner.

The remaining two nits are documentation, already in place: the Wazuh reattach fragility is
called out in the collector script header and in troubleshooting, and `enable_wazuh_agents`
creating a hard ordering dependency on `ops-tier` is stated in the scenario's prerequisites.

## Harness

> **Status: both patched in `.claude/settings.json` on 2026-09-25** (verified from a drifted
> cwd — see the verification block in H-1). Claude Code snapshots hooks at session start, so
> **the fix is not live in the session that made it** — restart, or `/hooks` to review and
> load, before relying on the guard.

### H-1 · The `guard-mutations.sh` PreToolUse hook fails open whenever the shell cwd drifts — **High**

**Exact symptom.** The hook exits **127** with
`bash: line 1: _hack/scripts/guard-mutations.sh: No such file or directory`.

**Cause — verified, not inferred.** `.claude/settings.json` registers the hook as a bare
**relative** path:

```json
"command": "_hack/scripts/guard-mutations.sh"
```

Claude Code runs a command hook **in the current working directory at the time of
invocation** (it's the `cwd` field of the hook's own JSON input). The Bash tool's cwd
persists across calls, so any `cd` into a subdirectory — which is the normal way to work in
this repo, `cd _infra/terraform/aws/range-network && terraform validate` — permanently
moves it, and the relative path stops resolving. Reproduced directly:

| cwd | Result |
| --- | --- |
| repo root | `BLOCKED by guard-mutations.sh: terraform/tofu state mutation` — exit **2** ✅ |
| `_infra/terraform/aws/range-network` | `No such file or directory` — exit **127** ❌ |

The script itself is fine: executable (`-rwxr-xr-x`), `jq` present, and the matching logic
correctly blocks `terraform apply` with exit 2 when it can be found at all.

**Why this is High, not cosmetic.** Per the hooks contract, **exit 2 is the only exit code
that blocks.** Any other nonzero exit with empty/plain-text stdout is a *non-blocking*
error: the transcript shows a `hook error` notice and **the tool call proceeds through
normal permission flow.** So this isn't a noisy annoyance — the guard is **failing open**
exactly when it's most likely to be needed, because the cwd that breaks it (a Terraform
root) is the cwd from which an `apply` would be run. The mechanical enforcement that
CLAUDE.md and `terraform.md` both lean on ("the hook enforces this mechanically") is not
currently in force. The prior session's note — "keep the shell cwd at the repo root or it
fails to resolve" — described the trigger but treated it as an operating constraint; it's a
one-line config bug, and the workaround silently degrades a safety control.

**Fix.** Use the `CLAUDE_PROJECT_DIR` placeholder, which is the documented, recommended way
to reference a project script from a hook — it points at the project root the session
started in and is immune to cwd drift:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/_hack/scripts/guard-mutations.sh"
        }
      ]
    }
  ]
}
```

(The docs prefer *exec form* — `"command": "${CLAUDE_PROJECT_DIR}/_hack/scripts/guard-mutations.sh", "args": []` — for any hook referencing a path placeholder; in shell form the
placeholder must be double-quoted, as above.)

**Verified after the change** (run from `_infra/terraform/aws/range-network`, i.e. the cwd
that used to break it):

| Payload | Exit | Expected |
| --- | --- | --- |
| `terraform apply` | **2** — `BLOCKED … state mutation` | 2 ✅ |
| `cd _infra && terraform validate` | **0** | 0 ✅ |
| `op run -- terraform destroy` | **2** | 2 ✅ |

**Hardening worth considering while you're in there:** the script's contract comment says
"fail-open on parse error so a malformed payload never wedges the session", which is the
right call for *parse* failures — but it means a missing `jq`, a non-executable bit, or a
bad path all also fail open indistinguishably. Since this guard is the mechanical half of a
safety rule, consider having it `block` (exit 2) when `jq` is absent, so the failure mode is
"you can't run Bash" rather than "the guard is off and you won't notice".

**Confirmed in force, 2026-09-26.** The patch is live: the guard blocked a Bash call
during the B-1..B-4 work. It was a **false positive** — the command was a Python heredoc
whose *documentation text* contained the words for a Terraform state mutation, not a
command. Worth recording because it tells you two useful things:

- The guard matches on the whole command string and cannot tell a token inside a quoted
  heredoc from a real invocation. It therefore blocks some legitimate work, notably
  **editing the runbook**, whose apply commands are the thing being documented. The
  workaround is to write the script to a file and execute the file.
- The failure direction is now **fail-closed**, which is the correct trade. Do not "fix"
  the false positive by loosening the match; if it becomes annoying, narrow it by ignoring
  matches that appear inside heredoc bodies, or keep using the write-then-run pattern.

### H-2 · The PostToolUse `fmt`/`yamllint` hook is a silent no-op — Low

**Evidence.** The `Edit|Write` PostToolUse hook is:

```
if [[ $CLAUDE_FILE_PATH == *.tf ]]; then terraform fmt "$CLAUDE_FILE_PATH" …
if [[ $CLAUDE_FILE_PATH == *.yaml || $CLAUDE_FILE_PATH == *.yml ]]; then yamllint "$CLAUDE_FILE_PATH"; fi
```

`CLAUDE_FILE_PATH` is **not a Claude Code environment variable.** The documented set is
`CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_EFFORT` (plus the
remote indicators); per-file information reaches a hook through the **stdin JSON**, as
`tool_input.file_path`. The variable expands empty, both `[[ ]]` tests are false, and the
hook exits 0 having done nothing — which is why it never appears to run. This is also why
`documentation.md`'s claim that "cloud-init YAML is linted by the PostToolUse yamllint hook
on save" has not been true in practice.

**Fix.** Read the path from stdin:

```json
{
  "type": "command",
  "command": "f=$(jq -r '.tool_input.file_path // empty'); case \"$f\" in *.tf) terraform fmt \"$f\" >/dev/null 2>&1 || true ;; *.yaml|*.yml) yamllint \"$f\" ;; esac"
}
```

Low severity — it's a convenience, not a control — but it's the same class of bug as H-1
(a hook silently not running), and it's worth fixing in the same pass so the `/lint`
guarantee in `documentation.md` is real.

---

## What's right — worth protecting

Stated explicitly so none of it gets "simplified" later:

- **Tag-based cross-root discovery instead of `terraform_remote_state`**, with the security
  rationale documented at the point of use. Correct decision, correctly implemented on both
  sides, and the tag vocabulary (`Discovery` / `SubnetName` / `SGRole` / `Project`) is
  coherent.
- **`aws_default_route_table` locked to local-only** so an unassociated subnet fails closed.
  This is good instinct — S-6 just extends the same instinct to the default SG.
- **Directional controls expressed as SG *references*, not CIDRs** — collector ingress from
  the victim SG, and *no* collector→victim rule at all. Referencing SG IDs is the
  only way to make "telemetry is one-way" actually true, and it's done right.
- **IMDSv2 required + hop limit 1 + no instance profile on all seven instances**, with
  `encrypted = true` and explicit `gp3` on every volume. No IPv6 CIDR on the VPC, so there
  is no accidental IPv6 egress path. `associate_public_ip_address = false` everywhere except
  the single deliberate EIP.
- **`prevent_destroy` on the SIEM volume**, single-AZ placement, and the honest framing of
  the ops↔victim degradation as rule-based rather than pretending it's structural.
- **The `infracost-usage.yml` Windows override**, and documenting infracost's 730-hour and
  Windows-as-Linux blind spots in the rules file rather than just working around them.
- **Amazon Time Sync needs no SG/NACL rules** (AWS documents this explicitly) — so the
  no-egress AD lab has no Kerberos clock-skew problem. Genuinely one less thing.

---

## Suggested order before Phase 1

0. ~~**Restart the session** so the H-1 hook patch is loaded.~~ **Done** — the guard is
   in force (it correctly blocked a call on 2026-09-26).
1. ~~**B-1, B-2, B-3**~~ and ~~**B-4**~~ — **done 2026-09-26**, see *Status* above.
2. ~~**K-1 and K-2**~~ — **done 2026-09-26**, both rule violations closed
   (`secrets.md`, `cost-guardrails.md` rule 4).
3. ~~**S-6 and S-7**~~ — **done 2026-09-26**, free account/VPC guardrails.
4. **Apply Phase 1**, then run the **S-1 DNS tests** as a hard gate. No sample runs until
   those four results are as required.
5. **Phase 2/3**, treating **S-4** (`Test-NetConnection 169.254.169.250 -Port 1688`) and
   **B-4** as first-boot verification items.
6. **S-3** (ICMP rule), **C-1** (heap pinning + Wazuh version bump), then the **C-2 / D-1 /
   D-2** doc and lint reconciliation.

**S-2** is the one item that is design work rather than a fix — worth deciding before a
second scenario exists, but it does not block the multi-forest deploy, since victim00↔victim01 is
exactly what §7 wants.

---

## Sources

AWS documentation:
- [Understanding Amazon DNS (Route 53 Resolver; "cannot filter … using network ACLs or security groups"; link-local quota)](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html)
- [DNS attributes for your VPC (`enableDnsSupport` / `enableDnsHostnames` semantics)](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html)
- [Filter DNS traffic using Route 53 Resolver DNS Firewall](https://docs.aws.amazon.com/vpc/latest/userguide/resolver-dns-firewall.html)
- [Use instance metadata to manage your EC2 instance (the user-data sensitive-data warning)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html)
- [Set the time reference on your EC2 instance (Amazon Time Sync needs no SG/NACL rules)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configure-ec2-ntp.html)
- [Resolve activation failure on Amazon EC2 Windows instances (outbound 1688 to 169.254.169.250/.251)](https://repost.aws/knowledge-center/windows-activation-fails)
- [IP address and port requirements for WorkSpaces (TCP 1688 to the KMS link-local addresses)](https://docs.aws.amazon.com/workspaces/latest/adminguide/workspaces-port-requirements.html)
- [EC2Config service (adds the route for 169.254.169.250/.251/.254)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2config-service.html)
- [Security Hub CSPM controls for Amazon EC2 (EC2.2 default security group, EC2.6 VPC flow logging)](https://docs.aws.amazon.com/securityhub/latest/userguide/ec2-controls.html)
- [Security best practices for your VPC](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [CloudWatch pricing (vended logs: $0.50/GB to 10 TB)](https://aws.amazon.com/cloudwatch/pricing/)

Claude Code:
- [Hooks reference (`CLAUDE_PROJECT_DIR`, hook cwd, exit-code semantics, exec vs shell form)](https://code.claude.com/docs/en/hooks)

Terraform / vendor:
- [`aws_ec2_instance_metadata_defaults`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_metadata_defaults)
- [Wazuh quickstart — all-in-one hardware requirements, current 4.14](https://documentation.wazuh.com/current/quickstart.html)
- [Wazuh indexer installation — aarch64/ARM64 support](https://documentation.wazuh.com/current/installation-guide/wazuh-indexer/index.html)
- [`Test-NetConnection` (NetTCPIP)](https://learn.microsoft.com/en-us/powershell/module/nettcpip/test-netconnection)
- [Kali Linux AWS documentation](https://www.kali.org/docs/cloud/aws/)
