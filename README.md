<div align="center">

<img width="1584" height="396" alt="Copy of Th0thv5" src="https://github.com/user-attachments/assets/4869f42b-36d3-4cc1-9cee-ba245ec05d28" />





</div>

<br>



`Th0th` is a **cloud-native cyber range** built using infrastructure as code (IaC). It exists to practice offensive **and** defensive techniques, develop
custom tooling and detections for Linux and Windows, and to study CVEs & malware safely.
Scenarios are automated as much as possible for repeatable, consistent learning — and the whole range runs on a hobby budget (**≤ $30/month**), reachable only over **Tailscale**.

> **🚧 Pivot in progress.** Th0th is moving from a self-hosted Proxmox range to a **cloud-native** one ([ADR-0010](_docs/decisions/0010-cloud-native-pivot.md)). The Claude Code harness and docs have been reoriented; the cloud `_infra/` (Terraform/images) is being rebuilt. Provider & topology are the next decision ([ADR-0011](_docs/README.md), pending). See **[`_docs/README.md`](_docs/README.md)** to follow along.

<div align="center">

## Example Use Cases

| Domain | Tooling |
| ------ | ------------ |
| 🔴 **Offensive** | An attacker box (SSH/RDP/VNC over Tailscale) + a local Nix env; payload & tool development within isolated, egress-denied networks. |
| 🔵 **Defensive** | Detection engineering: host telemetry shipped one-way to a collector/SIEM on the ops tier. |
| 🐛 **CVE testing** | Ephemeral, reproducible environments — spun up per session and torn down to stay under budget. |
| 💸 **Cost-aware** | Hard $30/month ceiling with `infracost` gating and budget alarms baked into the design. |


</div>

## ⚠️ Disclaimer

*This repository contains infrastructure as code (IaC) and configurations for an isolated malware analysis and penetration testing lab. These files are intended for educational and research purposes only.*
