# 本地无感升级：启动新后端 -> 切换 devproxy -> 排空旧后端
# 用法（PowerShell，在 deploy 目录）：
#   .\upgrade-dev.ps1
#   .\upgrade-dev.ps1 -NewVersion "0.2.0"

param(
    [string]$NewVersion = ""
)

$ErrorActionPreference = "Stop"
$DeployDir = $PSScriptRoot
$BackendDir = Join-Path $DeployDir "..\backend"
$ActiveFile = Join-Path $DeployDir ".active-backend-port"
$PidFile = Join-Path $DeployDir ".backend.pid"
$EnvFile = Join-Path $DeployDir ".env"

function Read-DotEnvPort {
    param([string]$Key, [string]$Default)
    if (-not (Test-Path $EnvFile)) { return $Default }
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match "^\s*$Key\s*=\s*(.+)\s*$") {
            return $Matches[1].Trim()
        }
    }
    return $Default
}

$portA = Read-DotEnvPort "BACKEND_PORT_A" "8081"
$portB = Read-DotEnvPort "BACKEND_PORT_B" "8082"
$adminSecret = Read-DotEnvPort "ADMIN_SECRET" ""

$current = $portA
if (Test-Path $ActiveFile) {
    $current = (Get-Content $ActiveFile -Raw).Trim()
}
$next = if ($current -eq $portA) { $portB } else { $portA }

Write-Host "Current active backend port: $current"
Write-Host "Starting new backend on port: $next"

$env:SERVER_PORT = $next
if ($NewVersion) { $env:SERVER_VERSION = $NewVersion }
$env:ENV_FILE = $EnvFile

Push-Location $BackendDir
$proc = Start-Process -FilePath "go" -ArgumentList "run", "./cmd/server" -PassThru -NoNewWindow
Pop-Location

Start-Sleep -Seconds 2
$healthUrl = "http://127.0.0.1:$next/api/health"
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        if ($resp.ok) { $ok = $true; break }
    } catch {}
    Start-Sleep -Seconds 1
}
if (-not $ok) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    throw "New backend on port $next did not become healthy"
}

Set-Content -Path $ActiveFile -Value $next -NoNewline
Set-Content -Path $PidFile -Value $proc.Id -NoNewline
Write-Host "devproxy active port -> $next (pid $($proc.Id))"

if ($current -ne $next -and $adminSecret) {
    $drainUrl = "http://127.0.0.1:$current/api/admin/drain"
    try {
        Invoke-RestMethod -Uri $drainUrl -Method Post -Headers @{ Authorization = "Bearer $adminSecret" } | Out-Null
        Write-Host "Requested drain on old backend :$current"
    } catch {
        Write-Host "Could not drain old backend (may already be stopped): $_"
    }
}

Write-Host "Upgrade complete. Clients on PUBLIC_PORT (8080 via devproxy) stay connected to $next."
