#!/usr/bin/env bash
# Convert the Debian 12 base into Kali rolling, install the attacker toolset, the
# qemu guest agent, then generalize for cloning. Runs as root (sudo) from Packer.
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# ── Add the Kali rolling repository + signing keyring ────────────────────────
wget -q https://archive.kali.org/archive-keyring.gpg -O /usr/share/keyrings/kali-archive-keyring.gpg
cat > /etc/apt/sources.list.d/kali.list <<'EOF'
deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
EOF
# Replace the Debian suite so we fully track kali-rolling.
rm -f /etc/apt/sources.list
: > /etc/apt/sources.list

apt-get update

# ── Toolset: headless metapackage (CLI). Swap to kali-linux-default for the GUI/
#    full toolset, or kali-linux-everything for all of it (large). ─────────────
apt-get install -y --no-install-recommends kali-linux-headless qemu-guest-agent
systemctl enable qemu-guest-agent || true

# ── Generalize for cloning ───────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /etc/ssh/ssh_host_*          # regenerated on first boot
truncate -s 0 /etc/machine-id
cloud-init clean --logs --seed 2>/dev/null || true
rm -f /root/.bash_history /home/packer/.bash_history || true
