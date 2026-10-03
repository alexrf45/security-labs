# home-0ps.com Review — 2026-05-27

> Generated: 2026-05-27 (`/lab-review`). Supersedes `home-0ps-review-2026-05-26.md`.
> Scope: Live `memphis` dev cluster at HEAD `d0f93cb` of `dev`.
> Trigger: **Storage sprint landed end-to-end the same evening as the baseline** + a follow-on Grafana OIDC fix today. **9 commits since the baseline `e495dae`**; headline = **CNPG backups now exist** (the four-review-streak gap is closed) and **Grafana OIDC `sub_mode` is pinned to `user_email`** so DB restores no longer orphan user_auth links.
>
> **In-place update — 2026-05-28:** the two paired follow-ups from this review's *Suggested Next Sprint* both landed today. Commits `bcdefb6` (drill log) + `ed3d828` (Gatus N-6 postgres persistence). The CNPG restore drill exercised both rip cords end-to-end against `freshrss-dev-cluster` (source untouched, drill cluster torn down — 3 drill zvols hand-cleaned from TrueNAS); N-6 spun up `gatus-dev-cluster` as the third CNPG cluster, history now survives pod restarts. Closed items struck through below; Suggested Next Sprint reordered accordingly.

---

## Executive Summary

The single biggest open item from the past four reviews — **zero DB backups** — is **resolved**. Between the baseline (2026-05-26 PM, `e495dae`) and now, 8 commits landed the same evening to ship the full storage sprint: external-snapshotter CRDs + snapshot-controller (S-1), both CNPG clusters migrated to single-instance on **static iSCSI PVs** (S-2; `dev-{authentik,freshrss}-db-pv`), R2/S3 barman-cloud retired (S-3), iscsi `StorageClass.reclaimPolicy` flipped to `Retain` (S-4), VolumeSnapshot ScheduledBackups + the S-6 `pg_dump` rip cord both wired, and CNPG PodMonitors + `CNPGBackupStale`/`CNPGDumpCronJobStale` alerts added on top.

Today (2026-05-27) a one-commit follow-up (`d0f93cb`) pinned the Grafana OIDC provider's `sub_mode` to `user_email` in the authentik blueprint. The trigger: the CNPG single-instance migration recreated the akadmin row, the default `hashed_user_id` derived `sub` from the new PK + signing-key salt, and Grafana's existing user_auth row no longer matched — login broke with "user not found". `user_email` derives `sub` from a value that survives restores.

Live state is healthy: **6 nodes Ready** (Talos `v1.12.8` / k8s `v1.35.0`, ~3d1h), **all 17 Flux Kustomizations Ready at `d0f93cb`** (no propagation cascade at survey time), **all 16 HelmReleases Ready**, no pods outside Running/Completed, 3 certs Ready (`wildcard-tls` on `letsencrypt-production`), both CNPG clusters 1/1 single-instance on static zvols, 4 VolumeSnapshots present (2 scheduled snaps ~23h old, 2 hand tests from sprint validation), 2 dump CronJobs scheduled.

**No DB-backup gap remains.** The next clear sprint is **Falco (H-3)** — long-standing top security item, deferred ~5 cycles — or **app dashboards (O-9 + O-10)** if you want a visible engagement win.

**2026-05-28 update — additional closures:**
- ✅ **CNPG restore drill** — both rip cords validated end-to-end against `freshrss-dev-cluster` (Path A VolumeSnapshot clone via `bootstrap.recovery.volumeSnapshots` matched source row counts exactly; Path B `pg_restore --clean --if-exists` from S-6 dump restored the dump's captured state cleanly). **6 gotchas** memorialized in `_docs/guides/cnpg-rescue.md` (see "Drill log — 2026-05-28"). Drill zvols hand-cleaned from TrueNAS — no residue.
- ✅ **N-6 Gatus persistence upgrade** — `gatus-dev-cluster` (third CNPG cluster) live on static iSCSI PV; gatus storage flipped memory→postgres; history persisted across a verified pod restart; on-demand VolumeSnapshot + pg_dump smoke both passed; Prometheus scraping the new podmonitor; existing `CNPGBackupStale`/`CNPGDumpCronJobStale` alerts auto-cover the new cluster.

---

## Section 1 — What Changed Since 2026-05-26

| Area | 2026-05-26 PM state | 2026-05-27 state |
| ---- | ------------------- | ---------------- |
| **CNPG backups (S-5)** | ❌ Zero ScheduledBackups, zero ObjectStores | ✅ **2 ScheduledBackups (method `volumeSnapshot`)**; last snap 23h ago for each cluster |
| Snapshot infrastructure (S-1) | ❌ Absent | ✅ external-snapshotter CRDs + snapshot-controller + `freenas-iscsi` VolumeSnapshotClass (deletionPolicy `Retain`) |
| CNPG layout (S-2) | 3-instance, dynamic PVs, R2 archive | ✅ **1-instance, static iSCSI PVs** (`dev-authentik-db-pv`, `dev-freshrss-db-pv`) — pre-created Retain zvols |
| S-3 barman-cloud R2 path | ✅ Already pruned (baseline) | — |
| S-4 iscsi reclaim default | ⚠️ `Delete` | ✅ **`Retain`** — one-shot SC delete + Helm re-create landed |
| S-6 last-resort backups | ❌ Open | ✅ `pg_dump` CronJobs (`authentik-cnpg-dump` 03:30 UTC, `freshrss-cnpg-dump` 03:00 UTC) → 20Gi `*-dumps-pvc` (iscsi); CCNPs + rescue runbook included |
| CNPG monitoring | None app-level | ✅ **PodMonitor per CNPG cluster** (`enablePodMonitor: true` on both `Cluster`s) |
| Custom alerts | OOMKilled, Flux reconcile/suspend | ✅ + **`CNPGBackupStale` (critical, 36h)** + **`CNPGDumpCronJobStale` (warning, 36h)** — severity-label routed to slack-critical/warning |
| Authentik Grafana OIDC | `sub_mode` default (`hashed_user_id`) | ✅ Pinned to `user_email` — survives DB restores |
| Flux DAG | 16 Kustomizations + flux-system | unchanged — still 16 + flux-system |
| Memory entries | (baseline set) | +5 (storage-sprint-complete, snapshot-controller / VolumeSnapshot quirks, ScheduledBackup-on-fresh-archiver-prefix, StorageClass.reclaimPolicy immutable, Flux `$VAR` brace form) |

---

## Section 2 — Live Cluster Snapshot (2026-05-27 PM, rev `d0f93cb`)

```
Nodes:        6 Ready — 3 cp + 3 worker — Talos v1.12.8 / k8s v1.35.0 — ~3d1h
Flux:         17 Kustomizations Ready at d0f93cb (no propagation cascade);
              all HelmReleases (16) Ready; no apply errors.
HelmReleases: 16, all Ready — cnpg 0.27.0; cnpg-crds 1.28.0; kps 78.0.0;
              authentik 2026.2.3; kyverno 3.7.0 (admission HA); cert-manager v1.19.3;
              democratic-csi 0.15.0 (both freenas + local-path).
Certs:        wildcard-tls (letsencrypt-PRODUCTION), trust-manager, op-connect-tls — Ready.
Workloads:    no pods outside Running/Completed.
CNPG:         authentik-dev-cluster 1/1 + freshrss-dev-cluster 1/1, both "healthy".
              PodMonitors live for both.
Snapshots:    VolumeSnapshotClass freenas-iscsi (Retain). 4 VolumeSnapshots ReadyToUse:
              authentik-dev-cluster-snap-20260527043000 (23h) + …-test-backup-1 (27h);
              freshrss-dev-cluster-snap-20260527040000 (23h)  + …-test-backup-1 (27h).
ScheduledBackups: authentik (30 3 * * *) + freshrss (0 3 * * *), method volumeSnapshot.
CronJobs:     authentik-cnpg-dump + freshrss-cnpg-dump (S-6 pg_dump rip cord) + renovate.
PVCs:         All Retain. CNPG data on static iSCSI zvols (dev-*-db-pv, 10Gi each).
              freshrss app pvc dev-freshrss-pv (2Gi static); dumps-pvc per app (20Gi);
              prom/grafana/alertmanager on iscsi.
gatus:        1 pod Running — 6 endpoints (not re-verified this cycle).
cloudflared:  2 pods Running — tunnel Healthy in Cloudflare (carried from baseline).
StorageClass: iscsi (default, Retain); local-path (default, Retain).
```

Notable:

- **Backups exist and the staleness watchdog is wired.** The 23h-old scheduled snapshots are inside the 36h SLO; if either ScheduledBackup or pg_dump CronJob lapses, Alertmanager pages.
- **CNPG is single-instance** by design (ADR-0003). HA was previously via 3-instance replication; recovery posture is now snapshot-based.
- **All PVs are Retain** — both static and dynamic. PV deletion will not destroy data.
- **Grafana OIDC fix is one-line user-impact**: post-DB-restore SSO no longer breaks. Memorialize the pattern if/when another OIDC integration lands.
- **Talos still pinned to v1.12.8** (I-1) — no change.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

(No open CRITICAL items. **S-5 closed** — backups exist, staleness alerts wired.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy is on. Consult [[cilium-gateway-egress-l7-filter]] before narrowing anything Gateway-routed. |
| H-3 | **Falco** | ❌ Disabled — **top security item, ~5 cycles deferred** | `_lib/controllers/kustomization.yaml`, `_lib/security/kustomization.yaml` | HR wired; `falco-rules/` empty stub. Decide CRD-ownership (Q1; `crds`-layer precedent now well established). Uncomment both, verify `modern_ebpf` on Talos + ServiceMonitor scrape. |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. Deprioritized below Falco. |
| O-5 / G2-2 | Cilium Gateway hardening + public-surface hardening | 🟡 Rate limit done; headers/WAF still open | exposed HTTPRoutes + public `dev-status.home-0ps.com` | Strip `Server`/`X-Powered-By`, body-size limits on the Gateway listeners; Cloudflare managed WAF rules on the public hostname. |

### Performance / capacity

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~P-1..P-4~~ | (all closed in prior cycles) | ✅ | — |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |
| ~~N-6~~ | ~~**Gatus persistence upgrade path** (G1-5)~~ | ✅ Done 2026-05-28 (`ed3d828`) | postgres-backed via new `gatus-dev-cluster` CNPG (single-instance, static iSCSI PV `dev-gatus-db-pv`, daily VolumeSnapshot + S-6 dump, PodMonitor scraped). Persistence verified across a `rollout restart`. |

### Observability follow-ups

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| O-5 | Gateway + public-surface hardening | 🟡 (rate-limit done; see HIGH above) | — |
| O-6 | Periodic posture scans | ❌ | `popeye` + `kubescape` CronJobs → Loki. |
| O-7 | Follow-up app alerts | 🟡 **Partially done** | `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml` | ✅ Done: `CNPGBackupStale`, `CNPGDumpCronJobStale` (31ccaae). Still open: **cert expiry**, **PVC near-full**, **Gatus endpoint-down** via metrics. |
| O-8 | Default-deny CCNP (cluster-wide fail-closed) | 🟡 Per-app default-deny landed | Add cluster-wide default-deny for unlabeled namespaces (Q4). |
| O-9 | App-level dashboards/alerts | ❌ Open | Flip Authentik `serviceMonitor.enabled: true`; add freshrss/authentik/gatus/cloudflared dashboards. The Grafana OIDC fix today (`d0f93cb`) means freshly-restored sessions land — pair with this work. |
| O-10 | **App-data dashboards in Grafana** | ❌ Open | `_lib/observability/` (postgres-exporter HR or per-CNPG sidecar), Grafana dashboards | Now that CNPG is single-instance on stable PVs, `postgres-exporter` is straightforward. Surface freshrss unread/favorites, authentik login stats, Gatus uptime history. Watch [[cilium-gateway-egress-l7-filter]] — exporters need explicit CCNP egress to the target CNPG on 5432. |
| O-11 | **Gatus endpoint statuses in repo README** | ❌ Open | `README.md` (root); read endpoint keys from `_lib/applications/gatus/base/configmap.yaml` | Embed Gatus SVG status badges for the 6 endpoints (authentik, grafana, freshrss, homer, TrueNAS, UniFi) using the public hostname `https://dev-status.home-0ps.com/api/v1/endpoints/<group>_<name>/health/badge.shields` (or `/uptimes/7d/badge.svg`). Bundle a stale-row cleanup: README's `## Applications` table still lists **Syncthing** (spun down 2026-05-15 per [[syncthing-spundown]]). Replace the static "Active" cells with live Gatus badges and remove Syncthing. Public hostname is already Cloudflare-tunnel-exposed + rate-limited (`terraform/cloudflare-tunnel/main.tf` G2). Risk: GitHub CDN caches SVGs for ~5min — refresh isn't instant. |

### Homer follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |

### Storage migration (S-tier — **COMPLETE**)

> ADR-0003 implemented end-to-end (commits `328148f` → `d5c5ca2`, 2026-05-26 evening).

| ID | Item | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~S-1~~ | ~~Snapshot infrastructure~~ | ✅ Done (`328148f`) | external-snapshotter CRDs in `global/crds/external-snapshotter/`; snapshot-controller in `_lib/storage/snapshot-controller/`; `freenas-iscsi` VolumeSnapshotClass (`Retain`). |
| ~~S-2~~ | ~~CNPG → static iSCSI + scheduled snapshots~~ | ✅ Done (`f18b661`, `d09126e`) | Both CNPG clusters single-instance, pre-created `Retain` zvols, `pvcTemplate.volumeName` static, ScheduledBackup `method: volumeSnapshot`. |
| ~~S-3~~ | ~~Retire R2/S3 from CNPG path~~ | ✅ Done | — |
| ~~S-4~~ | ~~iscsi StorageClass reclaim default~~ | ✅ Done (`31ccaae`) | Flipped to `Retain`; one-shot SC delete + Helm re-create required (reclaimPolicy is immutable). |
| ~~S-5~~ | ~~No CNPG backups~~ | ✅ Done | Closed by S-1 + S-2; `CNPGBackupStale` watches the path. |
| ~~S-6~~ | ~~Last-resort pg_dump rip cord~~ | ✅ Done (`d697e53`, `3c5c0aa`) | `*-cnpg-dump` CronJobs → 20Gi dumps-pvc per app; CCNPs in place; rescue runbook in `_docs/`. `CNPGDumpCronJobStale` watches the path. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |
| Untracked OPML in working tree | `_hack/cybersec-feeds.opml` | Optional commit — saved copy of the curated FreshRSS feed list (43 feeds, 8 categories) from the OPML-import session earlier today. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
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
| SSO public exposure (Phase 4) | ⏸️ **Unblocked** — Cloudflare Tunnel in place | Remaining: Authentik forward-auth outpost, Cloudflare WAF/access rules. |
| ~~**CNPG restore drill**~~ (new) | ✅ Done 2026-05-28 (`bcdefb6`) | Both rip cords validated against `freshrss-dev-cluster`. Path A (VolumeSnapshot clone via `bootstrap.recovery.volumeSnapshots`) — row counts matched source exactly. Path B (`pg_restore --clean --if-exists` from S-6 dump) — restored dump's captured state cleanly. **6 gotchas memorialized** in `_docs/guides/cnpg-rescue.md` "Drill log — 2026-05-28" (RESTORESIZE overhead, `--clean --if-exists` requirement, `postgresql.parameters` non-carry, CCNP cluster-name pinning, `pg_restore` exit-code semantics, TrueNAS-side manual cleanup). Drill zvols cleaned from TrueNAS. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — ✅ Descoped (ADR-0005). No change.

**docs-site** — 🗑️ Retired 2026-05-26. No change.

**Gatus** — ✅ Live + hardened (G0+G1+G2 + N-1..N-5). Memory-only persistence (N-6 upgrade path now achievable).

**Cloudflare Tunnel** — ✅ Live (G0) + rate-limited. Unblocks Phase 4 SSO public exposure.

**GPU sharing** — pre-decision (ADR-0004) unchanged. Deferred to a future Talos-PVE module rev.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **H-3 Falco** — top security item, deferred ~5 cycles. CRD-ownership precedent exists (external-snapshotter, prometheus-operator-crds, cnpg-crds all live in `global/crds/`). Uncomment in `_lib/controllers/kustomization.yaml` + `_lib/security/kustomization.yaml`, verify `modern_ebpf` on Talos, populate `falco-rules/`, wire ServiceMonitor.
2. **O-9 + O-10 app dashboards** — visible "lab demonstrates value" win, now that CNPG is stable. postgres-exporter per CNPG with custom queries; Grafana panels for freshrss unread/favorites + authentik logins + Gatus uptime (the gatus DB now exists, so panels can finally hit real history data). Three CNPG clusters means three exporter HRs; consider a shared `cnpg-postgres-exporter` chart pattern.
3. ~~**N-6 Gatus persistence upgrade**~~ ✅ Done 2026-05-28 (`ed3d828`).
4. **O-7 remaining alerts** — cert expiry, PVC near-full, Gatus endpoint-down via metrics. Half-day task on top of the existing prometheusrule-custom.yaml.
5. ~~**CNPG restore drill**~~ ✅ Done 2026-05-28 (`bcdefb6`). See `_docs/guides/cnpg-rescue.md` "Drill log — 2026-05-28" and the 6 gotchas memorialized there.
6. **I-1 Talos kubernetes_version unpin** + **R5 worker memory typo** + **R1/R2 module collapse verification** — small Terraform housekeeping batch.
7. **O-5/O-6 + WAF managed rules** — gateway header stripping + posture scans (popeye/kubescape) + Cloudflare WAF managed rules on the public hostname.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `global/crds/external-snapshotter/` | S-1 — VolumeSnapshot CRDs (CRD-layer per `crds.md` rule) |
| `_lib/storage/snapshot-controller/` | S-1 — snapshot-controller Deployment + freenas-iscsi VolumeSnapshotClass |
| `_lib/applications/freshrss/overlays/dev/cnpg-static-pv.yaml` | S-2 — static iSCSI PV manifest for freshrss CNPG |
| `_lib/applications/authentik/overlays/dev/cnpg-static-pv.yaml` | S-2 — static iSCSI PV manifest for authentik CNPG |
| `_lib/applications/{freshrss,authentik}/overlays/dev/database.yaml` | S-2/S-5 — CNPG single-instance + ScheduledBackup (`method: volumeSnapshot`) + `monitoring.enablePodMonitor` |
| `_lib/applications/{freshrss,authentik}/overlays/dev/dump-cronjob.yaml` | S-6 — pg_dump rip-cord CronJob + dumps-pvc |
| `_lib/applications/gatus/overlays/dev/{cnpg-static-pv,database,dump-cronjob}.yaml` | N-6 — third CNPG cluster + ScheduledBackup + S-6 dump CronJob (2026-05-28) |
| `_lib/applications/gatus/base/{configmap,deployment,externalsecret-db-creds,resourcequota,limitrange}.yaml` | N-6 — Gatus storage flip + PG_USER/PG_PASSWORD env + ESO from 1P `gatus_dev` + RQ/LR bump |
| `_lib/security/cilium-network-policies/{gatus-cnpg-allow,gatus-dump-allow}.yaml` | N-6 — gatus CNPG ingress/egress + operator-ingress :8000 rule |
| `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml` | O-7 (partial) — `CNPGBackupStale`, `CNPGDumpCronJobStale` (label-selector-based, auto-cover the gatus cluster) |
| `_clusters/dev/config/cluster-configs.yaml` | S-4 — `RECLAIM_POLICY: Retain` flip |
| `_clusters/dev/cluster.yaml` | N-6 — gatus Kustomization `dependsOn` gained `storage` + `external-secrets-operator` + `secrets` |
| `_lib/applications/authentik/base/blueprint-grafana.yaml` | OIDC fix — `sub_mode: user_email` (2026-05-27) |
| `_docs/storage-sprint.md` | Closed-out sprint plan; mirrors S-1..S-6 outcomes |
| `_docs/guides/cnpg-rescue.md` | Drill log 2026-05-28 — both rip cords validated end-to-end; 6 gotchas memorialized |
| `_docs/decisions/0003-static-pv-volumesnapshots-for-cnpg-backups.md` | ADR (Accepted) — strategy decided 2026-05-25, implemented 2026-05-26 |
| `_docs/reviews/home-0ps-review-2026-05-26.md` | Prior review — superseded by this doc |
