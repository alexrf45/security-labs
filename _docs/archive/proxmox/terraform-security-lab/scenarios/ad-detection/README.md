# scenario: ad-detection (Phase 2)

An intentionally-attackable Active Directory lab on the gateway-less detonation
vnet `vdet00`, plus a dual-homed Kali attacker. Local Terraform state (disposable).

| VM | Template | Net | Role |
| -- | -------- | --- | ---- |
| `DC01` | tpl-win2022 | vdet00 (10.50.0.10) | forest root DC + DNS |
| `WS10` | tpl-win10 | vdet00 (10.50.0.20) | domain workstation |
| `WS11` | tpl-win11 | vdet00 (10.50.0.21) | domain workstation |
| `kali` | tpl-kali | vlabops (dhcp) + vdet00 (10.50.0.50) | attacker (dual-homed) |

## Planted misconfigurations (detect these)

- **Kerberoasting** — `svc_sql` with SPN `MSSQLSvc/sql01.lab.local:1433`, weak password.
- **AS-REP roasting** — `asrep_user` with Kerberos pre-auth disabled.
- **Dangerous ACL** — `jdoe` has `GenericAll` over `svc_sql`.
- Plus regular users (`jdoe`, `asmith`, `bwilson`) with a weak shared password.

Sysmon (baked into the Windows templates) logs to
`Microsoft-Windows-Sysmon/Operational` — the source for the Phase 3 Wazuh pipeline.

## Prerequisites

1. `range-network` applied (vnets `vdet00` + `vlabops`, `det_isolation` group) and
   the Phase 0 air-gap test passed.
2. Packer templates built (Phase 1); put their vmids in `terraform.tfvars`.
3. The `snippet_datastore` (default `local`) has the **snippets** content type
   enabled.
4. `local_admin_password` ideally matches the Packer `winadmin_password`.

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in, SOPS-encrypt
terraform init                                  # local backend
op run -- terraform apply
```

First boot runs cloudbase-init → the bootstrap PowerShell: the DC promotes the
forest (one reboot) then a scheduled task seeds the misconfigurations; the
workstations rename + join in one reboot. Give it ~15-20 min, then check
`C:\ProgramData\lab\*.log` on each host via the Proxmox console.

## Snapshot for repeatable runs

bpg has no snapshot resource — after the lab settles, snapshot each VM so you can
roll back after an attack/CVE:

```bash
for id in $(terraform output -json domain_vm_ids | jq -r '.[]'); do
  qm snapshot $id clean-baseline   # run on the owning PVE node
done
```

## Attack → detect loop

From Kali (detonation side `10.50.0.50`): enumerate the domain, Kerberoast/AS-REP
roast `svc_sql`/`asrep_user`, crack the weak passwords, abuse the `GenericAll`
ACL. Watch the matching Sysmon/Security events on the victims (and in Wazuh once
Phase 3 is wired). Kali reaches the victims over the detonation L2 but cannot
reach the mgmt LAN, TrueNAS, or the ops subnet beyond its own DHCP gateway.

## Teardown

`op run -- terraform destroy` — node-local disks reclaimed; nothing was on TrueNAS.

## Safety

Re-check `.claude/rules/lab-isolation.md` before every apply: detonation NICs have
no gateway, disks are node-local, victims carry `det_isolation`, Kali is the only
dual-homed box and is `isolate = false`.
