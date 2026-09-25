# Bake Sysmon + a config into the Windows template at BUILD time (build network has
# egress; detonation hosts do not). Installs the service so every clone ships with
# Sysmon already logging to Microsoft-Windows-Sysmon/Operational. Phase 3 (Wazuh)
# forwards that channel. Runs over WinRM as Administrator.
$ErrorActionPreference = 'Stop'

$labDir = 'C:\ProgramData\lab\Sysmon'
New-Item -ItemType Directory -Force -Path $labDir | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile "$labDir\Sysmon.zip" -UseBasicParsing
Expand-Archive -Path "$labDir\Sysmon.zip" -DestinationPath $labDir -Force
Invoke-WebRequest -Uri $env:SYSMON_CONFIG_URL -OutFile "$labDir\sysmonconfig.xml" -UseBasicParsing

# Install the driver + service with the config. Idempotent-ish: skip if present.
$exe = Join-Path $labDir 'Sysmon64.exe'
if (Get-Service -Name 'Sysmon64' -ErrorAction SilentlyContinue) {
  & $exe -c "$labDir\sysmonconfig.xml"
} else {
  & $exe -accepteula -i "$labDir\sysmonconfig.xml"
}
Set-Service -Name 'Sysmon64' -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host 'Sysmon installed and running.'
