# home-0ps.com Review — 2026-05-28

> Generated: 2026-05-28 (`/lab-review`). Supersedes `home-0ps-review-2026-05-27.md`.
> Scope: Live `memphis` dev cluster — Flux currently at applied revision `6f51280` (one tick behind branch tip `56277b1`; reconcile pending for the O-9 changes).
> Trigger: **Three sprint items landed today via `/sprint-orchestrate` (new orchestrator tooling) — H-3 Falco, O-11 README badges, O-9 Authentik metrics + 4 dashboards** — plus a brief mid-flight git incident (PRs #46/#47 merge commits were force-clobbered from `dev`, recovered via `cherry-pick -m 1`). New project rule shipped to guard against repeat. **8 non-merge commits + 2 PR merges since baseline.**

---

## Executive Summary

The orchestrator pattern came online and shipped three of the previously-deferred items in one day:
- **H-3 Falco** (top security item, ~5 cycles deferred) is **LIVE** — 6 DaemonSet pods Running, ServiceMonitor scraped, `crds: Skip` on the HR (Falco 8.0.0 ships no CRDs; CRD-ownership rule vacuously satisfied; well-commented in the HR).
- **O-11 Gatus status badges** is **MERGED** — `README.md` now surfaces a `## Live status` block with both shields.io endpoint badges (Status) + direct Gatus SVG (Uptime 7d) for all 6 endpoints. Stale Syncthing row removed; bonus fix in `.claude/rules/kube-wrapper.md` (stern example swapped to freshrss).
- **O-9 Authentik metrics + 4 dashboards** is **MERGED in dev** (`e08f08a`), Flux **not yet reconciled**. Dashboards (authentik/cloudflared/gatus/freshrss) and `servicemonitor-authentik` will appear on the next reconcile tick. Centralised SM-ownership pattern matches Falco.

Today also delivered the **`/sprint-orchestrate` parallel sprint executor** (commit `e750b7a`) — `.claude/commands/sprint-orchestrate.md` + `.github/workflows/sprint-accept.yml` + per-task `accept.sh` template + state-file pattern + `/sprint-menu` handoff. Three subagents drove the three items in isolated `/tmp/sprints/<id>` worktrees; the GHA workflow is now the per-PR merge gate.

A real incident: PR #46 (H-3) + PR #47 (O-11) merged on GitHub at 07:31Z/07:43Z but a subsequent local `git push` from stale `dev` rewrote `origin/dev` backward, clobbering both merge commits. Recovered via `git cherry-pick -m 1 9b6881f 290677a` → fast-forward push. New project rule **`.claude/rules/git-pull-before-commit.md`** codifies the guard (`git pull --ff-only` before any local commit on shared branches) with the incident as the cited *why*.

Live state is healthy: **6 nodes Ready** (Talos `v1.12.8` / k8s `v1.35.0`, ~3d18h), **17 Flux Kustomizations Ready at `6f51280`**, **17 HelmReleases Ready** (new: falco@8.0.0), no pods outside Running/Completed, 3 certs Ready (wildcard on letsencrypt-production), **3 CNPG clusters single-instance** (authentik / freshrss / gatus, all 1/1), **7 VolumeSnapshots** ReadyToUse (3 fresh 16h scheduled snaps for authentik+freshrss+gatus on 2026-05-28 + 4 older), 3 dump CronJobs scheduled.

**Recommended next sprint:** **F-1 (Falco custom-rules mount) + F-2 (audit falcosidekick UI/Redis surface)** — finish the H-3 follow-ups; then **O-7 remaining alerts** (cert expiry / PVC near-full / Gatus endpoint-down).

---

## Section 1 — What Changed Since 2026-05-27

| Area | 2026-05-27 state | 2026-05-28 state |
| ---- | ---------------- | ---------------- |
| **Falco (H-3)** | ❌ Disabled, ~5 cycles deferred | ✅ **LIVE** — 6 DS pods, ServiceMonitor scraped, `crds: Skip` (chart has none), custom-rules ConfigMap shipped but **not yet mounted** (F-1) |
| **Gatus README badges (O-11)** | ❌ Open | ✅ Merged — `## Live status` block, 6 endpoint badges (shields.io + Gatus SVG), Syncthing row removed |
| **App dashboards / Authentik SM (O-9)** | ❌ Open | 🟡 **Merged in dev; awaiting Flux reconcile.** authentik metrics flip + 4 dashboards (authentik/cloudflared/gatus/freshrss) + cross-ns ServiceMonitor |
| Sprint tooling | None | ✅ `/sprint-orchestrate` + `accept.sh` template + GHA `sprint-accept.yml` + state file |
| Falco footprint | n/a | ⚠️ Brought along falcosidekick + UI + Redis (stateful, 1Gi iSCSI PVC) — wider than the brief expected |
| External-dns-unifi-webhook | v0.8.1 | ✅ v0.8.2 (renovate PR #41) |
| Git workflow guard | unwritten | ✅ `.claude/rules/git-pull-before-commit.md` — pull `--ff-only` before commits on shared branches; cites 2026-05-28 clobber incident |
| Flux HelmReleases | 16 Ready | 17 Ready (new: `security/security-falco` @ 8.0.0) |
| ServiceMonitors live | 14 | 15 (new: `monitoring/falco`); `authentik` SM exists in `dev` but not yet applied |
| VolumeSnapshots | 4 ReadyToUse | 7 ReadyToUse (3 fresh 16h scheduled + 4 carried) |
| Dev tip | `d0f93cb` | `56277b1` (8 non-merge commits + 2 PR merges since baseline) |

---

## Section 2 — Live Cluster Snapshot (2026-05-28 AM, applied rev `6f51280`)

```
Nodes:        6 Ready — 3 cp + 3 worker — Talos v1.12.8 / k8s v1.35.0 — ~3d18h
Flux:         17 Kustomizations Ready at 6f51280; gitrepo artifact at 6f51280
              (branch tip is 56277b1 — Flux reconcile pending for e08f08a O-9 + rule docs)
HelmReleases: 17, all Ready — falco 8.0.0 (NEW); cnpg 0.27.0; cnpg-crds 1.28.0;
              kps 78.0.0; authentik 2026.2.3; kyverno 3.7.0; cert-manager v1.19.3;
              democratic-csi 0.15.0 (both freenas + local-path).
Certs:        wildcard-tls (letsencrypt-PRODUCTION), trust-manager, op-connect-tls — Ready.
Workloads:    no pods outside Running/Completed.
Falco:        DaemonSet 6/6 Ready (one pod per node); falcosidekick (1) +
              falcosidekick-ui (1) + falcosidekick-ui-redis (StatefulSet 1/1) +
              k8s-metacollector (1) — all Running, 10m old.
CNPG:         3 clusters — authentik 1/1, freshrss 1/1, gatus 1/1 (all single-instance,
              static iSCSI PVs). PodMonitors live for all three.
ServiceMonitors: 15 — including the new `monitoring/falco`. NO `monitoring/authentik` yet
              (O-9 awaits Flux reconcile).
Snapshots:    VolumeSnapshotClass freenas-iscsi (Retain). 7 ReadyToUse:
              - authentik: snap-20260527 (40h), snap-20260528 (16h fresh), test-backup-1 (43h)
              - freshrss:  snap-20260527 (40h), snap-20260528 (16h fresh), test-backup-1 (44h)
              - gatus:     test-backup-1 (14h, hand from N-6 smoke) — scheduled didn't fire?
ScheduledBackups: authentik (30 3 * * *) + freshrss (0 3 * * *) + gatus (0 0 5 * * *),
              method volumeSnapshot.
PVCs:         All Retain.
              - CNPG data on static iSCSI zvols (dev-{authentik,freshrss,gatus}-db-pv, 10Gi).
              - Dumps-pvc per app (20Gi iscsi).
              - NEW: security-falco-falcosidekick-ui-redis-data (1Gi iscsi) — stateful redis
                shipped by the Falco chart's sidekick-ui subchart.
              - prom 50Gi / grafana 5Gi / alertmanager 5Gi all iscsi.
StorageClass: iscsi (default, Retain); local-path (default, Retain).
```

Notable:

- **H-3 is live but wider than expected.** Falco chart 8.0.0 brought falcosidekick + the falcosidekick-ui web app + a Redis StatefulSet (1Gi PVC). The brief was "DaemonSet + custom-rules + ServiceMonitor" — the UI/Redis is upstream-default. Worth a quick audit: is the UI exposed (it's `ClusterIP` only), is Redis necessary at this scale, can we disable `falcosidekick.ui.enabled` to shrink the attack surface? Captured as F-2.
- **`modern_ebpf` driver loading is unverified.** The H-3 PR body called this out as a post-merge manual check; not yet done. Captured as F-3.
- **Falco custom-rules ConfigMap is unmounted.** Shipped in H-3 but not wired into the DS via `mounts.volumes` + `volumeMounts`. Captured as F-1.
- **Gatus scheduled snapshot didn't fire on 2026-05-28.** Schedule is `0 0 5 * * *` (05:00 UTC); current time should be past that. Only the hand-created test-backup-1 is present. Worth a single Prometheus check on next session — the `CNPGBackupStale` alert (36h threshold) will catch it if it persists.
- **O-9's runtime effects won't appear until Flux reconciles** to `56277b1`. The git side is correct; the cluster side will catch up on the next 10m tick.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

(No open CRITICAL items.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| F-1 | **Falco custom-rules ConfigMap not mounted** | 🟡 **NEW** (from H-3 deviation) | `_lib/controllers/falco/helmrelease.yaml`, `_lib/security/falco-rules/configmap-custom-rules.yaml` | Add `mounts.volumes` + `volumeMounts` to the HR pointing at `/etc/falco/rules.d`. Until then DaemonSet runs with falcoctl-managed `falco-rules` + `falco-incubating-rules` packs only. Half-hour task. |
| F-2 | **Audit falcosidekick UI + Redis surface** | 🟡 **NEW** | `_lib/controllers/falco/helmrelease.yaml` (falcosidekick.ui.* + falcosidekick.config.redis.*) | Falco chart shipped a UI web app + stateful Redis (1Gi iSCSI PVC) by default. Decide: keep (and wire HTTPRoute + auth), or disable `falcosidekick.ui.enabled` + `falcosidekick.config.redis.*` to shrink security-ns footprint. Quick task. |
| F-3 | **Verify Falco `modern_ebpf` driver loading** | ❓ **NEW** post-merge check | `kube dev -n security logs ds/security-falco-falcosecurity -c falco \| grep -i "ebpf"` | If logs show fallback to legacy eBPF or kmod on Talos, fix `driver.kind: modern_ebpf` config and reconcile. 5-min check. |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy is on. Consult [[cilium-gateway-egress-l7-filter]] before narrowing anything Gateway-routed. |
| ~~H-3~~ | ~~**Falco**~~ | ✅ Done 2026-05-28 (`eb197cf`) | — | 6 DS pods running, ServiceMonitor scraped, `crds: Skip`. Follow-ups in F-1/F-2/F-3. |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. Deprioritized below F-1/F-2/F-3. |
| O-5 / G2-2 | Cilium Gateway hardening + public-surface hardening | 🟡 Rate limit done; headers/WAF still open | exposed HTTPRoutes + public `dev-status.home-0ps.com` | Strip `Server`/`X-Powered-By`, body-size limits on the Gateway listeners; Cloudflare managed WAF rules on the public hostname. |

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
| O-5 | Gateway + public-surface hardening | 🟡 (rate-limit done; see HIGH above) | — | — |
| O-6 | Periodic posture scans | ❌ | — | `popeye` + `kubescape` CronJobs → Loki. |
| O-7 | Follow-up app alerts | 🟡 **Partially done** | `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml` | ✅ `CNPGBackupStale`, `CNPGDumpCronJobStale`. Still open: **cert expiry**, **PVC near-full**, **Gatus endpoint-down** via metrics. |
| O-8 | Default-deny CCNP (cluster-wide fail-closed) | 🟡 Per-app default-deny landed | — | Add cluster-wide default-deny for unlabeled namespaces (Q4). |
| ~~O-9~~ | ~~App-level dashboards/alerts~~ | ✅ Merged in dev 2026-05-28 (`e08f08a`); Flux pending | `_lib/observability/kube-prometheus-stack/{servicemonitor-authentik.yaml, dashboards/}` | Verify post-reconcile: 4 dashboards in Grafana, authentik scrape targets up. Watch this slot for "applied revision" advancing past `6f51280`. |
| O-10 | **App-data dashboards in Grafana** (postgres-exporter) | ❌ Open | `_lib/observability/` (postgres-exporter HR or per-CNPG sidecar) | 3 CNPG clusters now (authentik/freshrss/gatus); postgres-exporter pattern should be shared. Watch [[cilium-gateway-egress-l7-filter]] — exporters need explicit CCNP egress to the target CNPG on 5432. |
| ~~O-11~~ | ~~Gatus endpoint statuses in repo README~~ | ✅ Done 2026-05-28 (`6f51280`) | `README.md` | Hybrid badge format (shields.io endpoint for Status, direct Gatus SVG for Uptime 7d). 6 endpoints surfaced. Stale Syncthing row removed. |
| ~~O-12~~ | ~~PR CI lacks PromQL alert-template validation~~ | ✅ Done 2026-05-29; awaiting first CI run | `.github/workflows/lint.yml` + `_lib/observability/kube-prometheus-stack/prometheusrule-*.yaml` | Sprig functions (`mul`, `div`, `add`, `default`, etc.) parse-pass YAML lint + CRD schema but fail at the Prometheus Operator's mutating webhook — alert templates use Go `text/template` + Prometheus extensions only. Example: PVCNearFull's `(mul $value 100)` shipped via O-7 (PR #50) and only surfaced when Flux re-applied during the 2026-05-29 kromgo reconcile (`11f008e`); fix landed in `8a7a6f7`. New `.github/workflows/lint.yml` runs yamllint + `promtool check rules` (extracted via `yq 'select(.kind == "PrometheusRule") | .spec'`) on every PR + push to `dev` — same class of bug now caught pre-merge. |
| ~~O-13~~ | ~~Flux controllers had never been scraped~~ | ✅ Done 2026-05-29 (`56df0f2`) — verified `up=1` × 4 controllers via PromQL | `_lib/observability/kube-prometheus-stack/podmonitor-flux.yaml` (was `servicemonitor-flux.yaml`) | Pre-existing latent bug surfaced while verifying kromgo: `flux_version` returned "No Data" because the flux ServiceMonitor had three independent defects — (1) selector `app:<name>` instead of `app.kubernetes.io/component:<name>`, (2) listed `helm-controller` + `kustomize-controller` (neither has a matching Service), (3) hit `http-prom` but the Services only expose `http`. Result: zero `gotk_*`/`flux_*` series cluster-wide. Replaced with a PodMonitor scraping all four controllers directly on container port `http-prom:8080`. Verifies that `FluxKustomizationNotReady`/`FluxHelmReleaseNotReady` alerts (shipped via O-7) had nothing to fire against — should now go live. |
| O-14 | Adapt third-party reference configs to local conventions | ❌ Open | `_lib/observability/kromgo/config/config.yaml` (initial example) | Both O-12 (bjw-s alert template Sprig-isms) and the kromgo "no data" issues (verbatim-copied `{kubernetes_node!=""}` selector) stem from importing reference configs without auditing label conventions. Next time we adopt a community config (rules, dashboards, scrape configs), spot-check label vocabularies against this cluster's actual series before merge. Could be a CLAUDE.md rule under `.claude/rules/`. |
| O-15 | `flux_version` kromgo badge stuck at "No Data" — KSM label allowlist needed | ❌ Open | `_lib/observability/kube-prometheus-stack/helmrelease.yaml` (KSM values) + `_lib/observability/kromgo/config/config.yaml` (`flux_version` query) | The kromgo PromQL `flux_instance_info` is a bjw-s artifact emitted by the optional flux-operator addon — not part of vanilla Flux 2.x. Vanilla Flux only emits operational metrics (`gotk_reconcile_duration_*`, `gotk_event_*`). Tomorrow: (1) add `kube-state-metrics.metricLabelsAllowlist: ["pods=[app.kubernetes.io/version,app.kubernetes.io/part-of,app.kubernetes.io/component]"]` to the kps HelmRelease — exposes `kube_pod_labels` with the `label_app_kubernetes_io_version` label, broad value for every workload not just Flux. (2) Rewrite the kromgo query: `label_replace(max by (label_app_kubernetes_io_version) (kube_pod_labels{namespace="flux-system",label_app_kubernetes_io_part_of="flux"}), "revision", "$1", "label_app_kubernetes_io_version", "v(.+)")`. Returns the suite version (`2.8.8`) not the source-controller image tag (`1.8.5`). Alternative considered: `kube_pod_container_info` image-tag parse — rejected, shows the wrong version number. Estimated 15min change + verify. |
| O-16 | Kromgo ConfigMap edits silently no-op until pod restart | ✅ Done 2026-05-29 (`b5e71cb`) | `_lib/observability/kromgo/kustomization.yaml` (configMapGenerator) | Kromgo reads `/kromgo/config.yaml` once at startup; no SIGHUP, no file-watcher. Static ConfigMap edits propagate to the pod's mount in ~60s but the running process never re-reads. Discovered while verifying `cf2558c` — Flux applied the fix but the metric endpoints kept returning the old "no data". Moved config to `config/config.yaml` and switched to a kustomize `configMapGenerator` with the default name-suffix hash; any edit produces a new ConfigMap name (e.g. `kromgo-config-t5ftc67d22`) and kustomize rewrites the Deployment's volume reference to match, forcing a rollout. No Stakater Reloader needed. Applies the same pattern when other apps add ConfigMap-driven runtime config. |

### Homer follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |

### Storage migration (S-tier — **COMPLETE**)

> ADR-0003 implemented end-to-end (commits `328148f` → `d5c5ca2`, 2026-05-26 evening).

| ID | Item | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~S-1~~ | ~~Snapshot infrastructure~~ | ✅ | — |
| ~~S-2~~ | ~~CNPG → static iSCSI + scheduled snapshots~~ | ✅ | 3 CNPG clusters total (authentik/freshrss/gatus). |
| ~~S-3~~ | ~~Retire R2/S3 from CNPG path~~ | ✅ | — |
| ~~S-4~~ | ~~iscsi StorageClass reclaim default~~ | ✅ | — |
| ~~S-5~~ | ~~No CNPG backups~~ | ✅ | — |
| ~~S-6~~ | ~~Last-resort pg_dump rip cord~~ | ✅ | + drill log 2026-05-28. |

### Sprint orchestrator (NEW — 2026-05-28)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| SO-1 | `/sprint-orchestrate` parallel sprint executor | ✅ Done (`e750b7a`) | `.claude/commands/sprint-orchestrate.md` + `.claude/sprints/_template/accept.sh` + `.github/workflows/sprint-accept.yml` | Drove H-3, O-9, O-11 today. Stress-tested by 2 mishaps (subagent session limit mid-O-9; PR #46+#47 merge clobber). Both recovered. |
| SO-2 | First-run polish | 🟡 Open | `.claude/commands/sprint-orchestrate.md` | Document the session-limit-mid-task recovery pattern (subagent leaves uncommitted work in worktree; orchestrator inspects + commits + rebases). Also document the cherry-pick recovery path for clobbered merges. Half-hour task. |
| SO-3 | Sprint-state.json schema versioning | 🟡 Open | `.claude/sprint-state.json` (gitignored) | Add a `"schema_version"` field; bump on future schema changes so resume can detect stale formats. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |
| Pre-existing `.claude/rules/` + `.claude/settings.json` edits | (working tree, now committed earlier 2026-05-28) | ✅ Folded into `ca9da94 nice` + `da613bb intervals for helmreleases spaced out`. |
| Sprint orchestrator follow-up rules | `.claude/rules/git-pull-before-commit.md` (NEW, `56277b1`) | Document repeats of the merge-clobber pattern if they recur; current rule is sufficient. |

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
| Falco `modern_ebpf` post-merge verify (F-3) | ❓ Pending | See F-3 above. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — ✅ Descoped (ADR-0005). No change.

**docs-site** — 🗑️ Retired 2026-05-26. No change.

**Gatus** — ✅ Live + hardened + persistent (G0+G1+G2 + N-1..N-5 + N-6). Now also surfaced in repo `README.md` via O-11.

**Cloudflare Tunnel** — ✅ Live (G0) + rate-limited.

**GPU sharing** — pre-decision (ADR-0004) unchanged.

**Falco** — ✅ Live (H-3) — wider footprint than brief expected (sidekick UI + Redis). See F-2.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **F-1 + F-2 + F-3 — Falco follow-ups** (half-day bundle). Mount the custom-rules ConfigMap into the DS, decide on falcosidekick UI/Redis (likely disable to shrink surface), verify `modern_ebpf` loaded on Talos workers. Single PR, ~30 min each. Natural cut point.
2. **O-7 remaining alerts** — cert expiry, PVC near-full, Gatus endpoint-down via metrics. Half-day task on `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml`. Pairs well with the post-O-9 reconcile (verify dashboards + scrape, then add the alerts).
3. **O-10 postgres-exporter** — three CNPG clusters now (authentik/freshrss/gatus); shared exporter HR pattern. Mind [[cilium-gateway-egress-l7-filter]] for the CCNPs. Multi-day if you want custom queries (freshrss unread/favorites, authentik login stats, gatus history).
4. **SO-2 + SO-3 sprint-orchestrator polish** — document the session-limit-mid-task recovery + the cherry-pick recovery for clobbered merges + state-file schema versioning. Quick.
5. **H-5 Trivy** — populate the empty `_lib/security/trivy/` HR, wire reports.
6. **I-1 Talos unpin + R5 memory typo + R1/R2 verify** — small Terraform housekeeping batch.
7. **O-5/O-6 + WAF managed rules** — gateway header stripping + posture scans + Cloudflare WAF on public hostname.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `_lib/controllers/falco/helmrelease.yaml` | H-3 — chart 8.0.0, `install/upgrade.crds: Skip`, `driver.kind: modern_ebpf`, `metrics.enabled: true`. F-1 needs `mounts.volumes`; F-2 may flip `falcosidekick.ui.*` off. |
| `_lib/security/falco-rules/configmap-custom-rules.yaml` | H-3 — custom-rules ConfigMap shipped, currently unmounted (F-1). |
| `_lib/observability/kube-prometheus-stack/servicemonitor-falco.yaml` | H-3 — centralised SM ownership pattern (also used by O-9 for authentik). |
| `_lib/controllers/authentik/helmrelease.yaml` | O-9 — server + worker `metrics.enabled: true`; chart-side SM stays off. |
| `_lib/observability/kube-prometheus-stack/servicemonitor-authentik.yaml` | O-9 — cross-namespace SM via `matchExpressions` covering both server + worker metrics services. |
| `_lib/observability/kube-prometheus-stack/dashboards/` | O-9 — 4 dashboard ConfigMaps (authentik/cloudflared community, gatus/freshrss handwritten). |
| `.yamllint.yaml` | O-9 — community dashboard YAMLs (authentik, cloudflared) added to ignore list (embedded markdown > 300-char line cap). |
| `README.md` | O-11 — `## Live status` block with shields.io endpoint + Gatus SVG badges; Syncthing row removed. |
| `.claude/commands/sprint-orchestrate.md` | SO-1 — orchestrator command spec. |
| `.claude/sprints/_template/accept.sh` | SO-1 — per-task acceptance test template (yq bootstrap pattern proven through 3 sprints). |
| `.github/workflows/sprint-accept.yml` | SO-1 — CI gate: runs `.claude/sprints/<id>/accept.sh` on `sprint/*` PRs. |
| `.claude/commands/sprint-menu.md` | SO-1 — picker now suggests `/sprint-orchestrate <ids>` for ≥2 independent task bundles. |
| `.claude/rules/git-pull-before-commit.md` | NEW (`56277b1`) — pull `--ff-only` before commits on shared branches; cites the 2026-05-28 merge-clobber incident as the *why*. |
| `_docs/guides/cnpg-rescue.md` | Drill log 2026-05-28 — both rip cords validated, 6 gotchas memorialized. |
| `_docs/reviews/home-0ps-review-2026-05-27.md` | Prior baseline. Carried-forward items keep their IDs. |
