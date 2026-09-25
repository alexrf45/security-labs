# Shared post-setup provisioner for every Windows template. Installs the QEMU
# guest agent + virtio drivers (NetKVM, vioscsi, balloon...) from the mounted
# virtio-win ISO, so the cloned VM reports its IP to Proxmox and supports virtio
# devices. Runs over WinRM as Administrator.
$ErrorActionPreference = 'Stop'

# Locate the virtio-win CD by volume label (PROVISION is the autounattend CD).
$virtio = (Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and (Test-Path "$($_.DriveLetter):\virtio-win-gt-x64.msi") } | Select-Object -First 1)
if (-not $virtio) {
  $virtio = (Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and (Test-Path "$($_.DriveLetter):\guest-agent") } | Select-Object -First 1)
}
if (-not $virtio) {
  Write-Warning 'virtio-win ISO not found on any CD-ROM; skipping guest tools install.'
  return
}
$d = "$($virtio.DriveLetter):"
Write-Host "virtio-win media at $d"

# QEMU guest agent (reports IP to Proxmox; required by scenario-vm/qemu_agent).
$qga = Join-Path $d 'guest-agent\qemu-ga-x86_64.msi'
if (Test-Path $qga) {
  Start-Process msiexec.exe -ArgumentList "/i `"$qga`" /qn /norestart" -Wait
  Set-Service -Name 'QEMU-GA' -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
}

# virtio driver bundle (NetKVM, vioscsi, balloon, etc.) so virtio NIC/disk work
# when scenario-vm clones this template with virtio devices.
$gt = Join-Path $d 'virtio-win-guest-tools.exe'
if (Test-Path $gt) {
  Start-Process $gt -ArgumentList '/install /quiet /norestart' -Wait
} else {
  $msi = Join-Path $d 'virtio-win-gt-x64.msi'
  if (Test-Path $msi) { Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait }
}

Write-Host 'Guest tools installed.'
