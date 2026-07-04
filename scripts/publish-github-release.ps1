# 将已构建的 domestic release APK 上传到 GitHub Release（需 gh CLI 或 GITHUB_TOKEN）。
# 用法：
#   .\scripts\publish-github-release.ps1 -Tag v2026-07-04-moses
#   $env:GITHUB_TOKEN = "ghp_..." ; .\scripts\publish-github-release.ps1 -Tag v2026-07-04-moses

param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,
    [string]$ApkPath = "mobile\build\app\outputs\flutter-apk\app-domestic-release.apk",
    [string]$Repo = "keller-cc/ihope"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$apk = Join-Path $root ($ApkPath -replace '/', '\')
if (-not (Test-Path $apk)) {
    throw "APK not found: $apk — run mobile\scripts\build-release.ps1 first"
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    gh release create $Tag $apk `
        --repo $Repo `
        --title "IHope $Tag" `
        --generate-notes
    Write-Host "Release published: https://github.com/$Repo/releases/tag/$Tag"
    exit 0
}

if (-not $env:GITHUB_TOKEN) {
    throw "Install GitHub CLI (gh) or set GITHUB_TOKEN to publish releases"
}

$headers = @{
    Authorization = "Bearer $($env:GITHUB_TOKEN)"
    Accept        = "application/vnd.github+json"
}
$base = "https://api.github.com/repos/$Repo"
$releaseBody = @{
    tag_name   = $Tag
    name       = "IHope $Tag"
    draft      = $false
    generate_release_notes = $true
} | ConvertTo-Json

$release = Invoke-RestMethod -Method Post -Uri "$base/releases" -Headers $headers -Body $releaseBody -ContentType "application/json"
$uploadUrl = $release.upload_url -replace '\{.*$', ''
$fileName = Split-Path $apk -Leaf
$uploadHeaders = @{
    Authorization = "Bearer $($env:GITHUB_TOKEN)"
    Accept        = "application/vnd.github+json"
    "Content-Type" = "application/vnd.android.package-archive"
}
Invoke-RestMethod -Method Post -Uri "${uploadUrl}?name=$fileName" -Headers $uploadHeaders -InFile $apk
Write-Host "Release published: $($release.html_url)"
