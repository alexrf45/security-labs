# Archive — Proxmox / on-prem era

These documents describe the **previous** incarnations of this repo and are kept for
historical reference only. **They do not describe the current cloud-native range** and
should not be treated as live context.

Two eras are archived here:

- **Home-ops Kubernetes lab** — the `reviews/home-0ps-review-*.md` series (2026-04 →
  2026-06) tracked a 6-node Talos/Flux GitOps cluster (`memphis`/`dev`), later spun
  down. Useful for the network/SDN reasoning (EVPN failures on the UCG hardware) that
  informed later decisions.
- **Proxmox security range** — `runbooks/security-lab-*.md` documented the
  hypervisor-based range (Proxmox SDN VLAN zones, structural air-gap, node-local
  disks, Packer golden images). It was built in-repo and `validate`-clean but **never
  deployed** before the cloud pivot.

## Why kept, not deleted

The design reasoning is reusable: the structural air-gap concept, the one-way
telemetry model, the state-split-by-blast-radius pattern, and the AD-detection
scenario shape all carry forward to the cloud range. The **live** design lives in:

- `_docs/decisions/0009-security-lab-segmentation.md` — Proxmox segmentation ADR
  (**Superseded by ADR-0010**; kept in `decisions/` to preserve the numbered chain).
- `_docs/decisions/0010-cloud-native-pivot.md` — the pivot record.
- `.claude/rules/range-safety.md` — the cloud-native successor to the old
  `lab-isolation.md` invariants.

When in doubt, prefer the current ADRs and rules over anything in this archive.
