# home-0ps.com Review — 2026-05-29

> Generated: 2026-05-29 (`/lab-review`). Supersedes `home-0ps-review-2026-05-28.md`.
> Scope: Live `memphis` dev cluster — Flux applied revision `0a47a77` (one tick behind branch tip `b5e71cb`; reconcile pending for the kromgo configMapGenerator refactor).
> Trigger: **A heavy observability+CI day.** Three baseline items closed (F-1+F-2+F-3, O-7 remaining alerts), six new fixes shipped (PVCNearFull template, kromgo end-to-end, flux scrape rewrite, CI lint workflow). **13 non-merge commits + 2 PR merges since baseline.**

---

## Executive Summary

The day's headline: **kromgo live cluster-stat badges shipped in README.md, the verification flushed out two latent observability bugs that had silently been costing us alerting coverage, and a CI gate now blocks the class of bug that started the cascade.**

The kromgo rollout was the trigger:
- **kromgo HelmRelease + initial config + 10 PromQL endpoint badges in `README.md`** (`11f008e`) — Prometheus → shields.io endpoint proxy fronted by cloudflared at `dev-kromgo.home-0ps.com`. Public CNAME + tunnel ingress + Cloudflare rate-limit ruleset extended to cover both hostnames (terraform/cloudflare-tunnel applied successfully).
- **Verification surfaced a 3-of-10 PromQL miss** (`cf2558c`): bjw-s's reference config filters node-exporter on `{kubernetes_node!=""}`; this lab's node-exporter targets don't carry that label, so CPU/Memory/Uptime returned "no data". Selector dropped.
- **Verification also surfaced the bigger find** (`56df0f2`): the flux `ServiceMonitor` had three independent defects and had been silently matching zero pods since the cluster bootstrapped 4 days ago — `flux_*` / `gotk_*` series were entirely absent. Replaced with a `PodMonitor` scraping all four controllers directly on `:8080/http-prom`. The `FluxKustomizationNotReady` / `FluxHelmReleaseNotReady` alerts shipped via O-7 now actually have data to evaluate against.
- **Kromgo's no-reload behavior was the third gotcha** (`b5e71cb`): kromgo reads `/kromgo/config.yaml` once at startup, ignores filesystem updates. The `cf2558c` fix landed in the ConfigMap via Flux, propagated to the pod's mount, and the running process still served the old config. Refactored to a kustomize `configMapGenerator` with the default name-suffix hash — every config edit produces a new ConfigMap name, kustomize rewrites the Deployment's volume reference, rollout is automatic. No Stakater Reloader needed.

The CI gate (`6931fa8` + `3384cae` + `e7c2c9d`): **`promtool check rules`** on every PR + push, catching Sprig template functions (`mul`, `div`, `add`, `default`) that parse-pass YAML lint + CRD schema but fail at the Prometheus Operator's mutating webhook. The PVCNearFull `(mul $value 100)` Sprig-ism shipped via O-7 (PR #50) on 2026-05-28 and only surfaced 2026-05-29 when Flux re-applied during the kromgo reconcile (`11f008e`), blocking the whole observability layer until fix (`8a7a6f7`). The new workflow also runs yamllint — extended ignore list for `_hack/`, `.venv-docs/`, `**/.sops.yaml`, and 6 explicitly-named SOPS-encrypted YAMLs that don't follow the `*.enc.yaml` naming convention; ~10 trivial trailing-blank-line nits fixed in-place. Local `/lint` and CI now behave identically.

Baseline catch-up: **F-1 + F-2 + F-3 closed** via PR #49 (FALCO-BUNDLE — custom-rules mounted, falcosidekick UI + Redis disabled, `modern_ebpf` verified). **O-7 remaining alerts closed** via PR #50 (cert expiry tiers + PVC near-full + Gatus endpoint-down).

Live state is healthy: **6 nodes Ready** (Talos `v1.12.8` / k8s `v1.35.0`, ~4d4h), **17 Flux Kustomizations Ready at `0a47a77`**, **17 HelmReleases Ready**, no pods outside Running/Completed, 3 certs Ready (wildcard on letsencrypt-**production**), **3 CNPG clusters single-instance** (all 1/1), **10 VolumeSnapshots ReadyToUse** (daily snaps firing for all 3 — authentik 04:30 / freshrss 04:00 / gatus 05:00; gatus's missing-snapshot worry from the 2026-05-28 review resolved itself), 3 dump CronJobs scheduled.

Two TargetDown alerts firing: **authentik-server-metrics** and **authentik-worker-metrics** — the O-9 ServiceMonitor is in `monitoring/authentik` but the chart-side metrics services in `authentik/` are unreachable. Captured as **O-17**.

**Recommended next sprint:** **O-15 KSM label allowlist + `flux_version` PromQL rewrite** (15 min — closes the last broken kromgo badge) + **O-17 authentik scrape repair** (resolves the TargetDown firing) + **O-10 postgres-exporter** (now possible since the KSM allowlist work overlaps with the per-CNPG scrape pattern).

---

## Section 1 — What Changed Since 2026-05-28

| Area | 2026-05-28 state | 2026-05-29 state |
| ---- | ---------------- | ---------------- |
| **kromgo (NEW)** | — | ✅ Live: 10 PromQL endpoints, configMapGenerator-driven rollouts, public via cloudflared at `dev-kromgo.home-0ps.com`, rate-limited. 9/10 metrics rendering on README badges. `flux_version` open (O-15). |
| **Flux scrape (O-13)** | ❌ ServiceMonitor matched zero pods (3 independent defects); zero `flux_*`/`gotk_*` series cluster-wide for the entire prior install | ✅ PodMonitor scraping all 4 controllers (`up=1` × 4) — O-7's FluxKustomizationNotReady / FluxHelmReleaseNotReady alerts now have data |
| **PrometheusRule CI gate (O-12)** | ❌ No promtool validation; PVCNearFull Sprig-ism slipped through PR #50 | ✅ `.github/workflows/lint.yml` — yamllint + `promtool check rules` on every PR + push to `dev` |
| **PVCNearFull alert** | ❌ Broken (`mul` undefined) — blocked entire observability layer reconcile | ✅ Fixed (`humanizePercentage`) — `8a7a6f7` |
| **Falco (F-1+F-2+F-3)** | 🟡 DS live but custom-rules unmounted; UI + Redis shipping by default; `modern_ebpf` unverified | ✅ All closed (PR #49) — custom-rules mounted, UI + Redis off (orphan PVC remains), `modern_ebpf` loaded |
| **O-7 remaining alerts** | 🟡 Partial (CNPG done; cert/PVC/Gatus still open) | ✅ Done (PR #50) — cert expiry (2 tiers) + PVC near-full + GatusEndpointDown |
| **YAML linting in CI** | ❌ `/lint` slash-command only (advisory) | ✅ yamllint job in `lint.yml`; ignore list extended; baseline nits fixed in-place |
| **kubectl wrapper docs** | In `README.md` | ✅ Moved to `_docs/kubectl-wrapper.md` |
| **README badges** | Live status table + tech-stack badges | ✅ + `## Cluster` block (10 kromgo endpoint badges); architecture badges filled out (Falco, Loki, Gatus, Trivy, Alloy, Helm, Authentik, SOPS); status-page badge fixed to markdown link |
| **Cloudflare Tunnel ingress** | Gatus only (`dev-status`) | + kromgo (`dev-kromgo`); rate-limit ruleset matches both via `http.host in {...}` |
| **PodMonitors live** | 4 (authentik, freshrss, gatus, tailscale-operator) | 5 (+ flux-system) — tailscale-operator one has historically matched zero targets (worth a check) |
| **VolumeSnapshots ReadyToUse** | 7 | 10 (3 new daily snaps on 2026-05-29) |
| **Dev tip** | `56277b1` | `b5e71cb` (13 non-merge commits + 2 PR merges since baseline) |

---

## Section 2 — Live Cluster Snapshot (2026-05-29, applied rev `0a47a77`)

```
Nodes:        6 Ready — 3 cp + 3 worker — Talos v1.12.8 / k8s v1.35.0 — ~4d4h
Flux:         17 Kustomizations Ready at 0a47a77; gitrepo artifact at 0a47a77
              (branch tip is b5e71cb — kromgo configMapGenerator reconcile pending)
HelmReleases: 17, all Ready — falco 8.0.0 (now slim); cnpg 0.27.0; cnpg-crds 1.28.0;
              kps 78.0.0; authentik 2026.2.3; kyverno 3.7.0; cert-manager v1.19.3;
              democratic-csi 0.15.0 (both freenas + local-path); external-dns 1.19.0
              (v0.8.2 webhook).
Certs:        wildcard-tls (letsencrypt-PRODUCTION), trust-manager-tls, op-connect-tls — Ready.
Workloads:    no pods outside Running/Completed.
Falco:        DaemonSet 6/6 Ready (2/2 containers per pod — custom-rules sidecar mounted);
              falcosidekick (1) + k8s-metacollector (1) — all Running, 9h old.
              NO falcosidekick-ui pod, NO redis StatefulSet (F-2 closed).
CNPG:         3 clusters — authentik 1/1, freshrss 1/1, gatus 1/1 (all single-instance,
              static iSCSI PVs). PodMonitors live for all three. Daily snapshots firing.
kromgo:       1 Deployment Ready, 1 ConfigMap, 1 Service, 1 HTTPRoute — public via
              cloudflared at dev-kromgo.home-0ps.com. 9/10 PromQL endpoints returning
              real data; `flux_version` "No Data" (O-15).
ServiceMonitors: 16 (no change from baseline +1 onepassword-connect was already counted).
PodMonitors:  5 — authentik-dev-cluster, freshrss-dev-cluster, gatus-dev-cluster,
              tailscale-operator (historically empty — needs a look), flux-system (NEW).
Snapshots:    VolumeSnapshotClass freenas-iscsi (Retain). 10 ReadyToUse:
              - authentik: snap-20260527, snap-20260528, snap-20260529 (109m), test-backup-1
              - freshrss:  snap-20260527, snap-20260528, snap-20260529 (139m), test-backup-1
              - gatus:     snap-20260529-050000 (79m, FIRST scheduled snap), test-backup-1
ScheduledBackups: authentik (30 4 * * *) + freshrss (0 4 * * *) + gatus (0 5 * * *),
              method volumeSnapshot — all firing.
PVCs:         All Retain.
              - CNPG data on static iSCSI zvols (dev-{authentik,freshrss,gatus}-db-pv, 10Gi).
              - Dumps-pvc per app (20Gi iscsi).
              - prom 50Gi / grafana 5Gi / alertmanager 5Gi all iscsi.
              - ORPHAN: security-falco-falcosidekick-ui-redis-data (1Gi iscsi) — F-2 disabled
                the StatefulSet but Retain policy kept the PVC. Captured as Hyg-2.
StorageClass: iscsi (default, Retain); local-path (default, Retain).
Active alerts: 3 firing — Watchdog (heartbeat, expected), TargetDown × 2 (authentik-server-metrics,
              authentik-worker-metrics). See O-17.
```

Notable:

- **kromgo is the day's headline addition.** Pattern proven end-to-end: Prometheus → shields.io endpoint proxy → cloudflared tunnel → README badges. Reusable pattern for any future cluster-stat exposure. Note the configMapGenerator approach (b5e71cb) — applies broadly any time we need a runtime config to auto-rotate without Reloader.
- **The flux scrape repair (O-13) is the most impactful invisible fix today.** The PodMonitor swap means O-7's two flux alerts now actually evaluate. Going forward, the cluster has working alerting on Flux reconciliation failures for the first time in 4 days.
- **TargetDown × 2 firing on authentik metrics** — O-9's ServiceMonitor (`monitoring/authentik`) is selecting `authentik-server-metrics` + `authentik-worker-metrics` services, but they're not reachable. Either the services aren't exposed (chart needs `metrics.serviceMonitor.enabled: true` to also expose the targets), or the endpoint slice is empty (no backing pods labeled correctly). Captured as O-17.
- **Falco PVC orphan** — `security-falco-falcosidekick-ui-redis-data` (1Gi) remains Bound on iSCSI because the SC is Retain and the StatefulSet was descoped without manual cleanup. PV stays consumed but unused. Captured as Hyg-2.
- **Tailscale-operator PodMonitor** has existed 4d3h with zero targets — its selector likely matches nothing. Captured as O-18.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

(No open CRITICAL items.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| ~~F-1~~ | ~~Falco custom-rules ConfigMap not mounted~~ | ✅ Done 2026-05-28 (`c492d45`, PR #49) | `_lib/controllers/falco/helmrelease.yaml` | `mounts.volumes` + `volumeMounts` wired; DS now 2/2 containers (custom-rules sidecar). |
| ~~F-2~~ | ~~Audit falcosidekick UI + Redis surface~~ | ✅ Done 2026-05-28 (`c492d45`, PR #49) — Hyg-2 orphan PVC follows on | `_lib/controllers/falco/helmrelease.yaml` | `falcosidekick.webui.enabled: false` + `falcosidekick.config.redis.*` disabled. UI gone, Redis StatefulSet gone. PVC orphan remains (Hyg-2). |
| ~~F-3~~ | ~~Verify Falco `modern_ebpf` driver loading~~ | ✅ Done 2026-05-28 (`c492d45`) | — | Confirmed via logs (PR #49 description). |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy is on. Consult [[cilium-gateway-egress-l7-filter]] before narrowing anything Gateway-routed. |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. |
| O-5 / G2-2 | Cilium Gateway hardening + public-surface hardening | 🟡 Rate-limit done (both `dev-status` + `dev-kromgo` covered); headers/WAF still open | exposed HTTPRoutes + public hostnames | Strip `Server`/`X-Powered-By`, body-size limits on the Gateway listeners; Cloudflare managed WAF rules. |

### Performance / capacity

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~P-1..P-4~~ | (all closed in prior cycles) | ✅ | — |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |

### Observability follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| O-5 | Gateway + public-surface hardening | 🟡 (rate-limit done; headers/WAF open — see HIGH) | — | — |
| O-6 | Periodic posture scans | ❌ | — | `popeye` + `kubescape` CronJobs → Loki. |
| ~~O-7~~ | ~~Follow-up app alerts~~ | ✅ Done 2026-05-29 (`df2c03a`, PR #50; PVCNearFull patched in `8a7a6f7`) | `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml` | All 4 alerts live: CNPGBackupStale, CNPGDumpCronJobStale, CertExpiringSoon (2 tiers), PVCNearFull (2 tiers), GatusEndpointDown. **Now FluxKustomizationNotReady / FluxHelmReleaseNotReady actually evaluate** thanks to O-13. |
| O-8 | Default-deny CCNP (cluster-wide fail-closed) | 🟡 Per-app default-deny landed | — | Add cluster-wide default-deny for unlabeled namespaces (Q4). |
| ~~O-9~~ | ~~App-level dashboards/alerts~~ | ✅ ServiceMonitor + 4 dashboards live | `_lib/observability/kube-prometheus-stack/{servicemonitor-authentik.yaml, dashboards/}` | But: ServiceMonitor's targets are TargetDown — see O-17. |
| O-10 | **App-data dashboards in Grafana** (postgres-exporter) | ❌ Open | `_lib/observability/` (postgres-exporter HR or per-CNPG sidecar) | 3 CNPG clusters now (authentik/freshrss/gatus); pattern should be shared. Mind [[cilium-gateway-egress-l7-filter]] — exporters need explicit CCNP egress to the target CNPG on 5432. Pairs well with O-15 KSM allowlist work (touching the same HelmRelease). |
| ~~O-11~~ | ~~Gatus endpoint statuses in repo README~~ | ✅ Done 2026-05-28 (`6f51280`) | `README.md` | — |
| ~~O-12~~ | ~~PR CI lacks PromQL alert-template validation~~ | ✅ Done 2026-05-29 (`6931fa8`+`3384cae`+`e7c2c9d`) | `.github/workflows/lint.yml` | promtool job + yamllint job, both green on `e7c2c9d`. |
| ~~O-13~~ | ~~Flux controllers had never been scraped~~ | ✅ Done 2026-05-29 (`56df0f2`) — `up=1` × 4 | `_lib/observability/kube-prometheus-stack/podmonitor-flux.yaml` | — |
| O-14 | Adapt third-party reference configs to local conventions | ❌ Open | `.claude/rules/` (proposed) | Codify a rule: spot-check label vocabularies against this cluster's actual series before merging any community-sourced PromQL / dashboards / scrape configs. Triggered by O-12 (Sprig-isms) and O-15 (`flux_instance_info` doesn't exist here). |
| **O-15** | **`flux_version` kromgo badge "No Data"** — KSM label allowlist needed | ❌ **Open — top of next sprint** | `_lib/observability/kube-prometheus-stack/helmrelease.yaml` (KSM values) + `_lib/observability/kromgo/config/config.yaml` (`flux_version` query) | bjw-s's `flux_instance_info` is a flux-operator addon metric we don't run. Vanilla Flux emits only operational metrics. **Tomorrow:** (1) `kube-state-metrics.metricLabelsAllowlist: ["pods=[app.kubernetes.io/version,app.kubernetes.io/part-of,app.kubernetes.io/component]"]` on the kps HR — exposes `kube_pod_labels` with `label_app_kubernetes_io_version` for every workload. (2) Rewrite kromgo query: `label_replace(max by (label_app_kubernetes_io_version) (kube_pod_labels{namespace="flux-system",label_app_kubernetes_io_part_of="flux"}), "revision", "$1", "label_app_kubernetes_io_version", "v(.+)")` — returns suite version (`2.8.8`) not the source-controller image tag (`1.8.5`). 15min change + verify. |
| ~~O-16~~ | ~~Kromgo ConfigMap edits silently no-op until pod restart~~ | ✅ Done 2026-05-29 (`b5e71cb`) | `_lib/observability/kromgo/kustomization.yaml` (configMapGenerator) | — |
| **O-17** | **TargetDown firing × 2 on authentik metrics scrape** | ❌ **NEW** | `_lib/observability/kube-prometheus-stack/servicemonitor-authentik.yaml` + `_lib/applications/authentik/overlays/dev/` | ServiceMonitor selects `authentik-server-metrics` + `authentik-worker-metrics` services but Prometheus reports them down. Likely either (a) chart `metrics.serviceMonitor.enabled: false` is suppressing the metrics services themselves, (b) services exist but have no endpoints (backing pod label mismatch), or (c) network policy blocking. **Next action:** `kube dev -n authentik get svc | grep metrics` then `kube dev -n authentik describe ep <svc>` to see what's actually exposed. 30min triage. |
| **O-18** | **tailscale-operator PodMonitor has 0 targets (4d3h old)** | ❓ **NEW — needs triage** | `tailscale` namespace, ts-operator chart | PodMonitor exists since cluster bootstrap, never matched a pod (no `up{}` series). Either selector mismatch or operator pods don't expose metrics. Quick check: `kube dev -n tailscale get podmonitor -o yaml` + `kube dev -n tailscale get pod --show-labels`. |

### Homer follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |

### Storage migration (S-tier — **COMPLETE**)

> ADR-0003 implemented end-to-end (commits `328148f` → `d5c5ca2`, 2026-05-26 evening).

| ID | Item | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~S-1..S-6~~ | (all closed) | ✅ | 3 CNPG clusters; both rip cords validated; daily snaps firing for all 3 as of 2026-05-29. |

### Sprint orchestrator

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| ~~SO-1~~ | ~~`/sprint-orchestrate` parallel sprint executor~~ | ✅ Done | — | Drove 3 baseline items 2026-05-28; not re-exercised today (single-thread session). |
| SO-2 | First-run polish | 🟡 Open | `.claude/commands/sprint-orchestrate.md` | Document session-limit-mid-task recovery + cherry-pick recovery path. |
| SO-3 | Sprint-state.json schema versioning | 🟡 Open | `.claude/sprint-state.json` (gitignored) | Add `"schema_version"` field. |

### Hygiene / cleanup

| ID | Item | Location | Action |
| -- | ---- | -------- | ------ |
| Hyg-1 | Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |
| **Hyg-2** | **Orphan Falco Redis PVC** (NEW) | `security/security-falco-falcosidekick-ui-redis-data-...` | F-2 disabled the StatefulSet but Retain policy kept the 1Gi iSCSI PVC. `kube dev -n security delete pvc <name>` after confirming PV mode — manual one-shot. |
| Hyg-3 | yamllint baseline warnings on `#applications` / `#observability` headers | `_clusters/dev/config/cluster-configs.yaml` + `_clusters/production/...` | 3 `comments` warnings — add space after `#` or drop the section headers. Non-blocking (CI doesn't run `--strict`). |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| I-1 | Talos `kubernetes_version` pinned to v1.12.8 | ⚠️ Open | `terraform/dev/`. Revisit when upstream supports 1.36.0 cleanly. |
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
| Hyg-2 PVC cleanup | ❓ Pending | See Hyg-2. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — ✅ Descoped (ADR-0005). No change.

**docs-site** — 🗑️ Retired 2026-05-26. No change.

**Gatus** — ✅ Live + hardened + persistent. Daily snapshots firing as of 2026-05-29 (the missing-snap concern from 2026-05-28 review resolved).

**Cloudflare Tunnel** — ✅ Live (G0) + rate-limited; now fronts both Gatus and kromgo.

**GPU sharing** — pre-decision (ADR-0004) unchanged.

**Falco** — ✅ Live + slimmed (H-3 + F-1+F-2+F-3 all closed). DS 6/6 with custom-rules sidecar; UI + Redis off. Orphan PVC tracked as Hyg-2.

**kromgo** — ✅ Live (NEW). 10 PromQL endpoint badges in README; 9/10 rendering. `flux_version` open as O-15.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **O-15 + O-17 + O-18 — observability cleanup bundle** (90 min). KSM label allowlist + kromgo `flux_version` query rewrite; authentik TargetDown triage; tailscale-operator PodMonitor sanity check. Closes the visible "broken badge" + the firing alerts in one PR. Natural cut.
2. **O-10 postgres-exporter** (multi-day). Three CNPG clusters now warrant a shared exporter pattern. Mind [[cilium-gateway-egress-l7-filter]] for CCNPs. Pairs with O-15 because both touch the kps HelmRelease.
3. **O-14 — codify the "audit community configs" rule** (15 min). One file in `.claude/rules/`. Pre-emptive against the next bjw-s/onedr0p copy-paste class of bug.
4. **Hyg-2 + Hyg-3 — quick housekeeping** (15 min). Delete orphan Redis PVC; fix the 3 cluster-config comment warnings.
5. **SO-2 + SO-3 sprint-orchestrator polish** — document recovery patterns + state-file schema versioning.
6. **H-5 Trivy** — populate the empty `_lib/security/trivy/` HR.
7. **I-1 Talos unpin + R5 memory typo + R1/R2 verify** — small Terraform housekeeping batch.
8. **O-5/O-6 + WAF managed rules** — gateway header stripping + posture scans + Cloudflare WAF on public hostnames.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `_lib/observability/kromgo/config/config.yaml` | NEW — 10 PromQL metric definitions; the canonical place to add/edit cluster-stat badges. |
| `_lib/observability/kromgo/kustomization.yaml` | NEW — configMapGenerator + name-suffix hash; reference pattern for any future ConfigMap-driven runtime config that needs auto-rollout. |
| `_lib/observability/kromgo/deployment.yaml` | NEW — kromgo Deployment, points at `prometheus-operated.monitoring.svc:9090`. |
| `_lib/observability/kromgo/{service,httproute}.yaml` | NEW — internal Cilium Gateway route at `dev.int.kromgo.home-0ps.com`. |
| `_lib/observability/kube-prometheus-stack/podmonitor-flux.yaml` | NEW — replaces broken `servicemonitor-flux.yaml`. Scrapes all 4 Flux controllers on `:8080/http-prom`. |
| `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml` | O-7 closed (cert/PVC/Gatus alerts shipped); PVCNearFull `mul $value 100` → `humanizePercentage $value` fix landed `8a7a6f7`. |
| `_lib/security/cilium-network-policies/kromgo-{default-deny,allow}.yaml` | NEW — scoped to `app: kromgo` (not whole monitoring ns); cloudflared-allow extended with kromgo backend. |
| `_lib/controllers/falco/helmrelease.yaml` | F-1+F-2+F-3 closed; UI + Redis disabled; custom-rules mounted; `modern_ebpf` verified. |
| `terraform/cloudflare-tunnel/main.tf` | Tunnel ingress + DNS extended for `dev-kromgo`; rate-limit ruleset matches both hostnames via `http.host in {...}`. Applied successfully. |
| `_clusters/dev/config/cluster-configs.yaml` | `KROMGO_VERSION` + `KROMGO_SUBDOMAIN` added. |
| `.github/workflows/lint.yml` | NEW — yamllint + `promtool check rules` on every PR + push. Closes O-12. |
| `.yamllint.yaml` | Ignore list extended: `_hack/`, `.venv-docs/`, `**/.sops.yaml`, 6 explicit SOPS files, `_lib/storage/local-path/helmrelease.yaml`. |
| `_docs/kubectl-wrapper.md` | NEW — kubectl wrapper docs moved out of README. |
| `README.md` | NEW `## Cluster` block (10 kromgo badges); architecture badges expanded; status badge fixed to markdown link form. |
| `_docs/reviews/home-0ps-review-2026-05-28.md` | Prior baseline. O-12, O-13, O-16 carry forward as ✅; O-15, O-17, O-18, Hyg-2, Hyg-3 are new. |
