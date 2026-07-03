# 生产 release APK — domestic / global flavor
# 用法（PowerShell，在 mobile 目录或任意目录）：
#   .\scripts\build-release.ps1
#   .\scripts\build-release.ps1 -Flavor domestic
#   .\scripts\build-release.ps1 -ApiBase "https://im.example.com"
#   .\scripts\build-release.ps1 -ConfigFile config/prod.json
#
# 首次：copy config\prod.json.example config\prod.json 并改 API_BASE

param(
    [ValidateSet("domestic", "global", "both")]
    [string]$Flavor = "both",
    [string]$ApiBase = "",
    [string]$ConfigFile = "config/prod.json"
)

$ErrorActionPreference = "Stop"
$MobileDir = Split-Path $PSScriptRoot -Parent
Set-Location $MobileDir

$configPath = Join-Path $MobileDir ($ConfigFile -replace '/', '\')
if (-not (Test-Path $configPath)) {
    $example = Join-Path $MobileDir "config\prod.json.example"
    throw "Missing $ConfigFile — copy prod.json.example and set API_BASE, e.g.: copy config\prod.json.example config\prod.json"
}

function Build-ReleaseApk {
    param([string]$MarketFlavor)

    $flavorConfig = Join-Path $MobileDir "config\$MarketFlavor.json"
    if (-not (Test-Path $flavorConfig)) {
        throw "Missing flavor config: config\$MarketFlavor.json"
    }

    $args = @(
        "build", "apk", "--release",
        "--flavor", $MarketFlavor,
        "--dart-define-from-file=$ConfigFile",
        "--dart-define-from-file=config/$MarketFlavor.json"
    )
    if ($ApiBase) {
        $args += "--dart-define=API_BASE=$ApiBase"
    }

    Write-Host "Building release APK ($MarketFlavor) ..."
    & flutter @args
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed for $MarketFlavor" }

    $outDir = Join-Path $MobileDir "build\app\outputs\flutter-apk"
    $apk = Get-ChildItem -Path $outDir -Filter "app-$MarketFlavor-release.apk" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($apk) {
        Write-Host "Output: $($apk.FullName)"
    }
}

$flavors = if ($Flavor -eq "both") { @("domestic", "global") } else { @($Flavor) }
foreach ($f in $flavors) {
    Build-ReleaseApk -MarketFlavor $f
}

Write-Host "Done."
