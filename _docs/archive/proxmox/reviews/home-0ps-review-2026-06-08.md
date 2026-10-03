# home-0ps.com Review — 2026-06-08

> Generated: 2026-06-08 (`/lab-review`). Supersedes `home-0ps-review-2026-05-29.md`.
> Scope: **Repo state only — the `memphis` dev cluster is fully spun down.** The live
> survey is N/A: `163b8e3 "Uninstall Flux"` removed the Flux bootstrap manifests and the
> `memphis-kubeconfig` 1Password item no longer exists (destroyed with the cluster). All
> live-runtime findings from the baseline are **paused → re-verify on redeploy**, not resolved.
> Trigger: **Return-from-hiatus / teardown + Proxmox-foundation rebuild.** Post-baseline work is
> docs polish + `Uninstall Flux` (committed) and a net-new **`terraform/proxmox-base/`** root
> (admin user + RBAC + automation token + SDN Simple zone) plus a Talos-module bridge param —
> all **uncommitted** in the working tree.

---

## Executive Summary

The lab moved from a live, healthy 6-node `memphis` cluster (baseline 2026-05-29) to a
**deliberate full spin-down**, and the focus shifted to **rebuilding the Proxmox foundation**
before re-deploying Talos.

Committed since the baseline review (`b5e71cb..HEAD`, all dated 2026-05-29, mostly README/docs):
- **Public bootstrap-guide site** (`2e74246` #52 + `54f7290`) — MkDocs Material (gruvbox) + D2
  diagrams + docs restructure into how-to (`a228578`, `41244e1`, `9a01031`).
- **`163b8e3 Uninstall Flux`** — deleted `_clusters/dev/flux-system/{gotk-components,gotk-sync,
  kustomization}.yaml` (6469 lines). The cluster's GitOps tree (`_lib/`, `cluster.yaml`'s 16-layer
  DAG) is **preserved** for re-bootstrap; only the bootstrap entrypoint was removed.

Uncommitted working tree — **the active workstream**:
- **`terraform/proxmox-base/` (NEW)** — persistent TF root, own S3 state, mirrors
  `terraform/cloudflare-tunnel/`. Provisions `admin@pve` (PVEAdmin), `terraform@pve` + custom role
  + `proxmox_user_token` (→ 1Password), and a **SDN Simple zone** `talos` → vnet `vtalos` → subnet
  `10.30.0.0/24` (SNAT) → applier. `terraform validate` passes. **Not yet applied.**
- **Talos module** `var.pve.bridge` param (default `vmbr0`) so a future single-host VNet move is one variable.
- **`cluster-configs.yaml`** — TrueNAS dataset reorg: `DATASET_PARENT` `home-share/iscsi/k8s/dev/volumes`
  → `home-share/k8s/dev`, snapshots path likewise (matches the manual TrueNAS PVE-plugin + iSCSI rework).
- `_hack/portainer/loki` tailscale image `v1.78` → `v1.98.4`; `best-practices.md` bpg-deprecation note.

**Update 2026-06-08:** `terraform/proxmox-base/` is now **applied** — admin user + RBAC + SDN live,
and the `terraform@pve` automation token authenticates and re-applies clean (PB-1/2/3, after fixing a
doubled-token bug in `users.tf`; see [[project_bpg_user_token_value_is_full_token]]).

**Talos-pve → SDN migration (TP-tier) — ✅ TP-1..TP-4 done 2026-06-08, TP-5 applying:** ~~next macro-task,
gated by the TP-1/PB-4 zone-type decision.~~ → **ADR-0008** chose **Option B (EVPN on an OpenFabric routed
underlay)**: the UCG-Ultra @ 5.1.15 has no persistent BGP so Option C was rejected; PVE 9.2.3 gives the
SDN fabric. SDN applied; dev re-IP'd onto `10.30.0.0/24` (bridge `vtalos`, gateway `10.30.0.1`, VIP
`.199`, CP `.200-.202`, workers `.203-.205`, LB `.225`); UniFi static route + TrueNAS iSCSI ACLs squared
away. **TP-5: applying the dev cluster now.** Still pending: SSH-signed commit of the foundation + this
work (PB-7).

---

## Section 1 — What Changed Since 2026-05-29

| Area | 2026-05-29 state | 2026-06-08 state |
| ---- | ---------------- | ---------------- |
| **Cluster lifecycle** | Live: 6 nodes Ready, 17 Kustomizations/HRs Ready | 🗑️ **Spun down.** `Uninstall Flux` (`163b8e3`) removed `flux-system/`; `memphis-kubeconfig` 1P item gone. `cluster.yaml` DAG + `_lib/` retained. |
| **Proxmox base (NEW)** | — (all access as root@pam, no RBAC, no SDN) | ✅ **Applied 2026-06-08.** `terraform/proxmox-base/`: admin user, automation user/role/token (token authenticates — fixed a doubled-token bug). PB-1/2/3 done. Still **uncommitted** (PB-7). |
| **Proxmox SDN (NEW)** | None | ✅ **EVPN-on-OpenFabric zone** `talos`/`vtalos`/`10.30.0.0/24` applied 2026-06-08 (ADR-0008, Option B). ~~Simple zone — no cross-node L2~~ → EVPN restores stretched L2, so the Talos VIP + Cilium L2 design ports over unchanged; dev re-IP'd. TP-1..TP-4 done, TP-5 applying. |
| **TrueNAS storage** | `home-share/iscsi/k8s/dev/volumes` datasets | 🟡 Reorg to `home-share/k8s/dev` (cluster-configs.yaml, **uncommitted**) — pairs with manual PVE TrueNAS-plugin + iSCSI setup. CFG-1. |
| **Talos module** | bridge hardcoded `vmbr0` | ✅ `var.pve.bridge` (default `vmbr0`); no behavior change. PB-6. |
| **Public docs site** | (in-cluster MkDocs retired 2026-05-26) | ✅ NEW external bootstrap-guide: MkDocs Material gruvbox + D2, CF Pages (`#52`). |
| **Off-cluster Loki host** | tailscale `v1.78` | 🟡 `v1.98.4` (uncommitted hygiene). |
| **All live observability/security items** | Verified live (O-*, H-*, Hyg-2, etc.) | ⏸️ **Paused** — unverifiable while cluster down; repo config unchanged, carries forward. |
| **Dev tip** | `b5e71cb` (review at `a6458fc`) | `163b8e3` (+22 commits, 21 docs/README + 1 teardown) + uncommitted working tree |

---

## Section 2 — Live Cluster Snapshot

**N/A — cluster spun down.** `kube dev …` fails at kubeconfig fetch: the `memphis-kubeconfig`
1Password Secure Note (exported by the now-destroyed Terraform run) is gone. No nodes, no Flux, no
workloads to survey. The next snapshot will be regenerated post-redeploy.

Repo-state facts confirmed in lieu of a live survey:
- `_clusters/dev/cluster.yaml` — 16 Kustomization layers intact (DAG ready for re-bootstrap).
- `_clusters/dev/flux-system/` — **removed** (only `config/` + `cluster.yaml` remain under `_clusters/dev/`).
- `terraform/proxmox-base/` — 7 files, `terraform validate` passes (benign bpg `acl` deprecation warning only).
- Working tree dirty: `terraform/proxmox-base/` (untracked) + 5 modified files (see Section 1); **0 of it committed.**

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**
**Note:** the cluster is down — every live-runtime item below is ⏸️ *paused, re-verify on redeploy*;
the repo config behind it is unchanged from baseline (0 commits touched `_lib/`).

### CRITICAL — gating the rebuild

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **CLUSTER-0** | **Re-deploy `memphis`** (Talos + Flux bootstrap) | ❌ **Open — the macro-task** | `terraform/dev/`, `_clusters/dev/cluster.yaml` | After PB-1..PB-4: re-add `flux-system/` bootstrap (or `flux bootstrap` via TF), `terraform apply` dev with `bootstrap_cluster = true`. Verify 6 nodes Ready + Kustomizations reconcile. |
| **PB-4** | **SDN Simple zone can't host the HA cluster** (no cross-node L2 → breaks Talos VIP + Cilium L2 LB) | ❌ **Open — decision needed before VNet migration** | `terraform/proxmox-base/sdn.tf` | Decide: **VXLAN/EVPN zone** (stretched L2) vs **control-plane-endpoint redesign** (drop L2 VIP). Write an ADR in `_docs/decisions/`. Simple zone is fine for single-host validation only. |

### Proxmox foundation (PB-tier — NEW workstream)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **PB-1** | Admin user + RBAC + automation token | ✅ **Applied 2026-06-08** | `terraform/proxmox-base/{users.tf,providers.tf}` | Phase-1 `apply` (root@pam) created `admin@pve` (PVEAdmin), `terraform@pve` + role + token→1P. Done. |
| **PB-2** | SDN Simple zone + vnet + subnet + applier | ✅ **Applied 2026-06-08** | `terraform/proxmox-base/sdn.tf` | Zone/vnet/subnet/applier applied. Still TODO: smoke-test a throwaway VM on bridge `vtalos` (SNAT egress) before the cluster moves there. |
| **PB-3** | Provider auth cutover → token (Phase 2) | 🟡 **proxmox-base done; dev root pending** | `terraform/proxmox-base/providers.tf` + `terraform/dev/providers.tf` | proxmox-base Phase-2 **VERIFIED 2026-06-08** — `terraform@pve!tf` token re-applies clean (after fixing a doubled-token bug in `users.tf`, see [[project_bpg_user_token_value_is_full_token]]). Remaining: wire the same `pve_api_token` conditional into `terraform/dev/providers.tf` (still root@pam). |
| **PB-5** | Manual prereqs: 1P admin item + tfvars + backend, SOPS-encrypt | ❌ Open (user) | `terraform/proxmox-base/{terraform.tfvars,remote.tfbackend}` | Pre-create 1P `proxmox-admin` (password field); fill tfvars (endpoint `192.168.20.6`, hosts `pve01..pve06`); `key=state/proxmox-base/v1.tfstate`; **SOPS-encrypt before commit**. |
| **PB-6** | Talos module bridge param | ✅ Done (coded) | `terraform/modules/talos-pve/{pve.tf,variables.tf}` | `var.pve.bridge` default `vmbr0`. Future VNet move = set `bridge="vtalos"` + new subnet/IPs. |
| **PB-7** | Commit the uncommitted foundation work | ❌ Open | working tree | `terraform/proxmox-base/`, module bridge, cluster-configs reorg, loki bump, best-practices note all uncommitted — branch + commit (SSH-signed by user). |

### Talos-pve → SDN migration (TP-tier — ✅ TP-1..TP-4 DONE 2026-06-08, TP-5 applying)

> **STATUS 2026-06-08:** TP-1..TP-4 complete. **ADR-0008** chose **Option B (EVPN on an OpenFabric
> routed underlay)** — the gateway is a UCG-Ultra @ UniFi OS 5.1.15 (no persistent BGP), so Option C
> was rejected; PVE 9.2.3 provides the SDN fabric. SDN applied (`proxmox-base/sdn.tf`, finalizer
> pattern), dev re-IP'd onto `10.30.0.0/24` (bridge `vtalos`, gateway `10.30.0.1`), UniFi static route
> `10.30.0.0/24 → 192.168.20.6` + TrueNAS iSCSI ACLs squared away. **TP-5: applying the dev cluster now.**

**The task:** with the Proxmox foundation applied and the automation token working (PB-1/2/3),
move `terraform/modules/talos-pve/` (consumed by `terraform/dev/`) off the flat LAN
`192.168.20.0/24` and onto the SDN vnet `vtalos` / subnet `10.30.0.0/24`. **TP-1 (the zone-type
decision, = PB-4) gated the rest.** See [[project_talos_pve_sdn_migration]] + ADR-0008.

**Why it's not just a re-IP:** today node IPs + the Talos control-plane VIP (`talos.vip_ip`) + the
Cilium L2 LB pool (`cilium_config.load_balancer_ip`, `node_network 192.168.20.0/24`) all live on
one **stretched L2** broadcast domain — the VIP floats by gratuitous ARP and Cilium L2 announces LB
IPs by ARP. A Simple SDN zone is **per-node isolated L2** (L3-routed between hosts), so neither
crosses hosts. The zone strategy decides whether the existing design ports over or has to change.

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **TP-1** | ~~Zone-type decision (= PB-4)~~ | ✅ **Done 2026-06-08 — Option B (EVPN-on-OpenFabric), ADR-0008** | `terraform/proxmox-base/sdn.tf` + ADR-0008 | Pick one, write ADR in `_docs/decisions/`: **(A) Simple zone, single-host** — pin all nodes to one PVE host (shared local L2); proves SDN+token+storage+bridge end-to-end, **no HA**. **(B) VXLAN/EVPN zone** *(recommended for HA)* — swap `proxmox_sdn_zone_simple`→vxlan/evpn (+ EVPN controller/peers); stretched L2 returns, existing VIP + Cilium L2 design ports over **unchanged, just re-IP'd**. **(C) Drop L2 dep** — routed CP endpoint (kube-vip BGP / haproxy / DNS-RR) + Cilium L2→BGP peer with the SDN gateway; biggest lift, most "real". |
| **TP-2** | ~~Re-IP the module onto `10.30.0.0/24`~~ | ✅ **Done 2026-06-08** | `terraform/dev/` tfvars + `modules/talos-pve/variables.tf` | Set `var.pve.bridge="vtalos"` (PB-6 param), `var.pve.gateway="10.30.0.1"`; move `cilium_config.node_network`→`10.30.0.0/24`, all `controlplane_nodes/worker_nodes[*].ip`, `talos.vip_ip`, `cilium_config.load_balancer_ip*`→`10.30.0.x`. CIDR validations in `variables.tf` re-check automatically. |
| **TP-3** | ~~Control-plane endpoint + Cilium LB per chosen path~~ | ✅ **Done 2026-06-08 — N/A for Path B** | `modules/talos-pve/{talos.tf,cilium_config.tf,locals.tf}` | Path B: no logic change, just the re-IP. Path A: pin CP `for_each` nodes to one host. Path C: replace the `eth0.vip` block + switch Cilium L2 announcement → BGP. |
| **TP-4** | ~~Off-TF networking & DNS~~ | ✅ **Done 2026-06-08 — UniFi route + TrueNAS ACLs squared away** | UniFi + `_lib/coredns/` + ExternalDNS | LAN clients can't reach `10.30.0.0/24` (SNAT egress only). Add UniFi route `10.30.0.0/24 → a pve host`, **or** expose services only via the existing Cloudflare Tunnel / Tailscale. Update the CoreDNS split-horizon forward + ExternalDNS records for the new IPs ([[project_coredns_split_horizon_forward]]). |
| **TP-5** | Validate the move | 🟡 **Applying now 2026-06-08** | `terraform/dev/` | `terraform apply` dev with `bootstrap_cluster=true` on the new subnet; confirm nodes Ready, API VIP reachable, a test LoadBalancer Service gets + announces a `10.30.0.x` IP. Then graduate Path A → Path B for HA. |

### Config / storage

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **CFG-1** | TrueNAS dataset path reorg | 🟡 Uncommitted | `_clusters/dev/config/cluster-configs.yaml` | `DATASET_PARENT`→`home-share/k8s/dev`. Confirm the live TrueNAS dataset layout matches before redeploy (democratic-csi will create under it). Commit with PB-7. |

### HIGH — security hardening (⏸️ paused, repo config carried forward)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy on. Consult [[cilium-gateway-egress-l7-filter]]. |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. |
| O-5 / G2-2 | Gateway + public-surface hardening | 🟡 Rate-limit done; headers/WAF open | exposed HTTPRoutes + public hostnames | Strip `Server`/`X-Powered-By`, body-size limits; Cloudflare managed WAF. |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |

### Observability follow-ups (⏸️ all paused — cluster down)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| O-6 | Periodic posture scans | ❌ | — | `popeye` + `kubescape` CronJobs → Loki. |
| O-8 | Cluster-wide default-deny CCNP | 🟡 Per-app done | — | Add cluster-wide default-deny for unlabeled namespaces. |
| O-10 | App-data dashboards (postgres-exporter) | ❌ Open | `_lib/observability/` | Shared exporter for the 3 CNPG clusters; mind [[cilium-gateway-egress-l7-filter]] (CCNP egress :5432). |
| O-14 | Codify "audit community configs" rule | ❌ Open | `.claude/rules/` (proposed) | Spot-check label vocabularies vs this cluster's series before merging community PromQL/dashboards. |
| O-15 | kromgo `flux_version` badge "No Data" — KSM label allowlist | ⏸️ Paused (kromgo down) | kps HR + kromgo `config.yaml` | KSM `metricLabelsAllowlist` + query rewrite (full recipe in 2026-05-29 review). Re-verify on redeploy. |
| O-17 | authentik metrics TargetDown × 2 | ⏸️ Paused | `_lib/observability/kube-prometheus-stack/servicemonitor-authentik.yaml` + `_lib/applications/authentik/overlays/dev/` | Was firing pre-teardown. On redeploy: `kube dev -n authentik get svc \| grep metrics` + describe endpoints. |
| O-18 | tailscale-operator PodMonitor 0 targets | ⏸️ Paused ❓ | `tailscale` ns, ts-operator chart | On redeploy: check podmonitor selector vs pod labels. |

### Homer

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |

### Storage migration (S-tier — COMPLETE)

| ID | Item | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~S-1..S-6~~ | (all closed) | ✅ | ADR-0003. Note CFG-1 dataset reorg + redeploy will re-create CNPG clusters from static PVs. |

### Sprint orchestrator

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| SO-2 | First-run polish | 🟡 Open | `.claude/commands/sprint-orchestrate.md` | Document session-limit recovery + cherry-pick path. |
| SO-3 | Sprint-state.json schema versioning | 🟡 Open | `.claude/sprint-state.json` | Add `"schema_version"`. |

### Hygiene / cleanup

| ID | Item | Location | Action |
| -- | ---- | -------- | ------ |
| Hyg-1 | Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |
| Hyg-2 | Orphan Falco Redis PVC | (was) `security` ns | ⏸️ Likely moot post-teardown — verify the TrueNAS zvol/PV was cleaned; StatefulSet stays off. |
| Hyg-3 | yamllint comment warnings | `_clusters/dev/config/cluster-configs.yaml` + prod | Add space after `#`. Non-blocking. |
| Hyg-4 | Loki tailscale bump uncommitted | `_hack/portainer/loki/docker-compose.yaml` | `v1.78`→`v1.98.4`; commit with PB-7. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| I-1 | Talos `kubernetes_version` pinned v1.12.8 | ⚠️ Open | `terraform/dev/`. Revisit at 1.36.0. |
| R5 | Worker memory typo `8092` | ⚠️ Open | `terraform/dev/variables.tf` + tfvars — tidy on next tfvars edit (redeploy touches this). |
| R1/R2 | pve.tf dedup + shared machine config | 🟡 Verify post-refactor | — |
| Sprint 6 | Node-label apply-ordering | ⏸️ Deferred (ADR-0006 #15) | Retry-on-apply workaround stands; will hit on redeploy. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| TrueNAS PVE plugin + shared iSCSI | ✅ Done (manual, this session) | Pairs with CFG-1 dataset reorg. |
| Proxmox admin user + SDN | ✅ Applied 2026-06-08 | Token verified working. TP-tier done (ADR-0008, EVPN-on-OpenFabric); dev re-IP'd + applying. |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Re-confirm on each node during rebuild. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh`. |
| SSO public exposure (Phase 4) | ⏸️ Blocked on redeploy | Cloudflare Tunnel infra persists (own state). |

---

## Section 4 — Thoth & future apps — Status

- **Thoth** — ✅ Descoped (ADR-0005). No change.
- **Cloudflare Tunnel** — ✅ Persists (own TF state, survives teardown). Will front services again post-redeploy.
- **Proxmox base / SDN** — ✅ Applied 2026-06-08 (PB-tier); **TP-tier** Talos-pve→SDN migration ✅ TP-1..TP-4 done (ADR-0008, EVPN-on-OpenFabric), 🟡 TP-5 applying the dev cluster. See [[project_proxmox_base_tf_root]] + [[project_talos_pve_sdn_migration]] + ADR-0008.
- **GPU sharing** — pre-decision (ADR-0004) unchanged.
- **All in-cluster apps** (Authentik, FreshRSS, Homer, Gatus, kromgo, Falco) — ⏸️ offline (cluster down); manifests intact, return on CLUSTER-0.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. ~~**PB-5 prereqs + PB-1/PB-2 apply**~~ ✅ **Done 2026-06-08** — proxmox-base applied (admin user, RBAC, SDN), token authenticates (PB-1/2/3 proxmox-base side). Natural cut.
2. **PB-7 commit** — branch + SSH-signed commit of the foundation work (proxmox-base + the `users.tf` doubled-token fix, bridge param, CFG-1, loki bump, best-practices note). Do this **first** so the applied state matches `dev`.
3. ~~**TP-1 / PB-4 decision (ADR)**~~ ✅ **Done 2026-06-08** — **ADR-0008**: Option B (EVPN on an OpenFabric underlay); C rejected (UCG-Ultra @ 5.1.15 has no persistent BGP).
4. ~~**TP-2/TP-3 re-IP + endpoint**~~ ✅ **Done 2026-06-08** — `dev/terraform.tfvars` + dev consumer code re-IP'd onto `vtalos`/`10.30.0.0/24`; Path B needs no module logic change.
5. ~~**TP-4 networking/DNS**~~ ✅ **Done 2026-06-08** — UniFi static route `10.30.0.0/24 → 192.168.20.6` + TrueNAS iSCSI ACLs squared away; ExternalDNS auto-reconciles the new LB IPs.
6. **CLUSTER-0 redeploy (TP-5)** — 🟡 **applying now (2026-06-08)**: `terraform apply` dev with `bootstrap_cluster=true` on `10.30.0.0/24`; confirm nodes Ready, VIP `10.30.0.199` reachable, a test LoadBalancer Service announces a `10.30.0.x` IP. Also flip `terraform/dev/providers.tf` to the token (PB-3 dev side); R5/Sprint-6/I-1 housekeeping here.
7. **Post-redeploy** — re-verify the paused observability/security punch list (O-15/O-17/O-18, Hyg-2) against the live cluster; regenerate the live snapshot.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `terraform/proxmox-base/users.tf` | NEW — admin@pve (PVEAdmin) + terraform@pve role/ACL/token; token → 1P. Manage perms via `proxmox_acl`, never inline `acl{}` (benign bpg deprecation warning). |
| `terraform/proxmox-base/sdn.tf` | NEW — Simple zone/vnet/subnet/applier. **Constraint:** no cross-node L2 (PB-4). |
| `terraform/proxmox-base/providers.tf` | NEW — two-phase auth (root@pam → token via `pve_api_token`). |
| `terraform/proxmox-base/terraform.tfvars.example` | NEW — fill template; real values endpoint `192.168.20.6`, hosts `pve01..pve06`. |
| `terraform/modules/talos-pve/{pve.tf,variables.tf}` | `var.pve.bridge` param (PB-6) — one-variable VNet move later. |
| `_clusters/dev/config/cluster-configs.yaml` | TrueNAS dataset reorg (CFG-1, uncommitted). |
| `_clusters/dev/cluster.yaml` | 16-layer DAG intact; the re-bootstrap spine (CLUSTER-0). |
| `_clusters/dev/flux-system/` | **Removed** by `163b8e3`; must be re-created for redeploy. |
| `_docs/guides/best-practices.md` | §1 — bpg `acl` deprecation note added this session. |
| `_docs/reviews/home-0ps-review-2026-05-29.md` | Prior baseline (live-cluster state); all live findings carry forward as ⏸️ paused. |
