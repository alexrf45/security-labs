# home-0ps.com Review — 2026-05-22

> Generated: 2026-05-22 (`/lab-review`) — **regenerated**, supersedes the earlier same-day pass (which predated the freshrss resilience bundle + `/sprint-menu`). Supersedes `home-0ps-review-2026-05-20.md`.
> Scope: Status update against the 2026-05-20 review + `storage-strategy-decision.md`. Live `memphis` dev cluster surveyed at rev `0878dcc`.
> Trigger: Periodic review. 9 commits since 2026-05-20; headline = **MkDocs docs-site shipped**, **R2/object-storage terraform decommissioned**, **observability trim** (Tempo removed, k8s events → Loki, Grafana SSO-only), and the **freshrss resilience bundle** (H-4 + R-1 + R-7). New tooling: `/sprint-menu` session picker.

---

## Executive Summary

The lab is workload-healthy — 6 nodes Ready (Talos `v1.13.0`, k8s `v1.35.0`, 24d), all pods Running/Completed, all 5 certs Ready (wildcard on `letsencrypt-production`). At survey time Flux was mid-propagation of `0878dcc`: upstream layers (cluster-config → controllers → crds → eso → pki → secrets → security) all `True@0878dcc`; `dns`/`storage`/`freshrss`/`observability`/`docs-site`/`homer`/`authentik` lagging one reconcile tick (transient dependency wave, not a fault).

**Headline changes since 2026-05-20:**

- **freshrss resilience bundle** (`0878dcc`, today) — **H-4** LimitRange (`freshrss-defaults`) + ResourceQuota (`freshrss`), **R-1** app-scoped PodDisruptionBudget (`maxUnavailable:1`, selector `app=freshrss`), **R-7** `terminationGracePeriodSeconds:45`. Validated (yamllint + render + server dry-run). Confirmed live that CNPG ships its own PDBs (`freshrss-dev-cluster`, `freshrss-dev-cluster-primary`) — the app PDB does not overlap them.
- **docs-site (MkDocs)** shipped as a new Flux app (`50b62a4`/`1596964`/`b29733a`/`3744bae`), internal `dev.int.docs.home-0ps.com`.
- **Object-storage terraform decommissioned** (`eb3faf0`) — deleted `modules/object-storage` + `dev/authentik-object-storage` + `dev/wallabag-s3-backup`; R2 + wallabag S3 cloud resources destroyed (confirmed).
- **Observability trim** (`8735a38`) — Tempo removed (HR pruned live; PVC pending manual delete), Alloy ships k8s events to Loki (O-4), Grafana SSO-only.
- **Tooling** (`21d5e3f`) — `/sprint-menu` session-kickoff picker reads the newest review and lets you pick a sprint/task to start.

**Known, accepted gap (R-8):** Authentik CNPG WAL archiving errors (`ContinuousArchiving=False`) since R2 was decommissioned — acceptable in dev, backup deferred to the storage sprint; cheap interim is stripping the dead barman-cloud config.

**Still open:** security tier — **Falco (H-3)** is now the top item (the evaluated next security tool), then Trivy (H-5). H-4 partially done (freshrss only; backfill other apps). Perf tier P-1/P-2/P-3 untouched. Storage S-tier (S-1…S-5) not started.

**Recommended next sprint:** **Falco (H-3)** — resolve the CRD-ownership decision, then enable + verify eBPF on Talos. See §5.

---

## Section 1 — What Changed Since 2026-05-20

| Area | 2026-05-20 state | 2026-05-22 state |
| ---- | ---------------- | ---------------- |
| freshrss resilience | ❌ No quota/limits/PDB/grace | ✅ **Bundle landed** (`0878dcc`) — LimitRange + ResourceQuota + app PDB + `terminationGracePeriodSeconds:45`. (Reconcile in flight at survey.) |
| Docs site | ❌ None | ✅ **docs-site live** — MkDocs → nginx-unprivileged, own Flux Kustomization, internal `dev.int.docs`. |
| Tracing (Tempo) | ✅ Deployed | ✅ **Removed** (`8735a38`) — HR pruned live; `storage-tempo-0` 30Gi PVC pending manual delete. |
| Logs/events | Logs-only | ✅ **k8s events → Loki** (O-4, `8735a38`). |
| Grafana auth | OIDC + local form | ✅ **SSO-only** (`8735a38`). |
| Object storage (IaC) | modules/object-storage + 2 consumers | ❌ **Deleted** (`eb3faf0`); R2 + wallabag S3 cloud resources destroyed. |
| Terraform layout | Talos module under dev/ | Extracted to `terraform/modules/talos-pve-v3.1.0/` (R1/R2 partial). |
| Flux DAG | 15 Kustomizations | **16** — `docs-site` added. |
| Tooling | `/lab-review`, `/flux-*`, `/terraform-*` | + **`/sprint-menu`** session picker (`21d5e3f`). |

---

## Section 2 — Live Cluster Snapshot (2026-05-22, rev `0878dcc`)

```
Nodes:      6 Ready — 3 cp + 3 worker — Talos v1.13.0 / k8s v1.35.0 — 24d
Flux:       16 Kustomizations — upstream layers True@0878dcc; dns/storage/freshrss/observability/docs-site/homer/authentik
            mid-propagation (transient dependency wave from the 0878dcc push)
HelmReleases: all Ready; tempo HR PRUNED (gone)
Certs:      wildcard-tls Ready (letsencrypt-PRODUCTION) · trust-manager, barman-cloud-{client,server}, op-connect-tls Ready
Workloads:  no pods outside Running/Completed
freshrss:   app 1/1 + CNPG 3/3 Running. CNPG PDBs live (freshrss-dev-cluster maxUnavail N/A minAvail 1;
            -primary allowed-disruptions 0). New app PDB + RQ + LimitRange NOT yet applied (freshrss ksz still catching up to 0878dcc).
PVCs:       authentik/freshrss CNPG on local-path; freshrss app + monitoring on iscsi; storage-tempo-0 (30Gi) STALE — manual delete.
CNPG:       authentik-dev-cluster 3/3 Ready · ContinuousArchiving=False (R-8, expected post-R2-decommission)
```

Notable:

- **freshrss bundle committed but not yet reconciled** — verify after the wave settles: `kube dev get resourcequota,limitrange,pdb -n freshrss` should show `freshrss`, `freshrss-defaults`, and the app `freshrss` PDB.
- **CNPG manages its own PDBs** — confirms the app-only PDB selector (`app=freshrss`) was the correct scope.
- **Tempo HR pruned**, but `storage-tempo-0` (30Gi iscsi) lingers — manual delete cascades to the TrueNAS zvol (`RECLAIM_POLICY: Delete`).
- **Every CNPG PVC still `local-path`** — the S-tier gap.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| ~~C-2~~ | ~~Wildcard cert on staging~~ | ✅ Done 2026-05-16 | `_lib/networking/gateway/tls.yaml` | — |

(No open CRITICAL items — the Authentik archiving gap is R-8, an accepted dev gap pending the storage sprint.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies | ✅ Live (authentik, freshrss, homer, docs-site) | `_lib/security/cilium-network-policies/` | Follow-up: tighten `world:443` egress to `toFQDNs` once L7 DNS policy is on. |
| H-3 | Falco | ❌ Disabled — **next sprint** | `_lib/controllers/kustomization.yaml` (`#  - ./falco`) + `_lib/security/kustomization.yaml` (`#- ./falco-rules`) | Runtime detection is the missing layer. ~½ day. Decide CRD-ownership first (Q1): HR uses `crds: CreateReplace` vs the repo's separate `crds` layer. Also: `falco-rules/kustomization.yaml` is an empty stub; `security` ns `namespace.yaml` is commented out of the falco kustomization; falcoctl egress must be allowed past default-deny. Verify eBPF (`modern_ebpf`) loads on Talos + ServiceMonitor scrapes. |
| H-4 | ResourceQuotas + LimitRanges | 🟡 Partial — **freshrss done** (`0878dcc`) | `_lib/applications/freshrss/base/{limitrange,resourcequota}.yaml` | Backfill the pattern to **authentik** (no quota/limits; CNPG pods unbounded), **homer**/**docs-site** (per-container limits set but no namespace LimitRange/Quota). Seed from `kube dev top pod -n <ns>`. |
| H-5 | Trivy operator | ❌ Empty dir (deprioritized below Falco) | `_lib/security/trivy/` + `_lib/security/kustomization.yaml` (`#- ./trivy`) | Populate trivy-operator HR, wire reports → Prometheus/Grafana. |

### Performance / capacity (from perf eval)

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| P-1 | No `metricRelabelings` → apiserver scrape cardinality | ❌ | Drop `apiserver_request_duration_seconds_bucket` / `apiserver_response_sizes_bucket` via `metricRelabelings` on the apiserver/kubelet monitors. Biggest memory lever vs. Prometheus' 2Gi cap. |
| P-2 | App resource requests/limits missing | 🟡 freshrss now covered by its LimitRange | Authentik server+worker still set none. Set explicit requests/limits (or rely on a namespace LimitRange once H-4 backfilled). |
| P-3 | Kyverno mutation webhook on every pod CREATE | ⚠️ | `add-safe-to-evict`/`disable-service-links` match all Pods, single-replica admission → admission latency. Scope to app namespaces and/or 2 admission replicas. |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~R-1~~ | ~~PodDisruptionBudgets~~ | ✅ Done where it matters (`0878dcc`) | freshrss app PDB added; CNPG ships its own DB PDBs (verified live). homer/docs-site stateless single-replica → skip. |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate yet. |
| ~~R-7~~ | ~~`terminationGracePeriodSeconds`~~ | ✅ Done freshrss (`0878dcc`) | Optional follow-up: authentik server/worker. |
| R-8 | Authentik CNPG archiving erroring (R2 decommissioned) | 🟡 Accepted dev gap | Interim (cheap): strip dead barman-cloud config — `_lib/applications/authentik/overlays/dev/{ob-archiver.enc.yaml,database.yaml}` + `base/external-secret.yaml` (`authentik-r2-creds`) — to stop `archive_command` errors + unbounded WAL on the 2Gi WAL PVC. Real backup = S-tier. `ob-archiver.enc.yaml` is SOPS — needs explicit OK to edit. |

### Observability follow-ups

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~O-4~~ | ~~K8s events → Loki~~ | ✅ Done (`8735a38`) | — |
| O-5 | Cilium Gateway hardening | ❌ | Strip `Server`/`X-Powered-By`, body-size limits, rate limiting on exposed HTTPRoutes (grafana/freshrss/authentik/homer/docs-site). |
| O-6 | Periodic posture scans | ❌ | `popeye` + `kubescape` CronJobs → Loki. |
| ~~O-7~~ | ~~Alertmanager routing~~ | ✅ Done (`67fcd52`) | Follow-up: app rules (cert expiry, PVC near-full, **CNPG ContinuousArchiving=False** — would auto-surface R-8). |
| O-8 | Default-deny CCNP | 🟡 Per-app default-deny landed | Add a cluster-wide default-deny CCNP for fail-closed on unlabeled namespaces (Q4). |
| O-9 | App-level dashboards/alerts | ❌ | Flip Authentik `serviceMonitor.enabled: true`; add freshrss/authentik dashboards. |

### Homer / docs-site follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount as `emptyDir`, flip to RO. |
| HM-2 | Homer service-tile content | ❓ Verify | `_lib/applications/homer/base/configmap.yaml` | Confirm tiles list live hosts incl. docs-site (`dev.int.docs`). |
| DS-1 | docs-site living-scaffold pages are manual | ⚠️ | `_docs/status.md`, `_docs/roadmap.md` | Refresh when apps land. |

### Storage migration (S-tier — from `storage-strategy-decision.md`)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| S-1 | Snapshot infrastructure | ❌ Absent | `global/crds/`, `_lib/storage/freenas-csi/` | Add external-snapshotter CRDs + snapshot-controller, enable democratic-csi snapshotter sidecar, create `VolumeSnapshotClass`. Verify a manual snapshot. **Blocks S-2.** |
| S-2 | CNPG → single-instance static iSCSI zvol | ❌ Not started | `_lib/applications/{authentik,freshrss}/overlays/dev/` | Pre-create zvols + static `Retain` PVs; CNPG `instances:1`; static `pvcTemplate.volumeName`. Verify operator `0.27.0` honors `volumeName` on a throwaway cluster first. (Q2: authentik first — broken backup — vs freshrss first — lower stakes.) |
| S-3 | Retire R2/S3 from CNPG path | 🟡 IaC removed; runtime still references it (R-8) | authentik overlay | Removing dead barman-cloud manifests = R-8; snapshot replacement = S-2. |
| S-4 | iscsi StorageClass reclaim default | ⚠️ `Delete` | `_clusters/dev/config/cluster-configs.yaml` (`RECLAIM_POLICY`) | Flip to `Retain` so accidental dynamic iscsi volumes survive PVC deletion. |
| S-5 | freshrss CNPG has no backup | ⚠️ Gap | `_lib/applications/freshrss/overlays/dev/database.yaml` | Resolved by S-2 VolumeSnapshot ScheduledBackup. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| Stale Tempo PVC | `monitoring/storage-tempo-0` (30Gi iscsi) | `kube dev -n monitoring delete pvc storage-tempo-0` (HR already pruned; cascades to TrueNAS zvol). |
| CryptPad TrueNAS zvol | `dev-cryptpad-data-pvc` | ❓ Confirm destroyed. |
| ADR-0005 Thoth descope | `_docs/decisions/0005…` | Update Draft → reflect "no full app; utilities/scripts only" (user, 2026-05-22). |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| TF-CoreDNS | Apply CoreDNS split-horizon inlineManifest | ⚠️ Committed (`8b3af1f`), apply unverified | `/terraform-plan` → `/terraform-apply` (interactive 1P). A rebuild without applying reverts the live DNS fix. |
| ~~TF-wallabag~~ | ~~Destroy dead wallabag S3 stack~~ | ✅ Done — IaC removed (`eb3faf0`); S3 bucket + IAM destroyed (confirmed 2026-05-22) | — |
| R1 | Collapse `pve.tf` cp/worker duplication | 🟡 Partial | Module extracted (`eb3faf0`). Verify cp/worker dup *within* `pve.tf` collapsed. |
| R2 | Extract shared Talos machine config | 🟡 Partial | Same extraction. Verify worker CP-only PSA exemptions. |
| R5 | Worker memory typo `8092` | ⚠️ | `terraform/dev/variables.tf` + `terraform.tfvars` — tidy next tfvars edit. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Pairs with Proxmox HA for power-blip recovery. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh`; not in Flux. |
| SSO public exposure (Phase 4) | ⏸️ Not started | Cloudflare Tunnel + forward-auth outposts; WAF terraform not built. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — descoped (user, 2026-05-22): no full app; focus on utilities/scripts + iterating existing infra. Update ADR-0005 to match (hygiene item above).

**docs-site** — ✅ Live. Polish = DS-1.

**GPU sharing** — pre-decision (`_docs/decisions/0004…`), single-node VFIO passthrough on HP Slim S01.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **H-3 — enable Falco** (the evaluated next security tool). Resolve the CRD-ownership decision (Q1) first, then enable + verify eBPF on Talos + ServiceMonitor scrape.
2. **P-1 + R-8 quick wins** — apiserver `metricRelabelings` (cheap memory win) and strip the dead Authentik R2 barman-cloud config (stops archiving errors). Plus delete the stale Tempo PVC and ADR-0005 Thoth descope.
3. **H-4 backfill** — extend the freshrss quota/LimitRange pattern to authentik/homer/docs-site.
4. **Storage S-tier — its own sprint** (S-1 → S-2 → S-4) — the real backup capability R-8 defers to.
5. **O-5/O-6/O-9** gateway hardening + posture scans + app dashboards; terraform R1/R2/R5 verification.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `_lib/applications/freshrss/base/{limitrange,resourcequota,pdb}.yaml` | H-4/R-1 resilience primitives (`0878dcc`) |
| `_lib/applications/freshrss/base/deployment.yaml` | R-7 `terminationGracePeriodSeconds:45` |
| `.claude/commands/sprint-menu.md` | New `/sprint-menu` session picker |
| `_lib/applications/authentik/overlays/dev/{ob-archiver.enc.yaml,database.yaml}` | R-8 — barman-cloud archiving targets destroyed R2 bucket |
| `_lib/controllers/kustomization.yaml` + `_lib/security/kustomization.yaml` | Falco commented (H-3) |
| `_lib/observability/{kustomization.yaml,alloy/configmap.yaml,kube-prometheus-stack/helmrelease.yaml}` | Tempo removed, O-4 events, Grafana SSO-only |
| `_clusters/dev/config/cluster-configs.yaml` | `RECLAIM_POLICY: Delete` (S-4) |
| `_docs/storage-strategy-decision.md` | S-tier — backup capability R-8 defers to |
| `_docs/reviews/home-0ps-review-2026-05-20.md` | Prior distinct review — superseded |
