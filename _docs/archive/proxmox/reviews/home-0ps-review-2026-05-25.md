# home-0ps.com Review — 2026-05-25

> Generated: 2026-05-25 (`/lab-review`). Supersedes `home-0ps-review-2026-05-22.md`.
> Scope: Status update against the 2026-05-22 review. Live `memphis` dev cluster surveyed at rev `95cb431` (HEAD of `dev`).
> Trigger: Periodic review. ~20 commits since 2026-05-22; headline = **the dev cluster was retired (2026-05-23) and rebuilt greenfield (~2026-05-25 04:00)** on a refactored Terraform module (ADR-0006 Option B) + **Flux upgraded to v2.8.8**. Pre-teardown quick-wins landed (P-1, dead-R2 strip, ADR-0005 descope). New `coredns` Flux layer owns the split-horizon forward. **Backup strategy decided this session: local TrueNAS zvol snapshots — barman-cloud plugin removed.**

---

## Executive Summary

The lab was **torn down and rebuilt from scratch**. On 2026-05-23 the dev cluster was spun down ("home-0ps.com retired for 2026", `68254bc`; Flux uninstalled `00f6381`). With no live VMs, the next apply was a greenfield rebuild — used as the cheap window to take big Terraform provider jumps (ADR-0006 Option B, `17a3e17`), relocate the Talos module to `terraform/modules/talos-pve-v3.1.0/`, and pin the Talos `kubernetes_version` to dodge a k8s 1.36.0 apply error (`fc20340`). The cluster came back ~2026-05-25 04:00 and Flux fully reconciled to HEAD.

Live state is healthy: **6 nodes Ready** (Talos `v1.12.8` / k8s `v1.35.0`, ~6h old), **all 18 Flux Kustomizations `True@95cb431`**, all 16 HelmReleases Ready, no pods outside Running/Completed, all 5 certs Ready (wildcard on `letsencrypt-production`), both CNPG clusters 3/3 healthy.

**Headline changes since 2026-05-22:**

- **Greenfield rebuild** (`68254bc` → `95cb431`) — terraform module refactor + provider upgrades (ADR-0006), **Talos pinned/rolled back `v1.13.0` → `v1.12.8`** (k8s stays `v1.35.0`) to avoid a 1.36.0 apply failure, **Flux upgraded to v2.8.8** (`e2ce729`/`7b14654`). The "ugh/boom/helmrelease version issue" churn (`53ebcf0`…`19bf60f`) was apiVersion fallout from the Flux jump — resolved; everything green now.
- **CoreDNS split-horizon is now Flux-owned** (`95cb431`) — new top-of-DAG `coredns` Kustomization force-applies `kube-system/coredns` ConfigMap (forwards `home-0ps.com` → UniFi `${INTERNAL_DNS_RESOLVER}` 10.3.3.1). Supersedes the old Talos-inlineManifest approach (closes **TF-CoreDNS**).
- **Tailscale CRDs moved to the `crds` layer** (`703e2a9`) — broke a CRD-ownership deadlock.
- **Grafana OIDC re-provisioned via an Authentik blueprint** (`55eb3b7`).
- **Pre-teardown quick-wins** (`be19e56`) — **P-1 done** (apiserver bucket cardinality dropped), dead R2 references removed, **ADR-0005 Thoth descoped** ✅.
- **Backups → local TrueNAS zvol snapshots** (decision, 2026-05-25; ADR-0003). **barman-cloud plugin removed this session** — it was deployed-but-unused (no ObjectStore, no CNPG `plugins`/`backup` block). Removed `_lib/storage/barman-cloud/`, its storage-kustomization entry, and the dead `world:443` egress in `authentik-cnpg-allow.yaml`.

**Known gap (now the headline open item):** **there are currently zero database backups.** Both CNPG clusters run with no `backup`/`plugins` block, no ObjectStore, no ScheduledBackup. `ContinuousArchiving=True` is trivially-true (nothing configured to fail), **not** evidence of working backups. The decided path forward is S-1 (snapshot infra) → S-2 (static zvol PVs) → ScheduledBackup on VolumeSnapshots.

**Still open:** security tier — **Falco (H-3)** wired but disabled (top item), Trivy (H-5) still an empty dir. H-4 partial (freshrss only). Storage S-tier untouched and now backup-critical.

**Recommended next sprint:** **Storage S-tier (S-1 → S-2)** — backups are now a real gap, and the strategy (local zvol snapshots) is decided. Falco (H-3) is the alternate if you'd rather close the security layer first. See §5.

---

## Section 1 — What Changed Since 2026-05-22

| Area | 2026-05-22 state | 2026-05-25 state |
| ---- | ---------------- | ---------------- |
| Cluster lifecycle | Live, 24d uptime | **Retired 2026-05-23, rebuilt greenfield ~05-25 04:00** (~6h old) |
| Terraform | Module half-moved (`eb3faf0`) | ✅ **ADR-0006 Option B** — module at `terraform/modules/talos-pve-v3.1.0/`, provider upgrades, greenfield apply |
| Talos / k8s | Talos `v1.13.0` / k8s `v1.35.0` | **Talos `v1.12.8`** (pinned down to dodge 1.36.0 apply error) / k8s `v1.35.0` |
| Flux | v2.x | ✅ **v2.8.8** (`e2ce729`/`7b14654`); apiVersion churn resolved |
| CoreDNS split-horizon | Talos inlineManifest (TF-CoreDNS, apply unverified) | ✅ **Flux-owned `coredns` Kustomization** (`95cb431`) — live & reconciled |
| Tailscale CRDs | In operator HR | ✅ **Moved to `crds` layer** (`703e2a9`) — deadlock broken |
| Grafana OIDC | Authentik entitlements | ✅ **Re-provisioned via Authentik blueprint** (`55eb3b7`) |
| P-1 apiserver cardinality | ❌ Open | ✅ **Done** (`be19e56`) — `apiserver_request_duration_seconds_bucket`/`_response_sizes_bucket` dropped |
| ADR-0005 Thoth | Draft (descope pending) | ✅ **Descoped** in-doc (no full app) |
| CNPG backups (R-8) | Authentik archiving erroring (dead R2) | 🟡 **Errors gone** (R2 config stripped) — but **no backups at all** now (S-5) |
| barman-cloud | Plugin path implied | ✅ **Removed** (deployed-but-unused) — backups go local zvol snapshots |
| Stale Tempo PVC | `storage-tempo-0` lingering | ✅ **Gone** (wiped by rebuild) |
| Flux DAG | 16 Kustomizations | **18** — `+coredns`; (full app set re-reconciled) |

---

## Section 2 — Live Cluster Snapshot (2026-05-25, rev `95cb431`)

```
Nodes:        6 Ready — 3 cp + 3 worker — Talos v1.12.8 / k8s v1.35.0 — ~6h
Flux:         18 Kustomizations — ALL True@95cb431 (cluster-config, coredns, crds, controllers, pki,
              external-secrets-operator, secrets, networking, dns, storage, observability, security,
              freshrss, authentik, homer, docs-site, flux-system)
HelmReleases: 16, all Ready (Flux v2.8.8; cnpg 0.27.0 + cnpg-crds 1.28.0; kps 78.0.0; authentik 2026.2.3)
Certs:        wildcard-tls Ready (letsencrypt-PRODUCTION) · trust-manager, barman-cloud-{client,server},
              op-connect-tls Ready  [barman-cloud certs will prune with the plugin removal]
Workloads:    no pods outside Running/Completed
freshrss:     app 1/1 + CNPG 3/3. RQ (freshrss) + LimitRange (freshrss-defaults) LIVE. App PDB + CNPG PDBs live.
authentik:    server/worker + CNPG 3/3. CNPG PDBs live. No namespace RQ/LimitRange (H-4 gap).
CNPG:         authentik-dev-cluster 3/3 + freshrss-dev-cluster 3/3, both "healthy".
              NO backup configured: plugins={} backup={} — 0 ObjectStores, 0 ScheduledBackups, 0 Backups.
PVCs:         all CNPG data+WAL on local-path; freshrss app + prometheus/grafana/alertmanager on iscsi.
              No stale Tempo PVC.
```

Notable:

- **No DB backups exist.** Direct evidence: `kube dev get objectstores,scheduledbackups,backups -A` → none; cluster specs have empty `plugins`/`backup`. `ContinuousArchiving=True` is misleading here (default state, nothing to fail). This is the real S-tier gap (S-5).
- **barman-cloud plugin removed** (this session) — Flux will prune the live `database/barman-cloud` Deployment + Service + RBAC + selfsigned certs on the next `storage` reconcile.
- **Talos rolled back to v1.12.8** — intentional pin (`fc20340`) to avoid a k8s 1.36.0 apply error. Revisit unpin once upstream is sorted (I-1).
- **CNPG still all `local-path`** — the durability gap S-2 targets.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| ~~C-2~~ | ~~Wildcard cert on staging~~ | ✅ Done 2026-05-16 | `_lib/networking/gateway/tls.yaml` | — |

(No open CRITICAL items. The total absence of DB backups is tracked as S-5/S-1 below — accepted in dev only until the storage sprint.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies | ✅ Live (authentik, freshrss, homer, docs-site; default-deny + app/CNPG allow) | `_lib/security/cilium-network-policies/` | Follow-up: tighten `world:443` egress to `toFQDNs` once L7 DNS policy is on. |
| H-3 | Falco | ❌ Disabled — **top security item** | `_lib/controllers/kustomization.yaml` (`#  - ./falco`) + `_lib/security/kustomization.yaml` (`#- ./falco-rules`) | HR is wired (`_lib/controllers/falco/` has helmrelease/repo/namespace/kustomization); `falco-rules/` is still an empty stub. Decide CRD-ownership (Q1) — note `crds` layer + tailscale precedent now exists (`703e2a9`). Uncomment both, allow falcoctl egress past default-deny, verify `modern_ebpf` loads on Talos + ServiceMonitor scrapes. |
| ~~H-4~~ | ~~ResourceQuotas + LimitRanges~~ | ✅ **Done** 2026-05-25 (`f9bef38`) | `_lib/applications/{authentik,homer,docs-site}/base/{limitrange,resourcequota}.yaml` | RQ + LimitRange now on authentik, homer, docs-site (+ freshrss). authentik CNPG pods bounded via LimitRange defaults; server/worker via P-2. |
| H-5 | Trivy operator | ❌ **Empty dir** | `_lib/security/trivy/` (no files) + `_lib/security/kustomization.yaml` (`#- ./trivy`) | Populate trivy-operator HR, wire reports → Prometheus/Grafana. Deprioritized below Falco. |

### Performance / capacity

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~P-1~~ | ~~apiserver scrape cardinality~~ | ✅ **Done** (`be19e56`) | `metricRelabelings` drop apiserver request/response buckets — `_lib/observability/kube-prometheus-stack/helmrelease.yaml:271`. |
| ~~P-2~~ | ~~App resource requests/limits missing~~ | ✅ **Done** 2026-05-25 (`f9bef38`) | Authentik server (req 640Mi/lim 1Gi) + worker (req 512Mi/lim 1Gi) set explicitly in the HelmRelease, sized above observed 543Mi/463Mi. |
| ~~P-3~~ | ~~Kyverno mutation webhook on every pod CREATE~~ | ✅ **Done** 2026-05-25 (`f9bef38`) | admissionController replicas 1→2 (HA) in `_lib/controllers/kyverno/helmrelease.yaml`. Policy breadth was already bounded by `resourceFiltersExcludeNamespaces`; `disable-service-links` already app-scoped; no autoscaler consumes `add-safe-to-evict` (left as-is). |
| ~~P-4~~ | ~~Cilium agents OOMKilled (250Mi limit too low)~~ | ✅ **Done** 2026-05-25 (`04ca94c`) | 5/6 agents OOMKilled mid-rollout ~02:06 (Slack alert); steady state already hit 212Mi/250Mi with WireGuard + Hubble L7 + Envoy + Gateway API. Bumped to req 384Mi / limit 768Mi. Live DaemonSet patched + terraform parity at `terraform/modules/talos-pve-v3.1.0/cilium_config.tf`. Note: Cilium is a Talos inlineManifest (bootstrap-only) — the live patch is the running-cluster fix; terraform covers the next rebuild. |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~R-1~~ | ~~PodDisruptionBudgets~~ | ✅ Done | freshrss app PDB + CNPG PDBs (both apps) live. |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |
| ~~R-7~~ | ~~`terminationGracePeriodSeconds`~~ | ✅ Done freshrss | Optional follow-up: authentik server/worker. |
| ~~R-8~~ | ~~Authentik CNPG archiving erroring~~ | ✅ **Resolved** — dead R2/barman config stripped pre-teardown + rebuild has none | Superseded by S-5: no backups now exist for *either* cluster. |

### Observability follow-ups

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~O-4~~ | ~~K8s events → Loki~~ | ✅ Done | — |
| O-5 | Cilium Gateway hardening | ❌ | Strip `Server`/`X-Powered-By`, body-size limits, rate limiting on exposed HTTPRoutes (grafana/freshrss/authentik/homer/docs-site). |
| O-6 | Periodic posture scans | ❌ | `popeye` + `kubescape` CronJobs → Loki. |
| ~~O-7~~ | ~~Alertmanager routing~~ | ✅ Done | Follow-up: app rules (cert expiry, PVC near-full, **CNPG no-backup / VolumeSnapshot age** once S-2 lands). |
| O-8 | Default-deny CCNP | 🟡 Per-app default-deny landed | Add a cluster-wide default-deny CCNP for fail-closed on unlabeled namespaces (Q4). |
| O-9 | App-level dashboards/alerts | ❌ | Flip Authentik `serviceMonitor.enabled: true`; add freshrss/authentik dashboards. |

### Homer / docs-site follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount as `emptyDir`, flip to RO. |
| HM-2 | Homer service-tile content | ❓ Verify | `_lib/applications/homer/base/configmap.yaml` | Confirm tiles list live hosts incl. docs-site (`dev.int.docs`). |
| DS-1 | docs-site living-scaffold pages manual | ⚠️ | `_docs/status.md`, `_docs/roadmap.md` | Refresh when apps land. |

### Storage migration (S-tier — now backup-critical)

> Strategy decided 2026-05-25: **local TrueNAS zvol snapshots** (ADR-0003), not object-storage WAL archiving. barman-cloud removed.

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| S-1 | Snapshot infrastructure | ❌ Absent | `global/crds/`, `_lib/storage/freenas-csi/` | Add external-snapshotter CRDs + snapshot-controller, enable democratic-csi snapshotter sidecar, create `VolumeSnapshotClass`. Verify a manual snapshot. **Blocks S-2; now the backup critical path.** |
| S-2 | CNPG → single-instance static iSCSI zvol + scheduled snapshots | ❌ Not started | `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | Pre-create zvols + static `Retain` PVs; CNPG `instances:1`; static `pvcTemplate.volumeName`; CNPG `ScheduledBackup` of method `volumeSnapshot`. Verify operator `0.27.0` honors `volumeName` on a throwaway cluster first (Q2: authentik vs freshrss first). |
| ~~S-3~~ | ~~Retire R2/S3 from CNPG path~~ | ✅ **Done** — IaC removed earlier; **barman-cloud plugin removed 2026-05-25** | `_lib/storage/kustomization.yaml`, `authentik-cnpg-allow.yaml` (dead `world:443` egress removed) | — |
| S-4 | iscsi StorageClass reclaim default | ⚠️ `Delete` | `_clusters/dev/config/cluster-configs.yaml` (`RECLAIM_POLICY: "Delete"`) | Flip to `Retain` so accidental dynamic iscsi volumes survive PVC deletion. |
| S-5 | **No CNPG backups (both clusters)** | ⚠️ **Real gap** | `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | Resolved by S-1 → S-2 (VolumeSnapshot ScheduledBackup). Until then there is zero DB recovery capability. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| ~~Stale Tempo PVC~~ | — | ✅ Gone (rebuild wiped it). |
| barman-cloud certs | `database/barman-cloud-{client,server}-tls` | Will prune with the plugin on next `storage` reconcile — verify gone post-reconcile. |
| ~~ADR-0005 Thoth descope~~ | `_docs/decisions/0005-thoth-knowledge-app.md` | ✅ Status = Descoped (2026-05-22). |
| CryptPad TrueNAS zvol | `dev-cryptpad-data-pvc` | ❓ Confirm destroyed (rebuild doesn't touch TrueNAS zvols). |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| ~~TF-CoreDNS~~ | ~~Apply CoreDNS split-horizon inlineManifest~~ | ✅ **Superseded** — now a Flux `coredns` Kustomization (`95cb431`), live & reconciled | `_lib/coredns/configmap.yaml` |
| ~~ADR-0006~~ | talos-pve module refactor + provider upgrades | ✅ **Done** (Option B, greenfield apply) | Module at `terraform/modules/talos-pve-v3.1.0/`; `terraform/dev/main.tf` consumes it. |
| I-1 | Talos `kubernetes_version` pinned/rolled back to dodge k8s 1.36.0 apply error | ⚠️ New | `terraform/dev/` (`fc20340`). Revisit unpin once upstream/provider supports the bump cleanly; currently Talos `v1.12.8`. |
| Sprint 6 | Node-label apply-ordering (`kubernetes_labels.worker_role` fails first apply) | ⏸️ Deferred (ADR-0006, finding #15) | Still present after the rebuild path — retry-on-apply workaround stands. |
| R1 | Collapse `pve.tf` cp/worker duplication | 🟡 Verify post-refactor | Confirm cp/worker dup *within* the module collapsed (must not break node scaling — see memory). |
| R2 | Extract shared Talos machine config | 🟡 Verify post-refactor | Confirm worker CP-only PSA exemptions. |
| R5 | Worker memory typo `8092` | ⚠️ | `terraform/dev/variables.tf` + `terraform.tfvars` — tidy next tfvars edit. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Pairs with Proxmox HA for power-blip recovery. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh`; not in Flux. |
| SSO public exposure (Phase 4) | ⏸️ Not started | Cloudflare Tunnel + forward-auth outposts; WAF terraform not built. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — ✅ Descoped (ADR-0005, 2026-05-22): no full app; utilities/scripts + harden existing infra.

**docs-site** — ✅ Live (re-reconciled in rebuild). Polish = DS-1.

**GPU sharing** — pre-decision (ADR-0004), single-node VFIO passthrough on HP Slim S01. ADR-0006 notes the pinned `bpg/proxmox` provider's `hostpci` support is relevant; GPU passthrough deferred to a future module version.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **Storage S-tier — S-1 → S-2** (now backup-critical; strategy decided = local zvol snapshots). Add external-snapshotter + snapshot-controller + `VolumeSnapshotClass` (S-1), verify a manual snapshot, then convert one CNPG cluster to static zvol PV + `ScheduledBackup`/volumeSnapshot (S-2). Add the O-7 "no-backup / snapshot-age" alert alongside.
2. **H-3 — enable Falco** (the wired-but-disabled security layer). CRD-ownership now has the `crds`-layer precedent; uncomment, allow falcoctl egress, verify eBPF + ServiceMonitor.
3. **H-4 backfill + P-2** — extend the freshrss RQ/LimitRange pattern to authentik/homer/docs-site; set authentik requests/limits.
4. **S-4 + I-1 + TF verify** — flip iscsi reclaim to `Retain`; revisit the Talos version pin; verify R1/R2 collapse post-refactor.
5. **O-5/O-6/O-9** — gateway hardening + posture scans + app dashboards.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `_clusters/dev/cluster.yaml` | Flux DAG — new `coredns` layer; full app set |
| `_lib/coredns/configmap.yaml` | Flux-owned CoreDNS split-horizon forward (supersedes TF-CoreDNS) |
| `_lib/storage/kustomization.yaml` | barman-cloud entry removed (S-3) |
| `_lib/security/cilium-network-policies/authentik-cnpg-allow.yaml` | dead barman `world:443` egress removed |
| `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | CNPG specs — no backup/plugins block (S-5); local-path storage (S-2) |
| `_lib/observability/kube-prometheus-stack/helmrelease.yaml` | P-1 apiserver `metricRelabelings` (done) |
| `_lib/controllers/kustomization.yaml` + `_lib/security/kustomization.yaml` | Falco/Trivy commented (H-3/H-5) |
| `terraform/modules/talos-pve-v3.1.0/` | Refactored Talos module (ADR-0006) |
| `_docs/decisions/0006-talos-pve-module-refactor.md` | Rebuild rationale + deferred Sprint 6 |
| `_docs/decisions/0003-cnpg-local-snapshots.md` | Decided backup strategy (local zvol snapshots) |
| `_docs/reviews/home-0ps-review-2026-05-22.md` | Prior review — superseded |
</content>
</invoke>
