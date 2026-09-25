# Installs + configures cloudbase-init so cloned VMs consume the Proxmox cloud-init
# drive on first boot: sets hostname/IP/DNS and runs the per-host first-boot
# PowerShell (DC promotion, domain join, Sysmon) that scenario-vm delivers as
# user-data. Installed but NOT run during the build (no config drive present), so
# it activates on the clone's first boot. Runs over WinRM as Administrator.
$ErrorActionPreference = 'Stop'

$msi = Join-Path $env:TEMP 'cloudbase-init.msi'
Invoke-WebRequest -Uri 'https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi' -OutFile $msi -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart RUN_SERVICE_AS_LOCAL_SYSTEM=1" -Wait

$confDir = Join-Path ${env:ProgramFiles} 'Cloudbase Solutions\Cloudbase-Init\conf'

# ConfigDrive (Proxmox cloud-init drive) + the plugins we need. UserDataPlugin runs
# the per-host first-boot script; allow_reboot lets a hostname change reboot once.
$conf = @'
[DEFAULT]
username=Administrator
groups=Administrators
inject_user_password=true
config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin,cloudbaseinit.plugins.common.localscripts.LocalScriptsPlugin
allow_reboot=true
stop_service_on_exit=false
check_latest_version=false
logdir=C:\CloudbaseInit\Logs\
logfile=cloudbase-init.log
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
'@

Set-Content -Path (Join-Path $confDir 'cloudbase-init.conf') -Value $conf -Encoding Ascii
Copy-Item (Join-Path $confDir 'cloudbase-init.conf') (Join-Path $confDir 'cloudbase-init-unattend.conf') -Force

# Service runs on next boot (the clone's first boot), not now.
Set-Service -Name 'cloudbase-init' -StartupType Automatic
Write-Host 'cloudbase-init installed; will run on first boot of a clone.'
