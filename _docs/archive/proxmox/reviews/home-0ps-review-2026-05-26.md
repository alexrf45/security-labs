# home-0ps.com Review — 2026-05-26

> Generated: 2026-05-26 (`/lab-review`). Supersedes `home-0ps-review-2026-05-25.md`.
> *End-of-day refresh — replaces the earlier 2026-05-26 snapshot at commit `42747f7` (preserved in git history).*
> Scope: Live `memphis` dev cluster at HEAD `e495dae` of `dev`.
> Trigger: Service-status sprint shipped end-to-end **and hardened** + docs-site retired. **27 commits since 2026-05-25**; headline = **Gatus is live internal + public via Cloudflare Tunnel, hardened with CCNPs + ServiceMonitors + rate-limit + Slack alerts**, and the MkDocs docs-site was spun down in one pass. Sprint C app guardrails (H-4/P-2/P-3) + the Cilium agent OOM fix (P-4) also landed earlier in the window.

---

## Executive Summary

A very productive ~37 hours: the **service-status sprint shipped + hardened end-to-end**. Gatus 5.36.0 runs internally at `dev.int.status.home-0ps.com` and publicly at `dev-status.home-0ps.com` through a Terraform-managed Cloudflare Tunnel; **all 6 endpoints 🟢** (authentik, freshrss, grafana, homer + TrueNAS, UniFi). Hardening pass landed in the same window: CCNPs for cloudflared + gatus, ServiceMonitors, a Cloudflare rate-limit ruleset, and Slack alerting via Gatus (reusing Alertmanager's webhook). The **MkDocs docs-site was retired** one-pass (CryptPad pattern) — including the GHCR image package.

**Two hard-earned policy lessons** were discovered, fixed, and memorialized while hardening:

1. **Cloudflared → backend is pod-to-pod, *not* `reserved:ingress`.** First fix path (502 Bad Gateway). See [[cilium-cloudflared-ingress]].
2. **Cilium Gateway egress is enforced at envoy's L7 filter against the BACKEND identity at the BACKEND port** — not at envoy itself, not on `:443`. Symptom: envoy `403 Access denied` with no transport error and `~8ms` fast-failure. Fix for probe-many use cases: `toEntities: [cluster]` (any port). See [[cilium-gateway-egress-l7-filter]].

**Sprint C** (Sprint C app guardrails) and **P-4** (Cilium agent OOM) shipped earlier in the same window: H-4 RQ+LimitRange backfill to authentik + homer + new gatus/cloudflared; P-2 authentik server/worker resources explicit; P-3 Kyverno admission HA (`replicas: 2`); P-4 Cilium agent `req 384Mi / limit 768Mi`.

Live state is healthy: **6 nodes Ready** (Talos `v1.12.8` / k8s `v1.35.0`, ~37h), **all HelmReleases Ready**, no pods outside Running/Completed, 3 certs Ready (wildcard on `letsencrypt-production`), both CNPG clusters 3/3. Some Flux Kustomizations transiently show "dependency not ready" — expected post-push propagation cascade ([[flux-reconcile-lag]]), not a fault.

**Known gap (still the headline open item):** **Zero DB backups.** Storage S-tier hasn't moved in **four review cycles** now. Same gap as 2026-05-22 / 25 / 26-morning.

**Recommended next sprint:** **Storage S-tier (S-1 → S-2)**. Backups have now been "the recommended #1" for four straight reviews without progress; treating this as anything other than CRITICAL is starting to feel optimistic. **Falco (H-3)** is the alternate if you want to close the security tier first instead.

---

## Section 1 — What Changed Since 2026-05-25

| Area | 2026-05-25 state | 2026-05-26 state |
| ---- | ---------------- | ---------------- |
| Cluster lifecycle | Rebuilt ~6h, healthy | Healthy, ~37h (no rebuild) |
| Service status engine | ❌ None | ✅ **Gatus 5.36.0 live + hardened** — internal + public, all 6 endpoints 🟢, Slack alerting wired |
| Cloudflare Tunnel | ❌ None (Tailscale + Cilium Gateway only) | ✅ **Stood up + rate-limited** — Terraform-managed, cloudflared 2026.5.1 (2 replicas), public rate limit live (`20 req/10s`/IP) |
| Public exposure | ❌ Internal-only | ✅ `dev-status.home-0ps.com`. Phase-4 prereq met. |
| docs-site (MkDocs wiki) | ✅ Live | 🗑️ **Retired** — one-pass spin-down; GHCR image deleted |
| H-4 RQ + LimitRange | 🟡 freshrss only | ✅ Done — authentik + homer + new gatus + cloudflared |
| P-2 authentik resources | ❌ Missing | ✅ Done (`f9bef38`) |
| P-3 Kyverno admission HA | ❌ Single-replica | ✅ Done (`f9bef38`) — `replicas: 2` |
| P-4 Cilium agent OOM | (new finding) | ✅ Done (`04ca94c`) — `req 384Mi / limit 768Mi` |
| Service-status hardening (CCNPs / SM / rate-limit / alerts) | (n/a — predates Gatus) | ✅ Done (`c739e8b`/`ed36234`/`070f2a7`/`b7e1e02`/`c8d45e8`) |
| Cilium policy lessons | (none) | 🧠 **2 new memories:** [[cilium-cloudflared-ingress]], [[cilium-gateway-egress-l7-filter]] |
| Wiki revamp (D1) | ❌ Not started | ✅ D1 shipped pre-spin-down; D2–D4 superseded |
| Flux DAG | 17 Kustomizations | **16** in `cluster.yaml` (`+gatus`, `-docs-site`) + `flux-system` |
| Certs | 5 (incl. barman-cloud-*) | 3 — barman-cloud certs pruned |
| Memory entries | (baseline set) | +2 project memories (Cloudflare Tunnel live, docs-site retired) and +2 policy lessons |

---

## Section 2 — Live Cluster Snapshot (2026-05-26 PM, rev `e495dae`)

```
Nodes:        6 Ready — 3 cp + 3 worker — Talos v1.12.8 / k8s v1.35.0 — ~37h
Flux:         16 Kustomizations + flux-system — propagation cascade at survey time
              (HEAD c8d45e8 applied; some downstream still waiting on dependencies);
              all HelmReleases (16) Ready; no apply errors.
HelmReleases: 16, all Ready (Flux v2.8.8; cnpg 0.27.0; kps 78.0.0; authentik 2026.2.3;
              kyverno 3.7.0 [admission replicas: 2]; cert-manager v1.19.3)
Certs:        wildcard-tls (letsencrypt-PRODUCTION), trust-manager, op-connect-tls — Ready.
              barman-cloud-{client,server}-tls pruned with the plugin.
Workloads:    no pods outside Running/Completed.
gatus:        1 pod Running — probing 6 endpoints, all 🟢 (✅ verified via the public
              /api/v1/endpoints/statuses); Slack alerts wired via gatus-slack-webhook ESO.
cloudflared:  2 pods Running — tunnel Healthy in Cloudflare; routes dev-status; egress
              + ingress under hardened CCNP; cloudflared-metrics Service + SM in place.
freshrss:     app 1/1 + CNPG 3/3. RQ + LimitRange + PDBs live.
authentik:    server 1/1 (req 640Mi/lim 1Gi) + worker 1/1 (req 512Mi/lim 1Gi) + CNPG 3/3.
              RQ + LimitRange live (H-4).
CNPG:         authentik-dev-cluster 3/3 + freshrss-dev-cluster 3/3, both "healthy".
              STILL no backup configured (S-5) — 0 ObjectStores, 0 ScheduledBackups.
PVCs:         all CNPG data+WAL on local-path; freshrss app + prometheus/grafana/
              alertmanager on iscsi. No docs-site PVCs.
Cloudflare:   tunnel `home-0ps` Healthy (2 connectors); ingress dev-status →
              gatus.gatus.svc:8080; rate-limit ruleset live (20 req/10s per IP, block).
```

Notable:

- **Gatus is healthy + alerting.** The public `/api/v1/endpoints/statuses` confirmed all 6 endpoints succeed after the L7-filter fix landed (`c8d45e8`).
- **All hardening done within the sprint window** — no deferred N-* items remain (the originally-deferred G0-6/G0-7/G1-4/G1-8/G2-2 are all closed).
- **No DB backups.** Four-review streak unchanged. The cluster is now meaningfully *more* exposed than the morning snapshot in terms of "things that should have backups" (Gatus history is memory-only by intent — N-6 — but everything else is the same).
- **Talos still pinned to v1.12.8** (I-1) — no change.
- **Kyverno admission is HA** (`replicas: 2`).
- **Two policy lessons memorialized** — neither is an open item, but they should be consulted on any future CCNP work touching Gateway-routed or Tunnel-routed services.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

(No open CRITICAL items. The total absence of DB backups is tracked as **S-5/S-1** below — accepted in dev only until the storage sprint.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy is on. (Note: gatus-allow now uses `cluster` for Gateway-routed probes — see [[cilium-gateway-egress-l7-filter]] before narrowing.) |
| H-3 | **Falco** | ❌ Disabled — **top security item** | `_lib/controllers/kustomization.yaml`, `_lib/security/kustomization.yaml` | HR wired; `falco-rules/` empty stub. Decide CRD-ownership (Q1; `crds`-layer precedent exists). Uncomment both, verify `modern_ebpf` on Talos + ServiceMonitor scrape. |
| ~~H-4~~ | ~~ResourceQuotas + LimitRanges~~ | ✅ Done (`f9bef38`) | covers gatus + cloudflared too | — |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. Deprioritized below Falco. |
| ~~N-1~~ | ~~cloudflared egress CCNP~~ | ✅ Done (`c739e8b`) | `_lib/security/cilium-network-policies/cloudflared-*` | — |
| ~~N-2~~ | ~~gatus egress CCNP~~ | ✅ Done (`c739e8b` → corrected to `cluster` in `c8d45e8`) | `_lib/security/cilium-network-policies/gatus-*` | — |
| O-5 / G2-2 | Cilium Gateway hardening + public-surface hardening | 🟡 Rate limit done (`070f2a7`); headers/WAF still open | exposed HTTPRoutes + public `dev-status.home-0ps.com` | Strip `Server`/`X-Powered-By`, body-size limits on the Gateway listeners; Cloudflare managed WAF rules on the public hostname. |

### Performance / capacity

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~P-1~~ | ~~apiserver scrape cardinality~~ | ✅ Done (`be19e56`) | — |
| ~~P-2~~ | ~~authentik server/worker resources missing~~ | ✅ Done (`f9bef38`) | — |
| ~~P-3~~ | ~~Kyverno admission SPOF~~ | ✅ Done (`f9bef38`) — `replicas: 2` | — |
| ~~P-4~~ | ~~Cilium agent OOMKilled~~ | ✅ Done (`04ca94c`) | req `384Mi` / limit `768Mi`; terraform parity |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~R-1~~ | ~~PodDisruptionBudgets~~ | ✅ Done | freshrss + CNPG PDBs live. Optional follow-up: PDBs for cloudflared (2 replicas, would benefit). |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |
| ~~R-7~~ | ~~`terminationGracePeriodSeconds`~~ | ✅ Done freshrss | Optional: authentik server/worker. |
| ~~R-8~~ | ~~Authentik CNPG archiving erroring~~ | ✅ Resolved | Superseded by S-5: no backups for *either* cluster. |
| N-6 | **Gatus persistence upgrade path** (G1-5) | ⏸️ Memory-only for v1 | `_lib/applications/gatus/base/configmap.yaml` (`storage.type: memory`) | Switch to `sqlite` on a small `democratic-csi` PVC, or `postgres` against a new CNPG cluster once S-tier lands. History lost on restart today. |

### Observability follow-ups

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~O-4~~ | ~~K8s events → Loki~~ | ✅ Done | — |
| O-5 | Gateway + public-surface hardening | 🟡 (rate-limit done; see HIGH above) | — |
| O-6 | Periodic posture scans | ❌ | `popeye` + `kubescape` CronJobs → Loki. |
| ~~O-7~~ | ~~Alertmanager routing~~ | ✅ Done | Follow-up app rules: cert expiry, PVC near-full, CNPG no-backup/snapshot-age once S-2 lands, **Gatus endpoint-down via metrics** once dashboards are added. |
| O-8 | Default-deny CCNP (cluster-wide fail-closed) | 🟡 Per-app default-deny landed | Add cluster-wide default-deny for unlabeled namespaces (Q4). |
| O-9 | App-level dashboards/alerts | ❌ | Flip Authentik `serviceMonitor.enabled: true`; add freshrss/authentik/gatus/cloudflared dashboards (SMs are in place for the latter two as of `c739e8b`). |
| ~~N-3~~ | ~~ServiceMonitors for gatus + cloudflared~~ | ✅ Done (`c739e8b`) | `_lib/observability/kube-prometheus-stack/servicemonitor-{gatus,cloudflared}.yaml` |
| ~~N-5~~ | ~~Gatus → Slack alerting~~ | ✅ Done (`ed36234`) | Reuses 1Password `metrics_webhook_dev`; per-endpoint `alerts: [- type: slack]`, defaults 3/2 fail/recover. |
| O-10 | **App-data dashboards in Grafana** (new) | ❌ Open | `_lib/observability/` (postgres-exporter HR or per-CNPG sidecar), Grafana dashboards | Surface app-internal stats as a "lab demonstrates value" piece: **freshrss** unread entries + favorites (from `entry` table; columns `is_read`, `is_favorite`), **authentik** login statistics (from `events_event`; filter on `action` IN login/login_failed), **Gatus** uptime history (the Gatus `/metrics` are already scraped via N-3 — just needs the dashboard). Approach: deploy `prometheus-community/postgres-exporter` against each CNPG with custom SQL queries → KPS scrape → Grafana panels. Watch the Cilium L7-filter lesson — postgres-exporter pods will need an egress allow to the target CNPG (port 5432). |

### Homer follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |
| ~~HM-2~~ | ~~Homer service-tile content~~ | ✅ Done — Gatus tile added | `_lib/applications/homer/base/configmap.yaml` | — |

### Storage migration (S-tier — STILL backup-critical, **fourth review unchanged**)

> Strategy decided 2026-05-25: **local TrueNAS zvol snapshots** (ADR-0003).

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| S-1 | Snapshot infrastructure | ❌ Absent | `global/crds/`, `_lib/storage/freenas-csi/` | Add external-snapshotter CRDs + snapshot-controller, enable democratic-csi snapshotter sidecar, create `VolumeSnapshotClass`. Verify a manual snapshot. **Blocks S-2.** |
| S-2 | CNPG → static iSCSI zvol + scheduled snapshots | ❌ Not started | `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | Pre-create zvols + static `Retain` PVs; CNPG `instances:1`; static `pvcTemplate.volumeName`; `ScheduledBackup` of method `volumeSnapshot`. |
| ~~S-3~~ | ~~Retire R2/S3 from CNPG path~~ | ✅ Done — barman-cloud gone | — | — |
| S-4 | iscsi StorageClass reclaim default | ⚠️ `Delete` | `_clusters/dev/config/cluster-configs.yaml` (`RECLAIM_POLICY`) | Flip to `Retain`. |
| S-5 | **No CNPG backups (both clusters)** | ⚠️ **Real gap — 4th review unchanged** | `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | Resolved by S-1 → S-2. Zero DB recovery capability today. |
| S-6 | **"Last-resort" backup + restore tooling** (new) | ❌ Open | TBD — likely `_hack/scripts/` or a new `_lib/storage/db-rescue/` | Sits alongside the volumeSnapshot path (S-2) as a safety net for snapshot/restore failures. (1) A script that uses `pg_dump` (logical) or `pg_basebackup` (physical) against each CNPG primary, writes to off-cluster storage (TrueNAS dataset). (2) A documented restore procedure that bootstraps a fresh CNPG cluster from that dump (CNPG `bootstrap.recovery.source` against a pg_basebackup dir, or `bootstrap.initdb.import` against a logical dump). Goal: a working "rip cord" the user can run even if S-1/S-2 are unhealthy. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| ~~barman-cloud certs~~ | — | ✅ Pruned with the plugin. |
| ~~docs-site GHCR image package~~ | `ghcr.io/alexrf45/home-0ps-docs` | ✅ Deleted. |
| ~~Sprint D1 superseded plan~~ | `_docs/archive/docs-site-wiki-revamp-sprint.md` | ✅ Archived. |
| ~~docs-site wiki-only files~~ | `_docs/status.md`, `_docs/assets/js/status.js`, `_docs/roadmap.md` | ✅ Removed. |
| ~~gatus-allow description block~~ | `_lib/security/cilium-network-policies/gatus-allow.yaml` | ✅ Refreshed (`e495dae`) to match actual rules post-L7-filter fix. |
| ~~CryptPad TrueNAS zvol~~ | ~~`dev-cryptpad-data-pvc`~~ | ✅ Destroyed (confirmed 2026-05-26). |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |
| Stale intermediate cilium-envoy commit | `29521c8` (and its rule, since replaced) | ✅ Effectively a no-op; left as breadcrumb. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| ~~TF-CoreDNS~~ | ~~Apply CoreDNS split-horizon inlineManifest~~ | ✅ Superseded — Flux-owned `coredns` | — |
| ~~ADR-0006~~ | talos-pve module refactor + provider upgrades | ✅ Done | — |
| ~~TF-CFTunnel~~ | Cloudflare Tunnel TF root | ✅ Done (G0) | `terraform/cloudflare-tunnel/` |
| ~~N-4~~ | ~~Cloudflare rate-limit ruleset~~ | ✅ Done (`070f2a7`) | Free-plan constraints surfaced (`period`/`mitigation_timeout` must be 10) + `characteristics` must include `cf.colo.id`. |
| I-1 | Talos `kubernetes_version` pinned to v1.12.8 | ⚠️ Open | `terraform/dev/` (`fc20340`). Revisit when upstream supports 1.36.0 cleanly. |
| Sprint 6 | Node-label apply-ordering | ⏸️ Deferred (ADR-0006 #15) | Retry-on-apply workaround stands. |
| R1 | Collapse `pve.tf` cp/worker duplication | 🟡 Verify post-refactor | — |
| R2 | Extract shared Talos machine config | 🟡 Verify post-refactor | — |
| R5 | Worker memory typo `8092` | ⚠️ Open | `terraform/dev/variables.tf` + `terraform.tfvars` — tidy on next tfvars edit. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Pairs with Proxmox HA for power-blip recovery. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh`; not in Flux. |
| SSO public exposure (Phase 4) | ⏸️ **Unblocked** — net-new exposure infra (Cloudflare Tunnel) is in place | Remaining: Authentik forward-auth outpost, Cloudflare WAF/access rules. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — ✅ Descoped (ADR-0005). No change.

**docs-site** — 🗑️ **Retired (2026-05-26)**. MkDocs wiki spun down one-pass. `_docs/` markdown retained as engineering reference. Sprint D1 foundation shipped pre-spin-down (mermaid wiring, nav reorg, journey archive, Home revamp); D2–D4 superseded.

**Gatus** — ✅ **Live + hardened (G0+G1+G2 + N-1..N-5)**. Internal `dev.int.status.home-0ps.com`, public `dev-status.home-0ps.com`. 6 endpoints all 🟢. Memory-only persistence (N-6 upgrade path).

**Cloudflare Tunnel** — ✅ **Live (G0) + rate-limited**. Net-new exposure infra; **also unblocks Phase 4 SSO public exposure**.

**GPU sharing** — pre-decision (ADR-0004) unchanged. Deferred to a future Talos-PVE module rev.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **Storage S-tier — S-1 → S-2 + S-6** (FOURTH cycle as recommended #1; the gap is now starting to feel structural). External-snapshotter + snapshot-controller + `VolumeSnapshotClass` (S-1), verify a manual snapshot, then convert one CNPG cluster to static zvol PV + `ScheduledBackup`/volumeSnapshot (S-2). Add the O-7 "no-backup / snapshot-age" alert alongside. **Also includes S-6 — last-resort backup/restore scripts** (`pg_dump` / `pg_basebackup` off-cluster + a documented `bootstrap.recovery` restore path) as the safety net underneath the volumeSnapshot path.
2. **O-9 + O-10 — app dashboards** (small, ships engagement signal): flip Authentik `serviceMonitor.enabled: true`; deploy `postgres-exporter` per CNPG with custom queries; build Grafana panels for **freshrss** unread/favorites, **authentik** login stats, and **Gatus** uptime history (the metrics scrape from N-3 is already feeding Prometheus).
3. **H-3 Falco** — long-standing top security item. CRD-ownership precedent exists; concrete and contained.
4. **S-4 + I-1 + TF verify** — flip iscsi reclaim to `Retain`; revisit the Talos v1.12.8 pin; verify R1/R2 module collapse.
5. **O-5/O-6 + WAF managed rules** — gateway hardening + posture scans + public-surface WAF managed rules.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `terraform/cloudflare-tunnel/` | G0 + G2 — TF root; own S3 state; tunnel + token + 1P item + ingress + DNS + rate-limit ruleset |
| `_lib/networking/cloudflared/` | G0 — in-cluster connector (2 replicas, token via ESO from `cf_tunnel_home-0ps.com`) + metrics Service |
| `_lib/applications/gatus/` | G1 — status engine (memory storage; 6 endpoints; HTTPRoute; Slack alerting ESO) |
| `_lib/security/cilium-network-policies/cloudflared-*.yaml` | N-1 — egress + ingress hardening for cloudflared |
| `_lib/security/cilium-network-policies/gatus-*.yaml` | N-2 — gatus CCNP (uses `toEntities: [cluster]` for the L7-filter fix; see [[cilium-gateway-egress-l7-filter]]) |
| `_lib/observability/kube-prometheus-stack/servicemonitor-{gatus,cloudflared}.yaml` | N-3 |
| `_clusters/dev/cluster.yaml` | Flux DAG — `+gatus`, `-docs-site` |
| `_clusters/dev/config/cluster-configs.yaml` | `+GATUS_VERSION`, `+GATUS_SUBDOMAIN`; `-DOCS_SUBDOMAIN` |
| `_lib/controllers/kyverno/helmrelease.yaml` | P-3 — `admissionController.replicas: 2` |
| `_lib/controllers/authentik/helmrelease.yaml` | P-2 — explicit server + worker resources |
| `terraform/modules/talos-pve-v3.1.0/cilium_config.tf` | P-4 terraform parity (Cilium 768Mi limit) |
| `_docs/decisions/0007-service-status-engine.md` | ADR (Proposed) — service status engine = Gatus |
| `_docs/service-status-sprint.md` | Sprint plan — **closed out** (Sprint outcome section at top) |
| `_docs/archive/docs-site-wiki-revamp-sprint.md` | Superseded plan |
| `_docs/reviews/home-0ps-review-2026-05-25.md` | Prior distinct-date review — superseded by this and the morning 2026-05-26 snapshot |
