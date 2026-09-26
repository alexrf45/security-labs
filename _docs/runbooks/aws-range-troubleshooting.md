# Troubleshoot the AWS range

Symptom-first fixes for the three Terraform roots under `_infra/terraform/aws/`. For the
ordered deploy itself see [Deploy the AWS range](aws-range-deployment.md); for current
progress see the [deployment status](aws-range-deployment-status.md).

> **Internal document — contains real lab values.** Before changing anything in range
> networking, re-read [`range-safety.md`](../../.claude/rules/range-safety.md): several
> symptoms below are the isolation invariants working as designed, and "fixing" them
> breaks the range.

## Terraform

**`interactive IO not available`**: bare `terraform`. Wrap in `op run --`; only `validate`
and `fmt` work without it.

**`no package for … hashicorp/aws … cached`**: the gitignored `.terraform/` cache is
missing. Re-run `terraform init`.

**`InvalidParameterValue` on a security group description at apply**: the description
contains a character AWS rejects. Allowed are `a-zA-Z0-9`, space and
`._-:/()#,@[]+=;{}!$*` — so a `§`, an em dash or an arrow fails, and `validate`/`tflint`
pass right up to the apply. Cite rule files without the section glyph (`range-safety.md`,
not `range-safety.md §3`). Terraform *variable* descriptions are unaffected; they never
reach AWS.

**`Invalid value for variable: ssh_public_key`**: the `op://` reference didn't resolve.
Quote the whole reference (the field is `public key`, with a space) and check you have a
1Password session. Also fires if a private key was passed by mistake — never do that; it
would be written into local state in plaintext.

**Tag discovery finds nothing**: Phase 1 isn't applied, `project` differs between roots,
or you're in the wrong region. All roots must share `project`, `aws_region` and
`availability_zone`. Check:
`aws ec2 describe-subnets --filters Name=tag:Discovery,Values=range-subnet`.

**Tag discovery finds multiple matches**: a previous session wasn't torn down; the
singular data sources error on more than one. Remove the stale resources.

**An edited bootstrap script seems to do nothing**: it should not; all seven instances
set `user_data_replace_on_change = true`, so a changed script replaces the host. If you
see an in-place update instead, you are on an older revision of the roots.

**`destroy` on `range-network` refuses**: the SIEM volume has `prevent_destroy` on
purpose. Remove that lifecycle block deliberately to decommission; you lose the index.

## Access

**Router missing from `tailscale status`**: expired or non-reusable auth key, or the
advertised route isn't approved. Approve `10.40.10.0/24` in the admin console; check the
`tailscale up` line in `/var/log/cloud-init-output.log`.

**`ssh` refused or prompts for a password**: the 1Password agent isn't offering the key.
Confirm `Security` is listed in `~/.config/1Password/ssh/agent.toml` and that `ssh-add -L`
lists it:

```toml
[[ssh-keys]]
vault = "Security"
```

Both hosts admit port 22 from the ops CIDR only, so you must be going through the router.

**Can't reach attacker/collector at all**: the router advertises only `10.40.10.0/24`,
never a victim CIDR, by design. Confirm the route is approved.

**Attacker: RDP won't log in**: `attacker_rdp_password` was empty, so xrdp has no
credential for `kali`. Re-apply with it injected. RDP is `:3389`, via the router only.

## Bootstrap

**Attacker: tools missing or shell isn't zsh**: first boot clones SCRT and downloads many
binaries; it takes a while. Individual failures log `WARN` without aborting. See
`/var/log/attacker-bootstrap.log`; if the clone failed, check egress and `scrt_repo_url`.

**Collector: SIEM volume never attached**: the bootstrap log ends with `did not attach
within 5 minutes`. The volume attachment is created *after* the instance, so the script
waits and resolves the device by NVMe serial. If it times out, confirm the volume is
`available` (not still held by a previous collector) and in the same AZ, then re-apply.

**Wazuh dashboard won't load**: the stack OOMs on 2 GB; keep the **t4g.medium** default.
Check `systemctl status wazuh-indexer wazuh-manager wazuh-dashboard` and
`/var/log/collector-bootstrap.log`. Reinstalling over an existing index is the
known-fragile path.

**Windows agents never enroll**: victims are air-gapped and can't fetch the installer;
the install fails soft. Enable the package mirror in both Phase 1 and Phase 2, then
relaunch the victims. Verify from a victim: `curl http://<collector_ip>:8080/`.

**Trust does not form**: a self-deleting task on **DC-B** waits for DC-A's LDAP; both
DCs must finish promotion first, so allow 10–20 minutes. Diagnose on DC-B via
`C:\trust-task.log` and `C:\bootstrap-dc.log`; confirm it resolves `forest-a.lab` and
reaches `<DC-A>:389`. Fallback: run the snippet in the
[multi-forest README](../../_infra/terraform/aws/scenarios/multi-forest/README.md#trust-bootstrap)
by hand.

**Windows won't activate**: it uses link-local KMS (`169.254.169.250/.251:1688`), which
needs no internet route. Confirm the **license-included** AMI
(`windows_ami_owner=amazon`, Base), not BYOL.

## Verification that lies

Two ways an invariant check can *look* like it passed without testing anything. Both are
worse than a failure, because they close a gate that is still open.

**`EnableDnsSupport` comes back `null`**: `describe-vpcs` does not return the DNS
attributes at all, so the JMESPath key resolves to `null` — "not asked", not `false`. Use
`describe-vpc-attribute --attribute enableDnsSupport` (then `enableDnsHostnames`), one
call each. Anything other than a literal `false` from *that* command is a Blocker.

**A `describe-*` query returns `[]`**: check the filter matched something before reading
it as an absence. Route tables, for example, carry only a `Name` tag — filtering them on
`tag:Discovery` matches nothing and `RouteTables[].Routes[]` flattens to `[]`, which is
indistinguishable from "no default route". Every route table always has the `local` route,
so `[]` there means the filter missed. Query by `vpc-id` and print all tables with their
names, per the [deploy runbook](aws-range-deployment.md).

## Expected, not a fault

**No DNS on a victim host**: VPC DNS is disabled (invariant 10). Victims use their DC as
DNS; cross-forest resolution goes through conditional forwarders. Don't "fix" this by
adding a route or re-enabling VPC DNS.

**A victim can't reach the internet**: that is the point (invariant 1). Victim subnets
have no default route, and there is no NAT gateway to add one to. Reach victims *from* the
attacker box instead.

**A probe from the attacker gets no reply, but TCP connects work**: victim NACL egress to
ops starts at port **1024**, so anything sourced from a privileged port gets no reply —
`nmap --source-port 53` is the usual culprit. Deliberate; drop the flag or use a port
above 1024. (`ping` and `nmap -PE` do work: NACL egress rule 320 permits ICMP.)

## Billing

**A Windows host looks far too cheap**: infracost priced it as Linux. Re-run with
`--usage-file infracost-usage.yml`; the bare number is a floor.

**Budget alarm never fired**: `budget_alert_emails` was empty at apply — re-apply with an
address and check `describe-subscribers-for-notification`. Do **not** go looking for a
confirmation email: budget `EMAIL` subscribers need no opt-in (that is an SNS-topic thing),
so silence before a threshold is crossed is the expected state, not a broken subscription.

**No confirmation email arrived for the budget**: none is sent. See above.

**Spend is higher than expected**: almost always something left running. Run `/lab-status`
and complete [teardown](aws-range-deployment.md#teardown).
