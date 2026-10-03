<div align="center">

<img width="1584" height="396" alt="Copy of Th0thv5" src="https://github.com/user-attachments/assets/4869f42b-36d3-4cc1-9cee-ba245ec05d28" />

</div>

<br>

`Th0th` is a **cloud-native cyber range** built using infrastructure as code (IaC). It exists to practice offensive **and** defensive techniques, develop
custom tooling and detections for Linux and Windows, and to study CVEs & malware safely.
Scenarios are automated as much as possible for repeatable, consistent learning — and the whole range runs on a hobby budget (**≤ $30/month**), reachable only over **Tailscale**.

**AWS · Terraform · Tailscale · 1Password · Wazuh**

<div align="center">

## Example Use Cases

| Domain | Tooling |
| ------ | ------------ |
| 🔴 **Offensive** | An attacker box (SSH/RDP/VNC over Tailscale) + a local Nix env; payload & tool development within isolated, egress-denied networks. |
| 🔵 **Defensive** | Detection engineering: host telemetry shipped one-way to a collector/SIEM on the ops tier. |
| 🐛 **CVE testing** | Ephemeral, reproducible environments — spun up per session and torn down to stay under budget. |
| 💸 **Cost-aware** | Hard $30/month ceiling with `infracost` gating and budget alarms baked into the design. |


</div>

## Documentation

**[Start here](_docs/README.md)** · [Deploy](_docs/runbooks/aws-range-deployment.md) · [Troubleshoot](_docs/runbooks/aws-range-troubleshooting.md) · [Reference](_docs/reference/aws-range-reference.md) · [Decisions](_docs/decisions/)

## Disclaimer

*This repository contains infrastructure as code (IaC) and configurations for an isolated malware analysis and penetration testing lab. These files are intended for educational and research purposes only.*
